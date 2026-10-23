# Spec Delta

## Purpose

Installs act (`act`), which runs a repository's GitHub Actions workflows locally against a Docker Engine, from
upstream's release artifacts at a chosen or the latest version, on `PATH` for every user of the container. It can
preselect act's default runner images for the remote user; it installs no container engine.

Upstream sources:

- Project home and README: https://github.com/nektos/act
- User guide: https://nektosact.com
- Installation guide: https://nektosact.com/installation/index.html
- Releases and changelog: https://github.com/nektos/act/releases

## ADDED Requirements

### Requirement: act on PATH for every user

The feature SHALL install the `act` executable at `/usr/local/bin/act`, executable by every user, so that `act` resolves
to it on the default `PATH` of the remote user and of root.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/act/compatibility.json`
- **THEN** `command -v act` run as the remote user resolves, following symbolic links, to `/usr/local/bin/act`
- **AND** `act --version` run as the remote user exits 0

#### Scenario: Listing a repository's workflows

- **WHEN** the feature has been installed and the remote user runs `act --list` in a Git repository holding a workflow
  under `.github/workflows/`
- **THEN** the command exits 0 and its output names the workflow's job, without a Docker Engine being reachable

### Requirement: Option version

The feature SHALL accept `version` and install the release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `act --version` reports the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing release such as `0.2.80`
- **THEN** `act --version` reports `0.2.80`

#### Scenario: Leading v accepted

- **WHEN** the feature is installed with `version` set to `v0.2.80`
- **THEN** `act --version` reports `0.2.80`

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag that is
  not a release version at or above `0.2.23`
- **THEN** the install fails before downloading any archive, with a message naming the tag, and `/usr/local/bin/act` is
  left as it was before the install

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to `0.2.22`
- **THEN** the install fails before downloading anything, with a message naming `0.2.23` as the minimum

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `0.2`, `master`, or `0.2.80-rc1`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release
- **THEN** the install fails with a message naming the version, and no `act` is installed

### Requirement: act release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://github.com/nektos/act/releases/latest redirects to at build time, which GitHub keeps at the newest release not
marked as a pre-release, and any other value is a release version `MAJOR.MINOR.PATCH` of decimal numbers at or above
`0.2.23`, with or without a leading `v`.

#### Scenario: Explicit version with a leading v

- **WHEN** the feature is installed with `version` set to `v0.2.80`
- **THEN** `act --version` reports `0.2.80`

### Requirement: act version rejection

The feature SHALL reject any `version` value other than `latest` or a release version `MAJOR.MINOR.PATCH` of decimal
numbers at or above `0.2.23`, with or without a leading `v`, before downloading anything, and SHALL fail before
downloading any archive when `latest` resolves to a tag of any other form.

#### Scenario: Explicit version below the accepted range

- **WHEN** the feature is installed with `version` set to `0.2.22`
- **THEN** the install fails before downloading anything, with a message naming `0.2.23` as the minimum

### Requirement: act release assets

The feature SHALL download the release archive from
`https://github.com/nektos/act/releases/download/v<version>/act_Linux_<arch>.tar.gz` and its checksum list from
`https://github.com/nektos/act/releases/download/v<version>/checksums.txt`, where `<version>` has no leading `v` and
`<arch>` is `x86_64` or `arm64`, over HTTPS only, including every redirect, and SHALL fail when the requested release
has no archive for the architecture.

#### Scenario: Release without an archive for the architecture

- **WHEN** the requested release has no archive for the machine's architecture
- **THEN** the install fails

### Requirement: Verified download from the GitHub release

The feature SHALL download and verify the selected GitHub release archive before installing `act`, and SHALL install the
archive's `act` only when the checksum list holds exactly one entry whose file name equals the archive's name and the
archive's SHA-256 digest equals that entry.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-256 digest equals its entry in the checksum list
- **THEN** the feature installs the `act` from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-256 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/act` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/act` is left as it was
  before the install

### Requirement: act release metadata trust

The feature SHALL rely on TLS alone for the checksum list itself, which upstream publishes unsigned from the same origin
as the archive, so this verification establishes the archive's integrity against the published release, not the
publisher's authenticity. To resolve `latest`, the feature SHALL read the redirect of the latest-release link over HTTPS
without following it and SHALL rely on TLS alone for it, since upstream publishes no checksum or signature for it.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the latest-release link's redirect over HTTPS without following it

### Requirement: Option defaultImage

The feature SHALL accept `defaultImage` and, unless it is `none`, preselect the runner images it names for the remote
user.

| Field   | Value                       |
| ------- | --------------------------- |
| Type    | `string`                    |
| Default | `"none"`                    |
| Enum    | `["none","medium","large"]` |

#### Scenario: Omitted defaultImage

- **WHEN** the feature is installed without `defaultImage`, or with `defaultImage` set to `none`, on an image whose
  remote user has no act configuration file
- **THEN** the remote user's home holds no `.config/act/actrc` and no `.actrc` after the install

#### Scenario: Medium images selected

- **WHEN** the feature is installed with `defaultImage` set to `medium`
- **THEN** the remote user's act configuration file holds the lines that requirement "act default image lines" names for
  `medium`
- **AND** `act --dryrun` run as the remote user without a terminal, in a Git repository holding a workflow whose job
  runs on `ubuntu-latest`, exits 0 without prompting

#### Scenario: Large images selected

- **WHEN** the feature is installed with `defaultImage` set to `large`
- **THEN** the remote user's act configuration file holds the lines that requirement "act default image lines" names for
  `large`

### Requirement: act default image configuration

When `defaultImage` is not `none`, the feature SHALL write the act configuration file `<home>/.config/act/actrc`, where
`<home>` is the remote user's home directory, or root's when no remote user is set, creating the missing directories on
the way. The file and every directory the feature creates SHALL belong to the remote user, and the file SHALL have mode
`0644`.

#### Scenario: File owned by the remote user

- **WHEN** the feature is installed with `defaultImage` set to `medium` on an image whose remote user is not root
- **THEN** `<home>/.config/act/actrc` and every directory the feature created on its path belong to the remote user, and
  the file has mode `0644`

#### Scenario: Existing configuration file replaced

- **WHEN** `<home>/.config/act/actrc` already exists as a regular file, and the feature is installed with `defaultImage`
  set to `medium` or `large`
- **THEN** the file holds exactly the lines for that value afterwards

#### Scenario: Configuration path that is not a regular file

- **WHEN** `<home>/.config/act/actrc` exists but is not a regular file, and the feature is installed with `defaultImage`
  set to `medium` or `large`
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: act default image lines

The configuration file the feature writes SHALL hold exactly the four lines act's own first-run prompt writes for the
matching choice, each ending with a newline, in the order the scenarios list them.

#### Scenario: Lines for medium

- **WHEN** the feature is installed with `defaultImage` set to `medium`
- **THEN** the configuration file holds exactly `-P ubuntu-latest=catthehacker/ubuntu:act-latest`,
  `-P ubuntu-22.04=catthehacker/ubuntu:act-22.04`, `-P ubuntu-20.04=catthehacker/ubuntu:act-20.04`, and
  `-P ubuntu-18.04=catthehacker/ubuntu:act-18.04`, one per line, in this order

#### Scenario: Lines for large

- **WHEN** the feature is installed with `defaultImage` set to `large`
- **THEN** the configuration file holds exactly `-P ubuntu-latest=catthehacker/ubuntu:full-latest`,
  `-P ubuntu-22.04=catthehacker/ubuntu:full-22.04`, `-P ubuntu-20.04=catthehacker/ubuntu:full-20.04`, and
  `-P ubuntu-18.04=catthehacker/ubuntu:full-18.04`, one per line, in this order

### Requirement: act default image location

The feature SHALL write the configuration file only to the location act reads when `XDG_CONFIG_HOME` is unset or points
to `<home>/.config`. A container that sets `XDG_CONFIG_HOME` elsewhere at run time sees act prompt again, which the
feature accepts because it cannot know a run-time `XDG_CONFIG_HOME` at build time.

#### Scenario: Configuration read by act

- **WHEN** the feature is installed with `defaultImage` set to `medium`, and `XDG_CONFIG_HOME` is unset in the remote
  user's environment
- **THEN** act run as the remote user reads the file the feature wrote and does not prompt

### Requirement: act runner images not verified

The feature SHALL neither pull nor verify the runner images the configuration file names. act pulls these third-party
images from Docker Hub at run time and runs workflow steps in them, which the feature accepts because selecting them is
what act's own prompt does.

#### Scenario: No runner image pulled at build time

- **WHEN** the feature is installed with `defaultImage` set to `medium` or `large`
- **THEN** the install makes no request to Docker Hub and starts no container

### Requirement: act version notices disabled

The feature SHALL set `ACT_DISABLE_VERSION_CHECK` to `1` in the container environment, so that act does not request
upstream's version notices on each run, because the feature, not act, manages the installed version.

#### Scenario: Version notices off in the container

- **WHEN** a shell starts in a container with the feature installed
- **THEN** `ACT_DISABLE_VERSION_CHECK` is `1` in its environment

### Requirement: No container engine installed

The feature SHALL NOT install a container engine, a Docker daemon, or the `docker` CLI, and SHALL NOT start, configure,
or check one. It SHALL be ordered after `ghcr.io/devcontainers/features/docker-in-docker` and
`ghcr.io/devcontainers/features/docker-outside-of-docker` when either is installed, and SHALL NOT depend on either.

#### Scenario: Image without Docker

- **WHEN** the feature is installed on an image that has no Docker Engine and no `docker` CLI
- **THEN** the install succeeds, and afterwards neither `docker` nor `dockerd` resolves on the remote user's `PATH`

#### Scenario: Running a job with a Docker Engine

- **WHEN** the feature is installed together with `ghcr.io/devcontainers/features/docker-in-docker` and the remote user
  runs `act` in a Git repository holding a workflow with one job that runs `echo` on `ubuntu-latest`, with `-P` naming
  an image available to the engine
- **THEN** the job runs in a container of that engine and the command exits 0

### Requirement: No other configuration

Beyond the file that requirement "act default image configuration" names and the environment variable that requirement
"act version notices disabled" names, the feature SHALL leave no act configuration anywhere in the image, SHALL NOT
write any other file under a user's home directory, edit shell startup files, or offer an option for a secret, a token,
an event payload, or an environment file, and SHALL NOT run a workflow or pull a runner image during the build.

#### Scenario: Nothing else configured after install

- **WHEN** the feature has been installed with default options
- **THEN** neither the remote user's nor root's home holds a file or directory whose name contains `act`
- **AND** no environment variable whose name starts with `ACT_` other than `ACT_DISABLE_VERSION_CHECK` is set in the
  remote user's environment

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/act/compatibility.json` and reject unsupported platforms
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

### Requirement: act platform gate

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian, Ubuntu, Fedora, and Alpine families; or when the image lacks the package
manager of the family it matched (`apt-get` for Debian and Ubuntu, `dnf` for Fedora, `apk` for Alpine).

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or identifies a
  distribution outside the supported families, or the image lacks the matched family's package manager
- **THEN** the install fails before downloading or installing anything, with a message naming what is unsupported

### Requirement: Installing twice

A second install SHALL succeed, apply the later options, and preserve the earlier executable if the second install
fails. A later `defaultImage` other than `none` SHALL replace the configuration file an earlier install wrote; a later
`none` SHALL leave an existing configuration file as it is.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second leaves `/usr/local/bin/act` unchanged, and `act --version` reports that
  version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `act --version` reports the version the second install selected
- **AND** `command -v act` resolves, following symbolic links, to `/usr/local/bin/act`, and `/usr/local/bin` holds no
  file other than `act` whose name starts with `act` or `.act`

#### Scenario: Default images selected, then none

- **WHEN** the feature is installed with `defaultImage` set to `medium` and then with `defaultImage` set to `none`
- **THEN** both installs succeed, and the remote user's act configuration file still holds the lines for `medium`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/act` exists but exits non-zero or prints no recognizable version, and the feature is
  installed
- **THEN** the install succeeds and replaces it, and `act --version` reports the requested version

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `act --version` still reports the version of the first install

### Requirement: act replacement safety

When the installed `/usr/local/bin/act` already reports the requested version, a second install SHALL leave it untouched
and download no archive; otherwise, including when the installed binary's version cannot be read, the version of the
later install SHALL replace it, so that the later options win and exactly one `act` remains. A second install that fails
SHALL leave the earlier `act` in place.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`
- **THEN** the second install leaves `/usr/local/bin/act` unchanged

### Requirement: act non-regular target

When `/usr/local/bin/act` exists but is not a regular file, the install SHALL fail before downloading anything, with a
message naming the path, and leave it as it is.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/act` exists but is not a regular file, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the prerequisites it
installs: after installing with `apt-get` it SHALL leave apt's package lists empty, after installing with `dnf` it SHALL
leave dnf's cache without metadata or downloaded packages, and it SHALL install with `apk` without keeping a cache. No
temporary directory or staged binary of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/act/compatibility.json`
- **THEN** apt's package lists, dnf's cache, and apk's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory or staged binary of the install remains in the temporary directory or in
  `/usr/local/bin`
