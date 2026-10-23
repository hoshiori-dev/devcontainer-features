# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the release it selects, interpreting and
rejecting values as "Betterleaks release version selection" and "Betterleaks version rejection" state.

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

The feature SHALL download and verify the selected release archive before installing `betterleaks`, as "Betterleaks
release assets and checksum", "Betterleaks archive digest check", "Betterleaks checksum trust", and "Betterleaks latest
release resolution" state.

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

The feature SHALL support the images and architectures listed in `test/betterleaks/compatibility.json`, and SHALL fail
before downloading or installing anything on an unsupported platform, as "Betterleaks platform prerequisites" states.

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

For `version`, `latest` SHALL mean the release that https://github.com/betterleaks/betterleaks/releases/latest redirects
to at build time, which GitHub keeps at the newest release not marked as a pre-release, and any other value SHALL be a
release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `1.0.1`, optionally followed by a pre-release suffix
`-rc.N` of a decimal number, with or without a leading `v`.

#### Scenario: Accepted version forms

- **WHEN** the feature is installed with `version` set to an existing release or pre-release such as `1.8.1`, `v1.8.1`,
  or `2.0.0-rc.2`
- **THEN** `betterleaks version` reports that version without a leading `v`

### Requirement: Betterleaks version rejection

The feature SHALL reject any `version` value other than `latest` or a release version of the accepted form at or above
`1.0.1` before downloading anything, and SHALL fail before downloading any archive when `latest` resolves to a tag of
any other form or to a tag carrying a pre-release suffix.

#### Scenario: Version grammar and minimum

- **WHEN** the feature is installed with `version` set to a malformed value or to a version below `1.0.1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms for a malformed value
  or naming `1.0.1` as the minimum for a version below it

#### Scenario: Latest tag is not a stable version

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag that is
  not a release version at or above `1.0.1`, or carries a pre-release suffix
- **THEN** the install fails before downloading any archive, with a message naming the tag, and
  `/usr/local/bin/betterleaks` is left as it was before the install

### Requirement: Betterleaks release assets and checksum

The feature SHALL download the release archive from
`https://github.com/betterleaks/betterleaks/releases/download/v<version>/betterleaks_<version>_linux_<arch>.tar.gz` and
its checksum list from `https://github.com/betterleaks/betterleaks/releases/download/v<version>/checksums.txt`, where
`<version>` has no leading `v` and `<arch>` is `x64` or `arm64`, over HTTPS only, including every redirect, and SHALL
fail when the requested release has no archive for the architecture.

#### Scenario: Release artifact selection

- **WHEN** a release is requested on a supported architecture
- **THEN** the feature downloads that release's archive for the architecture and its checksum list over HTTPS, and the
  install fails if the release has no archive for the architecture

### Requirement: Betterleaks archive digest check

The feature SHALL install the archive's `betterleaks` only when the checksum list holds exactly one entry whose file
name equals the archive's name and the archive's SHA-256 digest equals that entry.

#### Scenario: Digest checked before install

- **WHEN** the checksum list holds exactly one entry whose file name equals the archive's name and the archive's SHA-256
  digest equals that entry
- **THEN** the feature installs the `betterleaks` from that archive

### Requirement: Betterleaks checksum trust

Upstream also publishes a Sigstore signature bundle for the checksum list (`checksums.txt.sigstore.json`); the feature
SHALL NOT verify it, because no image of its compatibility list ships a tool that verifies a Sigstore bundle and
fetching one would need the same verification first, so the feature relies on TLS alone for the checksum list and the
digest check establishes the archive's integrity against the published release, not the publisher's authenticity.

#### Scenario: Checksum metadata is unsigned

- **WHEN** the feature verifies a release archive
- **THEN** it does not verify the Sigstore bundle and relies on TLS alone for the checksum list

### Requirement: Betterleaks latest release resolution

To resolve `latest`, the feature SHALL read the redirect of the latest-release link
(`https://github.com/betterleaks/betterleaks/releases/latest`) over HTTPS without following it and SHALL rely on TLS
alone for it, since upstream publishes no checksum or signature for it.

#### Scenario: Latest redirect transport

- **WHEN** the feature resolves `latest`
- **THEN** it reads the redirect of the latest-release link over HTTPS without following it

### Requirement: Betterleaks platform prerequisites

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package
manager of the family it matched (`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

#### Scenario: Platform gate

- **WHEN** the architecture, the distribution metadata, or the matched family's package manager is unsupported or
  missing
- **THEN** the install fails with a message naming what is unsupported, and nothing is downloaded or installed
