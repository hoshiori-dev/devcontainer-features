# Spec Delta

## Purpose

Installs the standard build of the Godot game engine's editor (`godot`) from upstream's release artifacts at a chosen or
the latest stable release, on `PATH` for every user of the container, for headless use: running projects, importing, and
serving the GDScript language server. It installs no editor extension, no export templates, no .NET build, and nothing
for a graphical session.

Upstream sources:

- Project home and README: https://github.com/godotengine/godot
- Website: https://godotengine.org
- Documentation: https://docs.godotengine.org/en/stable/
- Command line tutorial: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Export templates: https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- Release policy: https://docs.godotengine.org/en/stable/about/release_policy.html
- Releases and changelog: https://github.com/godotengine/godot/releases
- Godot Tools extension: https://github.com/godotengine/godot-vscode-plugin

## ADDED Requirements

### Requirement: Godot on PATH for every user

The feature SHALL install the Godot editor executable at `/usr/local/bin/godot`, executable by every user, so that
`godot` resolves to it on the default `PATH` of the remote user and of root.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/godot/compatibility.json`
- **THEN** `command -v godot` run as the remote user resolves, following symbolic links, to `/usr/local/bin/godot`
- **AND** `godot --version` run as the remote user exits 0 and prints a version ending in `.stable.official.` followed
  by a commit hash

### Requirement: Headless use

The installed editor SHALL run headless as the remote user without a display server and without any package beyond those
the feature installs: it SHALL run a project, import a project's resources, and serve the GDScript language server. A
minimal project here is a `project.godot` whose `application/run/main_scene` names a scene holding one node.

#### Scenario: Running a project headless

- **WHEN** the remote user runs `godot --headless --path <project> --quit` on a minimal project
- **THEN** the command exits 0

#### Scenario: Importing a project headless

- **WHEN** the remote user runs `godot --headless --path <project> --import` on a minimal project
- **THEN** the command exits 0, its output reports no missing font configuration library, and the project's `.godot/`
  directory exists afterwards

#### Scenario: Language server headless

- **WHEN** the remote user runs `godot --headless --editor --path <project> --lsp-port <port>` on a minimal project
- **THEN** the process accepts TCP connections on `127.0.0.1:<port>` until it is stopped

### Requirement: Option version

The feature SHALL accept `version` and install the stable release it selects.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `godot --version` reports the release that the latest-release link pointed to during the build

#### Scenario: Explicit version

- **WHEN** the feature is installed with `version` set to an existing stable release such as `4.6.3`
- **THEN** `godot --version` reports `4.6.3.stable.official.` followed by a commit hash

#### Scenario: Tag form accepted

- **WHEN** the feature is installed with `version` set to `4.6.3-stable`
- **THEN** `godot --version` reports `4.6.3.stable.official.` followed by a commit hash

#### Scenario: Zero patch accepted

- **WHEN** the feature is installed with `version` set to `4.6.0`
- **THEN** `godot --version` reports `4.6.stable.official.` followed by a commit hash

#### Scenario: Version below the minimum

- **WHEN** the feature is installed with `version` set to a release below `4.2.2`, such as `4.2.1` or `4.1.4`
- **THEN** the install fails before downloading anything, with a message naming `4.2.2` as the minimum

#### Scenario: Pre-release version

- **WHEN** the feature is installed with `version` set to a pre-release such as `4.8-beta2` or `4.7-rc1`
- **THEN** the install fails before downloading anything, with a message saying that only stable releases are accepted

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a value such as `4`, `v4.7.2`, `4.7.2.1`, `4.06`, or `master`
- **THEN** the install fails before downloading anything, with a message naming the accepted forms

#### Scenario: Release that does not exist

- **WHEN** the feature is installed with `version` set to a well-formed version that has no release, such as `4.6.9`
- **THEN** the install fails with a message naming the version, and `/usr/local/bin/godot` is left as it was before the
  install

### Requirement: Godot release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://github.com/godotengine/godot/releases/latest redirects to at build time; any other value is a selected version
`MAJOR.MINOR` or `MAJOR.MINOR.PATCH` of decimal numbers without leading zeros, at or above `4.2.2`, optionally followed
by `-stable`, and names the release tagged `<version>-stable`, where `<version>` is the selected version without the
suffix and without a zero patch.

#### Scenario: Two-part version

- **WHEN** the feature is installed with `version` set to `4.6`
- **THEN** it installs the release tagged `4.6-stable`, and `godot --version` reports `4.6.stable.official.` followed by
  a commit hash

### Requirement: Godot version rejection

The feature SHALL reject, before downloading anything, any `version` value other than `latest` or a selected version
that requirement "Godot release version selection" accepts. When `version` is `latest`, it SHALL use the tag the link
names unchanged and SHALL fail before downloading any archive unless that tag is exactly `MAJOR.MINOR-stable` or
`MAJOR.MINOR.PATCH-stable` with a non-zero patch, of decimal numbers without leading zeros, at or above `4.2.2`.

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag of
  another form or below `4.2.2`, such as `3.6.3-stable` or `4.2.1-stable`
- **THEN** the install fails before downloading any archive, with a message naming the tag, and `/usr/local/bin/godot`
  is left as it was before the install

### Requirement: Godot release assets

The feature SHALL download the archive
`https://github.com/godotengine/godot/releases/download/<tag>/Godot_v<tag>_linux.<arch>.zip` and the checksum list
`https://github.com/godotengine/godot/releases/download/<tag>/SHA512-SUMS.txt`, where `<tag>` is the selected tag (such
as `4.6.3-stable`) and `<arch>` is `x86_64` or `arm64`, over HTTPS only, including every redirect.

#### Scenario: Release without an archive for the architecture

- **WHEN** the selected release has no archive for the machine's architecture
- **THEN** the install fails with a message naming the archive, and `/usr/local/bin/godot` is left as it was before the
  install

### Requirement: Verified download from the GitHub release

The feature SHALL install from the archive only when the checksum list holds exactly one entry whose file name equals
the archive's name and the archive's SHA-512 digest equals that entry. It SHALL fail when the checksum list cannot be
downloaded, since upstream publishes one for every release the feature accepts.

#### Scenario: Digest matches

- **WHEN** the archive's SHA-512 digest equals its entry in the checksum list
- **THEN** the feature installs the editor from that archive

#### Scenario: Digest mismatch

- **WHEN** the archive's SHA-512 digest differs from its entry in the checksum list
- **THEN** the install fails with a message saying verification failed, and `/usr/local/bin/godot` is left as it was
  before the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message naming the archive and saying verification failed, and
  `/usr/local/bin/godot` is left as it was before the install

#### Scenario: Checksum list missing

- **WHEN** the checksum list cannot be downloaded, for example because upstream has not uploaded it yet
- **THEN** the install fails with a message naming the checksum list, and `/usr/local/bin/godot` is left as it was
  before the install

### Requirement: Godot release metadata trust

The feature SHALL rely on TLS alone for the checksum list, which upstream publishes unsigned from the same origin as the
archive and may replace after publication, so verification establishes the archive's integrity against the published
release, not the publisher's authenticity. It SHALL read the latest-release link's redirect over HTTPS without following
it, relying on TLS alone, since upstream signs neither.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the latest-release link's redirect over HTTPS without following it

### Requirement: Godot archive content

The feature SHALL install only when the verified archive holds exactly one entry, the executable
`Godot_v<tag>_linux.<arch>` at its root, and that executable, run with `--version` before it replaces anything, exits 0
and prints `<version>.stable.official.` followed by a commit hash, where `<version>` is the selected tag without its
`-stable` suffix.

#### Scenario: Unexpected archive content

- **WHEN** the verified archive holds any entry other than the expected executable, or lacks it
- **THEN** the install fails with a message naming the archive, and `/usr/local/bin/godot` is left as it was before the
  install

#### Scenario: Executable that does not run

- **WHEN** the extracted executable exits non-zero or reports another version when run with `--version`, for example on
  an image whose C library is too old for it
- **THEN** the install fails with a message naming the version check, and `/usr/local/bin/godot` is left as it was
  before the install

### Requirement: No editor customizations

The feature SHALL declare no editor customizations: it SHALL NOT request the Godot Tools VS Code extension or any other
extension, and SHALL write no editor setting. That extension runs, on every activation, an executable the opened
workspace's own settings can choose, and a dev container window trusts every folder opened in it, so installing it is
left to the user's own configuration, where it is visible.

#### Scenario: Metadata without customizations

- **WHEN** a client reads the feature's metadata
- **THEN** it finds no `customizations` entry, so the feature requests no extension and sets no editor setting

### Requirement: Prerequisites

The feature SHALL install, from the image's configured package repositories and only when missing, the tools it needs to
download, verify, and extract the archive and the font configuration library the editor loads at start, and SHALL leave
them installed. It SHALL install no X11, Wayland, GL, EGL, Vulkan, ALSA, or PulseAudio library and no .NET package.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image listed in `test/godot/compatibility.json` that lacks `curl`, CA
  certificates, or `unzip`
- **THEN** the install succeeds, and `curl`, the CA certificate bundle, and `unzip` are present afterwards

#### Scenario: No graphical session libraries

- **WHEN** the feature has been installed with default options on an image where none of `libX11.so.6`,
  `libwayland-client.so.0`, `libGL.so.1`, `libEGL.so.1`, `libvulkan.so.1`, `libasound.so.2`, and `libpulse.so.0` is
  known to the dynamic linker
- **THEN** none of them is known to the dynamic linker afterwards, and `dotnet` does not resolve on the remote user's
  `PATH`

### Requirement: No other configuration

The feature SHALL leave no Godot configuration, data, cache, or export template anywhere in the image, SHALL NOT create
the self-contained mode marker beside the executable, write any file under a user's home directory, edit shell startup
files, or set an environment variable, and SHALL NOT run a project or start the editor during the build.

#### Scenario: Nothing else configured after install

- **WHEN** the feature has been installed with default options
- **THEN** neither the remote user's nor root's home holds `.local/share/godot`, `.config/godot`, `.cache/godot`, or
  `.cache/fontconfig`
- **AND** `/usr/local/bin` holds neither `_sc_` nor `._sc_`
- **AND** no environment variable whose name starts with `GODOT` is set in the remote user's environment

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/godot/compatibility.json` and reject unsupported platforms
before changes.

#### Scenario: Unsupported architecture

- **WHEN** the feature is installed on a machine whose architecture is neither x86_64 nor aarch64
- **THEN** the install fails with a message naming the architecture, and nothing is downloaded or installed

#### Scenario: Unsupported distribution

- **WHEN** the feature is installed on an image whose `/etc/os-release` is missing or names none of the supported
  families
- **THEN** the install fails with a message naming the distribution, or saying that `/etc/os-release` is missing, and
  nothing is downloaded or installed

#### Scenario: musl-based image

- **WHEN** the feature is installed on an image that has bash and whose `/etc/os-release` identifies Alpine
- **THEN** the install fails with a message saying that upstream's builds need the GNU C library, and nothing is
  downloaded or installed

#### Scenario: Supported family without its package manager

- **WHEN** the feature is installed on an image whose `/etc/os-release` matches a supported family but which lacks that
  family's package manager
- **THEN** the install fails with a message naming the distribution and the missing package manager, and nothing is
  downloaded or installed

### Requirement: Godot platform gate

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian, Ubuntu, and Fedora families; or when the image lacks the matched family's
package manager (`apt-get` for Debian and Ubuntu, `dnf` for Fedora).

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or identifies a
  distribution outside the supported families, or the image lacks the matched family's package manager
- **THEN** the install fails before downloading or installing anything, with a message naming what is unsupported

### Requirement: Installing twice

A second install SHALL succeed, apply the later options, and preserve the earlier executable if the second install
fails.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second leaves `/usr/local/bin/godot` unchanged, and `godot --version` reports that
  version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `godot --version` reports the version the second install selected
- **AND** `command -v godot` resolves, following symbolic links, to `/usr/local/bin/godot`, and `/usr/local/bin` holds
  no file other than `godot` whose name starts with `godot` or `.godot`

#### Scenario: Unreadable installed version

- **WHEN** `/usr/local/bin/godot` exists but exits non-zero or prints no version ending in `.stable.official.` followed
  by a commit hash, and the feature is installed
- **THEN** the install succeeds and replaces it, and `godot --version` reports the requested version

#### Scenario: Failed second install

- **WHEN** a second install fails, for example because verification fails
- **THEN** `godot --version` still reports the version of the first install

### Requirement: Godot replacement safety

When the installed `/usr/local/bin/godot` already reports the requested version as an official stable build, a second
install SHALL leave it untouched and download no archive; otherwise, including when its version cannot be read, the
later install SHALL replace it, so that exactly one `godot` remains. A second install that fails SHALL leave the earlier
`godot` in place.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`, or with two values that select the same version such
  as `4.6`, `4.6.0`, and `4.6-stable`
- **THEN** the second install leaves `/usr/local/bin/godot` unchanged and downloads no archive

### Requirement: Godot non-regular target

When `/usr/local/bin/godot` exists but is not a regular file, the install SHALL fail before downloading anything, with a
message naming the path, and leave it as it is.

#### Scenario: Existing target is not a regular file

- **WHEN** `/usr/local/bin/godot` exists but is not a regular file, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the prerequisites it
installs: after installing with `apt-get` it SHALL leave apt's package lists empty, and after installing with `dnf` it
SHALL leave dnf's cache without metadata or downloaded packages. No temporary directory, archive, or staged executable
of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/godot/compatibility.json`
- **THEN** apt's package lists and dnf's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory, archive, or staged executable of the install remains in the temporary directory or in
  `/usr/local/bin`
