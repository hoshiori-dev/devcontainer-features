# Tasks

## 1. Scaffold and metadata

- [ ] 1.1 Run `just new-feature glab --name "GitLab CLI (glab)"` and verify it creates `src/glab/` and `test/glab/`
- [ ] 1.2 Fill `src/glab/devcontainer-feature.json`: version `1.0.0`, name, one-sentence description, and the `version`
      option with proposals `["latest", "1.47.0"]` and default `latest`; no `containerEnv`, `dependsOn`,
      `installsAfter`, `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, or lifecycle command.
      Verify by reading the file against design.md (Decisions, Security review) and by `just validate`
- [ ] 1.3 Write `test/glab/compatibility.json` with the four images of design.md (Supported images), each with
      `"arch": ["amd64", "arm64"]` and `"remoteUser": "vscode"` on the Ubuntu base only; verify by `just validate`

## 2. install.sh

- [ ] 2.1 Write `src/glab/install.sh` as POSIX `#!/bin/sh` with `set -eu`: validate `version` (`latest` or
      `v?MAJOR.MINOR.PATCH`, minimum `1.47.0`), map the architecture, detect the family from `/etc/os-release` `ID` or
      `ID_LIKE` and require its package manager, all before any package install or download; verify by shellcheck in
      `just check` and by the manual checks in 2.5
- [ ] 2.2 Install only the missing ones of `git`, `curl`, `ca-certificates`, and `tar` non-interactively and clean the
      package-manager cache (apt lists removed, `dnf clean all`, `apk add --no-cache`); verify by `test.sh`'s cache
      assertion on every image in `just test glab`
- [ ] 2.3 Resolve `latest` from the permanent link's redirect without following it, download `checksums.txt` and the
      archive with `curl --proto '=https' --proto-redir '=https'` from the URLs in design.md's URL inventory only, print
      each download's final URL, and verify the archive against its single exact `checksums.txt` line with
      `sha256sum -c`; verify by reviewing each `curl` call against the inventory and by the build log of
      `just test glab`
- [ ] 2.4 Skip the install when `/usr/local/bin/glab` already reports the requested version, otherwise stage the binary
      as `/usr/local/bin/.glab-feature.XXXXXX` and rename it over `/usr/local/bin/glab`; every build-time `glab` call
      runs with a temporary `GLAB_CONFIG_DIR`, `GLAB_CHECK_UPDATE=false`, `CHECK_UPDATE=false`, and
      `GLAB_SEND_TELEMETRY=false`; one `trap` removes the temporary directories and the staged file on every exit;
      verify by `duplicate.sh` and the manual checks in 2.5
- [ ] 2.5 Run the manual checks design.md (Goals) lists, once each on amd64 in throwaway containers (`debian:12` unless
      noted): malformed version, version below the minimum, release that does not exist, `latest` pointing to a
      pre-release tag, digest mismatch, missing entry, duplicated entry, unsupported architecture, `/etc/os-release`
      removed, unsupported distribution on `archlinux:latest`, missing package manager on `amazonlinux:2`, failed second
      install, same `version` twice (log message, unchanged inode and modification time), unreadable installed version;
      after each, verify no `${TMPDIR:-/tmp}/glab-feature.*` or `/usr/local/bin/.glab-feature.*` remains and, for the
      checks that fail before installing, that `git` is still missing; record each result for the PR's Validation
      section

## 3. Tests

- [ ] 3.1 Write `test/glab/test.sh`: first the "Nothing configured after install" assertions (no glab configuration
      directory in the remote user's or root's home, no `GITLAB_TOKEN`, `GITLAB_ACCESS_TOKEN`, or `OAUTH_TOKEN`), then
      `command -v glab` is `/usr/local/bin/glab`, `glab --version` and `git --version` exit 0, the version equals the
      one the latest-release permanent link names at test time, and no file remains under `/var/lib/apt/lists`,
      `/var/cache/libdnf5`, or `/var/cache/apk`; verify by `just test glab`
- [ ] 3.2 Write `test/glab/duplicate.sh`: after `1.47.0` then the defaults, `glab --version` reports the permanent
      link's version, which differs from `1.47.0`, `command -v glab` is `/usr/local/bin/glab`, and `/usr/local/bin`
      holds no other file whose name contains `glab`; verify by `just test glab`
- [ ] 3.3 Write `test/glab/scenarios.json` with scenarios for an explicit version (`1.119.0`) and a leading `v`
      (`v1.119.0`) on images of the compatibility list, and their scripts asserting `glab --version` reports `1.119.0`;
      verify by `just test-scenarios glab`

## 4. Documentation

- [ ] 4.1 Write `src/glab/NOTES.md`: no authentication is configured and how to authenticate after the container starts,
      pinning `version` for reproducible builds, the minimum version, integrity-only verification, the build-time
      network access, and the compatibility list; verify by reading it against the spec and design.md (Risks)
- [ ] 4.2 Replace "No features have been published yet." in the root `README.md` with one list item for `glab` linking
      to `src/glab/` with a one-sentence description; verify by `deno fmt --check` in `just check`
- [ ] 4.3 Run `just docs` and verify `src/glab/README.md` is generated and `just docs-check` passes

## 5. Validation

- [ ] 5.1 Run `just check` and verify it passes
- [ ] 5.2 Run `just test glab` on amd64 and verify every compatibility image passes the autogenerated and duplicate
      tests
- [ ] 5.3 Run `just test-scenarios glab` and verify every scenario passes
- [ ] 5.4 Record the results of 2.5 and 5.1 to 5.3, each Acceptance item, and each spec scenario with its result in the
      PR's Validation section
