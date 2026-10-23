# uv Specification

## Purpose

Installs Astral's uv Python package and project manager (`uv` and `uvx`) for every user of a dev container, optionally
installs Python command-line tools with it, and keeps the Python interpreters uv installs at runtime, and uv's cache, on
a volume that survives rebuilds of the dev container.

Upstream sources:

- Home: https://github.com/astral-sh/uv
- Documentation: https://docs.astral.sh/uv/
- Installation guide: https://docs.astral.sh/uv/getting-started/installation/
- Tools concept: https://docs.astral.sh/uv/concepts/tools/
- Storage locations: https://docs.astral.sh/uv/reference/storage/
- Environment variables: https://docs.astral.sh/uv/reference/environment/
- Changelog: https://github.com/astral-sh/uv/blob/main/CHANGELOG.md
- GitHub releases: https://github.com/astral-sh/uv/releases
- Dev Container `updateRemoteUserUID`: https://containers.dev/implementors/json_reference/
- Dev Container Feature lifecycle hooks: https://containers.dev/implementors/features/
- Docker volumes: https://docs.docker.com/engine/storage/volumes/

## Requirements

### Requirement: Option version

The feature SHALL accept `version` and install that upstream uv release for every user, as "Select and install a uv
release" states.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `uv --version` and `uvx --version`, run as the remote user, report the newest uv release published when the
  image was built

#### Scenario: Pinned release

- **WHEN** the feature is installed with `version` naming a published release
- **THEN** `uv --version` reports exactly that release

#### Scenario: Release does not exist

- **WHEN** `version` names a release that upstream has not published
- **THEN** the build fails with a message naming the requested version

#### Scenario: Invalid version

- **WHEN** `version` is neither `latest` nor `MAJOR.MINOR.PATCH`
- **THEN** the build fails with a message naming the value, and nothing is downloaded

### Requirement: Select the release build for the platform

The feature SHALL install the release build that matches the container's CPU architecture (x86_64 or aarch64) and C
library: the glibc (`gnu`) build where the image uses glibc, and the statically linked musl build where it uses musl.

#### Scenario: glibc image

- **WHEN** the feature is installed on a glibc-based image
- **THEN** `uv --version` names the `<arch>-unknown-linux-gnu` target of the container's architecture

#### Scenario: musl image

- **WHEN** the feature is installed on a musl-based image
- **THEN** `uv --version` names the `<arch>-unknown-linux-musl` target of the container's architecture

### Requirement: Verify the uv release before installing it

The feature SHALL verify the uv release archive before anything from it is installed, and SHALL resolve `latest`, as
"Verify uv release archive" and "Resolve the latest uv release" state.

#### Scenario: Checksum matches

- **WHEN** the archive's SHA-256 digest equals the published checksum
- **THEN** `uv` and `uvx` from that archive are installed

#### Scenario: Checksum does not match

- **WHEN** the archive's SHA-256 digest differs from the published checksum, or the checksum cannot be downloaded
- **THEN** the build fails with a message naming the archive, and `/usr/local/bin/uv` and `/usr/local/bin/uvx` are left
  as they were before this install

### Requirement: Verify build-time tool downloads

When `toolsToInstall` is not empty, the feature SHALL leave uv's default sources and checks in place for the
interpreters and packages the tools need, as "Verify uv-managed Python downloads" and "Verify uv tool package downloads"
state.

#### Scenario: Default sources

- **WHEN** the feature installs a tool from `toolsToInstall` at build time
- **THEN** the tool's interpreter and packages are downloaded only from the sources above, and the install runs with no
  uv setting from the feature that changes a source or a hash check

### Requirement: Install download prerequisites only from the image's repositories

The feature SHALL install missing download prerequisites only from the package repositories the image already
configures, as "Install uv prerequisites from configured repositories" and "Upgrade Arch Linux packages with a missing
uv prerequisite" state.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image without curl or CA certificates
- **THEN** the install succeeds, and the image's package repository configuration and signing keys are unchanged

### Requirement: Option toolsToInstall

The feature SHALL accept `toolsToInstall` as a comma-separated list of uv tools to install at build time, as "Parse and
install requested uv tools" and "Reject invalid uv tool entries" state.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted toolsToInstall

- **WHEN** the feature is installed without `toolsToInstall`, or with `toolsToInstall` empty or holding only separators
  and whitespace
- **THEN** no tool is installed and no Python interpreter is downloaded at build time

#### Scenario: Tools on PATH

- **WHEN** the feature is installed with `toolsToInstall` listing two tools
- **THEN** the executables of both tools run for the remote user by name, without a path

#### Scenario: Invalid tool entry

- **WHEN** an entry of `toolsToInstall` starts with `-`, is a URL or a path, or contains whitespace inside it
- **THEN** the build fails with a message naming the entry, and nothing is downloaded or installed

#### Scenario: Tool cannot be installed

- **WHEN** an entry of `toolsToInstall` names a package that uv cannot resolve or install
- **THEN** the build fails

### Requirement: Keep build-time tools in the image

The environments of the tools that `toolsToInstall` installs, and the uv-managed interpreters they run on, SHALL live in
the image, outside the persistent volume. The remote user SHALL be able to upgrade, reinstall, remove, and add tools
with `uv tool` at runtime, without elevated privileges.

#### Scenario: Tools survive a replaced volume

- **WHEN** a tool from `toolsToInstall` runs in a container whose persistent volume is new and empty
- **THEN** the tool runs, and its interpreter resolves to a path outside the persistent volume

#### Scenario: Remote user manages tools

- **WHEN** the remote user runs `uv tool upgrade`, `uv tool install --reinstall`, or `uv tool uninstall` for a tool from
  `toolsToInstall`, or `uv tool install` for a new tool, in the running container
- **THEN** the command succeeds without elevated privileges

### Requirement: Grant write access through the group uv

The feature SHALL grant write access to `/usr/local/share/uv` and a newly created volume at `/var/lib/uv` as "Use the uv
group for non-root write access", "Make the uv locations writable by the group uv", "Restrict uv installed-directory
permissions", and "Keep the uv locations root-only for root" state.

#### Scenario: Remote user in the group

- **WHEN** the feature is installed for a remote user other than root
- **THEN** the remote user is a member of the group `uv`, and `/usr/local/share/uv` and a newly created volume at
  `/var/lib/uv` belong to that group and are writable by its members

#### Scenario: Root remote user

- **WHEN** the feature is installed for the remote user root
- **THEN** the install creates no group, and `/usr/local/share/uv` and a newly created volume at `/var/lib/uv` are owned
  by root and writable by root only

#### Scenario: Existing group

- **WHEN** the feature is installed for a remote user other than root on an image that already has a group named `uv` to
  which no other account belongs
- **THEN** the install succeeds, the group keeps its ID, and the remote user is a member of it

#### Scenario: Nothing writable by every user

- **WHEN** the feature is installed with a tool in `toolsToInstall`, for a root or a non-root remote user
- **THEN** no file or directory the install left under `/usr/local/share/uv` is writable by every user, and neither is a
  newly created volume at `/var/lib/uv`

#### Scenario: Changed UID

- **WHEN** the dev container tooling has changed the remote user's UID to the host user's, so that the remote user no
  longer owns `/usr/local/share/uv` or a newly created volume
- **THEN** the remote user creates a virtual environment with a uv-managed interpreter that is installed under
  `/var/lib/uv`, and reinstalls, removes, and adds tools with `uv tool`, all without elevated privileges

#### Scenario: User outside the group

- **WHEN** a user that is not root, not a member of `uv`, and not the owner of the two locations tries to create a file
  in `/usr/local/share/uv` or in `/var/lib/uv`
- **THEN** the attempt fails, and the tools installed at build time still run for that user

### Requirement: Persist interpreters and cache per dev container

The feature SHALL persist uv interpreters and cache in a named volume specific to each dev container, as "Persist uv
data per dev container" and "Keep the modes of an existing uv volume" state.

#### Scenario: New volume

- **WHEN** a dev container with this feature is created and its volume does not exist yet
- **THEN** `/var/lib/uv` is a mount of that volume, holds no files before uv first runs, and the remote user can create
  files in it

#### Scenario: Runtime interpreter on the volume

- **WHEN** the remote user creates a virtual environment with a uv-managed interpreter that is not installed yet
- **THEN** the interpreter is installed under `/var/lib/uv`, and the environment's interpreter link resolves there

#### Scenario: Rebuild keeps a workspace environment

- **WHEN** a workspace `.venv/` created with a uv-managed interpreter exists and the dev container is rebuilt
- **THEN** the `.venv/`'s interpreter runs after the rebuild without being downloaded again, and packages cached before
  the rebuild are installed from the cache

#### Scenario: Separate dev containers

- **WHEN** two different dev containers install this feature
- **THEN** each mounts its own volume, and an interpreter installed in one does not appear in the other

### Requirement: Repair a volume that no longer fits the remote user

When a dev container is created, the feature SHALL check and repair the volume as "Determine whether the uv volume
fits", "Define a fitting uv volume", "Repair a non-fitting uv volume", "Leave cleared special bits after uv volume
repair", "Continue when uv volume repair fails", and "Limit uv volume repair" state.

#### Scenario: Volume filled under another UID

- **WHEN** a dev container is created whose volume holds interpreters and a cache that another UID wrote, and the remote
  user can run `sudo` without a password
- **THEN** after the creation the remote user owns everything in the volume and all of it has the group `uv`, and the
  remote user installs a package from the cache the volume already held without downloading it, and installs a further
  uv-managed interpreter

#### Scenario: Files left by root

- **WHEN** a dev container is created whose volume holds files that root wrote among the remote user's own, and the
  remote user can run `sudo` without a password
- **THEN** after the creation the remote user owns everything in the volume

#### Scenario: Executable special bits during repair

- **WHEN** a volume that needs repair holds an executable file with mode `6755` in a directory with mode `2775`, and the
  remote user can run `sudo` without a password
- **THEN** the ownership change clears the executable's setuid/setgid bits to mode `0755`, the directory stays `2775`,
  the file's contents are preserved, and the feature does not restore the cleared bits

#### Scenario: No passwordless sudo

- **WHEN** a dev container is created whose volume another UID filled, and the remote user cannot run `sudo` without a
  password or the image has no `sudo`
- **THEN** the creation succeeds, a warning names `/var/lib/uv` and the reason, and the volume keeps its owner, group,
  and modes

#### Scenario: Volume that fits

- **WHEN** a dev container is created with a new volume, or with a volume in whose root the remote user can create files
  and in which that user owns everything below `/var/lib/uv`
- **THEN** nothing in the volume changes, and `sudo` is not run

#### Scenario: Repair skipped for root

- **WHEN** a dev container is created with the remote user root and a volume that holds an entry another UID owns
- **THEN** nothing in the volume changes, and no warning is printed

### Requirement: Point uv at the feature's locations

The feature SHALL direct uv to the feature's tool, interpreter, and cache locations and expose its tools on `PATH`, as
"Configure uv locations" and "Append uv tools to PATH" state.

#### Scenario: Environment of the remote user

- **WHEN** the remote user opens a shell in the container, a login shell included
- **THEN** each of these variables has the stated value, and `PATH` contains `/usr/local/share/uv/bin` after any
  existing `/usr/local/bin` and `/usr/bin` entries; system commands take precedence over same-named tools

#### Scenario: Workspace install across filesystems

- **WHEN** the remote user installs packages from the cache into an environment in the bind-mounted workspace
- **THEN** uv copies the files and reports no link-mode fallback warning

### Requirement: Make uv available to later features

Features installed after this one in the same build SHALL find `uv` at `/usr/local/bin/uv` and SHALL see the environment
variables this feature sets.

#### Scenario: Later feature runs uv

- **WHEN** a feature that installs after this one runs `uv --version` during its own install
- **THEN** the command succeeds and `UV_PYTHON_INSTALL_DIR` is set to `/var/lib/uv/python`

### Requirement: Install twice

A second install SHALL preserve or update uv and tools according to the later options, as "Repeat the uv install" and
"Keep the uv group on a repeated install" state.

#### Scenario: Same options

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second downloads no uv release, and `uv --version` and the tools are as after the
  first

#### Scenario: Different options

- **WHEN** the feature is installed with one `version` and `toolsToInstall`, then again with another `version` and
  another `toolsToInstall`
- **THEN** `uv --version` reports the second install's release, and the tools of both lists run by name

#### Scenario: Tool listed again

- **WHEN** a tool installed by the first install is listed again by the second install with a version constraint the
  installed version does not satisfy
- **THEN** after the second install the tool's installed version satisfies that constraint

#### Scenario: Group after a second install

- **WHEN** the feature is installed twice for the same remote user other than root
- **THEN** the image has one group `uv` that lists the remote user once, and the tools of both installs belong to that
  group and are writable by its members

### Requirement: Fail on unsupported platforms and invalid options

The feature SHALL fail the build, with a message naming the problem, as "Reject unsupported uv platforms before
downloading", "Reject a missing remote user or a primary group uv", and "Reject a shared or unmanageable uv group"
state. The Option requirements state how invalid values of a single option fail.

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than x86_64 or aarch64
- **THEN** the build fails with a message naming the architecture, and nothing is downloaded

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a distribution outside the supported families
- **THEN** the build fails with a message naming the distribution, and nothing is downloaded

#### Scenario: Tools with a uv release that does not check index hashes

- **WHEN** `toolsToInstall` is not empty and `version` names a release older than 0.12.16
- **THEN** the build fails with a message naming the version and 0.12.16, and nothing is downloaded

#### Scenario: Remote user missing

- **WHEN** the feature is installed for a remote user that does not exist in the image
- **THEN** the build fails with a message naming the user

#### Scenario: Group is the remote user's primary group

- **WHEN** the feature is installed for a remote user whose primary group is named `uv`
- **THEN** the build fails with a message naming the user and the group

#### Scenario: Group has other members

- **WHEN** the feature is installed for a remote user other than root on an image whose group `uv` lists another user as
  a member or is another account's primary group
- **THEN** the build fails with a message naming the group and that account

#### Scenario: Group cannot be created

- **WHEN** the feature is installed for a remote user other than root on an image that has neither a group `uv` nor a
  tool to create one
- **THEN** the build fails with a message naming the group

#### Scenario: Remote user cannot be added to the group

- **WHEN** the feature is installed for a remote user other than root on an image that has a group `uv` without members
  and no tool to add a member to it
- **THEN** the build fails with a message naming the user and the group

### Requirement: Companion Python editor extensions

The feature SHALL request Microsoft's `ms-python.python` and `ms-python.vscode-python-envs` extensions through VS Code
customizations. It SHALL declare no editor settings or IDE backend and SHALL preserve its CLI installation, tool, and
environment behavior independently of editor choice.

#### Scenario: Python extension declarations

- **WHEN** a supporting editor reads the feature's VS Code customizations
- **THEN** its extension list requests `ms-python.python` and `ms-python.vscode-python-envs`
- **AND** no project interpreter, formatter, or IDE backend is selected by the feature

### Requirement: Python editor integration guidance

`NOTES.md` SHALL explain the supplied extensions, project environment discovery, optional Jupyter support, native
PyCharm uv integration, and the VS Code mechanism for excluding the supplied automatic-install requests. It SHALL
explain that consumers also receive these defaults when uv is installed as another feature's dependency.

#### Scenario: CLI-only extension exclusion

- **WHEN** a developer uses uv only for command-line tools or receives it through a dependent feature
- **THEN** the notes show `-ms-python.python` and `-ms-python.vscode-python-envs` in project customizations
- **AND** explain that exclusion does not uninstall existing extensions or remove requests from other sources
- **AND** Jupyter and project kernel setup are documented as additional notebook-specific choices

### Requirement: Select and install a uv release

The feature SHALL accept for `version` either `latest`, meaning the newest release at build time, or one release as
`MAJOR.MINOR.PATCH`; SHALL install the `uv` and `uvx` executables of that upstream uv release as `/usr/local/bin/uv` and
`/usr/local/bin/uvx`, executable by every user; and SHALL fail the build on any other value, with a message naming the
value, before downloading anything.

#### Scenario: Version outside both forms

- **WHEN** `version` is neither `latest` nor `MAJOR.MINOR.PATCH`
- **THEN** the build fails with a message naming the value, and nothing is downloaded

### Requirement: Verify uv release archive

The feature SHALL download the release archive from
`https://github.com/astral-sh/uv/releases/download/<version>/uv-<arch>-unknown-linux-<libc>.tar.gz` over HTTPS and SHALL
verify it against the SHA-256 checksum published beside it as the same URL with `.sha256` appended, before anything from
the archive is installed. The feature SHALL run no installer script from upstream.

#### Scenario: Archive checked before install

- **WHEN** the archive's SHA-256 digest differs from the checksum published beside it, or that checksum cannot be
  downloaded
- **THEN** the build fails, and nothing from the archive is installed

### Requirement: Resolve the latest uv release

For `latest`, the feature SHALL resolve the release from the redirect of
`https://github.com/astral-sh/uv/releases/latest` and SHALL accept only a `MAJOR.MINOR.PATCH` release name from it. The
feature SHALL trust that redirect on TLS alone, because upstream publishes no checksum or signature for it; it yields
only the release name, and the archive of that release is verified as "Verify uv release archive" states.

#### Scenario: Latest resolves to a release name

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** the release name taken from the redirect has the form `MAJOR.MINOR.PATCH`, and the archive of that release is
  verified against its published checksum before anything from it is installed

### Requirement: Verify uv-managed Python downloads

When `toolsToInstall` is not empty, the feature SHALL configure no Python download source and SHALL disable none of uv's
checks, so that the managed CPython builds uv downloads for the tools at build time, on the feature's behalf, come from
`https://releases.astral.sh/github/python-build-standalone/releases/download/`, falling back to
`https://github.com/astral-sh/python-build-standalone/releases/download/`, each checked against the SHA-256 that the
installed uv release carries for that build.

#### Scenario: Managed Python from the default sources

- **WHEN** the feature installs a tool from `toolsToInstall` at build time that needs a uv-managed CPython build
- **THEN** the build is downloaded only from the sources above, and the install runs with no uv setting from the feature
  that changes a source or a hash check

### Requirement: Verify uv tool package downloads

When `toolsToInstall` is not empty, the feature SHALL configure no package index and SHALL disable none of uv's checks,
so that the packages uv downloads for the tools at build time, on the feature's behalf, come from the index
`https://pypi.org/simple/` and its files on `https://files.pythonhosted.org/`, each file checked against the SHA-256 the
index supplies for it. The feature SHALL install tools only with a uv release that checks index-supplied hashes, which
is 0.12.16 or later.

#### Scenario: Packages from the default index

- **WHEN** the feature installs a tool from `toolsToInstall` at build time
- **THEN** the tool's packages are downloaded only from the sources above, and the install runs with no uv setting from
  the feature that changes a source or a hash check

### Requirement: Install uv prerequisites from configured repositories

The feature SHALL install curl, CA certificates, tar, and `sha256sum`, when the image lacks them, only from the package
repositories the image already configures, with the package manager of the distribution's family (`apt`, `dnf`,
`pacman`, `apk`, or `zypper`), and SHALL add no package repository or signing key. When nothing is missing, the feature
SHALL run no package manager. What it installs this way stays in the image.

#### Scenario: Prerequisites already present

- **WHEN** the feature is installed on an image that has curl, CA certificates, tar, and `sha256sum`
- **THEN** the install runs no package manager

### Requirement: Upgrade Arch Linux packages with a missing uv prerequisite

On Arch Linux, whose package manager supports installing a package only together with a full system upgrade, installing
a missing download prerequisite SHALL also upgrade the image's packages.

#### Scenario: Missing prerequisite on Arch Linux

- **WHEN** the feature is installed on an Arch Linux image that lacks one of the download prerequisites
- **THEN** the prerequisite is installed together with an upgrade of the image's packages, and the image's package
  repository configuration and signing keys are unchanged

### Requirement: Parse and install requested uv tools

For `toolsToInstall`, a comma-separated list in which whitespace around an entry is ignored and empty entries are
skipped, the feature SHALL install each listed tool with `uv tool install` at build time and put the tools' executables
on `PATH` for every user; and SHALL fail the build when `uv tool install` cannot install a listed tool.

#### Scenario: Two listed tools

- **WHEN** the feature is installed with `toolsToInstall` listing two tools
- **THEN** both are installed with `uv tool install`, and their executables run for the remote user by name

### Requirement: Reject invalid uv tool entries

The feature SHALL fail the build when an entry of `toolsToInstall` is not a package name with at most one bracketed
extra and one version constraint (an option, URL, path, or any whitespace inside an entry), with a message naming the
entry, before downloading anything.

#### Scenario: Entry outside the package-name form

- **WHEN** an entry of `toolsToInstall` starts with `-`, is a URL or a path, or contains whitespace inside it
- **THEN** the build fails with a message naming the entry, and nothing is downloaded or installed

### Requirement: Use the uv group for non-root write access

When the remote user is not root, the feature SHALL make the remote user a member of a system group named `uv`, creating
the group when the image has none. It SHALL use a group `uv` the image already has, leaving its ID unchanged, only when
no account other than the remote user belongs to that group, as a listed member or through its primary group; otherwise
the build fails as "Fail on unsupported platforms and invalid options" states.

#### Scenario: Existing group with another account

- **WHEN** the feature is installed for a remote user other than root on an image whose group `uv` lists another user as
  a member or is another account's primary group
- **THEN** the build fails with a message naming the group and that account

### Requirement: Make the uv locations writable by the group uv

When the remote user is not root, `/usr/local/share/uv`, with everything the install puts there, and a newly created
volume at `/var/lib/uv` SHALL belong to the group `uv` and be writable by its members, so that the remote user writes
both without elevated privileges also when the dev container tooling has changed that user's UID to the host user's
before the container starts.

#### Scenario: Locations of a non-root remote user

- **WHEN** the feature is installed for a remote user other than root
- **THEN** `/usr/local/share/uv` and a newly created volume at `/var/lib/uv` belong to the group `uv` and are writable
  by its members

### Requirement: Restrict uv installed-directory permissions

The install SHALL leave no file or directory in `/usr/local/share/uv` or in a newly created volume at `/var/lib/uv`
writable by every user, so that, besides root, only the members of `uv` and the owner the install set, which is the
remote user under the UID it had when the image was built, can write what the install left there. What is created there
at runtime gets the modes that uv and the creating user's umask give it; the feature does not change those modes.

#### Scenario: No location writable by every user

- **WHEN** the feature is installed with a tool in `toolsToInstall`, for a root or a non-root remote user
- **THEN** nothing the install left under `/usr/local/share/uv`, and no newly created volume at `/var/lib/uv`, is
  writable by every user

### Requirement: Keep the uv locations root-only for root

When the remote user is root, the feature SHALL create no group, and `/usr/local/share/uv` and a newly created volume at
`/var/lib/uv` SHALL be owned by root and, as the install leaves them, writable by root only.

#### Scenario: Remote user root

- **WHEN** the feature is installed for the remote user root
- **THEN** the install creates no group, and both locations are owned by root and writable by root only

### Requirement: Persist uv data per dev container

The feature SHALL mount a named volume `uv-${devcontainerId}`, one per dev container, at `/var/lib/uv`, and SHALL point
uv's managed-interpreter directory (`python/`) and cache (`cache/`) into it. A newly created volume SHALL hold nothing
written at build time and SHALL be writable by the remote user as "Grant write access through the group uv" states.

#### Scenario: One volume per dev container

- **WHEN** two different dev containers install this feature
- **THEN** each mounts its own volume at `/var/lib/uv`, and an interpreter installed in one does not appear in the other

### Requirement: Keep the modes of an existing uv volume

A volume that already holds data SHALL keep its owner, group, and modes, except for the ownership changes and executable
setuid/setgid bits cleared by "Repair a non-fitting uv volume".

#### Scenario: Existing volume that fits

- **WHEN** a dev container is created with a volume that already holds data and fits the remote user
- **THEN** the volume keeps its owner, group, and modes

### Requirement: Determine whether the uv volume fits

When a dev container is created, a rebuild included, the feature SHALL check the volume as the remote user, before the
creation commands of the user's `devcontainer.json` run, against "Define a fitting uv volume".

#### Scenario: Fit checked before creation commands

- **WHEN** a dev container is created, a rebuild included
- **THEN** the feature checks the volume as the remote user before the creation commands of the user's
  `devcontainer.json` run

### Requirement: Define a fitting uv volume

The feature SHALL treat the volume as fitting the remote user when that user can create files in `/var/lib/uv` and owns
every file and directory below it, and as no longer fitting when another UID has written it: the remote user was changed
to an account with another UID, the UID of the same account changed, or root wrote into it. For the remote user root it
SHALL treat every volume as fitting.

#### Scenario: Volume with files left by root

- **WHEN** a dev container is created whose volume holds files that root wrote among the remote user's own, and the
  remote user can run `sudo` without a password
- **THEN** after the creation the remote user owns everything in the volume

### Requirement: Repair a non-fitting uv volume

When the volume does not fit and the remote user can run `sudo` without a password, the feature SHALL make the remote
user the owner, and `uv` the group where the image has that group, of the volume and of everything in it, so that uv
works on the interpreters and the cache the volume already holds. The repair SHALL preserve file contents, ordinary
permission bits, and directory setgid bits, and SHALL change modes only as "Leave cleared special bits after uv volume
repair" states.

#### Scenario: Repair with passwordless sudo

- **WHEN** a dev container is created whose volume another UID wrote, and the remote user can run `sudo` without a
  password
- **THEN** after the creation the remote user owns everything in the volume, file contents, ordinary permission bits,
  and directory setgid bits are preserved, and the feature does not restore setuid/setgid bits the ownership change
  cleared

### Requirement: Leave cleared special bits after uv volume repair

The ownership change of the repair MAY clear setuid/setgid bits on executable files; the feature SHALL NOT restore those
cleared bits or otherwise change modes explicitly.

#### Scenario: Executable with special bits in a repaired volume

- **WHEN** a volume that needs repair holds an executable file with mode `6755`, and the remote user can run `sudo`
  without a password
- **THEN** after the repair the feature has not set the file's setuid/setgid bits again, and the file's contents are
  preserved

### Requirement: Continue when uv volume repair fails

When the volume does not fit and the remote user cannot run `sudo` without a password, the feature SHALL leave the
volume as it is and print a warning that names `/var/lib/uv` and the reason. When the change of owner fails, the feature
SHALL print a warning that names `/var/lib/uv` and the reason. In every case the creation of the dev container SHALL
continue.

#### Scenario: Ownership change fails after partial repair

- **WHEN** ownership repair changes some entries in `/var/lib/uv` and then fails
- **THEN** a warning names `/var/lib/uv` and the reason, and container creation continues

### Requirement: Limit uv volume repair

The feature SHALL change nothing on a volume that fits, nothing when the remote user is root, and nothing outside
`/var/lib/uv`, and SHALL add no sudo rule.

#### Scenario: Nothing to repair

- **WHEN** a dev container is created with a volume that fits, or with the remote user root
- **THEN** nothing in the volume changes

### Requirement: Configure uv locations

The feature SHALL set, for every process in the container, `UV_PYTHON_INSTALL_DIR` to `/var/lib/uv/python`,
`UV_CACHE_DIR` to `/var/lib/uv/cache`, `UV_TOOL_DIR` to `/usr/local/share/uv/tools`, `UV_TOOL_BIN_DIR` to
`/usr/local/share/uv/bin`, and `UV_LINK_MODE` to `copy`.

#### Scenario: Variables in a login shell

- **WHEN** the remote user opens a login shell in the container
- **THEN** each of these variables has the stated value

### Requirement: Append uv tools to PATH

The feature SHALL append `/usr/local/share/uv/bin` to `PATH` for every process in the container, after any existing
`/usr/local/bin` and `/usr/bin` entries, also in login shells whose system profile resets `PATH`. Commands already
available earlier in `PATH` SHALL take precedence over same-named tools.

#### Scenario: System command takes precedence

- **WHEN** a command already available earlier in `PATH` and a tool share a name
- **THEN** the command earlier in `PATH` runs

### Requirement: Repeat the uv install

Installing the feature a second time on the same image SHALL succeed. With the same options, it SHALL download no uv
release when the requested release is already installed, and leave installed tools as they are. With different options,
the later `version` SHALL replace the installed `uv` and `uvx`, every tool from both installs SHALL remain installed,
and a tool listed again SHALL end up satisfying the entry of the later install.

#### Scenario: Second install with the same options

- **WHEN** the feature is installed twice with the same options and the requested release is already installed
- **THEN** both installs succeed, the second downloads no uv release, and the installed tools are left as they are

### Requirement: Keep the uv group on a repeated install

A second install for the same remote user SHALL add no second group and no second membership, and SHALL leave
`/usr/local/share/uv`, including what it adds there, and a newly created volume as "Grant write access through the group
uv" states. A second install for another remote user that is not root finds the first install's remote user in the group
and fails as that requirement states for a group to which another account belongs.

#### Scenario: Different remote user on second install

- **WHEN** the feature is installed a second time for a different non-root remote user
- **THEN** it fails because the existing `uv` group has another member

### Requirement: Reject unsupported uv platforms before downloading

The feature SHALL fail the build with a message naming the problem, before downloading anything, when the container's
architecture is neither x86_64 nor aarch64, when the distribution belongs to none of the supported families (Debian- or
Ubuntu-based, RHEL- or Fedora-based, Arch Linux, Alpine, and openSUSE or SUSE), or when `toolsToInstall` is not empty
and `version` names a release older than 0.12.16. The supported images are those in `test/uv/compatibility.json`.

#### Scenario: Architecture outside x86_64 and aarch64

- **WHEN** the feature is installed on an architecture that is neither x86_64 nor aarch64
- **THEN** the build fails with a message naming the architecture, and nothing is downloaded

### Requirement: Reject a missing remote user or a primary group uv

The feature SHALL also fail the build, with a message naming the problem, when the remote user it is installed for does
not exist, and, for a remote user other than root, when the group `uv` is that user's primary group, whose ID the dev
container tooling changes together with the user's, so that it could not keep the write access.

#### Scenario: Remote user that does not exist

- **WHEN** the feature is installed for a remote user that does not exist in the image
- **THEN** the build fails with a message naming the user

### Requirement: Reject a shared or unmanageable uv group

For a remote user other than root, the feature SHALL also fail the build, with a message naming the problem, when an
account other than that user belongs to a group `uv` the image already has, as a listed member or through its primary
group, and when the group has to be created, or the user added to it, and the image has no tool for that step.

#### Scenario: No tool to create the group

- **WHEN** the feature is installed for a remote user other than root on an image that has neither a group `uv` nor a
  tool to create one
- **THEN** the build fails with a message naming the group
