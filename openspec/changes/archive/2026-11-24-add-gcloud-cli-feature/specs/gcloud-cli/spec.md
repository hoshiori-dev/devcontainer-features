# Spec Delta

## Purpose

Installs the Google Cloud CLI (`gcloud`, `bq`, `gsutil`, and optional components) in a dev container and retains private
project-scoped CLI configuration, authentication stores, and Application Default Credentials across container rebuilds.

Upstream sources:

- Documentation: https://docs.cloud.google.com/sdk/gcloud
- Installation guide: https://docs.cloud.google.com/sdk/docs/install-sdk
- Components guide: https://docs.cloud.google.com/sdk/docs/components
- Versioned archives: https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives
- Release notes: https://docs.cloud.google.com/sdk/docs/release-notes
- Authentication overview: https://docs.cloud.google.com/docs/authentication/gcloud

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here to select the release installed.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version` or with `version` set to `latest`
- **THEN** the newest stable release offered by the selected official source at build time is installed

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an available `MAJOR.MINOR.PATCH` release
- **THEN** `gcloud version` reports that exact release

#### Scenario: Malformed version

- **WHEN** `version` is empty, has a leading `v`, is a prerelease, or is outside `latest` and `MAJOR.MINOR.PATCH`
- **THEN** installation fails with a message naming the value before downloading or changing the image

#### Scenario: Unavailable version

- **WHEN** `version` is well-formed `MAJOR.MINOR.PATCH` but is absent from the selected official source
- **THEN** installation fails with a message naming the requested version

### Requirement: Option components

The feature SHALL accept the option `components` as declared here as a comma-separated list of component IDs.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted components

- **WHEN** the feature is installed without `components` or with `components` set to `""`
- **THEN** only the base Google Cloud CLI installation (`gcloud`, `bq`, `gsutil`) is installed

#### Scenario: Requested components

- **WHEN** `components` names valid comma-separated component IDs such as `kubectl,gke-gcloud-auth-plugin`
- **THEN** the requested components are installed and runnable by the remote user

#### Scenario: Invalid components value

- **WHEN** `components` contains empty items, whitespace, leading/trailing/repeated commas, or characters outside
  `[a-z0-9-]`
- **THEN** installation fails with a message naming the invalid entry before downloading or changing the image

#### Scenario: Unavailable component

- **WHEN** a requested component ID is unavailable for the target platform or selected version
- **THEN** installation fails with a message naming the component or failing installation step

### Requirement: CLI on PATH for every user

The feature SHALL install `gcloud`, `bq`, `gsutil`, and binaries of any requested `components` so they resolve on the
default `PATH` of both root and the remote user outside `/var/lib/gcloud-cli`, without editing shell startup files.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image in `test/gcloud-cli/compatibility.json`
- **THEN** `gcloud version`, `bq version`, and `gsutil version` succeed as the remote user on the default `PATH`
- **AND** the installed binaries reside outside `/var/lib/gcloud-cli`

#### Scenario: Shell profiles untouched

- **WHEN** the feature is installed
- **THEN** neither root's nor the remote user's shell startup files are modified by the installer

### Requirement: APT signed repository route

On Debian and Ubuntu images with `apt-get`, the feature SHALL verify
`https://packages.cloud.google.com/apt/doc/apt-key.gpg` holds one primary public key with fingerprint
`35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`, install it to `/usr/share/keyrings/cloud.google.gpg`, configure
`https://packages.cloud.google.com/apt` (`cloud-sdk main`), and install `google-cloud-cli` with
`CLOUDSDK_SKIP_PY_COMPILATION=1`.

#### Scenario: APT repository install

- **WHEN** installed on a Debian- or Ubuntu-family image with `apt-get`
- **THEN** missing prerequisites (`ca-certificates`, `curl`, `gnupg`) are installed from image repositories, the GPG key
  fingerprint is verified, and `google-cloud-cli` is installed from `packages.cloud.google.com/apt`

#### Scenario: Key fingerprint mismatch

- **WHEN** the downloaded APT signing key is unreadable, holds more than one primary key, or its fingerprint differs
  from `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`
- **THEN** installation fails naming the expected fingerprint before writing
  `/etc/apt/sources.list.d/google-cloud-sdk.list` or installing packages

#### Scenario: APT repository stays configured

- **WHEN** an APT installation completes
- **THEN** `/etc/apt/sources.list.d/google-cloud-sdk.list` and `/usr/share/keyrings/cloud.google.gpg` remain configured
  for subsequent `apt-get` use

### Requirement: DNF signed repository route

On Fedora and RHEL images with `dnf`, the feature SHALL verify
`https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg` holds one primary public key with fingerprint
`C5F744A098136F40C370E8493156C631B64936F9`, import it, configure
`https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-<arch>` with `gpgcheck=1`, and install `google-cloud-cli`
with `CLOUDSDK_SKIP_PY_COMPILATION=1`.

#### Scenario: DNF repository install

- **WHEN** installed on a Fedora- or RHEL-family image with `dnf` on `x86_64` or `aarch64`
- **THEN** missing prerequisites (`ca-certificates`, `curl`, `gnupg2`) are installed, the v10 GPG key fingerprint is
  verified and imported, and `google-cloud-cli` is installed from `cloud-sdk-el10-<arch>`

#### Scenario: DNF key fingerprint mismatch

- **WHEN** the downloaded RPM signing key is unreadable, holds more than one primary key, or its fingerprint differs
  from `C5F744A098136F40C370E8493156C631B64936F9`
- **THEN** installation fails naming the expected fingerprint before writing `/etc/yum.repos.d/google-cloud-sdk.repo` or
  importing into RPM

#### Scenario: DNF repository stays configured

- **WHEN** a DNF installation completes
- **THEN** `/etc/yum.repos.d/google-cloud-sdk.repo` remains configured with `gpgcheck=1` against the pinned local key

### Requirement: DNF repository metadata trust

The DNF repository configuration SHALL set `repo_gpgcheck=0` while enforcing `gpgcheck=1` against the pinned key on
every package. Risk: upstream's `repomd.xml.asc` uses a 2048-bit key rejected by EL10/Fedora 44 crypto policy, so
metadata freshness relies on TLS alone.

#### Scenario: Package signature enforced without metadata check

- **WHEN** DNF fetches metadata and RPM packages from `cloud-sdk-el10-<arch>`
- **THEN** metadata relies on TLS and every RPM package signature is verified against the pinned v10 key

### Requirement: Archive fallback for other distributions

On Linux `x86_64` and `aarch64` distributions outside APT and DNF, the feature SHALL warn naming the distribution and
download over HTTPS only:
`https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-<pkg_arch>.tar.gz` for `latest`, or
`https://storage.googleapis.com/cloud-sdk-release/google-cloud-cli-<version>-linux-<pkg_arch>.tar.gz` (`<pkg_arch>` is
`x86_64` or `arm`).

#### Scenario: Fallback warning and archive install

- **WHEN** installed on a supported architecture whose distribution is outside APT and DNF (or lacks `apt-get`/`dnf`)
- **THEN** the installer logs a warning naming the distribution without failing and installs the official Linux archive

#### Scenario: Fallback pinned release

- **WHEN** installed on a fallback distribution with an explicit `MAJOR.MINOR.PATCH` `version`
- **THEN** it downloads the versioned archive from `storage.googleapis.com/cloud-sdk-release` and `gcloud version`
  reports that version

#### Scenario: Fallback with components

- **WHEN** installed on a fallback distribution with non-empty `components`
- **THEN** requested components are installed non-interactively via `gcloud components install --quiet` using a
  temporary `HOME`

### Requirement: Archive fallback metadata trust

Because upstream publishes no detached signature or standalone checksum file for Linux archives, fallback archive
downloads and `gcloud components install` downloads SHALL rely on HTTPS/TLS alone.

#### Scenario: HTTPS transport enforced on fallback

- **WHEN** the fallback installer downloads an archive or installs components
- **THEN** every HTTP request and redirect uses HTTPS only

### Requirement: Archive staging and runtime dependencies

On the archive fallback route, the feature SHALL verify the staged `gcloud` executes in an isolated temporary `HOME`,
atomically replace `/usr/local/share/google-cloud-sdk`, and link binaries into `/usr/local/bin`, relying on the
archive's bundled Python on glibc Linux systems.

#### Scenario: Failed archive install preserves existing CLI

- **WHEN** an archive download, extraction, or staged execution check fails on a second installation
- **THEN** any working CLI previously installed at `/usr/local/share/google-cloud-sdk` remains intact

### Requirement: Component selection and mapping

On APT and DNF, `kubectl` SHALL map to `kubectl` (`1:<version>-0` on APT), `bigtable` to
`google-cloud-cli-bigtable-emulator`, `cloud-datastore-emulator` and `gcd-emulator` to
`google-cloud-cli-datastore-emulator`, `cloud-firestore-emulator` to `google-cloud-cli-firestore-emulator`,
`cloud-spanner-emulator` to `google-cloud-cli-spanner-emulator`, and any other ID `<id>` (except bundled
`alpha`/`beta`/`preview`) to `google-cloud-cli-<id>`.

#### Scenario: Common components across APT and DNF

- **WHEN** `components` includes `kubectl,gke-gcloud-auth-plugin` on APT or DNF
- **THEN** `kubectl` and `gke-gcloud-auth-plugin` packages are installed at matching release versions and callable on
  `PATH`

#### Scenario: Bundled release-level components

- **WHEN** `components` includes `alpha`, `beta`, or `preview`
- **THEN** installation succeeds on both repository and fallback routes and those command groups are usable

### Requirement: Fallback component installation

On the archive fallback route, the feature SHALL pass requested component IDs directly to
`gcloud components install --quiet` in a temporary `HOME` and link component executables under `/usr/local/bin`.

#### Scenario: Common components on fallback

- **WHEN** `components` includes `kubectl,alpha` on the archive fallback route
- **THEN** `kubectl` is linked on `PATH` and `gcloud alpha --help` succeeds as the remote user

### Requirement: Supported platforms and architecture gate

Tested images and architectures SHALL be recorded in `test/gcloud-cli/compatibility.json`. Non-Linux systems,
architectures outside `amd64`/`x86_64` and `arm64`/`aarch64`, and images without `bash` SHALL be unsupported. Fallback
distributions lacking required tools without a supported package manager (`zypper`, `pacman`) SHALL fail clearly naming
what is missing.

#### Scenario: Tested target

- **WHEN** installed on any image and architecture declared in `test/gcloud-cli/compatibility.json`
- **THEN** installation completes and `gcloud` runs as the image's remote user

#### Scenario: Unsupported architecture

- **WHEN** run on an architecture outside `amd64`/`x86_64` and `arm64`/`aarch64`, or a non-Linux kernel
- **THEN** installation fails with a message naming the architecture or OS before downloading or installing anything

#### Scenario: Missing fallback prerequisites

- **WHEN** run on a fallback image missing `curl`, `tar`, `gzip`, or `ca-certificates` with no supported package manager
- **THEN** installation fails with a message naming the missing prerequisites

### Requirement: Project-scoped state volume

The feature SHALL declare the named volume `gcloud-cli-${devcontainerId}` mounted at `/var/lib/gcloud-cli` for private
CLI configuration, CLI authentication stores, and Application Default Credentials, ordered after
`ghcr.io/devcontainers/features/common-utils`. Executables SHALL stay outside this mount, and distinct `devcontainerId`
values SHALL receive distinct volumes.

#### Scenario: Empty volume

- **WHEN** a new project container starts with an empty volume
- **THEN** `/var/lib/gcloud-cli/config` is writable by the remote user and `gcloud` runs without modifying image
  binaries

#### Scenario: Recreated container

- **WHEN** a new container for the same project mounts the previous volume
- **THEN** saved configurations and synthetic credential files persist in `/var/lib/gcloud-cli/config`

#### Scenario: Independent project

- **WHEN** another project uses a distinct `devcontainerId`
- **THEN** its default volume and saved gcloud state are isolated

### Requirement: State directory contract

The feature SHALL link exclusively `$HOME/.config/gcloud` to `/var/lib/gcloud-cli/config`, keeping `CLOUDSDK_CONFIG`
unset and leaving unrelated entries under `$HOME/.config` unlinked. Retained state SHALL include configurations,
`credentials.db`, `access_tokens.db`, `legacy_credentials/`, and `application_default_credentials.json`, surviving
atomic file replacement.

#### Scenario: Default state path

- **WHEN** `gcloud info --format="value(config.paths.global_config_dir)"` runs as the remote user
- **THEN** it resolves through `$HOME/.config/gcloud` to `/var/lib/gcloud-cli/config`

#### Scenario: Real config writes and atomic credential fixtures

- **WHEN** `gcloud config set` writes properties and synthetic credential files (`credentials.db`, `access_tokens.db`,
  `application_default_credentials.json`) are atomically replaced under `~/.config/gcloud`
- **THEN** `~/.config/gcloud` remains a symlink to `/var/lib/gcloud-cli/config` and all written files persist in the
  volume

#### Scenario: Unrelated config directory coexistence

- **WHEN** unrelated directories or files exist under `$HOME/.config`
- **THEN** those entries remain local to `$HOME/.config` and outside `/var/lib/gcloud-cli`

### Requirement: State mapping conflicts

State setup SHALL reuse links targeting `/var/lib/gcloud-cli/config`, create missing links at runtime
`$HOME/.config/gcloud`, and fail clearly while preserving any existing file, directory, dangling link, or link to
another target. A non-empty `CLOUDSDK_CONFIG` pointing outside the mapped directory SHALL fail clearly without changing
it or existing state.

#### Scenario: Conflicting existing path

- **WHEN** `$HOME/.config/gcloud` already exists as a file, directory, dangling symlink, or symlink to another target
- **THEN** setup fails with an actionable message and preserves both the existing content and the volume

#### Scenario: Existing valid mapping

- **WHEN** setup runs with `$HOME/.config/gcloud` already linking to `/var/lib/gcloud-cli/config`
- **THEN** it reuses the link without modifying saved state

#### Scenario: Recreated user home

- **WHEN** a container starts with a different effective `$HOME` mounting the existing volume
- **THEN** initialization creates the missing `$HOME/.config/gcloud` link and preserves saved state

#### Scenario: Caller-provided CLOUDSDK_CONFIG

- **WHEN** `CLOUDSDK_CONFIG` is set to a path that does not resolve to `$HOME/.config/gcloud` or
  `/var/lib/gcloud-cli/config`
- **THEN** initialization fails clearly without changing `CLOUDSDK_CONFIG` or existing state

### Requirement: Initialization lifecycle and readiness checks

The feature SHALL prepare `/var/lib/gcloud-cli`, `/var/lib/gcloud-cli/config`, and `${_REMOTE_USER_HOME}/.config/gcloud`
at build time and run `/usr/local/share/gcloud-cli-feature/initialize` once per container creation via
`onCreateCommand`, with no `postStartCommand` or `postAttachCommand`. Initialization SHALL verify `/var/lib/gcloud-cli`
is a real mount, reject symlinks at `config` or known credential files, and probe remote-user write access.

#### Scenario: Build-prepared link

- **WHEN** an image is built with `${_REMOTE_USER_HOME}/.config/gcloud` linked before volume mount
- **THEN** `onCreateCommand` verifies the mounted volume and remote-user access without re-linking

#### Scenario: Missing state mount

- **WHEN** `/var/lib/gcloud-cli` is not a mounted volume (or is a symlink)
- **THEN** initialization fails clearly instead of storing state on ephemeral container storage

#### Scenario: No recurring startup checks

- **WHEN** the container restarts or an editor attaches again
- **THEN** no `postStartCommand` or `postAttachCommand` from this feature runs

### Requirement: Bounded state repair, ownership, and privacy

Healthy reused volumes SHALL initialize without full-tree scans or recursive `chown`/`chmod`. Mode mismatches (`0700`
state directories, `0600` known credential files) on owned paths SHALL repair without `sudo`. Ownership mismatches SHALL
repair strictly inside `/var/lib/gcloud-cli` without crossing filesystems or following symlinks (`find -P -xdev`) via
root or noninteractive `sudo`; unavailable repair SHALL fail clearly without broadening permissions or deleting state.

#### Scenario: Healthy reused volume

- **WHEN** `/var/lib/gcloud-cli` has expected ownership, private permissions, and valid mapping
- **THEN** initialization completes without running recursive tree walks or `sudo`

#### Scenario: Mode repair without sudo

- **WHEN** the remote user owns the state root and directories/credential files have broader modes
- **THEN** initialization restores `0700`/`0600` modes directly without invoking `sudo`

#### Scenario: Changed remote UID

- **WHEN** a reused volume is owned by another numeric UID and noninteractive `sudo` (or root) is available
- **THEN** ownership and private modes are repaired inside `/var/lib/gcloud-cli` without touching external symlink
  targets

#### Scenario: Unavailable repair

- **WHEN** ownership repair is required and noninteractive `sudo` is unavailable
- **THEN** initialization fails clearly while leaving existing state intact and non-world-readable

#### Scenario: State symlink protection

- **WHEN** `/var/lib/gcloud-cli/config` or a known credential path inside the state root is a symlink
- **THEN** both normal initialization and `--repair` fail before modifying ownership or modes

### Requirement: No build-time account data and credential boundaries

The feature SHALL accept no credential, token, or project option, perform no build-time login, copy no host credentials,
and expose no real credentials in image layers or logs. It SHALL preserve upstream credential defaults without
provisioning keyrings, document `GOOGLE_APPLICATION_CREDENTIALS`, keyrings, and optional editor extensions in
`NOTES.md`, and validate persistence using synthetic fixtures only.

#### Scenario: Unauthenticated build

- **WHEN** the feature is built without Google Cloud credentials
- **THEN** installation succeeds, `gcloud --help` and `gcloud version` run, and no credentials or configurations are
  baked into the image

#### Scenario: Unattended synthetic validation

- **WHEN** automated tests verify state persistence and permissions
- **THEN** only synthetic credential fixtures are used, never printing their contents or proving live authentication

#### Scenario: Authentication documentation

- **WHEN** a developer reads `NOTES.md`
- **THEN** it identifies retained files under `~/.config/gcloud`, distinguishes retained files from active tokens, and
  explains consumer-managed `GOOGLE_APPLICATION_CREDENTIALS` and optional `GoogleCloudTools.cloudcode`

### Requirement: Installing twice

A second installation on the same image SHALL succeed with the same or different valid options: the later `version` wins
(upgrade or downgrade on APT/DNF; replacement or skip when unchanged on fallback), every requested component of the
later install is present at that version, state and mappings remain intact, no duplicate repository files or profile
edits are created, and pre-mutation/atomic failures preserve prior state.

#### Scenario: Same options twice

- **WHEN** installed twice with the same options
- **THEN** both runs succeed, repository definitions are not duplicated, and `gcloud version` matches

#### Scenario: Different version and components the second time

- **WHEN** installed with an earlier pinned `version` and one component set, then installed again with defaults or
  another `version` and component set
- **THEN** the later `version` and requested components are active and existing state mappings remain intact

#### Scenario: Failed second install preserves state

- **WHEN** a second install fails validation, key verification, or fallback archive verification
- **THEN** existing working CLI binaries and state mappings remain usable

### Requirement: Leave no build residue

The feature SHALL clean package-manager caches (`apt-get clean` and `/var/lib/apt/lists/*`, `dnf clean all`, or
`zypper clean --all`) after installing prerequisites or packages, and SHALL remove temporary GnuPG homes and staging
directories on every exit, whether installation succeeds or fails.

#### Scenario: Package caches clean

- **WHEN** installation finishes on any image in `test/gcloud-cli/compatibility.json`
- **THEN** APT package lists, DNF caches, and Zypper caches hold no downloaded metadata or package archives

#### Scenario: No temporary residue

- **WHEN** installation finishes, successfully or not
- **THEN** no temporary GnuPG home or staging directory remains in `/tmp` or `/usr/local/share`
