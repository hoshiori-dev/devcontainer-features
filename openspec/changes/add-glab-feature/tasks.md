# Tasks

## 1. Scaffold and metadata

- [x] 1.1 Run `just new-feature glab --name "GitLab CLI (glab)"` and verify it creates `src/glab/` and `test/glab/`
- [x] 1.2 Fill `src/glab/devcontainer-feature.json`: version `1.0.0`, the name `GitLab CLI` (the generated README
      appends the id), a one-sentence description, and the `version` option as the spec's `Option version` requirement
      declares it (type `string`, default `"latest"`, no `enum`) with design.md's proposals `["latest", "1.47.0"]`; no
      `containerEnv`, `dependsOn`, `installsAfter`, `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`,
      `entrypoint`, or lifecycle command. Verify by reading the file against design.md (Options, Security review), by
      `just validate`, and by `just spec-check`, which compares the option with `Option version`
- [x] 1.3 Write `test/glab/compatibility.json` with the four images of design.md (Supported images), each with
      `"arch": ["amd64", "arm64"]` and `"remoteUser": "vscode"` on the Ubuntu base only; verify by `just validate`

## 2. install.sh

- [x] 2.1 Write `src/glab/install.sh` as POSIX `#!/bin/sh` with `set -eu`: validate `version` (`latest` or
      `v?MAJOR.MINOR.PATCH`, minimum `1.47.0`; an empty value is rejected, not read as `latest`), map the architecture,
      detect the family from `/etc/os-release` `ID` or `ID_LIKE` and require its package manager, all before any package
      install or download; verify by shellcheck in `just check` and by reading the script against the `Option version`
      and "Supported platforms" requirements (behavior: 2.5)
- [x] 2.2 Install only the missing ones of `git`, `curl`, `ca-certificates`, and `tar` non-interactively and clean the
      package-manager cache (apt lists removed, `dnf clean all`, `apk add --no-cache`); verify by reading the script
      against design.md (Goals) (behavior: `test.sh`'s cache assertion in 5.2)
- [x] 2.3 Resolve `latest` from the permanent link's redirect without following it, download `checksums.txt` and the
      archive with `curl --proto '=https' --proto-redir '=https'` from the URLs in design.md's URL inventory only, print
      each download's final URL, and verify the archive against its single exact `checksums.txt` line with
      `sha256sum -c`; verify by reviewing each `curl` call against the inventory (behavior: 2.5 and the build logs of
      5.2 and 5.4)
- [x] 2.4 Skip the install when `/usr/local/bin/glab` already reports the requested version, otherwise stage the binary
      as `/usr/local/bin/.glab-feature.XXXXXX` and rename it over `/usr/local/bin/glab`; every build-time `glab` call
      runs with a temporary `GLAB_CONFIG_DIR`, `GLAB_CHECK_UPDATE=false`, `CHECK_UPDATE=false`, and
      `GLAB_SEND_TELEMETRY=false`; one `trap` removes the temporary directories and the staged file on every exit;
      verify by reading the script against the "Installing twice" requirement (behavior: `duplicate.sh` in 5.2 and 2.5)
- [x] 2.5 Run the manual checks design.md (Goals) lists against the current `install.sh`, once each on amd64 in
      throwaway containers (`debian:12` unless noted): malformed version, version below the minimum, release that does
      not exist, `latest` pointing to a pre-release tag, digest mismatch, missing entry, duplicated entry, unsupported
      architecture, `/etc/os-release` removed, unsupported distribution on `archlinux:latest`, missing package manager
      on `amazonlinux:2`, failed second install, same `version` twice (log message, unchanged inode and modification
      time), unreadable installed version; after each, verify no `${TMPDIR:-/tmp}/glab-feature.*` or
      `/usr/local/bin/.glab-feature.*` remains and, for the checks that fail before installing, that `git` is still
      missing; the results are recorded under 5.5

## 3. Tests

- [x] 3.1 Write `test/glab/checks.sh`, the POSIX stand-in for `dev-container-features-test-lib` with the same `check`
      and `reportResults` interface (design.md, Decisions), which every test script sources; verify by shellcheck in
      `just check` (behavior: 5.2 and 5.3)
- [x] 3.2 Write `test/glab/test.sh`: first the "Nothing configured after install" assertions (no glab configuration
      directory in the remote user's or root's home, no `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, or `OAUTH_TOKEN`), then
      `command -v glab` resolves to `/usr/local/bin/glab` (on `fedora:44` it prints `/usr/local/sbin/glab`, a directory
      symlink to `bin` that comes first on `PATH`), `glab --version` and `git --version` exit 0, the version equals the
      one the latest-release permanent link names at test time ("Omitted version"), no file remains under
      `/var/lib/apt/lists`, `/var/cache/libdnf5`, or `/var/cache/apk`, and no temporary file of the install remains;
      verify by shellcheck in `just check` and by reading it against the "Default install", "Omitted version", and
      "Nothing configured after install" scenarios (behavior: 5.2)
- [x] 3.3 Write `test/glab/duplicate.sh`: the first install used `VERSION` `1.47.0` and the second `VERSION__DEFAULT`
      `latest`; after both, `glab --version` reports the permanent link's version, which differs from `1.47.0`,
      `command -v glab` resolves to `/usr/local/bin/glab` (as in 3.2), and `/usr/local/bin` holds no other file whose
      name contains `glab`; verify by shellcheck in `just check` and by reading it against the "Different version the
      second time" scenario (behavior: 5.2)
- [x] 3.4 Write `test/glab/scenarios.json` with scenarios for an explicit version (`1.119.0`) and a leading `v`
      (`v1.119.0`) on images of the compatibility list, and their scripts asserting `glab --version` reports `1.119.0`;
      verify by `just validate` and shellcheck in `just check` (behavior: 5.3)

## 4. Documentation

- [x] 4.1 Write `src/glab/NOTES.md`: no authentication is configured and how to authenticate after the container starts,
      pinning `version` for reproducible builds, the minimum version, integrity-only verification, the build-time
      network access, and the compatibility list; verify by reading it against the spec and design.md (Risks)
- [x] 4.2 Replace "No features have been published yet." in the root `README.md` with one list item for `glab` linking
      to `src/glab/` with a one-sentence description; verify by `deno fmt --check` in `just check`
- [x] 4.3 Run `just docs` and verify `src/glab/README.md` is generated and `just docs-check` passes

## 5. Validation

- [x] 5.1 Run `just check` and verify it passes, and verify `git diff --stat origin/main...` lists no file outside
      `src/glab/`, `test/glab/`, the root `README.md`, and this change
- [x] 5.2 Run `just test glab` on amd64 and verify every compatibility image passes the autogenerated and duplicate
      tests, and that the build logs show each download's final URL
- [x] 5.3 Run `just test-scenarios glab` and verify every scenario passes
- [ ] 5.4 Verify the PR's container test jobs pass on every image and architecture of `test/glab/compatibility.json`,
      amd64 and arm64, and read one job's build log for the final download URLs (design.md, Goals)
- [ ] 5.5 Record the results of 2.5 and 5.1 to 5.4, each Acceptance item, and each spec scenario with its result in the
      PR's Validation section
