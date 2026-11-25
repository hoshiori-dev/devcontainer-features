## Purpose

Builds distrobuilder, the image building tool for Incus and LXC, from upstream's signed release source at a chosen
release or the one upstream marks as latest, and installs it with the tools it runs, on `PATH` for every user of the
container, in a container that holds the capability the tool needs to build container images.

Upstream sources:

- Home: https://linuxcontainers.org/distrobuilder/introduction/
- Documentation: https://linuxcontainers.org/distrobuilder/docs/latest/
- Installation guide: https://linuxcontainers.org/distrobuilder/docs/latest/howto/install/
- Source and README: https://github.com/lxc/distrobuilder
- Image definitions of the community image server: https://github.com/lxc/lxc-ci/tree/main/images
- Go downloads: https://go.dev/dl/

## ADDED Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/lxc-distrobuilder/compatibility.json`.
On a distribution that `/etc/os-release` identifies as neither Debian nor Ubuntu, the install SHALL fail before changing
the image, with a message naming the detected distribution. On an architecture other than amd64 and arm64 the install
SHALL fail before changing the image, with a message naming the detected architecture.

#### Scenario: Supported image

- **WHEN** the feature is installed with default options on an image listed in
  `test/lxc-distrobuilder/compatibility.json`
- **THEN** the build succeeds, and `distrobuilder --version` run by root in the container exits 0

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is neither Debian nor Ubuntu
- **THEN** the build fails with a message naming the detected distribution and installs nothing

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than amd64 and arm64
- **THEN** the build fails with a message naming the detected architecture and installs nothing

### Requirement: distrobuilder on PATH

The feature SHALL install the `distrobuilder` executable at `/usr/local/bin/distrobuilder`, executable by every user,
and SHALL record the installed release in `/usr/local/share/lxc-distrobuilder/version`. distrobuilder runs only as root
and needs its capability already to print its version, which an image build does not hold, so the record, not the
executable, tells an install which release is present.

#### Scenario: Default install

- **WHEN** the feature has been installed
- **THEN** `command -v distrobuilder` run as the remote user resolves to `/usr/local/bin/distrobuilder`, and the version
  `distrobuilder --version` prints as root equals the recorded one

#### Scenario: Container image built

- **WHEN** root, in a container that declares nothing beyond the feature, runs `distrobuilder build-incus` on an image
  definition that builds a container image
- **THEN** the command exits 0 and writes the image's metadata archive and its root file system

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `distrobuilder --version` prints the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `3.3.1`
- **THEN** `distrobuilder --version` prints `3.3.1`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v3.3.1`
- **THEN** `distrobuilder --version` prints `3.3.1`

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `3.2.0` or `3.3.0`
- **THEN** the install fails before downloading anything, with a message naming `3.3.1` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `3.4`, `main`, or `3.5.0-rc1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and `/usr/local/bin/distrobuilder` is left as it was
  before the install

### Requirement: Release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://github.com/lxc/distrobuilder/releases/latest redirects to at build time, which upstream marks as latest on
GitHub; any other value is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `3.3.1`, with or without
a leading `v`. Earlier releases carry tags and archive names of another form.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the latest-release link's redirect over HTTPS without following it, and installs the release the
  redirect names

### Requirement: Version rejection

The feature SHALL reject a `version` value that is neither `latest` nor such a release version before downloading
anything, and SHALL fail before downloading any archive when `latest` resolves to a tag that is not such a release
version.

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the latest-release link points to a tag that is not a release version at or above `3.3.1`
- **THEN** the install fails before downloading any archive, with a message naming the tag

### Requirement: Release metadata trust

The feature SHALL rely on TLS alone for the latest-release link, which upstream does not sign: a tampered redirect can
select another signed release at or above the minimum, never unsigned source.

#### Scenario: Latest resolved to a signed release

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** the release the redirect names is verified against its signature like an explicit version

### Requirement: Release source

The feature SHALL download, from `https://github.com/lxc/distrobuilder/releases/download/v<version>/`, the source
archive `distrobuilder-<version>.tar.gz` and its detached signature `distrobuilder-<version>.tar.gz.asc`, where
`<version>` has no leading `v`, over HTTPS on every hop including redirects.

#### Scenario: Redirect to a plain HTTP URL

- **WHEN** a URL the feature requests redirects to a URL whose scheme is not HTTPS
- **THEN** the install fails without requesting the redirect's target

### Requirement: Release signature

The feature SHALL fetch the public keys of upstream's release manager from `https://github.com/stgraber.gpg` and use the
archive only when its signature is a good OpenPGP signature by the key whose primary fingerprint is
`602F567663E593BCBD14F338C638974D64792D67`, verified in a keyring used for this install alone. The key file relies on
TLS alone, which does not weaken the check: only the pinned fingerprint is accepted.

#### Scenario: Signature by the pinned key

- **WHEN** the archive carries a good signature by the pinned key
- **THEN** the feature builds distrobuilder from that archive

#### Scenario: Signature by another key

- **WHEN** the archive carries a good signature by a key whose primary fingerprint differs from the pinned one, whether
  or not the fetched key file holds that key
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/distrobuilder` is left as it
  was before the install

#### Scenario: Invalid or missing signature

- **WHEN** the archive was altered after signing, or the release has no signature file for it
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/distrobuilder` is left as it
  was before the install

### Requirement: Go toolchain for the build

The feature SHALL build with the Go release that the `go` line of the verified source's `go.mod` names, downloaded as
`https://dl.google.com/go/go<go-version>.linux-<arch>.tar.gz` from the host the Go project's download page serves its
releases from. It SHALL fetch the checksum the Go project publishes beside the archive, at the same URL with `.sha256`
appended, and use the archive only when its SHA-256 digest equals it.

#### Scenario: Toolchain verified

- **WHEN** the archive's SHA-256 digest equals the published checksum
- **THEN** the build uses that toolchain

#### Scenario: Digest mismatch or missing checksum

- **WHEN** the archive's digest differs from the published checksum, or the checksum cannot be fetched
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/distrobuilder` is left as it
  was before the install

### Requirement: No toolchain left in the image

The toolchain SHALL be unpacked in a directory used for this install alone and removed, with the source and the build
cache, before the install ends. The feature SHALL leave no Go toolchain in the image and SHALL NOT use or change one the
image holds.

#### Scenario: No toolchain left

- **WHEN** the feature has been installed on an image without Go
- **THEN** `go` is not on `PATH`, and the source, the toolchain, and the build cache are gone

#### Scenario: Image with its own Go

- **WHEN** the feature is installed on an image that holds a Go toolchain
- **THEN** that toolchain is as it was before the install

### Requirement: Build from the verified source only

The feature SHALL build distrobuilder from the modules vendored in the verified source archive, with the build tags
upstream's `Makefile` sets, and SHALL make the Go toolchain download nothing: no module, and no other toolchain. The
build SHALL fail when the source needs anything the archive does not hold.

#### Scenario: Offline build

- **WHEN** the source archive and the toolchain have been verified
- **THEN** the build contacts no module proxy, checksum database, or source repository

### Requirement: Prerequisites from configured repositories

The feature SHALL install what the download and the build need (curl, CA certificates, GnuPG, tar, gzip, a C compiler,
and the C library's headers), only when the image lacks them, from the package repositories the image already configures
and without recommended packages. It SHALL add no package repository or signing key. What it installs this way stays in
the image.

#### Scenario: Minimal image

- **WHEN** the feature is installed with default options on an image that lacks curl, GnuPG, and a C compiler
- **THEN** the install succeeds

### Requirement: Tools for container images

The feature SHALL install, under the same rules, the tools distrobuilder runs to build container images: debootstrap,
GnuPG, rsync, the SquashFS tools, and xz.

#### Scenario: Tools present

- **WHEN** the feature has been installed with default options
- **THEN** `debootstrap`, `rsync`, `gpg`, `mksquashfs`, and `xz` are on root's `PATH`

### Requirement: Option vmSupport

The feature SHALL accept the option `vmSupport` as declared here: `true` installs, from the image's repositories, the
tools `distrobuilder build-incus --vm` runs. The option installs tools only; building a virtual machine image also needs
a privileged container (Requirement: What needs a privileged container).

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted vmSupport

- **WHEN** the feature is installed without `vmSupport` on an image that holds none of these tools
- **THEN** the feature installs none of them

#### Scenario: vmSupport enabled

- **WHEN** the feature is installed with `vmSupport` `true`
- **THEN** `mkfs.btrfs`, `mkfs.vfat`, `mkfs.ext4`, `sgdisk`, `qemu-img`, and `udevadm` are on root's `PATH`

#### Scenario: Virtual machine image in a privileged container

- **WHEN** `vmSupport` is `true`, the developer has declared the container privileged, and root runs
  `distrobuilder build-incus --vm` on an image definition that builds a virtual machine image
- **THEN** the command exits 0 and writes a disk image

### Requirement: Option windowsSupport

The feature SHALL accept the option `windowsSupport` as declared here: `true` installs, from the image's repositories,
the tools `distrobuilder repack-windows` runs. The option installs tools only; repacking also needs a privileged
container (Requirement: What needs a privileged container).

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted windowsSupport

- **WHEN** the feature is installed without `windowsSupport` on an image that holds none of these tools
- **THEN** the feature installs none of them

#### Scenario: windowsSupport enabled

- **WHEN** the feature is installed with `windowsSupport` `true`
- **THEN** `hivexregedit`, `wimlib-imagex`, and `genisoimage` are on `PATH`

### Requirement: Container privileges

The feature SHALL declare the capability `SYS_ADMIN` and the security option `apparmor=unconfined`, and nothing else
that widens the container: distrobuilder creates namespaces and mounts file systems as soon as it starts, which a
default container forbids, and Docker's default AppArmor profile forbids mounting also where the capability is held.
This is enough to build container images.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it holds the capability `SYS_ADMIN`, runs without an AppArmor profile, and is not privileged

### Requirement: What needs a privileged container

Building a virtual machine image and repacking Windows media need loop devices, which a feature cannot request singly,
so they need a privileged container, which the developer declares or another feature of the configuration brings.
`NOTES.md` SHALL state it.

#### Scenario: Virtual machine image without privilege

- **WHEN** root runs `distrobuilder build-incus --vm` in a container that declares nothing beyond the feature
- **THEN** the command fails for lack of a loop device

### Requirement: Capability risk

A process with `SYS_ADMIN` and no AppArmor profile is not confined against the host. The feature SHALL accept this risk:
the tool cannot run with less, the setting is visible in the feature's metadata, and it leaves the system call filter,
the masked system paths, and the device restrictions in place, unlike `privileged`. `NOTES.md` SHALL state the risk.

#### Scenario: Notes state the risk

- **WHEN** a developer reads the feature's `NOTES.md`
- **THEN** it says that the container holds `SYS_ADMIN` without an AppArmor profile and is not confined against its host

### Requirement: Nothing beyond the tool

The feature SHALL start no process at container start; SHALL declare no mount, entrypoint, lifecycle command, or
container environment variable; SHALL NOT write any file under a user's home directory or edit shell startup files; and
SHALL NOT give any user a way to run distrobuilder as root. distrobuilder refuses to run as another user, so a remote
user who is not root needs the image's own `sudo`; `NOTES.md` SHALL state it.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds a `.gnupg` directory that holds a file or a Go directory, and
  the image's `sudo` configuration is as it was before the install

### Requirement: Second install

Installing the feature a second time on the same image SHALL succeed. When the recorded release equals the selected one
and `/usr/local/bin/distrobuilder` exists, the feature SHALL download and build nothing; otherwise the later install's
release SHALL replace the earlier one. The later install SHALL add the tools its options ask for and SHALL NOT remove
those an earlier install added.

#### Scenario: Same release twice

- **WHEN** the feature is installed twice with the same explicit `version`
- **THEN** the second install downloads no source archive and no toolchain, and the executable is unchanged

#### Scenario: Another release

- **WHEN** the feature is installed with `version` `3.3.1` and then with `version` `3.4.0`
- **THEN** `distrobuilder --version` prints `3.4.0`, and the recorded release is `3.4.0`

#### Scenario: Other tool options

- **WHEN** the feature is installed with `vmSupport` `true` and then with defaults
- **THEN** the second install succeeds and `qemu-img` is still on `PATH`
