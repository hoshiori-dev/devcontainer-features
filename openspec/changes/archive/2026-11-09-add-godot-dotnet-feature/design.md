# Design

## Context

See proposal.md - Why. The feature follows the `godot` feature, whose approval package was approved on pull request
#189, last at commit `1d69cbd`, and is not yet merged; "the `godot` design" below means
[that design at that commit](https://github.com/hoshiori-dev/devcontainer-features/blob/1d69cbd6249e4004543ac3e3dee745f88776fe6e/openspec/changes/add-godot-feature/design.md).
This feature shares its release, its `version` option, its checksum verification, its headless scope, and its rule of no
editor customizations; the facts and reasons this change relies on are restated here where they matter, so a later
change to that package does not change this one. This pull request merges after #189, so that the exclusion's other side
(below) is on `main` first. The managed tree with a marker follows `quarto` (archived change
`2026-10-21-add-quarto-feature`), and the dependency on a first-party feature follows `openspec` and its `dependsOn` on
`ghcr.io/devcontainers/features/node:2` (archived change `2026-10-05-add-openspec-feature`).

The interface was agreed with the maintainer in conversation: a separate feature `godot-dotnet` rather than a `flavor`
option of `godot`, with the command name `godot` and mutual exclusion with `godot` (whichever is installed second
fails); the platforms the official dotnet feature supports and no others; the .NET SDK through `dependsOn` on that
feature; and otherwise the scope of `godot` (stable releases only, its minimum, the same `version` forms, no export
templates, no editor customizations of its own, no offline NuGet source). `godot`'s minimum was `4.2` when that was
agreed; the maintainer raised it to `4.2.2` on #189 on 2026-11-09 (commit `1d69cbd`), for the `--import` fact below,
which holds for the .NET build too, so this feature follows. The maintainer first chose the dependency's defaults (`{}`)
and, after the .NET 11 finding below, `{"version": "lts"}`.

Upstream facts this change relies on, checked on 2026-11-06 against github.com (the releases of `godotengine/godot` and
`godotengine/godot-builds`, the scripts of `godotengine/godot-build-scripts`, and the sources of `godotengine/godot` at
`4.2-stable`, `4.7.2-stable`, and the commit `godot-builds` names for `4.8-beta2`), docs.godotengine.org,
learn.microsoft.com, the .NET release metadata, and the published dotnet feature, and on 2026-11-09 by building dev
containers that combine that feature with a prototype of this one:

- Release and tags (shared with `godot`). Stable releases are tagged `MAJOR.MINOR[.PATCH]-stable`, never with a zero
  patch; GitHub's latest-release link redirects (`302`) to the newest one (`4.7.2-stable`, 2026-08-18). The release is
  public before its assets are uploaded, and `SHA512-SUMS.txt` (`sha512sum` format, unsigned, one line per asset) is
  uploaded last. A download is one `302` from `github.com` to `release-assets.githubusercontent.com`, then `200`.
- Archives. Every stable release from `4.2-stable` to `4.7.2-stable` (16 releases) has
  `Godot_v<tag>_mono_linux_x86_64.zip` and `Godot_v<tag>_mono_linux_arm64.zip`, with an underscore before the
  architecture where the standard build has a dot; no 4.x release before `4.2` has the arm64 one. The checksum list
  holds exactly one entry for each and arrived between about 2 and 8 minutes after the Linux archives, and for `4.6.1`
  about two hours later. The archives are about 55 MB (`4.2`) to 114 MB (`4.5`); `4.7.2` is 108 MB.
- Layout. Each archive holds one top directory `Godot_v<tag>_mono_linux_<arch>/` with exactly two entries: the
  executable `Godot_v<tag>_mono_linux.<arch>` (mode 0755, a dot before the architecture) and `GodotSharp/`
  (`Api/Debug/`, `Api/Release/`, `Tools/`, `Tools/nupkgs/`), with no symbolic link, absolute path, or `..` component.
  Files are 0644, some third-party DLLs 0744, directories 0755; every entry carries a Unix owner field of 1001:1001. The
  content of `GodotSharp/` varies by release (41 files in `4.2`, 73 from `4.6`; `4.5-stable` also carries leftover
  pre-release packages in `Tools/nupkgs/`), so only its presence, not its listing, is the same in every release. The
  editor finds `GodotSharp/` beside its real executable, resolving symbolic links and whatever the executable is named.
- The executables link only glibc libraries, need glibc 2.28 like the standard build, and load .NET's `hostfxr` at run
  time. `--version` prints `<version>.stable.mono.official.<9-hex hash>` (for example
  `4.7.2.stable.mono.official.ed1daf0bf`), exits 0, needs no .NET and no display, and writes nothing under `HOME`.
- Without a .NET runtime every editor command (`--editor`, `--import`, `--build-solutions`) crashes with exit status
  132, even for a project without C#. The editor finds the runtime through `DOTNET_ROOT`,
  `/etc/dotnet/install_location`, `/usr/share/dotnet`, and last the `dotnet` on `PATH`; it hosts its own assembly, which
  targets `net6.0` (`4.2`, `4.3`), `net8.0` (`4.4` to `4.7.2`), or `net10.0` (`4.8-beta2`), with roll-forward to the
  newest installed major (release runtimes only); and it builds with the SDK whose major equals that runtime's, found
  through `dotnet --info`. Godot's docs ask for the latest stable SDK. SDK 10.0.403 built and ran a `4.2` project
  (`net6.0`), a `4.6.3` project, and a `4.7.2` project (`net8.0`) on runtime 10.0.14.
- .NET 11. With SDK 11.0.100-rc.3 installed and the editor hosted on its runtime (alone, or beside SDK 10 with
  `DOTNET_ROLL_FORWARD_TO_PRERELEASE=1` to stand in for the release), `4.7.2`'s `--build-solutions` failed with
  `MSB4236` ("The SDK 'Microsoft.NET.Sdk' specified could not be found"): that SDK's `dotnet --info` prints its base
  path without a trailing slash, and the editor joins `Sdks` to it without one. `dotnet build` on the same project
  succeeded. .NET 11 is scheduled for 2026-11-10, the day .NET 8 and 9 reach end of support; whether its release behaves
  the same was not observable on 2026-11-09. With the dependency at its defaults, the release would be the container's
  only runtime.
- C# projects. `--build-solutions --quit` builds the project's `.csproj` with `dotnet build` and exits 1 when the build
  fails; with no `.csproj` it exits 0 without building. On `4.2.2` (two runs on fresh projects), `4.6.3`, and `4.7.2` a
  successful build exited 0; on `4.2` it exited 0 in one run and 139 (a crash after the assembly was written) on a fresh
  project in another. Godot writes the `.csproj` only from its editor UI, so a project created headless supplies its
  own: `Sdk="Godot.NET.Sdk/<release>"` with the three-part release (`4.2.0` for `4.2`), and a `TargetFramework`, which
  `4.2`'s SDK package requires; the assembly name is the project's `config/name` unless `dotnet/project/assembly_name`
  sets it. A `project.godot` naming a main scene that does not exist makes the first build crash. The first build
  restores `Godot.NET.Sdk` and Godot's packages from nuget.org into `~/.nuget` (about 8 s and 93 MB), and, with an SDK
  newer than the project's target, the older reference pack; a cold build without network fails with `MSB4236`, a warm
  one succeeds. The bundled `Tools/nupkgs/` is never used as a source.
- `--import` first appears in `4.2.2` (`main/main.cpp` at each tag): `4.2` and `4.2.1` pass it to the project, which
  then runs without quitting, as a `4.2` run showed. There, `--headless --editor --quit` imports the project (its
  `.godot/imported/` exists afterwards) and exits 0. On `4.2.2` with SDK 10, every headless check this design names
  (running, `--import`, opening the editor, building and running C#, the language server) passed twice.
- The dotnet feature. `ghcr.io/devcontainers/features/dotnet:2` is version 2.5.0. Its `version` `lts` makes it run its
  vendored copy of Microsoft's `dotnet-install.sh` on the `LTS` channel, which installed SDK 10.0.403 on 2026-11-09
  (`{}` instead selects the first channel of `releases-index.json` whose support phase is `active`). It installs into
  `/usr/share/dotnet` with a `/usr/bin/dotnet` link, and with `apt-get` installs `wget`, CA certificates,
  `icu-devtools`, `jq`, and the runtime's libraries (not `curl` or `unzip` on `debian:12`), leaving apt's package lists
  empty; with its default `tabCompletions` it writes `dotnet` completions for bash, zsh, and fish, and it writes
  `/etc/profile.d/dotnet.sh` adding `$HOME/.dotnet/tools` to a login shell's `PATH`. Its metadata sets `DOTNET_ROOT`,
  appends it to `PATH`, sets `DOTNET_RUNNING_IN_CONTAINER` and `DOTNET_USE_POLLING_FILE_WATCHER`, requests
  `ms-dotnettools.csharp`, sets `github.copilot.chat.codeGeneration.instructions`, and installs after `common-utils`. It
  supports Debian and Ubuntu only: on `fedora:44` it exits 127 at `apt-get`. `dotnet-install.sh` checks only that a
  downloaded file's size matches; Microsoft publishes SHA-512 hashes for each SDK archive, which it does not read. Per
  the Dev Container feature-dependency rules, a consumer's own `dotnet:2` entry is the same feature only with the same
  options, so an entry at its defaults installs a second SDK.
- Combined builds. With the dev container CLI 0.89.0, `debian:12` (root) and
  `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (`vscode`), each with the dotnet feature and the prototype, built
  on amd64; the dotnet feature ran first, and `dotnet` resolved during this feature's install. As the remote user,
  `4.7.2` ran a project, imported it, opened and quit the editor, built and ran a C# project
  (`HELLO_FROM_CSHARP 10.0.14`), and served the language server on a port. The CLI installs each feature in its own
  image layer, so a second install finds the first install's directories in a lower overlay layer, where renaming a
  directory fails with "Invalid cross-device link" and `mv` falls back to copying entry by entry; a directory created in
  the current layer, and any symbolic link, renames in one step. A prototype that installed `4.6.3` and then `4.7.2` in
  two layers, each into a new directory and switching the link, left one release directory and a working `godot`.
- The C# extension (`ms-dotnettools.csharp`, from its `package.json` on `dotnet/vscode-csharp` main) activates in a
  workspace containing a `.csproj`, restores and loads its projects with MSBuild
  (`dotnet.projects.enableAutomaticRestore`, default `true`), and declares limited support for untrusted workspaces. Its
  `dotnet.server.path` has the scope `machine-overridable`, which VS Code's configuration registry describes as machine
  settings "that can also be configured in workspace or folder settings". A Dev Containers window trusts every folder
  opened in it (the `godot` design, Context). The Dev Containers documentation lets a user opt out of an extension that
  a feature requests by listing it with a leading `-` in their own `customizations.vscode.extensions`.
- Export templates for the .NET build are `Godot_v<tag>_mono_export_templates.tpz` (about 1.2 GB for `4.7.2`) in the
  same release and checksum list; their `version.txt` reads `<version>.stable.mono`, the directory under
  `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/` where the editor looks for them.
- The devcontainer CLI's duplicate test installs the feature first with the first `proposals` value that is not its
  default, then with the defaults; both declare the same dependency, so the SDK is installed once. The CLI orders
  features by dependency rounds, not by their order in `devcontainer.json`; `overrideFeatureInstallOrder` changes it.

## Goals / Non-Goals

**Goals:**

- `install.sh` is bash (`#!/usr/bin/env bash`, `set -euo pipefail`). It matches `version` against `latest` or
  `MAJOR.MINOR[.PATCH]` of decimal numbers with an optional `-stable` suffix, without leading zeros, before the value
  enters a URL, a file name, or a comparison, gives a pre-release suffix its own message, and drops a zero patch; it
  uses the tag read from the latest-release redirect unchanged once it is exactly a stable tag at or above the minimum.
  Every download goes through `curl` restricted to HTTPS for the request and every redirect, requests only the URLs in
  the URL inventory, and prints each final URL without its signed query string. Every check that needs no network (the
  option's form, the minimum, the architecture, the distribution, `apt-get`, and both paths) runs before a package is
  installed or anything is downloaded, and the checksum list is fetched before the archive. Checked by shellcheck, the
  `fail_installation` scenario, and reading each `curl` call against the inventory and one CI build log.
- `install.sh` reads the architecture from `uname -m` and runs `curl` and `apt-get` by name through the `PATH` it
  inherits; the `fail_installation` stubs rely on this. Checked by that scenario.
- The archive's listing is checked before extraction: every entry under the one expected top directory, which holds
  exactly the executable and the directory `GodotSharp/`; no symbolic link (a listing mode starting with `l`), no
  absolute path, and no `..` component. Only that top directory is extracted, into the install's temporary directory.
  Checked by the `fail_installation` scenario.
- Ownership of the two paths, decided before anything changes: `/opt/godot-dotnet` belongs to the feature when it is a
  directory, not a link, holding the regular file `.devcontainer-feature-godot-dotnet` owned by root; and
  `/usr/local/bin/godot` belongs to it when it is a symbolic link whose target, read literally with `readlink`, is
  `/opt/godot-dotnet/<name>/godot` for a single path component `<name>` other than `.` and `..`. Outcomes:

  | `/usr/local/bin/godot`                    | `/opt/godot-dotnet`                         | Outcome                                           |
  | ----------------------------------------- | ------------------------------------------- | ------------------------------------------------- |
  | absent, or the feature's link             | absent, or the feature's                    | install; skip when the version check below passes |
  | a regular file                            | any                                         | fail, naming the path and the `godot` feature     |
  | anything else (a directory, another link) | any                                         | fail, naming the path                             |
  | absent, or the feature's link             | anything but a directory holding the marker | fail, naming the path                             |

  The skip check runs `/usr/local/bin/godot --version` only when both paths belong to the feature and the link's target
  exists. Checked by `test.sh`, the duplicate test, and the `fail_installation` scenario.
- The installation: `/opt/godot-dotnet` (mode 0755) holds the marker (mode 0644, written when the directory is created
  and rewritten with the installed tag after each switch, for a reader) and one release directory `<tag>.XXXXXX`,
  holding the executable renamed to `godot` and `GodotSharp/`. The release directory is created with `mktemp -d` inside
  `/opt/godot-dotnet`, so it is new in the current layer, and set to mode 0755; its contents get owner root, no group or
  other write bit, and read permission for everyone (execute on directories and the executable) explicitly, whatever the
  archive records. Its executable runs once with `--version`, with `HOME` in the install's temporary directory and the
  `XDG_*_HOME` variables unset, before anything outside it changes; the output must be `<version>.stable.mono.official.`
  and a hexadecimal hash, as the skip check requires. Checked by `test.sh` and the `fail_installation` scenario.
- The switch is one rename of a temporary link `/usr/local/bin/.godot-dotnet-feature.XXXXXX` over
  `/usr/local/bin/godot`. Nothing outside the new release directory, the temporary link, the temporary directory
  `${TMPDIR:-/tmp}/godot-dotnet-feature.XXXXXX`, and (on a first install) `/opt/godot-dotnet` itself changes before it;
  after it, the marker is rewritten and every other entry of `/opt/godot-dotnet` is removed. One `trap` removes the
  temporary directory, an unswitched release directory, the temporary link, and an `/opt/godot-dotnet` that this run
  created when the run ends before the switch. So every failure the scenarios can cause, all of them before the switch,
  leaves the earlier installation as it was, which the `fail_installation` scenario checks after each failing run; the
  switch and the removal after it are checked by reading `install.sh` in review, since no stub can make a rename fail
  without a hook.
- `install.sh` does not run `dotnet`, does not check for it, and touches nothing the dotnet feature installed. Checked
  by reading `install.sh` in review.
- Package installs: `curl`, `ca-certificates`, and `unzip` only when missing, and `libfontconfig1` only when
  `libfontconfig.so.1` is not known to the dynamic linker, with `apt-get` only, then apt's package lists removed. In CI
  the dependency installs CA certificates first, so only the `curl`, `unzip`, and fontconfig branches run there (on
  `debian:12`), checked by `test.sh`; the CA-certificate branch is checked by reading `install.sh` in review.
- `test.sh` checks the "Nothing else configured after install" scenario first; then the layout (the link and its
  target's form, the marker, one release directory, root ownership and no group or other write bit anywhere under
  `/opt/godot-dotnet`), the "Minimal image" and "No graphical session libraries" scenarios, the dependency
  (`dotnet --list-sdks` lists an SDK under `DOTNET_ROOT`, which names the directory `dotnet` resolves into), apt's empty
  package lists, and no `godot-dotnet-feature.*` entry in the temporary directory or `.godot-dotnet-feature.*` in
  `/usr/local/bin`; then compares `godot --version` with the tag the latest-release link names at test time; and, as the
  remote user in projects it creates, runs a minimal project, imports it (asserting the exit status, the `.godot/`
  directory, and no fontconfig message), starts the language server on a free port and connects to it, and builds a
  minimal C# project with `--build-solutions` and runs it, asserting the assembly and the line its script prints. The
  `.csproj` takes the `Godot.NET.Sdk` version from `godot --version` (padded to three parts) and the target framework
  from the `"tfm"` of the release directory's `GodotSharp/Api/Release/GodotPlugins.runtimeconfig.json`, read with `sed`;
  the assembly name equals the project's `config/name`.
- The "Extension requested through the dependency" scenario and the `NOTES.md` editor example are checked once with
  `devcontainer read-configuration --include-merged-configuration` on a configuration that adds this feature and the
  example's lines: the merged extensions hold the Godot Tools extension and setting the user adds and the C# extension
  the dependency adds. The three metadata scenarios are checked by reading `devcontainer-feature.json` in review.
- Scenarios a successful container build cannot show run as the scenario `fail_installation` on `debian:12`, under
  testing.md, Running the installer: the CLI installs the feature with `version` `4.6`, and the script runs
  `_feature/install.sh` itself through an `installer.sh` helper. Requests go to a `curl` stub on `PATH` that records
  them and serves fixture releases the script builds (a top directory holding a shell-script stand-in for the executable
  that prints `<version>.stable.mono.official.<hash>`, and a `GodotSharp/` directory, zipped with `zip`, and a matching
  checksum list), built with `zip`, which the script installs from the image's repositories before it places any stub;
  `uname` and `apt-get` are stubbed the same way, and `/etc/os-release` is replaced or removed and restored. For the
  "lacks `apt-get`" case the script moves `/usr/bin/apt-get` aside and removes only the `apt-get` stub, restoring both
  in a `trap`. For the runs that must fail before any change, the script first removes `libfontconfig1` with `dpkg`, and
  asserts afterwards that no `curl` or `apt-get` call was recorded and the library is still absent; it restores the
  library before the runs that must succeed. It covers: `4.6`, `4.6.0`, and `4.6-stable` skipping without a request;
  each malformed and pre-release form the scenarios name and a version below the minimum; a release that does not exist;
  `latest` pointing to a malformed tag and to `3.6.3-stable`; a missing checksum list; a missing or duplicated entry; a
  digest mismatch; a release without an archive for the architecture; archives with an entry outside the top directory,
  a symbolic link, a `..` component, an extra entry in the top directory, no executable, no `GodotSharp/`, and
  `GodotSharp` as a file; an executable that exits non-zero and one that reports another version or the standard build;
  an unsupported architecture; `/etc/os-release` missing or naming Alpine, Arch Linux, or Fedora; `apt-get` missing; at
  `/usr/local/bin/godot` a regular file, a directory, a link with another target, and a broken link of another form; at
  `/opt/godot-dotnet` a directory without the marker, one whose marker is not owned by root, a link to a directory
  holding a marker, and a file; the two partial installations of the spec; and an unreadable installed version (a
  stand-in that exits 1, and one printing `4.6.stable.custom_build.<hash>`), replaced from a fixture release. Before and
  after every failing run it compares both paths, the marker, and the release directory's listing and inode, and asserts
  no residue in the temporary directory, `/opt/godot-dotnet`, `/opt`, or `/usr/local/bin`. `install.sh` carries no test
  hook.
- Manual checks, which the approval of this package accepts, each run once on amd64 with its result in the PR's
  Validation section: the version check on an image whose C library is too old (`ubuntu:18.04`, glibc 2.27, running
  `install.sh` directly with `VERSION=4.6.3`); and a dev container that adds both `godot` (from its pull request's
  branch until it is published) and `godot-dotnet` fails to build, with `godot` installed first by the CLI's default
  order and with `overrideFeatureInstallOrder` listing `ghcr.io/devcontainers/features/dotnet`, this feature, then
  `godot`, each failure naming `/usr/local/bin/godot`. A scenario cannot express either, because the image or the build
  itself is the subject (testing.md, Running the installer).

**Non-Goals:**

- Choosing the SDK version from this feature: options of a `dependsOn` entry are fixed metadata that no option of this
  feature can change. `NOTES.md` shows how a project adds another SDK with its own `dotnet:2` entry and selects it with
  `global.json`, and what a newer major does to the editor's builds.
- Making a C# project's first build work offline: no NuGet source or package cache is configured.
- Generating a C# project: Godot creates `.csproj` files only from its editor UI.
- Fedora and other distributions the dotnet feature does not support; Alpine and other musl images; distroless images;
  pre-releases and `godotengine/godot-builds`; releases before `4.2.2`, the 3.x branch, and the 32-bit builds; a
  graphical session; export templates.
- Verifying the SDK beyond what the dotnet feature does; authenticity of the release beyond what github.com's TLS gives.

## Options

The feature has one option, new in this change; the spec's Option requirement states it.

| Name      | Type     | Default    | Enum or proposals              | Meaning                                                                                                                  |
| --------- | -------- | ---------- | ------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `version` | `string` | `"latest"` | proposals `["latest","4.6.3"]` | The stable release to install: `latest`, or `MAJOR.MINOR[.PATCH]` at or above `4.2.2`, with an optional `-stable` suffix |

- **`version` default `latest`.** Only the newest patch of each branch receives fixes under upstream's release policy,
  so the newest stable release is what most users want; a project pins `version` to the release its `project.godot` and
  its `.csproj` (`Godot.NET.Sdk/<release>`) were made with. The second proposal, `4.6.3`, is the newest release of the
  previous branch, so the duplicate test's first install is replaced by the second. Rejected: the minimum `4.2.2` — an
  unsupported branch is a poor suggestion; the current release — it equals what `latest` resolves to, so the replace
  path would never run in CI.
- **Accepted forms.** `4.6.3-stable` is how upstream writes tags and archive names, so a value copied from a release
  page works; `4.6.0` means `4.6`, because upstream never writes a zero patch and a user may. `4.6` names the release
  `4.6-stable`, not the newest 4.6.x, so every value names one release. Rejected: a leading `v` and leading zeros —
  upstream writes neither, and accepting them would give one release several spellings.
- **Rejected shapes.** An `sdkVersion` option — the dependency's options cannot depend on it, and a second SDK install
  by this feature would compete with the dotnet feature in `/usr/share/dotnet`; a `nugetOffline` option — the
  maintainer's decision; a `channel` option or pre-release versions — stable only; an `exportTemplates` option — not in
  `1.0.0`; an install path or a second command name.

## Decisions

- **Archive from `godotengine/godot`'s GitHub release download URLs, integrity from the release's `SHA512-SUMS.txt`,
  fetched first and required.** The repository is where upstream publishes stable releases, and it serves the .NET
  archive and its checksum list for every accepted release; a missing list means the release is still being uploaded,
  and fetching it first makes such a build fail naming it instead of after a 100 MB download. Rejected, as in the
  `godot` design: `downloads.godotengine.org` (a redirector to a bucket upstream's control of is only inferred, with no
  checksum list), `godotengine/godot-builds` (the same stable files plus pre-releases), Flathub's
  `org.godotengine.GodotSharp`, distribution packages such as Arch Linux's `godot-mono`, and community CI images.
- **`latest` from the latest-release link, read without following it, validated as a stable tag at or above `4.2.2`.**
  The link is upstream's own pointer and needs no token; a tag below `4.2.2` fails rather than installing a 3.x release.
  Rejected: the releases API (60 requests an hour without a token) and `git ls-remote` (a tag precedes its assets).
- **Minimum `4.2.2`, as `godot`.** `4.2` is the first 4.x release with a .NET arm64 archive, so every accepted version
  installs on both architectures, and `4.2.2`, the last 4.2 release, is the first with `--import`, so every headless
  command the spec names works from it on; the archive layout and the `--version` form are the same from `4.2` to
  `4.7.2`. Rejected: `4.2` — agreed first, but `4.2` and `4.2.1` run the project instead of importing, and `4.2` once
  crashed after a C# build; a minimum different from `godot`'s — the two features install the same releases of one
  engine, and the maintainer asked for this one to follow `godot`'s scope.
- **.NET SDK through `dependsOn` on `ghcr.io/devcontainers/features/dotnet:2` with options `{"version": "lts"}`.** The
  editor is unusable without .NET, so a dependency the CLI installs first makes the feature work as soon as it is added;
  the dotnet feature is the Dev Containers project's own. The maintainer first chose `{}`, its defaults, which Godot's
  docs' "latest stable SDK" matches and which equals a consumer's own entry at its defaults; then, because the `4.7.2`
  editor failed to build C# when hosted on .NET 11 RC3 and `{}` would move to .NET 11 on its release, chose `lts`: 10.0
  until the next LTS (.NET 12, planned for November 2027), which builds every accepted release's projects. Accepted, and
  stated in the spec: the SDK is checked only by size; the dependency adds its environment, completions, packages, and
  editor customizations; and a newer major a consumer adds beside it becomes the one the editor builds with. Rejected:
  `{}` — the .NET 11 finding; `"10.0"` — reproducible, but it needs a feature release when 10.0 reaches end of support
  (2028-11), where `lts` moves on with upstream; `installsAfter` with a build failure when `dotnet` is missing, or with
  documentation only — every user would add the dependency by hand, and the documentation-only form crashes at run time;
  downloading the SDK in this feature from `builds.dotnet.microsoft.com` and verifying its published SHA-512 — it would
  duplicate the dotnet feature, compete with it in `/usr/share/dotnet`, and still need the runtime's libraries;
  Microsoft's APT repository — Debian only, no Ubuntu 24.04, and on arm64 only SDK 10; the distributions' packages —
  none in Debian 12, and Ubuntu's `1xx` SDKs install elsewhere.
- **Debian and Ubuntu only.** The dependency fails on any other distribution before this feature runs, so this feature's
  own platform gate matches it and gives a clear message to a direct run of `install.sh`.
- **A release directory per install under `/opt/godot-dotnet`, the executable renamed to `godot`, and
  `/usr/local/bin/godot` a link switched in one rename.** `GodotSharp/` must sit beside the real executable, so a single
  file in `/usr/local/bin` is not enough; the link keeps the command name the maintainer chose and the one the Godot
  Tools extension runs by default. The CLI installs a second install in a new image layer, where the earlier directories
  cannot be renamed in one step (Context), so the new release goes into a new directory and only the link, which renames
  in one step, changes; the earlier release stays usable until the switch and is removed after it. The fixed name
  `godot` keeps the link's form the same for every release. Rejected: one fixed tree `/opt/godot-dotnet` replaced by
  renaming it aside — on a second layer the rename becomes a copy that a failure can leave split between two paths;
  `GodotSharp/` in `/usr/local/bin`, as a community CI image does — a directory of assemblies among commands; release
  directories named by the tag alone — reinstalling the same release after a failed check would need to rename over a
  directory in a lower layer.
- **A marker file claims the tree; anything else at either path fails the build.** As `quarto` does: a tree or link the
  feature did not create is left alone, with a message, rather than replaced or reused. The marker records the tag for a
  reader; the skip check relies on `--version`.
- **Mutual exclusion with `godot` through `/usr/local/bin/godot`.** The `godot` package at `1d69cbd` fails when that
  path "exists but is not a regular file", and its implementation, not yet pushed, tests for a link first, so only this
  feature's side needs a rule: a regular file there fails with a message naming the `godot` feature. Rejected: a
  `flavor` option on `godot` — the maintainer's decision; a second name such as `godot-mono`, as Homebrew, Scoop, and
  Arch Linux use — the maintainer chose `godot`; replacing the other feature's command — a configured feature would
  silently change its build. No global scenario tests the pair: the build failure is the subject (Goals, manual checks),
  and that manual check is what guards the other side until `godot`'s own tests cover a link.
- **No check for `dotnet` at build time.** The dependency installs the SDK before this feature, and a consumer cannot
  remove a `dependsOn` entry; this feature needs no .NET to install.
- **Run the extracted executable before activating it.** A C library too old for the build, a damaged extraction, or an
  archive holding another version or the standard build is caught before anything is switched.
- **The fontconfig library as the one runtime package.** The build looks it up on every start and prints errors without
  it; X11, GL, and audio libraries are not loaded headless, and a user who forwards a display chooses them.
- **No editor customizations of its own.** As in the `godot` design: the Godot Tools extension runs an executable that
  the opened workspace's settings can choose, so `NOTES.md` shows the lines a user adds to their own configuration. The
  C# extension that the dependency requests is the same class of risk; this feature cannot remove another feature's
  request, and the maintainer chose the dependency knowing it. Rejected: declaring `-ms-dotnettools.csharp` in this
  feature's own metadata — it would take the extension from every C# user, and whether the Dev Containers extension
  honours an opt-out from a feature's metadata was not checked.
- **Scenarios.** `test_version_explicit` installs `4.6.3` on `debian:12` and also builds and runs the minimal C#
  project, so a release other than the latest restores its own `Godot.NET.Sdk`; `test_version_tag_form` installs
  `4.6.3-stable` on the Ubuntu base as `vscode`; `test_version_two_part` installs `4.6` on the Ubuntu base as `vscode`,
  since `fail_installation` already builds `debian:12` with `4.6`; each asserts the version and that `godot` runs a
  project headless. `fail_installation` on `debian:12` covers the zero-patch form and the rest (Goals).
  `scenarioArchitectures` selects amd64 and arm64.

## Security review

- **Downloads by this feature:** the archive and checksum list of one release and architecture, and one header-only
  request for `latest`, all on github.com over HTTPS with one redirect to GitHub's asset host (URL inventory). Nothing
  is piped to a shell.
- **Verification:** SHA-512 of the archive against its exact entry in the checksum list; the checksum list and the
  latest-release link rely on TLS alone (spec, "Godot .NET release metadata trust"). This detects corruption and a
  mismatched file, not a compromised release pipeline or a release replaced after publication; upstream signs nothing
  for Linux, so there is no key to pin.
- **Dependency:** `ghcr.io/devcontainers/features/dotnet:2`, resolved by the CLI from GHCR at build time and pinned only
  by a consumer's lockfile. It runs as root at build time, downloads the SDK checked by size only, and adds what the
  spec lists (".NET SDK dependency trust", "What the dotnet dependency adds"). Its C# extension (spec, "C# extension
  trust") is the same class of risk for which the `godot` design leaves Godot Tools to the user: a C# workspace opened
  in the container makes it run build logic the projects define and a server path the workspace's settings may choose,
  from metadata the user does not read. `NOTES.md` names it and shows the opt-out.
- **Archive handling:** the listing is checked before extraction (Goals), so no entry lands outside the temporary
  directory and no link is followed; ownership and modes are set explicitly.
- **Code run at build time:** the verified executable once with `--version`, and the installed one once for the skip
  check, both as root with `HOME` in the temporary directory; the installed one runs only when the feature owns both
  paths. The second runs what an earlier layer put there, as the `godot` and `act` designs accept.
- **Metadata:** `dependsOn` as above; no `customizations`, `installsAfter`, `containerEnv`, `mounts`, `capAdd`,
  `privileged`, `securityOpt`, `init`, `entrypoint`, or lifecycle command of its own.
- **Files written:** `/opt/godot-dotnet`, `/usr/local/bin/godot`, and the prerequisites' packages; nothing under a home
  directory.
- **Options:** `version`, validated before use; no URL, path, credential, or free-form option.
- **Idempotency and failure behavior:** the spec's "Installing twice", "Godot .NET replacement safety", and failure
  scenarios, checked as described under Goals; every failure exits non-zero, which fails the image build.

## Supported images

The planned `test/godot-dotnet/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                                    |
| -------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; a non-root user; the dotnet feature's own CI covers it   |
| `debian:12`                                        | Minimal `apt-get` image; the dotnet feature's own CI covers it; the failure scenario's |

`fedora:44`, in the `godot` list, is left out because the dependency fails on it. Only amd64 was run during research;
the arm64 archives were inspected (AArch64, glibc only, glibc 2.28), and CI runs both features on arm64 runners.

## URL inventory

Every URL this feature's scripts access, all at build time by `install.sh`; nothing at container start. `<tag>` and
`<arch>` are as in the spec. The dependency is resolved by the CLI, not by `install.sh`, and fetches what its own source
names.

| URL                                                                                                  | Purpose                                                   | When                                                                        | Verification                                                  | Evidence                                                                                           |
| ---------------------------------------------------------------------------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `https://github.com/godotengine/godot/releases/latest`                                               | Resolve `latest` from the `Location` header, not followed | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` | TLS; the tag must pass the version validation and minimum     | 2026-11-06: `302` to `.../releases/tag/4.7.2-stable`                                               |
| `https://github.com/godotengine/godot/releases/download/<tag>/Godot_v<tag>_mono_linux_<arch>.zip`    | Release archive                                           | Build                                                                       | TLS; SHA-512 against its exact entry (integrity only)         | 2026-11-06: 16 releases, both architectures; one `302`, then `200`; digests equal                  |
| `https://github.com/godotengine/godot/releases/download/<tag>/SHA512-SUMS.txt`                       | Checksum list, fetched before the archive                 | Build                                                                       | TLS only; unsigned, same origin as the archive                | 2026-11-06: all 16 lists in `sha512sum` format, one entry per .NET Linux archive                   |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<path>?<signed query>` | Where GitHub serves release assets; reached by redirect   | Build                                                                       | As the row that redirected to it                              | 2026-11-06: final host for every download, one redirect hop                                        |
| `ghcr.io/devcontainers/features/dotnet:2` (OCI)                                                      | `dependsOn`: the .NET SDK                                 | Build, resolved by the dev container CLI                                    | OCI manifest digest; pinned by the consumer's lockfile if any | 2026-11-09: version 2.5.0; with `lts` it installed SDK 10.0.403 from `builds.dotnet.microsoft.com` |

At run time the editor and the SDK make the requests their own settings allow, such as nuget.org on a C# project's first
build; the feature itself requests nothing.

## Risks / Trade-offs

- [The LTS channel moves to .NET 12 in November 2027, or a consumer adds a newer major beside it] → The editor builds
  with the newest major; if that major behaves like .NET 11 RC3 for the installed release, the editor's C# builds fail
  while `dotnet build` works. `NOTES.md` says so; a later change chooses other options, which a maintainer decides.
- [The SDK is verified by size only] → Accepted with the dependency (spec).
- [A C# project's first build needs nuget.org, and right after a release its `Godot.NET.Sdk` may not be there yet] →
  `NOTES.md` says that the first build needs nuget.org; a CI run in that window fails the C# check, and a re-run passes.
- [The C# extension the dependency requests runs code a C# workspace defines] → Stated in the spec as accepted with the
  dependency; `NOTES.md` names it and shows how to opt out with `-ms-dotnettools.csharp`.
- [Adding both `godot` and `godot-dotnet` fails the build] → The intended exclusion; both messages name the path, and
  this feature's names the `godot` feature.
- [Upstream switches the .NET build to the single-executable `_dotnet_linux.<arch>.zip` its build scripts can already
  produce] → The archive name differs, so the install fails naming the archive; a feature change follows.

- [GitHub's latest-release link briefly points to a newly published release of an older branch, or a release is public
  before its assets] → A `latest` build in that window installs that release, or fails naming the checksum list or the
  tag; a rebuild later passes. Users who need a fixed release pin `version`.
- [The checksum list is unsigned and served from the same origin, and releases are mutable] → The spec states integrity
  only.
- [The installed release differs from the project's] → An editor run imports the project with the installed release and
  may write files a newer release adds; `NOTES.md` tells users to pin `version` to their project's release.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because `apt-get`
  matches and the version check guards the C library; only listed images are supported.

## Open Questions

None.
