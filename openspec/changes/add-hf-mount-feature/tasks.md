# Tasks

## 1. Feature

- [x] 1.1 Scaffold `src/hf-mount/` and `test/hf-mount/` with `just new-feature hf-mount` and verify that the generated
      `devcontainer-feature.json` declares exactly the options `version` (`string`, default `"latest"`), `backend`
      (`string`, enum `nfs`, `fuse`, `both`, default `"both"`), and `installMountDependencies` (`boolean`, default
      `true`), as the Option requirements state
- [x] 1.2 Complete `src/hf-mount/devcontainer-feature.json`: version `1.0.0`, `name`, a one-sentence `description`,
      `documentationURL`, the `version` proposals `latest` and `0.13.1`, the `backend` enum in the order `nfs`, `fuse`,
      `both`, and a description per option (design, Options); verify with `just validate` and `just spec-check`, and by
      reading the file for the absence of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`,
      `containerEnv`, lifecycle commands, `dependsOn`, and `installsAfter`
- [x] 1.3 Write `src/hf-mount/install.sh` as POSIX `sh` with `set -eu` within the design's bounds: the `version`,
      architecture, glibc 2.34, and distribution (`ID` of `/etc/os-release`) checks before anything is installed or
      downloaded; `curl` and `ca-certificates` only when missing; `latest` read from the redirect of
      `https://github.com/huggingface/hf-mount/releases/latest` without following it; one download per selected binary
      from the spec's URL template with the exact asset name, all into a temporary directory removed on every exit; the
      mount helpers (`nfs-common` or `nfs-utils`, `fuse3`) with `--no-install-recommends` or
      `--setopt=install_weak_deps=False` only after every download completed; the binaries with `install` as root, mode
      `0755`, into `/usr/local/bin` last; package caches cleaned; verify with `shellcheck`, by reviewing the `curl`
      flags against the design's Goals (HTTPS only on every request and redirect, a failure on an HTTP error status, no
      credential, nothing that relaxes certificate checking, no retry or extra request), and by one default install in a
      throwaway `debian:12` container that leaves the three binaries, `mount.nfs`, and `fusermount3` in place
- [x] 1.4 Write `src/hf-mount/NOTES.md` within the design's bounds (the container settings a mount needs, the non-root
      prerequisites, the downloads resting on TLS alone with no checksum or signature, what a second install does, the
      supported images), regenerate `src/hf-mount/README.md` with `just docs`, and verify that `just docs-check` passes
      and that the generated README documents every option

## 2. Container tests

- [x] 2.1 Write `test/hf-mount/compatibility.json` with the four images of the design's Supported images, each on
      `amd64` and `arm64`, and `remoteUser` `vscode` on `mcr.microsoft.com/devcontainers/base:ubuntu24.04`; verify with
      `just validate` and against the design's table
- [x] 2.2 Write `test/hf-mount/test.sh` for the default options, without any network request (scenarios "Omitted
      version", "Omitted backend", "Omitted installMountDependencies", "The installed daemon runs", "Downloads succeed",
      "NFS dependencies", "FUSE dependencies", "Container starts with no mount"); verify with `shellcheck` and
      `just test hf-mount --image debian:12`
- [x] 2.3 Write `test/hf-mount/duplicate.sh` (scenario "Non-default options, then the defaults"); verify with
      `shellcheck` and `just test hf-mount --image debian:12`
- [x] 2.4 Write `test/hf-mount/scenarios.json` and one script per scenario on `debian:12`: `backend` `nfs` ("Only the
      NFS backend selected"), `backend` `fuse` ("Only the FUSE backend selected"), `installMountDependencies` disabled
      ("Dependencies disabled"), and a pinned `version` ("Pinned release"); verify with `just validate`, `shellcheck`,
      and `just test-scenarios hf-mount`

## 3. Hand checks

- [x] 3.1 Version: run `install.sh` with `version` set to `v0.13.1`, `0.13`, and `9.9.9` in throwaway containers and
      verify that each fails with the message its scenario names ("Malformed version", "Release does not exist") and
      that `/usr/local/bin` is left as it was
- [x] 3.2 Downloads: run a copy of `install.sh` with a binary name altered ("Asset missing from the release", whose 404
      also shows "HTTP error") and a copy whose latest-release URL names a repository without a release ("Latest release
      cannot be resolved"); verify the message of each scenario and that `/usr/local/bin` is left as it was
- [x] 3.3 Platforms: run `install.sh` on `alpine` ("musl-based image"), `debian:11` ("glibc too old"), `rockylinux:9`
      ("Unsupported distribution"), and a third architecture under emulation ("Unsupported architecture"); verify the
      message of each scenario and that nothing was installed
- [x] 3.4 Installing twice: build an image with the first options and build on it with the second, for the same options
      twice ("Same options twice"), `backend` `nfs` then `fuse` ("A backend not selected the second time"), and
      `version` `0.13.1` then `0.13.0` ("Older version the second time"); verify the scenarios' results, and for the
      last one compare each binary's SHA-256 with the digest the Releases API reports for the `0.13.0` asset
- [x] 3.5 Mounts: on `mcr.microsoft.com/devcontainers/base:ubuntu24.04` with the feature installed and the `runArgs`
      `NOTES.md` names, mount a small public Hugging Face repository once per backend, as root and as `vscode`; verify
      that a file of the repository can be listed and read through each mount

## 4. Repository README

- [x] 4.1 Add the `hf-mount` row under "## Features" in the root `README.md`, with the id linking to `src/hf-mount/` and
      a one-sentence description, replacing "No features have been published yet."; verify with
      `deno fmt --check README.md` and by reading the section

## 5. Validation

- [x] 5.1 Run `just check` and verify it passes
- [x] 5.2 Run `just test hf-mount` and verify the autogenerated and install-twice tests pass on every image of the
      compatibility list for this machine's architecture
- [x] 5.3 Run `just test-scenarios hf-mount` and verify every scenario passes
- [ ] 5.4 Verify that the pull request's container jobs pass on every image and architecture of the compatibility list
      (arm64 runs only in CI) and that every required check but `spec-archived` is green
- [ ] 5.5 Record each Acceptance item and each scenario with its test or hand check, image, architecture, and result in
      the PR's Validation section
