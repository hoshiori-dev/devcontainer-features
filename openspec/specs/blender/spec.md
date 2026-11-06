# blender Specification

## Purpose

Installs the official Blender release build for all users of a dev container, ready for headless scripting and rendering
by developers and coding agents, and for add-on and extension development.

Upstream sources:

- Home: https://www.blender.org/
- Source repository: https://projects.blender.org/blender/blender
- Official GitHub mirror: https://github.com/blender/blender
- Download page: https://www.blender.org/download/
- System requirements: https://www.blender.org/download/requirements/
- Long-term support releases: https://www.blender.org/download/lts/
- Release notes: https://developer.blender.org/docs/release_notes/
- Manual: https://docs.blender.org/manual/en/latest/
- Command line arguments: https://docs.blender.org/manual/en/latest/advanced/command_line/arguments.html
- Extensions: https://docs.blender.org/manual/en/latest/advanced/extensions/index.html
- Python API: https://docs.blender.org/api/current/

## Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here: `latest` selects the newest release at install time,
`MAJOR.MINOR` the newest release of that series, and `MAJOR.MINOR.PATCH` exactly that release, each 4.2.0 or later, and
any other value fails before downloads or package installation.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** `version` is omitted or set to `latest`
- **THEN** `blender --version` reports the newest release resolved during that installation

#### Scenario: Release series

- **WHEN** `version` names a series such as `4.5`
- **THEN** Blender reports the newest release of that series resolved during that installation

#### Scenario: Exact release

- **WHEN** `version` names a published release, 4.2.0 or later
- **THEN** Blender reports exactly that release

#### Scenario: Invalid version

- **WHEN** `version` is empty, carries a prefix or suffix such as `v5.2.3` or `5.2-lts`, names a release older than
  4.2.0, or is another unsupported value
- **THEN** installation fails naming the value and the accepted forms before downloading or installing packages

#### Scenario: Unavailable release

- **WHEN** the requested series has no qualifying release, or the requested release has no Linux x64 archive or no
  checksum file on the release host
- **THEN** installation fails naming the release or series and what is missing

### Requirement: Release resolution

The feature SHALL resolve `latest` from the listing at `https://download.blender.org/release/` and the series listings
it names, and a series from `https://download.blender.org/release/Blender<MAJOR>.<MINOR>/`, counting only releases whose
Linux x64 archive and checksum file are both listed and comparing versions numerically. An exact release SHALL need no
listing. Listings are trusted through TLS alone because Blender publishes no signed release index.

#### Scenario: Numeric selection

- **WHEN** `latest` or a series is resolved from listings whose entries are ordered as text
- **THEN** the numerically highest qualifying release is selected, for example 4.5.15 over 4.5.2

#### Scenario: Release without checksum

- **WHEN** the newest listed archive of the selection has no listed checksum file
- **THEN** that release is not selected

#### Scenario: Series not yet released

- **WHEN** `latest` is resolved while the newest series directory lists no qualifying release
- **THEN** the newest qualifying release of an earlier series is selected

#### Scenario: Listing unavailable

- **WHEN** a needed listing cannot be fetched, the requested series lists no qualifying release, or no series does for
  `latest`
- **THEN** installation fails naming the listing URL and leaves any managed installation unchanged

### Requirement: Verified official archive

The feature SHALL download
`https://download.blender.org/release/Blender<MAJOR>.<MINOR>/blender-<VERSION>-linux-x64.tar.xz` and, before extracting
it, verify its SHA-256 against the single entry for that file name in `blender-<VERSION>.sha256` from the same
directory. A missing checksum file or entry SHALL fail installation; no installer script SHALL run.

#### Scenario: Verified archive

- **WHEN** the archive's digest matches its single entry in the release's checksum file
- **THEN** only that verified archive supplies the installation

#### Scenario: Verification failure

- **WHEN** a download fails, the checksum file or its entry is missing or duplicated, or the digest differs
- **THEN** installation fails before extracting or executing anything from the archive and leaves any managed
  installation unchanged

### Requirement: Download host

Every request the feature makes itself SHALL go to `https://download.blender.org` over HTTPS and SHALL NOT follow a
redirect. Blender's download page links to a mirror redirector that sends clients to third-party mirrors, so the feature
uses neither that redirector nor the download page's links. A redirect, certificate error, or non-HTTPS URL SHALL fail
installation.

#### Scenario: Redirected request

- **WHEN** the release host answers a request with a redirect
- **THEN** installation fails naming the requested URL, without contacting the redirect target

#### Scenario: Transport failure

- **WHEN** a request meets a certificate error or a connection failure
- **THEN** installation fails without falling back to another host or to an unchecked download

### Requirement: Checksum trust

The checksum file SHALL be trusted through TLS alone. Blender publishes no signature for release archives or checksum
files, and both come from the same host, so verification detects a corrupted or truncated download but not a compromise
of that host. No certificate or checksum check SHALL be disabled, and the feature SHALL embed no checksum tied to a
particular release.

#### Scenario: Integrity source

- **WHEN** any release is installed
- **THEN** the only integrity evidence is that release's checksum file entry, fetched at install time

### Requirement: Supported platforms

The feature SHALL support the image and architecture pairs in `test/blender/compatibility.json`, all amd64, since
Blender publishes no Linux build for other architectures. It SHALL detect the distribution from `/etc/os-release`,
install on the Debian, Ubuntu, Fedora, and Enterprise Linux families, and reject other distributions, musl-based images,
and other architectures before downloads or package installation.

#### Scenario: Compatibility matrix

- **WHEN** installation runs on each declared image
- **THEN** `blender --version` reports the selected release for root and for the image's remote user

#### Scenario: Unsupported architecture

- **WHEN** installation runs on arm64 or another architecture than amd64
- **THEN** it fails stating that Blender publishes no Linux build for that architecture, before downloading or
  installing packages

#### Scenario: Unsupported distribution

- **WHEN** installation runs on Alpine, another musl-based image, or a distribution outside the supported families
- **THEN** it fails identifying the distribution before downloading or installing packages

### Requirement: Runtime libraries

The feature SHALL install, only from the image's configured repositories and without adding a repository or key, the
missing tools it needs to download, verify, and extract a release, and the system libraries Blender needs in background
mode: X11 client libraries, xkbcommon, and OpenGL and EGL with Mesa's DRI drivers, used through its software driver. It
SHALL clean temporary downloads and package-manager caches.

#### Scenario: Minimal supported image

- **WHEN** a supported image lacks these tools or libraries
- **THEN** installation obtains them non-interactively from the configured repositories and Blender starts in background
  mode

#### Scenario: Nothing beyond Blender's needs

- **WHEN** the feature is installed
- **THEN** it installs no display server, no Vulkan driver, no GPU driver package beyond Mesa's DRI package, and no
  Python interpreter or package beyond the one bundled with Blender

### Requirement: Headless rendering

Blender SHALL run in background mode on a container without a display server or GPU, for root and for the remote user:
Python scripts that use `bpy`, and renders with each built-in engine — Cycles on the CPU, Workbench and EEVEE through
Mesa's software OpenGL driver.

#### Scenario: Built-in engines

- **WHEN** a user renders a frame of the factory startup scene in background mode with Cycles, Workbench, or EEVEE
- **THEN** the command exits 0 and writes a non-empty image, without a display server

#### Scenario: Script status

- **WHEN** a user runs a script in background mode with factory settings and `--python-exit-code 1` before `--python`
- **THEN** Blender exits 0 when the script succeeds and 1 when it raises

### Requirement: Extension development

The installed Blender SHALL let the remote user validate, build, and install an extension package with
`blender --command extension`, without network access and without enabling Blender's online access, into that user's own
Blender directory.

#### Scenario: Offline extension workflow

- **WHEN** the remote user validates and builds a minimal extension and installs the built package from its file, in a
  container without network access
- **THEN** each command exits 0 and the extension is installed and enabled for that user only

### Requirement: System-wide installation

The feature SHALL install Blender under `/opt/blender`, owned and writable only by root, and expose only its executable,
through `/usr/local/bin/blender`, to every user. The link targets the executable rather than `blender-launcher`, so the
launcher's `LD_LIBRARY_PATH` does not reach processes a Blender script starts; in exchange, an `LD_LIBRARY_PATH` set for
the whole image takes precedence over Blender's bundled libraries.

#### Scenario: Non-root use

- **WHEN** a container starts as a non-root remote user
- **THEN** `blender` runs without sudo or shell initialization, keeps that user's settings under the user's home, and
  the user cannot modify the installation

#### Scenario: Executable link

- **WHEN** a Blender script started through `/usr/local/bin/blender` starts another process
- **THEN** the link resolves to `/opt/blender/blender`, and that process sees the caller's `LD_LIBRARY_PATH` unchanged

### Requirement: Precompiled bytecode

The feature SHALL precompile the bundled Python modules with Blender's own interpreter after verifying the archive, so
that running Blender, as root or as any other user, writes nothing into `/opt/blender`.

#### Scenario: Unchanged tree

- **WHEN** root and the remote user run Blender, including a Python script and an extension command
- **THEN** no file under `/opt/blender` is created, modified, or removed

### Requirement: Existing installation conflicts

The feature SHALL reject an existing `blender` command on the installer's PATH or the remote user's PATH, and an
occupied `/opt/blender` or `/usr/local/bin/blender`, unless it belongs to this feature's managed installation. The
diagnostic SHALL name the conflict and ask for its removal, and the conflicting files SHALL be preserved.

#### Scenario: Unmanaged command

- **WHEN** another installation, such as a distribution package, supplies a `blender` command, even at the requested
  version
- **THEN** installation fails with removal guidance and neither reuses nor overwrites it

#### Scenario: Occupied destination

- **WHEN** either destination is occupied by an unmanaged file, directory, or symbolic link, including a broken link
- **THEN** installation fails naming the path and preserves its contents

### Requirement: Repeat installation

Every invocation SHALL resolve the requested release anew, including `latest` and a series. If the healthy managed
installation already matches it, installation SHALL succeed without downloading the archive or changing the tree.
Otherwise the last successful invocation SHALL replace the managed installation with the selected release, upgrades and
downgrades alike, without accumulating links or PATH entries.

#### Scenario: Same release

- **WHEN** the feature runs again for the release already installed and the managed installation is healthy
- **THEN** it succeeds without downloading the archive or modifying the tree

#### Scenario: Changed release

- **WHEN** a managed installation is followed by an installation that selects another release
- **THEN** Blender reports the second release, newer or older, and the previous tree is gone

#### Scenario: Unhealthy managed installation

- **WHEN** the managed installation is unhealthy and the same release is selected again
- **THEN** a successful invocation replaces it with a freshly verified archive

### Requirement: Failed replacement

The feature SHALL preserve or restore the prior managed installation when downloading, verifying, extracting, or
validating a replacement fails, keeping it usable if it was usable before the attempt. Success SHALL require a runnable
Blender reporting the selected release.

#### Scenario: Replacement failure

- **WHEN** an attempt to change a healthy managed installation to another release fails
- **THEN** the previous Blender remains usable and reports the previous release

#### Scenario: Failed repair

- **WHEN** replacing an already unhealthy managed installation fails
- **THEN** installation reports failure and preserves or restores the prior tree without claiming that it is usable

### Requirement: Upstream defaults

The feature SHALL leave Blender's own defaults in place: it SHALL set no Blender environment variable, write no user
preferences, enable no online access, install no add-on, extension, or Python package, and request no editor extension
or editor setting.

#### Scenario: Fresh user

- **WHEN** the remote user starts the installed Blender for the first time
- **THEN** online access is off, Blender's per-user directories resolve under the user's home and are created only when
  Blender first saves state there, and only the add-ons and extensions bundled with the release are present

#### Scenario: Editor customizations

- **WHEN** a client applies the feature's metadata
- **THEN** it requests no editor extension and writes no editor settings

### Requirement: Usage guidance

`NOTES.md` SHALL document headless use for scripts and agents: how a failing script reaches the exit status, why each
run needs a time limit, and how to run with the developer's own extension enabled under factory settings, failing when
it cannot load. It SHALL also cover the offline extension workflow, enabling online access only on purpose, per-user
state, software rendering, the launcher for images that set `LD_LIBRARY_PATH`, and the amd64-only scope.

#### Scenario: Agent example

- **WHEN** a developer runs the notes' headless example with a script that succeeds and with one that raises
- **THEN** the first writes its output and exits 0, and the second exits non-zero

#### Scenario: Extension example

- **WHEN** a developer follows the notes' extension example in a container without network access
- **THEN** the extension validates, builds, and installs as described, and the notes' headless example runs a script
  with it enabled and exits non-zero when it cannot be loaded
