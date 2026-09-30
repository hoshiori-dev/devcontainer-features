# Spec Delta

## Purpose

Installs the NVIDIA Container Toolkit (`nvidia-ctk`, `nvidia-container-runtime`, and `libnvidia-container`) in a dev
container, so that a container engine running inside it can hand the host's GPUs to the containers it starts, and
optionally registers the NVIDIA runtime with a Docker daemon installed in the dev container.

Upstream sources:

- Home: https://github.com/NVIDIA/nvidia-container-toolkit
- Documentation: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/index.html
- Installation guide: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
- Supported platforms: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/supported-platforms.html
- Changelog: https://github.com/NVIDIA/nvidia-container-toolkit/blob/main/CHANGELOG.md

## ADDED Requirements

### Requirement: Install the toolkit from NVIDIA's stable repository

The feature SHALL install the packages `nvidia-container-toolkit`, `nvidia-container-toolkit-base`,
`libnvidia-container-tools`, and `libnvidia-container1`, all at the same version, from NVIDIA's stable package
repository for the image's package manager and architecture: on apt-based images from
`https://nvidia.github.io/libnvidia-container/stable/deb/<arch>` (`<arch>` being `amd64` or `arm64`), and on dnf- and
zypper-based images from `https://nvidia.github.io/libnvidia-container/stable/rpm/<arch>` (`<arch>` being `x86_64` or
`aarch64`). The feature SHALL leave that repository configured in the image and SHALL NOT configure NVIDIA's
experimental channel. The installed commands SHALL be on the default `PATH` of every user. The supported images are
those listed in `test/nvidia-container-toolkit/compatibility.json`.

#### Scenario: Default install on a supported image

- **WHEN** the feature is installed with default options on an image listed in
  `test/nvidia-container-toolkit/compatibility.json`
- **THEN** `nvidia-ctk --version` and `nvidia-container-cli --version` succeed for the dev container's remote user
- **AND** the package manager reports all four packages installed at one and the same version

#### Scenario: The repository stays configured

- **WHEN** the feature has been installed
- **THEN** the image's package manager lists NVIDIA's stable repository for the image's architecture as a configured
  source, so later package updates of the toolkit come from it

### Requirement: Trust only NVIDIA's pinned signing key

The feature SHALL download NVIDIA's repository signing key from `https://nvidia.github.io/libnvidia-container/gpgkey`
and SHALL use it only after verifying that the downloaded file contains exactly one primary key, whose full fingerprint
is `C95B321B61E88C1809C4F759DDCAE044F796ECB0`. The configured repository SHALL accept only content signed by that key:
on apt-based images the repository's signed index is checked against that key alone, and on dnf- and zypper-based images
both the repository metadata and every package are signature-checked against a local copy of that key. Neither the
feature nor the repository configuration it writes SHALL import or trust any key other than the verified copy of that
key.

#### Scenario: Key with the pinned fingerprint

- **WHEN** the downloaded key file holds exactly one primary key and its fingerprint is
  `C95B321B61E88C1809C4F759DDCAE044F796ECB0`
- **THEN** the feature configures the repository with that key and installs the packages

#### Scenario: Key with any other fingerprint

- **WHEN** the downloaded key file is missing or unreadable, holds more than one primary key, or its primary fingerprint
  differs from `C95B321B61E88C1809C4F759DDCAE044F796ECB0`
- **THEN** the feature fails the build with a message naming the expected fingerprint, before it configures NVIDIA's
  repository or installs any toolkit package

#### Scenario: Unsigned or wrongly signed repository content

- **WHEN** the repository index, the repository metadata, or a package is unsigned or not signed by the pinned key
- **THEN** the package manager refuses it and the feature fails the build

### Requirement: Choose the toolkit version

The `version` option SHALL select the toolkit version: `latest` installs the newest version that NVIDIA's stable
repository offers at build time, and a version of the form `MAJOR.MINOR.PATCH` installs exactly that version of all four
packages. The feature SHALL impose no minimum version: every `MAJOR.MINOR.PATCH` version the repository offers SHALL be
installed as requested, including releases with known vulnerabilities. Any other value, including a version with a
package release suffix such as `1.20.1-1`, SHALL fail the build.

#### Scenario: Latest version

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** `nvidia-ctk --version` reports the newest version in NVIDIA's stable repository at build time

#### Scenario: Exact version

- **WHEN** the feature is installed with `version` set to a version the repository offers, for example `1.19.1`
- **THEN** all four packages are installed at that version and `nvidia-ctk --version` reports it

#### Scenario: Older release with known vulnerabilities

- **WHEN** the feature is installed with `version` set to an older release the repository offers that has known
  vulnerabilities, for example `1.14.0`
- **THEN** the build succeeds and all four packages are installed at that version

#### Scenario: Version the repository does not offer

- **WHEN** the feature is installed with `version` set to a well-formed version the repository does not offer
- **THEN** the feature fails the build with a message naming the requested version

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value that is neither `latest` nor `MAJOR.MINOR.PATCH`
- **THEN** the feature fails the build with a message naming the value, before it changes the image

### Requirement: Register the NVIDIA runtime with Docker

When the `configureDocker` option is enabled and a Docker daemon (`dockerd`) is installed in the image when the feature
runs, the feature SHALL register a runtime named `nvidia` whose path is `nvidia-container-runtime` in
`/etc/docker/daemon.json`, creating the file when it is missing or empty. It SHALL keep every other setting already in
that file and SHALL NOT change the daemon's default runtime. When that file exists but is not valid JSON, the feature
SHALL fail the build and leave the file unchanged. When `configureDocker` is enabled and no Docker daemon is installed,
the feature SHALL install the toolkit, print a message that it skipped the Docker configuration, and succeed without
creating `/etc/docker/daemon.json`. When `configureDocker` is disabled, the feature SHALL NOT create or change
`/etc/docker/daemon.json`. The feature SHALL be ordered after `ghcr.io/devcontainers/features/docker-in-docker` when
both are installed.

#### Scenario: Docker daemon installed by docker-in-docker

- **WHEN** the feature is installed with `configureDocker` enabled together with the docker-in-docker feature
- **THEN** `/etc/docker/daemon.json` contains `runtimes.nvidia` with `path` `nvidia-container-runtime`
- **AND** the Docker daemon started in the running dev container lists `nvidia` among its runtimes

#### Scenario: Existing daemon settings are kept

- **WHEN** `/etc/docker/daemon.json` already holds other settings, including another runtime or a `default-runtime`, and
  the feature is installed with `configureDocker` enabled on an image with a Docker daemon
- **THEN** those settings are unchanged and `runtimes.nvidia` is added beside them

#### Scenario: Empty daemon settings file

- **WHEN** `/etc/docker/daemon.json` exists and is empty, and the feature is installed with `configureDocker` enabled on
  an image with a Docker daemon
- **THEN** the build succeeds and the file holds valid JSON containing `runtimes.nvidia`

#### Scenario: Invalid daemon settings file

- **WHEN** `/etc/docker/daemon.json` holds content that is not valid JSON, and the feature is installed with
  `configureDocker` enabled on an image with a Docker daemon
- **THEN** the feature fails the build and the file is unchanged

#### Scenario: No Docker daemon

- **WHEN** the feature is installed with `configureDocker` enabled on an image without `dockerd`, including one with
  only the Docker CLI
- **THEN** the toolkit is installed, the build log says the Docker configuration was skipped, the build succeeds, and
  `/etc/docker/daemon.json` does not exist unless something else created it

#### Scenario: Docker configuration disabled

- **WHEN** the feature is installed with `configureDocker` disabled on an image with a Docker daemon
- **THEN** `/etc/docker/daemon.json` is neither created nor changed

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed and leave one consistent installation: with the
same options nothing changes; with a different `version` the later value wins and all four packages move to it, whether
that is an upgrade or a downgrade; `/etc/docker/daemon.json` never holds more than one `nvidia` runtime entry; and a
second install with `configureDocker` disabled leaves an entry an earlier install registered in place.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the installed version is unchanged, and the repository is configured once

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an older exact version and then again with `version` set to
  `latest`, or the other way round
- **THEN** all four packages end at the version the second install selected

#### Scenario: Docker configured twice

- **WHEN** the feature is installed twice with `configureDocker` enabled on an image with a Docker daemon
- **THEN** `/etc/docker/daemon.json` holds exactly one `nvidia` runtime entry

#### Scenario: Docker configuration disabled the second time

- **WHEN** the feature is installed with `configureDocker` enabled on an image with a Docker daemon and then again with
  `configureDocker` disabled
- **THEN** the `nvidia` runtime entry from the first install is still in `/etc/docker/daemon.json`

### Requirement: Unsupported platforms fail the build

The feature SHALL fail the build with a message naming the distribution or architecture, before it changes the image,
when the distribution is not Debian- or Ubuntu-based with apt, Fedora- or RHEL-based with dnf, or openSUSE- or
SLES-based with zypper, or when the architecture is not `amd64` or `arm64`. A distribution of one of these families that
is not listed in `test/nvidia-container-toolkit/compatibility.json` is not refused, but it is not supported: the feature
attempts the install there without a guarantee that it succeeds.

#### Scenario: Distribution without a supported package manager

- **WHEN** the feature is installed on an image such as Alpine Linux or Amazon Linux 2
- **THEN** the build fails with a message naming the distribution, and no repository or key has been added

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an image whose architecture is neither `amd64` nor `arm64`
- **THEN** the build fails with a message naming the architecture, and no repository or key has been added
