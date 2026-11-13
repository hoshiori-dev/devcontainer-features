## What it does

Installs the libvirt client tools from the distribution (`virsh`, and by default `virt-install` with `virt-clone` and
`virt-xml`) and prepares the dev container to manage **the host's virtual machines**: the tools talk to the libvirt
daemon that runs on the host, through the host's `/run/libvirt` directory, which you mount into the container. No
libvirt daemon and no QEMU is installed in the container. To run virtual machines inside the dev container instead, use
[libvirt-in-docker](../libvirt-in-docker/README.md); the two are alternatives, and installing both fails the build.

The full behavior is specified in
[openspec/specs/libvirt-outside-of-docker/spec.md](../../openspec/specs/libvirt-outside-of-docker/spec.md).

## Add the mount

The feature declares no mount, so a container with it also starts on a machine without libvirt. Add this to your
`devcontainer.json`:

```json
"mounts": ["source=/run/libvirt,target=/run/libvirt,type=bind,readonly"]
```

Keep the target path as it is: the client finds the sockets of both daemon layouts (`libvirtd`, or the modular
`virtqemud`) there by itself. `readonly` keeps the container from creating or removing anything in the host's directory;
connecting to a socket works through a read-only mount.

**This mount gives the container control of the host's libvirt daemon, which amounts to root on the host**: the daemon
attaches any host file or device to a virtual machine on request. The read-only flag does not limit this. Add the mount
only to a dev container whose users you would trust with root on the host.

## What happens at every start

- `LIBVIRT_DEFAULT_URI` is `qemu:///system` for every process, so `virsh list --all` and `virt-install` reach the host's
  system daemon without `--connect`. To use another connection, such as `qemu+ssh://user@server/system`, set the
  variable in `remoteEnv` of `devcontainer.json`; with the dev container CLI, a value in `containerEnv` does not reach
  the remote user's processes.
- The feature's entrypoint, `/usr/local/share/libvirt-outside-of-docker/align_group.sh`, looks at the mounted socket and
  adds the remote user to a group of the container that has the socket's group ID. When no group has it, the group
  `libvirt-host` gets it. If a group of the container already has that ID, the remote user joins that group and also
  gets what the group grants inside the container. The socket and everything else under `/run/libvirt` are never
  changed. Nothing is done for a socket that every user may write to, or one that belongs to the root group: there the
  host decides who may connect by other means.
- The outcome is recorded in `/run/libvirt-outside-of-docker/status`.
- The feature's `postStartCommand`, `/usr/local/share/libvirt-outside-of-docker/check.sh`, reports the connection. With
  no socket mounted it prints the mount above and exits zero. With a socket it runs
  `virsh --connect qemu:///system version` and fails, with the daemon's error and the recorded outcome, when the
  connection is refused. Run it again by hand at any time; it changes nothing.

The group is aligned at container start only: after libvirt is installed or reconfigured on the host, restart the
container.

## Host requirements

- Linux, with a Docker daemon that runs as root on the same machine as the libvirt daemon. Docker Desktop, rootless
  Docker, and Podman are not supported: there the host's `/run/libvirt`, or the identity the daemon sees, does not reach
  the container.
- The numeric user ID of the container's user must belong to a user of the host. The host's daemon looks the ID up and
  refuses one it does not know ("Failed to find user record for uid"). Where the host authorizes its socket through
  polkit (a socket every user may write to), polkit decides by that same ID.
- A host that confines containers with SELinux must have that confinement lifted for the socket by you; the feature
  requests no security option.

## Limits

- Paths in a virtual machine's definition are paths **on the host**, not in the container. A disk image at
  `/workspaces/project/disk.qcow2` means that path on the host. Use a storage pool with `virsh vol-upload`, or mount the
  workspace at the same path as on the host.
- Only the host's system daemon (`qemu:///system`) is reached, not a user's session daemon (`qemu:///session`).
- Graphical consoles (VNC, SPICE) listen on the host and are not reachable through the mount; `virsh console` is.

## How this feature is tested

The repository's CI has no libvirt daemon on the machine that runs the test containers, so CI covers the install, the
second install, the group alignment (against a socket file the test makes), and the start check without a daemon. It
does **not** cover a connection to a real daemon.

That connection was tested once, by hand, on 2026-11-13, with dev container CLI 0.89.0 on an amd64 Docker 29.9 daemon.
The stand-in for a host was a second container running the distribution's libvirt daemon, with its `/run/libvirt` kept
in a directory that the feature's container (Ubuntu 24.04, remote user `vscode`) mounted as described above:

| Daemon                                                          | Result                                                                                                                                               |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Debian 13, `libvirtd` 11.3, socket owned by a group             | Connected, read-only and writable mount; the socket's group ID was already a group of the container, which the user joined; host directory unchanged |
| Fedora 44, modular daemons 12.0, socket owned by a group        | Connected through `virtqemud-sock` as a member of `libvirt-host`; a virtual machine defined and started from the container ran on the daemon's side  |
| Debian 13, `libvirtd` 11.3, distribution default (polkit)       | Refused, as expected without a polkit rule for the user; the start check failed with the daemon's error                                              |
| Either daemon, no user with the container user's ID on its side | Refused ("Failed to find user record for uid"); connected once such a user existed                                                                   |
| Debian 13, `LIBVIRT_DEFAULT_URI` set in `remoteEnv`             | `virsh` used the developer's URI                                                                                                                     |

Not tested: a libvirt daemon installed directly on a host, a host whose polkit rules admit the user, SELinux, and arm64
hosts.

## OS support

See [test/libvirt-outside-of-docker/compatibility.json](../../test/libvirt-outside-of-docker/compatibility.json).
