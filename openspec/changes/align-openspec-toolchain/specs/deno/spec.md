# Spec Delta

## MODIFIED Requirements

### Requirement: Verified download from GitHub releases

The feature SHALL download and verify Deno release artifacts before installing the executable.

#### Scenario: Archive checksum mismatch

- **WHEN** the downloaded archive does not match the checksum in its `.zip.sha256sum` file
- **THEN** the installation fails with a message naming the archive, and nothing is extracted or installed

#### Scenario: Executable checksum mismatch

- **WHEN** the extracted `deno` executable does not match the checksum in the release's `deno-<target>.sha256sum` file
- **THEN** the installation fails with a message naming the executable, and it is not installed

#### Scenario: Release without both checksum files

- **WHEN** the feature is installed with `version` set to a release whose archive exists but which lacks one or both
  checksum files, such as `2.5.0`, `2.0.0`, or `1.46.3`
- **THEN** the installation fails with a message naming each missing checksum file, and nothing is installed

#### Scenario: Unknown version

- **WHEN** the feature is installed with `version` set to a version for which Deno published no archive for the image's
  architecture, such as `9.9.9`
- **THEN** the installation fails with a message naming the requested version, and nothing is installed

### Requirement: Shared location for global tools

The feature SHALL provide a shared location for globally installed Deno tools, available by name in every shell.

#### Scenario: Existing group belongs to another account

- **WHEN** a non-root remote user exists and another account is a supplementary member of `deno` or uses its GID as its
  primary group
- **THEN** installation fails before package installation or downloads, names the conflicting account, and leaves group
  membership and the tools directories unchanged

#### Scenario: Remote user has deno as its primary group

- **WHEN** a non-root remote user exists and uses the existing `deno` group's GID as its primary group
- **THEN** installation fails before package installation or downloads, explains the primary-group conflict, and leaves
  group membership and the tools directories unchanged

#### Scenario: Existing group is reserved for the feature

- **WHEN** an existing `deno` group is no account's primary group and has no supplementary members other than the
  non-root remote user
- **THEN** installation succeeds, including when that group is empty, and the user retains tools access after UID/GID
  remapping and a reinstall

#### Scenario: Group command missing

- **WHEN** a non-root remote user exists, and the image lacks `groupadd` while no `deno` group exists, or lacks
  `usermod` while that user is not a member of the `deno` group
- **THEN** installation fails before package installation or downloads, names the missing command, and leaves group
  membership and the tools directories unchanged

#### Scenario: Group prepared in the image

- **WHEN** a non-root remote user is already the only supplementary member of a `deno` group that is no account's
  primary group, and the image lacks both `groupadd` and `usermod`
- **THEN** installation succeeds and that user installs a global tool with `deno install --global` without elevated
  privileges

#### Scenario: Non-root remote user installs a global tool

- **WHEN** the remote user is a non-root user that exists at build time and runs `deno install --global` on a local
  script
- **THEN** the command succeeds without elevated privileges, the executable appears in `/usr/local/share/deno/bin`, and
  it runs by name from a new shell

#### Scenario: Remote user's UID changed after the build

- **WHEN** the remote user is a non-root user that exists at build time, and its UID and GID are changed after the
  build, as the Dev Container CLI's `updateRemoteUserUID` does to match the host
- **THEN** that user still installs a global tool with `deno install --global` without elevated privileges, and the tool
  runs by name from a new shell

#### Scenario: Login shell runs a global tool

- **WHEN** a global tool is installed with `deno install --global` and a login shell (`bash -l`) is started as the
  remote user, on an image whose `/etc/profile` resets `PATH`
- **THEN** the tool runs by name in that login shell, and `/usr/local/share/deno/bin` appears in its `PATH` once, after
  the image's own entries

#### Scenario: Root or absent remote user

- **WHEN** the remote user is root, or does not exist when the feature is installed
- **THEN** the installation succeeds and `/usr/local/share/deno` is owned by root

### Requirement: Prerequisite packages

The feature SHALL ensure required download prerequisites are installed and leave package-manager caches clean.

#### Scenario: Debian-family image without the prerequisites

- **WHEN** the feature is installed on a Debian-family image that has neither `curl`, `unzip`, nor a CA certificate
  bundle
- **THEN** the installation succeeds, all three are present afterwards, and apt's package lists hold no package index

#### Scenario: Fedora-family image without unzip

- **WHEN** the feature is installed on a Fedora-family image that has `dnf`, `curl`, and a CA certificate bundle but
  lacks `unzip`
- **THEN** the installation succeeds, `unzip` is present afterwards, and dnf's cache holds no repository metadata and no
  downloaded package

#### Scenario: openSUSE-family image without unzip

- **WHEN** the feature is installed on an openSUSE-family image that has `zypper`, `curl`, and a CA certificate bundle
  but lacks `unzip`
- **THEN** the installation succeeds, `unzip` is present afterwards, and zypper's cache holds no file

#### Scenario: Image with the prerequisites

- **WHEN** the feature is installed on a supported image that already has `curl`, `unzip`, and a CA certificate bundle
- **THEN** the set of installed packages is unchanged

#### Scenario: Package manager missing

- **WHEN** the feature is installed on an image of a supported family that lacks `unzip` and lacks that family's package
  manager, such as a Fedora-family image whose only package manager is `microdnf`
- **THEN** the installation fails with a message naming `unzip` and the package manager it needs, and nothing is
  downloaded

### Requirement: Supported platforms

The feature SHALL support only the platforms declared in `test/deno/compatibility.json` that meet its runtime
prerequisites.

#### Scenario: musl-based image

- **WHEN** the feature is installed on an image with Bash whose C library is musl
- **THEN** the installation fails with a message stating that Deno publishes glibc builds only, and nothing is
  downloaded

#### Scenario: C library not identified

- **WHEN** the feature is installed on an image with Bash that is not musl-based and on which `getconf GNU_LIBC_VERSION`
  reports no glibc version, such as an image without `getconf`
- **THEN** the installation fails with a message stating that the C library could not be identified and that Deno needs
  glibc 2.27 or newer, and nothing is downloaded

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a glibc-based image whose `/etc/os-release` names none of the supported families,
  such as Arch Linux
- **THEN** the installation fails with a message naming the distribution and the supported families, and nothing is
  downloaded

#### Scenario: glibc older than 2.27

- **WHEN** the feature is installed on an image of a supported family whose glibc is older than 2.27
- **THEN** the installation fails with a message naming the glibc version found and the minimum, and nothing is
  downloaded

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an image whose architecture is neither amd64 nor arm64
- **THEN** the installation fails with a message naming the architecture, and nothing is downloaded

## ADDED Requirements

### Requirement: Deno release archive selection

The feature SHALL fetch only `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip` over
HTTPS, where amd64 maps to `x86_64-unknown-linux-gnu` and arm64 to `aarch64-unknown-linux-gnu`.

#### Scenario: Architecture selects archive target

- **WHEN** Deno is installed on amd64 or arm64
- **THEN** the feature requests the matching target archive from the stated HTTPS release URL

### Requirement: Deno archive checksum

Before extraction, the feature SHALL verify the archive's SHA-256 against
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`.

#### Scenario: Archive checksum is checked before extraction

- **WHEN** the feature receives a Deno archive
- **THEN** it verifies the archive against the release checksum before extracting it

### Requirement: Deno executable checksum

Before installation, the feature SHALL verify the extracted `deno` executable's SHA-256 against
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`.

#### Scenario: Executable checksum is checked before installation

- **WHEN** the archive is verified and extracted
- **THEN** the feature verifies the executable against its release checksum before installing it

### Requirement: Deno checksum transport and availability

Checksum files have no upstream signature, so the feature SHALL rely on TLS alone for them and use HTTPS on every
request and redirect. It SHALL NOT install a release that omits either checksum file.

#### Scenario: Missing checksum file

- **WHEN** a release lacks either required checksum file
- **THEN** the feature refuses to install that release

### Requirement: Deno global tool locations

The feature SHALL set `DENO_INSTALL_ROOT=/usr/local/share/deno` and expose `/usr/local/share/deno/bin` on the container
`PATH` after image entries. It SHALL append that directory in login shells through its own `/etc/profile.d/` file when
absent, because startup files may reset `PATH`.

#### Scenario: Global tool path in login shell

- **WHEN** a login shell starts, including one whose system profile resets `PATH`
- **THEN** the Deno bin directory appears once after image entries and global Deno tools run by name

### Requirement: Deno global tool directory access

When the remote user exists and is non-root, the feature SHALL make `/usr/local/share/deno` and its `bin` writable by
that user without elevation, including after Dev Container CLI UID or GID changes. Otherwise both directories SHALL
remain root-owned.

#### Scenario: Non-root UID or GID changes

- **WHEN** the existing non-root remote user's UID or GID changes to match the host
- **THEN** the user can still write globally installed Deno tools without elevation

### Requirement: Safe reuse of the Deno group

For a non-root remote user, an existing `deno` group SHALL be reused only if it has no supplementary member other than
that user and is not any account's primary group. A conflict SHALL fail before package installation or downloads, name
the conflicting account, and leave group membership and tool directories unchanged.

#### Scenario: Deno group conflicts

- **WHEN** another account is a supplementary or primary member of the existing `deno` group
- **THEN** installation fails before packages or downloads, names the conflicting account, and changes neither
  membership nor tool directories

### Requirement: Required Deno group commands

For a non-root remote user, the feature SHALL require `groupadd` only when `deno` does not exist, and `usermod` only
when the user is not already a member. A missing required command SHALL fail before packages or downloads, name the
command, and leave membership and tool directories unchanged.

#### Scenario: Required group command missing

- **WHEN** a required `groupadd` or `usermod` command is unavailable
- **THEN** installation fails before packages or downloads, names the command, and changes neither membership nor tool
  directories

### Requirement: Deno prerequisite package handling

When `curl`, `unzip`, or a CA bundle is missing, the feature SHALL install only missing prerequisites with `apt-get` for
the Debian/Ubuntu family, `dnf` for Fedora, or `zypper` for openSUSE. It SHALL leave installed packages in place and
clean fetched repository metadata and packages from cache. When a prerequisite is missing and its manager is
unavailable, the feature SHALL fail before downloads and name both.

#### Scenario: Missing prerequisite and package manager

- **WHEN** a prerequisite is missing and the image lacks its family's package manager
- **THEN** installation fails before downloads and names the prerequisite and required manager

### Requirement: Deno CA bundle detection

A CA bundle is present when any of `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`,
`/etc/ssl/ca-bundle.pem`, or `/etc/ssl/cert.pem` is a non-empty file. When `curl`, `unzip`, and a CA bundle all exist,
the feature SHALL install and remove no package.

#### Scenario: Prerequisites already exist

- **WHEN** all download prerequisites are present
- **THEN** the feature installs and removes no package

### Requirement: Deno supported runtime platforms

The feature SHALL require Bash, glibc 2.27 or newer, amd64 or arm64, and a Debian (`debian` or `ubuntu`), Fedora
(`fedora`, `rhel`, or `centos`), or openSUSE (`opensuse`) family identified by the first matching word in `ID`, then
`ID_LIKE`. It SHALL NOT install Bash. Unsupported images with Bash fail before downloads and name the unsupported
condition; supported images are listed in `test/deno/compatibility.json`.

#### Scenario: Unsupported Deno runtime

- **WHEN** Bash is absent, glibc is older than 2.27, architecture is unsupported, or no supported family matches
- **THEN** the feature does not install Bash and fails before downloads naming the unsupported condition
