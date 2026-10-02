# Spec Delta

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

## ADDED Requirements

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

The feature SHALL download the release archive only from
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip` over HTTPS, where `<target>` is
`x86_64-unknown-linux-gnu` on amd64 and `aarch64-unknown-linux-gnu` on arm64. Before extracting it, the feature SHALL
verify the archive against the SHA-256 checksum published at
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`. Before installing the
extracted `deno` executable, the feature SHALL verify it against the SHA-256 checksum published at
`https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`. Deno publishes no signature for
the checksum files, so the feature SHALL rely on TLS alone for them, over HTTPS on every hop, redirects included. The
feature SHALL NOT install a release that does not publish both checksum files.

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

The feature SHALL set `DENO_INSTALL_ROOT` to `/usr/local/share/deno` in the container environment and SHALL put
`/usr/local/share/deno/bin` on `PATH` there, so that executables created with `deno install --global` land in that
directory and run by name in every shell. `/usr/local/share/deno/bin` SHALL come after the image's own `PATH` entries.
Because a login shell's startup files may reset `PATH` (Debian's `/etc/profile` does), the feature SHALL also append the
directory to `PATH` in login shells through a file of its own under `/etc/profile.d/`, adding it only when it is not
already there. When the remote user exists at build time and is not root, the feature SHALL make `/usr/local/share/deno`
and `/usr/local/share/deno/bin` writable by that user without elevated privileges, also after the Dev Container CLI
changes that user's UID or GID to match the host; otherwise it SHALL leave them owned by root.

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

On an image that lacks `curl`, `unzip`, or a CA certificate bundle, the feature SHALL install the missing ones with the
package manager of the image's family (`apt-get` for the Debian family, `dnf` for the Fedora family, `zypper` for the
openSUSE family), SHALL leave them installed, and SHALL leave no repository metadata or downloaded package in that
package manager's cache. A CA certificate bundle is present when `/etc/ssl/certs/ca-certificates.crt`,
`/etc/pki/tls/certs/ca-bundle.crt`, `/etc/ssl/ca-bundle.pem`, or `/etc/ssl/cert.pem` is a non-empty file. On an image
that has all three, the feature SHALL install and remove no package. When one is missing and the image lacks its
family's package manager, the feature SHALL fail before downloading anything, with a message naming what is missing and
the package manager it needs.

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

The feature SHALL support the images listed in `test/deno/compatibility.json`, and SHALL install only on images with
Bash already installed and glibc 2.27 or newer, on amd64 or arm64, whose `/etc/os-release` places them in a supported
family: the Debian family (`debian` or `ubuntu`), the Fedora family (`fedora`, `rhel`, or `centos`), or the openSUSE
family (`opensuse`). The first word of `ID`, then of `ID_LIKE`, that names a family decides it. Images without Bash are
unsupported; the feature SHALL NOT install Bash. On other unsupported images with Bash it SHALL fail before downloading
anything, with a message naming what is unsupported.

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
