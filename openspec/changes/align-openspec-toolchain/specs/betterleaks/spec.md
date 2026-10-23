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
- **THEN** `betterleaks version` reports the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.8.1`
- **THEN** `betterleaks version` reports `1.8.1`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v1.8.1`
- **THEN** `betterleaks version` reports `1.8.1`

#### Scenario: Pre-release named explicitly

- **WHEN** the feature is installed with `version` set to an existing pre-release such as `2.0.0-rc.2`
- **THEN** `betterleaks version` reports `2.0.0-rc.2`

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag that is
  not a release version at or above `1.0.1`, or carries a pre-release suffix
- **THEN** the install fails before downloading any archive, with a message naming the tag, and
  `/usr/local/bin/betterleaks` is left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `1.0.0`
- **THEN** the install fails before downloading anything, with a message naming `1.0.1` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `1.8`, `main`, `1.8.1-beta`, or `2.0.0-rc`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `betterleaks` is installed

### Requirement: Verified download from the GitHub release

The feature SHALL download and verify the selected release archive before installing `betterleaks`.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its entry in the checksum list
- **THEN** the feature installs the `betterleaks` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/betterleaks` is left as it
  was before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/betterleaks` is left as it
  was before the install

### Requirement: Supported platforms

The feature SHALL support the images and architectures listed in `test/betterleaks/compatibility.json` and fail before
downloads on unsupported platforms.

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

### Requirement: Betterleaks release version selection

`latest` SHALL resolve the stable release at `https://github.com/betterleaks/betterleaks/releases/latest`. Explicit
versions SHALL match decimal `MAJOR.MINOR.PATCH` at or above `1.0.1`, optionally prefixed by `v` and optionally suffixed
by `-rc.N` with decimal `N`; malformed values fail before downloads.

#### Scenario: Version grammar and minimum

- **WHEN** `version` is malformed or below `1.0.1`
- **THEN** installation fails before downloads and names the accepted forms or minimum

#### Scenario: Latest tag is not a stable version

- **WHEN** the latest link resolves to a tag outside the accepted release grammar or with an `-rc.N` suffix
- **THEN** installation fails before downloading an archive, names the tag, and leaves the existing executable unchanged

### Requirement: Betterleaks release assets and checksum

The feature SHALL fetch
`https://github.com/betterleaks/betterleaks/releases/download/v<version>/betterleaks_<version>_linux_<arch>.tar.gz` and
`https://github.com/betterleaks/betterleaks/releases/download/v<version>/checksums.txt`, where `<version>` has no
leading `v` and `<arch>` is `x64` or `arm64`. It SHALL require the exact archive and exactly one matching checksum
entry, then compare SHA-256 before installing; a missing architecture asset SHALL fail installation.

#### Scenario: Release artifact selection

- **WHEN** a release is requested on a supported architecture
- **THEN** the feature requests only the matching archive and checksum list from that release, and fails if the archive
  is absent

### Requirement: Betterleaks latest release resolution

The feature SHALL resolve `latest` from the HTTPS redirect of
`https://github.com/betterleaks/betterleaks/releases/latest` without following it and rely on TLS alone because upstream
publishes no checksum or signature for that redirect. All release requests and redirects SHALL use HTTPS.

#### Scenario: Latest redirect transport

- **WHEN** the feature resolves `latest`
- **THEN** it reads the redirect without following it and every request hop uses HTTPS

### Requirement: Betterleaks checksum trust

The feature SHALL rely on TLS alone for `checksums.txt`. It SHALL NOT verify upstream's `checksums.txt.sigstore.json`
Sigstore bundle because compatible images lack a verifier and obtaining one would itself require an unverified download.
Archive checksum verification establishes integrity against the published release, not publisher authenticity.

#### Scenario: Checksum metadata is unsigned

- **WHEN** the feature verifies a release archive
- **THEN** it does not verify the Sigstore bundle and relies on the TLS-delivered checksum list, establishing archive
  integrity but not publisher authenticity

### Requirement: Betterleaks platform prerequisites

The feature SHALL accept only x86_64 or aarch64 and distributions identified through `/etc/os-release` `ID` or `ID_LIKE`
as Debian, Ubuntu, Fedora, or Alpine. It SHALL require `apt-get` for Debian/Ubuntu, `dnf` for Fedora, and `apk` for
Alpine; missing os-release, unsupported distributions, architectures, or package managers fail before downloads or
installation with the unsupported item named.

#### Scenario: Platform gate

- **WHEN** architecture, distribution metadata, or the matched family's package manager is unsupported or missing
- **THEN** installation fails before download or installation and names the unsupported item
