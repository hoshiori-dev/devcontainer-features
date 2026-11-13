## What it does

Installs the distribution's libvirt daemon, QEMU for the container's architecture, UEFI firmware, `virsh`,
`virt-install`, and `qemu-img`, and starts the daemon at every container start, so you run **virtual machines inside the
dev container**. To manage the host's virtual machines instead, use
[libvirt-outside-of-docker](../libvirt-outside-of-docker/README.md); the two are alternatives, and installing both fails
the build.

The full behavior is specified in
[openspec/specs/libvirt-in-docker/spec.md](../../openspec/specs/libvirt-in-docker/spec.md).

```sh
virt-install --name demo --memory 2048 --vcpus 2 --disk size=10 --cdrom /workspaces/project/installer.iso \
  --osinfo detect=on,require=off --graphics vnc
virsh list --all
```

## Security

- **The container is privileged.** Guests need `/dev/kvm` and tap devices, and the default network needs a bridge and
  packet filter rules; a feature cannot request single devices. A privileged container can take over its host.
- **Membership in the `libvirt` group amounts to root in the container and on its host.** The feature adds the remote
  user to that group, and the daemon's sockets belong to it without further authentication, because the distributions'
  polkit authorization cannot work in a container that runs no polkit. The daemon runs QEMU as root.
- **Guests are not confined against the container**, and per-guest limits through cgroups (CPU shares, memory limits)
  have no effect: a container cannot load AppArmor profiles or SELinux labels for its guests and has no systemd to give
  each guest a cgroup.

Use this feature only for dev containers whose users you would trust with root on the host.

## What happens at every start

- The feature's entrypoint, `/usr/local/share/libvirt-in-docker/start.sh`, starts `virtlogd` and the daemons the
  distribution ships: `libvirtd` on Debian and Ubuntu, the modular daemons (`virtqemud`, `virtnetworkd`, `virtstoraged`,
  `virtnodedevd`, `virtsecretd`, `virtnwfilterd`) on Fedora. It first removes the runtime state an earlier start of the
  container left under `/run`.
- With `defaultNetwork` `true` (the default) it starts libvirt's `default` network: NAT on the bridge `virbr0`,
  `192.168.122.0/24`. With `false` the network stays defined and you start it with `virsh net-start default`.
- `LIBVIRT_DEFAULT_URI` is `qemu:///system` for every process, so `virsh` and `virt-install` reach the daemon without
  `--connect`. Only this system daemon is set up, not a per-user session daemon (`qemu:///session`).
- The outcome is recorded in `/run/libvirt-in-docker/status`: the result, whether KVM is available, and the state of the
  default network.
- The feature's `postStartCommand`, `/usr/local/share/libvirt-in-docker/check.sh`, reads that record, connects as the
  remote user, and fails with the reason when the daemons do not run. The daemons' logs are in `/var/log/libvirt`.

The daemons are not supervised. If one stops, run `sudo /usr/local/share/libvirt-in-docker/start.sh`: it starts each
daemon that does not run, never stops one, and changes nothing when all run and `qemu:///system` answers. Restart the
container if a daemon hangs.

## KVM

Guests use KVM when the host exposes `/dev/kvm` to the container; otherwise they run under QEMU's software emulation,
which is slow. To see which applies, read the `kvm=` line of `/run/libvirt-in-docker/status`, or the line the start
check prints.

## What persists

Two named volumes per dev container survive a rebuild:

| Volume                                       | Mounted at          | Holds                                        |
| -------------------------------------------- | ------------------- | -------------------------------------------- |
| `libvirt-in-docker-data-${devcontainerId}`   | `/var/lib/libvirt`  | Disk images, firmware variables, guest state |
| `libvirt-in-docker-config-${devcontainerId}` | `/etc/libvirt/qemu` | The definitions of guests and networks       |

- Definitions libvirt keeps elsewhere under `/etc/libvirt` (storage pools, secrets, network filters) do not persist.
  After a rebuild the disk images are still in `/var/lib/libvirt/images`; `virt-install` defines the `default` pool
  again when it next uses it.
- Deleting the volumes deletes the guests and their disks.
- A disk image may also live in the workspace; libvirt does not change its owner.

## Limits

- **Stopping the container ends every running guest at once**, as a power cut would: a feature has no hook that runs
  before the container stops. The feature starts no guest again at the next start. Shut guests down first
  (`virsh shutdown <name>`).
- A guest's graphical console listens inside the container (`127.0.0.1`, port 5900 and up); reach it through a forwarded
  port, or use `virsh console` for a serial console.
- On Fedora the option `swtpm` makes no difference: Fedora's QEMU driver package depends on swtpm, so it is always
  installed there.

## OS support

See [test/libvirt-in-docker/compatibility.json](../../test/libvirt-in-docker/compatibility.json).
