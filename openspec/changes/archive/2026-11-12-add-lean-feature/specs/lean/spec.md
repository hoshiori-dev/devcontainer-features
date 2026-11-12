# Spec Delta

## Purpose

Installs elan, the Lean version manager, and its `lean` and `lake` proxies for every user of a dev container, so that
each project's `lean-toolchain` file selects its Lean 4 toolchain, which elan installs on first use. On request, chosen
toolchains are installed into the image at build time. elan's home, Lake's artifact cache, and Mathlib's build cache
live on a volume per dev container that survives rebuilds.

Upstream sources:

- Lean home: https://lean-lang.org
- Lean installation guide: https://lean-lang.org/install/manual/
- Lean 4 source and releases: https://github.com/leanprover/lean4
- elan README: https://github.com/leanprover/elan
- elan changelog: https://github.com/leanprover/elan/blob/master/CHANGELOG.md
- Lake README: https://github.com/leanprover/lean4/blob/master/src/lake/README.md
- Mathlib: https://github.com/leanprover-community/mathlib4
- Lean 4 VS Code extension: https://github.com/leanprover/vscode-lean4
- Dev Container `updateRemoteUserUID`: https://containers.dev/implementors/json_reference/
- Dev Container Feature lifecycle hooks: https://containers.dev/implementors/features/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/

## ADDED Requirements

### Requirement: elan and its proxies on PATH

The feature SHALL install elan as `/usr/local/bin/elan`, executable by every user, and SHALL create `lean`, `lake`,
`leanc`, `leanmake`, `leanchecker`, and `leanpkg` in `/usr/local/bin` as symbolic links to it, the proxies elan's own
installer creates, so that each runs by name for the remote user and for root.

#### Scenario: Remote user and root

- **WHEN** the feature is installed
- **THEN** `elan --version`, run as the remote user and as root, reports the installed release, and each of the six
  proxies resolves to `/usr/local/bin/elan`

### Requirement: Project toolchain selection

The feature SHALL leave each project's `lean-toolchain` file in charge of the toolchain `lean` and `lake` run inside the
project, and SHALL NOT set `ELAN_TOOLCHAIN` or an elan override. elan installs a toolchain that is not installed yet on
first use.

#### Scenario: New Lake project

- **WHEN** the remote user creates a project with `lake new` for a toolchain other than the default toolchain and runs
  `lake build` in it
- **THEN** the build uses the project's toolchain, succeeds, and the project's executable runs

#### Scenario: Toolchain installed on first use

- **WHEN** a project names a toolchain that is not installed and the remote user runs `lake build` in it
- **THEN** elan installs the toolchain under `/var/lib/lean/elan/toolchains/` and the build succeeds

### Requirement: Option elanVersion

The feature SHALL accept the option `elanVersion` and install the elan release it names, as "Select an elan release"
states.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted elanVersion

- **WHEN** the feature is installed without `elanVersion`, or with `elanVersion` set to `latest`
- **THEN** `elan --version` reports the release the latest-release redirect named at build time

#### Scenario: Pinned release

- **WHEN** the feature is installed with `elanVersion` naming a published release at or above the minimum
- **THEN** `elan --version` reports exactly that release

#### Scenario: Release that does not exist

- **WHEN** `elanVersion` has the accepted form but names no published release
- **THEN** the build fails with a message naming the requested version, and nothing is installed

### Requirement: Select an elan release

The feature SHALL accept for `elanVersion` either `latest` or one release as `MAJOR.MINOR.PATCH` that is `4.1.0` or
later, the first release that resolves toolchains through upstream's release index. It SHALL fail the build on any other
value, with a message naming the option, the value, and the accepted forms, before downloading anything.

#### Scenario: Version outside the accepted forms

- **WHEN** `elanVersion` is a partial version, carries a leading `v` or a pre-release suffix, or names a release below
  `4.1.0`
- **THEN** the build fails with a message naming `elanVersion`, the value, and the accepted forms, and nothing is
  downloaded

### Requirement: Resolve the latest elan release

For `latest`, the feature SHALL take the release from the redirect of
`https://github.com/leanprover/elan/releases/latest` and accept only a `v<MAJOR>.<MINOR>.<PATCH>` tag from it. It SHALL
rely on TLS alone for that redirect, which upstream does not sign: it yields only a release name.

#### Scenario: Malformed latest-release redirect

- **WHEN** `elanVersion` is `latest` and the redirect names no tag of the form `v<MAJOR>.<MINOR>.<PATCH>`
- **THEN** the build fails with a message showing what it received, and no archive is downloaded

### Requirement: Download the elan release

The feature SHALL download
`https://github.com/leanprover/elan/releases/download/v<version>/elan-<arch>-unknown-linux-gnu.tar.gz`, with `<arch>`
`x86_64` or `aarch64`, over HTTPS on every hop, redirects included, and SHALL install the archive's `elan-init`
executable as elan. It SHALL run no installer script from upstream.

#### Scenario: Archive without the executable

- **WHEN** the downloaded archive holds no regular file `elan-init`
- **THEN** the build fails with a message naming the archive, and nothing is installed

### Requirement: elan release integrity

Upstream publishes no checksum or signature for elan's archives, so the feature SHALL rely on TLS alone for them; the
risk is accepted because the GitHub release is upstream's only Linux distribution of elan. When
`https://api.github.com/repos/leanprover/elan/releases/tags/v<version>` answers with a SHA-256 digest for the archive,
the feature SHALL compare the archive with it, and SHALL NOT require one.

#### Scenario: Digest reported and not matching

- **WHEN** GitHub reports a digest for the archive and the downloaded file does not match it
- **THEN** the build fails with a message naming the archive, and nothing is installed

#### Scenario: No digest reported

- **WHEN** GitHub's API does not answer, or reports no digest for the archive
- **THEN** the install continues with the downloaded archive

### Requirement: Failed installation keeps the previous state

When an installation fails, the feature SHALL leave `/usr/local/bin/elan`, its proxies, and the toolchains in
`/usr/local/share/lean/toolchains/` as they were, and SHALL leave no partially written file there and no file it
downloaded itself. Prerequisite packages installed before the failure MAY remain.

#### Scenario: Failure over an existing installation

- **WHEN** the feature is already installed and a later installation of it fails at any point
- **THEN** `elan --version` reports the earlier release, the earlier build-time toolchains are unchanged, and no file
  from the failed attempt remains in `/usr/local/bin`, `/usr/local/share/lean`, or a temporary directory

### Requirement: Toolchain names

The feature SHALL accept as a toolchain name only `stable`, `beta`, `nightly`, `v<MAJOR>.<MINOR>.<PATCH>` with an
optional `-rc<N>`, or `nightly-<YYYY>-<MM>-<DD>`, each optionally prefixed with `leanprover/lean4:` or
`leanprover/lean4-nightly:`. It SHALL fail the build on any other name in `defaultToolchain` or `preinstallToolchains`,
with a message naming the option and the name, before downloading anything.

#### Scenario: Name outside the official forms

- **WHEN** a toolchain name in either option names another origin, a path, a version without its leading `v`, or a
  `lean-toolchain` file of a repository
- **THEN** the build fails with a message naming the option and the name, and nothing is downloaded

### Requirement: Option defaultToolchain

The feature SHALL accept the option `defaultToolchain` as the toolchain elan uses outside a project, as "Set the default
toolchain at container creation" states.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"stable"` |

#### Scenario: Omitted defaultToolchain

- **WHEN** the feature is installed without `defaultToolchain` and the dev container is created
- **THEN** `elan show`, run as the remote user outside any project, names `stable` as the default it resolves from

#### Scenario: Named default toolchain

- **WHEN** the feature is installed with `defaultToolchain` naming a toolchain and the dev container is created
- **THEN** `elan show`, run as the remote user outside any project, names that toolchain as the default

#### Scenario: Empty defaultToolchain

- **WHEN** the feature is installed with `defaultToolchain` empty and the dev container is created with a new volume
- **THEN** elan has no default toolchain

### Requirement: Set the default toolchain at container creation

When `defaultToolchain` is not empty, the feature SHALL set elan's default toolchain to that name, unresolved, each time
the dev container is created, replacing a default set before, and SHALL download nothing to do so. When it is empty, the
feature SHALL leave elan's default as it is.

#### Scenario: Default changed by the user

- **WHEN** the remote user changed the default with `elan default`, and the dev container is created again with the same
  volume
- **THEN** the default is `defaultToolchain` again when that option is not empty, and stays the user's choice when it is
  empty

### Requirement: Option preinstallToolchains

The feature SHALL accept the option `preinstallToolchains` as a comma-separated list of toolchain names to install into
the image at build time, in which whitespace around an entry is ignored and empty entries are skipped.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted preinstallToolchains

- **WHEN** the feature is installed without `preinstallToolchains`, or with it holding only separators and whitespace
- **THEN** no toolchain is downloaded at build time and `/usr/local/share/lean/toolchains/` holds none

#### Scenario: Listed toolchains

- **WHEN** the feature is installed with `preinstallToolchains` listing toolchains, and the container has no network
- **THEN** a project pinned to any of them builds without a download

#### Scenario: Toolchain cannot be installed

- **WHEN** an entry has an accepted form but upstream publishes no such toolchain for the architecture
- **THEN** the build fails with a message naming the entry

### Requirement: Build-time toolchains in the image

The feature SHALL install each toolchain from `preinstallToolchains` with the installed elan into
`/usr/local/share/lean/toolchains/`, under the directory name elan gives it, owned by root and writable by no other
user. It SHALL download no toolchain that directory already holds.

#### Scenario: Toolchain already in the image

- **WHEN** `preinstallToolchains` names a toolchain that `/usr/local/share/lean/toolchains/` already holds
- **THEN** the install downloads no toolchain for it and leaves the directory unchanged

#### Scenario: Nothing writable by other users

- **WHEN** the feature is installed with a toolchain in `preinstallToolchains`
- **THEN** no file or directory under `/usr/local/share/lean` is owned by a user other than root or writable by its
  group or by every user

### Requirement: Toolchain download sources

For `preinstallToolchains`, the feature SHALL give elan no download setting, so that elan reads the release index
`https://release.lean-lang.org` and downloads releases from `https://releases.lean-lang.org/lean4/`, which redirects to
`https://github.com/leanprover/lean4/releases/download/`, and nightlies from
`https://github.com/leanprover/lean4-nightly/releases/download/`.

#### Scenario: Default sources

- **WHEN** a toolchain from `preinstallToolchains` is installed at build time
- **THEN** it comes from the sources above, and the install runs with no setting from the feature that changes elan's
  sources or certificate checks

### Requirement: Toolchain integrity

Upstream publishes no checksum or signature for Lean toolchains and elan verifies none, so build-time toolchains SHALL
rely on TLS alone. elan follows redirects without limiting them to HTTPS; every hop of these sources is HTTPS today.
Both risks are accepted: these hosts are upstream's only distribution of toolchains, and elan fetches the same files at
run time.

#### Scenario: Toolchain download fails

- **WHEN** elan reports a download or unpack error for a toolchain from `preinstallToolchains`
- **THEN** the build fails with a message naming the toolchain, and no partial toolchain is left in
  `/usr/local/share/lean/toolchains/`

### Requirement: Persist elan's home and caches per dev container

The feature SHALL mount a named volume `lean-${devcontainerId}`, one per dev container, at `/var/lib/lean`, so that
toolchains, which are executable code, are shared with no other dev container. A newly created volume SHALL hold nothing
written at build time.

#### Scenario: Separate dev containers

- **WHEN** two different dev containers install this feature
- **THEN** each mounts its own volume at `/var/lib/lean`, and a toolchain installed in one does not appear in the other

#### Scenario: Rebuild keeps toolchains and caches

- **WHEN** a toolchain was installed at run time and Lake's and Mathlib's caches hold files, and the dev container is
  rebuilt
- **THEN** the toolchain runs without a download and the cached files are still there

### Requirement: Point elan, Lake, and Mathlib at the volume

The feature SHALL set, for every process in the container, `ELAN_HOME` to `/var/lib/lean/elan`, `LAKE_CACHE_DIR` to
`/var/lib/lean/cache/lake`, and `MATHLIB_CACHE_DIR` to `/var/lib/lean/cache/mathlib`.

#### Scenario: Variables in a login shell

- **WHEN** the remote user opens a login shell in the container
- **THEN** each of these variables has the stated value

#### Scenario: Lake artifact cache with a build-time toolchain

- **WHEN** the remote user builds a project with Lake's artifact cache enabled, using a build-time toolchain
- **THEN** the build succeeds and the artifacts are stored under `/var/lib/lean/cache/lake`

### Requirement: Prepare elan's home at container creation

Each time a dev container is created, the feature SHALL, as the remote user and before the creation commands of the
user's `devcontainer.json` run, create the directories `elan/toolchains/`, `cache/lake/`, and `cache/mathlib/` in
`/var/lib/lean` when they are missing, then link build-time toolchains and set the default toolchain.

#### Scenario: New volume

- **WHEN** a dev container is created with a new volume
- **THEN** the three directories exist, belong to the remote user, and the remote user creates files in each

### Requirement: Link build-time toolchains into elan's home

For each toolchain in `/usr/local/share/lean/toolchains/`, the feature SHALL create a symbolic link of the same name in
`/var/lib/lean/elan/toolchains/` when no entry of that name exists, and SHALL keep an existing entry. It SHALL remove a
link there whose target is under `/usr/local/share/lean/toolchains/` and no longer exists, and SHALL change nothing
else.

#### Scenario: Build-time toolchain linked

- **WHEN** a dev container is created from an image with a build-time toolchain
- **THEN** elan lists the toolchain as installed, and it runs without a download

#### Scenario: Toolchain of the same name on the volume

- **WHEN** the volume already holds a directory for a toolchain that the image also holds
- **THEN** the directory stays as it was and no link replaces it

#### Scenario: Toolchain dropped from the image

- **WHEN** the image no longer holds a toolchain that a link on the volume points to
- **THEN** that link is removed, and links to other targets and every other entry stay as they were

#### Scenario: Build-time toolchain uninstalled

- **WHEN** the remote user uninstalls a build-time toolchain with `elan toolchain uninstall`
- **THEN** only the link is removed, the toolchain in `/usr/local/share/lean/toolchains/` is unchanged, and the next
  creation of the dev container links it again

### Requirement: Use the group lean for non-root write access

When the remote user is not root, the feature SHALL make the remote user a member of a system group named `lean`,
creating it when the image has none. It SHALL use an existing group `lean`, keeping its ID, only when no account other
than the remote user belongs to it, as a listed member or through its primary group.

#### Scenario: Remote user in the group

- **WHEN** the feature is installed for a remote user other than root
- **THEN** the remote user is a member of the group `lean`

#### Scenario: Existing group

- **WHEN** the feature is installed for a remote user other than root on an image whose group `lean` has no member
- **THEN** the install succeeds, the group keeps its ID, and the remote user is a member of it

### Requirement: Make the volume writable by the group lean

When the remote user is not root, a newly created volume at `/var/lib/lean` SHALL belong to the group `lean` and be
writable by its members and by no other user, so that the remote user writes it without elevated privileges also after
the dev container tooling changed that user's UID to the host user's.

#### Scenario: Changed UID

- **WHEN** the dev container tooling has changed the remote user's UID, so that the user no longer owns a newly created
  volume
- **THEN** the creation step prepares the volume, and the remote user installs a toolchain and builds a project without
  elevated privileges

### Requirement: Keep the volume root-only for root

When the remote user is root, the feature SHALL create no group, and a newly created volume at `/var/lib/lean` SHALL be
owned by root and writable by root only.

#### Scenario: Remote user root

- **WHEN** the feature is installed for the remote user root
- **THEN** the install creates no group, and a newly created volume is owned by root and writable by root only

### Requirement: Determine whether the volume fits

At each container creation, before it prepares elan's home, the feature SHALL treat the volume as fitting when the
remote user can create files in `/var/lib/lean` and owns every entry below it, and as not fitting when another UID wrote
into it. For the remote user root, every volume fits.

#### Scenario: Volume that fits

- **WHEN** a dev container is created with a new volume, or with a volume the remote user owns throughout
- **THEN** no ownership in the volume changes, and `sudo` is not run

### Requirement: Repair a volume that no longer fits

When the volume does not fit and the remote user can run `sudo` without a password, the feature SHALL make the remote
user the owner, and `lean` the group where the image has it, of the volume and of everything in it. It SHALL follow no
symbolic link, and SHALL preserve file contents and permission bits, except setuid/setgid bits the change clears, which
it SHALL NOT restore.

#### Scenario: Volume filled under another UID

- **WHEN** a dev container is created whose volume holds toolchains and caches that another UID or root wrote, and the
  remote user can run `sudo` without a password
- **THEN** after the creation the remote user owns everything in the volume and uses the toolchains without a download

#### Scenario: Links into the image

- **WHEN** a volume that needs repair holds links to build-time toolchains
- **THEN** the links change owner, and nothing under `/usr/local/share/lean` changes

### Requirement: Continue when the volume cannot be prepared

When the volume does not fit and the remote user cannot run `sudo` without a password, or when the repair, a directory,
a link, or the default toolchain cannot be written, the feature SHALL print a warning naming `/var/lib/lean` and the
reason, and the creation SHALL continue. The feature SHALL add no sudo rule and change nothing outside `/var/lib/lean`.

#### Scenario: No passwordless sudo

- **WHEN** a dev container is created whose volume another UID filled, and the remote user cannot run `sudo` without a
  password or the image has no `sudo`
- **THEN** the creation succeeds, a warning names `/var/lib/lean` and the reason, and the volume keeps its owners

### Requirement: Install prerequisites from configured repositories

The feature SHALL install curl, CA certificates, tar, gzip, git, and find, when the image lacks them, only from the
package repositories the image configures, with the family's package manager (`apt`, `dnf`, `zypper`, or `pacman`),
adding no repository or key and leaving no package index or downloaded package in its cache. With nothing missing, it
SHALL run no package manager.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image without curl, CA certificates, or git
- **THEN** the install succeeds, all three are present afterwards, and the package manager's cache holds no package
  index or downloaded package

#### Scenario: Prerequisites already present

- **WHEN** the feature is installed on an image that has all prerequisites
- **THEN** the install runs no package manager

### Requirement: Upgrade Arch Linux packages with a missing prerequisite

On Arch Linux, whose package manager supports installing a package only together with a full system upgrade, installing
a missing prerequisite SHALL also upgrade the image's packages.

#### Scenario: Missing prerequisite on Arch Linux

- **WHEN** the feature is installed on an Arch Linux image that lacks a prerequisite
- **THEN** the prerequisite is installed together with an upgrade of the image's packages

### Requirement: Lean editor extension

The feature SHALL request the VS Code extension `leanprover.lean4` through VS Code customizations, and SHALL declare no
editor settings.

#### Scenario: Extension declaration

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** its extension list requests `leanprover.lean4`, and the feature declares no setting

### Requirement: Lean usage guidance

`NOTES.md` SHALL explain the project toolchain on first use, the volume with its disk use and `elan toolchain gc`, the
image size each build-time toolchain adds, Mathlib's `lake exe cache get` as a `postCreateCommand`, that elan is updated
through `elanVersion` and not `elan self update`, what setting `ELAN_HOME` elsewhere gives up, how to exclude the editor
extension, and that only images with glibc 2.30 or later run current toolchains.

#### Scenario: Reading the notes

- **WHEN** a developer reads the feature's generated README
- **THEN** it covers each of these topics

### Requirement: Installing twice

Installing the feature a second time on the same image SHALL succeed. With the same options, it SHALL download no elan
release and no toolchain. With different options, the later `elanVersion` and `defaultToolchain` SHALL take effect, the
build-time toolchains of both installs SHALL remain, and the group `lean` SHALL list the remote user once.

#### Scenario: Same options

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, and the second downloads no elan release and no toolchain

#### Scenario: Different options

- **WHEN** the feature is installed with one `elanVersion`, `defaultToolchain`, and `preinstallToolchains`, then again
  with other values
- **THEN** `elan --version` reports the second install's release, the default toolchain after creation is the second
  install's, and the toolchains of both installs run without a download

#### Scenario: Different remote user on the second install

- **WHEN** the feature is installed a second time for a different non-root remote user
- **THEN** the second install fails because the group `lean` has another member

### Requirement: Supported platforms

The feature SHALL fail the build, with a message naming the problem and before downloading anything, when the
architecture is neither x86_64 nor aarch64, when the C library is not glibc, or when the distribution belongs to none of
the families Debian or Ubuntu, Fedora or RHEL, Arch Linux, and openSUSE. The supported images are those in
`test/lean/compatibility.json`.

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than x86_64 and aarch64
- **THEN** the build fails with a message naming the architecture, and nothing is downloaded

#### Scenario: musl image

- **WHEN** the feature is installed on an image whose C library is musl
- **THEN** the build fails with a message saying elan and Lean need glibc, and nothing is downloaded

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a distribution outside the supported families
- **THEN** the build fails with a message naming the distribution, and nothing is downloaded

### Requirement: Reject a missing remote user or an unusable group

The feature SHALL fail the build, naming the problem, before downloading anything, when the remote user does not exist;
and, for a non-root remote user, when `lean` is that user's primary group, when another account belongs to an existing
group `lean`, or when the image lacks the tool to create the group or to add the user to it.

#### Scenario: Remote user that does not exist

- **WHEN** the feature is installed for a remote user that does not exist in the image
- **THEN** the build fails with a message naming the user

#### Scenario: Group is the remote user's primary group

- **WHEN** the feature is installed for a remote user whose primary group is named `lean`
- **THEN** the build fails with a message naming the user and the group

#### Scenario: Group has another member

- **WHEN** the feature is installed for a non-root remote user on an image whose group `lean` lists another user or is
  another account's primary group
- **THEN** the build fails with a message naming the group and that account

#### Scenario: No tool for the group

- **WHEN** the feature is installed for a non-root remote user on an image that lacks the tool to create the group or to
  add the user to it
- **THEN** the build fails with a message naming the group and the missing tool
