# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta spec](specs/latex/spec.md) for the contract. This is a new
feature; the collection currently has no TeX installation to extend. Implementation starts only after the draft PR's
approval package is approved.

Upstream research on 2026-10-16 established that:

- TinyTeX supplies prebuilt glibc archives for both x86_64 and arm64. TinyTeX-2 is a daily-only full-scheme archive of
  about 1.8 GB compressed; the standard TinyTeX archive is about 152–158 MB.
- The upstream shell installer removes an existing installation before unpacking its replacement and does not verify
  archive digests. This feature implements replacement itself so it can verify the new archive and restore the previous
  tree on failure.
- Current minted bundles latexminted and its Python libraries, including Pygments. Python 3.8+ is required; current TeX
  Live supports restricted shell escape for latexminted. A separate pygmentize remains useful for older templates.
- The TeX Live package database names the Unicode data package `unicode-data`. Japanese bibliography commands are
  supplied by the engine packages; `pbibtex` and `upbibtex` are not standalone top-level packages. `pbibtex-base`
  supplies bibliography styles.
- A disposable AlmaLinux 10 repository query found YAML::Tiny and system Pygments in the vendor CRB repository, CJK Noto
  fonts under names different from the original proposal, and no IPAex system package in the queried repositories.

The source identities were cross-checked: the TinyTeX repository links its documentation website, the website links the
repository and release repository, and CRAN's tinytex package page lists both the repository and documentation URLs.
These are first-party TinyTeX sources. The repository also contains an R companion package; installing R or that package
is unnecessary for this feature.

## Goals / Non-Goals

**Goals**

- Use upstream archives without a source-install fallback; verify the selected architecture and archive provenance in
  download tests.
- Keep TeX operations and writable caches under the configured user's ownership; verify actual package installation and
  compilation as that user.
- Replace an existing TinyTeX installation on every invocation; verify that the last selections win and failed
  replacements restore the previous tree.
- Make the bounded profiles' three-minute ceiling measurable; retain cold-build timings with functional results.
- Complete caching at build time; verify first-use compilation and cache ownership without runtime hooks.

**Non-Goals**

- A persistent volume or lifecycle bootstrap: metadata inspection confirms neither is added.
- Bit-for-bit reconstruction across dates: daily bundles and live CTAN repositories are deliberately rolling. Notes
  explain the limitation and users can preserve a built image by digest.
- Automatic migration of old packages or custom files into the replacement: each installation starts from its selected
  upstream archive. Cross-year repository errors restore the previous tree.
- Automatic editor settings or an unrestricted shell-escape default: metadata and documented recipes are checked.

## Decisions

### Options

All options are new; the delta spec is authoritative.

| Name         | Type   | Default    | Enum                        | Meaning                                            |
| ------------ | ------ | ---------- | --------------------------- | -------------------------------------------------- |
| `profile`    | string | `standard` | `basic`, `standard`, `full` | Bundle and required package tier                   |
| `languages`  | string | `zh,ja`    | none                        | Additional CJK selections, or `none`               |
| `packages`   | string | empty      | none                        | Space/comma-separated TeX Live package names       |
| `ctanMirror` | string | empty      | none                        | HTTPS TeX Live repository; empty uses CTAN routing |

`standard` supplies the requested academic tools without the full archive. Both languages default on for the intended
audience. Extra packages default empty to keep additions explicit. An empty mirror follows CTAN routing rather than
assuming the user's region. A single language string fits the Feature option model; separate language booleans add
configuration without improving the required combinations. A free-form command option is rejected: package selection
does not need shell execution. No upstream-version option is added in this first version because the three bundles share
a rolling daily channel and full is unavailable on the normal monthly channel.

### Bundle installation and verification

Download and unpack the architecture-specific upstream daily archive directly, preserving TinyTeX's normal home layout.
The metadata and archive origins are specified in the delta spec. Resolve the release once per invocation, match the
selected asset, and verify the downloaded bytes against any published verification data and the platform digest when
available. A daily asset replaced between metadata lookup and download causes a mismatch and fails; it never bypasses
verification. Temporary downloads are isolated and removed on failure or success.

This replaces invoking the upstream shell installer. The installer remains useful research for post-install setup,
including the XeTeX postaction, but executing an additional mutable script provides no benefit when extraction and
verification must already be controlled. Native install-tl is rejected because its per-package bootstrap works against
the installation budget. System TeX packages do not provide the required user-owned tlmgr environment. Tectonic does not
provide the traditional Japanese engine workflows.

HTTPS and upstream verification remain enabled for both the bundle and subsequent TeX packages. A user-supplied
repository is an explicit trust choice; it must be a TeX Live repository URL without credentials. Requests to CTAN's
router and its chosen official mirror use HTTPS throughout. The first release does not silently fall back to HTTP, an
unrelated mirror, an older bundle, or an unsigned verification mode.

CTAN's router assigns a mirror per tlmgr run, and CI showed some official mirrors failing every request: one serves an
incomplete certificate chain, others accept no connections. On the default route, the installer therefore runs a failed
`tlmgr install` up to three times in total, so each attempt can reach a different official mirror. A custom repository
is a fixed mirror and gets one attempt. Transfers that tlmgr starts give up after a 20-second connection timeout instead
of the more than two minutes observed in CI. Bundle and release-metadata requests to GitHub use curl's own retries for
every error, including connection resets, with a short delay; certificate verification and the digest check stay in
force. The maintainer rejected pinning one mirror in CI, which would hide the default-route failure users hit, and
reducing the installer's GitHub API requests.

### Package selection

Fresh basic, standard, and full installations use TinyTeX-1, TinyTeX, and TinyTeX-2 respectively. Common tools are
explicitly ensured for every profile rather than relying on a mutable bundle inventory. The common set includes
latex-bin, xetex, luahbtex, luaotfload, fontspec, latexmk, latexindent, and chktex. System Python and Pygments provide
the command-line highlighting interface; standard and full additionally use the TeX-distributed minted integration.

The standard academic set is defined once in the delta spec. Chinese uses its stated package set. Japanese explicitly
includes xecjk for zxjatype, including when Chinese is not selected. Japanese adds luatexja, zxjatype, xecjk, ptex,
uptex, platex, uplatex, japanese-otf, pxjahyper, bxjscls, pbibtex-base, ptex-fontmaps, haranoaji, and ipaex where an OS
IPAex installation is unavailable. Dependencies supply the matching engine binaries. Traditional font maps select Harano
Aji so DVI-to-PDF compilation does not require proprietary fonts.

Package selections are aggregated and deduplicated. One local installed-package inventory filters existing packages for
every profile; tlmgr receives the missing selection in a batch and manages dependencies. Installing no missing packages
avoids a needless package-install transaction. Link refresh and generated formats remain part of successful
installation. Package-manager failures propagate; an already installed package does not conceal another missing one.

### User paths and replacement installation

System dependencies are installed as root. TeX package management, formats, and Lua caches run as the configured remote
user with its actual home. Every invocation downloads the currently selected archive, including TinyTeX-2 when full
follows basic or standard. Existing trees are replaced regardless of provenance, ownership, or markers.

Verify the archive first, move the previous target path to a temporary sibling backup, and extract the new tree at the
normal TinyTeX path so setup uses its final location. Keep the backup until package installation, environment setup, and
cache generation succeed. On failure, remove the incomplete new tree and restore the backup. On success, delete the
backup. Earlier custom files and package additions are intentionally discarded.

Refresh TinyTeX links in the user's `.local/bin`, removing obsolete links into TinyTeX trees while rejecting unrelated
command conflicts. Replace the managed PATH declaration without appending duplicate entries. Other users' trees,
system-managed TeX distributions, and editor settings are not replacement targets. Existing OS dependencies and fonts
may remain; package managers are not used to undo earlier language selections.

Volume persistence and recursive ownership repair remain unnecessary: the current configuration determines a fresh,
user-owned TeX tree in the image layer. A different remote user receives its own installation.

### System dependencies and fonts

Use the distribution's signed repositories for curl, CA certificates, tar, xz, Perl, Python, Pygments, fontconfig, and
latexindent's required Perl modules. Unicode::LineBreak is included for the optional GCString functionality. AlmaLinux's
vendor CRB repository can supply missing modules; no EPEL or other third-party repository is added. Package mappings
follow the tested distribution and release rather than just the executable name of its package manager. Missing required
dependencies cause a clear installation failure.

Noto CJK system fonts supplement the TeX fonts. Where native IPAex packages exist, use them; otherwise use the
TeX-distributed ipaex package. This preserves Japanese compilation without making every distribution enable another
repository. Fandol and Harano Aji remain explicit TeX font dependencies. Smoke documents use these static TeX fonts, so
variations in distribution-provided Noto formats do not alter their font selection.

Fontconfig caches are generated after fonts are installed. Lua font indexing runs as the target user and covers its TeX
and system font sources. Cache failures fail the build. Every replacement prepares the new tree's font index. No volume,
TEXMF relocation, or container-start initialization is introduced.

### Compatibility and verification scope

The initial planned entries for `test/latex/compatibility.json` are:

| Image                                              | Architectures | Remote user |
| -------------------------------------------------- | ------------- | ----------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64  | vscode      |
| `debian:12`                                        | amd64, arm64  | root        |
| `fedora:44`                                        | amd64, arm64  | root        |
| `almalinux:10`                                     | amd64, arm64  | root        |
| `archlinux:latest`                                 | amd64         | root        |

The compatibility file becomes the authoritative supported-image inventory. AlmaLinux supplies RHEL-family coverage;
this does not claim untested RHEL/Rocky releases. Arch ARM is deferred because it needs a separate distribution image
and validation. Alpine and other musl images fail before dependency installation.

Functional coverage includes the common engines, Chinese and Japanese compilation, traditional Japanese font embedding,
bibliography resolution, minted, formatting, and linting. Scenarios exercise all profiles, language subsets, extra
packages, repository selection, target-user ownership, replacement, rollback, and failures. Full-profile smoke coverage
runs on both architectures on the reference Ubuntu image; the default matrix covers every supported pair. Download
failure tests use controlled fixtures and never weaken live download verification.

### Three-minute reference measurement

The ceiling is a release acceptance condition, not a timeout that leaves an incomplete installation after 180 seconds.
Measure the full install.sh wall time, including OS dependencies, bundle transfer and verification, package additions,
font maps, caches, and cleanup. Base-image pulling, unrelated Features, and user-specified extra packages are outside
this measurement. Both bounded profiles use default languages, no extra packages, and the default CTAN route.

The reference environment is a native GitHub-hosted Ubuntu 24.04 Linux runner for each architecture, with one build
running at a time and the base image already available. Disable Docker installation-layer caching; do not seed OS,
TinyTeX, or tlmgr download caches. Record runner resources, base digest, architecture, upstream release, resolved
repository, and elapsed time. Measure both bounded profiles on every declared image/architecture pair; repeat the Ubuntu
reference image three times for each profile and architecture. Every qualifying run must finish in 180 seconds.

A qualifying run has no service outage, transfer retry, or package-repository error. Report excluded network failures
alongside successful measurements rather than silently selecting the fastest run. Ordinary slow successful transfers
still count. Do not claim an unconditional network SLA. Full is functionally tested and timed, with no upper bound. If
standard exceeds the ceiling, optimize within the approved tool/package contract or seek a design revision before
acceptance; do not drop a language, dependency, verification step, or cache to make the measurement pass.

## Risks / Trade-offs

- Rolling bundles and CTAN can change package sizes, compilation behavior, and timing. Functional and timing evidence
  accompanies acceptance; a later performance regression requires a follow-up change rather than an unsupported claim.
- Full installs several gigabytes and increases CI cost. Keep its dedicated scenarios on the reference image while
  testing the default profile on the complete matrix.
- System Noto fonts may use variable formats on some distributions. Representative documents explicitly use the static
  TeX fonts; notes distinguish those from system-font customization.
- Proprietary-font or historical publisher templates can need extra user configuration. Document tested workflows and
  avoid a universal template-compatibility claim.
- Runtime tlmgr changes are absent from a fresh rebuild unless declared in packages. Notes explain that image-layer
  caching is an optimization, not persistence of a running container's filesystem.
