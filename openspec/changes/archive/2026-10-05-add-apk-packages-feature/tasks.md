# Tasks

This file describes the baseline implementation. The same PR also carries ../configure-apk-packages-installation/, a
separate phase 1 extension approved in conversation on 2026-10-04 and implemented in this first release. Its delta
supersedes the relevant baseline requirements only when applied; the baseline task completion and test results do not
validate its new paths.

## 1. Feature

- [x] 1.1 Scaffold `src/apk-packages/` and `test/apk-packages/` with `just new-feature apk-packages` and verify that the
      generated `devcontainer-feature.json` declares exactly one option, `packages` (`string`, default `""`), as the
      Option requirement states
- [x] 1.2 Complete `src/apk-packages/devcontainer-feature.json`: version `1.0.0`, `name`, a one-sentence `description`,
      `documentationURL`, and `packages` with the proposals `"file"` and `"file,tree"` and a description (design,
      Options); verify with `just validate` and `just spec-check`, and by reading the file for the absence of
      `dependsOn`, `installsAfter`, `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`,
      `containerEnv`, and lifecycle commands
- [x] 1.3 Write `src/apk-packages/install.sh` as POSIX `sh` with `set -eu` in the design's order (parse, validate, the
      empty check, the `apk` check, refresh, install, clean): the allowlist from decision "A strict allowlist per
      manager" checked under `LC_ALL=C`, exit 1 naming a refused entry, exit 0 for an empty list, exit 1 naming `apk`
      and Alpine Linux when `apk` is missing (`/etc/os-release` read only for the message), a cache directory and an
      empty working directory made with `mktemp -d` and removed through a `trap`, `apk update` into that cache
      directory, which must exit 0, then one `apk add` run in the empty directory with the entries as separate arguments
      after `--`, every `apk` call carrying `--no-interactive` and `--cache-dir`; verify with `shellcheck`, by reviewing
      it against the design's Goals (no URL, download tool, `eval`, `sh -c`, unquoted entry, or listed weakening or
      upgrade option, and no `APK_CONFIG`, `SSL_*`, or proxy variable), and by running its parse, validation, empty, and
      missing-`apk` paths under `dash` and busybox `sh`
- [x] 1.4 Write `src/apk-packages/NOTES.md` (entry syntax and what is refused, the index fetched on every run and a
      failing repository failing the build, `name~prefix` instead of a pin that stops resolving, a constraint staying in
      apk's world, install-if packages, provided names, `community` on `alpine:3.22` without security fixes, option
      values carrying no untrusted `"`, `$`, or backtick, packages that add repositories or keys themselves, a second
      install, supported images), regenerate `src/apk-packages/README.md` with `just docs`, and verify that
      `just docs-check` passes

## 2. Container tests

- [x] 2.1 Write `test/apk-packages/compatibility.json` with `alpine:3.24` and `alpine:3.22`, each on `amd64` and
      `arm64`; verify with `just validate` and against the design's Supported images
- [x] 2.2 Write `test/apk-packages/test.sh` for the default options (scenario "Omitted packages": none of the
      `proposals` packages installed or in apk's world, `/var/cache/apk` empty, no feature directory left), as POSIX
      `sh` with its own `check` and `reportResults`, because the images ship no bash for the CLI's test library; verify
      with `shellcheck`
- [x] 2.3 Write `test/apk-packages/duplicate.sh` (scenarios "Listed packages are installed" with the `proposals` list
      and "Caches are removed"): every entry of `PACKAGES` installed and a line of apk's world after the second, default
      install, `/var/cache/apk` empty, and no feature directory left; verify with `shellcheck`
- [x] 2.4 Write `test/apk-packages/scenarios.json` and one script per scenario for the Test plan's "Scenario" rows:
      "Listed packages are installed" on each amd64 image, and "Install-if packages follow their conditions" with
      "Spaces and empty entries are ignored", each also asserting "Caches are removed"; verify with `just validate` and
      `shellcheck`

## 3. Direct checks

- [x] 3.1 Write the host-side runner `test/apk-packages/direct_checks.ts` (Deno, decision "Direct checks for what a
      scenario cannot assert"), whose shebang runs it with `deno run --check`: it runs `src/apk-packages/install.sh`,
      mounted read-only, as root in throwaway containers of every image the compatibility list names for the host's
      architecture, of `alpine:3.24.0` and `alpine:3.22.0` pinned by digest, and of `debian:12` pinned by digest, and
      checks each Test plan row marked "Direct", reading versions at run time and failing clearly when no installed
      package lags the repositories; verify with `deno check`, `deno lint test/apk-packages/`, and `deno fmt --check` on
      the file, and by reviewing that every "Direct" row of the Test plan maps to a check

## 4. Repository README

- [x] 4.1 Add the `apk-packages` row under "## Features" in the root `README.md`, with the id linking to
      `src/apk-packages/` and a one-sentence description, replacing "No features have been published yet."; verify with
      `deno fmt --check README.md` and by reading the section

## 5. Validation

- [x] 5.1 Run `just check` and verify it passes
- [x] 5.2 Run `just test apk-packages` and verify the autogenerated and install-twice tests pass on every image of the
      compatibility list (arm64 in CI)
- [x] 5.3 Run `just test-scenarios apk-packages` and verify every scenario passes
- [x] 5.4 Run `test/apk-packages/direct_checks.ts` on every amd64 image of the compatibility list and on the pinned
      images outside it, and verify every check passes
- [x] 5.5 Record each Acceptance item and each scenario with its test, image, architecture, and result, including the
      direct checks' output, in the PR's Validation section
