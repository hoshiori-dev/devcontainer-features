# Tasks

## 1. Scaffold, metadata, and supported images

- [x] 1.1 Scaffold `src/uv/` and `test/uv/` with `just new-feature uv --name uv` and verify it creates
      `devcontainer-feature.json`, `install.sh`, `NOTES.md`, `test.sh`, `duplicate.sh`, and `compatibility.json`
- [x] 1.2 Complete `src/uv/devcontainer-feature.json` at version `1.0.0`: `name`, `description`, `documentationURL`, the
      options `version` and `toolsToInstall` with the proposals and descriptions of the design's option table,
      `containerEnv` (the five `UV_*` variables and `PATH` with `/usr/local/share/uv/bin` prepended), the `mounts` entry
      for the volume `uv-${devcontainerId}` at `/var/lib/uv`, and `installsAfter`
      `ghcr.io/devcontainers/features/common-utils`, with no other widening metadata; verify with `just validate` and
      `just spec-check`
- [x] 1.3 Write `test/uv/compatibility.json` as planned in the design (six images; `archlinux:latest` on amd64 only; the
      Ubuntu base image with `remoteUser` `vscode`) and verify with `just validate`

## 2. Install uv

- [x] 2.1 In `src/uv/install.sh` (POSIX `sh`, `set -eu`), validate `version` and every trimmed, non-empty
      `toolsToInstall` entry, refuse tools with a pinned release older than 0.12.16, and fail on an unsupported
      architecture, an unsupported distribution, or a missing remote user, all before any download or file change;
      verify with shellcheck and review against "Option version", "Option toolsToInstall", and "Fail on unsupported
      platforms and invalid options"
- [x] 2.2 Install missing prerequisites (curl, CA certificates, tar, `sha256sum`) only from the image's repositories
      with the family's package manager (`pacman -Syu --needed` on Arch), without recommended or weak dependencies,
      cleaning package caches, and run no package manager when nothing is missing; verify with shellcheck and the
      `minimal_image` build scenario on `debian:12`, whose test compares the apt sources and keyrings with the image's
- [x] 2.3 Resolve `latest` from the redirect of `https://github.com/astral-sh/uv/releases/latest` without following it,
      skip the download when `/usr/local/bin/uv` already reports the release, otherwise download the archive of the
      container's architecture and C library and its `.sha256` over HTTPS only, verify the checksum in a temporary
      directory, and replace `uv` and `uvx` in `/usr/local/bin` by rename; verify with shellcheck and `test/uv/test.sh`
      ("Omitted version", "glibc image", "musl image", "Checksum matches")
- [x] 2.4 Create `/var/lib/uv` empty and owned by the remote user, `/usr/local/share/uv/{tools,python,bin}` owned by the
      remote user and its primary group, and `/etc/profile.d/uv.sh` (root-owned, 0644, overwritten on every install)
      that prepends `/usr/local/share/uv/bin` to `PATH` only when it is missing; verify with `test/uv/test.sh` ("New
      volume", "Environment of the remote user" in the environment and in login shells)
- [x] 2.5 Write `test/uv/test.sh` (POSIX `sh` that re-executes with bash, adding bash from `apk` when missing)
      asserting, before running uv, that `/var/lib/uv` is a mount, empty, and owned by the remote user, then the release
      and build target of `uv` and `uvx`, no build-time tool or interpreter, the environment and `PATH` order in the
      environment and in login shells, and the executable and environment "Later feature runs uv" relies on; verify with
      shellcheck
- [x] 2.6 Add the `pinned_release` scenario (`version` `0.12.16` on `alpine:3.24`) and the `minimal_image` build
      scenario (`debian:12` recording SHA-256 sums of `/etc/apt/sources.list*`, `/etc/apt/trusted.gpg*`, and
      `/usr/share/keyrings/`) to `test/uv/scenarios.json` with their scripts; verify with shellcheck and `just validate`

## 3. Build-time tools

- [x] 3.1 Install each validated `toolsToInstall` entry with `uv tool install` as root with
      `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python`, `UV_CACHE_DIR` in a temporary directory removed at the end,
      and `UV_MANAGED_PYTHON=1`, setting no index, mirror, download-metadata, or hash-policy variable or flag and
      writing no `uv.toml`, then give `/usr/local/share/uv` to the remote user; verify with shellcheck and review
      against "Verify build-time tool downloads"
- [x] 3.2 Add the `tools` scenario on the Ubuntu base image as `vscode` with two tools, surrounding whitespace, and an
      empty entry, asserting "Tools on PATH", "Tools survive a replaced volume" (interpreters under
      `/usr/local/share/uv/python`), "Remote user manages tools" (`uv tool upgrade` and `uv tool install` without sudo),
      and "Default sources" (no `UV_*` variable beyond the five the feature sets, no `uv.toml` from the feature); verify
      with shellcheck and `just validate`
- [x] 3.3 Write `test/uv/duplicate.sh` asserting "Different options": `uv --version` and `uvx --version` report the
      second (default) install's release and the first install's tools still run by name; verify with shellcheck

## 4. Runtime volume and environment

- [x] 4.1 Add the `runtime_python` scenario on the Ubuntu base image as `vscode` asserting "Runtime interpreter on the
      volume" (a `uv venv --managed-python` interpreter installed and resolving under `/var/lib/uv/python`) and
      "Workspace install across filesystems" (an install from the cache into an environment in the bind-mounted
      workspace, on another filesystem than `/var/lib/uv`, prints no link-mode fallback warning); verify with shellcheck
      and `just validate`

## 5. Documentation

- [x] 5.1 Write `src/uv/NOTES.md`: supported distribution families with their package managers (pointing to
      `test/uv/compatibility.json` and the `mcr.microsoft.com/devcontainers/base` images), the volume layout
      (`/var/lib/uv` from `uv-${devcontainerId}`, `python/` and `cache/`), the contract for later features that run uv
      at build time or install tools into `/usr/local/share/uv/tools`, build-time interpreters not visible to runtime
      uv, the download hosts with the release-asset host caveat, maintenance (`uv cache prune`, `uv python uninstall`,
      removing the volume, a volume with another owner), and the upstream references of the spec's Purpose; verify by
      review against the spec and design
- [x] 5.2 Regenerate `src/uv/README.md` with `just docs` and verify `just docs-check` passes
- [x] 5.3 Replace "No features have been published yet." in the root `README.md` with one row for `uv` under its
      "Features" heading, its id linking to `src/uv/` and a one-sentence description; verify with `deno fmt --check`

## 6. Observations in throwaway containers

- [x] 6.1 Observe the failure scenarios with the methods the design names (a `uname` stub printing `riscv64`,
      `photon:5.0`, a `curl` wrapper that alters or fails the `.sha256` request, `version` `9.9.9`, `_REMOTE_USER`
      naming no account, an unpublished tool, `version` `0.12.15` with one tool, and each invalid `version` and
      `toolsToInstall` form) and record each result in the PR's Validation section
- [x] 6.2 Observe the `dnf`, `pacman`, and `zypper` prerequisite branches on `almalinux:10`, `archlinux:latest`, and
      `opensuse/leap:16.0` with `tar` removed without its dependents, and record that `install.sh` installs `tar` and
      succeeds
- [x] 6.3 Install the feature twice in one container with identical options, and with two non-empty tool lists that list
      one tool again with another constraint, and record "Same options", "Different options", and "Tool listed again"
- [x] 6.4 Build a throwaway, uncommitted local feature that installs after `uv`, runs `uv --version`, and fails unless
      `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv/python`, and record one build ("Later feature runs uv")
- [x] 6.5 Observe "Rebuild keeps a workspace environment" on a real rebuild of one dev container and "Separate dev
      containers" on two dev containers on one Docker host, and record both

## 7. Integration

- [x] 7.1 Run `just check`, `just test uv`, and `just test-scenarios uv`, and record the results with every Acceptance
      item in the PR's Validation section
