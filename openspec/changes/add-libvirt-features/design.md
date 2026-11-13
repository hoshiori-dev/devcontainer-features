# Design

## Context

See proposal.md - Why. The pair follows the division of `docker-outside-of-docker` and `docker-in-docker` in
https://github.com/devcontainers/features: one feature reaches a daemon outside the container, the other runs the daemon
inside it. In this collection the nearest relatives are `firewall` (an entrypoint that runs as root at every start, a
start record, and a `postStartCommand` check that reads it) and `slurm` (distribution daemons started without systemd, a
named volume for configuration). What is the same is named, not repeated. The interface was agreed with the maintainer
in conversation before this change and is recorded in issue #202: the two feature ids, the options below, `privileged`
and two volumes for `libvirt-in-docker`, no cgroup controllers, a mount the developer declares for
`libvirt-outside-of-docker`, and no change to CI.

Facts this change relies on, checked on 2026-11-13 in throwaway containers on an amd64 Docker 29.9 daemon with cgroup v2
and a usable `/dev/kvm`:

- Versions: `debian:13` ships libvirt 11.3.0 and QEMU 10.0; `mcr.microsoft.com/devcontainers/base:ubuntu24.04` ships
  libvirt 10.0.0 and QEMU 8.2; `fedora:44` ships libvirt 12.0.0 and QEMU 10.2.
- Daemon layout: Debian 13 and Ubuntu 24.04 ship `libvirtd` and `virtlogd`, and no modular daemon is installed with
  them. Fedora 44 ships no `libvirtd`; `virtqemud`, `virtnetworkd`, `virtstoraged`, `virtnodedevd`, `virtsecretd`, and
  `virtnwfilterd` each start with `-d` in a privileged container and answer on their sockets, and `qemu:///system` then
  lists guests, networks, storage pools, node devices, secrets, and filters.
- Without systemd: in a privileged container, `virtlogd -d` followed by the daemons starts them on all three images. The
  `default` network starts (bridge `virbr0`, `192.168.122.1/24`). A diskless guest of type `kvm` starts on all three,
  and one of type `qemu` (software emulation) on Ubuntu.
- `qemu.conf`: with `security_driver = "none"`, `user = "root"`, `group = "root"`, `dynamic_ownership = 0`, and
  `cgroup_controllers = [ ]`, guests start; the QEMU process stays in the container's root cgroup and libvirt logs one
  error line about missing cgroup controllers.
- Access: with the distributions' defaults, a user who is not root is refused on Debian with "Unable to get system bus
  connection", since authorization goes through polkit. With `unix_sock_group = "libvirt"`,
  `unix_sock_rw_perms = "0770"`, `unix_sock_ro_perms = "0770"`, `auth_unix_rw = "none"`, and `auth_unix_ro = "none"` in
  the daemon's file (`libvirtd.conf`, or `virtqemud.conf`, `virtnetworkd.conf`, `virtstoraged.conf` on Fedora), a member
  of the `libvirt` group defines and starts guests on Ubuntu and Fedora. The packages create the `libvirt` group on all
  three.
- Restart: `docker restart` keeps `/run`. After it, `libvirtd` starts over its stale sockets and process ID files, but
  the `default` network, marked autostart, stays inactive: libvirt's record under `/run/libvirt` says it was already
  started. Guests that ran are listed as shut off.
- The `default` network's definition comes marked autostart on Ubuntu and Fedora and not on Debian.
- Client to a daemon in another container: a container that holds only the client packages (`libvirt-clients` and
  `virtinst` on Debian, `libvirt-client` and `virt-install` on Fedora) and a read-only bind mount, at `/run/libvirt`, of
  the `/run/libvirt` of a container running the daemon connects with `virsh --connect qemu:///system` in all four pairs
  of Debian and Fedora as client and as daemon, so in both daemon layouts, without any client configuration. A write
  into the mount is refused ("Read-only file system"). A user who is not root, added to a group created with the
  socket's GID, connects from the Debian client to both layouts and lists guests, networks, and pools.
- A non-root user's `virsh` without `LIBVIRT_DEFAULT_URI` goes to `qemu:///session` and fails, also when
  `/etc/libvirt/libvirt.conf` sets `uri_default`.
- `docker run --mount type=bind` fails the container's creation when the source path does not exist on the daemon's
  machine ("bind source path does not exist").
- Other packages: `swtpm` and `swtpm-tools` exist on Debian 13, Ubuntu 24.04, and Fedora 44; the arm64 emulator and
  firmware are `qemu-system-arm` and `qemu-efi-aarch64` on Debian and Ubuntu, `qemu-system-aarch64-core` and
  `edk2-aarch64` on Fedora.

Not checked before this change: anything on arm64 (Open Questions).

Found while implementing, on 2026-11-13, and carried into the delta specs:

- The host's daemon looks up the connecting user ID in the host's own user database and refuses an ID it does not know
  ("Failed to find user record for uid"), also where the socket's group admits the caller.
- With dev container CLI 0.89.0, a `containerEnv` value of `devcontainer.json` reaches the container's configuration,
  but the remote user's processes still get the feature's value; a `remoteEnv` value replaces it.
- Fedora 44's `libvirt-daemon-driver-qemu` depends on `swtpm-tools`, so swtpm is installed there whatever the option
  says. `swtpm_setup --version` of swtpm 0.7, which Debian 13 and Ubuntu 24.04 ship, prints the version and exits 1.
- Daemons stopped and started again inside one start of the container find their networks and guests only when
  `/run/libvirt` is kept: the bridge of a network outlives the daemon, and libvirt cannot create it a second time.

Repository facts: `just validate` requires `test/<id>/test.sh` and `test/<id>/compatibility.json` for every feature, and
CI's plan fails for an affected feature without a compatibility list, so a feature cannot be left untested without
changing scripts or workflows.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- Both `install.sh` files and every shipped script are bash with `set -euo pipefail`, as `shell-style.md` says; every
  supported image ships bash. Checked by shellcheck in `just check`.
- Validate before any change: the distribution, for `libvirt-in-docker` the architecture, the form of each option, and
  the presence of the other feature are checked before any package is installed. Checked by a `fail_*` scenario of each
  feature that runs the installer with an invalid option and with the other feature's marker present, and asserts that
  no package was added.
- The other feature is recognized by its share directory (`/usr/local/share/libvirt-outside-of-docker`,
  `/usr/local/share/libvirt-in-docker`), which each install creates. Checked by the same scenarios.
- The start scripts take nothing from their environment: the entrypoints read the remote user's name and the options
  from a root-owned file in the feature's share directory, written at build time. Checked by the "Environment does not
  change the start" scenario and by review.
- `libvirt-outside-of-docker` never writes under `/run/libvirt`: its scripts open that directory only with `stat` and
  through `virsh`. Checked by review of every path the scripts name, and by the group alignment scenario, which compares
  a listing of the directory before and after.
- `libvirt-in-docker` removes runtime state only under `/run/libvirt` and the daemons' own process ID files in `/run`,
  and only after it has found that `/run/libvirt` is not a mount point and that no daemon answers. It removes
  `/run/libvirt` only when the start record does not belong to the current start of the container, so daemons started
  again by hand keep their state. Checked by the "Mounted run directory", "Run again by hand", and "Restart" scenarios.
- Each feature's configuration edits are one marked block per file, replaced as a whole. Checked by `duplicate.sh`,
  which counts the markers.
- The entrypoints are bounded: the wait for the socket has a fixed limit, after which the failure is recorded and the
  container's command runs. Checked by the "Daemon not started" scenario, which makes the daemon binary fail.
- Packages are installed without recommended or weak dependencies, and package caches are cleaned at the end, as the
  other features do.

**Non-Goals:**

- A session daemon, hypervisor drivers other than QEMU, storage backends beyond what the distributions' core storage
  driver holds, and graphical clients.
- Shutting guests down when the container stops: a feature has no hook for it.
- Supervising the daemons: one that exits stays down until the next start or until root runs the start script again.
- Emulators for architectures other than the container's.

## Decisions

### Two features, not one with a mode

`privileged` and `mounts` are fixed in a feature's metadata and cannot follow an option. One feature with a mode would
make every user of the client side run a privileged container with two volumes. Two features keep the metadata of each
as small as its job, and the ids mirror the Docker pair developers already know. Rejected names: `libvirt-host` and
`libvirt` (the second says nothing about where the daemon runs), `libvirt-client` (the feature does more than install a
client).

### Options

`libvirt-outside-of-docker`:

| Name          | Type    | Default | Meaning                                                 |
| ------------- | ------- | ------- | ------------------------------------------------------- |
| `virtInstall` | boolean | `true`  | Install `virt-install` (with `virt-clone`, `virt-xml`). |
| `qemuImg`     | boolean | `false` | Install `qemu-img`.                                     |

`libvirt-in-docker`:

| Name             | Type    | Default | Meaning                                                |
| ---------------- | ------- | ------- | ------------------------------------------------------ |
| `defaultNetwork` | boolean | `true`  | Start libvirt's `default` network at every start.      |
| `swtpm`          | boolean | `false` | Install the software TPM emulator and its setup tools. |

- `virtInstall` defaults to `true`: creating a guest is the first thing most users do, and the package is small next to
  what it saves. It is an option at all because it pulls in Python.
- `qemuImg` defaults to `false` in `libvirt-outside-of-docker`: an image made in the container is useful to the host's
  daemon only when the host sees the same path, which the feature cannot arrange. `libvirt-in-docker` always installs
  it, since the daemon and the tool share one filesystem.
- `defaultNetwork` defaults to `true`: a guest without a network is rarely what is wanted, and the distributions
  disagree on whether the network starts by itself, so the feature decides at start instead of leaving it to the
  distribution's mark.
- `swtpm` defaults to `false`: only guests that demand a TPM need it.
- Rejected: a `uri` option. The connection is `LIBVIRT_DEFAULT_URI`, libvirt's own variable, which the developer sets in
  `devcontainer.json` like any other; an option could only write the same value somewhere less visible.
- Rejected: runtime variables of the feature's own (`DEVCONTAINER_LIBVIRT_*`, as `slurm` has). Nothing is decided at
  start that an option or libvirt's variable does not already express.
- Rejected: an option to skip the group alignment or the daemon start. A developer who wants neither does not need the
  feature.
- Rejected: `firmware`, `kvm`, and per-architecture emulator options. Firmware is required on arm64 and small on amd64;
  KVM is used when present.

### `LIBVIRT_DEFAULT_URI` through `containerEnv`

A user who is not root gets `qemu:///session` by default, which neither feature sets up. `/etc/libvirt/libvirt.conf`
does not change that for such a user (Context), and a file in the remote user's home would be written into a directory
developers often mount. `containerEnv` is fixed in the metadata, visible, and reaches every process of the container.

### The mount of `libvirt-outside-of-docker` is the developer's

The feature first was to declare the bind mount of `/run/libvirt` itself. Docker refuses to create a container whose
bind source is missing, so every container with the feature would fail on a machine without libvirt, among them the CI
runners; and the repository cannot leave a feature untested (Context). Changing CI was ruled out by the maintainer. The
mount is therefore one line the developer adds, which `NOTES.md` gives:

```json
"mounts": ["source=/run/libvirt,target=/run/libvirt,type=bind,readonly"]
```

The same target path as on the host keeps the client's own socket lookup working for both daemon layouts, so the feature
writes no socket path anywhere. `readonly` is recommended because connecting to a socket does not need a writable
filesystem (Context), and it keeps the container from creating or removing entries in the host's directory. Rejected:
mounting a parent directory that always exists (`/run`), which would hand the container every socket of the host.

### Group alignment in the entrypoint

A process's groups are fixed when it starts. A dev container tool may start its server while lifecycle commands still
run, so a group added in `postStartCommand` could reach the developer's terminals only after a reconnect. The entrypoint
runs first and as root in the images the collection supports. It never changes the socket, only `/etc/group` in the
container. Rejected: a `socat` proxy to a socket the remote user owns, as `docker-outside-of-docker` does: it adds a
long-running root process and hides who connects from the host's daemon, which matters where polkit decides by user ID.
Rejected: changing the GID of an existing group of the container to the socket's, which would break the files that group
owns.

Where the socket is world-writable or owned by the root group, the host authorizes by other means (polkit, or root only)
and the feature has nothing to align; the start check then reports what the daemon answered.

### Daemon start in the entrypoint, verdict in `postStartCommand`

As in `firewall`: the entrypoint runs as root before the container's command and cannot fail the start, so it writes a
record under `/run/libvirt-in-docker/`, and the `postStartCommand` check, which the dev container tool reports, reads
it. `libvirt-outside-of-docker` keeps the same pair under `/run/libvirt-outside-of-docker/`. Rejected: starting the
daemons from `postStartCommand` through `sudo`, as `slurm` does: it needs passwordless `sudo` for the remote user, and
lifecycle commands of the developer that use `virsh` would race the start.

The entrypoint clears the previous start's runtime state because a restarted container keeps `/run`, and libvirt would
otherwise skip what it believes it already started (Context). It starts the `default` network itself instead of relying
on the autostart mark for the same reason and because the distributions differ on the mark; `install.sh` removes the
mark from the image so that one rule applies everywhere. A volume that already exists keeps whatever mark the developer
set.

### Daemon layout follows the distribution

The feature runs `libvirtd` when the binary is installed and the six modular daemons otherwise. Rejected: forcing one
layout everywhere. Ubuntu 24.04 ships no modular daemons and Fedora 44 no `libvirtd` (Context).

### No cgroup controllers

Without systemd, libvirt would have to manage cgroups itself, which under cgroup v2 needs the container's processes
moved out of the root cgroup first, as `docker-in-docker` does for its own daemon. `cgroup_controllers = [ ]` avoids
that machinery; the cost, no per-guest limits, is stated in the spec. Agreed with the maintainer.

### Two volumes

`/var/lib/libvirt` holds what is large and slow to recreate (disk images, firmware variables). `/etc/libvirt/qemu` holds
guest and network definitions. The rest of `/etc/libvirt` stays in the image so that the feature's configuration blocks
follow an upgrade of the feature instead of being frozen in a volume. The cost is that pool, secret, and filter
definitions are not kept; `virt-install` recreates the `default` pool on use. Rejected: one volume for all of
`/etc/libvirt` with the blocks rewritten at every start, which would have the entrypoint edit files the developer also
edits.

### Supported images

Both features, on amd64 and arm64:

| Image                                              | Remote user in tests |
| -------------------------------------------------- | -------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | `vscode`             |
| `debian:13`                                        | root                 |
| `fedora:44`                                        | root                 |

Alpine, Arch Linux, and openSUSE are left out: their daemon packaging differs again, and nothing was checked there.
`scenarioArchitectures` stays at the default, amd64.

### Tests

- `libvirt-outside-of-docker`: `test.sh` and `duplicate.sh` run in containers without the mount and assert the tools,
  the variable, the "No socket" result of the check, and the metadata. A scenario makes a socket file at
  `/run/libvirt/libvirt-sock` with a chosen GID and mode, runs the entrypoint's script again as root, and asserts each
  case of the group alignment and that the directory's listing is unchanged. A `fail_*` scenario covers the unsupported
  distribution (with `/etc/os-release` rewritten for one run, as `test/apptainer/` does), the presence of
  `libvirt-in-docker`, and invalid options.
- `libvirt-in-docker`: `test.sh` asserts, as the image's remote user, the daemons, the connection, the active network,
  and a diskless guest of type `qemu` that reaches the running state, so no job depends on KVM. Scenarios cover
  `defaultNetwork` `false`, `swtpm` `true`, a second start of the script by hand, and a failing daemon binary; a
  `fail_*` scenario covers the same three refusals and another architecture. "Mounted run directory" runs in a scenario
  too, with a tmpfs the script mounts. What needs a second container start or a volume that outlives a container
  ("Restart", "Rebuild keeps guests", "Volumes recreated") is checked once, locally, with `devcontainer up` against this
  checkout, and recorded in the PR's Validation section.

### Local end-to-end test

The scenarios of `libvirt-outside-of-docker` that need a daemon outside the container ("Read-only mount", "Remote user's
default connection", "Connected", "Refused", "Writable mount") cannot run in CI. They are run once, locally, with
`devcontainer up` against this checkout: a second container runs the distribution's libvirt daemon, in each layout, with
its `/run/libvirt` kept in a directory of the machine that runs Docker, and the feature's container mounts that
directory as `NOTES.md` says. This stands in for a host daemon; a daemon installed on a host and authorized through
polkit is not covered. `NOTES.md` says what was and was not tested and the result, and the PR's Validation section
records the run.

## Risks / Trade-offs

- A privileged container with QEMU as root and a group that reaches the daemon without authentication → stated in the
  spec of `libvirt-in-docker` with its reasons; the metadata shows `privileged`.
- The developer's mount gives the container the host's daemon → stated in the spec and in `NOTES.md` of
  `libvirt-outside-of-docker`; the feature itself grants nothing until the mount is added.
- The remote user joins a container group that happens to share the socket's GID → stated in the spec; the start record
  names the group.
- CI does not cover the connection to an outside daemon → the local test above, and `NOTES.md` says so.
- CI runners may lack KVM, and arm64 was not checked before the change → tests use software emulation; the first CI run
  on arm64 is the check, and a package that is missing there is fixed in the implementation or the image is dropped from
  the list with the maintainer's word.
- A forgotten mount gives a container that starts and a check that only prints a notice → the notice names the mount;
  failing the check would also fail every container that deliberately uses a remote URI.
- Guests die with the container → stated in `NOTES.md`.

## Open Questions

- Whether every supported image on arm64 ships each package the features need; the first CI run on arm64 answers it.
