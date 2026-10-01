# glab Specification

## Purpose

Installs the GitLab CLI (`glab`) from upstream's release artifacts at a chosen or the latest version, on `PATH` for
every user of the container, and deliberately configures no authentication.

Upstream sources:

- Project home and README: https://gitlab.com/gitlab-org/cli
- Documentation: https://docs.gitlab.com/cli/
- Releases and changelog: https://gitlab.com/gitlab-org/cli/-/releases

## Requirements

### Requirement: glab on PATH for every user

The feature SHALL install the `glab` executable at `/usr/local/bin/glab`, executable by every user, so that `glab`
resolves to it on the default `PATH` of the remote user and of root. It SHALL make `git` available, which glab needs at
run time, installing it when the image lacks it.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/glab/compatibility.json`
- **THEN** `command -v glab` run as the remote user resolves, following symbolic links, to `/usr/local/bin/glab`
- **AND** `glab --version` run as the remote user exits 0
- **AND** `git --version` run as the remote user exits 0

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the release it selects: `latest` means the
release that https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest redirects to at build time, and any other
value is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `1.47.0`, with or without a leading `v`;
the feature SHALL reject any other value before downloading anything, and SHALL fail before downloading any archive when
`latest` resolves to a tag of any other form.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `glab --version` reports the release that the permanent link to the latest release pointed to during the
  build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.119.0`
- **THEN** `glab --version` reports `1.119.0`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v1.119.0`
- **THEN** `glab --version` reports `1.119.0`

#### Scenario: Permanent link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the permanent link to the latest release points
  to a tag that is not a release version at or above `1.47.0`, such as a pre-release tag
- **THEN** the install fails before downloading any archive, with a message naming the tag, and `/usr/local/bin/glab` is
  left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `1.46.0`
- **THEN** the install fails before downloading anything, with a message naming `1.47.0` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `1.119`, `main`, or `1.119.0-rc1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `glab` is installed

### Requirement: Verified download from the GitLab release

The feature SHALL download the release archive from
`https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/glab_<version>_linux_<arch>.tar.gz` and its checksum
list from `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/checksums.txt`, where `<version>` has no
leading `v` and `<arch>` is `amd64` or `arm64`, over HTTPS only, including every redirect, and SHALL fail when the
requested release has no archive for the architecture. It SHALL install the archive's `glab` only when the checksum list
holds exactly one entry whose file name equals the archive's name and the archive's SHA-256 digest equals that entry.
The feature SHALL rely on TLS alone for the checksum list itself, which upstream publishes unsigned from the same origin
as the archive, so this verification establishes the archive's integrity against the published release, not the
publisher's authenticity. To resolve `latest`, the feature SHALL read the redirect of the latest-release permanent link
over HTTPS without following it and SHALL rely on TLS alone for it, since upstream publishes no checksum or signature
for it.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its entry in the checksum list
- **THEN** the feature installs the `glab` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/glab` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/glab` is left as it was
  before the install

### Requirement: Supported platforms

The feature SHALL support the images and architectures listed in `test/glab/compatibility.json`. It SHALL fail, before
downloading or installing anything, with a message naming what is unsupported when the machine architecture is neither
x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or `ID_LIKE`, a distribution outside
the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package manager of the family it matched
(`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on a machine whose architecture is neither x86_64 nor aarch64
- **THEN** the install fails with a message naming the architecture, and nothing is downloaded or installed

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose `/etc/os-release` is missing or names none of the supported
  families
- **THEN** the install fails with a message naming the distribution, or saying that `/etc/os-release` is missing, and
  nothing is downloaded or installed

#### Scenario: Supported family without its package manager

- **WHEN** the feature is installed on an image whose `/etc/os-release` matches a supported family but which lacks that
  family's package manager
- **THEN** the install fails with a message naming the distribution and the missing package manager, and nothing is
  downloaded or installed

### Requirement: No authentication or glab configuration

The feature SHALL offer no option for a login, a token, or a GitLab host. It SHALL leave no glab configuration or
credential anywhere in the image, and SHALL NOT write any file under a user's home directory, set container environment
variables, or edit shell startup files.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds a glab configuration directory
- **AND** none of the environment variables glab reads a token from (`GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`,
  `OAUTH_TOKEN`) is set in the remote user's environment

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. When the installed `/usr/local/bin/glab` already
reports the requested version, the second install SHALL leave it untouched and download no archive; otherwise, including
when the installed binary's version cannot be read, the version of the later install SHALL replace it, so that the later
options win and exactly one `glab` remains. A second install that fails SHALL leave the earlier `glab` in place.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same `version`
- **THEN** both installs succeed, the second leaves `/usr/local/bin/glab` unchanged, and `glab --version` reports that
  version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `glab --version` reports the version the second install selected
- **AND** `command -v glab` resolves, following symbolic links, to `/usr/local/bin/glab`, and `/usr/local/bin` holds no
  file other than `glab` whose name contains `glab`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/glab` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `glab --version` reports the requested version

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `glab --version` still reports the version of the first install
