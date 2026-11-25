# Design

## Context

See proposal.md - Why. In this collection the nearest relative of `incus` is `libvirt-in-docker`: a privileged container
with `init`, a daemon packaged for systemd that an entrypoint starts as root at every start, a start record under
`/run`, a `postStartCommand` check that reads it, and named volumes for what must survive a rebuild. The nearest
relatives of `lxc-distrobuilder` are `opentofu` (a release selected by `version`, verified against a signature by a key
pinned by fingerprint) and `apptainer` (security options for a tool that creates namespaces and mounts). What is the
same is named, not repeated. The interface was agreed with the maintainer in conversation before this change and is
recorded in issue #211: the two feature ids, the options below, `privileged` for `incus`, and `SYS_ADMIN` with
`apparmor=unconfined` for `lxc-distrobuilder`.

Facts this change relies on, checked on 2026-11-25 in throwaway containers on an amd64 Docker daemon with cgroup v2, a
6.18 kernel, and no AppArmor in the kernel:

- Incus releases: the latest feature release is 7.6; the long-term support series are 7.0 and 6.0. Upstream's GitHub
  releases hold a static client and no daemon.
- Zabbly repository: `https://pkgs.zabbly.com/incus/<channel>` has the channels `stable` (7.6), `lts-7.0` (7.0.2),
  `lts-6.0` (6.0.7), and `daily`; each serves the suites `bookworm`, `trixie`, `jammy`, `noble`, and `resolute` for
  amd64 and arm64, and no others. Each package index holds only the two newest builds. The key at
  `https://pkgs.zabbly.com/key.asc` is one primary key with the fingerprint `4EFC590696CB15B87C73A3AD82CC8797C838DCFD`,
  expiring 2030-08-17.
- Zabbly packages: `incus-base` runs containers and depends on `incus-client`; `incus` depends on `incus-base` and adds
  a bundled QEMU; everything the daemon needs (LXC, LXCFS, QEMU) is under `/opt/incus`, and the commands in `/usr/bin`
  are wrappers. `/opt/incus/lib/systemd/incusd` is the script the systemd unit runs: it sets the paths of the bundle and
  runs the daemon with its arguments. `incus-base` depends on `systemd | systemd-standalone-sysusers | systemd-sysusers`
  to create its groups.
- Distribution packages: Debian 13 has Incus 6.0.4, Ubuntu 24.04 has 6.0.0, Debian 12 has it in backports only, and
  Ubuntu 22.04 has none.
- Install without systemd: on `debian:13`, with `systemd-standalone-sysusers` installed first, `incus-base` 7.6 installs
  in an image build; the package script warns that systemd was not found and exits 0; the groups `incus` and
  `incus-admin` exist afterwards and root has a subordinate ID range of 1,000,000,000 in `/etc/subuid` and
  `/etc/subgid`. Without that package apt selects `systemd`.
- Daemon in a privileged container: `/opt/incus/lib/systemd/incusd --group incus-admin --logfile <file>` starts,
  `incus admin waitready` returns, `incus admin init --minimal` creates a `dir` pool and the bridge `incusbr0`, and an
  Alpine instance from the community image server starts, gets an IPv4 address, and reaches the network. The daemon logs
  that AppArmor is unavailable and, for the `incus-base` package, that virtual machines are not operational.
- Without `privileged`: with `SYS_ADMIN` and `NET_ADMIN` the bridge cannot be created (`/proc/sys` is read-only); adding
  `systempaths=unconfined` creates the bridge but the instance does not start; adding `seccomp=unconfined` as well, the
  instance starts and reaches the network. `seccomp=unconfined` without `systempaths=unconfined` fails like the first
  case.
- Ended processes: in a privileged container whose command is `sleep infinity`, two ended `incusd` processes stayed
  uncollected under process 1 after two instance starts.
- cgroups: the instance's cgroup has no controllers, `incus config set <instance> limits.memory=256MiB` fails with
  "setting cgroup item for the container failed", and LXC logs "Could not enable ... controllers in the unified cgroup"
  with "Device or resource busy". LXC puts an instance's cgroup below the cgroup of the daemon; inside the container's
  cgroup namespace that cgroup holds processes, so it cannot delegate controllers. Moving every process to a child
  cgroup first, as `docker-in-docker` does, moved the instance's cgroup with the daemon and changed nothing.
- distrobuilder releases: the latest is 3.4.0. A release holds two assets, `distrobuilder-<version>.tar.gz` and its
  `.asc`; no release holds a binary. Tags are `v3.4.0`, `v3.3.1`, `v3.3.0`, and before that `distrobuilder-3.2`; the
  archive of 3.3.0 is named `distrobuilder-3.3.tar.gz`. The signatures of 3.4.0 and 3.3.1 are by the key
  `602F567663E593BCBD14F338C638974D64792D67`, which `https://github.com/stgraber.gpg` serves. The Snap Store no longer
  has distrobuilder. Debian 13 and the Zabbly package `incus-extra` ship 3.2; Debian 12 and Ubuntu 22.04 ship none, and
  Ubuntu 24.04 none for amd64 or arm64.
- distrobuilder build: the archive of 3.4.0 holds a `vendor` directory and a `go.mod` with `go 1.25.12` (3.3.1:
  `go 1.25.6`). On `debian:12`, with the Go 1.25.12 archive from `dl.google.com`, `gcc`, and `libc6-dev`, and with
  `GOFLAGS=-mod=vendor`, `GOPROXY=off`, and `GOTOOLCHAIN=local`, `go build` with the tags of upstream's `Makefile`
  produces a 44 MB executable in 33 seconds that links only the C library and prints `3.4.0`. The unpacked toolchain
  takes 243 MB and the build cache 351 MB. `https://dl.google.com/go/<archive>.sha256` holds the archive's bare SHA-256
  digest; `https://go.dev/dl/<archive>` redirects to `dl.google.com`.
- distrobuilder privileges, with 3.2 and the `alpine.yaml` definition of the community image server: in a default
  container every command, `--version` included, fails with "Failed to unshare namespaces: Operation not permitted";
  with `--cap-add SYS_ADMIN` alone, `build-dir` and `build-incus` succeed; with `MKNOD` dropped as well they fail at
  creating `/dev/console`; `build-incus --vm` fails with "Failed to setup loop device" unless the container is
  privileged, where it writes `disk.qcow2`.

Not checked before this change: anything on arm64; a host with AppArmor; `ubuntu:22.04`, `ubuntu:24.04`, and `debian:12`
for `incus`; a container restart; `repack-windows` (Open Questions).

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- Both `install.sh` files and every shipped script are bash with `set -euo pipefail`, as `shell-style.md` says; every
  supported image ships bash. Checked by shellcheck in `just check`.
- Validate before any change: the distribution, the architecture, and the form of each option are checked before
  anything is downloaded or installed. Checked by a `fail_*` scenario of each feature that runs the installer with an
  invalid option and with a rewritten `/etc/os-release`, and asserts that no package was added.
- Every key and every downloaded file is checked in a temporary directory that the install removes on every exit, and
  GnuPG runs with a home directory inside it. Checked by the scenarios that assert no `.gnupg` content in a home
  directory, and by review.
- `incus`: the Zabbly key is accepted by comparing the fingerprints of all primary keys in the fetched file with the
  pinned one, before the key is copied to `/etc/apt/keyrings`. Checked by a scenario that runs the installer against a
  stub `curl` serving another key.
- `incus`: the start scripts take nothing from their environment: the entrypoint reads the remote user's name and the
  options from a root-owned file in `/usr/local/share/incus-feature`, written at build time. Checked by the "Environment
  does not change the start" scenario and by review.
- `incus`: the entrypoint is bounded: the wait for the daemon has a fixed limit, after which the failure is recorded and
  the container's command runs. Checked by the "Daemon fails to start" scenario, which makes the daemon's script fail.
- `incus`: the entrypoint never stops the daemon and never writes into the volume itself; only the daemon and
  `incus admin init` do. Checked by the "Run again by hand" scenario and by review of every path the scripts name.
- `lxc-distrobuilder`: the build runs with `GOFLAGS=-mod=vendor`, `GOPROXY=off`, `GOTOOLCHAIN=local`, and `GOCACHE`,
  `GOPATH`, and `GOMODCACHE` inside the temporary directory, so it can reach no network and leaves nothing outside that
  directory but the executable. Checked by review, and by the "No toolchain left" scenario.
- `lxc-distrobuilder`: the executable is replaced only after the build succeeded, by a rename on the same file system,
  and the version record is written after it. Checked by the scenarios that assert the executable is left as it was
  after a failed install.
- Packages are installed without recommended packages, and package caches are cleaned at the end, as the other features
  do.

**Non-Goals:**

- A client-only feature for an Incus daemon outside the container, the Incus web UI, clustering, and remote API access.
- Storage backends other than `dir` out of the box: a developer may create a loop-backed pool by hand.
- Shutting instances down when the container stops, and supervising the daemon: one that exits stays down until the next
  start or until root runs the start script again.
- Working beside a Docker daemon in the same container.
- distrobuilder releases before 3.3.1, and running distrobuilder as a user other than root.

## Decisions

### Two independent features

Incus and distrobuilder are separate tools with separate releases, and each is useful alone: distrobuilder builds images
for LXC and for an Incus elsewhere, and most Incus users launch published images. Their privilege needs differ
(`privileged` against one capability), and metadata cannot follow an option, so one feature would give every
distrobuilder user a privileged container with a daemon. Neither names the other in `dependsOn` or `installsAfter`:
nothing either installs changes what the other does.

Rejected: installing distrobuilder as an option of `incus` through the Zabbly package `incus-extra`. It ships 3.2,
cannot select a release, and brings five unrelated tools.

### Ids

`incus` is the upstream name and names the whole of what the feature runs. Rejected: `incus-in-docker`, after
`libvirt-in-docker`: no counterpart outside the container is planned, and a later client-only feature would be
`incus-client`. `lxc-distrobuilder` carries the prefix of the project it belongs to, because the bare word is common and
says nothing about whose tool it is; decided by the maintainer.

### Options

`incus`:

| Name         | Type    | Default   | Enum                           | Meaning                                                           |
| ------------ | ------- | --------- | ------------------------------ | ----------------------------------------------------------------- |
| `channel`    | string  | `stable`  | `stable`, `lts-7.0`, `lts-6.0` | The Zabbly channel to install from.                               |
| `vm`         | boolean | `false`   |                                | Install `incus` (with virtual machine support), not `incus-base`. |
| `initialize` | string  | `minimal` | `minimal`, `none`              | Initialize an uninitialized daemon at start, or leave it.         |

`lxc-distrobuilder`:

| Name             | Type    | Default  | Proposals         | Meaning                                    |
| ---------------- | ------- | -------- | ----------------- | ------------------------------------------ |
| `version`        | string  | `latest` | `latest`, `3.4.0` | The distrobuilder release to build.        |
| `vmSupport`      | boolean | `false`  |                   | Install the tools `build-incus --vm` runs. |
| `windowsSupport` | boolean | `false`  |                   | Install the tools `repack-windows` runs.   |

- `channel` defaults to `stable`: it matches the `latest` default of the collection's other features, and a dev
  container is rebuilt often enough to follow a monthly release. Decided by the maintainer. `daily` is left out: it is
  an unreleased build.
- `channel` is an `enum`, not a version: the repository holds only the newest builds of each channel, so an exact
  version could not be installed a month later. A new long-term support series needs a new minor version of the feature.
- `vm` defaults to `false`: the `incus` package adds a bundled QEMU and its firmware to the 269 MB that `incus-base`
  puts under `/opt/incus`, and virtual machines work only where the host offers `/dev/kvm`.
- `initialize` defaults to `minimal`: an uninitialized daemon cannot launch anything, and Incus's own minimal
  initialization is the smallest working setup. `none` is for a preseed, which the developer runs from a lifecycle
  command where it is visible.
- `version` defaults to `latest`, as in the other features that build or download a release.
- `vmSupport` and `windowsSupport` default to `false`: both pull in tools most image builds never run, and both need a
  privileged container the feature does not declare.
- Rejected: a `preseed` option holding YAML or a path. A multi-line value in a feature option is hard to read in
  `devcontainer.json`, and a path would make the entrypoint read a file of the workspace as root.
- Rejected: a `storage` option for Btrfs, ZFS, or LVM pools. Each needs kernel support and tools the feature cannot
  check at build time; `initialize` `none` leaves the way open.
- Rejected: a `ui` option. The Zabbly UI package depends on the `incus` package and needs a listening HTTPS address.
- Rejected: one `extraTools` list for distrobuilder. Two booleans name what each set is for and keep the package names
  out of the configuration.

### Incus from the Zabbly repository

Upstream's installation guide names the Zabbly repository for Debian and Ubuntu, and upstream's project leader maintains
it, so it is the channel upstream publishes current packages through. It is the only source that gives one Incus version
on all four supported images, and its packages bundle LXC, LXCFS, and QEMU at the versions that Incus version needs. The
feature pins the signing key by fingerprint and defines the repository in one deb822 file, so a second install replaces
the channel instead of adding a second one.

Rejected: the distributions' packages. Two of the four images have none, and the other two have 6.0 releases of
different age. Rejected: upstream's GitHub release, which holds only a client. Rejected: building from source, which
needs LXC and QEMU built the same way.

Before the Zabbly packages, the feature installs `systemd-standalone-sysusers` where the image has no systemd and the
distribution release ships that package, so that apt does not pull systemd into the image to create two groups.

### `privileged` for `incus`

A set without `privileged` exists (Context): `SYS_ADMIN`, `NET_ADMIN`, `seccomp=unconfined`, and
`systempaths=unconfined`, with `apparmor=unconfined` where the host has AppArmor. It was rejected because it protects
little more than `privileged` does — the system call filter, AppArmor, and the masked paths are all off, and only the
device restrictions remain — while it loses virtual machines and loop-backed pools for want of devices, depends on an
option only Docker knows (`systempaths`), and was shown for one instance on one kernel. A monthly `stable` release that
touches one more kernel interface would break it without a change in this repository.

### `init` for `incus`

Ended helper processes of the daemon are left to process 1 (Context). The dev container CLI's default command collects
them, but a Compose service or `overrideCommand: false` keeps the image's command. As in `libvirt-in-docker`.

### One volume at `/var/lib/incus`

Everything Incus keeps is under `/var/lib/incus`: the database, the `dir` pool with instances and images, and the
socket. A named volume keeps it across rebuilds and keeps the instances' root file systems off the container's overlay
file system. The configuration the feature writes lives outside it, in `/usr/local/share/incus-feature`, so an upgrade
of the feature is never frozen in a volume. An older Incus cannot open a database a newer one wrote; the spec leaves
that to the developer (a new volume) instead of guarding against it, since the daemon's own error names the cause.

### Daemon start in the entrypoint, verdict in `postStartCommand`

As in `libvirt-in-docker` and `firewall`: the entrypoint runs as root before the container's command and cannot fail the
start, so it writes a record, and the `postStartCommand` check, which the dev container tool reports, reads it. The
record is under `/run/incus-feature/`, and the feature's files under `/usr/local/share/incus-feature/`, because
`/run/incus` and `/usr/share/incus` belong to Incus. The entrypoint runs the script the Zabbly systemd unit runs, so the
bundle's paths stay the package's business. It does not start LXCFS: the unit that would is disabled inside containers
by its own condition.

The first initialization is decided from the daemon's state (no storage pool and no managed network), not from a marker
file, so a volume from an earlier container and a daemon the developer initialized are both left alone.

### No cgroup delegation

Instance limits are not applied (Context). Making them work means giving the daemon a cgroup without processes below a
cgroup that delegates controllers, which inside the container's cgroup namespace means moving every process of the dev
container. That was tried in its simple form without effect, and the remaining forms change where the developer's own
processes are accounted. `libvirt-in-docker` made the same choice. The spec states the limit.

### distrobuilder from the signed source

Upstream publishes distrobuilder as a signed source archive with vendored modules and points to distribution packages
for binaries. Those packages are at 3.2 where they exist at all and missing on three of the four supported images. The
source archive gives every release from 3.3.1 on, on every image and both architectures, and its signature is the only
verification upstream offers for distrobuilder at all.

The Go toolchain comes from the Go project's download host with the checksum the project publishes beside it; the
version is the one the verified `go.mod` names, so the feature carries no Go version. `GOTOOLCHAIN=local` keeps the `go`
command from fetching another toolchain. The build calls `go build` for the one command, with the tags of upstream's
`Makefile`; it does not run `make`, whose default target rewrites the source with `gofmt` and installs every command
into a Go path.

The release manager's public key is fetched from the GitHub account's key endpoint and accepted by fingerprint only. A
new signing key therefore needs a new version of the feature, like every pinned key in the collection.

Rejected: the Zabbly package `incus-extra` (3.2, no release selection, bundled with other tools, and in conflict with
the `incus` feature's channel). Rejected: the distributions' packages (above). Rejected: removing the C compiler after
the build; removing packages from a shared image can take others with them, and the collection's rule is that a
prerequisite stays.

The minimum is 3.3.1 because 3.3.0's archive has another name and everything earlier another tag form.

### `SYS_ADMIN` and `apparmor=unconfined` for `lxc-distrobuilder`

distrobuilder needs to create namespaces and mount, which is `SYS_ADMIN`; `MKNOD`, which it also needs, is in Docker's
default set (Context). Docker's default AppArmor profile denies `mount` whatever the capabilities, so the profile is
switched off; `apptainer` does the same. The system call filter stays: Docker's default filter allows `mount` and
`unshare` to a process with `SYS_ADMIN`. Both settings are understood by Docker and Podman.

Rejected: `privileged`. It would make virtual machine images and `repack-windows` work out of the box, but most users
build container images, and for them it would add every device of the host and remove the filter and the masked paths
for nothing. A developer who needs loop devices adds `"privileged": true`, or installs `incus`, which brings it.
Rejected: declaring nothing and documenting the flags, which leaves a feature that fails at its first command.

### Supported images

Both features, on amd64 and arm64:

| Image                                              | Remote user in tests |
| -------------------------------------------------- | -------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | `vscode`             |
| `debian:13`                                        | root                 |
| `debian:12`                                        | root                 |
| `ubuntu:22.04`                                     | root                 |

These are the releases the Zabbly repository serves that the collection already tests elsewhere. `lxc-distrobuilder`
keeps the same list although its build would work on more: its runtime tools are named per distribution family, and only
this one was checked. `scenarioArchitectures` stays at the default, amd64.

### Tests

- `incus`: `test.sh` asserts, as the image's remote user, the daemon, the group, the start record, the storage pool and
  bridge of the first initialization, and an instance that starts. So that no job depends on the community image server,
  the instance is created from an image the test builds from a small root file system and imports. Scenarios cover
  `channel` `lts-6.0`, `vm` `true` (the package only, since CI may lack KVM), `initialize` `none`, a second run of the
  start script by hand, a failing daemon script, and a start without a network; a `fail_*` scenario covers the refusals
  and the key check. What needs a second container start or a volume that outlives a container ("Restart", "Rebuild
  keeps instances", "Volume recreated") is checked once, locally, with `devcontainer up` against this checkout, and
  recorded in the PR's Validation section.
- `lxc-distrobuilder`: `test.sh` asserts the executable, the version record, the tools, and a `build-incus` of a small
  image definition in the container the feature's metadata gives. Scenarios cover an explicit `version`, `vmSupport` and
  `windowsSupport`, and the failure of `--vm` without a privileged container; a `fail_*` scenario covers the refusals
  and, with a stub `curl`, a wrong signature and a wrong toolchain digest. The virtual machine image in a privileged
  container is checked once, locally, because no scenario gains `privileged` (`testing.md`).
- One global scenario installs both and imports an image built by distrobuilder into Incus.

## Risks / Trade-offs

- A privileged container with a group that reaches a root daemon → stated in the spec of `incus` with its reasons; the
  metadata shows `privileged`.
- `SYS_ADMIN` without AppArmor is not a boundary → stated in the spec of `lxc-distrobuilder`; the metadata shows both.
- A third package repository in the image → named by upstream, key pinned by fingerprint, one file that a second install
  replaces.
- Source compiled at build time → signature-verified source, checksum-verified toolchain, no network during the build;
  about a minute and 600 MB of temporary space per build.
- `stable` moves monthly, and the host's kernel must meet its requirement (upstream names 6.12 for the current release)
  → `NOTES.md` states it and names the `lts-6.0` channel for older hosts; the CI runners' kernel decides whether the
  `stable` jobs can run (Open Questions).
- Instance limits are not applied, and instances die with the container → stated in the spec and in `NOTES.md`.
- A pinned key expires or is replaced (Zabbly's in 2030) → the install fails with a clear message, and the fix is a new
  version of the feature.
- The test image definition and the Alpine mirror it downloads from are a network dependency of the `lxc-distrobuilder`
  tests → the definition is as small as distrobuilder allows, and a failing mirror shows as a download failure, not as a
  wrong result.

## Open Questions

- Whether the kernel of the CI runners meets the requirement of Incus 7.x, and what the daemon does when it does not. If
  the `stable` jobs cannot run there, the maintainer decides between another default and a documented limit.
- Whether `apparmor=unconfined` is needed and sufficient for `lxc-distrobuilder` on a host with AppArmor; the first CI
  run answers it. A further option would change the approval package.
- Whether every supported image on both architectures ships each package the features need, among them
  `systemd-standalone-sysusers`, `wimtools`, and `genisoimage`; the first builds answer it, and an image that lacks one
  is fixed in the implementation or dropped from the list with the maintainer's word.
- Whether the daemon finds its state after `docker restart`, which keeps `/run`: the "Restart" scenario is checked
  locally, and state the daemon cannot start over is removed by the entrypoint as `libvirt-in-docker` does.
- Whether instances that ran when the container stopped start again with the daemon. The spec promises only that they
  are listed.
