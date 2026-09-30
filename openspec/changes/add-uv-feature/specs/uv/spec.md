# Spec Delta

## Purpose

Installs Astral's uv Python package and project manager (`uv` and `uvx`) for every user of a dev container, optionally
installs Python command-line tools with it, and keeps the Python interpreters uv installs at runtime, and uv's cache, on
a volume that survives rebuilds of the dev container.

Upstream sources:

- Home: https://github.com/astral-sh/uv
- Documentation: https://docs.astral.sh/uv/
- Installation guide: https://docs.astral.sh/uv/getting-started/installation/
- Storage locations: https://docs.astral.sh/uv/reference/storage/
- Environment variables: https://docs.astral.sh/uv/reference/environment/
- Changelog: https://github.com/astral-sh/uv/blob/main/CHANGELOG.md

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here, naming either `latest`, meaning the newest release at
build time, or one release as `MAJOR.MINOR.PATCH`; SHALL install the `uv` and `uvx` executables of that upstream uv
release as `/usr/local/bin/uv` and `/usr/local/bin/uvx`, executable by every user; and SHALL fail the build on any other
value, with a message naming the value, before downloading anything.

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

The feature SHALL download the release archive from
`https://github.com/astral-sh/uv/releases/download/<version>/uv-<arch>-unknown-linux-<libc>.tar.gz` over HTTPS and SHALL
verify it against the SHA-256 checksum published beside it as the same URL with `.sha256` appended, before anything from
the archive is installed. For `latest`, the feature SHALL resolve the release from the redirect of
`https://github.com/astral-sh/uv/releases/latest` and SHALL accept only a `MAJOR.MINOR.PATCH` release name from it. The
feature SHALL trust that redirect on TLS alone, because upstream publishes no checksum or signature for it; it yields
only the release name, and the archive of that release is verified as above. The feature SHALL run no installer script
from upstream.

#### Scenario: Checksum matches

- **WHEN** the archive's SHA-256 digest equals the published checksum
- **THEN** `uv` and `uvx` from that archive are installed

#### Scenario: Checksum does not match

- **WHEN** the archive's SHA-256 digest differs from the published checksum, or the checksum cannot be downloaded
- **THEN** the build fails with a message naming the archive, and `/usr/local/bin/uv` and `/usr/local/bin/uvx` are left
  as they were before this install

### Requirement: Verify build-time tool downloads

When `toolsToInstall` is not empty, uv downloads at build time, on the feature's behalf, the interpreters and packages
the tools need. The feature SHALL configure no package index or Python download source and SHALL disable none of uv's
checks, so that these downloads come from uv's default sources and are verified by uv:

- managed CPython builds from `https://releases.astral.sh/github/python-build-standalone/releases/download/`, falling
  back to `https://github.com/astral-sh/python-build-standalone/releases/download/`, each checked against the SHA-256
  that the installed uv release carries for that build;
- packages from the index `https://pypi.org/simple/` and its files on `https://files.pythonhosted.org/`, each file
  checked against the SHA-256 the index supplies for it.

The feature SHALL install tools only with a uv release that checks index-supplied hashes, which is 0.12.16 or later.

#### Scenario: Default sources

- **WHEN** the feature installs a tool from `toolsToInstall` at build time
- **THEN** the tool's interpreter and packages are downloaded only from the sources above, and the install runs with no
  uv setting from the feature that changes a source or a hash check

### Requirement: Install download prerequisites only from the image's repositories

The feature SHALL install curl, CA certificates, tar, and `sha256sum`, when the image lacks them, only from the package
repositories the image already configures, and SHALL add no package repository or signing key. What it installs this way
stays in the image.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image without curl or CA certificates
- **THEN** the install succeeds, and the image's package repository configuration and signing keys are unchanged

### Requirement: Option toolsToInstall

The feature SHALL accept the option `toolsToInstall` as declared here, a comma-separated list in which whitespace around
an entry is ignored and empty entries are skipped; SHALL install each listed tool with `uv tool install` at build time
and put the tools' executables on `PATH` for every user; SHALL fail the build when an entry is not a package name with
at most one bracketed extra and one version constraint (an option, URL, path, or any whitespace inside an entry), with a
message naming the entry, before downloading anything; and SHALL fail the build when `uv tool install` cannot install a
listed tool.

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
the image, outside the persistent volume. The remote user SHALL be able to upgrade and add tools with `uv tool` at
runtime.

#### Scenario: Tools survive a replaced volume

- **WHEN** a tool from `toolsToInstall` runs in a container whose persistent volume is new and empty
- **THEN** the tool runs, and its interpreter resolves to a path outside the persistent volume

#### Scenario: Remote user manages tools

- **WHEN** the remote user runs `uv tool upgrade` for a tool from `toolsToInstall`, or `uv tool install` for a new tool,
  in the running container
- **THEN** the command succeeds without elevated privileges

### Requirement: Persist interpreters and cache per dev container

The feature SHALL mount a named volume `uv-${devcontainerId}`, one per dev container, at `/var/lib/uv-data`, and SHALL
point uv's managed-interpreter directory and cache into it. A newly created volume SHALL be owned by the remote user and
SHALL hold nothing written at build time.

#### Scenario: New volume

- **WHEN** a dev container with this feature is created and its volume does not exist yet
- **THEN** `/var/lib/uv-data` is a mount of that volume, owned by the remote user, and holds no files before uv first
  runs

#### Scenario: Runtime interpreter on the volume

- **WHEN** the remote user creates a virtual environment with a uv-managed interpreter that is not installed yet
- **THEN** the interpreter is installed under `/var/lib/uv-data`, and the environment's interpreter link resolves there

#### Scenario: Rebuild keeps a workspace environment

- **WHEN** a workspace `.venv/` created with a uv-managed interpreter exists and the dev container is rebuilt
- **THEN** the `.venv/`'s interpreter runs after the rebuild without being downloaded again, and packages cached before
  the rebuild are installed from the cache

#### Scenario: Separate dev containers

- **WHEN** two different dev containers install this feature
- **THEN** each mounts its own volume, and an interpreter installed in one does not appear in the other

### Requirement: Point uv at the feature's locations

The feature SHALL set, for every process in the container, `UV_PYTHON_INSTALL_DIR` to `/var/lib/uv-data/python`,
`UV_CACHE_DIR` to `/var/lib/uv-data/cache`, `UV_TOOL_DIR` to `/usr/local/share/uv/tools`, `UV_TOOL_BIN_DIR` to
`/usr/local/share/uv/bin`, `UV_LINK_MODE` to `copy`, and SHALL put `/usr/local/share/uv/bin` in `PATH` ahead of
`/usr/local/bin` and `/usr/bin`, also in login shells whose system profile resets `PATH`.

#### Scenario: Environment of the remote user

- **WHEN** the remote user opens a shell in the container, a login shell included
- **THEN** each of these variables has the stated value, and `PATH` contains `/usr/local/share/uv/bin` ahead of
  `/usr/local/bin` and `/usr/bin`

#### Scenario: Workspace install across filesystems

- **WHEN** the remote user installs packages from the cache into an environment in the bind-mounted workspace
- **THEN** uv copies the files and reports no link-mode fallback warning

### Requirement: Make uv available to later features

Features installed after this one in the same build SHALL find `uv` at `/usr/local/bin/uv` and SHALL see the environment
variables this feature sets.

#### Scenario: Later feature runs uv

- **WHEN** a feature that installs after this one runs `uv --version` during its own install
- **THEN** the command succeeds and `UV_PYTHON_INSTALL_DIR` is set to `/var/lib/uv-data/python`

### Requirement: Install twice

Installing the feature a second time on the same image SHALL succeed. With the same options, it SHALL download no uv
release when the requested release is already installed, and leave installed tools as they are. With different options,
the later `version` SHALL replace the installed `uv` and `uvx`, every tool from both installs SHALL remain installed,
and a tool listed again SHALL end up satisfying the entry of the later install.

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

### Requirement: Fail on unsupported platforms and invalid options

The feature SHALL fail the build with a message naming the problem, before downloading anything, when the container's
architecture is neither x86_64 nor aarch64, when the distribution is neither Debian- or Ubuntu-based nor Alpine, or when
`toolsToInstall` is not empty and `version` names a release older than 0.12.16. It SHALL also fail when the remote user
it is installed for does not exist. The Option requirements state how invalid values of a single option fail. The
supported images are those in `test/uv/compatibility.json`.

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on an architecture other than x86_64 or aarch64
- **THEN** the build fails with a message naming the architecture, and nothing is downloaded

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on a distribution that is neither Debian- or Ubuntu-based nor Alpine
- **THEN** the build fails with a message naming the distribution, and nothing is downloaded

#### Scenario: Tools with a uv release that does not check index hashes

- **WHEN** `toolsToInstall` is not empty and `version` names a release older than 0.12.16
- **THEN** the build fails with a message naming the version and 0.12.16, and nothing is downloaded

#### Scenario: Remote user missing

- **WHEN** the feature is installed for a remote user that does not exist in the image
- **THEN** the build fails with a message naming the user
