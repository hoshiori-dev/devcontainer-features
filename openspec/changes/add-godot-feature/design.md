# Design

## Context

See proposal.md - Why. The feature follows the `act` feature (archived change `2026-10-23-add-act-feature`), itself
derived from `gitleaks`: one executable from upstream's GitHub release archive, verified against the release's checksum
list, installed atomically to `/usr/local/bin`, with `latest` read from the latest-release redirect. Its platform bounds
follow `quarto` (archived change `2026-10-21-add-quarto-feature`): a glibc build, so Debian, Ubuntu, and Fedora without
Alpine. What differs is written below; what is the same is named, not repeated.

The interface was agreed with the maintainer in conversation before this change: the standard build only, with the .NET
build as a separate feature; no export templates in `1.0.0`; stable releases only. The maintainer first chose to request
the Godot Tools extension and, after review found the activation behavior described below, chose to leave it out. Issue
#188 records the resulting scope.

Upstream facts this change relies on, checked on 2026-11-06 against godotengine.org, the Godot Foundation's site,
github.com (the releases of `godotengine/godot` and `godotengine/godot-builds`, their release pages and asset lists, the
scripts of `godotengine/godot-build-scripts`, and the sources of `godotengine/godot` at `4.2-stable` and
`4.7.2-stable`), and by running the `4.2` and `4.7.2` x86_64 builds, each verified against its checksum list, in
containers of the planned images:

- Provenance. `github.com/godotengine` carries GitHub's verified-domain mark for `godotengine.org`, whose registrant is
  Stichting Godot (the Godot Foundation, which holds the Godot trademarks; Godot announced its move to it from the
  Software Freedom Conservancy in 2022). The website links to the organization, and the repository's README names the
  website as the home of the official binaries. Stable releases on `godotengine/godot` are published by a Foundation
  board member's account through `publish-release.sh`; `godotengine/godot-builds`, published by the project's build bot,
  holds the same stable releases and every pre-release.
- The website's download buttons go through `downloads.godotengine.org`, which redirects to an object storage bucket
  under Hetzner's shared domain when the file is there and to `godot-builds` otherwise; the redirector serves no
  checksum list, and its routing is not documented.
- The latest release is `4.7.2-stable` (2026-08-18); GitHub's latest-release link redirects (`302`) to
  `https://github.com/godotengine/godot/releases/tag/4.7.2-stable`. `godotengine/godot` holds 73 releases, every one a
  stable tag `MAJOR.MINOR[.PATCH]-stable` except the historical `2.0.4.1-stable`, never with a zero patch (`4.3-stable`
  exists; `4.3.0-stable` does not). Releases of older branches (3.6.x, 4.5.2) are published after newer ones, and
  upstream's script passes no `--latest` flag; every archived snapshot taken after such a release showed the newest 4.x
  as latest, but whether the link briefly pointed at the older release could not be established.
- From `4.2-stable` (2023-11-30) to `4.7.2-stable` every release has `Godot_v<tag>_linux.x86_64.zip` and
  `Godot_v<tag>_linux.arm64.zip`; no 4.x release before `4.2` has an arm64 archive (3.6.x, published later, does). Each
  archive holds exactly one entry, the executable `Godot_v<tag>_linux.<arch>` (mode 0755) at its root; the 4.7.2
  archives are about 78 MB.
- Every release from `3.1.2` on carries `SHA512-SUMS.txt` in `sha512sum` format (`<128 hex>  <file name>`), listing
  every asset but itself. Upstream's script publishes the release before uploading any asset: the Linux archives follow
  minutes later, and `SHA512-SUMS.txt` comes last, about 3 to 19 minutes after publication. No release carries a
  signature or an attestation, and releases are not immutable. GitHub's asset digest exists only for assets uploaded
  after 2025-06-03.
- A release download is one `302` from `github.com` to `release-assets.githubusercontent.com`, then `200`.
- The executable is dynamically linked against glibc only (`libc`, `libm`, `libdl`, `libpthread`, `librt`); it loads
  X11, Wayland, GL, Vulkan, audio, fontconfig, D-Bus, and udev libraries at run time when present. `4.2` to `4.7.2` need
  glibc 2.28, and `4.8-beta2` needs 2.34. It does not run on Alpine, with or without `gcompat`.
- `godot --version` prints `<version>.stable.official.<9-hex hash>` (for example `4.7.2.stable.official.ed1daf0bf` and
  `4.2.stable.official.46dc27791`), exits 0, needs no display, and writes nothing under `HOME`. On every planned image
  it runs with no added package; without the fontconfig library each run prints the line
  `libfontconfig.so.1: cannot open shared object file`, and editor commands print `Unable to load fontconfig` about ten
  times, exiting 0 all the same. None of the planned images ships that library.
- `--headless --path <project> --quit` writes only `~/.local/share/godot/app_userdata/<name>/logs/`; `--import` and the
  other editor commands also write `~/.config/godot/` and `~/.cache/godot/`, and with fontconfig present
  `~/.cache/fontconfig/`. Absolute `XDG_*_HOME` values are honoured. A file `_sc_` or `._sc_` beside the executable
  switches the editor to a self-contained mode that writes beside the executable.
- `--lsp-port` first appears in `4.2-stable`. The Godot Tools extension (`geequlim.godot-tools`, source in
  `godotengine/godot-vscode-plugin`, on the VS Code Marketplace and Open VSX; checked at `2.7.1`) activates in any
  workspace containing `project.godot`. It reads the project's major version only from `config/features` in
  `project.godot` (a project without a `"4.N"` entry counts as Godot 3) and uses `godotTools.editorPath.godot4` (default
  `godot`) or `godotTools.editorPath.godot3` (default `godot3`) accordingly. On every activation it runs that path with
  `--version` as a shell command string, retrying a path it cannot run relative to the workspace folder; the settings
  are window-scoped, so a workspace's own settings can change them. With its default `godotTools.lsp.headless` (`false`)
  it then only connects to an editor a user has open; set to `true`, it runs
  `godot --path <project> --editor --headless --no-window --lsp-port <port>` itself as soon as it activates. An editor
  opened on a project runs the project's enabled editor plugins and `@tool` scripts. The extension compares only major
  versions: it refuses when the executable's major version differs from the project's, or, for a Godot 4 project, when
  the executable is older than `4.2`. Its manifest declares no Workspace Trust capability, so VS Code disables it in
  Restricted Mode, but a Dev Containers window treats every folder opened in it as trusted (checked in the Dev
  Containers extension `0.471.0`), so inside the container Restricted Mode never applies.
- Export templates for a release are one `.tpz` of about 1.28 GB, and the editor looks for them only in
  `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/<version>.stable/` of the user running it.
- `debian:12` lacks `curl`, CA certificates, and `unzip`; `fedora:44` lacks `unzip`; the Ubuntu dev container base has
  all three. Every planned image has `sha512sum`.
- The devcontainer CLI's duplicate test installs a string option first with the first `proposals` value that is not its
  default, then with the defaults.

## Goals / Non-Goals

**Goals:**

- `install.sh` is bash (`#!/usr/bin/env bash`, `set -euo pipefail`): no planned image lacks bash, and Alpine is out of
  scope. On a stock Alpine image, which has no bash, the shell refuses the script before it runs; the musl message of
  the spec is for an Alpine image that has bash. Checked by shellcheck in `just check`.
- Every download goes through `curl` restricted to HTTPS for the request and every redirect, requests only the URLs in
  the URL inventory below, and prints each final URL without its signed query string, as in the `act` design. Checked by
  reviewing each `curl` call against the inventory and one CI build log.
- The `version` value is matched against `latest` or `MAJOR.MINOR[.PATCH]` of decimal numbers with an optional `-stable`
  suffix, each number without leading zeros, before it enters a URL, a file name, or a comparison; a pre-release suffix
  gets its own message; a zero patch is dropped. The tag read from the latest-release redirect must be exactly a stable
  tag as upstream writes it (no zero patch) at or above the minimum, and is used unchanged. Checked by the
  `fail_installation` scenario.
- Every check that needs no network — the option's form, the minimum version, the architecture, the distribution, its
  package manager, and the target path being absent or a regular file — runs before any package is installed or anything
  is downloaded. Checked by the `fail_installation` scenario, whose `curl` and `apt-get` stubs record every call.
- `install.sh` reads the machine architecture from `uname -m`, runs `curl` and the package manager by name through the
  `PATH` it inherits, and checks the extracted executable only by running it with `--version`; the `fail_installation`
  stubs rely on this. Checked by that scenario.
- The checksum list is downloaded before the archive, so a build in the minutes while upstream uploads a release fails
  naming the checksum list. Checked by reading `install.sh` in review.
- The archive is listed before extraction and must hold exactly the one expected entry; only that entry is extracted.
  The extracted executable runs once with `--version`, with `HOME` set to the install's temporary directory and the
  `XDG_*_HOME` variables unset, before it is renamed into place; its output must be `<version>.stable.official.`
  followed by a hexadecimal hash, as the skip check requires. Checked by the `fail_installation` scenario and, for the
  isolation, by the "Nothing else configured after install" scenario.
- The skip check runs the installed `/usr/local/bin/godot --version` the same way and skips only when it prints
  `<version>.stable.official.` followed by a hexadecimal hash; any other result replaces the file. Checked by the
  duplicate test and the `fail_installation` scenario.
- Package installs (`curl`, `ca-certificates`, and `unzip` only when missing; `libfontconfig1` on Debian and Ubuntu,
  `fontconfig` on Fedora, only when `libfontconfig.so.1` is not already known to the dynamic linker), the cache cleanup,
  the checksum selection of exactly one entry, the temporary directory and staged executable under one `trap`, and the
  atomic rename: as in the `act` design, checked the same way; the directories are
  `${TMPDIR:-/tmp}/godot-feature.XXXXXX` and `/usr/local/bin/.godot-feature.XXXXXX`.
- `test.sh` checks the "Nothing else configured after install" scenario first, then the "Minimal image" and "No
  graphical session libraries" scenarios (`curl`, the CA bundle, and `unzip` present; none of the named libraries in
  `ldconfig -p`; no `dotnet`), then compares `godot --version` with the tag the latest-release link names at test time,
  and, as the remote user in a minimal project it creates, runs the project, imports it (asserting the exit status, the
  `.godot/` directory, and no fontconfig message), and starts the language server on a free port, asserting that a TCP
  connection to it succeeds before stopping it. Checked by reading `test.sh` in review.
- Scenarios a successful container build cannot show run in CI as the scenario `fail_installation` on `debian:12`, under
  testing.md, Running the installer: the CLI installs the feature with `version` `4.6`, and the script runs
  `_feature/install.sh` itself through the `installer.sh` helper. Requests go to a `curl` stub on `PATH`
  (`fixture_curl.sh`) that records them and serves fixture releases the script builds (a shell-script stand-in for the
  executable, zipped with `zip`, which the script installs, and a matching checksum list); `uname` is stubbed the same
  way, and `/etc/os-release` is replaced or removed and restored. For the runs that must fail before any change, the
  script first removes `libfontconfig1` with `dpkg` and puts on `PATH` an `apt-get` stub that records each call and
  exits 1, and after each such run it asserts that no `curl` or `apt-get` call was recorded and that
  `libfontconfig.so.1` is still absent; it restores the library before the runs that must succeed. The script covers:
  `4.6`, `4.6.0`, and `4.6-stable` skipping without a request (inode and modification time unchanged); each malformed
  and pre-release form the scenarios name and a version below the minimum failing with no request; a release that does
  not exist; `latest` pointing to a malformed tag and to `3.6.3-stable`; a missing checksum list; a missing or
  duplicated entry; a digest mismatch; a release without an archive for the architecture; an archive with an extra entry
  and one whose only entry has another name; an executable that exits non-zero and one that reports another version; an
  unsupported architecture; `/etc/os-release` missing or naming Alpine, Arch Linux, or Fedora on an image without `dnf`;
  a directory at the target; and an unreadable installed version, both a stub that exits 1 and one that exits 0 printing
  `4.6.stable.custom_build.<hash>`, each replaced from a fixture release. After every failing run it asserts that
  `/usr/local/bin/godot` is unchanged and that no temporary directory or staged file remains. `install.sh` itself
  carries no test hook.
- Checks a scenario cannot express (testing.md, Running the installer), which the approval of this package accepts as
  manual checks, each run once on amd64 with its result in the PR's Validation section: a real image whose C library is
  too old (an Ubuntu 18.04 image, glibc 2.27, expecting the version-check failure); and the `NOTES.md` editor example.
  For the latter, VS Code with the Dev Containers extension opens a folder holding a minimal project whose
  `project.godot` carries `config/features=PackedStringArray("<installed MAJOR.MINOR>")`, as Godot's editor writes it,
  and whose own `devcontainer.json` adds this feature and the `NOTES.md` snippet (the extension and
  `godotTools.lsp.headless`): the extension reports a connected headless language server and offers completion in a
  `.gd` file. The "Metadata without customizations" scenario is checked by reading `devcontainer-feature.json` in
  review.

**Non-Goals:**

- The .NET build: a separate feature, by the maintainer's decision, with its own issue and change.
- Export templates: left out of `1.0.0` by the maintainer's decision; `NOTES.md` shows how to install them from the same
  release and verify them against its checksum list. A later MINOR change may add an option.
- Pre-releases (`dev`, `alpha`, `beta`, `rc`) and `godotengine/godot-builds`.
- Releases before `4.2`, the 3.x branch, and the x86_32 and arm32 builds.
- A graphical session: no X11, Wayland, GL, Vulkan, or audio package, and no check that the editor's window opens.
  `NOTES.md` says what a user who forwards a display has to add.
- Alpine and other musl images, distroless images, and images of a supported family that lack its package manager; the
  feature fails clearly on them.
- Authenticity of the release beyond what github.com's TLS gives.

## Options

The feature has one option, new in this change; the spec's Option requirement states it.

| Name      | Type     | Default    | Enum or proposals              | Meaning                                                                                                                |
| --------- | -------- | ---------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","4.6.3"]` | The stable release to install: `latest`, or `MAJOR.MINOR[.PATCH]` at or above `4.2`, with an optional `-stable` suffix |

- **`version` default `latest`.** Only the newest patch of each branch receives fixes under upstream's release policy,
  so the newest stable release is what most users want; a project pins `version` to the release its `project.godot` was
  made with, since any editor run, including one an editor extension starts, imports the project with the installed
  release. The second proposal, `4.6.3`, is the newest release of the previous branch, which still receives fixes, and
  older than `latest`, so the duplicate test's first install is replaced by the second. Rejected: the minimum `4.2` — an
  unsupported branch is a poor suggestion in the generated README; the current release — it equals what `latest`
  resolves to, so the replace path would never run in CI.
- **Accepted forms.** `4.6.3-stable` is how upstream writes tags and archive names, so a value copied from a release
  page works; `4.6.0` means `4.6`, because upstream never writes a zero patch and a user may. `4.6` names the release
  `4.6-stable`, not the newest 4.6.x: every two-part value is an exact release upstream published, and reading it as a
  range would make it mean two things. A tag read from the latest-release link is not normalized: it must already be in
  upstream's form, so the feature never fetches a tag other than the one the link named. Rejected: a leading `v` —
  upstream writes no `v` in tags or versions, only after `Godot_` in file names; leading zeros such as `4.06` — upstream
  writes none, and accepting them would give one release several spellings.
- **Rejected shapes.** A `flavor` option for the .NET build — a separate feature, by the maintainer's decision; an
  `exportTemplates` option — left out of `1.0.0`; a `channel` option or pre-release versions — stable only; an install
  path, or a second command name such as `godot4`; a boolean that requests the editor extension — a Feature's
  `customizations` are static metadata that no option can switch, and the extension belongs in the user's own
  configuration, where it is visible (Decisions).

## Decisions

- **Archive from `godotengine/godot`'s GitHub release download URLs, integrity from the release's `SHA512-SUMS.txt`.**
  As in the `act` design, with SHA-512 and the archive names above. The repository is where upstream's script publishes
  stable releases, and it serves the archive and its checksum list for every accepted release. Rejected:
  `downloads.godotengine.org` — the website's buttons use it, but it redirects to a bucket on Hetzner's shared domain
  that upstream's control of is only inferred, its routing is undocumented, and it serves no checksum list;
  `godotengine/godot-builds` — the same stable files, plus the pre-releases this feature does not install, so it adds a
  second source without adding a release; Flathub, the snaps, and distribution packages — community builds, often behind
  upstream; Steam, the Epic Games Store, and itch.io — upstream-operated, but they need an account and a client;
  community CI images and setup actions — the ones examined download the same archives without verifying them.
- **`latest` from the latest-release link, read without following it, validated as a stable tag at or above `4.2`.** As
  in the `act` design. A tag of an older branch below `4.2` (3.x) fails the install; one at or above it is installed.
  The 3.x branch's archives are named differently (`_x11.64.zip`), and its 3.6.x arm64 archive shares the 4.x name, so
  the minimum, not the archive name, keeps a 3.x tag out. Rejected: the highest version among `git ls-remote` tags — it
  needs `git` in the image, and a tag is pushed before its release has assets, so builds would fail more often; the
  releases API — rate-limited to 60 requests an hour per address without a token;
  `https://godotengine.org/versions.json` — a data file of the website with no documented contract and no checksum.
- **Minimum version `4.2`.** The first 4.x release with an arm64 archive, so every accepted version installs on both
  architectures; the archive names, layout, checksum list, and `--version` output are the same from there to `4.7.2`;
  and `--lsp-port`, which a headless language server needs, first appears in it. Rejected: `4.0` with an amd64-only
  range — a version that installs on one architecture and fails on the other is a trap; a higher minimum — nothing in
  the tested range differs.
- **Fail when the checksum list is missing; fetch it first.** Upstream publishes one for every accepted release, so a
  missing list means the release is still being uploaded or something is wrong; feature-authoring.md requires the
  failure. Fetching it before the archive means a build during an upload fails naming the list, which is uploaded last,
  instead of downloading an 80 MB archive first. A rebuild a few minutes later passes.
- **Run the extracted executable before activating it.** A glibc too old for the build, a damaged extraction, or an
  archive holding another version is caught before anything is replaced, and the earlier `godot` stays. The run uses
  `--version`, which needs no display and, with `HOME` in the temporary directory, writes nothing anywhere else.
- **`/usr/local/bin/godot`, one file, replaced atomically.** The docs' own suggestion and the name the upstream desktop
  file and the Godot Tools extension's default use. The archive holds one executable and nothing beside it to keep, so
  the tree and symlink of `quarto` would only add a second path. Rejected: `/opt/godot/<version>` with a link — several
  versions side by side are not asked for and leave old releases behind; a `godot4` name — no upstream source uses it.
- **The fontconfig library as the one runtime package.** The build looks it up on every start and prints errors without
  it, which every headless editor command, including a language server an editor extension starts, then shows; the
  package is small and in every planned image's repositories. Rejected: leaving it out — the errors look like a broken
  install; adding X11, GL, or audio libraries — headless use does not load them, and a user who forwards a display
  chooses those.
- **No editor customizations; the Godot Tools extension left to the user.** The extension is the one upstream's
  organization maintains, and for a Godot 4 project its default editor path `godot` resolves to the installed
  executable. But once installed it runs, on every activation, a shell command built from an editor path that the opened
  workspace's own settings can set, or for a project it reads as Godot 3, a `godot3` file in the workspace; and a Dev
  Containers window trusts every folder opened in it (Context). Requesting it from the feature would let any Godot
  project later opened in the container choose a command the extension runs, from metadata the user does not read
  (feature-authoring.md, Developer trust and readability). `NOTES.md` instead shows the lines a user adds to their own
  `devcontainer.json` (the extension, and `godotTools.lsp.headless` for a language server without a display) and says
  what the extension then runs, so the choice is visible where it is made. Rejected: requesting the extension and
  stating the risk — the maintainer's decision, for the reason above; requesting it with `godotTools.lsp.headless` set
  to `true` — that also starts the Godot editor, running the project's editor plugins and `@tool` scripts, as soon as a
  workspace opens; requesting it with absolute editor paths — a workspace setting still overrides them.
- **Scenarios.** `test_version_explicit` installs `4.6.3` on `debian:12`, `test_version_tag_form` installs
  `4.6.3-stable` on the Ubuntu base as `vscode`, and `test_version_two_part` installs `4.6` on `fedora:44`; each asserts
  the version and that `godot` runs a project headless. `fail_installation` on `debian:12` runs the installer itself
  (Goals) and covers the zero-patch form. `scenarioArchitectures` selects amd64 and arm64; the failure scenario uses
  fixture releases, so it runs the same on both.
- **Prerequisites from the image's own repositories, only when missing, left installed; the target checked to be absent
  or a regular file; the skip check on the parsed `--version` output.** As in the `act` design, for the same reasons,
  with `unzip` in place of `tar`.

## Security review

- **Downloads:** the archive and the checksum list of one release and architecture, and one header-only request for
  `latest`; all on github.com over HTTPS with one redirect to GitHub's asset host (URL inventory). Nothing is piped to a
  shell.
- **Verification:** SHA-512 of the archive against its exact entry in the checksum list; the checksum list and the
  latest-release link rely on TLS alone, stated in the spec. This detects corruption and a mismatched file but not a
  compromised release pipeline or a release replaced after publication.
- **Keys:** none; upstream signs nothing for Linux, so there is no key or identity to pin.
- **Code run at build time:** the verified executable once with `--version`, and the executable already at
  `/usr/local/bin/godot` once with `--version` for the skip check, both as root with `HOME` in the temporary directory.
  The second runs whatever an earlier layer put there; the `act` design accepts the same for `act --version`.
- **Metadata:** no `customizations`, so the feature brings no editor extension that a workspace could make run a command
  (Decisions; spec, "No editor customizations"). `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`,
  lifecycle commands, `containerEnv`, `dependsOn`, and `installsAfter` are not declared.
- **Files written:** only `/usr/local/bin/godot` and the prerequisites' packages; nothing under a home directory and no
  self-contained mode marker (spec, "No other configuration").
- **Options:** `version`, validated before use; no URL, path, credential, or free-form option, by design.
- **Idempotency:** the spec's "Installing twice" requirement, reached through the skip check, the target check, the
  version check before activation, and the atomic replace, tested through the duplicate test (Options).
- **Failure behavior:** the spec's failure scenarios, checked as described under Goals; every failure exits non-zero,
  which fails the image build.

## Supported images

The planned `test/godot/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                         |
| -------------------------------------------------- | --------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with a non-root user           |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl`, certificates, `unzip` |
| `fedora:44`                                        | `dnf` path; the feature installs `unzip`                                    |

The same list as `quarto`, whose change verified that all three tags publish amd64 and arm64 images. Only the x86_64
build was run during research (the research machine had no arm64 emulation); the arm64 archive was inspected and
declares the same libraries and glibc 2.28, and CI runs it on arm64 runners.

## URL inventory

Every URL the feature's scripts access. All are fetched at build time by `install.sh`; the feature fetches nothing at
container start. It configures no package repository and has no feature OCI reference. `<tag>` is the selected tag, such
as `4.6.3-stable`; `<arch>` is `x86_64` or `arm64`. The host of the redirect target in the last row may move.

| URL                                                                                                                                         | Purpose                                                      | When                                                                        | Verification                                                               | Evidence (2026-11-06)                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `https://github.com/godotengine/godot/releases/latest`                                                                                      | Resolve `latest` from the `Location` header, not followed    | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` | TLS; the tag must pass the version validation and the minimum              | `302`, `Location: https://github.com/godotengine/godot/releases/tag/4.7.2-stable`     |
| `https://github.com/godotengine/godot/releases/download/<tag>/Godot_v<tag>_linux.<arch>.zip`                                                | Release archive holding the executable                       | Build                                                                       | TLS; SHA-512 against its exact entry in the checksum list (integrity only) | `4.2` and `4.7.2`, x86_64 and arm64: `302` to the row below, then `200`; digest equal |
| `https://github.com/godotengine/godot/releases/download/<tag>/SHA512-SUMS.txt`                                                              | Checksum list for the release, fetched before the archive    | Build                                                                       | TLS only; unsigned, same origin as the archive                             | `200`; one line per Linux archive in `4.2`, `4.3`, `4.6`, `4.6.3`, `4.7.2`            |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<path>?<signed query>`, redirect target of the two rows above | Where GitHub serves release assets; reached only by redirect | Build                                                                       | As the row that redirected to it                                           | Final host `release-assets.githubusercontent.com`, one redirect hop                   |

The target of the latest-release link is only read from the header, never fetched. At run time the editor makes the
requests its own settings allow; the feature itself requests nothing.

## Risks / Trade-offs

- [GitHub's latest-release link briefly points to a newly published release of an older branch] → A `latest` build in
  that window installs that release when it is at or above `4.2`, or fails naming the tag; a rebuild later installs the
  newest. Users who need a fixed release pin `version`.
- [A release is public before its archives and checksum list are uploaded] → The checksum list is fetched first and
  uploaded last, so a build in those minutes fails naming the checksum list; a rebuild passes. CI runs share the window.
- [The checksum list is unsigned and served from the same origin, and releases are mutable] → The spec states integrity
  only; upstream has announced no signing.
- [A release is published between a CI job's build and its test] → That job's comparison with the latest-release link
  fails; a re-run passes.
- [A future release changes the archive names, the archive layout, or the `--version` output] → The install fails
  clearly before replacing anything, or the skip check replaces the file needlessly; a PATCH release of the feature
  follows. `4.8` raises the glibc floor to 2.34, which every planned image meets; the version check catches an image
  that does not.
- [The installed release differs from the project's] → An editor run on the project, including the headless language
  server a user turns on in the Godot Tools extension (which starts any 4.x at or above `4.2` for a Godot 4 project),
  imports it and may write files a newer release adds (such as `.uid` files) into the workspace; `NOTES.md` tells users
  to pin `version` to their project's release.
- [Users expect the editor extension and the language server without configuration] → Both need the lines `NOTES.md`
  shows in the user's own `devcontainer.json`; the cost is accepted for the reason under Decisions.
- [Users expect the editor's window or export templates] → `NOTES.md` states the headless scope and the template steps.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches and the version check guards the C library, but only listed images are supported; `NOTES.md` points to
  the compatibility list.

## Open Questions

None.
