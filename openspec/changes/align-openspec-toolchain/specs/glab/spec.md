# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

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

The feature SHALL download and verify the selected GitLab release archive before installing `glab`.

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

The feature SHALL support images and architectures in `test/glab/compatibility.json` and reject unsupported platforms
before changes.

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

## ADDED Requirements

### Requirement: Glab release version selection

`latest` SHALL resolve the release from `https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest`. Explicit
versions SHALL be decimal `MAJOR.MINOR.PATCH` at or above `1.47.0`, optionally prefixed by `v`; other forms SHALL fail
before downloads. A latest permalink resolving to another tag form also fails before archive download.

#### Scenario: Unsupported version form

- **WHEN** an explicit version is malformed or below `1.47.0`, or latest resolves to a malformed tag
- **THEN** installation fails before downloads and names the invalid value or tag

### Requirement: Glab release assets and checksum

The feature SHALL fetch
`https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/glab_<version>_linux_<arch>.tar.gz` and
`https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/checksums.txt`, where version omits `v` and
architecture is `amd64` or `arm64`. It SHALL install only the archive's `glab` executable after exactly one matching
checksum-list entry agrees with its SHA-256; an absent architecture asset fails.

#### Scenario: Missing or ambiguous archive checksum

- **WHEN** the requested archive is absent or its checksum list has no unique matching filename
- **THEN** installation fails and uses no substitute asset or checksum entry

### Requirement: Glab release metadata trust

All requests and redirects SHALL use HTTPS. The feature SHALL resolve `latest` from the HTTPS redirect of the permanent
link without following it and rely on TLS alone because upstream provides no checksum or signature for the redirect. It
SHALL rely on TLS alone for the unsigned checksum list from the archive's origin; checksum verification establishes
archive integrity against that list, not publisher authenticity.

#### Scenario: Unsigned checksum list

- **WHEN** the feature verifies a release archive
- **THEN** it uses HTTPS throughout and treats the unsigned checksum list as TLS-delivered metadata, not proof of
  publisher authenticity

### Requirement: Glab platform gate

The feature SHALL require x86_64 or aarch64 and `/etc/os-release` `ID` or `ID_LIKE` identifying Debian, Ubuntu, Fedora,
or Alpine. It SHALL require `apt-get` on Debian/Ubuntu, `dnf` on Fedora, and `apk` on Alpine. Missing os-release,
unsupported family or architecture, and a missing family package manager SHALL fail before download or installation and
name the unsupported item.

#### Scenario: Unsupported platform prerequisite

- **WHEN** the architecture, distribution metadata, or matched family's package manager is unsupported or missing
- **THEN** installation fails before download or installation and names the unsupported item
