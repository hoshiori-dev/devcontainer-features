# Spec Delta

## Purpose

Installs rclone (`rclone`), which copies, synchronizes, serves, and mounts files across cloud storage providers, from
upstream's signed release archives at a chosen or the newest stable version, on `PATH` for every user of the container,
with its bash, zsh, and fish completions. On request it installs the FUSE helper `rclone mount` needs; it writes no
rclone configuration and grants the container no privilege.

Upstream sources:

- Project home and documentation: https://rclone.org
- Source and README: https://github.com/rclone/rclone
- Installation guide: https://rclone.org/install/
- Changelog: https://rclone.org/changelog/
- Mount command: https://rclone.org/commands/rclone_mount/

## ADDED Requirements

### Requirement: rclone on PATH for every user

The feature SHALL install the `rclone` executable at `/usr/local/bin/rclone`, executable by every user, so that `rclone`
resolves to it on the default `PATH` of the remote user and of root.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/rclone/compatibility.json`
- **THEN** `command -v rclone` run as the remote user resolves, following symbolic links, to `/usr/local/bin/rclone`
- **AND** `rclone version` run as the remote user exits 0

#### Scenario: Copy between local directories

- **WHEN** the feature has been installed and the remote user, with no rclone configuration, runs `rclone copy` from a
  local directory holding one file to an empty local directory
- **THEN** the command exits 0 and the destination holds a byte-identical copy of the file

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** the first line of `rclone version` names the release that `https://downloads.rclone.org/version.txt` named
  during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `1.70.0`
- **THEN** the first line of `rclone version` is `rclone v1.70.0`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v1.70.0`
- **THEN** the first line of `rclone version` is `rclone v1.70.0`

#### Scenario: Version file naming an unusable release

- **WHEN** the feature is installed with `version` set to `latest` and the version file holds anything other than one
  line `rclone v<version>` naming a release version at or above `1.63.0`
- **THEN** the install fails before downloading any checksum list or archive, with a message quoting what the version
  file holds, and `/usr/local/bin/rclone` is left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `1.62.2`
- **THEN** the install fails before downloading anything, with a message naming `1.63.0` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `1.70`, `master`, or
  `1.77.0-beta.10751.d459c3f99`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `rclone` is installed

### Requirement: rclone release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://downloads.rclone.org/version.txt names at build time in its single line `rclone v<version>`, and any other value
is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above `1.63.0`, with or without a leading `v`.

#### Scenario: Newest stable release

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the version file once over HTTPS and installs the release that file names

### Requirement: rclone version rejection

The feature SHALL reject any `version` value other than `latest` or a release version `MAJOR.MINOR.PATCH` of decimal
numbers at or above `1.63.0`, with or without a leading `v`, before downloading anything, and SHALL fail before
downloading any checksum list or archive when the version file names a release of any other form.

#### Scenario: Beta build requested

- **WHEN** the feature is installed with `version` set to the version of a beta build, such as
  `1.77.0-beta.10751.d459c3f99`
- **THEN** the install fails before downloading anything

### Requirement: rclone release assets

The feature SHALL download the release archive from
`https://downloads.rclone.org/v<version>/rclone-v<version>-linux-<arch>.zip` and its checksum list from
`https://downloads.rclone.org/v<version>/SHA256SUMS`, where `<version>` has no leading `v` and `<arch>` is `amd64` or
`arm64`, and SHALL fail when the release has no archive for the architecture. It SHALL make every request over HTTPS and
fail on a redirect instead of following it.

#### Scenario: Release without an archive for the architecture

- **WHEN** the requested release has no archive for the machine's architecture
- **THEN** the install fails, and `/usr/local/bin/rclone` is left as it was before the install

#### Scenario: Redirect from an upstream URL

- **WHEN** a URL the feature requests answers with a redirect
- **THEN** the install fails without requesting the redirect's target, and `/usr/local/bin/rclone` is left as it was
  before the install

### Requirement: rclone release signature

The feature SHALL fetch upstream's key list from `https://rclone.org/KEYS` and accept the checksum list only when it
carries a good OpenPGP clearsigned signature by the key whose primary fingerprint is
`FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA`, verified in a keyring used for this install alone. It SHALL look up the
archive's checksum only in the text that signature covers.

#### Scenario: Signature by the pinned key

- **WHEN** the checksum list carries a good signature by the pinned key
- **THEN** the feature checks the archive against the signed text

#### Scenario: Signature by another key

- **WHEN** the checksum list carries a good signature by a key whose primary fingerprint differs from the pinned one,
  whether or not the key list holds that key
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/rclone` is left as it was
  before the install

#### Scenario: Invalid or missing signature

- **WHEN** the checksum list's signed text was altered after signing, or the checksum list carries no signature
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/rclone` is left as it was
  before the install

#### Scenario: Entry outside the signed text

- **WHEN** the checksum list holds the archive's entry only outside the text the signature covers
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/rclone` is left as it was
  before the install

#### Scenario: Key list unavailable

- **WHEN** `https://rclone.org/KEYS` cannot be fetched
- **THEN** the install fails with a message naming the URL, and `/usr/local/bin/rclone` is left as it was before the
  install

### Requirement: rclone signing key strength

The feature SHALL accept upstream's signature although the pinned key is a DSA-1024 key that signs with SHA-1 digests,
both below current recommendations, because upstream publishes no other signature and the alternative is TLS alone. It
SHALL NOT weaken GnuPG's checks to do so: when the GnuPG in the image refuses that key or digest, the install fails
instead of falling back.

#### Scenario: GnuPG refusing the signature algorithm

- **WHEN** the image's GnuPG refuses the signature's key or digest algorithm
- **THEN** the install fails with a message saying verification failed, and nothing is installed

### Requirement: rclone archive checksum

The feature SHALL install the archive's `rclone` only when the signed text holds exactly one entry whose file name
equals the archive's name and the archive's SHA-256 digest equals that entry.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its single entry in the signed text
- **THEN** the feature installs the `rclone` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the signed text
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/rclone` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the signed text holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/rclone` is left as it was
  before the install

### Requirement: rclone release metadata trust

The feature SHALL rely on TLS alone for https://downloads.rclone.org/version.txt, which upstream publishes unsigned: a
tampered version file can select an older signed release at or above the minimum, never an unsigned build. The key list
also relies on TLS alone, which does not weaken the signature check, since only the pinned fingerprint is accepted.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** the release the version file names is verified against the signed checksum list like an explicit version

### Requirement: Shell completions

On every successful install the feature SHALL write the completion scripts the installed `rclone` generates for bash,
zsh, and fish to `/usr/local/share/bash-completion/completions/rclone`, `/usr/local/share/zsh/site-functions/_rclone`,
and `/usr/share/fish/vendor_completions.d/rclone.fish`, readable by every user, replacing any file there. It SHALL NOT
install bash, bash-completion, zsh, or fish.

#### Scenario: Completion files after install

- **WHEN** the feature has been installed with default options
- **THEN** the three files exist as regular files readable by every user, and each equals what
  `rclone completion <shell> -` of the installed `rclone` prints for its shell

#### Scenario: Completion in bash

- **WHEN** the feature has been installed on an image whose interactive bash loads bash-completion
- **THEN** in an interactive bash of the remote user, loading the completion for `rclone` through bash-completion
  defines a completion for `rclone`

#### Scenario: Completion in zsh

- **WHEN** the feature has been installed on an image whose interactive zsh initializes its completion system
- **THEN** the remote user's interactive zsh finds `_rclone` on its function path

#### Scenario: Image without the shells

- **WHEN** the feature is installed on an image without bash-completion, zsh, and fish
- **THEN** the three files are written and none of bash-completion, zsh, and fish is installed

### Requirement: Option installMountDependencies

The feature SHALL accept the option `installMountDependencies` as declared here: when it is enabled, the feature
installs the distribution package `fuse3`, which provides `fusermount3`; when it is disabled, it installs no FUSE
package; a value that is neither `true` nor `false` fails the install before anything is downloaded.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted installMountDependencies

- **WHEN** the feature is installed without `installMountDependencies` on an image without `fusermount3`
- **THEN** `fusermount3` is still absent after the install

#### Scenario: Mount dependencies enabled

- **WHEN** the feature is installed with `installMountDependencies` set to `true`
- **THEN** `fusermount3` resolves on the remote user's `PATH`, owned by root and with the set-user-ID bit

#### Scenario: Invalid installMountDependencies

- **WHEN** the feature is installed with `installMountDependencies` set to a value that is neither `true` nor `false`
- **THEN** the install fails before anything is downloaded, with a message naming the option

### Requirement: Packages installed

Apart from `fuse3` under `installMountDependencies`, the feature SHALL install only the packages it needs to download
and verify the release (curl, CA certificates, GnuPG, and unzip), only when the image lacks them, from the image's own
package repositories, and SHALL leave them installed.

#### Scenario: Minimal image

- **WHEN** the feature is installed with default options on an image that lacks curl, GnuPG, and unzip
- **THEN** the install succeeds, and `curl`, `gpg`, and `unzip` are on `PATH` afterwards

### Requirement: Mounts left to the user

The feature SHALL NOT start a mount, a transfer, or an `rclone` process other than its own build-time calls to read the
installed version and generate completions, at build time, at container start, or later; SHALL NOT grant the container
privileges, capabilities, devices, security options, or mounts; and SHALL NOT change `/etc/fuse.conf` or the sudo
configuration. Its notes SHALL name the container settings a mount needs.

#### Scenario: Container starts with no mount

- **WHEN** a container is started from an image with the feature installed with `installMountDependencies` enabled
- **THEN** no `rclone` process runs, no FUSE filesystem is mounted, and the feature has added no uncommented
  `user_allow_other` line to `/etc/fuse.conf`

### Requirement: No rclone configuration

The feature SHALL offer no option for a remote, a credential, a token, or a configuration path; SHALL leave no rclone
configuration anywhere in the image; and SHALL NOT write any file under a user's home directory, set container
environment variables, or edit shell startup files.

#### Scenario: Nothing configured after install

- **WHEN** the feature has been installed
- **THEN** neither the remote user's nor root's home holds `.config/rclone`, `.cache/rclone`, `.rclone.conf`, or a
  `.gnupg` directory
- **AND** no environment variable whose name starts with `RCLONE_` is set in the remote user's environment

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/rclone/compatibility.json` and reject unsupported platforms
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

### Requirement: rclone platform gate

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package
manager of the family it matched (`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or identifies a
  distribution outside the supported families, or the image lacks the matched family's package manager
- **THEN** the install fails before downloading or installing anything, with a message naming what is unsupported

### Requirement: Installing twice

A second install SHALL succeed, apply later options, and preserve the earlier executable and completion files if the
second install fails.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second leaves `/usr/local/bin/rclone` unchanged, and `rclone version` names that
  release

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, `rclone version` names the release the second install selected, and the completion
  files equal what that release generates
- **AND** `command -v rclone` resolves, following symbolic links, to `/usr/local/bin/rclone`, and `/usr/local/bin` holds
  no file other than `rclone` whose name contains `rclone`

#### Scenario: Mount dependencies enabled, then disabled

- **WHEN** the feature is installed with `installMountDependencies` enabled and then with it disabled
- **THEN** both installs succeed and `fusermount3` is still present

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/rclone` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `rclone version` names the requested release

#### Scenario: Target that is not a regular file

- **WHEN** `/usr/local/bin/rclone` exists as a directory, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and the directory is left as
  it was

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `rclone version` still names the release of the first install, and the completion files are unchanged

### Requirement: rclone replacement safety

When the installed `/usr/local/bin/rclone` already reports the requested release, a second install SHALL leave it
untouched and download no archive; otherwise, including when its version cannot be read, the release of the later
install SHALL replace it, so that the later options win and exactly one `rclone` remains. A second install that fails
SHALL leave the earlier `rclone` and completion files in place.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`
- **THEN** the second install leaves `/usr/local/bin/rclone` unchanged and downloads no archive

### Requirement: rclone non-regular target

When `/usr/local/bin/rclone` or one of the completion file paths exists but is not a regular file, the install SHALL
fail before downloading anything, with a message naming the path, and leave it as it is.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/rclone` or a completion file path exists but is not a regular file, and the feature is
  installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the packages it installs:
after installing with `apt-get` it SHALL leave apt's package lists empty, after installing with `dnf` it SHALL leave
dnf's cache without metadata or downloaded packages, and it SHALL install with `apk` without keeping a cache. No
temporary directory, keyring, or staged file of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/rclone/compatibility.json`
- **THEN** apt's package lists, dnf's cache, and apk's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory, keyring, or staged file of the install remains in the temporary directory, in
  `/usr/local/bin`, or beside a completion file
