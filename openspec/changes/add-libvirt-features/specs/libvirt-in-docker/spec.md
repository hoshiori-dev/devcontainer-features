# Spec Delta

## Purpose

Installs the libvirt daemon, QEMU, UEFI firmware, and the libvirt client tools from the image's distribution, and starts
the daemon at every container start in a privileged dev container, so that the remote user manages virtual machines that
run inside the container, with their definitions and disks persisted in named volumes.

Upstream sources:

- Home: https://libvirt.org/
- Documentation: https://libvirt.org/docs.html
- Daemons and their sockets: https://libvirt.org/daemons.html
- QEMU driver and `qemu.conf`: https://libvirt.org/drvqemu.html
- Virtual networking: https://libvirt.org/formatnetwork.html
- Connection URIs: https://libvirt.org/uri.html
- QEMU: https://www.qemu.org/
- virt-install: https://virt-manager.org/
- swtpm: https://github.com/stefanberger/swtpm
- Dev Container Features reference: https://containers.dev/implementors/features/

## ADDED Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/libvirt-in-docker/compatibility.json`.
On a distribution whose `/etc/os-release` identifies none of the supported families, the install SHALL fail before
changing the image, with a message naming the detected distribution. On an architecture other than amd64 and arm64 the
install SHALL fail before changing the image, with a message naming the detected architecture.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/libvirt-in-docker/compatibility.json`
- **THEN** the build succeeds, `virsh`, `virt-install`, `qemu-img`, and the QEMU system emulator of the container's
  architecture are present, and the scripts the feature declares as its entrypoint and its `postStartCommand` exist and
  are executable

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is not supported
- **THEN** the build fails with a message naming the detected distribution and installs nothing

### Requirement: Packages from the image's repositories only

The feature SHALL install its packages (Requirement: Installed components) only from the package repositories already
configured in the image, at the versions they ship and with the package manager's signature verification in effect. It
SHALL NOT add a package repository or a signing key, and SHALL NOT download anything else at build time.

#### Scenario: Distribution versions installed

- **WHEN** the feature has been installed
- **THEN** `virsh --version` reports the version of the distribution's libvirt package, and the image's repository and
  signing key configuration is unchanged

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

### Requirement: Installed components

The feature SHALL install the libvirt daemon with its QEMU, network, storage, node device, secret, and network filter
drivers; the QEMU system emulator of the container's architecture; `qemu-img`; the UEFI firmware for guests of that
architecture and the boot ROMs of QEMU's network devices; `virsh`; `virt-install`; the definition of libvirt's `default`
network; and the DHCP and packet filter tools that network needs.

#### Scenario: Tools present

- **WHEN** the feature has been installed
- **THEN** `virsh`, `virt-install`, and `qemu-img` run, the QEMU system emulator of the container's architecture is
  installed, and a UEFI firmware image for that architecture is present

#### Scenario: Guest with a network device

- **WHEN** a guest of the container's architecture with a virtio network device is started, on amd64 or arm64
- **THEN** QEMU finds the device's boot ROM and the guest runs

### Requirement: Option defaultNetwork

The feature SHALL accept the option `defaultNetwork` as declared here: `true` makes libvirt's `default` network active
at every container start, and `false` leaves starting it to the developer (Requirement: Default network).

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted defaultNetwork

- **WHEN** the feature is installed without `defaultNetwork` and the container starts with new volumes
- **THEN** `virsh net-list` shows the network `default` as active

#### Scenario: defaultNetwork disabled

- **WHEN** the feature is installed with `defaultNetwork` `false` and the container starts with new volumes
- **THEN** the network `default` is defined and inactive

### Requirement: Option swtpm

The feature SHALL accept the option `swtpm` as declared here: `true` installs the distribution's software TPM emulator
and its setup tools, which a guest with an emulated TPM needs, and `false` does not ask for them. A distribution whose
libvirt packages depend on them installs them whatever the option says.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted swtpm

- **WHEN** the feature is installed without `swtpm` on an image that does not hold `swtpm`
- **THEN** `swtpm` is installed only when a package of Requirement: Installed components depends on it

#### Scenario: swtpm enabled

- **WHEN** the feature is installed with `swtpm` `true`
- **THEN** `swtpm --version` succeeds and `swtpm_setup` is on `PATH`

### Requirement: Privileged container

The feature SHALL declare the container privileged: guests need `/dev/kvm` and tap devices, the `default` network needs
a bridge and packet filter rules, and a feature cannot request single devices. A privileged container can take over its
host. The feature SHALL accept this risk, since running virtual machines in the container is its purpose and the setting
is visible in its metadata, and `NOTES.md` SHALL state it.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it is privileged

### Requirement: Daemons started at every start

On every start of the container the feature's entrypoint SHALL, when it runs as root, start the log daemon and the
daemons of Requirement: Daemon layout, wait a bounded time for the system socket to answer, and apply Requirement:
Default network, before it hands over to the container's command. It SHALL hand over whatever the outcome. An entrypoint
that does not run as root SHALL start nothing.

#### Scenario: First start

- **WHEN** a container built with the feature starts
- **THEN** the remote user's `virsh list --all` succeeds once the start check has passed

#### Scenario: Daemon fails to start

- **WHEN** a daemon cannot be started or its socket does not answer within the limit
- **THEN** the container's command still runs and the start record names the failure

### Requirement: State of an earlier start

Before it starts the daemons, the entrypoint SHALL remove the runtime state an earlier start of the same container left
under `/run`: libvirt's sockets, its process ID files, and its record of what it started. It SHALL keep the state of the
current start, and SHALL remove nothing while a daemon runs.

#### Scenario: Restart

- **WHEN** a container with the feature is stopped and started again
- **THEN** the daemon answers again, the guests defined before are listed as shut off, and with `defaultNetwork` `true`
  the network `default` is active

### Requirement: Run again by hand

The entrypoint's script SHALL be safe for root to run again in a running container. It SHALL never stop a daemon; it
SHALL start each daemon that does not run; and when every daemon runs and the system daemon answers, it SHALL change
nothing, the start record included.

#### Scenario: Run again by hand

- **WHEN** root runs the entrypoint's script while every daemon runs and a guest is running
- **THEN** the guest keeps running, no daemon is restarted, and the start record is unchanged

#### Scenario: A daemon has stopped

- **WHEN** root runs the script after one daemon has stopped
- **THEN** that daemon is started, the others keep their processes, and the networks that were active are still active

### Requirement: Start settings from the image only

The entrypoint SHALL read its settings, the options and the daemon layout, only from root-owned files written at build
time, and SHALL NOT read them from its environment or from a file the remote user can change.

#### Scenario: Environment does not change the start

- **WHEN** the container's environment sets a variable with the name of an option
- **THEN** the start behaves as the options the image was built with say

### Requirement: Daemon layout

The feature SHALL run the daemon layout the distribution's packages provide: the monolithic `libvirtd` where the
distribution ships it, and otherwise the modular daemons for QEMU, networks, storage, node devices, secrets, and network
filters (`virtqemud`, `virtnetworkd`, `virtstoraged`, `virtnodedevd`, `virtsecretd`, `virtnwfilterd`). In both layouts
it SHALL run `virtlogd`, and `qemu:///system` SHALL be the connection that reaches the guests.

#### Scenario: Monolithic distribution

- **WHEN** the container's distribution ships `libvirtd`
- **THEN** after a start `libvirtd` and `virtlogd` run and `/run/libvirt/libvirt-sock` answers

#### Scenario: Modular distribution

- **WHEN** the container's distribution ships no `libvirtd`
- **THEN** after a start the six modular daemons and `virtlogd` run, and `virsh --connect qemu:///system` lists guests,
  networks, and storage pools

### Requirement: QEMU configuration for a container

The feature SHALL configure the QEMU driver, in a block of `/etc/libvirt/qemu.conf` it owns and replaces at each
install, with no security driver, QEMU running as root, no changes of file ownership by libvirt, and no cgroup
controllers, so that guests start in a container without systemd. Lines outside the block SHALL stay as the distribution
or the developer wrote them (Requirement: Configuration blocks come first).

#### Scenario: Guest starts

- **WHEN** the remote user defines and starts a guest of the container's architecture that uses software emulation
- **THEN** the guest is listed as running

#### Scenario: Disk image in the workspace keeps its owner

- **WHEN** a guest whose disk image is a file of the workspace is started and shut down
- **THEN** the file's owner and group are those it had before

#### Scenario: Block replaced

- **WHEN** the feature is installed a second time
- **THEN** `/etc/libvirt/qemu.conf` holds the feature's block once

### Requirement: Configuration blocks come first

Each block the feature writes SHALL stand at the top of its file, because libvirt takes the first setting of a name and
ignores a later one: the feature's settings hold whatever the rest of the file sets. The install SHALL log each setting
outside a block that the block overrides, and SHALL keep the file's owner, group, and mode.

#### Scenario: Earlier setting in the image

- **WHEN** the image's `libvirtd.conf` or `qemu.conf` already sets a name the feature's block sets, to another value
- **THEN** the daemon uses the feature's value, and the build log names the file and the setting

### Requirement: Guests are not confined

Guests are not confined against the container, and per-guest limits through cgroups have no effect. The feature SHALL
accept this: a container cannot load AppArmor profiles or SELinux labels for its guests and has no systemd to delegate a
cgroup to each, libvirt would otherwise re-own disk images that are files of the host, and the container is privileged
already. `NOTES.md` SHALL state it.

#### Scenario: Limits without effect

- **WHEN** a guest's definition sets CPU shares or a memory limit through cgroups
- **THEN** the guest starts and the limit is not enforced

### Requirement: Access for the remote user

The feature SHALL add the remote user to the `libvirt` group at build time and SHALL configure each daemon it starts, in
a block of the daemon's configuration file it owns and replaces at each install, so that its read-write and read-only
sockets belong to the `libvirt` group with mode `0770` and need no further authentication. The administration sockets
SHALL stay root-only.

#### Scenario: Remote user connects

- **WHEN** the remote user, who is not root, runs `virsh --connect qemu:///system list --all` after a start
- **THEN** it succeeds without `sudo`

#### Scenario: User outside the group

- **WHEN** a user who is neither root nor a member of the `libvirt` group runs the same command
- **THEN** the connection is refused

#### Scenario: Root remote user

- **WHEN** the remote user is root
- **THEN** the build succeeds and no group membership is added

### Requirement: The libvirt group is root

A member of the `libvirt` group controls a daemon that runs QEMU as root in a privileged container, which amounts to
root in the container and on its host. The feature SHALL accept this for the remote user, who develops in that
container; the distributions' polkit authorization cannot work where no polkit and no system bus run. `NOTES.md` SHALL
state it.

#### Scenario: Notes state the reach of the group

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it says that membership in the `libvirt` group amounts to root in the container and on its host

### Requirement: Default connection

The feature SHALL set the container environment variable `LIBVIRT_DEFAULT_URI` to `qemu:///system`, so that the libvirt
client tools of every user, the remote user included, connect to the system daemon the feature starts instead of a
per-user session daemon. It SHALL NOT write a libvirt client configuration file.

#### Scenario: Remote user's default connection

- **WHEN** the remote user runs `virsh uri` after a start
- **THEN** it prints `qemu:///system`

### Requirement: Default network

At build time the feature SHALL leave libvirt's `default` network defined as the distribution ships it and not marked to
start by itself. With `defaultNetwork` `true`, the entrypoint SHALL start the network at every start when it is defined
and not active; with `false` it SHALL NOT. A network that is not defined or fails to start SHALL be recorded and SHALL
NOT stop the daemons.

#### Scenario: Network active after a start

- **WHEN** `defaultNetwork` is `true` and the container starts
- **THEN** the network `default` is active, and a guest attached to it starts

#### Scenario: Network removed by the developer

- **WHEN** the developer has undefined the network `default` and the container is started again
- **THEN** the daemons run, no network is created, and the start record says the network is not defined

### Requirement: Persistent volumes

The feature SHALL declare exactly two mounts: the named volume `libvirt-in-docker-data-${devcontainerId}` at
`/var/lib/libvirt` (disk images and other guest state) and the named volume `libvirt-in-docker-config-${devcontainerId}`
at `/etc/libvirt/qemu` (definitions of guests and networks). A non-empty volume SHALL keep its content across stops,
rebuilds, and feature upgrades; the feature SHALL never replace it.

#### Scenario: Rebuild keeps guests

- **WHEN** a guest with a disk image in `/var/lib/libvirt/images` is defined, and the dev container is rebuilt
- **THEN** after the rebuild the guest is listed as shut off and its disk image is in place

#### Scenario: Volumes recreated

- **WHEN** both volumes are deleted and the container is created again
- **THEN** no guest is defined and the network `default` is defined as the image ships it

### Requirement: KVM when available

The feature SHALL NOT require KVM. When `/dev/kvm` can be opened in the container, guests of the container's
architecture can use KVM; otherwise guests run under QEMU's software emulation, the daemons start all the same, and the
start record says KVM is not available.

#### Scenario: Host with KVM

- **WHEN** the host exposes `/dev/kvm` and the container starts
- **THEN** `virsh domcapabilities --virttype kvm` succeeds and the start record says KVM is available

#### Scenario: Host without KVM

- **WHEN** the container has no usable `/dev/kvm`
- **THEN** the daemons run, a guest that uses software emulation starts, and the start record says KVM is not available

### Requirement: Start record

Each start whose entrypoint runs as root SHALL write a record of its result, its reason, whether KVM is available, and
the state of the `default` network to a file `NOTES.md` names, readable and not writable by the remote user.

#### Scenario: Remote user reads the record

- **WHEN** the remote user reads the start record
- **THEN** it names the result, the KVM availability, and the network's state, and writing to it is denied

### Requirement: Start check

The feature SHALL run, as its `postStartCommand` and as the remote user, a check that waits a bounded time for the
current start's record, treats an earlier start's record as missing, and runs `virsh --connect qemu:///system version`.
It SHALL exit zero with a one-line summary when the record reports started daemons and the command succeeds; otherwise
it SHALL print the reason and the daemons' log directory and exit non-zero. It SHALL change nothing.

#### Scenario: Daemon running

- **WHEN** the current start started the daemons and the remote user can connect
- **THEN** the check prints a summary naming the libvirt version and whether KVM is available, and exits zero

#### Scenario: Daemon not started

- **WHEN** the daemons failed to start, or the entrypoint did not run as root
- **THEN** the check prints the reason and exits non-zero, so the dev container tool reports the failure

#### Scenario: Stale record

- **WHEN** the only start record present belongs to an earlier start of the container
- **THEN** the check treats the current start as not recorded

### Requirement: Not together with libvirt-outside-of-docker

The install SHALL fail, before changing the image, with a message naming both features, when the image already holds the
`libvirt-outside-of-docker` feature. At every start the entrypoint SHALL start no daemon and remove nothing when
`/run/libvirt` is a mount point, and SHALL record that as the reason: a daemon started there would write into another
system's libvirt directory.

#### Scenario: Installed after libvirt-outside-of-docker

- **WHEN** the feature is installed on an image on which `libvirt-outside-of-docker` was installed
- **THEN** the build fails with a message naming both features and saying they are alternatives

#### Scenario: Mounted run directory

- **WHEN** a container with the feature starts with a directory mounted at `/run/libvirt`
- **THEN** no daemon is started, nothing under the mount is created or removed, and the start check fails naming the
  mount

### Requirement: Container metadata

The feature SHALL declare `privileged`, the two mounts of Requirement: Persistent volumes, one `containerEnv` variable,
one entrypoint, and one `postStartCommand`, and SHALL NOT request `capAdd`, `securityOpt`, or `init`. It SHALL declare
no `dependsOn` and SHALL name exactly `ghcr.io/devcontainers/features/common-utils` in `installsAfter`, so that a remote
user that feature creates exists when this feature's install adds the user to a group.

#### Scenario: Mounts of a built container

- **WHEN** a container is built with only this feature
- **THEN** its mounts the feature declared are exactly the two named volumes

#### Scenario: Remote user missing

- **WHEN** the remote user the dev container tool names does not exist in the image when the feature is installed
- **THEN** the build fails, before any package is installed, with a message naming the user

### Requirement: Installing twice

Installing the feature a second time SHALL succeed. With the same options, the image SHALL end up as after one install.
With different options, a package an earlier install added SHALL stay, the feature's configuration blocks SHALL be
present once, the later install's `defaultNetwork` SHALL be the one in effect from the next start on, and the remote
user of each install SHALL stay a member of the `libvirt` group.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** the build succeeds and the configuration and the start behavior are those of one install

#### Scenario: Different options the second time

- **WHEN** the feature is installed with `defaultNetwork` `false` and `swtpm` `true`, and then with default options
- **THEN** the build succeeds, `swtpm` is still installed, and at the next start the network `default` is active

### Requirement: Documented limits

`NOTES.md` SHALL state that stopping the container ends every running guest at once, as a power cut would, and that the
feature starts no guest again; that without KVM guests run under software emulation, which is slow, and how to see which
applies; and that a guest's graphical console listens inside the container and can be reached through a forwarded port.

#### Scenario: Notes list the limits

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** each statement of this requirement is present

### Requirement: Documented persistence

`NOTES.md` SHALL state that only `/var/lib/libvirt` and the definitions of guests and networks persist; that definitions
libvirt keeps elsewhere under `/etc/libvirt` (storage pools, secrets, network filters) do not; that deleting the volumes
deletes the guests and their disks; and that only the system daemon (`qemu:///system`) is set up, not a per-user session
daemon.

#### Scenario: Notes describe persistence

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** each statement of this requirement is present
