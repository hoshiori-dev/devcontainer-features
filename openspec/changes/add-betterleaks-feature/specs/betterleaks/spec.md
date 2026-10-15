# Spec Delta

## Purpose

Installs the Betterleaks secrets scanner (`betterleaks`) from upstream's release artifacts at a chosen or the latest
stable version, on `PATH` for every user of the container, and deliberately writes no scan configuration.

Upstream sources:

- Project home and README: https://github.com/betterleaks/betterleaks
- Website: https://betterleaks.com
- Scanning guide: https://github.com/betterleaks/betterleaks/blob/main/docs/scanning.md
- Configuration reference: https://github.com/betterleaks/betterleaks/blob/main/docs/config.md
- Releases and changelog: https://github.com/betterleaks/betterleaks/releases

## ADDED Requirements

### Requirement: betterleaks on PATH for every user

The feature SHALL install the `betterleaks` executable at `/usr/local/bin/betterleaks`, executable by every user, so
that `betterleaks` resolves to it on the default `PATH` of the remote user and of root. It SHALL make `git` available,
which betterleaks runs to scan a repository's history, installing it when the image lacks it.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/betterleaks/compatibility.json`
- **THEN** `command -v betterleaks` run as the remote user resolves, following symbolic links, to
  `/usr/local/bin/betterleaks`
- **AND** `betterleaks version` run as the remote user exits 0
- **AND** `git --version` run as the remote user exits 0

#### Scenario: Scan of a repository

- **WHEN** the feature has been installed and the remote user runs `betterleaks git` on a Git repository whose history
  holds no secret
- **THEN** the command exits 0 and reports no finding

### Requirement: Option version

The feature SHALL accept the option `version` as declared here and install the release it selects: `latest` means the
release that https://github.com/betterleaks/betterleaks/releases/latest redirects to at build time, which GitHub keeps
at the newest release not marked as a pre-release, and any other value is a release version `MAJOR.MINOR.PATCH` of
decimal numbers at or above `1.0.1`, optionally followed by a pre-release suffix `-rc.N` of a decimal number, with or
without a leading `v`; the feature SHALL reject any other value before downloading anything, and SHALL fail before
downloading any archive when `latest` resolves to a tag of any other form or to a tag carrying a pre-release suffix.

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

The feature SHALL download the release archive from
`https://github.com/betterleaks/betterleaks/releases/download/v<version>/betterleaks_<version>_linux_<arch>.tar.gz` and
its checksum list from `https://github.com/betterleaks/betterleaks/releases/download/v<version>/checksums.txt`, where
`<version>` has no leading `v` and `<arch>` is `x64` or `arm64`, over HTTPS only, including every redirect, and SHALL
fail when the requested release has no archive for the architecture. It SHALL install the archive's `betterleaks` only
when the checksum list holds exactly one entry whose file name equals the archive's name and the archive's SHA-256
digest equals that entry. Upstream also publishes a Sigstore signature bundle for the checksum list
(`checksums.txt.sigstore.json`); the feature SHALL NOT verify it, because no image of its compatibility list ships a
tool that verifies a Sigstore bundle and fetching one would need the same verification first, so the feature relies on
TLS alone for the checksum list and this verification establishes the archive's integrity against the published release,
not the publisher's authenticity. To resolve `latest`, the feature SHALL read the redirect of the latest-release link
over HTTPS without following it and SHALL rely on TLS alone for it, since upstream publishes no checksum or signature
for it.

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

The feature SHALL support the images and architectures listed in `test/betterleaks/compatibility.json`. It SHALL fail,
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
betterleaks configuration anywhere in the image, SHALL NOT write any file under a user's home directory, set container
environment variables, edit shell startup files, or install a Git hook, and SHALL NOT run a scan during the build.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds a file or directory whose name contains `betterleaks`
- **AND** no environment variable whose name starts with `BETTERLEAKS_` is set in the remote user's environment

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. When the installed `/usr/local/bin/betterleaks`
already reports the requested version, the second install SHALL leave it untouched and download no archive; otherwise,
including when the installed binary's version cannot be read, the version of the later install SHALL replace it, so that
the later options win and exactly one `betterleaks` remains. A second install that fails SHALL leave the earlier
`betterleaks` in place.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same `version`
- **THEN** both installs succeed, the second leaves `/usr/local/bin/betterleaks` unchanged, and `betterleaks version`
  reports that version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `betterleaks version` reports the version the second install selected
- **AND** `command -v betterleaks` resolves, following symbolic links, to `/usr/local/bin/betterleaks`, and
  `/usr/local/bin` holds no file other than `betterleaks` whose name contains `betterleaks`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/betterleaks` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `betterleaks version` reports the requested version

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `betterleaks version` still reports the version of the first install

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the prerequisites it
installs: after installing with `apt-get` it SHALL leave apt's package lists empty, after installing with `dnf` it SHALL
leave dnf's cache without metadata or downloaded packages, and it SHALL install with `apk` without keeping a cache. No
temporary directory or staged binary of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in
  `test/betterleaks/compatibility.json`
- **THEN** apt's package lists, dnf's cache, and apk's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory or staged binary of the install remains in the temporary directory or in
  `/usr/local/bin`
