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
- **THEN** `gitleaks version` reports the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `8.28.0`
- **THEN** `gitleaks version` reports `8.28.0`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v8.28.0`
- **THEN** `gitleaks version` reports `8.28.0`

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag that is
  not a release version at or above `8.2.0`, such as a `-test` tag
- **THEN** the install fails before downloading any archive, with a message naming the tag, and
  `/usr/local/bin/gitleaks` is left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `8.1.2`
- **THEN** the install fails before downloading anything, with a message naming `8.2.0` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `8.28`, `master`, or `8.15.1-test3`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `gitleaks` is installed

### Requirement: Verified download from the GitHub release

The feature SHALL download and verify the selected GitHub release archive before installing `gitleaks`.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its entry in the checksum list
- **THEN** the feature installs the `gitleaks` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/gitleaks` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/gitleaks` is left as it was
  before the install

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/gitleaks/compatibility.json` and reject unsupported
platforms before changes.

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

### Requirement: Installing twice

A second install SHALL succeed, apply later options, and preserve the earlier executable if the second install fails.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same `version`
- **THEN** both installs succeed, the second leaves `/usr/local/bin/gitleaks` unchanged, and `gitleaks version` reports
  that version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `gitleaks version` reports the version the second install selected
- **AND** `command -v gitleaks` resolves, following symbolic links, to `/usr/local/bin/gitleaks`, and `/usr/local/bin`
  holds no file other than `gitleaks` whose name contains `gitleaks`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/gitleaks` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `gitleaks version` reports the requested version

#### Scenario: Target that is not a regular file

- **WHEN** `/usr/local/bin/gitleaks` exists as a directory, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and the directory is left as
  it was

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `gitleaks version` still reports the version of the first install

## ADDED Requirements

### Requirement: Gitleaks release version selection

`latest` SHALL resolve the newest non-prerelease release through `https://github.com/gitleaks/gitleaks/releases/latest`.
Explicit versions SHALL be decimal `MAJOR.MINOR.PATCH` at or above `8.2.0`, optionally prefixed by `v`; other forms
SHALL fail before downloads. A latest tag outside this grammar also SHALL fail before archive download.

#### Scenario: Unsupported version form

- **WHEN** an explicit version is malformed or below `8.2.0`, or latest resolves to a malformed tag
- **THEN** installation fails before downloads and names the invalid value or tag

### Requirement: Gitleaks release assets and checksum

The feature SHALL fetch
`https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_linux_<arch>.tar.gz` and
`https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_checksums.txt`, where version
omits `v` and architecture is `x64` or `arm64`. It SHALL install only the archive's `gitleaks` executable after exactly
one matching checksum-list entry agrees with its SHA-256; an absent architecture asset fails.

#### Scenario: Missing or ambiguous archive checksum

- **WHEN** the requested archive is absent or its checksum list has no unique matching filename
- **THEN** installation fails and uses no substitute asset or checksum entry

### Requirement: Gitleaks release metadata trust

All requests and redirects SHALL use HTTPS. The feature SHALL resolve `latest` from the HTTPS redirect without following
it and rely on TLS alone because upstream provides no checksum or signature for the redirect. It SHALL rely on TLS alone
for the unsigned checksum list from the archive's origin; checksum verification establishes archive integrity against
that list, not publisher authenticity.

#### Scenario: Unsigned checksum list

- **WHEN** the feature verifies a release archive
- **THEN** it uses HTTPS throughout and treats the unsigned checksum list as TLS-delivered metadata, not proof of
  publisher authenticity

### Requirement: Gitleaks platform gate

The feature SHALL require x86_64 or aarch64 and `/etc/os-release` `ID` or `ID_LIKE` identifying Debian, Ubuntu, Fedora,
or Alpine. It SHALL require `apt-get` on Debian/Ubuntu, `dnf` on Fedora, and `apk` on Alpine. Missing os-release,
unsupported family or architecture, and a missing family package manager SHALL fail before download or installation and
name the unsupported item.

#### Scenario: Unsupported platform prerequisite

- **WHEN** the architecture, distribution metadata, or matched family's package manager is unsupported or missing
- **THEN** installation fails before download or installation and names the unsupported item

### Requirement: Gitleaks replacement safety

When `/usr/local/bin/gitleaks` already reports the requested version, a second install SHALL leave it untouched and
download no archive. Otherwise, including when its version is unreadable, the later release SHALL replace it and leave
exactly one `gitleaks`. If the path exists but is not a regular file, installation SHALL fail before downloads and leave
it unchanged; any failed second install SHALL preserve the first executable.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/gitleaks` exists but is not a regular file
- **THEN** installation fails before downloads, names the path, and leaves it unchanged
