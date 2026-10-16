# gitleaks Specification

## Purpose

Installs the Gitleaks secrets scanner (`gitleaks`) from upstream's release artifacts at a chosen or the latest version,
on `PATH` for every user of the container, and deliberately writes no scan configuration. Upstream maintains Gitleaks
for security fixes only; the feature exists for parity with pipelines that still run it.

Upstream sources:

- Project home and README: https://github.com/gitleaks/gitleaks
- Website: https://gitleaks.io
- Releases and changelog: https://github.com/gitleaks/gitleaks/releases
- Successor: https://github.com/betterleaks/betterleaks

## Requirements

### Requirement: gitleaks on PATH for every user

The feature SHALL install the `gitleaks` executable at `/usr/local/bin/gitleaks`, executable by every user, so that
`gitleaks` resolves to it on the default `PATH` of the remote user and of root. It SHALL make `git` available, which
gitleaks runs to scan a repository's history, installing it when the image lacks it.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/gitleaks/compatibility.json`
- **THEN** `command -v gitleaks` run as the remote user resolves, following symbolic links, to `/usr/local/bin/gitleaks`
- **AND** `gitleaks version` run as the remote user exits 0
- **AND** `git --version` run as the remote user exits 0

#### Scenario: Scan of a repository

- **WHEN** the feature has been installed and the remote user runs `gitleaks git` on a Git repository whose history
  holds no secret
- **THEN** the command exits 0

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the release it selects: `latest` means the
release that https://github.com/gitleaks/gitleaks/releases/latest redirects to at build time, which GitHub keeps at the
newest release not marked as a pre-release, and any other value is a release version `MAJOR.MINOR.PATCH` of decimal
numbers at or above `8.2.0`, with or without a leading `v`; the feature SHALL reject any other value before downloading
anything, and SHALL fail before downloading any archive when `latest` resolves to a tag of any other form.

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

The feature SHALL download the release archive from
`https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_linux_<arch>.tar.gz` and its
checksum list from `https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_checksums.txt`,
where `<version>` has no leading `v` and `<arch>` is `x64` or `arm64`, over HTTPS only, including every redirect, and
SHALL fail when the requested release has no archive for the architecture. It SHALL install the archive's `gitleaks`
only when the checksum list holds exactly one entry whose file name equals the archive's name and the archive's SHA-256
digest equals that entry. The feature SHALL rely on TLS alone for the checksum list itself, which upstream publishes
unsigned from the same origin as the archive, so this verification establishes the archive's integrity against the
published release, not the publisher's authenticity. To resolve `latest`, the feature SHALL read the redirect of the
latest-release link over HTTPS without following it and SHALL rely on TLS alone for it, since upstream publishes no
checksum or signature for it.

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

The feature SHALL support the images and architectures listed in `test/gitleaks/compatibility.json`. It SHALL fail,
before downloading or installing anything, with a message naming what is unsupported when the machine architecture is
neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or `ID_LIKE`, a distribution
outside the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package manager of the family it
matched (`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

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

### Requirement: No scan configuration

The feature SHALL offer no option for a scan configuration, a baseline, a credential, or a hook. It SHALL leave no
gitleaks configuration anywhere in the image, SHALL NOT write any file under a user's home directory, set container
environment variables, edit shell startup files, or install a Git hook, and SHALL NOT run a scan during the build.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds a file or directory whose name contains `gitleaks`
- **AND** no environment variable whose name starts with `GITLEAKS_` is set in the remote user's environment

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. When the installed `/usr/local/bin/gitleaks`
already reports the requested version, the second install SHALL leave it untouched and download no archive; otherwise,
including when the installed binary's version cannot be read, the version of the later install SHALL replace it, so that
the later options win and exactly one `gitleaks` remains. When `/usr/local/bin/gitleaks` exists but is not a regular
file, the install SHALL fail before downloading anything, with a message naming the path, and leave it as it is. A
second install that fails SHALL leave the earlier `gitleaks` in place.

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

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the prerequisites it
installs: after installing with `apt-get` it SHALL leave apt's package lists empty, after installing with `dnf` it SHALL
leave dnf's cache without metadata or downloaded packages, and it SHALL install with `apk` without keeping a cache. No
temporary directory or staged binary of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/gitleaks/compatibility.json`
- **THEN** apt's package lists, dnf's cache, and apk's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory or staged binary of the install remains in the temporary directory or in
  `/usr/local/bin`
