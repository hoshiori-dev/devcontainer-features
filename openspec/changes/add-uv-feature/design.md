# Design

## Context

- This is the repository's first feature to declare `mounts`, and `hf-cli` (#17) will declare `dependsOn` on it. Its
  change runs Hugging Face's standalone installer as the remote user, or as root when the remote user is root or unset,
  which installs into a virtual environment in that user's home with `uv pip install --python <venv>/bin/python`, in an
  environment `hf-cli` builds with `UV_NO_CACHE=1` and without `UV_PYTHON_INSTALL_DIR` or `UV_CACHE_DIR`, so it
  downloads no uv-managed Python and writes no cache. What this feature leaves in the image and in the build environment
  is therefore a contract for later features, not only for users.
- The Dev Container spec adds a feature's `containerEnv` to the image as `ENV` before the feature's `install.sh` runs,
  so `install.sh` and every later feature already see `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR` pointing at
  `/var/lib/uv`, while the volume is not mounted during the build. Anything written there at build time lands in the
  image's mount point: Docker copies it into a new, empty volume and hides it behind an existing one.
- When Docker creates a named volume and mounts it over an image directory, it copies that directory's contents and its
  owner and mode into the volume, only while the volume is empty (moby `copyExistingContents` into containerd continuity
  `fs.CopyDir`, whose `copyFileInfo` calls `os.Lchown`; disabled by `volume-nocopy`). A mount point owned by the remote
  user therefore yields a volume the remote user owns, with no entrypoint.
- Facts verified on 2026-09-30 against uv 0.12.21 (released 2026-09-29), the newest release:
  - Release tags have no `v` prefix. Each Linux archive `uv-<triple>.tar.gz` holds `uv-<triple>/uv` and
    `uv-<triple>/uvx` (mode 0755) and has a `<archive>.sha256` beside it in `sha256sum` text format (`<hex>  <name>`);
    for all four x86_64/aarch64 gnu/musl archives the checksum files equal the GitHub API's `digest` field, and
    `sha256sum -c` passed on the downloaded x86_64-gnu and aarch64-musl archives. The musl builds are fully static. uv
    publishes no GPG signature; GitHub artifact attestations exist for the archives.
  - The gnu builds need glibc 2.17 (x86_64) or 2.28 (aarch64) (uv's platform policy).
  - `uv --version` prints `uv <version> (<target triple>)`, which exposes both the release and the build.
  - `uv tool install` prefers a Python found on `PATH` unless managed Python is required (`UV_MANAGED_PYTHON=1`); with
    it, uv downloads a managed CPython first from `https://releases.astral.sh/github/python-build-standalone/...` and
    falls back to the same path on GitHub, checking the SHA-256 compiled into the uv binary (`HashMismatch` in
    `crates/uv-python/src/downloads.rs`). In uv 0.12.21's `download-metadata.json`, all 2828 CPython entries for Linux
    x86_64/aarch64 gnu/musl carry a SHA-256; the 5 of 5646 entries without one are wasm32 emscripten builds.
  - A tool environment links to the patch-level interpreter directory; a `uv venv` environment links to the minor-level
    directory (`cpython-3.14-...`), so a patch upgrade on the volume keeps it working, except for an environment created
    with a patch version pinned (`uv venv -p 3.x.y`), which keeps that patch.
  - Tool packages come from `https://pypi.org/simple/` and `https://files.pythonhosted.org/`. Since uv 0.12.16
    (CHANGELOG, uv PR #21562), uv checks downloaded wheels and source distributions against the hashes the index
    supplies; PyPI lists a SHA-256 for each file it links. Earlier releases do not check index-supplied hashes by
    default, and `uv tool install` has no `--require-hashes` flag. A tool install writes nothing to `$HOME` when
    `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, and `UV_CACHE_DIR` are set.
  - Installing an already installed tool again exits 0 and changes nothing; installing it with a different constraint
    (`pkg==X` or `pkg@X`) reinstalls it to satisfy the new constraint; an unconstrained repeat keeps the installed
    version.
  - With the cache and the target environment on different filesystems and no `UV_LINK_MODE`, uv prints "Failed to
    hardlink files; falling back to full copy" on every install; with `UV_LINK_MODE=copy` it prints nothing.
  - `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` ships curl, tar, `sha256sum`, CA certificates, and bash, and no
    `python3`. `debian:12` and `alpine:3.24`, pulled from the `public.ecr.aws/docker/library` mirror because Docker Hub
    rate-limited the pull: `debian:12` has tar, `sha256sum`, and bash, and lacks curl, wget, and CA certificates;
    `alpine:3.24` has busybox `wget`, tar, `sha256sum`, and CA certificates, and lacks curl and bash; root's login shell
    is `/bin/bash` and `/bin/sh` respectively.
  - `almalinux:10` (`ID_LIKE="rhel centos fedora"`, glibc 2.39), `archlinux:latest` (`ID=arch`, glibc 2.44), and
    `opensuse/leap:16.0` (`ID_LIKE="suse opensuse"`, glibc 2.40) ship curl, tar, `sha256sum`, CA certificates, and bash;
    their curl reads the `releases/latest` redirect with `--proto '=https' --proto-redir '=https'` (302 to the 0.12.21
    tag), and root's login shell is bash. `almalinux:10` and `opensuse/leap:16.0` publish amd64 and arm64 images;
    `archlinux:latest` publishes amd64 only (`docker buildx imagetools inspect`). The Arch image ships no package
    database, so `pacman -S` finds no package until a `-Sy`, and Arch supports a sync only together with a full upgrade
    (`-Syu`). Photon OS (`photon:5.0`, `ID=photon`, no `ID_LIKE`) belongs to none of the families.
  - `/etc/profile` of `debian:12`, `alpine:3.24`, and `opensuse/leap:16.0` sets `PATH` to a fixed list, so a login shell
    started inside the container drops a directory that `containerEnv` put in `PATH`; `/etc/profile` of the Ubuntu base
    image, `almalinux:10`, and `archlinux:latest` does not. Every profile sources `/etc/profile.d/*.sh` afterwards, and
    a snippet there that adds the directory when it is missing restored it on all six images, for `sh -l`, `bash -li`,
    and a login shell started with an empty environment. The devcontainer CLI (0.89.0) merges the container's `PATH`
    back into the environment its `userEnvProbe` reads from a login shell, so processes the CLI starts
    (`devcontainer exec`, the test scripts, the editor's server) keep the directory without the snippet.
  - The CLI's `dev-container-features-test-lib` (0.89.0) is a bash script (`#!/bin/bash`, arrays), and the CLI runs
    `./test.sh` and `./<scenario>.sh` through `devcontainer exec`, so the script's shebang decides the interpreter.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `sh` (`#!/bin/sh`, `set -eu`), because `alpine:3.24` ships no bash. Checked by shellcheck in
  `just check` and by the alpine jobs.
- Every option value is validated before any network access or file change: `version` against `latest` or
  `^[0-9]+\.[0-9]+\.[0-9]+$`, and each trimmed, non-empty `toolsToInstall` entry against a package name with at most one
  bracketed extra and at most one constraint (`==`, `~=`, `!=`, `>=`, `<=`, `>`, `<`, or `@` followed by a version), so
  no entry can become a uv option, a URL, a path, or a shell word split. A non-empty tool list with a pinned `version`
  below 0.12.16 fails at the same point; with `latest`, the resolved release is compared before the archive is
  downloaded. Checked during implementation by building with each invalid form from the spec's scenarios and recording
  the failures in the PR's Validation section.
- Nothing from a download is used before its checksum passes, and a failed download or check leaves a previously
  installed `uv` and `uvx` untouched: the archive is verified and unpacked in a temporary directory, and the binaries
  replace the old ones by rename within `/usr/local/bin`. The two renames are not atomic as a pair: a failure between
  them, which needs a failing `mv` on one filesystem, would leave `uv` and `uvx` at different releases until the next
  install. Checked by a local run with a corrupted `.sha256` recorded in the PR.
- Build-time uv runs with the sources and checks of the "Verify build-time tool downloads" requirement: `install.sh`
  sets no index, mirror, download-metadata, or hash-policy variable, passes no such flag, and writes no `uv.toml`; an
  image that already configures uv (its own environment or `/etc/uv/uv.toml`) keeps that configuration. Checked by
  review of `install.sh` and by a scenario asserting that the container environment carries no such variable from the
  feature.
- The image's `/var/lib/uv` is empty and owned by the remote user when this feature's install ends; build-time uv runs
  with `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python`, `UV_CACHE_DIR` in a temporary directory removed at the end,
  and `UV_MANAGED_PYTHON=1`, so tool interpreters are uv-managed and in the image regardless of any system Python.
  Checked by `test.sh`, which asserts, before running uv, that `/var/lib/uv` is a mount, empty, and owned by the remote
  user, and by a tools scenario asserting that each tool's interpreter resolves under `/usr/local/share/uv/python`.
- The build-time layout under `/usr/local/share/uv/` (`tools`, `python`, `bin`) is owned by the remote user and that
  user's primary group when the remote user is not root, so the remote user can run `uv tool` at runtime (Open
  Questions, item 1). Checked by a scenario running as `vscode` that upgrades a tool.
- `/usr/local/share/uv/bin` stays in `PATH` in login shells: `install.sh` writes `/etc/profile.d/uv.sh`, a file this
  feature owns and overwrites on every install, which puts the directory at the front of `PATH` only when it is missing,
  and sets nothing else (Open Questions, item 5). Checked by `test.sh` asserting the `PATH` of `sh -lc` on every image.
- A second install is decided by `uv --version` of `/usr/local/bin/uv`: the same release skips the download; another
  release replaces both binaries; tools are installed with `uv tool install` into the same `UV_TOOL_DIR`, which keeps
  earlier tools. Checked by `duplicate.sh` (other `version` and tools first, defaults with an empty tool list second),
  and by running `install.sh` twice in one throwaway container, once with identical options and once with two non-empty
  tool lists that list one tool again with another constraint, recorded in the PR.
- Prerequisites (curl, CA certificates, tar, `sha256sum`) are installed only when missing, from the image's configured
  repositories through the family's package manager (`apt-get`, `dnf`, `pacman -Syu --needed`, `apk`, or `zypper`),
  non-interactively and without recommended or weak dependencies where the manager has such a setting, with package
  caches cleaned afterwards, and stay in the image; when nothing is missing, no package manager runs. Checked by the
  `debian:12` and `alpine:3.24` jobs, which lack curl, and by a `build` scenario on `debian:12` whose Dockerfile records
  a SHA-256 of every file under `/etc/apt/sources.list*`, `/etc/apt/trusted.gpg*`, and `/usr/share/keyrings/`, which the
  scenario test compares with the built image. The `dnf`, `pacman`, and `zypper` images lack no prerequisite, so their
  branches are observed during implementation in a throwaway container of each image with `tar` removed without its
  dependents (`rpm -e --nodeps`, `pacman -Rdd`), running `install.sh` and recording in the PR that it installs `tar` and
  succeeds.
- `test.sh`, `duplicate.sh`, and the scenario scripts are POSIX `sh` that re-execute themselves with bash before
  sourcing the bash-only test library; on an image without bash they first add it from the image's `apk` repositories,
  inside the test container only. Checked by shellcheck and by the `alpine:3.24` jobs.
- Failure scenarios a successful build cannot show are produced in a throwaway container running `install.sh`: an
  unsupported architecture with a `uname` stub earlier on `PATH` that prints another machine name (for example
  `riscv64`); an unsupported distribution on an image outside the supported families (Photon OS, `photon:5.0`); a
  mismatching or missing checksum with a `curl` wrapper earlier on `PATH` that alters or fails only the `.sha256`
  request; a missing release with an unpublished version such as `9.9.9`; a missing remote user with `_REMOTE_USER`
  naming no account; an uninstallable tool with an unpublished package name; an old release with tools with `version`
  `0.12.15` and one tool. Each result is recorded in the PR.
- Later features find `uv` and this feature's environment during their install, because `containerEnv` is written as
  image `ENV` before they install (Context). Checked by a throwaway local feature, not committed, that installs after
  this one, runs `uv --version`, and fails unless `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv/python`; one build of it is
  recorded in the PR. From `hf-cli`'s change (#17) on, its global scenario `uv_and_hf_cli` checks this again: its build
  fails unless `hf-cli`'s install runs `uv`, and its runtime value of the variable is the one later features saw, by the
  same `ENV` fact.
- `NOTES.md` gives users the facts they check before adopting the feature: the supported distribution families with
  their package managers, pointing to `test/uv/compatibility.json` for the tested images and to the
  `mcr.microsoft.com/devcontainers/base` images of those families; the layout of the volume (`/var/lib/uv`, mounted from
  `uv-${devcontainerId}`, with `python/` as `UV_PYTHON_INSTALL_DIR` and `cache/` as `UV_CACHE_DIR`); and the upstream
  references of the spec's Purpose. Checked by review of `NOTES.md` against the spec.
- Nothing a rebuild replaces holds a path a workspace `.venv/` links to: interpreters uv installs at runtime exist only
  on the volume. Checked by the rebuild observation in the proposal's Acceptance.

**Non-Goals:**

- Creating or syncing a project environment at build time, setting `UV_PROJECT_ENVIRONMENT`, or installing a system
  Python through the distribution's package manager (the issue's Out of scope). The workspace `.venv/` stays where uv
  puts it.
- Persisting tools installed at runtime: their environments live in the image's `UV_TOOL_DIR` and go with a rebuild
  (their interpreters, on the volume, stay).
- Persisting executables that `uv python install` places in `~/.local/bin`; uv's default stays.
- Repairing a volume that already exists with another owner (Open Questions, item 2).
- Podman: whether it copies the mount point's owner into a new volume was not verified; the compatibility list names
  Docker-run images only.
- Architectures other than x86_64 and aarch64, which have no CI runner here.

## Options

The feature has two options, both new in this change; the spec's Option requirements state them.

| Name             | Type     | Default    | Enum or proposals                | Meaning                                                                                                                            |
| ---------------- | -------- | ---------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `version`        | `string` | `"latest"` | proposals `["latest","0.12.16"]` | The uv release to install: `latest`, the newest release at build time, or one release as `MAJOR.MINOR.PATCH`                       |
| `toolsToInstall` | `string` | `""`       | proposals `["","pycowsay"]`      | Python command-line tools to install at build time, comma-separated, each a package name with at most one extra and one constraint |

- **Default `latest` for `version`.** A configuration that omits `version` follows upstream releases without a feature
  release for each; a pinned `version` gives reproducible builds (Risks). The Acceptance runs "Omitted version" in
  `test.sh`, which installs the defaults. Proposals, not an enum: every published release is valid, and each new release
  adds one. `0.12.16`, the oldest release allowed with tools (Decisions), differs from what `latest` resolves to, so the
  second install of `duplicate.sh`, with the defaults, takes the replace path.
- **Default empty `toolsToInstall`.** The default image downloads no interpreter and reaches none of URL inventory rows
  5–8, and `duplicate.sh` installs the defaults second with an empty tool list (Goals). `pycowsay` is the small tool
  verified in the URL inventory; it gives the first install of `duplicate.sh` a tool to keep.
- **Rejected shapes.** An enum of uv releases (every uv release would need a feature release, and `latest` would be
  impossible); options for a package index, a mirror, a Python download source, or a hash policy (they would let
  configuration redirect or weaken verified downloads, against "Verify build-time tool downloads"); one option per tool
  or a JSON list (options are `boolean` or `string`; a comma-separated list matches the first-party Python feature's
  `toolsToInstall`, with the limit in Risks).
- **Not in this change, pending Open Questions item 4.** An option for the Python version of build-time tools. The
  recommendation there is to leave it out, so this table does not list it; if the maintainer decides otherwise, the
  table and the delta spec gain it before implementation.

## Decisions

- **Release archive from GitHub Releases, verified against its per-archive `.sha256`.** Rejected: uv's `uv-installer.sh`
  (the download rules in `.agents/knowledge/feature-authoring.md` would allow it only saved to a file before it runs,
  with the spec stating that its content is not verified unless upstream publishes a checksum for it; it downloads the
  same archives and also edits shell rc files, so it adds a script to trust and a side effect with no gain);
  `pip`/`pipx` (need a system Python the images lack); distribution packages (not packaged for every supported
  distribution, and not pinnable to an upstream release); the same archives from `releases.astral.sh`, which uv's own
  installer uses (a second host with no gain once the checksum is checked); the aggregate `sha256.sum` (binary-mode
  `*name` lines, one file for all targets); pinning checksums inside the feature (every uv release would need a feature
  release, and `latest` would be impossible); verifying GitHub artifact attestations (needs `gh` or a Sigstore verifier
  the images lack, one more download to trust; a later MINOR can add it).
- **Resolve `latest` from the redirect of `https://github.com/astral-sh/uv/releases/latest`, read without following
  it**, so the release tag page is never fetched. Rejected: the GitHub REST API (60 unauthenticated requests per hour
  per IP, shared by CI runners); `releases/latest/download/<asset>` (the version is unknown before downloading, so the
  same-version skip is impossible, and the archive and checksum could come from two releases at a release boundary).
- **curl as the download tool on every distribution.** It reports a redirect target without following it, restricts
  every request and redirect to HTTPS, and fails on HTTP errors, identically on glibc and musl images. Rejected: busybox
  `wget` on Alpine (no redirect-target output, a second code path to test). Prerequisites the feature installs stay in
  the image: removing them could remove a package the image, the user, or a later feature relies on, and a second
  install would add them again.
- **gnu or musl chosen by the C library, not by the distribution:** musl when `/lib/ld-musl-*.so.1` exists, gnu
  otherwise. Rejected: the musl build everywhere (static and portable, but its name resolution ignores glibc's
  `/etc/nsswitch.conf`, a behavior difference users would not expect on Debian or Ubuntu).
- **uv at `/usr/local/bin`, tool executables in `/usr/local/share/uv/bin` added to `PATH` through `containerEnv`, and
  through `/etc/profile.d/uv.sh` for login shells.** `/usr/local/bin` is on `PATH` everywhere, and a separate tool
  directory means a tool can never overwrite `uv`. Rejected: `~/.local/bin` (`containerEnv` cannot name the remote
  user's home, and it is not on `PATH` on every image); editing `/etc/profile`, `/etc/bash.bashrc`, or other shared
  files (a file of the feature's own is replaced whole on a second install); narrowing the spec to processes the CLI
  starts (a login shell or `su -` in a Debian or Alpine container would lose the tools).
- **Build-time tools and their interpreters in `/usr/local/share/uv/{tools,python}` in the image; runtime interpreters
  and the cache on the volume.** Rejected: build-time interpreters on the volume (absent at build time, and a non-empty
  volume hides whatever the build put in the mount point, so tools would point at nothing after the first rebuild); a
  system Python for tools (varies by image, and another feature may replace it).
- **Tools only with uv 0.12.16 or later.** Earlier releases install packages from PyPI with TLS only. The download rules
  in `.agents/knowledge/feature-authoring.md` accept a registry package because the tool that fetches it verifies it,
  and accept TLS alone only for a direct download whose upstream publishes no checksum; PyPI supplies a SHA-256 for
  every file, and uv checks it only from 0.12.16 on. Rejected: accepting older releases as a documented exception (Open
  Questions, item 6); pinning hashes through a constraints file (not verified that `uv tool install` enforces them, and
  the user's list would need hashes).
- **A named volume `uv-${devcontainerId}` at `/var/lib/uv`, one per dev container.** `${devcontainerId}` is allowed in a
  feature's `mounts` and stable across rebuilds; the first-party docker-in-docker and powershell features use the same
  pattern. Rejected: one volume shared by all dev containers (owners differ between projects, and one project's cache
  and interpreters would leak into another); a host bind mount (depends on a host path); no mount (the issue's problem).
- **Ownership through the mount point, not at runtime.** The image's `/var/lib/uv` is created empty and owned by
  `_REMOTE_USER`, and Docker copies that owner into the new volume. Rejected: an `entrypoint` or `postStartCommand` that
  runs `chown` (runs as root on every start, widens metadata, and cannot run as root in every setup); making the volume
  world-writable.
- **`UV_LINK_MODE=copy`.** The cache volume and the workspace bind mount are always different filesystems, so the
  default `clone` always falls back to copying and warns on every install. Rejected: the default (the warning);
  `hardlink` (impossible across filesystems); `symlink` (uv discourages it: cleaning the cache breaks environments).
- **Distribution families, by `ID` or `ID_LIKE` in `/etc/os-release`: Debian/Ubuntu (`debian`, `ubuntu`) with `apt`,
  RHEL/Fedora (`rhel`, `centos`, `fedora`) with `dnf`, Arch Linux (`arch`) with `pacman`, Alpine (`alpine`) with `apk`,
  and openSUSE/SUSE (`suse`, `opensuse`, or an `ID` starting with `opensuse`) with `zypper`; anything else fails**
  (maintainer decision, replacing Open Questions item 3). The distribution matters only for installing prerequisites, so
  a family costs one package-manager branch and one compatibility image. Rejected: Debian/Ubuntu and Alpine only, with
  other families as later MINORs; proceeding on any distribution that already has the prerequisites (a missing one would
  then fail late, with no package manager to install it).
- **On Arch Linux, `pacman -Syu --needed` only when a prerequisite is missing.** Arch supports no partial upgrade, and
  its image ships no package database. Rejected: `pacman -Sy <pkg>` (a partial upgrade, which Arch does not support);
  failing on Arch when a prerequisite is missing (the image lacks none today, but a slimmer Arch image would fail).
- **`installsAfter: ghcr.io/devcontainers/features/common-utils`**, so a remote user that feature creates exists before
  ownership is set. No `dependsOn`: nothing is needed from another feature.

## Security review surface

| Surface               | Bound                                                                                                                                                                                                                                                                                                                                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Downloads             | HTTPS only; exactly the URLs in the URL inventory; no installer script; no URL, path, or option from a user option reaches curl or uv (validation above).                                                                                                                                                                                                                                                  |
| Verification          | uv archive: SHA-256 from the same release's `.sha256`, checked before unpacking. `latest` redirect: TLS alone, stated in the spec's "Verify the uv release before installing it". Managed interpreters: SHA-256 compiled into uv, checked by uv. PyPI packages: SHA-256 supplied by the index, checked by uv 0.12.16 or later; the feature refuses tools with an older release and adds no pin of its own. |
| Keys                  | None. uv publishes no signing key; the feature installs no repository key.                                                                                                                                                                                                                                                                                                                                 |
| `mounts`              | One named volume `uv-${devcontainerId}` → `/var/lib/uv`, needed so interpreters and cache survive a rebuild; no bind mount, no host path.                                                                                                                                                                                                                                                                  |
| `containerEnv`        | `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_LINK_MODE`, and `PATH` with `/usr/local/share/uv/bin` prepended; nothing secret, nothing that changes an index or a download source.                                                                                                                                                                                        |
| Shell startup         | `/etc/profile.d/uv.sh` (root-owned, mode 0644) prepends `/usr/local/share/uv/bin` to `PATH` when it is missing; nothing else.                                                                                                                                                                                                                                                                              |
| `installsAfter`       | `ghcr.io/devcontainers/features/common-utils` (ordering only).                                                                                                                                                                                                                                                                                                                                             |
| `dependsOn`           | None.                                                                                                                                                                                                                                                                                                                                                                                                      |
| Not used              | `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, lifecycle commands.                                                                                                                                                                                                                                                                                                                           |
| Files owned by a user | `/var/lib/uv` (empty mount point) and `/usr/local/share/uv/` belong to the remote user when it is not root (Open Questions, item 1).                                                                                                                                                                                                                                                                       |
| Idempotency           | Same release skips the download; binaries replaced by rename; tool installs are additive; `/etc/profile.d/uv.sh` overwritten whole; directories created only if missing.                                                                                                                                                                                                                                   |
| Failure behavior      | As in the spec's "Fail on unsupported platforms and invalid options", "Verify the uv release before installing it", "Option version", and "Option toolsToInstall"; a remote user that does not exist fails the install.                                                                                                                                                                                    |

Planned `test/uv/compatibility.json`:

```json
{
  "images": [
    {
      "image": "mcr.microsoft.com/devcontainers/base:ubuntu-24.04",
      "arch": ["amd64", "arm64"],
      "remoteUser": "vscode"
    },
    { "image": "debian:12", "arch": ["amd64", "arm64"] },
    { "image": "alpine:3.24", "arch": ["amd64", "arm64"] },
    { "image": "almalinux:10", "arch": ["amd64", "arm64"] },
    { "image": "archlinux:latest", "arch": ["amd64"] },
    { "image": "opensuse/leap:16.0", "arch": ["amd64", "arm64"] }
  ]
}
```

The first entry covers glibc with a non-root remote user, the second glibc as root on a minimal image, the third musl.
The last three cover the `dnf`, `pacman`, and `zypper` families, each with a root remote user on the distribution's own
image. Arch Linux publishes no arm64 image, so `archlinux:latest` runs on amd64 only; its rolling `latest` tag is the
only one upstream maintains. Fedora belongs to the RHEL/Fedora family without an image of its own: it shares `dnf` with
`almalinux:10` and adds no C library.

## URL inventory

Every URL the feature's scripts access. The feature has no start-time script, so nothing is fetched at start. The
feature configures no package repository: prerequisites come from the repositories the image already has. Rows 5–8 are
accessed at build time only when `toolsToInstall` is not empty, by uv itself on the feature's behalf; the same hosts
serve the remote user's own uv commands at runtime.

| #  | URL / template                                                                                                                                          | Purpose                                                                         | When                                                 | Integrity / authenticity                                                                               | Official source evidence                                                                                                                                  | Verified                                                                                                                                                                             |
| -- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1  | `https://github.com/astral-sh/uv/releases/latest`                                                                                                       | Resolve `latest` to a release name; the redirect is read, not followed          | Build, `version` = `latest`                          | TLS alone (a spec Requirement); the redirect target's last path segment must match `MAJOR.MINOR.PATCH` | https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases                                                                  | 2026-09-30: 302 to `https://github.com/astral-sh/uv/releases/tag/0.12.21`                                                                                                            |
| 2  | `https://github.com/astral-sh/uv/releases/download/<version>/uv-<x86_64\|aarch64>-unknown-linux-<gnu\|musl>.tar.gz`                                     | uv release archive                                                              | Build, unless the release is already installed       | SHA-256 from row 3, checked before unpacking                                                           | https://docs.astral.sh/uv/getting-started/installation/ ("GitHub Releases"); https://github.com/astral-sh/uv/releases                                     | 2026-09-30: `0.12.21`, all four builds 200, final host `release-assets.githubusercontent.com`, `sha256sum -c` OK for x86_64-gnu and aarch64-musl; an unpublished version returns 404 |
| 3  | Row 2 + `.sha256`                                                                                                                                       | Checksum of the archive                                                         | Build, with row 2                                    | TLS; same release as the archive (integrity, not independent authenticity)                             | https://github.com/astral-sh/uv/releases (each archive lists its `.sha256`)                                                                               | 2026-09-30: all four 200, final host `release-assets.githubusercontent.com`, format `<hex>  <name>`, equal to the API `digest`                                                       |
| 4  | `https://release-assets.githubusercontent.com/github-production-release-asset/<id>/<uuid>?<signed query>`                                               | Redirect target of rows 2, 3, and 6                                             | Build, with those rows                               | Short-lived URL signed by GitHub; content checked as in the originating row                            | https://docs.github.com/en/actions/reference/runners/self-hosted-runners (lists the host)                                                                 | 2026-09-30: final host of rows 2, 3, 6, 200                                                                                                                                          |
| 5  | `https://releases.astral.sh/github/python-build-standalone/releases/download/<build>/cpython-<version>%2B<build>-<triple>-install_only_stripped.tar.gz` | Managed CPython for build-time tools (uv's first choice)                        | Build, `toolsToInstall` not empty                    | SHA-256 compiled into the uv binary, checked by uv                                                     | https://docs.astral.sh/uv/reference/environment/ (`UV_ASTRAL_MIRROR_URL`); https://github.com/astral-sh/uv/blob/0.12.21/crates/uv-python/src/downloads.rs | 2026-09-30: 3.14.7, all four triples 200 on `releases.astral.sh` with no redirect; uv 0.12.21 fetched from it in a local `uv tool install`                                           |
| 6  | `https://github.com/astral-sh/python-build-standalone/releases/download/<build>/<same file as row 5>`                                                   | Fallback when row 5 fails                                                       | Build, `toolsToInstall` not empty, row 5 unavailable | As row 5                                                                                               | https://docs.astral.sh/uv/reference/environment/ (`UV_PYTHON_INSTALL_MIRROR`); `crates/uv-python/src/downloads.rs` as in row 5                            | 2026-09-30: 3.14.7, all four triples 200, final host `release-assets.githubusercontent.com`                                                                                          |
| 7  | `https://pypi.org/simple/<package>/`                                                                                                                    | Resolve each tool and its dependencies                                          | Build, `toolsToInstall` not empty                    | TLS; supplies the SHA-256 of each file in row 8                                                        | https://docs.astral.sh/uv/concepts/indexes/ (PyPI is the default index); https://docs.pypi.org/api/index-api/                                             | 2026-09-30: `pycowsay` 200 on `pypi.org`; uv 0.12.21 requested it in a local run                                                                                                     |
| 8  | `https://files.pythonhosted.org/packages/<path>`                                                                                                        | Distribution files and their metadata                                           | Build, `toolsToInstall` not empty                    | SHA-256 from row 7, checked by uv 0.12.16 or later; the feature adds no pin                            | https://docs.pypi.org/api/index-api/ (index responses link files on this host)                                                                            | 2026-09-30: `pycowsay-0.0.0.2-py3-none-any.whl` and its `.metadata` 200 on `files.pythonhosted.org`                                                                                  |
| 9  | The image's configured `apt`, `dnf`, `pacman`, `apk`, or `zypper` repositories                                                                          | curl, CA certificates, tar, `sha256sum` when missing                            | Build, only when a prerequisite is missing           | The distribution's signed repository metadata, with keys the image already has                         | Not configured by this feature                                                                                                                            | Not applicable                                                                                                                                                                       |
| 10 | `ghcr.io/devcontainers/features/common-utils` (OCI, `installsAfter`)                                                                                    | Ordering only; this feature never fetches it, the CLI does if the user lists it | Build (Dev Container CLI)                            | OCI digests, verified by the CLI                                                                       | https://github.com/devcontainers/features/tree/main/src/common-utils                                                                                      | 2026-09-30: anonymous GHCR tag list 200, tags include `2`                                                                                                                            |

## Risks / Trade-offs

- [The `.sha256` comes from the same release as the archive, so a compromised release passes] → TLS to GitHub and
  GitHub's release storage are the trust root; attestation verification is the named upgrade path (Decisions).
- [`latest` changes what a rebuild installs] → `version` pins a release; the same-version skip keeps a repeated install
  of one release offline.
- [`test.sh` compares `uv --version` with `releases/latest` at test time, so a release published between the build and
  the test fails the job] → The window is minutes; a rerun clears it.
- [A later feature that runs uv at build time as root without its own directories writes into `/var/lib/uv` in the
  image. Docker copies those root-owned files into every new volume, so the remote user's uv fails with permission
  denied on the cache or interpreter directory, and the volume no longer holds only what the remote user wrote] →
  `NOTES.md` states the contract for dependents: the paths under `/var/lib/uv` are for runtime only, and a feature that
  runs uv at build time, as any user, keeps uv's interpreter and cache writes out of it: it downloads no managed Python
  (for example `uv pip install --python <interpreter>`) or sets its own `UV_PYTHON_INSTALL_DIR` outside it, and it sets
  `UV_NO_CACHE=1` or a temporary `UV_CACHE_DIR`. `hf-cli`'s change (#17) follows it (Context) and adds the global
  scenario `uv_and_hf_cli`, which installs both features and asserts that uv installed `hf-cli`'s package, that
  `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv/python`, and that `/var/lib/uv` is a mount, empty, and owned by the remote
  user in a container started with a new volume.
- [A dependent that installs tools as root into `/usr/local/share/uv/tools` leaves root-owned environments in a
  directory the remote user owns, so the remote user's `uv tool upgrade --all` fails on them] → `NOTES.md` asks
  dependents to give such environments the remote user as owner, as this feature does, or to use their own tool
  directory (Open Questions, item 7).
- [Interpreters installed at build time for tools are not visible to runtime uv, whose `UV_PYTHON_INSTALL_DIR` is the
  volume, so a runtime `uv venv` or `uv python list` does not see them and downloads a matching version again] → A
  deliberate trade-off: the volume must hold nothing from the build. `NOTES.md` states it.
- [GitHub has moved its release-asset host before (`objects.githubusercontent.com`,
  `github-releases.githubusercontent.com`), so an allow-list that names only row 4's host breaks when that happens
  again] → `NOTES.md` lists the hosts of the URL inventory with that caveat.
- [The volume grows as uv versions change cache layouts and interpreters accumulate] → `NOTES.md` documents
  `uv cache prune`, `uv python uninstall`, and removing the volume (`docker volume rm uv-<devcontainerId>`), which also
  outlives a deleted dev container.
- [Test runs leave one named volume per test container on the machine that ran them] → CI runners are discarded;
  locally, `docker volume prune` removes them.
- [If `devcontainer features test` does not apply feature `mounts`, the mount assertions in `test.sh` fail] → That
  failure is the signal; the implementation reports it before changing the assertions.
- [A comma-separated option cannot express an extra list or a constraint that contains a comma (`pkg[a,b]`,
  `pkg>=1,<2`)] → The same limitation as the first-party Python feature's `toolsToInstall`; a single constraint or
  `pkg@version` covers pinning.
- [Build-time tools run on the interpreter uv chooses by default] → A tool that cannot run on it fails the build visibly
  (Open Questions, item 4).

## Open Questions

Decisions for the maintainer, each with a recommendation:

1. **Who owns `/usr/local/share/uv/`, and where its `bin` goes in `PATH`.** Owning it as the remote user lets
   `uv tool install` and `uv tool upgrade` work at runtime without sudo, but it puts a user-writable directory at the
   front of `PATH` for every process, including root shells (not `sudo`, whose `secure_path` ignores it).
   Recommendation: remote-user ownership, prepended — the remote user of a dev container can usually become root anyway,
   and appending would let an image's older copy of a tool win. The spec's "Remote user manages tools" scenario and its
   `PATH` order ("ahead of `/usr/local/bin` and `/usr/bin`") encode this recommendation, so approving the spec decides
   it. The alternative is root ownership (runtime `uv tool` then needs sudo, and "Remote user manages tools" is dropped)
   or appending.
2. **A volume that already exists with another owner** (the remote user changed). Recommendation: no runtime fix;
   `NOTES.md` documents removing the volume. An `entrypoint` that runs `chown` would widen metadata for a rare case.
3. **Distribution families.** Decided by the maintainer: Debian/Ubuntu, RHEL/Fedora, Arch Linux, Alpine, and
   openSUSE/SUSE, each with its image in the compatibility list (Decisions); anything else fails.
4. **An option for the Python version of build-time tools** (for example `toolsPythonVersion`). Recommendation: not now;
   uv's default interpreter is enough for the known consumers, and an option can arrive as a MINOR.
5. **`PATH` in login shells on images whose `/etc/profile` resets it** (`debian:12`, `alpine:3.24`,
   `opensuse/leap:16.0`). Recommendation: `/etc/profile.d/uv.sh`, as specified. The alternative is no snippet and a spec
   narrowed to processes the dev container tooling starts, with the gap documented in `NOTES.md`.
6. **Tools with a uv release older than 0.12.16**, which installs PyPI packages with TLS only. Recommendation: fail the
   build, as specified. The alternative is to allow it as an explicit exception to the download rules in
   `.agents/knowledge/feature-authoring.md` (a registry package installed on TLS alone), stated as a Requirement in the
   spec and documented in `NOTES.md`.
7. **The contract for dependents that install tools into `/usr/local/share/uv/tools`.** No planned dependent does:
   `hf-cli` (#17) installs into a virtual environment in the remote user's home through Hugging Face's installer and
   uses neither `UV_TOOL_DIR` nor `UV_TOOL_BIN_DIR`. Recommendation: `NOTES.md` asks a future dependent that installs
   tools there to give them the owner this feature uses, so the remote user's `uv tool upgrade --all` keeps working. The
   alternative is a separate tool directory per dependent, with its own `bin` on `PATH`.
