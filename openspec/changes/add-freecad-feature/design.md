# Design

## Context

See [proposal.md](proposal.md) for the outcome and [specs/freecad/spec.md](specs/freecad/spec.md) for the contract. No
FreeCAD feature exists in this collection. The closest precedent is `blender`: an official build under `/opt`, commands
in `/usr/local/bin`, a provenance marker, precompiled bytecode, and staged replacement; `quarto` and `pi` are the
precedents for resolving releases through the GitHub API.

Research on 2026-11-25, needed only for this change. Everything was run on amd64; nothing was run on arm64.

- **Releases.** `FreeCAD/FreeCAD` publishes stable releases with plain tags (`1.1.0` to `1.1.4`, and `1.0.2`), each
  neither draft nor pre-release, and a weekly pre-release (`weekly-2026.11.25`) every week. GitHub's latest release is
  1.1.4, which its notes call the last planned maintenance release of the 1.1 series. The release listing is two pages
  of 100 today, most of it weekly builds.
- **Assets.** A 1.1 release holds, per architecture, `FreeCAD_<VERSION>-Linux-<x86_64|aarch64>-py311.AppImage`, a
  `.zsync` file, and `<NAME>-SHA256.txt` in coreutils format with one entry. 1.0.2 names its files
  `FreeCAD_1.0.2-conda-Linux-…`, and weekly builds drop the `-py311` part and have no checksum file. No release has a
  signature for its Linux assets; the release notes say only the Windows and macOS builds are signed. The 1.1.4 x86_64
  AppImage is 782 MiB, and its digest matched its checksum file. A download URL redirects to
  `release-assets.githubusercontent.com` over HTTPS.
- **Unpacking.** The AppImage ran `--appimage-extract` in a container without FUSE in about 5 s and unpacked to 3.1 GiB.
  The tree holds `AppRun`, a desktop entry, and `usr/`, with `usr/bin/` holding `freecad`, `freecadcmd`, `python`,
  `pip`, `gmsh`, `ccx`, `dot`, `unflatten`, and `pyside6-rcc`. Unpacked files keep the build's ownership and some are
  group-writable.
- **Command line.** `usr/bin/freecadcmd`, started directly with no environment set, reported its version, ran a script,
  and exported STEP on bare `debian:12`, `debian:13`, `ubuntu:22.04`, `fedora:44`, `almalinux:8`, and `almalinux:9`,
  with no package added; the binaries need glibc 2.17 symbols at most. As a non-root user it ran from a read-only tree
  and created `~/.config`, `~/.cache`, and `~/.local`. A script ending in `raise SystemExit(3)` exits 3; a script with
  an uncaught exception prints the traceback and exits 0.
- **GUI.** The tree carries its own X11, xcb, xkbcommon, fontconfig, freetype, Wayland client, and libglvnd libraries,
  but no Mesa vendor library or DRI driver, no font, and a fontconfig library that finds no configuration by itself.
  With a reachable X server and nothing added, `freecad` aborts with "Could not initialize GLX" on `debian:12`,
  `debian:13`, `fedora:44`, and `almalinux:9`. With the packages below and `FONTCONFIG_FILE=/etc/fonts/fonts.conf`,
  `FONTCONFIG_PATH=/etc/fonts`, it opened a document and saved an image of its 3D view on llvmpipe on the same four
  images; on the devcontainers Ubuntu 24.04 base the same ran with the X server in the same container. With
  `QT_QPA_PLATFORM=offscreen` and no X server, the GUI starts and a script using `FreeCADGui` runs, but there is no
  OpenGL context, and saving an image of a 3D view hangs.
  - apt: `libgl1-mesa-dri libglx-mesa0 libegl-mesa0 fontconfig-config fonts-dejavu-core`
  - dnf: `mesa-dri-drivers mesa-libGL mesa-libEGL fontconfig dejavu-sans-fonts`
- **AppRun.** Upstream's launcher exports `PREFIX`, `PYTHONHOME`, `PATH_TO_FREECAD_LIBDIR`, `FONTCONFIG_FILE` and
  `FONTCONFIG_PATH` (the host's `/etc/fonts`), `QT_QPA_PLATFORM=xcb` ("use X to run on Wayland"), and `SSL_CERT_FILE`
  and `GIT_SSL_CAINFO` (the tree's `usr/ssl/cacert.pem`), all unconditionally, then starts `usr/bin/freecad` or the
  `usr/bin` program its first argument names. Started through it without an X server, `freecad` aborts with Qt's "no Qt
  platform plugin could be initialized", and no caller can choose another platform.
- **Bytecode.** The tree ships 18 `.pyc` files for about 10,200 Python sources. One root run of a small script wrote 24
  more into the tree. Compiling `usr/` with the tree's interpreter in isolated mode took 8 s on 28 cores, added about
  0.3 GiB, and exited 1 because a few bundled sources do not compile; afterwards a root run importing Part, Mesh,
  Sketcher, Draft, and Import wrote nothing into the tree.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- One upstream: every request the feature makes goes to `api.github.com` for metadata or to
  `github.com/FreeCAD/FreeCAD/releases/download/` for assets, over HTTPS on every hop. Checked by download review of
  every `curl` call and by a fixture scenario whose `curl` stub records each request.
- Verify before running: nothing from an AppImage is unpacked or executed before its digest matches its checksum file.
  Checked by fixture scenarios for a missing checksum asset, a missing or duplicated entry, and a mismatch.
- A root-owned tree at `/opt/freecad`, two launchers, and a root-owned provenance marker inside the tree identify the
  active, feature-managed release. Checked by permission, conflict, and repeat-installation scenarios.
- No run of FreeCAD changes the tree. Checked by comparing a manifest of the tree before and after root and remote-user
  runs of scripts that import the bundled workbenches.
- Replacement stages the new tree on the same filesystem and keeps the previous tree until the new `freecadcmd` reports
  the selected release. Checked by failed-replacement and failed-repair scenarios.
- The feature provides no display. The GUI is checked against an X server the test itself installs and starts in the
  container; that server is test preparation, never part of the feature.
- The launchers add only the five variables the spec names and never replace a caller's value. Checked by a scenario
  that prints the environment of a child process and by one that starts `freecad` on the offscreen platform.

**Non-Goals:**

- Weekly, release-candidate, and other pre-release builds; releases before 1.1.0.
- A display server, VNC, noVNC, a window manager, or a desktop; GPU passthrough and Vulkan drivers.
- Running FreeCAD as an AppImage through FUSE, and keeping several releases side by side.
- Putting the bundled Python, pip, Gmsh, CalculiX, or Graphviz tools on `PATH`, and making the FreeCAD modules
  importable from another Python interpreter.
- Add-ons, extra workbenches, macros, editor extensions, and MCP servers.
- Persisting per-user FreeCAD state across container rebuilds.
- The openSUSE and Arch families and musl-based images; adding a family later is a MINOR change.

## Decisions

### Option interface

| Name      | Type     | Default  | Enum / proposals                   | Meaning                                                                       |
| --------- | -------- | -------- | ---------------------------------- | ----------------------------------------------------------------------------- |
| `version` | `string` | `latest` | No enum; proposals `latest`, `1.1` | Newest stable release, newest stable release of a series, or an exact release |

`latest` keeps the zero-configuration path useful and follows the collection's convention. A series follows patch
releases within one line, which matters here because 1.1.4 fixed two file-handling vulnerabilities. An exact release
gives reproducible builds. The floor is 1.1.0: from it on, asset and checksum names follow one pattern, while 1.0.2 uses
another, and upstream states that every release before 1.1.4 carries the two vulnerabilities, so reaching further back
would add a naming rule to serve releases upstream asks users to leave.

Rejected shapes: weekly builds, as a keyword or a `weekly-<date>` value, because they have no checksum file, so
installing one would rest on TLS alone, and their asset names follow another pattern; the maintainer decided against
them. A `gui` switch for the GUI libraries, because the maintainer decided they are always installed and they are small
beside a 3.1 GiB tree. An option exposing the bundled Python, deferred by the maintainer. A leading `v`, because
FreeCAD's tags and file names write versions without it. A URL override, because it would bypass the source rule.

### Release metadata

Resolve through the three GitHub API URLs the spec names, unauthenticated, with `jq` reading the responses. An exact
release reads its own release object; `latest` reads GitHub's latest release and then applies the same checks as an
exact release (not a draft, not a pre-release, a plain-version tag, 1.1.0 or later), so a mislabeled release fails
instead of installing. A series reads the listing 100 entries a page, up to a fixed bound of pages, keeps the stable
releases whose tag belongs to the series, and sorts numerically; the bound is a constant in the script, and a series
that would need more pages fails naming the bound. The asset is found in the release object by the spec's name pattern,
anchored on the version and architecture, and must match exactly once; the `-py<DIGITS>` part is matched, not fixed,
because the bundled Python version is upstream's to change.

Rejected: the `releases/latest` web redirect the single-binary features use, because a series still needs the listing
and the asset name cannot be built from the version alone; GitHub's own asset digest in the API response, because the
download rules allow using it but upstream's checksum file is the evidence they require; a `GITHUB_TOKEN` to raise the
rate limit, because a build-time secret would end up in image layers, so a rate-limit response fails with the URL
instead.

### Unpacking and trust

Verify the AppImage against its checksum file, then run it once with `--appimage-extract` in a staging directory and
delete the file. This executes the AppImage's embedded runtime as root, after verification and before anything else from
it; the spec states it. Normalize the unpacked tree to root ownership without group or world write access, because the
build's ownership and modes come through as they are.

Rejected: `unsquashfs`, which would avoid running the runtime but needs the image's squashfs tools to support the
AppImage's compression and the script to locate the filesystem inside the ELF file, and FreeCAD's own code runs as root
moments later anyway for the version check and the bytecode step; keeping the AppImage and setting
`APPIMAGE_EXTRACT_AND_RUN=1`, which unpacks 3.1 GiB into `/tmp` on every start; distribution packages (Debian 12 has
0.20, and paths and versions differ by distribution); Flathub and Snap (not usable in an image build); the conda
packages (a second package manager and no checksum of the same kind).

### Layout, launchers, and environment

`/opt/freecad` holds the unpacked AppImage tree, the two launchers, and the marker. `/usr/local/bin/freecad` and
`/usr/local/bin/freecadcmd` are symbolic links to the launchers, so the commands and the tree are replaced together. A
launcher is a short script that applies the spec's five defaults and `exec`s `usr/bin/freecad` or `usr/bin/freecadcmd`.

The launchers do not call `AppRun`, for two reasons found in research: it overrides `QT_QPA_PLATFORM`, which takes the
offscreen platform and Wayland away from the caller, and it exports `PYTHONHOME`, which would break any other Python
interpreter a FreeCAD script starts. The binaries started without `PREFIX`, `PYTHONHOME`, or `PATH_TO_FREECAD_LIBDIR` on
every image tried, so the launchers leave those three out. They keep the other five as defaults: the bundled fontconfig
finds no configuration without the two fontconfig variables; the certificate variables are upstream's fix for the
bundled Python's TLS, and a caller behind an inspecting proxy can now point them at the image's bundle; and `xcb` stays
the default platform because upstream forces it to avoid FreeCAD's Wayland problems, which a dev container that forwards
both a Wayland and an X11 socket would otherwise meet. The same launcher logic serves `freecadcmd`, which ignores the Qt
variable.

Rejected: links straight to the binaries, as `blender` does, because the GUI would start without fonts; a
`/etc/profile.d` script or `containerEnv`, because they would set the variables for every process in the container and
not reach commands run without a login shell; defaulting to `offscreen` when no display is set, because it would make
`freecad` appear to work while a 3D view cannot render, which is a guess upstream does not make.

### Runtime libraries

Install the package sets in Context from the image's repositories, skipping packages already present, with weak
dependencies and recommendations disabled, together with the missing download tools (curl, CA certificates, jq,
sha256sum). They are unconditional: without Mesa's vendor libraries and a DRI driver the GUI aborts at start even with a
display, and without a font it shows no text. EGL is included beside GLX so that a caller who chooses the Wayland
platform has a vendor library too. Rejected: Xvfb or a VNC stack (the feature provides no display; NOTES shows how to
add one); Mesa's Vulkan driver (FreeCAD's views use OpenGL).

### Bytecode

Compile the tree's Python sources with the tree's own interpreter in isolated mode before activation, and accept sources
that do not compile: the step fails the installation only when the interpreter cannot run. Without it every root run
writes into the managed tree, which the conflict and health checks treat as the feature's own, and every non-root start
recompiles. Rejected: leaving the tree as unpacked, and `PYTHONDONTWRITEBYTECODE` in the launchers, which would keep the
tree unchanged but leave every start slow and add a sixth variable that leaks into child processes.

### Conflicts and replacement

Follow the `blender` precedent. Only a tree with the feature's root-owned marker is managed; a foreign `freecad` or
`freecadcmd`, including a distribution package, conflicts even at the requested version. Commands are discovered on
root's PATH and the remote user's login PATH without executing foreign binaries. A healthy managed installation is one
whose marker and `freecadcmd --version` agree on the release. Replacement renames trees on the same filesystem, keeps
the previous tree until the staged `freecadcmd` reports the selected release, and removes backups only after success. A
replacement temporarily needs room for two trees and the AppImage, about 7.5 GiB.

### Platform and test bounds

Compatibility candidates, each on amd64 and arm64: `mcr.microsoft.com/devcontainers/base:ubuntu24.04` as `vscode`,
`debian:12`, `debian:13`, `fedora:44`, and `almalinux:9`. Research ran the amd64 build on each; the implementation
confirms them with the feature itself, and the compatibility list stays the authority. The arm64 build was not run: CI's
arm64 runner is its first test, and if it cannot be made to pass, the design returns to the maintainer instead of
quietly dropping the architecture.

Real-release tests cover `latest`, the `1.1` series, and exact `1.1.0`, the floor; they never assert which release is
newest. Local fixtures, with a `curl` stub serving recorded metadata and a small stand-in AppImage, cover a listing in
mixed order with weekly builds, a mislabeled latest release, a rate-limit response, missing and ambiguous assets,
checksum failures, and failed replacements. Architecture, distribution, and musl rejection run the installer on a
supported image with a stubbed `uname`, a substituted `/etc/os-release`, and a stub musl loader, in one `fail_`
scenario. The GUI scenario installs Xvfb in its script and bounds every `freecad` run with a timeout. Every job
downloads about 0.8 GiB and needs about 4 GiB of disk, and the plan is one job per image, architecture, and scenario, so
checks that share a preparation share a scenario and scenarios run on amd64 only unless a check is specific to arm64.
Helpers stay in `test/freecad/`.

### Documentation

NOTES covers the command-line recipe (`timeout <seconds> freecadcmd script.py`), wrapping a script's body so that an
exception ends in a non-zero `sys.exit`, the difference between `freecadcmd` and `freecad -c`, giving the GUI a display
(the editor's or host's X11 forwarding, or an X server the developer adds), the `xcb` default and
`QT_QPA_PLATFORM=offscreen` with its limit that 3D views do not render, software rendering on llvmpipe, per-user state
under the user's home and its loss on rebuild without a volume, the bundled programs under `/opt/freecad` that stay off
`PATH`, the size of the image layer, and that weekly builds are not offered.

## Risks / Trade-offs

- [Same-release checksum] A compromise of the FreeCAD project's GitHub release is undetectable → the spec states the
  TLS-alone trust; the collection accepts upstream compromise generally.
- [Asset naming] A new series may rename its assets again, as 1.1 did → the pattern match fails naming the release and
  the missing asset instead of guessing; earlier releases keep working, and widening the pattern is a spec change.
- [API rate limit] Unauthenticated GitHub API calls are limited per address, and a shared build host can exhaust them →
  installation fails naming the URL; one to three calls per build keeps the use small.
- [Size] About 3.4 GiB of FreeCAD with bytecode per image, plus Mesa with LLVM (not measured); a build needs roughly
  twice that for a moment → NOTES states it.
- [arm64 untested in research] The aarch64 build or its package set may behave differently → CI decides; see Platform
  and test bounds.
- [Uncompilable sources] A few bundled sources do not compile, so a module among them still writes nothing but is
  recompiled per start → the unchanged-tree check covers the workbenches named in the spec's scenario, not every module.
- [GUI without GPU] llvmpipe renders slowly on large models → NOTES says so; GPU passthrough is out of scope.
- [End of the 1.1 series] `latest` will move to the next series when upstream releases it → a consumer who needs 1.1
  pins the series.
