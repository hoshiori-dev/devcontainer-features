# deno Specification

## Purpose

Installs the Deno CLI, a JavaScript, TypeScript, and WebAssembly runtime, as a system-wide `deno` executable at a chosen
or the latest release, with a shared location on `PATH` for tools installed with `deno install --global`.

Upstream sources:

- Home: https://github.com/denoland/deno
- Releases and changelog: https://github.com/denoland/deno/releases
- Documentation: https://docs.deno.com/runtime/
- Installation guide: https://docs.deno.com/runtime/getting_started/installation/
- Environment variables: https://docs.deno.com/runtime/reference/env_variables/
- Stability and release channels: https://docs.deno.com/runtime/fundamentals/stability_and_releases/

## Requirements

### Requirement: Deno on PATH for every user

The feature SHALL install the Deno CLI as `/usr/local/bin/deno`, executable by every user, so that `deno` runs by name
for the remote user and for root.

#### Scenario: Remote user and root

- **WHEN** the feature is installed
- **THEN** `deno --version` runs by name as the remote user and as root

### Requirement: Option version

The feature SHALL accept the option `version` as declared here, with the value `latest` or an exact `MAJOR.MINOR.PATCH`
release version, and SHALL fail the installation on any other value before anything is downloaded, with a message naming
the option and the accepted forms.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `deno --version`, run as the remote user, reports the version the latest-release pointer named at build time

#### Scenario: Exact version

- **WHEN** the feature is installed with `version` set to an exact release version such as `2.9.7`
- **THEN** `deno --version` reports that version when run as the remote user and when run as root

#### Scenario: Partial version rejected

- **WHEN** the feature is installed with `version` set to `2.9`
- **THEN** the installation fails with a message naming `version` and the accepted forms, and nothing is downloaded or
  installed

### Requirement: Resolving latest

The feature SHALL resolve `latest` by reading `https://dl.deno.land/release-latest.txt` over HTTPS and SHALL use its
content only when it has the form `v<MAJOR>.<MINOR>.<PATCH>` once surrounding whitespace is removed. Deno publishes no
checksum or signature for the pointer, so the feature SHALL rely on TLS alone for it, over HTTPS on every hop, redirects
included; the release it names is verified like any other.

#### Scenario: Malformed latest-release pointer

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release pointer returns content that
  is not of the form `v<MAJOR>.<MINOR>.<PATCH>`
- **THEN** the installation fails with a message showing the content it received, and no release archive is downloaded

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

### Requirement: Failed installation leaves the previous Deno

When an installation fails, the feature SHALL leave any `/usr/local/bin/deno` that existed before it unchanged, and
SHALL leave behind no partially written executable and no file it downloaded itself. Prerequisite packages installed
before the failure MAY remain.

#### Scenario: Failure over an existing installation

- **WHEN** Deno is already installed by this feature and a later installation of the feature fails at any point
- **THEN** `deno --version` still reports the earlier version, and no file from the failed attempt remains in
  `/usr/local/bin` or in a temporary directory

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

### Requirement: Update check disabled

The feature SHALL set `DENO_NO_UPDATE_CHECK` to `1` in the container environment, because the feature, not Deno, manages
the installed version.

#### Scenario: Update check off in the container

- **WHEN** a shell starts in a container with the feature installed
- **THEN** `DENO_NO_UPDATE_CHECK` is `1` in its environment

### Requirement: Prerequisite packages

The feature SHALL install missing download prerequisites and leave no repository metadata or downloaded package in the
package manager's cache.

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

The feature SHALL support the images listed in `test/deno/compatibility.json`.

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

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. When the installed Deno already reports the
version the second installation resolves, the feature SHALL keep it without downloading it again. When the second
installation resolves a different version, that version SHALL replace the earlier one. In both cases the feature SHALL
keep `/usr/local/share/deno` and every tool installed there.

#### Scenario: Same version the second time

- **WHEN** `/usr/local/bin/deno` already reports an exact version and the feature is installed with `version` set to
  that version
- **THEN** the installation succeeds, leaves `/usr/local/bin/deno` unchanged, and reports that the version is already
  installed

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an exact version and then again with `version` set to
  `latest`, which resolves to a different version
- **THEN** both installations succeed and `deno --version` reports the version `latest` resolved to

#### Scenario: Global tools survive a reinstall

- **WHEN** `/usr/local/share/deno/bin` holds a tool, such as one created with `deno install --global`, and the feature
  is installed again, with the same or a different `version`
- **THEN** the tool is still in `/usr/local/share/deno/bin` and runs by name

### Requirement: Companion editor extension

The feature SHALL request `denoland.vscode-deno` through VS Code customizations and the official JetBrains `deno` plugin
through JetBrains customizations. It SHALL declare no editor settings or IDE backend and SHALL leave CLI installation
behavior independent of editor choice.

#### Scenario: Companion extension declaration

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** the extension list requests `denoland.vscode-deno`
- **AND** the feature declares no editor settings or IDE backend

#### Scenario: JetBrains companion declaration

- **WHEN** a supporting JetBrains client reads the feature customizations
- **THEN** its plugin list requests `deno` without selecting an IDE backend

### Requirement: Project-controlled editor activation

`NOTES.md` SHALL explain project-controlled Deno activation, including partial activation in mixed Node/Deno workspaces,
and use of the supplied official JetBrains Deno plugin. It SHALL distinguish project examples from configuration
supplied by the feature.

#### Scenario: Project-controlled activation

- **WHEN** a developer reads the editor guidance
- **THEN** it offers `deno.enable` for a Deno project and `deno.enablePaths` for selected mixed-project directories
- **AND** it identifies the supplied JetBrains plugin and leaves compatible IDE backend selection to the project
- **AND** it does not claim that installing the feature enables Deno language services throughout the workspace

### Requirement: Documented extension exclusion

`NOTES.md` SHALL document the VS Code mechanism for excluding the feature's default extension using
`-denoland.vscode-deno` in the consuming project's customization. The guidance SHALL describe exclusion from automatic
installation rather than claiming to uninstall an already installed extension.

#### Scenario: Documented extension exclusion

- **WHEN** a developer wants the CLI without its VS Code companion extension
- **THEN** the notes provide a project configuration example using `-denoland.vscode-deno`
- **AND** they explain that exclusion does not uninstall an existing extension

### Requirement: Deno release archive selection

The feature SHALL download the release archive only from
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip` over HTTPS, where `<target>` is
`x86_64-unknown-linux-gnu` on amd64 and `aarch64-unknown-linux-gnu` on arm64.

#### Scenario: Architecture selects archive target

- **WHEN** Deno is installed on amd64 or arm64
- **THEN** the feature downloads the archive for the matching `<target>` from the stated HTTPS release URL

### Requirement: Deno archive checksum

Before extracting the release archive, the feature SHALL verify the archive against the SHA-256 checksum published at
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`.

#### Scenario: Archive checksum is checked before extraction

- **WHEN** the feature has downloaded a Deno release archive
- **THEN** it verifies the archive against the release's `.zip.sha256sum` checksum before extracting it

### Requirement: Deno executable checksum

Before installing the extracted `deno` executable, the feature SHALL verify it against the SHA-256 checksum published at
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`.

#### Scenario: Executable checksum is checked before installation

- **WHEN** the archive is verified and extracted
- **THEN** the feature verifies the `deno` executable against the release's `deno-<target>.sha256sum` checksum before
  installing it

### Requirement: Deno checksum transport and availability

Deno publishes no signature for the checksum files, so the feature SHALL rely on TLS alone for them, over HTTPS on every
hop, redirects included. The feature SHALL NOT install a release that does not publish both checksum files.

#### Scenario: Missing checksum file

- **WHEN** a release does not publish both checksum files
- **THEN** the feature does not install that release

### Requirement: Deno global tool locations

The feature SHALL set `DENO_INSTALL_ROOT` to `/usr/local/share/deno` in the container environment and SHALL put
`/usr/local/share/deno/bin` on `PATH` there, so that executables created with `deno install --global` land in that
directory and run by name in every shell. `/usr/local/share/deno/bin` SHALL come after the image's own `PATH` entries.

#### Scenario: Global tool location in the container environment

- **WHEN** a shell starts in a container with the feature installed
- **THEN** `DENO_INSTALL_ROOT` is `/usr/local/share/deno` and `/usr/local/share/deno/bin` is on `PATH` after the image's
  own entries

### Requirement: Deno global tools in login shells

Because a login shell's startup files may reset `PATH` (Debian's `/etc/profile` does), the feature SHALL also append
`/usr/local/share/deno/bin` to `PATH` in login shells through a file of its own under `/etc/profile.d/`, adding it only
when it is not already there.

#### Scenario: Global tool path in login shell

- **WHEN** a login shell starts as the remote user, including on an image whose `/etc/profile` resets `PATH`
- **THEN** `/usr/local/share/deno/bin` appears in its `PATH` once, after the image's own entries, and tools created with
  `deno install --global` run by name

### Requirement: Deno global tool directory access

When the remote user exists at build time and is not root, the feature SHALL make `/usr/local/share/deno` and
`/usr/local/share/deno/bin` writable by that user without elevated privileges, also after the Dev Container CLI changes
that user's UID or GID to match the host; otherwise it SHALL leave them owned by root.

#### Scenario: Non-root UID or GID changes

- **WHEN** the remote user is a non-root user that exists at build time and the Dev Container CLI changes its UID or GID
  to match the host
- **THEN** that user can still write to `/usr/local/share/deno` and `/usr/local/share/deno/bin` without elevated
  privileges

### Requirement: Safe reuse of the Deno group

For a non-root remote user, an existing `deno` group SHALL be reused only when it has no supplementary members other
than that user and is not any account's primary group. A conflict SHALL fail before package installation or downloads,
with a message naming the conflicting account, without changing group membership or the tools directories.

#### Scenario: Deno group conflicts

- **WHEN** a non-root remote user exists and another account is a supplementary member of the existing `deno` group or
  uses its GID as its primary group
- **THEN** installation fails before package installation or downloads, names the conflicting account, and changes
  neither group membership nor the tools directories

### Requirement: Required Deno group commands

For a non-root remote user, the feature SHALL require `groupadd` only when the `deno` group does not exist yet, and
`usermod` only when that user is not yet a member of the `deno` group. When a command it requires is missing, the
feature SHALL fail before package installation or downloads, with a message naming the missing command, without changing
group membership or the tools directories.

#### Scenario: Required group command missing

- **WHEN** a non-root remote user exists and a `groupadd` or `usermod` command the feature requires is missing
- **THEN** installation fails before package installation or downloads, names the missing command, and changes neither
  group membership nor the tools directories

### Requirement: Deno prerequisite package handling

On an image that lacks `curl`, `unzip`, or a CA certificate bundle, the feature SHALL install the missing ones with the
package manager of the image's family (`apt-get` for the Debian family, `dnf` for the Fedora family, `zypper` for the
openSUSE family), SHALL leave them installed, and SHALL leave no repository metadata or downloaded package in that
package manager's cache.

#### Scenario: Missing prerequisite installed

- **WHEN** the feature is installed on a supported image that lacks `curl` and has its family's package manager
- **THEN** `curl` is installed with that package manager and stays installed, and that package manager's cache holds no
  repository metadata and no downloaded package

### Requirement: Deno missing package manager

When `curl`, `unzip`, or a CA certificate bundle is missing and the image lacks its family's package manager, the
feature SHALL fail before downloading anything, with a message naming what is missing and the package manager it needs.

#### Scenario: Missing prerequisite and package manager

- **WHEN** a prerequisite is missing and the image lacks its family's package manager
- **THEN** installation fails before downloading anything, with a message naming the missing prerequisite and the
  package manager it needs

### Requirement: Deno CA bundle detection

A CA certificate bundle is present when `/etc/ssl/certs/ca-certificates.crt`, `/etc/pki/tls/certs/ca-bundle.crt`,
`/etc/ssl/ca-bundle.pem`, or `/etc/ssl/cert.pem` is a non-empty file. On an image that has `curl`, `unzip`, and a CA
certificate bundle, the feature SHALL install and remove no package.

#### Scenario: Prerequisites already exist

- **WHEN** the image has `curl`, `unzip`, and a non-empty file at one of those CA certificate bundle paths
- **THEN** the feature installs and removes no package

### Requirement: Deno supported runtime platforms

The feature SHALL install only on images with Bash already installed and glibc 2.27 or newer, on amd64 or arm64, whose
`/etc/os-release` places them in a supported family: the Debian family (`debian` or `ubuntu`), the Fedora family
(`fedora`, `rhel`, or `centos`), or the openSUSE family (`opensuse`). The first word of `ID`, then of `ID_LIKE`, that
names a family decides it.

#### Scenario: Family decided by ID_LIKE

- **WHEN** the feature is installed on an image whose `/etc/os-release` has an `ID` that names no supported family and
  an `ID_LIKE` whose first family-naming word is `debian`
- **THEN** the feature treats the image as Debian family

### Requirement: Deno unsupported images

Images without Bash are unsupported; the feature SHALL NOT install Bash. On other unsupported images with Bash it SHALL
fail before downloading anything, with a message naming what is unsupported.

#### Scenario: Image without Bash

- **WHEN** the feature is installed on an image without Bash
- **THEN** the feature does not install Bash

#### Scenario: Unsupported image with Bash

- **WHEN** the feature is installed on an image with Bash whose glibc is older than 2.27, whose architecture is neither
  amd64 nor arm64, or whose `/etc/os-release` names no supported family
- **THEN** the installation fails before downloading anything, with a message naming what is unsupported
