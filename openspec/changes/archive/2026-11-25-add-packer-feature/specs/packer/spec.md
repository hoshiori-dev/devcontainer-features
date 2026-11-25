# Spec Delta

## Purpose

Installs HashiCorp Packer's `packer` command, which builds machine images from templates, from upstream's signed release
archives at a chosen release or the one upstream reports as current, on `PATH` for every user of the container. It
installs no Packer plugin, writes no Packer configuration, and grants the container no privilege.

Upstream sources:

- Project home: https://developer.hashicorp.com/packer
- Documentation: https://developer.hashicorp.com/packer/docs
- Installation guide: https://developer.hashicorp.com/packer/install
- Source and README: https://github.com/hashicorp/packer
- Changelog: https://github.com/hashicorp/packer/blob/main/CHANGELOG.md
- Release verification guide: https://developer.hashicorp.com/well-architected-framework/verify-hashicorp-binary

## ADDED Requirements

### Requirement: packer on PATH for every user

The feature SHALL install the `packer` executable at `/usr/local/bin/packer`, executable by every user, so that `packer`
resolves to it on the default `PATH` of the remote user and of root, including on an image that already has another
`packer` command in a system directory.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/packer/compatibility.json`
- **THEN** `command -v packer` run as the remote user resolves, following symbolic links, to `/usr/local/bin/packer`
- **AND** `packer version` run as the remote user exits 0

#### Scenario: Template with built-in components

- **WHEN** the feature has been installed and the remote user, in an empty directory holding one template that uses only
  the built-in `null` builder and `shell-local` provisioner to write a constant string to a file, runs `packer validate`
  and then `packer build` on that directory
- **THEN** each command exits 0, and the file holds the constant string

#### Scenario: Image with another packer command

- **WHEN** the feature is installed on an image whose `/usr/sbin/packer` belongs to another package
- **THEN** `command -v packer` run as the remote user resolves, following symbolic links, to `/usr/local/bin/packer`,
  and `/usr/sbin/packer` is left as it was

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** the first line of `packer version` names the release that upstream's Checkpoint service reported as current
  during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.15.4`
- **THEN** the first line of `packer version` is `Packer v1.15.4`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v1.15.4`
- **THEN** the first line of `packer version` is `Packer v1.15.4`

#### Scenario: Current version of an unusable form

- **WHEN** the feature is installed with `version` set to `latest` and the Checkpoint answer names no current version,
  more than one, or one that is not a release version at or above `1.7.0`, such as a pre-release
- **THEN** the install fails before downloading any checksum list or archive, with a message naming what was received,
  and `/usr/local/bin/packer` is left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `1.6.6`
- **THEN** the install fails before downloading anything, with a message naming `1.7.0` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `1.15`, `main`, or `1.12.0-alpha1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `packer` is installed

### Requirement: Packer release version selection

The feature SHALL install the release `version` selects: `latest` means the value of `current_version` in the answer of
https://checkpoint-api.hashicorp.com/v1/check/packer at build time, which is the release upstream reports as current,
and any other value is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `1.7.0`, with or without a
leading `v`.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the Checkpoint answer over HTTPS without following a redirect, and installs the release whose
  version the answer's single `current_version` names

### Requirement: Packer version rejection

The feature SHALL reject any `version` value other than `latest` or a release version `MAJOR.MINOR.PATCH` of decimal
numbers at or above `1.7.0`, with or without a leading `v`, before downloading anything, and SHALL fail before
downloading any checksum list or archive when `latest` resolves to a value of any other form.

#### Scenario: Pre-release requested

- **WHEN** the feature is installed with `version` set to the version of a pre-release, such as `1.11.0-beta` or
  `1.12.0-alpha1`
- **THEN** the install fails before downloading anything

### Requirement: Packer release assets

The feature SHALL download, from `https://releases.hashicorp.com/packer/<version>/`, the archive
`packer_<version>_linux_<arch>.zip`, the checksum list `packer_<version>_SHA256SUMS`, and its signature
`packer_<version>_SHA256SUMS.sig`, where `<version>` has no leading `v` and `<arch>` is `amd64` or `arm64`, over HTTPS
without following a redirect, and SHALL fail when the release has no archive for the architecture.

#### Scenario: Release without an archive for the architecture

- **WHEN** the requested release has no archive for the machine's architecture
- **THEN** the install fails, and `/usr/local/bin/packer` is left as it was before the install

#### Scenario: Redirect answered

- **WHEN** a URL the feature requests answers with a redirect
- **THEN** the install fails without requesting the redirect's target, and `/usr/local/bin/packer` is left as it was
  before the install

### Requirement: Packer release signature

The feature SHALL fetch upstream's public key from `https://www.hashicorp.com/.well-known/pgp-key.txt` and accept the
checksum list only when its detached signature is a good OpenPGP signature by the key whose primary fingerprint is
`C874011F0AB405110D02105534365D9472D7468F`, verified in a keyring used for this install alone.

#### Scenario: Signature by the pinned key

- **WHEN** the checksum list carries a good signature by a signing subkey of the pinned key
- **THEN** the feature checks the archive against the checksum list

#### Scenario: Signature by another key

- **WHEN** the checksum list carries a good signature by a key whose primary fingerprint differs from the pinned one,
  whether or not the fetched key file holds that key
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/packer` is left as it was
  before the install

#### Scenario: Invalid or missing signature

- **WHEN** the checksum list was altered after signing, or the release has no signature file for it
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/packer` is left as it was
  before the install

#### Scenario: Key unavailable

- **WHEN** `https://www.hashicorp.com/.well-known/pgp-key.txt` cannot be fetched
- **THEN** the install fails with a message naming the URL, and `/usr/local/bin/packer` is left as it was before the
  install

### Requirement: Packer archive checksum

The feature SHALL install the archive's `packer` only when the verified checksum list holds exactly one entry whose file
name equals the archive's name and the archive's SHA-256 digest equals that entry, and SHALL install no other file of
the archive.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its single entry in the checksum list
- **THEN** the feature installs the `packer` from that archive, and nothing else from it

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/packer` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/packer` is left as it was
  before the install

### Requirement: Packer release metadata trust

The feature SHALL rely on TLS alone for the Checkpoint answer, which upstream does not sign: a tampered answer can
select another signed release at or above the minimum, never an unsigned build. The public key also relies on TLS alone,
which does not weaken the signature check, since only the pinned fingerprint is accepted.

#### Scenario: Latest resolved to a signed release

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** the release the Checkpoint answer names is verified against its signed checksum list like an explicit version

### Requirement: No Packer plugins or configuration

The feature SHALL offer no option for a plugin, credential, token, template, or configuration path; SHALL install no
Packer plugin and leave no Packer configuration, plugin, or cache directory in the image; SHALL NOT write any file under
a user's home directory, set container environment variables, declare a mount, or edit shell startup files; and SHALL
request no editor extension and install no shell completion.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds `.config/packer`, `.packer.d`, `.packerconfig`, or
  `.cache/packer`, or a `.gnupg` directory that holds a file
- **AND** no environment variable whose name starts with `PACKER_` or `CHECKPOINT_` is set in the remote user's
  environment

#### Scenario: Metadata declarations

- **WHEN** a tool reads the feature's metadata
- **THEN** it declares no mount, container environment variable, editor customization, or lifecycle command

### Requirement: Install Packer prerequisites from configured repositories

The feature SHALL install curl, CA certificates, GnuPG, and unzip, only when the image lacks them, from the package
repositories the image already configures, with the package manager of the distribution's family, and SHALL add no
package repository or signing key. When nothing is missing, it SHALL run no package manager. What it installs this way
stays in the image.

#### Scenario: Minimal image

- **WHEN** the feature is installed with default options on an image that lacks curl, GnuPG, and unzip
- **THEN** the install succeeds, and `curl`, `gpg`, and `unzip` are on `PATH` afterwards

#### Scenario: Prerequisites already present

- **WHEN** the feature is installed on an image that has all prerequisites
- **THEN** the install runs no package manager

### Requirement: Upgrade Arch Linux packages with a missing Packer prerequisite

On Arch Linux, whose package manager supports installing a package only together with a full system upgrade, installing
a missing prerequisite SHALL also upgrade the image's packages.

#### Scenario: Missing prerequisite on Arch Linux

- **WHEN** the feature is installed on an Arch Linux image that lacks a prerequisite
- **THEN** the prerequisite is installed together with an upgrade of the image's packages, and the image's package
  repository configuration and signing keys are unchanged

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/packer/compatibility.json` and reject unsupported platforms
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

### Requirement: Packer platform gate

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
- **THEN** both installs succeed, the second leaves `/usr/local/bin/packer` unchanged, and `packer version` names that
  release

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `packer version` names the release the second install selected
- **AND** `command -v packer` resolves, following symbolic links, to `/usr/local/bin/packer`, and `/usr/local/bin` holds
  no file other than `packer` whose name contains `packer`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/packer` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `packer version` names the requested release

#### Scenario: Target that is not a regular file

- **WHEN** `/usr/local/bin/packer` exists as a directory, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and the directory is left as
  it was

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `packer version` still names the release of the first install

### Requirement: Packer replacement safety

When the installed `/usr/local/bin/packer` already reports the requested release, a second install SHALL leave it
untouched and download no archive; otherwise, including when its version cannot be read, the release of the later
install SHALL replace it, so that the later options win and exactly one `packer` remains in `/usr/local/bin`. A second
install that fails SHALL leave the earlier `packer` in place.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`
- **THEN** the second install leaves `/usr/local/bin/packer` unchanged and downloads no archive

### Requirement: Packer non-regular target

When `/usr/local/bin/packer` exists but is not a regular file, the install SHALL fail before downloading anything, with
a message naming the path, and leave it as it is.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/packer` exists but is not a regular file, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: Leave no build residue

The feature SHALL leave in the package manager's cache no package index or downloaded package that its own
package-manager run fetched, and SHALL install with `apk` without keeping a cache. No temporary directory, keyring, or
staged file of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/packer/compatibility.json`
- **THEN** apt's package lists, dnf's cache, zypper's cache, pacman's package cache, and apk's cache hold no package
  index or downloaded package that the install fetched

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory, keyring, or staged file of the install remains in the temporary directory or in
  `/usr/local/bin`
