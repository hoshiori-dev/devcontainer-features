# Design

## Context

See proposal.md, Why. The feature combines three patterns the collection already has, and what is the same is named, not
repeated:

- a release binary installed atomically to `/usr/local/bin`, with `latest` read from GitHub's latest-release redirect,
  as in the `uv` and `deno` designs;
- a GitHub release asset without an upstream checksum, compared with GitHub's asset digest when the API reports one, as
  in the `apptainer` design;
- a per-dev-container volume made writable through a group, repaired by an `onCreateCommand` when another UID wrote it,
  as in the `uv` design (archived change `2026-10-02-add-uv-feature`, Decisions).

The interface was agreed with the maintainer in conversation before this change and is recorded in issue #197. It has
the feature id `lean` and the options `elanVersion`, `defaultToolchain` (default `stable`), and `preinstallToolchains`.
elan's home lives on a volume per dev container, and build-time toolchains live in the image, linked into elan's home.
The images are the full list of glibc families. One point changed during research: the agreed `none` for "no default"
became the empty value (Decisions, Option interface).

Upstream facts this change relies on. They were checked on 2026-11-10 against `github.com/leanprover/elan`: the release
API, `master` source, `CHANGELOG.md`, and `elan-init.sh`. They were also checked against `release.lean-lang.org`, the
`leanprover/lean4` release API, Lake's `Lake/Config/Env.lean` and Mathlib's `Cache/IO.lean` on `master`, and
`leanprover/vscode-lean4` on `master`. Behavior was checked with elan 4.2.4 and Lean v4.35.0 in throwaway containers on
an arm64 host. Arch Linux was checked for prerequisites only, under amd64 emulation.

- elan releases. The newest is `v4.2.4` (2026-08-25), and `https://github.com/leanprover/elan/releases/latest` redirects
  to `/releases/tag/v4.2.4`. The releases from `4.1.0` on are `4.1.0`, `4.1.1`, `4.1.2`, and `4.2.0` to `4.2.4`. Tags
  such as `path-toolchain` and `eager-resolution-v9` are marked pre-release; `v4.0.0-rc1` is not. Every release has
  `elan-x86_64-unknown-linux-gnu.tar.gz` and `elan-aarch64-unknown-linux-gnu.tar.gz`. Each holds a single regular file
  `elan-init` of about 13 MB. Its download URL redirects to `release-assets.githubusercontent.com` over HTTPS. Upstream
  publishes no checksum or signature. GitHub's API reports a SHA-256 digest for the `4.2.4` assets and none (`null`) for
  `4.1.0`. No musl build exists, and `elan-init.sh` refuses musl systems. That script always fetches the newest release,
  and without `--no-modify-path` it edits the shell profiles.
- Since `4.1.0`, elan resolves `leanprover/lean4` and `leanprover/lean4-nightly` toolchains through the release index
  `https://release.lean-lang.org`, which has the channels `stable`, `beta`, and `nightly`. Release assets are at
  `https://releases.lean-lang.org/lean4/<tag>/lean-<version>-linux[_aarch64].tar.zst`, which redirects (302) to
  `https://github.com/leanprover/lean4/releases/download/<tag>/…`. Nightlies are at
  `https://github.com/leanprover/lean4-nightly/releases/download/<tag>/…`. Before `4.1.0`, and for any other origin,
  elan scrapes `https://github.com/<origin>/releases/expanded_assets/<tag>`. elan downloads with libcurl, follows
  redirects with no protocol limit, and checks no digest (`download_and_check` passes no hash).
- elan picks its mode from the file stem of `argv[0]`. A symbolic link named `lean` therefore acts as the `lean` proxy;
  Homebrew's and Nixpkgs' packages install the proxies this way. The proxies its installer creates are `lean`,
  `leanpkg`, `leanchecker`, `leanc`, `leanmake`, and `lake` (`self_update.rs`, `TOOLS`).
- elan 4.x behavior, checked in containers:
  - `elan default <name>` stores the name unresolved in `$ELAN_HOME/settings.toml` and downloads nothing, also without a
    network. `elan default none` stores `none`, which `elan show` resolves as `leanprover/lean4:none`, so the value does
    not unset the default.
  - elan creates a missing `ELAN_HOME` whose parent is writable.
  - A toolchain is installed when `$ELAN_HOME/toolchains/<name>` is a directory or a link to one. The name encodes `/`
    as `--` and `:` as `---`, as in `leanprover--lean4---v4.35.0`.
  - With such a link in place, `elan toolchain install` reports "already installed" and exits 0. `lean --version` runs
    the linked toolchain, and `elan toolchain uninstall` removes only the link (`raw::remove_dir`).
  - A dangling link is still listed by `elan toolchain list`.
  - Offline, a `stable` default falls back to the newest installed release with a warning.
  - Installing a toolchain first asks `https://github.com/leanprover/elan/releases/latest` for a newer elan and only
    prints a notice. `elan self update` installs into `$ELAN_HOME/bin`.
- Lean v4.35.0 for Linux is 566 MiB as `.tar.zst`, and 3.1 GB with 18,571 entries unpacked. Its files have modes 0755
  and 0644; the only entries with group or other write are symbolic links. A `find` over its tree took 0.1 s on a warm
  page cache.
- Running v4.35.0 (aarch64):
  - Its bundled clang links against glibc symbols up to `GLIBC_2.30`, so `lake build` of a C target fails on AlmaLinux 8
    (glibc 2.28).
  - `lake new` with the default executable template, `lake build`, and running the executable succeeded with no system
    compiler on `debian:12`, `debian:13`, `ubuntu:24.04`, `fedora:44`, `almalinux:9`, `almalinux:10`, and
    `opensuse/leap:16.0`. Only git was installed for the run.
  - In that check, a non-root user ran a toolchain from a read-only directory through a link in a writable `ELAN_HOME`,
    with no error.
- Lake keeps its artifact cache in `<ELAN_HOME>/toolchains/<toolchain>/lake/cache` unless `LAKE_CACHE_DIR` is set
  (`Env.lean`, `addCacheDirs`). With the toolchain read-only and `LAKE_ARTIFACT_CACHE=true`, `lake build` failed with
  "failed to cache artifact: read-only file system". With `LAKE_CACHE_DIR` set, it succeeded and stored the artifacts
  there. Mathlib's cache uses `MATHLIB_CACHE_DIR`, else `$XDG_CACHE_HOME/mathlib`, else `~/.cache/mathlib`.
- The VS Code extension `leanprover.lean4` adds `~/.elan/bin` to its own `PATH` and runs `elan` from `PATH`. It
  recommends elan 4.0.0 or later and offers `elan self update` only below that.
- Prerequisites missing on each image:

  | Image                                                   | Missing     |
  | ------------------------------------------------------- | ----------- |
  | `debian:12`, `debian:13`, `ubuntu:24.04`                | curl, git   |
  | `fedora:44`, `almalinux:9`, `almalinux:10`, `archlinux` | git         |
  | `opensuse/leap:16.0`                                    | git, `find` |
  | `mcr.microsoft.com/devcontainers/base:ubuntu24.04`      | none        |

  Every image has bash, tar, gzip, `getent`, `groupadd`, `usermod`, `useradd`, `stat`, and `sha256sum`. Only the base
  image and `fedora:44` have `sudo`.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- `install.sh` and the creation script are bash, since every listed image ships it. Checked by shellcheck in
  `just check` and by every compatibility image.
- Validate before any change. The options' forms, the minimum elan release, the architecture, the C library, the
  distribution and its package manager, the remote user, and the group conditions are all checked first. So is each
  target path (`/usr/local/bin/elan` and the six proxies) being absent, a regular file, or a link. All of this happens
  before any package is installed or anything is downloaded. Checked by `fail_contract`, which asserts after each
  rejected run that no package was added and that its `curl` stand-in recorded no request.
- Every request `install.sh` makes itself goes through `curl` with `--proto '=https' --proto-redir '=https'` and only to
  URLs in the URL inventory. Requests elan makes are bounded only by the hosts it is pointed at (Risks). Checked by
  reviewing each `curl` call against the inventory, and by `fail_contract`, whose stand-in records each call's arguments
  and asserts both flags.
- Stage everything, then rename:
  - elan is written beside its target under a temporary name and renamed into place.
  - Each proxy is a new link renamed over the old one.
  - Build-time toolchains are installed under a temporary `ELAN_HOME` beside `/usr/local/share/lean/`, on the same file
    system and outside it, and renamed into `toolchains/` only after elan finished all of them and every other file is
    staged.

  A failure before the renames leaves every earlier file as it was. Checked by the failure cases of `fail_contract` and
  by `duplicate.sh`.
- Build-time elan runs use `ELAN_HOME` and `HOME` inside a temporary directory. The build writes nothing to a real home
  and nothing below `/var/lib/lean` but the empty mount point. Checked by `test.sh`, which finds below `/var/lib/lean`
  only what the creation step makes.
- Nothing under `/usr/local/share/lean` is owned by a user other than root, or is a non-link writable by group or
  others. Checked by `duplicate.sh` and `test_offline_toolchains`.
- The creation script runs as the remote user and changes nothing outside `/var/lib/lean`. It uses `sudo -n` only for
  the repair, and it follows no symbolic link: the walk uses `find -P` and the repair `chown -R -h -P`. Checked by
  `test_repair_volume`, which plants links into the image and outside it.

**Non-Goals:**

- Alpine and other musl images: elan has no musl build and the toolchains are glibc builds.
- glibc older than 2.30 (AlmaLinux 8, Ubuntu 18.04): current toolchains fail there.
- Architectures other than amd64 and arm64: elan builds no others.
- Toolchains from origins other than `leanprover/lean4` and `leanprover/lean4-nightly`, `<origin>:lean-toolchain`
  references, and path toolchains (the issue's Out of scope).
- Running `lake exe cache get`, `lake build`, or any project command, and installing Mathlib.
- `elan self update`, and silencing elan's update notice, for which elan has no switch.
- Sharing toolchains between dev containers, moving run-time toolchains into the image, and garbage-collecting the
  volume.
- A JetBrains plugin: upstream publishes none.

## Decisions

### Option interface

| Name                   | Type     | Default    | Enum or proposals                                    | Meaning                                                                                        |
| ---------------------- | -------- | ---------- | ---------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `elanVersion`          | `string` | `"latest"` | proposals `["latest","4.1.0"]`                       | The elan release: `latest`, or `MAJOR.MINOR.PATCH` from `4.1.0` on                             |
| `defaultToolchain`     | `string` | `"stable"` | proposals `["stable","leanprover/lean4:v4.35.0",""]` | elan's default toolchain outside a project, set at each container creation; empty: not managed |
| `preinstallToolchains` | `string` | `""`       | proposals `["","leanprover/lean4:v4.35.0"]`          | Comma-separated toolchains installed into the image at build time                              |

- **`elanVersion`, not `version`.** elan and Lean both use 4.x numbers, and both an elan `4.2.0` and a Lean `v4.2.0`
  exist. Under `version`, someone who means the Lean release would silently get that elan with the `stable` toolchain.
  The feature also has no single "Lean version": `defaultToolchain`, `preinstallToolchains`, and each project's
  `lean-toolchain` decide it. And the first-party `rust` feature's `version` names the toolchain, so users arrive with
  that expectation. No tooling relies on an option named `version`. Rejected: `version`; `leanVersion` for a toolchain
  (it is `defaultToolchain`).
- **`elanVersion` default `latest`, minimum `4.1.0`.** elan is a version manager with a stable command surface, and the
  newest release is what upstream's installer gives. `4.1.0` is the first release that resolves the official origins
  through the release index, so every toolchain download goes through the sources the spec names. Older releases scrape
  GitHub HTML. The second proposal is the minimum, so the duplicate test's first install is replaced. Rejected: `4.0.0`
  (HTML scraping); accepting a leading `v` (`uv` and `deno` accept only `MAJOR.MINOR.PATCH`).
- **`defaultToolchain` default `stable`, empty meaning "not managed".** `stable` is what elan's installer sets. elan
  keeps it unresolved and resolves it at each use, so it follows upstream's stable channel and needs no rebuild. It
  matters for files outside a project, `lake new`, and the editor's first start. The research showed that `none` does
  not unset elan's default, so the agreed `none` became the empty value. That value also covers users who manage the
  default with `elan default` themselves. Setting it at each creation keeps the configuration as the source of truth.
  Rejected:
  - `none` as a value: elan would store `leanprover/lean4:none`, and unsetting it would mean editing elan's
    `settings.toml` by hand.
  - Default empty: standalone files and the editor would have no toolchain.
  - `ELAN_TOOLCHAIN`: it overrides every project's `lean-toolchain`.
  - Setting the default only on a new volume: the option would stop applying after the first creation.
- **`preinstallToolchains` default empty.** Each toolchain adds 3.1 GB to the image, projects pin their own, and
  toolchains elan installs at run time persist on the volume. The proposal names a fixed release, current stable at
  writing, so the duplicate test is reproducible. Rejected: a boolean that preinstalls the default toolchain (what a
  project needs is its pinned toolchain, and the default is usually a channel); one option for both purposes.
- **Toolchain names limited to the official forms**, one rule for both options. Build-time downloads then come only from
  the sources the spec names, and a value cannot point elan at an arbitrary repository's releases or at a path. elan
  rejects some combinations of prefix and name the pattern admits (`leanprover/lean4-nightly:v4.35.0`) with "no such
  release", which fails the build for `preinstallToolchains` and the first use for `defaultToolchain`. Rejected:
  accepting any name elan accepts (other origins go through HTML scraping of any GitHub repository); a bare `4.35.0`
  (upstream's names carry the `v`, as `lean-toolchain` files do).

### Storage: elan's home on the volume, build-time toolchains in the image

elan has a single home (`ELAN_HOME`) for settings and toolchains. The feature puts it on the volume
(`/var/lib/lean/elan`), so toolchains elan installs at run time survive rebuilds. Build-time toolchains live in the
image under `/usr/local/share/lean/toolchains/`, root-owned and read-only. The creation script links each one into
`/var/lib/lean/elan/toolchains/` under elan's own directory name. elan treats the link as an installed toolchain
(Context), so a project's `lean-toolchain` finds it, and uninstalling or `elan toolchain gc` removes only the link. The
next creation links it again: the image decides what is preinstalled. An entry of the same name already on the volume
wins, since it is a complete toolchain elan installed. Links into the image directory that no longer resolve are
removed, because elan would list them as installed.

Rejected:

- `ELAN_HOME` in the image, with only the caches on the volume: every rebuild downloads 570 MB again for each toolchain
  a project used.
- Build-time toolchains written into the volume path and copied into a new volume by Docker: the copy happens only for a
  new volume, so a changed option never reaches an existing one, and every new volume would duplicate 3.1 GB per
  toolchain.
- Copying build-time toolchains onto the volume at creation: 3.1 GB written per toolchain and creation.
- `elan toolchain link`: it registers a custom name that no `lean-toolchain` file refers to.
- No build-time toolchains at all: offline use, CI, and prebuilt images would always start with a download.

### elan and its proxies in `/usr/local/bin`

The archive's `elan-init` is installed as `/usr/local/bin/elan`, and the six proxies are links to it (Context). Root,
the remote user, and later features find them on the default `PATH`, and no `containerEnv` entry for `PATH` is needed.
Nothing goes into `$ELAN_HOME/bin`: binaries there would live on the volume and outlast a rebuild that changes
`elanVersion`. `elan self update` writes into `$ELAN_HOME/bin`, which is not on `PATH`, so it changes nothing.
`NOTES.md` says so and names `elanVersion`.

Rejected: upstream's `elan-init.sh` (piped into a shell, newest release only, edits profiles); running
`elan-init -y
--no-modify-path` (it installs into `$ELAN_HOME/bin`, on the volume); distribution packages (absent or
different per family); a wrapper script that blocks `self update` (elan dispatches on `argv[0]`, and a wrapper adds a
layer for no safety gain).

A target path that is a directory fails the install. A regular file or a link at a target is replaced, since the feature
owns these seven paths.

### Environment

`containerEnv` sets `ELAN_HOME=/var/lib/lean/elan`, `LAKE_CACHE_DIR=/var/lib/lean/cache/lake`, and
`MATHLIB_CACHE_DIR=/var/lib/lean/cache/mathlib`. `LAKE_CACHE_DIR` is necessary, not only convenient. Without it Lake
writes its artifact cache into the toolchain directory, which fails for a read-only build-time toolchain (Context) and
disappears with `elan toolchain gc` for a run-time one. Lake's system cache would also stay in `~/.cache`, which a
rebuild loses. Lake's artifacts are content-addressed, so one directory for all toolchains is safe; it is what Lake does
when elan is absent. Rejected: `XDG_CACHE_HOME` (it moves every tool's cache); leaving Lake's defaults (above).

### Volume, group, and repair

These follow the `uv` design's decisions "A named volume…", "Write access through a group…", "The group comes from the
image's own account tools…", and "A volume that no longer fits its user is repaired…", with these differences:

- The volume is `lean-${devcontainerId}` at `/var/lib/lean`, and the group is `lean`. The image's mount point is empty,
  owned by the remote user and the group `lean`, with mode `2775`; for a root remote user it is root's, with mode
  `0755`.
- Only the mount point carries the group. Build-time toolchains are root's and read-only, unlike `uv`'s tool directory,
  since the remote user never needs to change them.
- No BusyBox branch for the group tools: there is no Alpine image.
- The repair runs `chown -R -h -P`, because the volume holds links into the image.
- The creation script also creates the volume's directories, links build-time toolchains, and sets the default
  toolchain. A failure of any step warns and lets the creation continue, as the repair does. Lean still works without
  them; it only downloads more.
- Script and configuration: `/usr/local/share/lean-feature/initialize` is the `onCreateCommand`.
  `/usr/local/share/lean-feature/default-toolchain` holds the option's value, written at build time, so a later install
  replaces it.

The fit check walks the whole volume. On a warm page cache that takes about 0.1 s per toolchain (Context), while the
Mathlib cache adds a few thousand files. Rejected: checking only the volume's top level (the `uv` design's reasons
apply).

### elan release source and integrity

`latest` comes from the redirect of `https://github.com/leanprover/elan/releases/latest`, read without following it, as
in the `uv` design. The archive comes from the release's download URL, following GitHub's redirect over HTTPS only.
GitHub's digest is read from `https://api.github.com/repos/leanprover/elan/releases/tags/v<version>`. It is compared
when the API answers and reports one, and its absence is logged, as in the `apptainer` design. The download is skipped
when the first line of `/usr/local/bin/elan --version` names the requested release.

Rejected:

- The API for resolving `latest`: it is rate-limited for anonymous callers, and the redirect is not.
- Requiring the digest: the `4.1.x` assets have none.
- Building elan from source: it needs a Rust toolchain.

### Toolchains at build time

`install.sh` runs the installed elan with a temporary `ELAN_HOME` beside `/usr/local/share/lean/`. Its `toolchains/`
first holds links to the toolchains the image already has. The script then runs `elan toolchain install` for each listed
name. elan resolves channels itself, and finds the linked ones installed, so nothing already in the image is downloaded.
Each new directory elan created is then renamed into `/usr/local/share/lean/toolchains/`. Group and other write are
removed from every non-link entry, and the temporary home is deleted.

Rejected:

- Downloading the archives with `curl` and comparing GitHub's digest. That would reimplement elan's channel and nightly
  resolution and its `.tar.zst` unpacking (a `zstd` prerequisite), only to install what elan downloads unverified at run
  time anyway.
- Pointing elan at the final directory as its home: settings, lock files, and `known-projects` would end up in the
  image.

### Prerequisites and platforms

- **Packages.** Missing tools only, from the image's own repositories, in one transaction, and kept afterwards, as in
  the `uv` design. `find` is needed by the creation script, and git by Lake.

  | Family            | Packages                                                                                |
  | ----------------- | --------------------------------------------------------------------------------------- |
  | Debian and Ubuntu | `curl` `ca-certificates` `tar` `gzip` `git` `findutils`                                 |
  | Fedora and RHEL   | `curl` `ca-certificates` `tar` `gzip` `git-core` `findutils`                            |
  | openSUSE          | `curl` `ca-certificates-mozilla` `tar` `gzip` `git-core` `findutils`                    |
  | Arch Linux        | `curl` `ca-certificates` `tar` `gzip` `git` `findutils`, through `pacman -Syu --needed` |

  `git-core` is preferred where it exists, since it skips Perl and the extra tools. No `zstd`: elan unpacks it itself.
- **Families.** Matched by `ID` or `ID_LIKE` as in the `uv` design, without Alpine.
- **Architectures.** `uname -m` must be `x86_64` or `aarch64`.
- **C library.** musl is rejected when `/lib/ld-musl-*.so.1` exists or `ldd --version` names musl. There is no glibc
  version check. The floor depends on the toolchain a project picks, and moves with upstream, so `NOTES.md` states it
  for current toolchains instead.
- **Ordering.** `installsAfter: ghcr.io/devcontainers/features/common-utils`, as in the `uv` design.

### Editor

`customizations.vscode.extensions` requests `leanprover.lean4` and no settings. `NOTES.md` shows `-leanprover.lean4` for
users who do not want it.

### Tests

- **`test.sh`**, with defaults on every compatibility image as its remote user, checks:
  - `elan --version` against the latest-release redirect at test time;
  - the six proxies;
  - the three variables in a login shell;
  - that `/var/lib/lean` is a mount (`/proc/self/mountinfo`);
  - the volume's directories, owners, and modes, the group membership, or root's case;
  - that `elan show` names `stable` as the default;
  - that `/usr/local/share/lean/toolchains/` is empty, and that only the creation step's entries exist below
    `/var/lib/lean`;
  - the prerequisites and the package-manager caches.
- **`duplicate.sh`**, on every compatibility image. The CLI installs `elanVersion` `4.1.0`, `defaultToolchain`
  `leanprover/lean4:v4.35.0`, and `preinstallToolchains` `leanprover/lean4:v4.35.0`, then the defaults. It asserts:
  - the newest elan;
  - the build-time v4.35.0, owned by root and linked on the volume;
  - the default `stable`;
  - one group membership;
  - no group- or world-writable non-link under `/usr/local/share/lean`;
  - that `lake new` for v4.35.0, `lake build` with `LAKE_ARTIFACT_CACHE=true`, and the executable succeed, with the
    artifacts under `LAKE_CACHE_DIR`.

  This runs a toolchain on every listed image.
- **Scenarios**, with `scenarioArchitectures` `["amd64","arm64"]`:
  - **`test_offline_toolchains`**. On the base image as `vscode`, with `preinstallToolchains`
    `" leanprover/lean4:v4.35.0 , , v4.35.0 "` and `"runArgs": ["--network=none"]`, it covers:
    - two names for one toolchain, with whitespace and an empty entry;
    - a pinned project built offline;
    - the offline `stable` fallback;
    - uninstall and relink;
    - a dangling image link removed, and a foreign link and a real directory of the same name kept.
  - **`test_version_floor`**. `fedora:44` with `elanVersion` `4.1.0` and `preinstallToolchains`
    `leanprover/lean4:v4.35.0`: the minimum release resolves through the index and builds a project.
  - **`test_unmanaged_default`**. `debian:12` as root with `defaultToolchain` `""`: no default after creation, and a
    user's `elan default` survives a rerun of the creation script.
  - **`test_changed_uid`**. A `build` scenario, `FROM debian:13` with a user `developer` of UID 23456, as `developer`.
    The CLI changes the UID. The scenario then checks the group membership, the creation step's directories, the default
    toolchain, and writes as that user.
  - **`test_repair_volume`**. On the base image as `vscode` with `preinstallToolchains` `leanprover/lean4:v4.35.0`, the
    volume is filled under a foreign UID and by root, with a mode-`6755` executable and links into the image and outside
    the volume. The scenario then checks:
    - the repair;
    - that nothing under `/usr/local/share/lean` or outside the volume changes;
    - the warning without sudo, through a `sudo` stand-in that fails.
  - **`fail_contract`**. `debian:12` with defaults. Its script runs `install.sh` with `curl`, `uname`, and API
    stand-ins. Each case asserts that the targets, packages, and temporary directory are as they were:
    - every rejected form of each option;
    - a malformed redirect, an unknown release (404), a mismatched digest, and an archive without `elan-init`;
    - an unknown toolchain, which reaches the real index;
    - an architecture, a musl marker, an edited `/etc/os-release`, and a hidden package manager;
    - a missing remote user, the group as primary group, the group with another member, and a hidden `groupadd`;
    - a directory at `/usr/local/bin/elan`;
    - a failure after a new elan is staged (the creation script missing from the payload).

    The same-options repeat (no request, inode unchanged) is asserted here too, over a mount point whose setgid bit an
    install for root clears.
- **Checked by hand**, once on amd64, with the results in the PR's Validation section:
  - a rebuild with `devcontainer up --remove-existing-container` keeps a run-time toolchain and cache files;
  - two workspaces get two volumes;
  - VS Code installs the extension.
- **Checked by review only**: that elan's toolchain requests go to the URL inventory's hosts. They are elan's own code
  path, read in Context.

## Security review

- **Downloads by `install.sh`.** These are the latest-release redirect, the release API for the digest, and the elan
  archive. All are GitHub's, over HTTPS with HTTPS-only redirects. Nothing is piped to a shell.
- **Downloads by elan at build time.** These happen only when `preinstallToolchains` is set: the release index and the
  toolchain archives on upstream's hosts and GitHub (URL inventory). They rely on TLS, and elan follows redirects
  without a protocol limit. The spec states both.
- **Verification.** None is available from upstream for either artifact. GitHub's digest is compared for elan when it is
  reported. This detects corruption, and tampering after upload. It does not detect a malicious upstream release
  (review-guidance.md, accepted for every feature).
- **Build-time execution.** Only elan runs, as root, with temporary homes, to report its version and install toolchains.
  No toolchain binary runs at build time.
- **Creation-time execution.** The creation script runs as the remote user. It uses `sudo -n` only for a `chown` bounded
  to `/var/lib/lean` that follows no link, and adds no sudo rule. It removes only links that point into
  `/usr/local/share/lean/toolchains/` and no longer resolve.
- **Volume isolation.** Toolchains are executable code, and the remote user can write the volume. One volume per dev
  container keeps one project's container from changing another project's toolchains.
- **Files written as root:**
  - `/usr/local/bin/elan` and six links;
  - `/usr/local/share/lean/toolchains/` (root-only);
  - `/usr/local/share/lean-feature/{initialize,default-toolchain}`;
  - the mount point `/var/lib/lean`;
  - the group `lean`.

  Nothing is writable by every user.
- **Options.** One version and toolchain names, each matched against a fixed pattern before use. There is no path, URL,
  or origin option.
- **Metadata.**
  - `containerEnv` sets three directories.
  - `mounts` adds one named volume.
  - `onCreateCommand` runs the creation script.
  - `installsAfter` names `common-utils`.
  - VS Code customizations request one extension.

  There is no `privileged`, `capAdd`, `securityOpt`, `init`, or `entrypoint`.

## Supported images

The planned `test/lean/compatibility.json`, with `"scenarioArchitectures": ["amd64", "arm64"]`:

| Image                                              | Arch         | Why                                                                                   |
| -------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64 | The usual dev container base, remote user `vscode` with sudo; no prerequisite missing |
| `debian:12`                                        | amd64, arm64 | `apt` path with curl and git missing; root remote user                                |
| `debian:13`                                        | amd64, arm64 | The current Debian release                                                            |
| `fedora:44`                                        | amd64, arm64 | `dnf` path, newest glibc of the RHEL family                                           |
| `almalinux:9`                                      | amd64, arm64 | The oldest glibc on the list (2.34)                                                   |
| `almalinux:10`                                     | amd64, arm64 | The current RHEL-compatible release                                                   |
| `archlinux:latest`                                 | amd64        | `pacman -Syu` path; upstream publishes no arm64 image                                 |
| `opensuse/leap:16.0`                               | amd64, arm64 | `zypper` path, and `find` missing                                                     |

`ubuntu:24.04` was checked in Context and is covered by the base image. AlmaLinux 8 is left out: current toolchains fail
there.

## URL inventory

Requests made by `install.sh`:

| URL                                                                                                    | Purpose               | When                                             | Verification                                                 | Evidence (2026-11-10)                                             |
| ------------------------------------------------------------------------------------------------------ | --------------------- | ------------------------------------------------ | ------------------------------------------------------------ | ----------------------------------------------------------------- |
| `https://github.com/leanprover/elan/releases/latest`                                                   | Resolve `latest`      | Build, only for `latest`; also read by the tests | TLS; the redirect must name a `v<MAJOR>.<MINOR>.<PATCH>` tag | 302 to `/releases/tag/v4.2.4`                                     |
| `https://github.com/leanprover/elan/releases/download/v<version>/elan-<arch>-unknown-linux-gnu.tar.gz` | elan archive          | Build, unless the release is installed           | TLS on every hop; GitHub's digest when reported              | 302 to `release-assets.githubusercontent.com`, `elan-init` inside |
| `https://api.github.com/repos/leanprover/elan/releases/tags/v<version>`                                | GitHub's asset digest | Build, when downloading                          | TLS; may be absent                                           | digest for `4.2.4`, `null` for `4.1.0`                            |

Requests made by elan at build time, only when `preinstallToolchains` is not empty:

| URL                                                                                 | Purpose                                          | Verification                    |
| ----------------------------------------------------------------------------------- | ------------------------------------------------ | ------------------------------- |
| `https://release.lean-lang.org`                                                     | Release index; resolves names and channels       | TLS                             |
| `https://releases.lean-lang.org/lean4/<tag>/lean-<version>-linux[_aarch64].tar.zst` | Release toolchain                                | TLS; 302 to the next row        |
| `https://github.com/leanprover/lean4/releases/download/<tag>/…`                     | Release toolchain                                | TLS; 302 to GitHub's asset host |
| `https://github.com/leanprover/lean4-nightly/releases/download/<tag>/…`             | Nightly toolchain                                | TLS; 302 to GitHub's asset host |
| `https://release-assets.githubusercontent.com/…`                                    | GitHub's asset host for both toolchain rows      | TLS                             |
| `https://github.com/leanprover/elan/releases/latest`                                | elan's update notice; the result is only printed | TLS                             |

The creation script requests nothing. At run time, elan, Lake, and Mathlib's cache tool download what the user's
commands ask for.

## Risks / Trade-offs

- [elan and toolchains carry no upstream checksum or signature] → Accepted in the spec. The digest comparison covers
  elan where GitHub reports one.
- [elan follows a downgrade redirect from an upstream host] → Accepted in the spec. Every hop is HTTPS today, and the
  same downloads happen at run time without the feature.
- [The volume grows by about 3.1 GB per toolchain, plus Mathlib's cache] → `NOTES.md` names `elan toolchain gc` and
  removing the volume.
- [Each build-time toolchain adds about 3.1 GB to the image] → The default installs none, and `NOTES.md` states the
  size.
- [A user's `elan default` is replaced at the next creation] → Documented; the empty value hands the default to the
  user.
- [`elan self update` appears to succeed and changes nothing] → Documented, with `elanVersion` as the way to update.
- [A user who sets `ELAN_HOME` elsewhere loses the volume, the links, and the managed default] → Documented. The
  creation script still prepares `/var/lib/lean`.
- [root runs Lake, so the volume holds root-owned files] → The next creation repairs them where sudo is available, and
  warns otherwise, as in `uv`.
- [Upstream raises the glibc floor of its toolchains] → The build still succeeds, but a project fails at run time on an
  older listed image. The CI run of a later feature change shows it, and the compatibility list follows with a MAJOR
  bump.
- [The first use of `stable` needs the network] → A `stable` default falls back to an installed release offline
  (Context). `preinstallToolchains` covers offline use.
- [CI downloads a toolchain in every duplicate job and three scenarios] → About 570 MB each. That is accepted, because
  it is the only check that a toolchain runs on each listed image.
- [A release between a CI job's build and its test] → That job's comparison fails, and a re-run passes. elan releases
  are months apart.
- [Upstream renames `elan-init`, the asset names, or the release index format] → The install fails clearly, and a PATCH
  follows.

## Open Questions

None that block the approach. Whether Mathlib's cache moves to Lake's own cache service changes nothing here:
`LAKE_CACHE_DIR` and `MATHLIB_CACHE_DIR` cover both.
