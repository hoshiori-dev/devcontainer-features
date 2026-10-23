# nvidia-container-toolkit Specification

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

## Requirements

### Requirement: Install the toolkit from NVIDIA's stable repository

The feature SHALL install NVIDIA's four toolkit packages at one selected version from the stable repository.

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

The feature SHALL trust only the verified NVIDIA repository signing key.

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

### Requirement: Option version

The feature SHALL accept `version` to select a stable repository version.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
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

- **WHEN** the feature is installed with `version` set to a value that is neither `latest` nor `MAJOR.MINOR.PATCH`, such
  as `1.20.1-1`
- **THEN** the feature fails the build with a message naming the value, before it changes the image

### Requirement: Option configureDocker

The feature SHALL accept `configureDocker` to control Docker runtime registration.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted configureDocker

- **WHEN** the feature is installed without `configureDocker`
- **THEN** it does what it does with `configureDocker` enabled: on an image with a Docker daemon it registers the
  `nvidia` runtime in `/etc/docker/daemon.json`, and on an image without one it skips the Docker configuration

#### Scenario: No Docker daemon

- **WHEN** the feature is installed with `configureDocker` enabled on an image without `dockerd`, including one with
  only the Docker CLI
- **THEN** the toolkit is installed, the build log says the Docker configuration was skipped, the build succeeds, and
  `/etc/docker/daemon.json` does not exist unless something else created it

#### Scenario: Docker configuration disabled

- **WHEN** the feature is installed with `configureDocker` disabled on an image with a Docker daemon
- **THEN** `/etc/docker/daemon.json` is neither created nor changed

#### Scenario: Invalid configureDocker

- **WHEN** the feature is installed with `configureDocker` set to a value that is neither `true` nor `false`, such as
  `yes`, `TRUE`, `1`, or an empty value
- **THEN** the feature fails the build with a message naming the value, before it changes the image

### Requirement: Register the NVIDIA runtime with Docker

When the `configureDocker` option is enabled and a Docker daemon (`dockerd`) is installed in the image when the feature
runs, the feature SHALL register the `nvidia` runtime in `/etc/docker/daemon.json` as "NVIDIA Docker runtime
registration" states, and SHALL be ordered after docker-in-docker as "NVIDIA feature ordering after docker-in-docker"
states.

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

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed and leave one consistent installation: with a
different `version` the later value wins and all four packages move to it, whether that is an upgrade or a downgrade;
`/etc/docker/daemon.json` never holds more than one `nvidia` runtime entry; and a second install with `configureDocker`
disabled leaves an entry an earlier install registered in place.

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
when the distribution is outside the apt, dnf, and zypper families or the architecture is not `amd64` or `arm64`, as
"NVIDIA supported platform gate" states; an unlisted distribution of those families is not refused.

#### Scenario: Distribution without a supported package manager

- **WHEN** the feature is installed on an image such as Amazon Linux 2
- **THEN** the build fails with a message naming the distribution, and no repository or key has been added

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an image whose architecture is neither `amd64` nor `arm64`
- **THEN** the build fails with a message naming the architecture, and no repository or key has been added

### Requirement: NVIDIA stable repository package selection

The feature SHALL install `nvidia-container-toolkit`, `nvidia-container-toolkit-base`, `libnvidia-container-tools`, and
`libnvidia-container1` at one version from NVIDIA's stable repository. Apt uses
`https://nvidia.github.io/libnvidia-container/stable/deb/<arch>` (`amd64` or `arm64`); dnf and zypper use
`https://nvidia.github.io/libnvidia-container/stable/rpm/<arch>` (`x86_64` or `aarch64`).

#### Scenario: Stable repository packages

- **WHEN** the feature installs on a supported image
- **THEN** all four packages come from the stable architecture-specific repository at one version

### Requirement: Keep NVIDIA repository and expose commands

The feature SHALL leave NVIDIA's stable repository configured, SHALL NOT configure the experimental channel, and SHALL
expose installed commands on every user's default `PATH`. Supported images are listed in
`test/nvidia-container-toolkit/compatibility.json`.

#### Scenario: Repository remains configured

- **WHEN** installation succeeds
- **THEN** the stable repository remains configured and installed commands resolve on every user's default PATH

### Requirement: NVIDIA repository signing key verification

The feature SHALL download NVIDIA's repository signing key from `https://nvidia.github.io/libnvidia-container/gpgkey`
and SHALL use it only after verifying that the downloaded file contains exactly one primary key, whose full fingerprint
is `C95B321B61E88C1809C4F759DDCAE044F796ECB0`.

#### Scenario: Downloaded key fingerprint

- **WHEN** the feature downloads NVIDIA's repository key
- **THEN** it uses the file only when it holds exactly one primary key and that key has the pinned full fingerprint

### Requirement: NVIDIA repository signature enforcement

The configured repository SHALL accept only content signed by the verified pinned key: on apt-based images the
repository's signed index is checked against that key alone, and on dnf- and zypper-based images both the repository
metadata and every package are signature-checked against a local copy of that key. Neither the feature nor the
repository configuration it writes SHALL import or trust any key other than the verified copy of that key.

#### Scenario: Repository signatures use only pinned key

- **WHEN** package metadata or packages are fetched from NVIDIA's repository
- **THEN** signatures are checked by the package-manager-specific method against only the verified pinned key

### Requirement: NVIDIA stable version selection

For option `version`, `latest` SHALL install the newest version that NVIDIA's stable repository offers at build time, a
version of the form `MAJOR.MINOR.PATCH` that the repository offers SHALL install exactly that version of all four
packages with no minimum version, including releases with known vulnerabilities, and any other value, including a
version with a package release suffix, SHALL fail the build.

#### Scenario: Exact vulnerable version remains selectable

- **WHEN** the stable repository offers a requested `MAJOR.MINOR.PATCH` version, even one with known vulnerabilities
- **THEN** all four packages install at that exact version

### Requirement: Docker configuration option outcomes

When `configureDocker` is enabled and no Docker daemon is installed, the feature SHALL install the toolkit, print a
message that it skipped the Docker configuration, and succeed without creating `/etc/docker/daemon.json`. When it is
disabled, the feature SHALL NOT create or change `/etc/docker/daemon.json`. Any value other than `true` or `false`,
including an empty value, SHALL fail the build.

#### Scenario: Docker configuration skipped or disabled

- **WHEN** no Docker daemon (`dockerd`) is installed with configuration enabled, or configuration is disabled
- **THEN** the enabled case reports the skip without creating daemon settings, and the disabled case leaves settings
  unchanged

### Requirement: NVIDIA Docker runtime registration

When `configureDocker` is enabled and `dockerd` is installed in the image when the feature runs, the feature SHALL
register runtime `nvidia` with path `nvidia-container-runtime` in `/etc/docker/daemon.json`, creating the file if
missing or empty, SHALL keep every other setting in it, and SHALL NOT change the default runtime. When that file exists
but is not valid JSON, the feature SHALL fail the build and leave the file unchanged.

#### Scenario: Docker settings are invalid

- **WHEN** runtime registration is enabled and the existing daemon settings are invalid JSON
- **THEN** the build fails and leaves the file unchanged

### Requirement: NVIDIA feature ordering after docker-in-docker

The feature SHALL be ordered after `ghcr.io/devcontainers/features/docker-in-docker` when both are installed.

#### Scenario: Installed together with docker-in-docker

- **WHEN** the feature and `ghcr.io/devcontainers/features/docker-in-docker` are installed in the same dev container
- **THEN** the feature runs after docker-in-docker

### Requirement: NVIDIA supported platform gate

The feature SHALL fail the build with a message naming the distribution or architecture, before changing the image, when
the distribution is not Debian- or Ubuntu-based with apt, Fedora- or RHEL-based with dnf, or openSUSE- or SLES-based
with zypper, or the architecture is not `amd64` or `arm64`. A distribution of these families not in
`test/nvidia-container-toolkit/compatibility.json` is not refused but unsupported: the feature attempts the install
without a guarantee that it succeeds.

#### Scenario: Unlisted family distribution

- **WHEN** a family-compatible distribution is absent from the compatibility list
- **THEN** the feature attempts installation without promising success
