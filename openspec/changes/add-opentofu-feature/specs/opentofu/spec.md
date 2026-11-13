## Purpose

Installs OpenTofu's `tofu` command, which plans and applies infrastructure-as-code configurations, from upstream's
signed release archives at a chosen release or the one upstream marks as latest, on `PATH` for every user of the
container, and requests upstream's VS Code extension. It writes no OpenTofu configuration and grants the container no
privilege.

Upstream sources:

- Project home: https://opentofu.org
- Documentation: https://opentofu.org/docs/
- Installation guide: https://opentofu.org/docs/intro/install/
- Source and README: https://github.com/opentofu/opentofu
- Changelog: https://github.com/opentofu/opentofu/blob/main/CHANGELOG.md
- VS Code extension: https://github.com/opentofu/vscode-opentofu

## ADDED Requirements

### Requirement: tofu on PATH for every user

The feature SHALL install the `tofu` executable at `/usr/local/bin/tofu`, executable by every user, so that `tofu`
resolves to it on the default `PATH` of the remote user and of root.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/opentofu/compatibility.json`
- **THEN** `command -v tofu` run as the remote user resolves, following symbolic links, to `/usr/local/bin/tofu`
- **AND** `tofu version` run as the remote user exits 0

#### Scenario: Configuration without providers

- **WHEN** the feature has been installed and the remote user, in an empty directory holding one configuration file that
  declares only an output with a constant string value, runs `tofu init`, then `tofu apply -auto-approve`, then
  `tofu output -raw` for that output
- **THEN** each command exits 0, and the last one prints the constant string

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** the first line of `tofu version` names the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.12.12`
- **THEN** the first line of `tofu version` is `OpenTofu v1.12.12`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v1.12.12`
- **THEN** the first line of `tofu version` is `OpenTofu v1.12.12`

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag that is
  not a release version at or above `1.6.3`, such as a pre-release tag
- **THEN** the install fails before downloading any checksum list or archive, with a message naming the tag, and
  `/usr/local/bin/tofu` is left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `1.6.2`
- **THEN** the install fails before downloading anything, with a message naming `1.6.3` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `1.13`, `main`, or `1.13.0-rc1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `tofu` is installed

### Requirement: OpenTofu release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://github.com/opentofu/opentofu/releases/latest redirects to at build time, which is the release upstream marks as
latest on GitHub, and any other value is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `1.6.3`,
with or without a leading `v`.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the latest-release link's redirect over HTTPS without following it, and installs the release the
  redirect names

### Requirement: OpenTofu version rejection

The feature SHALL reject any `version` value other than `latest` or a release version `MAJOR.MINOR.PATCH` of decimal
numbers at or above `1.6.3`, with or without a leading `v`, before downloading anything, and SHALL fail before
downloading any checksum list or archive when `latest` resolves to a tag of any other form.

#### Scenario: Pre-release requested

- **WHEN** the feature is installed with `version` set to the version of a pre-release, such as `1.13.0-rc1` or
  `1.13.0-beta1`
- **THEN** the install fails before downloading anything

### Requirement: OpenTofu release assets

The feature SHALL download, from `https://github.com/opentofu/opentofu/releases/download/v<version>/`, the archive
`tofu_<version>_linux_<arch>.tar.gz`, the checksum list `tofu_<version>_SHA256SUMS`, and its signature
`tofu_<version>_SHA256SUMS.gpgsig`, where `<version>` has no leading `v` and `<arch>` is `amd64` or `arm64`, over HTTPS
on every hop including redirects, and SHALL fail when the release has no archive for the architecture.

#### Scenario: Release without an archive for the architecture

- **WHEN** the requested release has no archive for the machine's architecture
- **THEN** the install fails, and `/usr/local/bin/tofu` is left as it was before the install

#### Scenario: Redirect to a plain HTTP URL

- **WHEN** a URL the feature requests redirects to a URL whose scheme is not HTTPS
- **THEN** the install fails without requesting the redirect's target, and `/usr/local/bin/tofu` is left as it was
  before the install

### Requirement: OpenTofu release signature

The feature SHALL fetch upstream's public key from `https://get.opentofu.org/opentofu.asc` and accept the checksum list
only when its detached signature is a good OpenPGP signature by the key whose primary fingerprint is
`E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80`, verified in a keyring used for this install alone.

#### Scenario: Signature by the pinned key

- **WHEN** the checksum list carries a good signature by the pinned key
- **THEN** the feature checks the archive against the checksum list

#### Scenario: Signature by another key

- **WHEN** the checksum list carries a good signature by a key whose primary fingerprint differs from the pinned one,
  whether or not the fetched key file holds that key
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/tofu` is left as it was
  before the install

#### Scenario: Invalid or missing signature

- **WHEN** the checksum list was altered after signing, or the release has no signature file for it
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/tofu` is left as it was
  before the install

#### Scenario: Key unavailable

- **WHEN** `https://get.opentofu.org/opentofu.asc` cannot be fetched
- **THEN** the install fails with a message naming the URL, and `/usr/local/bin/tofu` is left as it was before the
  install

### Requirement: OpenTofu archive checksum

The feature SHALL install the archive's `tofu` only when the verified checksum list holds exactly one entry whose file
name equals the archive's name and the archive's SHA-256 digest equals that entry.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its single entry in the checksum list
- **THEN** the feature installs the `tofu` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/tofu` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/tofu` is left as it was
  before the install

### Requirement: OpenTofu release metadata trust

The feature SHALL rely on TLS alone for the latest-release link, which upstream does not sign: a tampered redirect can
select another signed release at or above the minimum, never an unsigned build. The public key also relies on TLS alone,
which does not weaken the signature check, since only the pinned fingerprint is accepted.

#### Scenario: Latest resolved to a signed release

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** the release the redirect names is verified against its signed checksum list like an explicit version

### Requirement: OpenTofu editor extension

The feature SHALL request the VS Code extension `opentofu.vscode-opentofu` through VS Code customizations, and SHALL
declare no editor settings.

#### Scenario: Extension declaration

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** its extension list requests `opentofu.vscode-opentofu`, and the feature declares no setting

### Requirement: No OpenTofu configuration

The feature SHALL offer no option for a backend, credential, token, provider, or configuration path; SHALL leave no
OpenTofu configuration in the image; SHALL NOT write any file under a user's home directory, set container environment
variables, or edit shell startup files; and SHALL install no `terraform` command and no shell completion.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds `.terraform.d`, `.terraformrc`, `.tofurc`, or a `.gnupg`
  directory
- **AND** no environment variable whose name starts with `TF_` or `TOFU_` is set in the remote user's environment
- **AND** `terraform` does not resolve on the remote user's `PATH`

### Requirement: Install OpenTofu prerequisites from configured repositories

The feature SHALL install curl, CA certificates, GnuPG, tar, and gzip, only when the image lacks them, from the package
repositories the image already configures, with the package manager of the distribution's family, and SHALL add no
package repository or signing key. When nothing is missing, it SHALL run no package manager. What it installs this way
stays in the image.

#### Scenario: Minimal image

- **WHEN** the feature is installed with default options on an image that lacks curl and GnuPG
- **THEN** the install succeeds, and `curl` and `gpg` are on `PATH` afterwards

#### Scenario: Prerequisites already present

- **WHEN** the feature is installed on an image that has all prerequisites
- **THEN** the install runs no package manager

### Requirement: Upgrade Arch Linux packages with a missing OpenTofu prerequisite

On Arch Linux, whose package manager supports installing a package only together with a full system upgrade, installing
a missing prerequisite SHALL also upgrade the image's packages.

#### Scenario: Missing prerequisite on Arch Linux

- **WHEN** the feature is installed on an Arch Linux image that lacks a prerequisite
- **THEN** the prerequisite is installed together with an upgrade of the image's packages, and the image's package
  repository configuration and signing keys are unchanged

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/opentofu/compatibility.json` and reject unsupported
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

### Requirement: OpenTofu platform gate

The feature SHALL fail before downloading or installing anything, naming what is unsupported, when the architecture is
neither x86_64 nor aarch64; when `/etc/os-release` is missing or its `ID` and `ID_LIKE` name none of the families Debian
or Ubuntu (`apt-get`), Fedora or RHEL (`dnf`), Alpine (`apk`), openSUSE or SUSE (`zypper`), and Arch Linux (`pacman`);
or when the image lacks the matched family's package manager.

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or identifies a
  distribution outside the supported families, or the image lacks the matched family's package manager
- **THEN** the install fails before downloading or installing anything, with a message naming what is unsupported

### Requirement: Installing twice

A second install SHALL succeed, apply later options, and preserve the earlier executable if the second install fails.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second leaves `/usr/local/bin/tofu` unchanged, and `tofu version` names that
  release

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `tofu version` names the release the second install selected
- **AND** `command -v tofu` resolves, following symbolic links, to `/usr/local/bin/tofu`, and `/usr/local/bin` holds no
  file other than `tofu` whose name contains `tofu`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/tofu` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `tofu version` names the requested release

#### Scenario: Target that is not a regular file

- **WHEN** `/usr/local/bin/tofu` exists as a directory, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and the directory is left as
  it was

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `tofu version` still names the release of the first install

### Requirement: OpenTofu replacement safety

When the installed `/usr/local/bin/tofu` already reports the requested release, a second install SHALL leave it
untouched and download no archive; otherwise, including when its version cannot be read, the release of the later
install SHALL replace it, so that the later options win and exactly one `tofu` remains. A second install that fails
SHALL leave the earlier `tofu` in place.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`
- **THEN** the second install leaves `/usr/local/bin/tofu` unchanged and downloads no archive

### Requirement: OpenTofu non-regular target

When `/usr/local/bin/tofu` exists but is not a regular file, the install SHALL fail before downloading anything, with a
message naming the path, and leave it as it is.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/tofu` exists but is not a regular file, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: Leave no build residue

The feature SHALL leave in the package manager's cache no package index or downloaded package that its own
package-manager run fetched, and SHALL install with `apk` without keeping a cache. No temporary directory, keyring, or
staged file of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/opentofu/compatibility.json`
- **THEN** apt's package lists, dnf's cache, zypper's cache, pacman's package cache, and apk's cache hold no package
  index or downloaded package that the install fetched

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory, keyring, or staged file of the install remains in the temporary directory or in
  `/usr/local/bin`
