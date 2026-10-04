# Tasks

This file describes the baseline implementation. The same PR also carries ../configure-pacman-packages-cleanup/, a
separate phase 1 extension awaiting approval and implementation. Its delta supersedes the relevant baseline requirements
only when applied; the baseline task completion and test results do not validate its new paths.

## 1. Feature

- [x] 1.1 Scaffold `src/pacman-packages/` and `test/pacman-packages/` with `just new-feature pacman-packages` and verify
      that the generated `devcontainer-feature.json` declares exactly one option, `packages` (`string`, default `""`),
      as the Option requirement states
- [x] 1.2 Complete `src/pacman-packages/devcontainer-feature.json`: version `1.0.0`, `name`, a one-sentence
      `description`, `documentationURL`, and `packages` with the proposals `"bc"` and `"bc,tree"` and a description
      (design, Options); verify with `just validate` and `just spec-check`, and by reading the file for the absence of
      `dependsOn`, `installsAfter`, `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`,
      `containerEnv`, and lifecycle commands
- [x] 1.3 Write `src/pacman-packages/install.sh` as POSIX `sh` with `set -eu` in the design's order (parse, validate,
      the empty check, the `pacman` check, install, clean): the allowlist of decision "A strict allowlist per manager"
      matched under `LC_ALL=C`, exit 1 naming a refused entry, exit 0 for an empty list, exit 1 naming `pacman` and Arch
      Linux when `pacman` is missing (`/etc/os-release` read only for the message), one
      `pacman -Syu --needed --noconfirm --` call with the entries as separate arguments and no other option, then
      removal of the files inside `/var/cache/pacman/pkg/` and `/var/lib/pacman/sync/`; verify with `shellcheck`, by
      reviewing it against the design's Goals (no URL, download tool, `eval`, `sh -c`, unquoted entry, `pacman-key`
      call, write to a pacman configuration file, or option outside the bound), and by running its parse, validation,
      empty, and missing-`pacman` paths under `dash` and `bash` with a stub `pacman` on the `PATH`
- [x] 1.4 Write `src/pacman-packages/NOTES.md` (entry syntax and what is refused; the full system upgrade for a
      non-empty list, including replacing packages the repositories declare replaced; prebuilding and pinning the built
      image for a fixed package set; the packager key import, the hosts outside Arch Linux it may contact, and that
      fetched keys stay in the keyring without trust; the databases relying on TLS alone; option values carrying no
      untrusted `"`, `$`, or backtick; what a second install does; supported images), regenerate
      `src/pacman-packages/README.md` with `just docs`, and verify that `just docs-check` passes

## 2. Container tests

- [x] 2.1 Write `test/pacman-packages/compatibility.json` with `archlinux:latest` on `amd64`; verify with
      `just validate` and against the design's Supported images
- [x] 2.2 Write `test/pacman-packages/test.sh` for the default options (scenario "Omitted packages": none of the
      `proposals` packages installed, no sync database downloaded); verify with `shellcheck`
- [x] 2.3 Write `test/pacman-packages/duplicate.sh` (scenarios "Listed packages are installed" with the `proposals`
      list, "Different list on the second install", and "Caches are removed"): every entry of `PACKAGES` installed after
      the second, default install, and no downloaded package, signature, or sync database file left; verify with
      `shellcheck`
- [x] 2.4 Write `test/pacman-packages/scenarios.json` and one script per scenario for the Test plan's "Scenario" rows:
      "Listed packages are installed", and "Optional dependencies are left out" with `rsync` (asserting `python` is
      absent) together with "Spaces and empty entries are ignored", each also asserting "Caches are removed"; verify
      with `just validate` and `shellcheck`

## 3. Direct checks

- [x] 3.1 Write the host-side runner `test/pacman-packages/direct_checks.ts` (Deno, decision "Direct checks for what a
      scenario cannot assert"): it runs `src/pacman-packages/install.sh`, mounted read-only, as root in throwaway
      containers of every image the compatibility list names for the host's architecture and of the pinned `alpine:3.24`
      digest the Test plan names, and checks each Test plan row marked "Direct", reading package names and versions from
      the repositories at run time and taking previous versions from the Arch Linux Archive; verify with `deno check`,
      `deno lint`, and `deno fmt --check` on the file, and by reviewing that every "Direct" row of the Test plan maps to
      a check

## 4. Repository README

- [x] 4.1 Add the `pacman-packages` row under "## Features" in the root `README.md`, with the id linking to
      `src/pacman-packages/` and a one-sentence description, replacing "No features have been published yet."; verify
      with `deno fmt --check README.md` and by reading the section

## 5. Validation

- [x] 5.1 Run `just check` and verify it passes
- [x] 5.2 Run `just test pacman-packages` and verify the autogenerated and install-twice tests pass on every image of
      the compatibility list
- [x] 5.3 Run `just test-scenarios pacman-packages` and verify every scenario passes
- [x] 5.4 Run `test/pacman-packages/direct_checks.ts` on every image of the compatibility list and on the pinned
      `alpine:3.24` digest, and verify every check passes
- [ ] 5.5 Record each Acceptance item and each scenario with its test, image, architecture, and result, including the
      direct checks' output, in the PR's Validation section
