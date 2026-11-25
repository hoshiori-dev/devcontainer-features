# incus Specification

## Purpose

Installs Incus, the system container and virtual machine manager, from the Zabbly package repository, and starts the
Incus daemon at every container start in a privileged dev container, so that the remote user launches and manages
instances that run inside the container, with instances and images persisted in a named volume.

Upstream sources:

- Home: https://linuxcontainers.org/incus/
- Documentation: https://linuxcontainers.org/incus/docs/main/
- Installation guide: https://linuxcontainers.org/incus/docs/main/installing/
- Source and README: https://github.com/lxc/incus
- Zabbly packaging and README: https://github.com/zabbly/incus
- Dev Container Features reference: https://containers.dev/implementors/features/

## Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/incus/compatibility.json`. On a
distribution that `/etc/os-release` identifies as neither Debian nor Ubuntu, the install SHALL fail before changing the
image, with a message naming the detected distribution. On an architecture other than amd64 and arm64 the install SHALL
fail before changing the image, with a message naming the detected architecture.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/incus/compatibility.json`
- **THEN** the build succeeds, `incus` is on `PATH`, and the scripts the feature declares as its entrypoint and its
  `postStartCommand` exist and are executable

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is neither Debian nor Ubuntu
- **THEN** the build fails with a message naming the detected distribution and installs nothing

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than amd64 and arm64
- **THEN** the build fails with a message naming the detected architecture and installs nothing

### Requirement: Zabbly package repository

The feature SHALL install Incus from the Zabbly package repository, which upstream's installation guide names for Debian
and Ubuntu and which upstream's project leader maintains, with the package manager's signature verification in effect. A
release of Debian or Ubuntu that the repository does not serve SHALL fail the build. The repository keeps only a
channel's newest builds, so the feature offers no option for an exact version.

#### Scenario: Release the repository does not serve

- **WHEN** the feature is installed on a Debian or Ubuntu release for which the repository has no suite
- **THEN** the build fails

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

### Requirement: Repository definition

The feature SHALL define the repository in the one file `/etc/apt/sources.list.d/zabbly-incus.sources`, replaced as a
whole at each install: the URI `https://pkgs.zabbly.com/incus/<channel>`, the suite named by the image's
`VERSION_CODENAME`, the component `main`, the image's architecture, and `/etc/apt/keyrings/zabbly.asc` as the only key
that may sign it.

#### Scenario: Repository defined

- **WHEN** the feature has been installed with `channel` `stable` on Debian 13
- **THEN** `/etc/apt/sources.list.d/zabbly-incus.sources` names `https://pkgs.zabbly.com/incus/stable`, the suite
  `trixie`, and `/etc/apt/keyrings/zabbly.asc`, and the installed `incus-client` package comes from that repository

### Requirement: Zabbly signing key

The feature SHALL fetch the repository's signing key from `https://pkgs.zabbly.com/key.asc`, over HTTPS on every hop,
and SHALL install it as `/etc/apt/keyrings/zabbly.asc` only when the fetched file holds exactly one primary key and its
fingerprint is `4EFC590696CB15B87C73A3AD82CC8797C838DCFD`, checked in a keyring used for this install alone before the
repository is defined. The key file relies on TLS alone; only the pinned fingerprint is accepted.

#### Scenario: Pinned key

- **WHEN** the fetched key file holds the key with the pinned fingerprint and no other primary key
- **THEN** the key is installed and the repository is defined

#### Scenario: Another key

- **WHEN** the fetched key file holds a key with another fingerprint, alone or beside the pinned one
- **THEN** the install fails with a message saying the key was not accepted, before any repository is defined or package
  installed

#### Scenario: Key unavailable

- **WHEN** `https://pkgs.zabbly.com/key.asc` cannot be fetched
- **THEN** the install fails with a message naming the URL

### Requirement: Prerequisites from configured repositories

The feature SHALL install curl, CA certificates, and GnuPG, only when the image lacks them, from the package
repositories the image already configures. Everything else it installs SHALL come from the Zabbly repository or, as a
dependency of its packages, from the repositories the image already configures. It SHALL install packages without
recommended packages, SHALL download nothing else at build time, and SHALL contact the network at container start for
nothing.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image that lacks curl and GnuPG
- **THEN** the install succeeds

#### Scenario: Start without a network

- **WHEN** a container built with the feature starts without a network
- **THEN** the daemon starts and the start check passes

### Requirement: Option channel

The feature SHALL accept the option `channel` as declared here and install the newest Incus of that Zabbly channel:
`stable` is upstream's current feature release, `lts-7.0` and `lts-6.0` its long-term support series.

| Field   | Value                            |
| ------- | -------------------------------- |
| Type    | `string`                         |
| Default | `"stable"`                       |
| Enum    | `["stable","lts-7.0","lts-6.0"]` |

#### Scenario: Omitted channel

- **WHEN** the feature is installed without `channel`
- **THEN** the repository definition names `https://pkgs.zabbly.com/incus/stable`

#### Scenario: Long-term support channel

- **WHEN** the feature is installed with `channel` `lts-6.0`
- **THEN** `incus --version` reports a version of the 6.0 series

#### Scenario: Unknown channel

- **WHEN** the installer runs with `channel` set to a value outside the enumeration, such as `daily`
- **THEN** it fails before changing the image, with a message naming the accepted values

### Requirement: Option vm

The feature SHALL accept the option `vm` as declared here: `false` installs the package `incus-base`, which runs
containers only, and `true` installs the package `incus`, which adds the virtual machine support the Zabbly packages
bundle. Virtual machines need the host to offer `/dev/kvm`.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted vm

- **WHEN** the feature is installed without `vm`
- **THEN** the package `incus-base` is installed and the package `incus` is not

#### Scenario: vm enabled

- **WHEN** the feature is installed with `vm` `true`
- **THEN** the package `incus` is installed

### Requirement: Option initialize

The feature SHALL accept the option `initialize` as declared here: `minimal` initializes a daemon that has not been
initialized (Requirement: First initialization), and `none` leaves initialization to the developer.

| Field   | Value                |
| ------- | -------------------- |
| Type    | `string`             |
| Default | `"minimal"`          |
| Enum    | `["minimal","none"]` |

#### Scenario: Omitted initialize

- **WHEN** the feature is installed without `initialize` and the container starts with a new volume
- **THEN** `incus storage list` shows a storage pool and `incus network list` shows a managed bridge

#### Scenario: initialize none

- **WHEN** the feature is installed with `initialize` `none` and the container starts with a new volume
- **THEN** the daemon answers, and it holds no storage pool and no managed network

### Requirement: Privileged container

The feature SHALL declare the container privileged: instances need writable cgroups, system paths Docker masks, and a
bridge with packet filter rules; virtual machines need `/dev/kvm` and loop-backed storage pools need loop devices, which
a feature cannot request singly.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it is privileged

### Requirement: Privileged container risk

A privileged container can take over its host. The feature SHALL accept this risk: running instances in the container is
its purpose, the smaller set of capabilities and security options that starts an instance protects little more and is
specific to Docker, and the setting is visible in the feature's metadata. `NOTES.md` SHALL state the risk.

#### Scenario: Notes state the privilege

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it says that the container is privileged and that a privileged container can take over its host

### Requirement: Init process

The feature SHALL declare that the container runs an init process as its first process. The daemon leaves ended helper
processes to the container's first process, and a container command that collects none would accumulate them.

#### Scenario: Ended helpers are collected

- **WHEN** an instance has been started and stopped in a container whose command is `sleep infinity`
- **THEN** no ended `incusd` process remains uncollected

### Requirement: Persistent volume

The feature SHALL declare exactly one mount: the named volume `incus-data-${devcontainerId}` at `/var/lib/incus`, which
holds the daemon's database, its storage pools of the `dir` driver, images, and instances. A non-empty volume SHALL keep
its content across stops, rebuilds, and feature upgrades; the feature SHALL never replace it.

#### Scenario: Rebuild keeps instances

- **WHEN** an instance is created and the dev container is rebuilt
- **THEN** after the rebuild `incus list` shows the instance

#### Scenario: Volume recreated

- **WHEN** the volume is deleted and the container is created again
- **THEN** the daemon starts, and with `initialize` `minimal` it is initialized again

### Requirement: Daemon started at every start

On every start of the container the feature's entrypoint SHALL, when it runs as root, start the Incus daemon with the
group `incus-admin` as the owner group of its socket and `/var/log/incus/incusd.log` as its log, wait at most 60 seconds
until the daemon answers, and apply Requirement: First initialization, before it hands over to the container's command.
It SHALL hand over whatever the outcome. An entrypoint that does not run as root SHALL start nothing.

#### Scenario: First start

- **WHEN** a container built with the feature starts
- **THEN** the remote user's `incus list` succeeds once the start check has passed

#### Scenario: Daemon fails to start

- **WHEN** the daemon cannot be started, does not keep running, or does not answer within the limit
- **THEN** the container's command still runs and the start record names the failure

#### Scenario: Restart

- **WHEN** a container with the feature is stopped and started again
- **THEN** the daemon answers again and the instances created before are listed

### Requirement: Run again by hand

The entrypoint's script SHALL be safe for root to run again in a running container. It SHALL never stop the daemon; it
SHALL start the daemon when it does not run; and when the daemon runs and answers, it SHALL leave the daemon and its
instances as they are.

#### Scenario: Run again by hand

- **WHEN** root runs the entrypoint's script while the daemon runs and an instance is running
- **THEN** the instance keeps running and the daemon is not restarted

#### Scenario: The daemon has stopped

- **WHEN** root runs the script after the daemon has stopped
- **THEN** the daemon is started and answers

### Requirement: Start settings from the image only

The entrypoint SHALL read its settings, the options and the remote user's name, only from a root-owned file written at
build time, and SHALL NOT read them from its environment or from a file the remote user can change.

#### Scenario: Environment does not change the start

- **WHEN** the container's environment sets a variable with the name of an option
- **THEN** the start behaves as the options the image was built with say

### Requirement: First initialization

With `initialize` `minimal`, the entrypoint SHALL run Incus's own minimal initialization (`incus admin init --minimal`)
once the daemon answers, when the daemon holds no storage pool and no managed network. This creates a storage pool of
the `dir` driver inside the volume, a managed bridge with NAT, and the devices of the `default` profile that use them.

#### Scenario: New volume

- **WHEN** `initialize` is `minimal` and the container starts with a new volume
- **THEN** an instance launched from an image in the daemon's image store starts and gets an address on the managed
  bridge

### Requirement: Initialized daemon left alone

When the daemon holds a storage pool or a managed network, the entrypoint SHALL change nothing, and with `initialize`
`none` it SHALL never initialize. A failed initialization SHALL be recorded and SHALL NOT stop the daemon.

#### Scenario: Initialized volume

- **WHEN** the container starts again with a volume that holds a storage pool
- **THEN** the storage pools, networks, and profiles are as they were before the start

#### Scenario: Developer's own initialization

- **WHEN** `initialize` is `none` and the developer runs `incus admin init` with a preseed after the start
- **THEN** the daemon holds what the preseed describes, and later starts change none of it

### Requirement: Documented initialization by preseed

`NOTES.md` SHALL give the configuration for a developer's own initialization: `initialize` `none`, a preseed file in the
workspace, and a `postCreateCommand` in `devcontainer.json` that runs `incus admin init --preseed` on it. It SHALL say
that the command runs again when the container is created again, against the daemon the volume already holds, and that
Incus applies an unchanged preseed again without error.

#### Scenario: Notes give the preseed configuration

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it shows the option value, the lifecycle command, and an example preseed that declares a storage pool, a
  network, and the `default` profile's devices

#### Scenario: Preseed applied twice

- **WHEN** `initialize` is `none` and the same preseed is applied to the daemon a second time
- **THEN** the command exits 0 and the storage pools and networks are as after the first time

### Requirement: Access for the remote user

The feature SHALL add the remote user to the `incus-admin` group at build time, so that the user controls the daemon
through its socket without `sudo`. When the remote user is root it SHALL add no membership.

#### Scenario: Remote user connects

- **WHEN** the remote user, who is not root, runs `incus list` after a start
- **THEN** it succeeds without `sudo`

#### Scenario: User outside the group

- **WHEN** a user who is neither root nor a member of the `incus-admin` group runs `incus list`
- **THEN** the daemon's socket refuses the connection

#### Scenario: Root remote user

- **WHEN** the remote user is root
- **THEN** the build succeeds and no group membership is added

### Requirement: The incus-admin group is root

A member of the `incus-admin` group controls a daemon that runs as root in a privileged container, which amounts to root
in the container and on its host. The feature SHALL accept this for the remote user, who develops in that container.
`NOTES.md` SHALL state it.

#### Scenario: Notes state the reach of the group

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it says that membership in the `incus-admin` group amounts to root in the container and on its host

### Requirement: Start record and check

The entrypoint SHALL record the outcome of each start in `/run/incus-feature/status`, readable by every user and
writable by root alone: the result, the reason of a failure, the state of the initialization, and the path of the
daemon's log. The feature's `postStartCommand` SHALL read that record, connect to the daemon as the user it runs as, and
exit non-zero with the recorded reason when the daemon did not start or does not answer.

#### Scenario: Started

- **WHEN** the daemon started and answers
- **THEN** the check exits 0 and prints the installed Incus version

#### Scenario: Not started

- **WHEN** the record reports a failed start
- **THEN** the check exits non-zero and prints the reason and the path of the daemon's log

#### Scenario: Failed initialization

- **WHEN** the daemon answers and the record reports a failed initialization
- **THEN** the check exits 0 and prints the failure

### Requirement: Instance limits are not applied

Limits an instance sets through cgroups, such as `limits.memory` and `limits.cpu`, are not applied: inside the
container's cgroup namespace the daemon's cgroup holds processes and cannot delegate controllers to the instances. The
feature SHALL accept this, since moving the daemon to another cgroup would change where every process of the dev
container is accounted, and the instances still start. `NOTES.md` SHALL state it.

#### Scenario: Limit without effect

- **WHEN** an instance is running in a container built with the feature
- **THEN** the instance has no memory controller, and setting `limits.memory` on it is refused or has no effect

### Requirement: Documented limits of the container

`NOTES.md` SHALL state: that stopping the container ends every running instance at once, since a feature has no hook
that runs before the container stops; that a Docker daemon in the same container sets a forwarding policy that cuts
instances off the network, with the upstream page that describes the remedy; and that `init` cannot be switched off from
`devcontainer.json`.

#### Scenario: Notes state the container's limits

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it names each of these limits

### Requirement: Documented limits of versions

`NOTES.md` SHALL state: that the host's kernel must meet the requirement of the installed Incus series, with the channel
to choose for an older host; and that a volume written by a newer Incus cannot be opened by an older one, so a change to
an older channel needs a new volume.

#### Scenario: Notes state the version limits

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it names each of these limits

### Requirement: Second install

Installing the feature a second time on the same image SHALL succeed, and the later install's options SHALL be the ones
in effect: the repository definition and the start settings are replaced as a whole, the newest version of the later
channel is installed, also when it is older than the installed one, and the remote user's group membership is added
once. A second install SHALL NOT remove a package: after `vm` `true` followed by `vm` `false`, the package `incus` stays
installed.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** the second install succeeds and the repository definition, the key, and the start settings are unchanged

#### Scenario: Another channel

- **WHEN** the feature is installed with `channel` `stable` and then with `channel` `lts-6.0`
- **THEN** the repository definition names only `lts-6.0`, and `incus --version` reports a version of the 6.0 series

#### Scenario: Other start options

- **WHEN** the feature is installed with `initialize` `none` and then with defaults
- **THEN** a start with a new volume initializes the daemon
