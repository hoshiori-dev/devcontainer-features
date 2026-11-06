# Design

## Context

See [proposal.md](proposal.md) for the outcome and [specs/blender/spec.md](specs/blender/spec.md) for the contract. No
Blender feature exists in this collection or in the public Dev Container Features index. The closest precedent is
`quarto`: an official tarball under `/opt`, one link in `/usr/local/bin`, a provenance marker, and staged replacement.

Research on 2026-11-06, needed only for this change:

- **Source trust.** `github.com/blender` is a GitHub-verified organization that controls `www.blender.org`.
  `blender/blender` is Blender's official read-only mirror of `projects.blender.org/blender/blender`, where development
  happens (developer handbook, "GitHub Mirror"); it publishes no GitHub Releases and no binaries, and its tags appear
  about a day before the release archives. `www.blender.org` is run by Blender Institute B.V. for the Stichting Blender
  Foundation. Its download page links to `mirror.blender.org`, a Mirrorbits redirector that answered with a 302 to
  third-party mirrors (13 of its 14 mirrors are third parties). `download.blender.org` is the Foundation's own entry in
  that mirror list and the host the release checklist deploys to; it served the archive and the checksum file directly
  over HTTPS with HSTS and no redirect. This was observed from one Cloudflare location only. The host does redirect a
  directory URL without its trailing slash (`/release/Blender5.2` to `/release/Blender5.2/`), and the release checklist
  creates a series directory before uploading its files.
- **Release layout.** `download.blender.org/release/` is an HTML autoindex of `Blender<MAJOR>.<MINOR>/` directories with
  no JSON index; entries are ordered as text (4.5.10 before 4.5.2). Every release from 4.2.0 to 5.2.3 has exactly one
  Linux asset, `blender-<VERSION>-linux-x64.tar.xz`, and a `blender-<VERSION>.sha256` (also `.md5`) in coreutils format
  covering all of that release's assets. No release has a detached signature. Release directories hold final releases
  only. One checksum file (4.5.4) was uploaded about 19 hours after its archive.
- **Versions.** Newest release 5.2.3 (2026-10-22), an LTS. Maintained LTS lines: 4.5 (until July 2027) and 5.2 (until
  July 2028); 4.2 LTS ended in July 2026. 5.3.0 is scheduled for 2026-11-10 and makes Vulkan the default backend on
  Linux. No first-party Linux arm64 build exists: not in releases, daily builds, Snap, or PyPI `bpy`.
- **Runtime.** The binary needs glibc 2.28 and an x86-64-v2 CPU. It links `libX11`, `libXrender`, `libXfixes`, `libXi`,
  and `libxkbcommon`, and through its bundled USD library `libSM`, `libICE`, `libXext`, and `libGL`; `libEGL` is opened
  when a GPU context is first needed. Without `libEGL`, Workbench and EEVEE abort; with `libEGL` but no Mesa DRI driver
  (AlmaLinux 8, where the driver is not pulled in) they crash; Cycles works either way. With the libraries below, all
  three engines rendered in background mode on llvmpipe without Xvfb on debian:12 and 13, ubuntu:22.04 and 24.04, the
  devcontainers Ubuntu 24.04 base, fedora:44 and 45, and almalinux:8 to 10, for 5.2.3 and 4.5.15. These sets pull in
  Mesa's hardware DRI drivers beside llvmpipe, Wayland client libraries, and on debian:13 and Ubuntu 24.04 the Vulkan
  loader, but no Vulkan driver, display server, or Python package.
  - apt:
    `libx11-6 libxrender1 libxfixes3 libxi6 libxkbcommon0 libsm6 libice6 libxext6 libgl1 libegl1 libegl-mesa0
    libgl1-mesa-dri`
  - dnf:
    `libX11 libXrender libXfixes libXi libxkbcommon libSM libICE libXext libglvnd-glx libglvnd-egl mesa-libEGL
    mesa-dri-drivers`
- **Size and timing.** The 5.2.3 archive is 368 MiB and unpacks to about 1.2 GiB; the Mesa stack adds 200–240 MB. On 28
  cores at 64×48: Python start 1.2 s, Cycles 1.4 s, Workbench 2 s, first EEVEE render 8–17 s (shader compilation on
  llvmpipe, cached afterwards in `~/.cache`). Debian and Ubuntu print three harmless `EGL_BAD_MATCH` lines per GPU
  render.
- **Python.** The bundled interpreter is Python 3.11 for 4.2–5.0 and 3.13 from 5.1, with pip. It ignores `PYTHONPATH`
  and the user site directory unless `--python-use-system-env` is given (5.2.3 also has `--python-use-user-env`; 4.5.15
  does not). The 4.5.15 archive ships 855 `.pyc` files; 5.2.3 ships none, so a non-root user recompiles on every start
  (1.25 s against 0.37 s precompiled), and any Python run as root writes about 425 `.pyc` files into the tree.
  Precompiling the release directory with the bundled interpreter takes about 1 s and adds 43 MiB; afterwards a root
  sweep of scripts, all three engines, every bundled add-on, exports, saved preferences, and extension commands left
  every file of the 5.2.3 and 4.5.15 trees byte-identical.
- **Command line.** A raising `--python` script exits 0 unless `--python-exit-code` comes before `--python`; an invalid
  output format also exits 0. In background mode 4.5.15 hangs indefinitely on an unknown `-E` engine id; 5.2.3 exits 1.
  The EEVEE id is `BLENDER_EEVEE_NEXT` for 4.2–4.5 and `BLENDER_EEVEE` from 5.0. `--command extension` `validate`,
  `build`, and `install-file` work offline; `sync` and repository installs need `--online-mode`, even for a `file://`
  repository. An extension installed with `install-file` is enabled in later plain `-b` runs but not under
  `--factory-startup` unless `--addons bl_ext.user_default.<id>` names it, and a module `--addons` cannot load still
  exits 0 under `--python-exit-code`.
- **Agent and editor tooling.** Blender Lab publishes an official MCP add-on (Blender 5.1+); it needs Blender's online
  access and runs the code its connected client sends. The community MCP servers examined require a GUI session. No
  Blender Foundation publisher exists on the VS Code Marketplace or Open VSX; `JacquesLucke.blender-development`,
  published by an individual developer on the Marketplace and not on Open VSX, starts a GUI Blender and installs Python
  packages with pip on first launch.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- One upstream host: every request the feature makes goes to `download.blender.org` and fails on a redirect instead of
  following it. Checked by download review of every `curl` call, and by a fixture scenario whose `curl` stub records
  each request's arguments, asserts the HTTPS-only and no-redirect flags, and answers one request with a redirect.
- Verify before extraction: nothing from an archive is extracted or run before its digest matches the release's checksum
  entry. Checked by fixture scenarios for a missing file, a missing or duplicated entry, and a mismatch.
- A root-owned tree at `/opt/blender`, one link `/usr/local/bin/blender`, and a root-owned provenance marker inside the
  tree identify the active, feature-managed release. Checked by permission, conflict, and repeat-installation scenarios.
- No run of Blender changes the tree. Checked by comparing a manifest of the tree before and after root and remote-user
  runs of a script, each render engine, and an extension command.
- Replacement stages the new tree on the same filesystem and keeps the previous tree until the new Blender reports the
  selected release. Checked by failed-replacement and failed-repair scenarios.
- Headless only, from distribution Mesa: every compatibility image renders with all three engines in background mode, as
  root and as the remote user, with no display server. Checked by render scenarios that assert exit status and a
  non-empty image, not the absence of warnings.
- Extension development works without network access. Checked by a scenario run with `--network=none`.

**Non-Goals:**

- Architectures other than amd64, and any fallback to distribution packages.
- GPU passthrough, Vulkan drivers, a GUI session or desktop, and several Blender releases side by side.
- Pre-release, release-candidate, and daily builds.
- PyPI `bpy`, type stubs, MCP servers, add-ons, extensions, and editor extensions.
- Persisting per-user Blender state across container rebuilds.
- The openSUSE and Arch families; adding one later is a MINOR change.

## Decisions

### Option interface

| Name      | Type     | Default  | Enum / proposals                          | Meaning                                                         |
| --------- | -------- | -------- | ----------------------------------------- | --------------------------------------------------------------- |
| `version` | `string` | `latest` | No enum; proposals `latest`, `5.2`, `4.5` | Newest release, newest release of a series, or an exact release |

`latest` keeps the zero-configuration path useful and follows the collection's convention. A series follows patch
releases within one line, which suits add-on development against an LTS line; the proposals name the two maintained LTS
lines today. An exact release gives reproducible builds. The floor is 4.2.0: it introduced the extensions platform and
`blender --command extension`, which the add-on use case depends on, and asset and checksum naming has been uniform
since well before it.

Rejected shapes: an `lts` keyword, because `download.blender.org` carries no LTS marker and the only first-party sources
— the `projects.blender.org` milestones API, which already lists unreleased LTS lines, or the version header in the
source at a tag — would add an install-time host behind a Cloudflare challenge on its web paths; NOTES links the LTS
page instead. A leading `v`, because Blender's archives and documentation write versions without it. A separate series
or channel option, because it allows contradictory combinations. A URL or mirror override, because it would bypass the
download host rule.

### Downloads and trust

Request only the listing, archive, and checksum URLs named in the spec. Every request passes
`--proto '=https' --location --max-redirs 0`, so curl fails on any 3xx without contacting its target (plain `--fail`
without `--location` would exit 0 on a 3xx). This deviates from the collection's usual fetch, which follows HTTPS
redirects, because a redirect from this host can lead into the mirror network the spec excludes. Listing URLs keep their
trailing slash, since the host redirects a directory URL without it. Exact releases build their URLs directly and need
no listing. `latest` and a series read the autoindex HTML, accept only entries matching strict version patterns, sort
numerically, and count a release only when its archive and checksum file are both listed, so an upload in progress
selects the previous release instead of failing; for `latest` that includes a new series directory that has no files
yet. The checksum file must hold exactly one entry for the archive name; the `.md5` file is ignored. Listings and the
checksum file rely on TLS alone, as the spec states, because Blender signs neither.

Rejected sources: the download page and `mirror.blender.org` (third-party mirrors); the GitHub mirror and
`projects.blender.org` tags (no binaries, and tags precede the archives); `builder.blender.org` (rebuilt artifacts with
other digests, pre-releases, rotating retention, and a separate CDN host); Snap, Steam, and the Microsoft Store (not
usable in an image build); Flathub (community repackaging); distribution packages (Debian 12 has 3.4.1 and Ubuntu 24.04
has 4.0.2, both without the extension command line, and paths differ by distribution); PyPI `bpy` (requires exactly the
bundled Python version, has no extension command line, and is a module rather than the application).

### Runtime libraries

Install the package sets in Context, from the image's repositories, skipping packages already present, with weak
dependencies and recommendations disabled. Also install only the missing download and extraction tools (curl, CA
certificates, tar, xz, sha256sum); an existing `curl-minimal` satisfies curl on Enterprise Linux. The EGL and Mesa DRI
packages are named explicitly because AlmaLinux 8 does not pull the DRI driver, and they are unconditional because
`libGL` already brings Mesa and without EGL two of the three engines crash; EGL itself adds under 1 MB. Rejected: an
option to skip them (it would only produce a Blender that crashes on two engines), Xvfb (background rendering does not
need it), and Mesa's Vulkan driver (about 100–120 MB, while 5.3 falls back to OpenGL when no Vulkan driver exists).

### Layout, link, and bytecode

Extract the verified archive into a staging directory beside `/opt/blender`, strip the archive's top directory, and
point `/usr/local/bin/blender` at the `blender` executable rather than `blender-launcher`: the launcher prepends the
tree's `lib` to `LD_LIBRARY_PATH`, which then leaks into every process a Blender script starts. The cost is that an
image-wide `LD_LIBRARY_PATH` could shadow bundled libraries; NOTES mentions the launcher for that case.

Precompile the tree's Python modules with the verified bundled interpreter in isolated mode before activation. 5.x
archives ship no bytecode, so without it every non-root start pays about 0.9 s, which agents pay per call, and every
root run writes bytecode into the managed tree. 4.5 archives ship bytecode themselves, so this restores upstream's
earlier layout rather than adding a new kind of file. Rejected: leaving the tree byte-identical to the archive (slower
starts and a tree that root runs change), and an option for it (no user benefits from slower starts).

### Conflicts and replacement

Follow the `quarto` precedent. Only a tree with the feature's root-owned marker is managed; a foreign `blender` command,
including a distribution package, conflicts even at the requested version. Discover commands on root's PATH and the
remote user's login PATH without executing foreign binaries. A healthy managed installation is one whose marker and
`blender --version` agree on the release; checking it starts no Python. Replacement renames trees on the same
filesystem, keeps the previous tree until the staged Blender reports the selected release, and removes backups only
after success. Replacement temporarily needs room for two trees and the archive, about 2.8 GiB.

### Platform and test bounds

Compatibility candidates, amd64 only: `mcr.microsoft.com/devcontainers/base:ubuntu24.04` as `vscode`, `debian:12`,
`debian:13`, `fedora:44`, and `almalinux:9`. Research ran the binary on each; the implementation confirms them with the
feature itself, and the compatibility list stays the authority.

Real-release tests cover `latest`, the `4.5` series, and an exact 4.2 release, the floor; they never assert which
release is newest. Local fixtures cover listings in text order, a release without a checksum file, redirects, checksum
failures, and failed replacements. Architecture, distribution, and musl rejection run the installer on a supported image
with a stubbed `uname`, a substituted `/etc/os-release`, and a stub musl loader, as quarto's `fail_contract` does, in
one `fail_` scenario. Render checks use each series' EEVEE id and bound every Blender run with a timeout, because 4.5
hangs on an unknown engine id. Every job downloads about 368 MiB and needs about 2 GiB of disk, so checks that share a
preparation share a scenario. Helpers stay in `test/blender/`.

### Documentation, editor, and agent integration

NOTES covers the headless recipe
(`timeout <seconds> blender -b --factory-startup --python-exit-code 1 --python script.py -- <args>`), engine ids per
series, the slow first EEVEE render and harmless EGL warnings, the extension workflow (`validate`, `build`,
`install-file`), running a script with the developer's extension under factory settings
(`--factory-startup --addons bl_ext.user_default.<id>` and a check in the script that fails the run when the module is
not loaded, since a failed `--addons` load alone exits 0), `--online-mode` before `--command` when online access is
wanted, per-user state under `~/.config/blender/<MAJOR>.<MINOR>/` and `~/.cache` and its loss on rebuild without a
volume, the bundled Python, why `pip --user` packages are invisible, and the `PYTHONPATH` with `--python-use-system-env`
form that works on every supported series, the launcher for images with `LD_LIBRARY_PATH`, GPU use being outside the
feature, sizes, and the amd64-only scope.

The feature requests no editor extension: there is no first-party one, and the widely used community extension needs a
GUI Blender and installs packages at first launch. Agents use the command line directly. The official Blender Lab MCP
add-on is left to a later change, which would name its source and state the risk of running generated code with online
access enabled.

## Risks / Trade-offs

- [Same-host checksum] A compromise of `download.blender.org` is undetectable → the spec states the TLS-alone trust; the
  collection accepts upstream compromise generally.
- [Listing format] A change of the autoindex HTML breaks `latest` and series resolution → strict parsing fails with the
  listing URL instead of guessing; exact releases keep working.
- [Redirect policy] If `download.blender.org` starts redirecting to mirrors, from some regions or under load,
  installation fails rather than fetching from a third party → the error names the URL; research saw one region only.
- [Vulkan default from 5.3] Rendering relies on the OpenGL fallback when no Vulkan driver exists → render scenarios on
  `latest` exercise it once 5.3 is out; if the fallback fails, the design returns to the maintainer rather than silently
  adding Vulkan drivers.
- [Size] About 1.2 GiB of Blender, 0.2 GiB of libraries, and 43 MiB of bytecode per image → NOTES states it.
- [CPU baseline] Blender refuses CPUs without SSE4.2, and amd64 emulation on Apple Silicon is untested → Blender's own
  startup check and the installation's version check fail clearly.
- [Old lines] 4.2 no longer receives fixes and 4.5 hangs on an unknown engine id → the floor stays at 4.2 for add-on
  compatibility testing, and NOTES recommends a time limit for every run.
