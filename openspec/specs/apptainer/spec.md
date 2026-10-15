# apptainer Specification

## Purpose

Installs Apptainer, the container runtime of HPC systems, in its unprivileged non-setuid form from the distribution,
EPEL, the project's PPA, or the GitHub release, together with the container security options under which an unprivileged
user can run it inside a dev container.

Upstream sources:

- Home and source: https://github.com/apptainer/apptainer
- Releases and changelog: https://github.com/apptainer/apptainer/releases
- Admin guide: https://apptainer.org/docs/admin/latest/
- User guide: https://apptainer.org/docs/user/latest/
- Slurm container support: https://slurm.schedmd.com/containers.html

## Requirements

### Requirement: Supported images

The feature SHALL install on the distributions and architectures listed in `test/apptainer/compatibility.json`. On a
distribution whose `/etc/os-release` identifies none of the supported families, or on a family and architecture for
which no source below exists, the install SHALL fail before changing the image, with a message naming the detected
distribution and architecture.

#### Scenario: Supported image

- **WHEN** the feature is installed on an image listed in `test/apptainer/compatibility.json`
- **THEN** the build succeeds and `apptainer --version` reports a version

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose distribution is not supported, or on Debian for an architecture
  the GitHub release has no package for
- **THEN** the build fails with a message naming the detected distribution and architecture, and installs nothing

### Requirement: Packages from the distribution

The feature SHALL install `apptainer` from one source per family: Fedora's configured repositories, EPEL on a RHEL
derivative, the project's PPA on Ubuntu, and the GitHub release on Debian, as the requirements of those names state. A
repository source is used with the package manager's signature verification in effect, and nothing is downloaded at
build time but the packages, the PPA key, and the Debian release asset.

#### Scenario: Fedora

- **WHEN** the feature is installed on a Fedora image
- **THEN** `apptainer --version` reports the version Fedora ships, and the image's repository and key configuration is
  unchanged

#### Scenario: Package verification fails

- **WHEN** the package manager rejects a package or repository signature during the install
- **THEN** the build fails and the feature does not retry with verification disabled

### Requirement: EPEL on RHEL derivatives

On a RHEL derivative, the feature SHALL install `apptainer` from EPEL. When no EPEL repository is configured, it SHALL
install the distribution's `epel-release` package from the repositories configured in the image and SHALL verify the key
that package delivers as Requirement: EPEL signing key states before any EPEL package is installed; when that package is
unavailable, the install SHALL fail naming EPEL before changing the image.

#### Scenario: EPEL enabled on a RHEL derivative

- **WHEN** the feature is installed on a RHEL-derivative image of the compatibility list without EPEL configured
- **THEN** EPEL is configured from the distribution's `epel-release` package, `apptainer --version` reports the version
  EPEL ships, and the `epel` repository has package signature checking on

#### Scenario: EPEL already configured

- **WHEN** the feature is installed on a RHEL-derivative image where EPEL is already configured
- **THEN** the install adds no repository and installs `apptainer` from the configured EPEL

### Requirement: EPEL signing key

When the feature enables EPEL, it SHALL trust it only when the key file the `epel-release` package installs for that
release holds exactly one primary key whose full fingerprint equals the pinned one: EPEL 9,
`FF8AD1344597106ECE813B918A3872BF3228467C`. A release without a pinned fingerprint SHALL fail the install naming the
release. The feature SHALL NOT import a key from any other source.

#### Scenario: Key matches

- **WHEN** the `epel-release` package installs the EPEL 9 key with the pinned fingerprint
- **THEN** the install continues and EPEL packages are verified by the package manager with that key

#### Scenario: Key mismatch

- **WHEN** the key file holds a key with another fingerprint, or more than one primary key
- **THEN** the build fails naming the fingerprint found, and no EPEL package is installed

#### Scenario: Unpinned release

- **WHEN** the feature is installed on a RHEL derivative without EPEL configured whose EPEL release has no pinned
  fingerprint
- **THEN** the build fails naming the release, and no EPEL package is installed

### Requirement: PPA on Ubuntu

On Ubuntu the feature SHALL install `apptainer` from the project's PPA at
`https://ppa.launchpadcontent.net/apptainer/ppa/ubuntu`, for the image's release codename, through a source definition
the feature writes whole at a fixed path with `signed-by` naming a feature-owned keyring that holds only the key
Requirement: PPA signing key verifies. The source SHALL use HTTPS, and the feature SHALL NOT use `add-apt-repository`.

#### Scenario: Ubuntu

- **WHEN** the feature is installed on an Ubuntu image of the compatibility list
- **THEN** `apptainer --version` reports the version the PPA ships for that release, and the source file names the PPA
  over HTTPS with `signed-by` pointing at the feature's keyring

#### Scenario: Release without PPA packages

- **WHEN** the feature is installed on an Ubuntu release for which the PPA publishes no `apptainer`
- **THEN** the build fails with the package manager's error, and no `apptainer` is installed

### Requirement: PPA signing key

The feature SHALL fetch the PPA's key over HTTPS from Ubuntu's keyserver at
`https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF6B0F5193D4F3301EF491FF0AFE36534FC6218AE` and SHALL use it only
when the file holds exactly one primary key whose full fingerprint is `F6B0F5193D4F3301EF491FF0AFE36534FC6218AE`; only
that key SHALL be exported into the keyring the source names.

#### Scenario: Key matches

- **WHEN** the fetched key holds exactly the pinned primary key
- **THEN** the install continues and the PPA's index is verified with that key

#### Scenario: Key mismatch

- **WHEN** the fetched file holds a key with another fingerprint, or more than one primary key
- **THEN** the build fails naming the fingerprint found, and no source and no keyring is written

### Requirement: GitHub release on Debian

On Debian for amd64, the feature SHALL download the `apptainer` `.deb` of the newest release of `apptainer/apptainer`,
as GitHub reports it, from that release's assets under `https://github.com/apptainer/apptainer/releases/download/`,
choosing the `trixie+` asset on Debian 13 and newer and the plain asset before, over HTTPS on every hop, and install it
with the package manager. An asset absent from the release SHALL fail the install naming it.

#### Scenario: Debian

- **WHEN** the feature is installed on a Debian image of the compatibility list on amd64
- **THEN** `apptainer --version` reports the newest release's version, and the package manager records the package as
  installed

#### Scenario: Release asset missing

- **WHEN** the newest release has no `.deb` asset for the image's Debian release
- **THEN** the build fails naming the asset, and nothing is installed

### Requirement: Unsigned Debian download

Upstream publishes no checksum or signature for the release's `.deb` assets, so the Debian download relies on TLS alone;
the risk is accepted because the GitHub release is the only package source for Debian. The feature MAY compare the asset
with the digest GitHub reports for it and SHALL NOT require one.

#### Scenario: Digest reported

- **WHEN** GitHub reports a digest for the downloaded asset and the file does not match it
- **THEN** the build fails naming the asset, and nothing is installed

#### Scenario: No digest reported

- **WHEN** GitHub reports no digest for the asset
- **THEN** the install continues with the downloaded file

### Requirement: Non-setuid installation

The feature SHALL install only the non-setuid Apptainer package and SHALL NOT install `apptainer-suid`; no file the
feature installs SHALL have the setuid bit, and `apptainer` SHALL report that it runs without setuid.

#### Scenario: No setuid helper

- **WHEN** the feature has been installed
- **THEN** no `apptainer-suid` package is installed, and no setuid file exists under Apptainer's library directory

### Requirement: Container security options

The feature SHALL declare `securityOpt` with exactly `seccomp=unconfined` and `apparmor=unconfined`, so that an
unprivileged process in the container can create user namespaces and mount inside them. It SHALL NOT change any host
setting; a host that forbids unprivileged user namespaces makes `apptainer` fail with Apptainer's own message.

#### Scenario: User namespace available

- **WHEN** a container built with the feature runs on a host that allows unprivileged user namespaces
- **THEN** an unprivileged user in it creates a user namespace with a mount namespace inside

#### Scenario: Host forbids user namespaces

- **WHEN** the host forbids unprivileged user namespaces
- **THEN** `apptainer exec` fails with Apptainer's message about user namespaces, and nothing else in the container is
  affected

### Requirement: Unprivileged execution

In a container built with the feature, on a host that allows unprivileged user namespaces, an unprivileged user SHALL be
able to build a sandbox directory from an OCI image and run commands in it, and to run a SIF image with `--unsquash`;
running a SIF image without `--unsquash` SHALL need `/dev/fuse` in the container, and `--fakeroot` is not supported.

#### Scenario: Sandbox directory

- **WHEN** an unprivileged user runs `apptainer build --sandbox` from a small OCI image and then `apptainer exec` on the
  directory
- **THEN** the command runs inside the sandbox and reports that image's distribution

#### Scenario: SIF without FUSE

- **WHEN** the container has no `/dev/fuse` and the user runs a SIF image with `--unsquash`, then without it
- **THEN** the first run succeeds and the second fails naming `/dev/fuse`

#### Scenario: SIF with FUSE

- **WHEN** the container was started with `/dev/fuse` and the user runs a SIF image without `--unsquash`
- **THEN** the run succeeds

### Requirement: Container metadata

The feature SHALL declare `securityOpt` as Requirement: Container security options states and nothing else that widens
the container: no `privileged`, `capAdd`, `mounts`, `entrypoint`, `init`, `containerEnv`, or lifecycle command, and no
`dependsOn` or `installsAfter`.

#### Scenario: Metadata of a built container

- **WHEN** a container is built with only this feature
- **THEN** it is not privileged, has no added capability, and its security options are exactly the two the feature
  declares

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed and leave the same result as one install: the
package installed once, the source definition and keyring (where the family has them) rewritten with the same content.
The feature has no options, so a second install cannot differ in options.

#### Scenario: Second install

- **WHEN** the feature is installed twice on the same image
- **THEN** the build succeeds, `apptainer --version` reports the same version, and the source definition exists once
