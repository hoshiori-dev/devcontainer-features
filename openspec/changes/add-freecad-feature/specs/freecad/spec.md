## Purpose

Installs the official FreeCAD release build for all users of a dev container: `freecadcmd` for scripting, modeling, and
file conversion by developers and coding agents without a display, and the `freecad` GUI for a display the developer
provides.

Upstream sources:

- Home: https://www.freecad.org/
- Source repository: https://github.com/FreeCAD/FreeCAD
- Download page: https://www.freecad.org/downloads.php
- Release notes: https://wiki.freecad.org/Release_notes
- Documentation: https://wiki.freecad.org/
- Start up and command line options: https://wiki.freecad.org/Start_up_and_Configuration
- Headless FreeCAD: https://wiki.freecad.org/Headless_FreeCAD
- Python scripting: https://wiki.freecad.org/Python_scripting_tutorial
- AppImage: https://wiki.freecad.org/AppImage

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here: `latest` selects the newest stable release at install
time, `MAJOR.MINOR` the newest stable release of that series, and `MAJOR.MINOR.PATCH` exactly that release, each 1.1.0
or later, and any other value fails before downloads or package installation.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** `version` is omitted or set to `latest`
- **THEN** `freecadcmd --version` reports the newest stable release resolved during that installation

#### Scenario: Release series

- **WHEN** `version` names a series such as `1.1`
- **THEN** FreeCAD reports the newest stable release of that series resolved during that installation

#### Scenario: Exact release

- **WHEN** `version` names a published stable release, 1.1.0 or later
- **THEN** FreeCAD reports exactly that release

#### Scenario: Invalid version

- **WHEN** `version` is empty, carries a prefix or suffix such as `v1.1.4` or `1.1.4-rc1`, names a weekly build such as
  `weekly-2026.11.25`, names a release older than 1.1.0, or is another unsupported value
- **THEN** installation fails naming the value and the accepted forms before downloading or installing packages

#### Scenario: Unavailable release

- **WHEN** the requested series has no stable release, or the requested release does not exist, is a draft or a
  pre-release, or has no AppImage or no checksum file for the image's architecture
- **THEN** installation fails naming the release or series and what is missing

### Requirement: Release resolution

The feature SHALL resolve `latest` from `https://api.github.com/repos/FreeCAD/FreeCAD/releases/latest`, an exact release
from `https://api.github.com/repos/FreeCAD/FreeCAD/releases/tags/<VERSION>`, and a series from the listing
`https://api.github.com/repos/FreeCAD/FreeCAD/releases`, comparing versions numerically. Release metadata is trusted
through TLS alone because GitHub does not sign these responses.

#### Scenario: Numeric selection

- **WHEN** a series is resolved from a listing that holds its releases in any order
- **THEN** the numerically highest stable release of the series is selected, for example 1.1.10 over 1.1.9

#### Scenario: Metadata unavailable

- **WHEN** release metadata cannot be fetched, including a rate-limit response, or cannot be read
- **THEN** installation fails naming the URL and leaves any managed installation unchanged

### Requirement: Stable releases only

The feature SHALL count only a release that is neither a draft nor a pre-release and whose tag is the plain version, so
that weekly builds and other pre-releases are never installed, whichever way the release was selected.

#### Scenario: Pre-releases in the listing

- **WHEN** the listing holds weekly builds or other pre-releases newer than every stable release
- **THEN** none of them is selected

#### Scenario: Unexpected latest release

- **WHEN** the release GitHub reports as latest is a draft or a pre-release, has a tag that is not a plain version, or
  is older than 1.1.0
- **THEN** installation fails naming the tag instead of installing it

### Requirement: Release asset

The feature SHALL take from the selected release the single asset named `FreeCAD_<VERSION>-Linux-<ARCH>.AppImage` or
`FreeCAD_<VERSION>-Linux-<ARCH>-py<DIGITS>.AppImage`, where `<ARCH>` is `x86_64` or `aarch64`, and its checksum file,
the asset `<NAME>-SHA256.txt` of the same release.

#### Scenario: Matching asset

- **WHEN** the release holds exactly one AppImage for the image's architecture and its checksum file
- **THEN** that pair is selected, whatever Python version its name carries

#### Scenario: Ambiguous or missing asset

- **WHEN** the release has no AppImage for the architecture, more than one, or no checksum file for it
- **THEN** installation fails naming the release and what is missing, without downloading an AppImage

### Requirement: Verified official AppImage

The feature SHALL download the AppImage and its checksum file from
`https://github.com/FreeCAD/FreeCAD/releases/download/<VERSION>/` and verify the AppImage's SHA-256 against the checksum
file before unpacking or running it. Downloads SHALL use HTTPS on every hop, including GitHub's redirect to its release
asset host.

#### Scenario: Verified AppImage

- **WHEN** the AppImage's digest matches the single entry for its name in its checksum file
- **THEN** only that verified AppImage supplies the installation

#### Scenario: Verification failure

- **WHEN** a download fails, the checksum file holds no entry or more than one for the AppImage, or the digest differs
- **THEN** installation fails before unpacking or running anything from the AppImage and leaves any managed installation
  unchanged

### Requirement: Checksum trust

The checksum file SHALL be trusted through TLS alone. FreeCAD publishes no signature for its Linux AppImages or their
checksum files, and both are assets of the same GitHub release, so verification detects a corrupted or truncated
download but not a compromise of the FreeCAD project's release. No certificate or checksum check SHALL be disabled, and
the feature SHALL embed no checksum tied to a particular release.

#### Scenario: Integrity source

- **WHEN** any release is installed
- **THEN** the only integrity evidence is that release's checksum file, fetched at install time

### Requirement: Unpacked installation

The feature SHALL unpack the verified AppImage at install time with the AppImage's own extraction, so that FreeCAD runs
in a container without FUSE, and SHALL NOT keep the AppImage file in the image. Running the AppImage's extraction
executes code from the verified file as root; it is the only upstream code the installation runs before FreeCAD itself.

#### Scenario: Container without FUSE

- **WHEN** the feature is installed in an image build and the container has no `/dev/fuse`
- **THEN** installation succeeds and FreeCAD runs from the unpacked tree

#### Scenario: Temporary files

- **WHEN** installation ends, successfully or not
- **THEN** the downloaded AppImage and other temporary files are removed

### Requirement: Supported platforms

The feature SHALL support the image and architecture pairs in `test/freecad/compatibility.json`, on amd64 and arm64. It
SHALL detect the distribution from `/etc/os-release`, install on the Debian, Ubuntu, Fedora, and Enterprise Linux
families, and reject other distributions, musl-based images, and other architectures before downloads or package
installation.

#### Scenario: Compatibility matrix

- **WHEN** installation runs on each declared image and architecture
- **THEN** `freecadcmd --version` reports the selected release for root and for the image's remote user

#### Scenario: Unsupported architecture

- **WHEN** installation runs on an architecture other than amd64 and arm64
- **THEN** it fails naming the architecture before downloading or installing packages

#### Scenario: Unsupported distribution

- **WHEN** installation runs on Alpine, another musl-based image, or a distribution outside the supported families
- **THEN** it fails identifying the distribution before downloading or installing packages

### Requirement: Runtime libraries

The feature SHALL install, only from the image's configured repositories and without adding a repository or key, the
missing tools it needs to resolve, download, and verify a release, and what the release build leaves to the host for its
GUI: Mesa's OpenGL and EGL libraries with its DRI drivers, a fontconfig configuration, and one font family. It SHALL
always install them, and SHALL clean temporary downloads and package-manager caches.

#### Scenario: Minimal supported image

- **WHEN** a supported image lacks these tools or libraries
- **THEN** installation obtains them non-interactively from the configured repositories

#### Scenario: Nothing beyond FreeCAD's needs

- **WHEN** the feature is installed
- **THEN** it installs no display server, no VNC or remote-desktop server, no window manager, no Vulkan driver, and no
  Python interpreter or package beyond those bundled with FreeCAD

### Requirement: System-wide installation

The feature SHALL install FreeCAD under `/opt/freecad`, owned and writable only by root and readable by every user.

#### Scenario: Non-root use

- **WHEN** a container starts as a non-root remote user
- **THEN** `freecadcmd` and `freecad` run without sudo or shell initialization, keep that user's settings under the
  user's home, and the user cannot modify the installation

### Requirement: Commands

The feature SHALL expose exactly two commands to every user, `/usr/local/bin/freecad` and `/usr/local/bin/freecadcmd`,
each a launcher the feature owns that starts the release's executable of the same name with the caller's arguments and
returns its exit status. The other programs in the release — its Python interpreter, pip, Gmsh, CalculiX, and Graphviz
tools — SHALL stay off `PATH`.

#### Scenario: Two commands

- **WHEN** the feature is installed
- **THEN** `freecad` and `freecadcmd` resolve to `/usr/local/bin`, and the feature adds no other command and no `PATH`
  entry

#### Scenario: Exit status

- **WHEN** a script run with `freecadcmd` ends with `sys.exit(3)`
- **THEN** the command exits 3

### Requirement: Launch environment

Each launcher SHALL set five variables that upstream's own AppImage launcher sets, each only where the caller's
environment leaves it unset: `FONTCONFIG_FILE` and `FONTCONFIG_PATH` naming the image's fontconfig configuration,
`SSL_CERT_FILE` and `GIT_SSL_CAINFO` naming the certificate bundle in the release, and `QT_QPA_PLATFORM=xcb`. It SHALL
set no other variable, and a variable the caller sets, even to an empty value, SHALL reach FreeCAD unchanged.

#### Scenario: Defaults

- **WHEN** `freecad` starts with none of these variables set
- **THEN** it uses the image's fonts and the X11 platform, as upstream's launcher does

#### Scenario: Caller's choice

- **WHEN** the caller sets `QT_QPA_PLATFORM=offscreen` or `SSL_CERT_FILE` to another bundle
- **THEN** FreeCAD starts with the caller's value, which upstream's launcher would have replaced

#### Scenario: Child processes

- **WHEN** a FreeCAD script starts another process
- **THEN** that process sees no `LD_LIBRARY_PATH`, `PYTHONHOME`, or `PYTHONPATH` set by the feature

### Requirement: Unchanged installation tree

The feature SHALL precompile the Python modules of the release with the release's own interpreter after verifying the
AppImage, so that running FreeCAD, as root or as any other user, writes nothing into `/opt/freecad`.

#### Scenario: Unchanged tree

- **WHEN** root and the remote user run `freecadcmd` scripts that import the bundled workbenches
- **THEN** no file under `/opt/freecad` is created, modified, or removed

### Requirement: Command-line use

`freecadcmd` SHALL run on a container without a display server or GPU, for root and for the remote user: Python scripts
that create and recompute a document, and import and export of the exchange formats the release supports.

#### Scenario: Model and export

- **WHEN** a user runs a script with `freecadcmd` that creates a solid, saves the document, and exports STEP and STL
- **THEN** the command exits 0 and each file is written and non-empty, without a display server

#### Scenario: Round trip

- **WHEN** a user runs a script that imports the exported STEP file
- **THEN** the imported shape has the volume of the original solid

### Requirement: GUI use

`freecad` SHALL start and render a 3D view through an X server the developer provides, using Mesa's software OpenGL
driver when the container has no GPU, for root and for the remote user. The feature SHALL NOT provide the display:
without one, and without another Qt platform chosen by the caller, `freecad` fails as upstream's build does.

#### Scenario: X server available

- **WHEN** a user runs `freecad` with a script that opens a document and saves an image of its 3D view, with `DISPLAY`
  naming a reachable X server
- **THEN** the command exits 0 and the image shows the model

#### Scenario: Offscreen platform

- **WHEN** a user runs `freecad` with `QT_QPA_PLATFORM=offscreen` and a script that uses the GUI module without a 3D
  view
- **THEN** the script runs with the GUI up and the command exits 0, without a display server

#### Scenario: No display

- **WHEN** a user runs `freecad` with no display and no Qt platform chosen
- **THEN** the command fails with Qt's message that no platform plugin could be initialized

### Requirement: Existing installation conflicts

The feature SHALL reject an existing `freecad` or `freecadcmd` command on the installer's PATH or the remote user's
PATH, and an occupied `/opt/freecad`, `/usr/local/bin/freecad`, or `/usr/local/bin/freecadcmd`, unless it belongs to
this feature's managed installation. The diagnostic SHALL name the conflict and ask for its removal, and the conflicting
files SHALL be preserved.

#### Scenario: Unmanaged command

- **WHEN** another installation, such as a distribution package, supplies a `freecad` or `freecadcmd` command, even at
  the requested version
- **THEN** installation fails with removal guidance and neither reuses nor overwrites it

#### Scenario: Occupied destination

- **WHEN** a destination is occupied by an unmanaged file, directory, or symbolic link, including a broken link
- **THEN** installation fails naming the path and preserves its contents

### Requirement: Repeat installation

Every invocation SHALL resolve the requested release anew, including `latest` and a series. If the healthy managed
installation already matches it, installation SHALL succeed without downloading the AppImage or changing the tree.
Otherwise the last successful invocation SHALL replace the managed installation with the selected release, upgrades and
downgrades alike, without accumulating commands or PATH entries.

#### Scenario: Same release

- **WHEN** the feature runs again for the release already installed and the managed installation is healthy
- **THEN** it succeeds without downloading the AppImage or modifying the tree

#### Scenario: Changed release

- **WHEN** a managed installation is followed by an installation that selects another release
- **THEN** FreeCAD reports the second release, newer or older, and the previous tree is gone

#### Scenario: Unhealthy managed installation

- **WHEN** the managed installation is unhealthy and the same release is selected again
- **THEN** a successful invocation replaces it with a freshly verified AppImage

### Requirement: Failed replacement

The feature SHALL preserve or restore the prior managed installation when downloading, verifying, unpacking, or
validating a replacement fails, keeping it usable if it was usable before the attempt. Success SHALL require a runnable
`freecadcmd` reporting the selected release.

#### Scenario: Replacement failure

- **WHEN** an attempt to change a healthy managed installation to another release fails
- **THEN** the previous FreeCAD remains usable and reports the previous release

#### Scenario: Failed repair

- **WHEN** replacing an already unhealthy managed installation fails
- **THEN** installation reports failure and preserves or restores the prior tree without claiming that it is usable

### Requirement: Upstream defaults

The feature SHALL leave FreeCAD's own defaults in place: beyond the launch environment it SHALL set no environment
variable, write no user preferences, install no add-on, workbench, macro, or Python package, register no desktop entry
or file association, and request no editor extension or editor setting.

#### Scenario: Fresh user

- **WHEN** the remote user starts the installed FreeCAD for the first time
- **THEN** FreeCAD's per-user directories resolve under the user's home and are created by FreeCAD itself, and only the
  workbenches bundled with the release are present

#### Scenario: Editor customizations

- **WHEN** a client applies the feature's metadata
- **THEN** it requests no editor extension and writes no editor settings

### Requirement: Usage guidance

`NOTES.md` SHALL document command-line use for scripts and agents: running a script with `freecadcmd`, how a failing
script reaches the exit status given that an uncaught exception alone leaves it 0, and why each run needs a time limit.
It SHALL also cover giving the GUI a display, the Qt platform default and how to override it, software rendering,
per-user state, the size of the installation, and the programs that stay off `PATH`.

#### Scenario: Agent example

- **WHEN** a developer runs the notes' command-line example with a script that succeeds and with one that raises
- **THEN** the first writes its output and exits 0, and the second exits non-zero

#### Scenario: GUI example

- **WHEN** a developer follows the notes' GUI example on a container with an X server
- **THEN** `freecad` starts and renders as described
