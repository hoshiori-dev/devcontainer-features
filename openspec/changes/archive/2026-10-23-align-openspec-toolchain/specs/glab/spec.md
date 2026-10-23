# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the release it selects, as stated in "Glab
release version selection".

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

The feature SHALL download the release archive and its checksum list as stated in "Glab release assets and checksum",
verify the archive against that list, and trust them as stated in "Glab release metadata trust".

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

The feature SHALL support the images and architectures listed in `test/glab/compatibility.json`, and SHALL reject an
unsupported platform before downloading or installing anything, as stated in "Glab platform gate".

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

For `version`, `latest` SHALL mean the release that https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest
redirects to at build time, and any other value SHALL be a release version `MAJOR.MINOR.PATCH` of decimal numbers at or
above `1.47.0`, with or without a leading `v`; the feature SHALL reject any other value before downloading anything, and
SHALL fail before downloading any archive when `latest` resolves to a tag of any other form.

#### Scenario: Unsupported version form

- **WHEN** the feature is installed with `version` set to a malformed value or a version below `1.47.0`, or with
  `latest` while the permanent link points to a tag that is not a release version at or above `1.47.0`
- **THEN** the install fails before downloading any archive

### Requirement: Glab release assets and checksum

The feature SHALL download the release archive from
`https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/glab_<version>_linux_<arch>.tar.gz` and its checksum
list from `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/checksums.txt`, where `<version>` has no
leading `v` and `<arch>` is `amd64` or `arm64`, over HTTPS only, including every redirect, and SHALL fail when the
requested release has no archive for the architecture.

#### Scenario: Release without an archive for the architecture

- **WHEN** the requested release has no archive for the machine's architecture
- **THEN** the install fails

### Requirement: Glab archive checksum match

The feature SHALL install the archive's `glab` only when the checksum list holds exactly one entry whose file name
equals the archive's name and the archive's SHA-256 digest equals that entry.

#### Scenario: Checksum entry matches

- **WHEN** the checksum list holds exactly one entry whose file name equals the archive's name and the archive's SHA-256
  digest equals that entry
- **THEN** the feature installs the `glab` from that archive

### Requirement: Glab release metadata trust

The feature SHALL rely on TLS alone for the checksum list itself, which upstream publishes unsigned from the same origin
as the archive, so this verification establishes the archive's integrity against the published release, not the
publisher's authenticity. To resolve `latest`, the feature SHALL read the redirect of the latest-release permanent link
over HTTPS without following it and SHALL rely on TLS alone for it, since upstream publishes no checksum or signature
for it.

#### Scenario: Latest resolved from the redirect

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the redirect of the latest-release permanent link over HTTPS without following it

### Requirement: Glab platform gate

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package
manager of the family it matched (`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or names none of the
  supported families, or the image lacks the matched family's package manager
- **THEN** the install fails before downloading or installing anything, with a message naming what is unsupported
