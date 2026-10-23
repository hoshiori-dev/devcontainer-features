# Spec Delta

## MODIFIED Requirements

### Requirement: Option version

The feature SHALL accept `version` and install that upstream uv release for every user.

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

### Requirement: Verify the uv release before installing it

The feature SHALL verify the selected uv release archive before installing its contents.

#### Scenario: Checksum matches

- **WHEN** the archive's SHA-256 digest equals the published checksum
- **THEN** `uv` and `uvx` from that archive are installed

#### Scenario: Checksum does not match

- **WHEN** the archive's SHA-256 digest differs from the published checksum, or the checksum cannot be downloaded
- **THEN** the build fails with a message naming the archive, and `/usr/local/bin/uv` and `/usr/local/bin/uvx` are left
  as they were before this install

### Requirement: Verify build-time tool downloads

When tools are requested, the feature SHALL use uv defaults and verification for their interpreter and package
downloads.

#### Scenario: Default sources

- **WHEN** the feature installs a tool from `toolsToInstall` at build time
- **THEN** the tool's interpreter and packages are downloaded only from the sources above, and the install runs with no
  uv setting from the feature that changes a source or a hash check

### Requirement: Install download prerequisites only from the image's repositories

The feature SHALL obtain missing download prerequisites only from repositories already configured in the image.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image without curl or CA certificates
- **THEN** the install succeeds, and the image's package repository configuration and signing keys are unchanged

### Requirement: Option toolsToInstall

The feature SHALL accept `toolsToInstall` as a comma-separated list of uv tools to install at build time.

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

### Requirement: Grant write access through the group uv

For a non-root remote user, the feature SHALL provide group-based write access to its installed tools and the uv volume.

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

The feature SHALL persist uv interpreters and cache in a named volume specific to each dev container.

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

At container creation, the feature SHALL repair a uv volume that no longer fits the remote user when passwordless sudo
permits it.

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

The feature SHALL direct uv to the feature’s tool, interpreter, and cache locations and expose its tools on PATH.

#### Scenario: Environment of the remote user

- **WHEN** the remote user opens a shell in the container, a login shell included
- **THEN** each of these variables has the stated value, and `PATH` contains `/usr/local/share/uv/bin` after any
  existing `/usr/local/bin` and `/usr/bin` entries; system commands take precedence over same-named tools

#### Scenario: Workspace install across filesystems

- **WHEN** the remote user installs packages from the cache into an environment in the bind-mounted workspace
- **THEN** uv copies the files and reports no link-mode fallback warning

### Requirement: Install twice

A second install SHALL preserve or update uv and tools according to the later options.

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

The feature SHALL fail before downloads for unsupported platforms, invalid combined versions, missing users, or unsafe
group setup.

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

## ADDED Requirements

### Requirement: Select and install a uv release

`latest` SHALL resolve the newest uv release at build time; explicit versions SHALL be `MAJOR.MINOR.PATCH`. Install its
`uv` and `uvx` at `/usr/local/bin/uv` and `/usr/local/bin/uvx`, executable by every user; any other value fails naming
it before downloads.

#### Scenario: Invalid version

- **WHEN** `version` is neither `latest` nor `MAJOR.MINOR.PATCH`
- **THEN** installation fails naming the value before downloads

### Requirement: Verify uv release archive

The feature SHALL fetch
`https://github.com/astral-sh/uv/releases/download/<version>/uv-<arch>-unknown-linux-<libc>.tar.gz` and its adjacent
`.sha256` checksum over HTTPS. The feature SHALL verify the archive before installing any contents. For `latest`, it
SHALL accept only a `MAJOR.MINOR.PATCH` tag from `https://github.com/astral-sh/uv/releases/latest` HTTPS redirect; it
SHALL rely on TLS alone for this unsigned name-only redirect. The feature SHALL NOT run an upstream installer script.

#### Scenario: Invalid latest release tag

- **WHEN** the latest-release redirect names a value other than `MAJOR.MINOR.PATCH`
- **THEN** installation fails without installing archive contents

### Requirement: Verify uv-managed Python downloads

When tools are requested, uv SHALL use default managed CPython sources:
`https://releases.astral.sh/github/python-build-standalone/releases/download/`, falling back to
`https://github.com/astral-sh/python-build-standalone/releases/download/`. Each interpreter SHALL be checked against the
SHA-256 carried by the installed uv release.

#### Scenario: Managed Python uses default sources

- **WHEN** a requested tool needs managed CPython
- **THEN** uv uses the stated source or fallback and verifies its digest

### Requirement: Verify uv tool package downloads

When tools are requested, uv SHALL use the default `https://pypi.org/simple/` index and
`https://files.pythonhosted.org/` files, checking each package against the index SHA-256. The feature SHALL configure no
alternate index or Python source, disable no uv check, and require uv >=`0.12.16` to install tools.

#### Scenario: Tool packages use default index verification

- **WHEN** a requested tool requires Python packages
- **THEN** uv downloads from the stated PyPI sources and verifies each file against its index digest

### Requirement: Install uv prerequisites from configured repositories

The feature SHALL install missing `curl`, CA certificates, `tar`, or `sha256sum` only from already configured image
repositories using the family manager (`apt`, `dnf`, `pacman`, `apk`, or `zypper`). The feature SHALL add no repository
or key and SHALL leave installed prerequisites in the image. On Arch, installing any missing prerequisite SHALL also
upgrade the image packages. If none is missing, the feature SHALL run no package manager.

#### Scenario: No missing prerequisites

- **WHEN** all four prerequisites are already present
- **THEN** the feature runs no package manager

### Requirement: Parse and install requested uv tools

The feature SHALL parse `toolsToInstall` as comma-separated entries, trim surrounding whitespace, and skip empty
entries. It SHALL install each with `uv tool install` and expose executables on every user's PATH. It SHALL reject
entries other than package names with at most one bracketed extra and one version constraint, including options, URLs,
paths, or internal whitespace; name the entry and fail before downloads. It SHALL fail if uv cannot install an entry.

#### Scenario: Invalid tool entry

- **WHEN** an entry is an option, URL, path, has internal whitespace, or otherwise violates the allowed package-name
  form
- **THEN** installation fails naming the entry before downloading anything

### Requirement: Keep build-time uv tools in the image

Tool environments and uv-managed interpreters installed for `toolsToInstall` SHALL live in the image outside the
persistent volume. The remote user SHALL be able to upgrade, reinstall, remove, and add tools at runtime without
elevated privileges.

#### Scenario: Tool survives empty runtime volume

- **WHEN** a build-time tool runs with a new empty persistent volume
- **THEN** it runs from the image and its interpreter resolves outside the volume

### Requirement: Use the uv group for non-root write access

For non-root remote users, the feature SHALL create system group `uv` if absent, otherwise reuse it with its ID
unchanged only when no other account belongs by listed or primary membership. The remote user, `/usr/local/share/uv` and
its installed contents, and a newly created `/var/lib/uv` volume SHALL have group-based write access, including after
the tooling changes the user's UID. A conflicting account SHALL fail under “Fail on unsupported platforms and invalid
options.”

#### Scenario: Existing group with another account

- **WHEN** a different account belongs to the existing `uv` group as a listed member or primary group
- **THEN** installation fails naming that account and does not reuse the group

### Requirement: Restrict uv installed-directory permissions

The install SHALL leave no file or directory under `/usr/local/share/uv` or in a newly created `/var/lib/uv` volume
writable by everyone. For non-root users, only root, group members, and the install-time owner may write installed
content; runtime-created content keeps modes from uv and the creating user's umask. For root, create no group and leave
both locations root-owned and root-writable only.

#### Scenario: Root remote user

- **WHEN** the remote user is root
- **THEN** no group is created and both locations are root-owned and writable only by root

### Requirement: Persist uv data per dev container

The feature SHALL mount a named volume `uv-${devcontainerId}` at `/var/lib/uv`, unique to each dev container, and point
uv's managed interpreter `python/` and `cache/` there. A new volume SHALL contain nothing written at build time and be
writable as “Use the uv group for non-root write access” specifies. Existing volume owner, group, and modes SHALL be
preserved except as “Repair a uv volume for the current user” permits.

#### Scenario: Separate dev containers

- **WHEN** two dev containers use this feature
- **THEN** each has its own volume and an interpreter in one is absent from the other

### Requirement: Determine whether the uv volume fits

A volume fits when the remote user can create files in `/var/lib/uv` and owns every entry beneath it. Writes by any
other UID, including root, make it not fit; root considers every volume fitting. At dev container creation and rebuild,
the feature SHALL check as the remote user before `devcontainer.json` creation commands run.

#### Scenario: Volume fit check precedes creation commands

- **WHEN** a dev container is created or rebuilt with a uv volume
- **THEN** the feature checks fit as the remote user before user creation commands

### Requirement: Repair a non-fitting uv volume

When the volume does not fit and passwordless `sudo` is available, the feature SHALL make the remote user owner and
group `uv` where present for the volume and every entry, so cached interpreters and packages remain usable. It SHALL
preserve contents, ordinary mode bits, and directory setgid bits. Ownership changes MAY clear executable setuid/setgid
bits; the feature SHALL NOT restore them or otherwise change modes, and SHALL add no sudo rule.

#### Scenario: Ownership repair preserves content and modes

- **WHEN** a non-fitting volume is repaired
- **THEN** entries receive the remote user's ownership and group `uv` where present, contents and ordinary modes remain,
  and executable special bits cleared by ownership changes are not restored

### Requirement: Continue when uv volume repair fails

If passwordless sudo is unavailable or ownership change fails, the feature SHALL leave `/var/lib/uv` unchanged, warn
with its path and reason, and continue container creation. It SHALL change nothing when the volume fits, when the user
is root, or outside `/var/lib/uv`.

#### Scenario: Repair unavailable or unnecessary

- **WHEN** repair is unavailable, the volume fits, or the remote user is root
- **THEN** container creation continues; unavailable repair warns and leaves the volume unchanged, while fitting and
  root volumes are not changed

### Requirement: Configure uv locations and PATH

For every container process, the feature SHALL set `UV_PYTHON_INSTALL_DIR=/var/lib/uv/python`,
`UV_CACHE_DIR=/var/lib/uv/cache`, `UV_TOOL_DIR=/usr/local/share/uv/tools`, `UV_TOOL_BIN_DIR=/usr/local/share/uv/bin`,
`UV_LINK_MODE=copy`, and SHALL append `/usr/local/share/uv/bin` after existing `/usr/local/bin` and `/usr/bin`,
including login shells whose system profile resets PATH. Earlier commands SHALL take precedence over same-named tools.

#### Scenario: System command takes precedence

- **WHEN** a system command and uv tool share a name
- **THEN** the earlier PATH command resolves first

### Requirement: Preserve uv state on repeated installation

A second install SHALL succeed. With same options and an already installed requested release, the feature SHALL download
no uv release and leave tools unchanged. With different options it SHALL replace `uv` and `uvx` with the later version,
retain tools from both installs, and make a repeated tool satisfy the later entry. Repeating for the same non-root user
SHALL add no group or membership and preserve access rules; another non-root user SHALL fail because the first user
belongs to `uv`.

#### Scenario: Different remote user on second install

- **WHEN** the feature is installed a second time for a different non-root remote user
- **THEN** it fails because the existing `uv` group has another member

### Requirement: Reject unsupported uv platforms and group setup

The feature SHALL fail before downloads for unsupported arch or distro families (Debian/Ubuntu, RHEL/Fedora, Arch,
Alpine, openSUSE/SUSE), nonempty `toolsToInstall` with uv <`0.12.16`, or a missing remote user, naming the issue. For
non-root it SHALL reject primary group `uv` because Dev Container tooling changes its GID with the user's UID,
preventing group write access. It SHALL reject other `uv` members or missing group tools. Supported images are listed in
`test/uv/compatibility.json`.

#### Scenario: Missing group-management tool

- **WHEN** a non-root user needs a `uv` group created or membership added but the image lacks the required tool
- **THEN** the build fails before downloads and names the group or user issue
