## Purpose

Installs the Google Colab CLI (`colab`) in a dev container for the remote user, with release selection and no build-time
authentication.

Upstream sources:

- Home and installation guide: https://github.com/googlecolab/google-colab-cli
- Package metadata: https://github.com/googlecolab/google-colab-cli/blob/main/pyproject.toml
- uv tools: https://docs.astral.sh/uv/concepts/tools/
- uv Python versions: https://docs.astral.sh/uv/concepts/python-versions/

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept `version` as declared here: `latest` selects the newest stable `google-colab-cli` release on
PyPI at build time; an exact `MAJOR.MINOR.PATCH` selects that release. `colab version` SHALL report the selected
release, and `colab --help` SHALL succeed for the remote user. Other values SHALL fail before this feature downloads or
installs anything; an unavailable release SHALL fail the build with a message naming the release.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version` or with `latest`
- **THEN** the remote user's `colab version` reports the newest stable release available during installation
- **AND** `colab --help` succeeds

#### Scenario: Pinned release

- **WHEN** the feature is installed with an exact published stable release
- **THEN** the remote user's `colab version` reports that release and `colab --help` succeeds

#### Scenario: Invalid version

- **WHEN** `version` is empty or outside `latest` and `MAJOR.MINOR.PATCH`
- **THEN** this feature fails with a message naming the value before downloading or installing anything

#### Scenario: Release does not exist

- **WHEN** `version` names a release not available on PyPI
- **THEN** the build fails with a message naming the requested release

### Requirement: Required uv dependency

The feature SHALL declare `ghcr.io/hoshiori-dev/devcontainer-features/uv:1` in `dependsOn` and SHALL install
`google-colab-cli` with `uv tool install`. It SHALL require uv 0.12.16 or later, which checks index-supplied package
hashes; an older uv SHALL cause this feature to fail before downloading or installing anything. It SHALL provide
uv-managed CPython 3.12 for the tool without replacing the image's Python commands.

#### Scenario: Dependency installed automatically

- **WHEN** a configuration selects only `colab-cli`
- **THEN** uv is installed first, and `colab` runs on managed CPython 3.12 even if the image has no Python

#### Scenario: Existing system Python

- **WHEN** the image already has Python commands
- **THEN** those commands keep their paths and versions, and `colab` uses its managed interpreter

#### Scenario: Older uv

- **WHEN** this feature runs with uv older than 0.12.16
- **THEN** it fails with a message naming the installed version and the minimum, before it downloads or installs
  anything

### Requirement: Verified package installation

The feature SHALL use uv's default PyPI index `https://pypi.org/simple/` and package files at
`https://files.pythonhosted.org/`, verified by uv against index-supplied hashes. It SHALL ignore build-time uv source,
credential, and verification overrides and configuration files, and SHALL disable no TLS or integrity checks. Resolution
or download failure SHALL fail the build with an actionable message.

#### Scenario: Official package source

- **WHEN** the build environment supplies an alternate index or uv configuration
- **THEN** this feature still installs the package from the official sources with uv's checks enabled

#### Scenario: Installation fails

- **WHEN** uv cannot resolve, download, verify, or install the selected package
- **THEN** the build fails and reports which installation failed

### Requirement: Verified interpreter installation

The feature SHALL use uv's managed CPython builds from
`https://releases.astral.sh/github/python-build-standalone/releases/download/`, with uv's fallback to
`https://github.com/astral-sh/python-build-standalone/releases/download/`, verified against the build's SHA-256 carried
by the installed uv release. It SHALL supply no alternate download source or disable verification.

#### Scenario: Managed interpreter download

- **WHEN** the tool needs a managed CPython 3.12 interpreter
- **THEN** uv downloads and verifies it from these sources, or the build fails

### Requirement: Keep the CLI in the image

The feature SHALL keep the tool environment, executable, and managed interpreter under `/usr/local/share/uv`, outside
the dependency's `/var/lib/uv` runtime volume. The remote user SHALL find `colab` on PATH in ordinary and login shells
and SHALL be able to manage its tool environment through `uv tool` without elevated privileges, including after a UID
change. The feature SHALL leave no installed file writable by every user.

#### Scenario: Empty runtime volume

- **WHEN** the built container starts with a new empty uv runtime volume
- **THEN** the remote user's `colab version` and `colab --help` succeed in ordinary and login shells

#### Scenario: Changed remote user UID

- **WHEN** the tooling changes the non-root remote user's UID before startup
- **THEN** that user still runs `colab` and manages the tool through `uv tool` without elevated privileges

#### Scenario: Installed permissions

- **WHEN** installation completes for a root or non-root remote user
- **THEN** no file or directory this feature installed is writable by every user

### Requirement: Supported platforms

The feature SHALL support the Linux image and architecture pairs in `test/colab-cli/compatibility.json`, for root and
the declared non-root remote users. Unsupported distributions and architectures SHALL fail before this feature downloads
or installs anything, with a message identifying the platform.

#### Scenario: Supported image

- **WHEN** the feature is installed on a declared image and architecture pair
- **THEN** `colab version` and `colab --help` succeed as that image's remote user

#### Scenario: Unsupported platform

- **WHEN** this feature runs on an unsupported distribution or architecture
- **THEN** it fails with a message naming the platform before downloading or installing anything

### Requirement: Install twice

A second installation SHALL succeed with the same or different valid options. An exact release already installed SHALL
skip the package installation; `latest` SHALL resolve again and replace the tool only if a newer release is available.
Different versions SHALL leave the later selected release active. Repeated installation SHALL duplicate no PATH entry or
group membership and SHALL preserve unrelated uv tools.

#### Scenario: Same options

- **WHEN** the feature is installed twice with the same exact release
- **THEN** both installs succeed, the second skips package installation, and that release remains active

#### Scenario: Different options

- **WHEN** the feature is installed with a pinned release and then with defaults
- **THEN** the latest stable release is active, unrelated tools remain usable, and integration is not duplicated

### Requirement: Runtime authentication

The feature SHALL accept no credential or account option and SHALL perform no authentication, session provisioning,
remote execution, or Drive mounting during image build. The remote user SHALL be able to inspect help and version
without credentials; authentication and remote resource use remain runtime actions.

#### Scenario: Build without credentials

- **WHEN** the feature is installed without credentials or an authenticated account
- **THEN** the build succeeds, help and version work, and no authentication or Colab session is started
