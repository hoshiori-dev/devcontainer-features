# Tasks

## 1. Scaffold and metadata

- [x] 1.1 Scaffold the feature with `just new-feature deno --name "Deno"` and verify `src/deno/` and `test/deno/` hold
      the generated files
- [x] 1.2 Write `src/deno/devcontainer-feature.json`: id `deno`, version `1.0.0`, the `version` option with proposals
      `latest` and `2.8.0`, the three `containerEnv` entries (`DENO_INSTALL_ROOT`, `PATH` appended,
      `DENO_NO_UPDATE_CHECK`), and `installsAfter` common-utils without a tag, nothing else that widens the container;
      verify with `just validate` and a review against design.md (Goals, Decisions, Security review)

## 2. Install scripts

- [x] 2.1 Write `src/deno/install.sh` in POSIX `sh` with `set -eu`, holding only the platform checks (C library first,
      then the first matching family, glibc 2.27, architecture, bash) and handing over with `exec bash` to
      `src/deno/scripts/`; verify with shellcheck and the hand runs on `alpine`, Wolfi, Arch, `debian:9`, and
      `linux/s390x` (Verifying failure scenarios)
- [x] 2.2 Write the bash script with `set -euo pipefail`: validate `version` before any network access, install missing
      `curl`, a CA bundle, and `unzip` with apt, dnf, or zypper and clean the manager cache, resolve `latest` from the
      pointer with its format check, and skip the download when `/usr/local/bin/deno` already reports the resolved
      version; verify with the hand runs "Partial version rejected" and "Malformed latest-release pointer" and with the
      tests of group 3
- [x] 2.3 Implement the verified download: both checksum files fetched first, a `HEAD` request telling a missing
      checksum file from an unknown version, the name field checked and the hash compared with the feature's own
      `sha256sum` for the archive before `unzip` and for the executable before staging, atomic rename within
      `/usr/local/bin`, and an `EXIT` trap removing the temporary directory and the staging file; every `curl` call uses
      `--proto '=https' --proto-redir '=https' --fail`; verify with `grep -rn 'https\?://' src/deno` against the URL
      inventory and the hand runs for both checksum mismatches, the missing checksum files, the unknown version, and the
      failure over an existing installation
- [x] 2.4 Create `/usr/local/share/deno/bin` and apply the ownership rule (root:deno mode 2775 and group membership for
      a non-root remote user, otherwise root mode 0755, plus the login-shell profile) on every run, including the skip
      path; verify with `test.sh` on both images and the hand run with an absent remote user

## 3. Tests

- [x] 3.1 Write `test/deno/compatibility.json` with `base:ubuntu24.04` (`remoteUser` `vscode`) `debian:12`, `fedora:44`,
      `almalinux:9`, `almalinux:8`, and `opensuse/leap:16.0`, each with `"arch": ["amd64", "arm64"]`; verify with
      `just validate`
- [x] 3.2 Write `test/deno/test.sh`: `deno` resolves to `/usr/local/bin/deno` and reports the version the latest pointer
      names, the container environment (`DENO_INSTALL_ROOT`, `DENO_NO_UPDATE_CHECK`, `PATH` with the tools directory
      after the image's entries), the prerequisites installed, the tools directories owned by root with the specified
      group and mode, and `deno install --global` of a local script running by name from a new shell; verify with
      `just test deno`
- [x] 3.3 Write `test/deno/duplicate.sh` asserting that after `2.8.0` then `latest`, `deno --version` reports the
      version the latest pointer names, no staging file is left, and the tools tree exists with its owner, group, and
      mode (tools surviving a reinstall are the scenarios' part); verify with `just test deno`
- [x] 3.4 Write `test/deno/scenarios.json` with its scripts and `build` folders: an exact version checked as the remote
      user and as root on `base:ubuntu24.04`; a `debian:12` build with a stub `deno` reporting `2.8.0` and a plain tool
      in `/usr/local/share/deno/bin`, installed once with `2.8.0` (stub unchanged, tool runs) and once with `latest`
      (stub replaced, tool runs); and a `base:ubuntu24.04` build that saves the `dpkg-query -W` listing, compared after
      installation; add the UID/GID remap and AlmaLinux non-root group scenarios; verify with `just test-scenarios deno`

## 4. Documentation

- [x] 4.1 Write `src/deno/NOTES.md` (supported images by reference to the compatibility list, accepted versions and the
      checksum requirement, global tools location and ownership, update check); verify by review against the spec
- [x] 4.2 Replace "No features have been published yet." in the root `README.md` with one row for `deno` linking to
      `src/deno/` and a one-sentence description; verify by review of the diff
- [x] 4.3 Generate `src/deno/README.md` with `just docs`; verify with `just docs-check`

## 5. Integration checks

- [ ] 5.1 Run `just check` and verify it passes
- [ ] 5.2 Run `just test deno` and verify it passes on the two Debian-family images on amd64 per design.md; the four
      added images and all arm64 images run in CI
- [ ] 5.3 Run `just test-scenarios deno` and verify every scenario passes
- [ ] 5.4 Record the results of 5.1 to 5.3, the hand runs of design.md (Verifying failure scenarios), and each
      Acceptance item and spec scenario with its result in the PR's Validation section
