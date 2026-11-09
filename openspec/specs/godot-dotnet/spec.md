# godot-dotnet Specification

## Purpose

Installs the .NET build of the Godot game engine's editor (`godot`) from upstream's release artifacts at a chosen or the
latest stable release, on `PATH` for every user of the container, with a .NET SDK from the first-party dotnet feature,
for headless use: building C# scripts, running projects, importing, and serving the language server. It requests no
editor extension of its own, installs no export templates and nothing for a graphical session, and cannot be combined
with the `godot` feature.

Upstream sources:

- Project home and README: https://github.com/godotengine/godot
- Website: https://godotengine.org
- Documentation: https://docs.godotengine.org/en/stable/
- C# basics: https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html
- Command line tutorial: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
- Export templates: https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html
- Release policy: https://docs.godotengine.org/en/stable/about/release_policy.html
- Releases and changelog: https://github.com/godotengine/godot/releases
- dotnet feature: https://github.com/devcontainers/features/tree/main/src/dotnet
- Godot Tools extension: https://github.com/godotengine/godot-vscode-plugin

## Requirements

### Requirement: Godot .NET on PATH for every user

The feature SHALL install one release directory under `/opt/godot-dotnet`, holding the editor executable and the
`GodotSharp` directory upstream ships beside it, all owned by root and writable by no one else, and SHALL make
`/usr/local/bin/godot` a symbolic link to that executable, so that `godot` resolves to it on the default `PATH` of the
remote user and of root.

#### Scenario: Default install

- **WHEN** the feature is installed with default options on an image listed in `test/godot-dotnet/compatibility.json`
- **THEN** `command -v godot` run as the remote user prints `/usr/local/bin/godot`, a symbolic link to an executable in
  a directory directly under `/opt/godot-dotnet`
- **AND** `godot --version` run as the remote user exits 0 and prints a version ending in `.stable.mono.official.`
  followed by a commit hash
- **AND** every file and directory under `/opt/godot-dotnet` is owned by root and has neither the group nor the other
  write permission

### Requirement: .NET SDK dependency

The feature SHALL declare `ghcr.io/devcontainers/features/dotnet:2` with options `{"version": "lts"}` as its only
`dependsOn` entry, so that the CLI installs the current long-term-support .NET SDK first and `dotnet` resolves on the
remote user's `PATH`. The editor uses the newest .NET major present, so a newer one, from a consumer's own dotnet entry
or the next LTS, may break its C# builds as .NET 11 RC3 did; this is accepted.

#### Scenario: SDK available to the remote user

- **WHEN** the feature has been installed with default options
- **THEN** `dotnet --list-sdks` run as the remote user exits 0 and lists at least one SDK

#### Scenario: Metadata names the dependency

- **WHEN** a client reads the feature's metadata
- **THEN** `dependsOn` holds exactly one entry, `ghcr.io/devcontainers/features/dotnet:2`, with options
  `{"version": "lts"}`

### Requirement: .NET SDK dependency trust

The feature SHALL take its dotnet dependency as published under that major tag, including how it installs the SDK: with
Microsoft's `dotnet-install.sh`, which checks only each downloaded file's size, so the SDK's integrity rests on TLS
alone. This is accepted: it is the Dev Containers project's own .NET install, and the dependency is visible in the
feature's metadata.

#### Scenario: SDK installed by the dependency

- **WHEN** the feature has been installed with default options
- **THEN** the SDK that `dotnet --list-sdks` lists lies under the directory that `DOTNET_ROOT` names in the remote
  user's environment

### Requirement: What the dotnet dependency adds

The feature SHALL leave in place what its dotnet dependency adds besides the SDK: `/usr/bin/dotnet`; `DOTNET_ROOT`, a
`PATH` entry, and two other `DOTNET_` variables; a login-shell `PATH` entry for `~/.dotnet/tools`; `dotnet` completions;
the runtime's libraries, CA certificates, `wget`, `jq`, and ICU tools; and in VS Code the C# extension
`ms-dotnettools.csharp` and a Copilot instruction setting. A user opts out of the extension with
`-ms-dotnettools.csharp`.

#### Scenario: Dependency environment reaches the remote user

- **WHEN** the feature has been installed with default options
- **THEN** `DOTNET_ROOT` is set in the remote user's environment and names the directory that the `dotnet` on the remote
  user's `PATH` resolves into, following symbolic links

#### Scenario: Extension requested through the dependency

- **WHEN** a client merges the configuration of a dev container that adds this feature
- **THEN** the merged VS Code extensions include `ms-dotnettools.csharp`, which comes from the dotnet feature's
  metadata, not from this feature's

### Requirement: C# extension trust

The C# extension that the dotnet dependency requests SHALL be accepted with its behavior: in any workspace holding a
`.csproj` opened in the container, it restores and loads the projects with MSBuild, running build logic they define, and
runs the server that `dotnet.server.path` names, a setting the workspace may set. The feature cannot remove another
feature's request, and the maintainer chose the dependency knowing it.

#### Scenario: Extension left to the dependency and the user

- **WHEN** a client reads this feature's own metadata
- **THEN** it finds no request for `ms-dotnettools.csharp` and no setting for it, so whether the extension is installed
  is decided by the dotnet feature and the user's own configuration

### Requirement: Headless use

The installed editor SHALL run headless as the remote user without a display server: it SHALL build a C# project's
scripts with the SDK on `PATH`, run a project, import a project's resources, and serve the GDScript language server. A
minimal C# project here is a `project.godot` whose main scene holds one node with a C# script, and a `.csproj` using the
`Godot.NET.Sdk` version of the installed release; a minimal project has the scene without the script.

#### Scenario: Building C# scripts headless

- **WHEN** the feature has been installed with default options and the remote user runs
  `godot --headless --path <project> --build-solutions --quit` on a minimal C# project while nuget.org is reachable
- **THEN** the command exits 0 and the project's assembly exists under `<project>/.godot/mono/temp/bin/`

#### Scenario: Running a C# project headless

- **WHEN** the remote user then runs `godot --headless --path <project> --quit-after <frames>` on that project
- **THEN** the command exits 0 and its output holds the line the C# script prints when its node is ready

#### Scenario: Running a project headless

- **WHEN** the feature has been installed with default options and the remote user runs
  `godot --headless --path <project> --quit` on a minimal project
- **THEN** the command exits 0

#### Scenario: Importing a project headless

- **WHEN** the feature has been installed with default options and the remote user runs
  `godot --headless --path <project> --import` on a minimal project
- **THEN** the command exits 0, its output reports no missing font configuration library, and the project's `.godot/`
  directory exists afterwards

#### Scenario: Language server headless

- **WHEN** the feature has been installed with default options and the remote user runs
  `godot --headless --editor --path <project> --lsp-port <port>` on a minimal project
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
- **THEN** `godot --version` reports `4.6.3.stable.mono.official.` followed by a commit hash

#### Scenario: Tag form accepted

- **WHEN** the feature is installed with `version` set to `4.6.3-stable`
- **THEN** `godot --version` reports `4.6.3.stable.mono.official.` followed by a commit hash

#### Scenario: Zero patch accepted

- **WHEN** the feature is installed with `version` set to `4.6.0`
- **THEN** `godot --version` reports `4.6.stable.mono.official.` followed by a commit hash

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
- **THEN** the install fails with a message naming the version, and the installation is left as it was before the
  install

### Requirement: Godot .NET release version selection

The feature SHALL install the release `version` selects: `latest` means the release that
https://github.com/godotengine/godot/releases/latest redirects to at build time; any other value is a selected version
`MAJOR.MINOR` or `MAJOR.MINOR.PATCH` of decimal numbers without leading zeros, at or above `4.2.2`, optionally followed
by `-stable`, and names the release tagged `<version>-stable`, where `<version>` is the selected version without the
suffix and without a zero patch.

#### Scenario: Two-part version

- **WHEN** the feature is installed with `version` set to `4.6`
- **THEN** it installs the release tagged `4.6-stable`, and `godot --version` reports `4.6.stable.mono.official.`
  followed by a commit hash

### Requirement: Godot .NET version rejection

The feature SHALL reject, before downloading anything, any `version` value other than `latest` or a selected version
that requirement "Godot .NET release version selection" accepts. When `version` is `latest`, it SHALL use the tag the
link names unchanged and SHALL fail before downloading any archive unless that tag is exactly `MAJOR.MINOR-stable` or
`MAJOR.MINOR.PATCH-stable` with a non-zero patch, of decimal numbers without leading zeros, at or above `4.2.2`.

#### Scenario: Latest-release link to an unusable tag

- **WHEN** the feature is installed with `version` set to `latest` and the latest-release link points to a tag of
  another form or below `4.2.2`, such as `3.6.3-stable` or `4.2.1-stable`
- **THEN** the install fails before downloading any archive, with a message naming the tag, and the installation is left
  as it was before the install

### Requirement: Godot .NET release assets

The feature SHALL download the archive
`https://github.com/godotengine/godot/releases/download/<tag>/Godot_v<tag>_mono_linux_<arch>.zip` and the checksum list
`https://github.com/godotengine/godot/releases/download/<tag>/SHA512-SUMS.txt`, where `<tag>` is the selected tag (such
as `4.6.3-stable`) and `<arch>` is `x86_64` or `arm64`, over HTTPS only, including every redirect.

#### Scenario: Release without an archive for the architecture

- **WHEN** the selected release has no archive for the machine's architecture
- **THEN** the install fails with a message naming the archive, and the installation is left as it was before the
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
- **THEN** the install fails with a message saying verification failed, and the installation is left as it was before
  the install

#### Scenario: No entry for the archive

- **WHEN** the checksum list holds no entry, or more than one, whose file name equals the archive's name
- **THEN** the install fails with a message naming the archive and saying verification failed, and the installation is
  left as it was before the install

#### Scenario: Checksum list missing

- **WHEN** the checksum list cannot be downloaded, for example because upstream has not uploaded it yet
- **THEN** the install fails with a message naming the checksum list, and the installation is left as it was before the
  install

### Requirement: Godot .NET release metadata trust

The feature SHALL rely on TLS alone for the checksum list, which upstream publishes unsigned from the same origin as the
archive and may replace after publication, so verification establishes the archive's integrity against the published
release, not the publisher's authenticity. It SHALL read the latest-release link's redirect over HTTPS without following
it, relying on TLS alone, since upstream signs neither.

#### Scenario: Resolving latest

- **WHEN** the feature is installed with `version` set to `latest`
- **THEN** it reads the latest-release link's redirect over HTTPS without following it

### Requirement: Godot .NET archive content

The feature SHALL install only when every entry of the verified archive lies under one top directory
`Godot_v<tag>_mono_linux_<arch>/`, which holds exactly the executable `Godot_v<tag>_mono_linux.<arch>` and the directory
`GodotSharp/`, with no symbolic link and no `..` component, and when that executable, run with `--version` before
anything is replaced, exits 0 and prints `<version>.stable.mono.official.` and a commit hash, `<version>` being the
selected tag without `-stable`.

#### Scenario: Unexpected archive content

- **WHEN** the verified archive holds an entry outside the expected top directory, a symbolic link, a `..` component, or
  anything other than the executable and the `GodotSharp/` directory directly in the top directory, or lacks either of
  them
- **THEN** the install fails with a message naming the archive, and the installation is left as it was before the
  install

#### Scenario: Executable that does not run

- **WHEN** the extracted executable exits non-zero or reports another version or build when run with `--version`, for
  example on an image whose C library is too old for it
- **THEN** the install fails with a message naming the version check, and the installation is left as it was before the
  install

### Requirement: Exclusive with the godot feature

The feature SHALL fail before downloading anything, leaving the path as it is, when `/usr/local/bin/godot` exists and is
not a link whose literal target is `/opt/godot-dotnet/<name>/godot` (`<name>` one path component, not `.` or `..`), or
when `/opt/godot-dotnet` exists and is not a directory holding the feature's root-owned marker. If
`/usr/local/bin/godot` is a regular file, the message SHALL name the `godot` feature as a likely source and say that the
two cannot be combined.

#### Scenario: Standard build already installed

- **WHEN** `/usr/local/bin/godot` is a regular file, as the `godot` feature installs it, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming `/usr/local/bin/godot` and the `godot`
  feature, and the file is left as it is

#### Scenario: Occupied destination

- **WHEN** `/usr/local/bin/godot` is anything other than a regular file or a symbolic link of the feature's form (for
  example a directory, or a link to another target or a relative one), or `/opt/godot-dotnet` is anything other than a
  directory holding the feature's root-owned marker, and the feature is installed
- **THEN** the install fails before downloading anything, with a message naming the path, and leaves it as it is

#### Scenario: Partial installation

- **WHEN** `/opt/godot-dotnet` holds the feature's marker and `/usr/local/bin/godot` is absent, or
  `/usr/local/bin/godot` is a symbolic link of the feature's form whose target does not exist while `/opt/godot-dotnet`
  is absent or holds the marker, and the feature is installed
- **THEN** the install succeeds as a first install would, and `godot --version` reports the requested version

### Requirement: No editor customizations of its own

The feature SHALL declare no editor customizations of its own: it SHALL NOT request the Godot Tools VS Code extension or
any other extension, and SHALL write no editor setting. That extension runs, on every activation, an executable the
opened workspace's own settings can choose, and a dev container window trusts every folder opened in it, so installing
it is left to the user's own configuration, where it is visible.

#### Scenario: Metadata without customizations

- **WHEN** a client reads the feature's metadata
- **THEN** it finds no `customizations` entry, so the feature itself requests no extension and sets no editor setting

### Requirement: Prerequisites

The feature SHALL install, from the image's configured package repositories and only when missing, the tools it needs to
download, verify, and extract the archive and the font configuration library the editor loads at start, and SHALL leave
them installed. It SHALL install no X11, Wayland, GL, EGL, Vulkan, ALSA, or PulseAudio library.

#### Scenario: Minimal image

- **WHEN** the feature is installed on an image listed in `test/godot-dotnet/compatibility.json` that lacks `curl`, CA
  certificates, or `unzip`
- **THEN** the install succeeds, and `curl`, the CA certificate bundle, and `unzip` are present afterwards

#### Scenario: No graphical session libraries

- **WHEN** the feature has been installed with default options on an image where none of `libX11.so.6`,
  `libwayland-client.so.0`, `libGL.so.1`, `libEGL.so.1`, `libvulkan.so.1`, `libasound.so.2`, and `libpulse.so.0` is
  known to the dynamic linker
- **THEN** none of them is known to the dynamic linker afterwards

### Requirement: No other configuration

The feature SHALL leave no Godot configuration, data, cache, or export template anywhere in the image, SHALL NOT create
the self-contained mode marker beside the executable, write any file under a user's home directory, edit shell startup
files, or set an environment variable, and SHALL NOT run a project or start the editor during the build.

#### Scenario: Nothing else configured after install

- **WHEN** the feature has been installed with default options
- **THEN** neither the remote user's nor root's home holds `.local/share/godot`, `.config/godot`, `.cache/godot`, or
  `.cache/fontconfig`
- **AND** the release directory under `/opt/godot-dotnet` holds neither `_sc_` nor `._sc_`
- **AND** no environment variable whose name starts with `GODOT` is set in the remote user's environment

### Requirement: Supported platforms

The feature SHALL support images and architectures in `test/godot-dotnet/compatibility.json` and reject unsupported
platforms before changes.

#### Scenario: Unsupported architecture

- **WHEN** the feature's install script runs on a machine whose architecture is neither x86_64 nor aarch64
- **THEN** the install fails with a message naming the architecture, and the script downloads and installs nothing

#### Scenario: Unsupported distribution

- **WHEN** the feature's install script runs on an image whose `/etc/os-release` is missing or names none of the
  supported families, such as Fedora
- **THEN** the install fails with a message naming the distribution, or saying that `/etc/os-release` is missing, and
  the script downloads and installs nothing

#### Scenario: musl-based image

- **WHEN** the feature's install script runs on an image that has bash and whose `/etc/os-release` identifies Alpine
- **THEN** the install fails with a message saying that upstream's builds need the GNU C library, and the script
  downloads and installs nothing

#### Scenario: Supported family without its package manager

- **WHEN** the feature's install script runs on an image whose `/etc/os-release` matches a supported family but which
  lacks `apt-get`
- **THEN** the install fails with a message naming the distribution and the missing package manager, and the script
  downloads and installs nothing

### Requirement: Godot .NET platform gate

The feature SHALL fail, before downloading or installing anything, with a message naming what is unsupported when the
machine architecture is neither x86_64 nor aarch64; when `/etc/os-release` is missing or identifies, by its `ID` or
`ID_LIKE`, a distribution outside the Debian and Ubuntu families, which are the ones its dotnet dependency supports; or
when the image lacks `apt-get`.

#### Scenario: Unsupported platform prerequisite

- **WHEN** the machine architecture is neither x86_64 nor aarch64, `/etc/os-release` is missing or identifies a
  distribution outside the supported families, or the image lacks `apt-get`
- **THEN** the install script fails before downloading or installing anything, with a message naming what is unsupported

### Requirement: Installing twice

A second install SHALL succeed, apply the later options, and preserve the earlier installation if the second install
fails before it switches `/usr/local/bin/godot`.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed, the second leaves `/opt/godot-dotnet` and `/usr/local/bin/godot` unchanged, and
  `godot --version` reports that version

#### Scenario: Different version the second time

- **WHEN** the feature is installed with `version` set to an explicit older release and then with a `version` that
  selects a newer release
- **THEN** both installs succeed, and `godot --version` reports the version the second install selected
- **AND** `/opt/godot-dotnet` holds the marker and exactly one release directory, the one `/usr/local/bin/godot` points
  into; `/opt` holds no other entry whose name starts with `godot-dotnet` or `.godot-dotnet`; and `/usr/local/bin` holds
  no entry other than `godot` whose name starts with `godot` or `.godot`

#### Scenario: Unreadable installed version

- **WHEN** the installed executable exits non-zero or prints no version ending in `.stable.mono.official.` followed by a
  commit hash, and the feature is installed
- **THEN** the install succeeds and replaces the release directory, and `godot --version` reports the requested version

#### Scenario: Failed second install

- **WHEN** a second install fails before it switches `/usr/local/bin/godot`, for example because verification fails
- **THEN** `godot --version` still reports the version of the first install, and `/opt/godot-dotnet` holds the marker
  and the first install's release directory and nothing else

### Requirement: Godot .NET replacement safety

When the installed editor reports the requested version as an official stable .NET build, a second install SHALL leave
`/opt/godot-dotnet` and `/usr/local/bin/godot` untouched and download no archive. Otherwise it SHALL install the release
in a new release directory, switch `/usr/local/bin/godot` to it in one step, and then remove every other entry of
`/opt/godot-dotnet` but the marker. An install that fails before the switch SHALL leave the earlier installation as it
was.

#### Scenario: Matching version already installed

- **WHEN** the feature is installed twice with the same `version`, or with two values that select the same version such
  as `4.6`, `4.6.0`, and `4.6-stable`
- **THEN** the second install leaves `/opt/godot-dotnet` and `/usr/local/bin/godot` unchanged and downloads no archive

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that `apt-get` fetched for the prerequisites it installs, so
that apt's package lists are empty after it installs any. No temporary directory, archive, or temporary link of the
install, and no release directory other than the one `/usr/local/bin/godot` points into, SHALL remain after an install,
whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in
  `test/godot-dotnet/compatibility.json`
- **THEN** apt's package lists hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** the temporary directory holds no directory of the install, `/opt/godot-dotnet` holds no release directory
  other than the one `/usr/local/bin/godot` points into, and `/usr/local/bin` holds no temporary link of the install
