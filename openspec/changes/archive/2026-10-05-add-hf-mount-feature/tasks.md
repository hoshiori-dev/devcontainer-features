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

## 6. Install script rework

- [x] 6.1 Rebuild `src/hf-mount/install.sh` on the POSIX skeleton of `.agents/knowledge/shell-style.md` (Skeletons),
      keeping every URL, every `curl` flag (no `--retry`: design, Goals), the order of the checks (root, `version`,
      `backend`, `installMountDependencies`, architecture, glibc, distribution), every package, and every installed
      file: the header without its second-install sentence, naming the variable each option arrives in (`version` as
      `VERSION`, `backend` as `BACKEND`, `installMountDependencies` as `INSTALLMOUNTDEPENDENCIES`) and giving the reason
      for POSIX `sh` that the design's Goals give; `set -eu`; `readonly` constants before the option defaults
      (`REPOSITORY_URL`, `LATEST_URL`, `TAG_URL_PREFIX`, `BIN_DIR`, the glibc floor, and a new one for
      `/var/lib/apt/lists`); the three `${NAME-default}` lines; the mutable globals in lower case; `log` and `fail` with
      `printf` and the prefixes `hf-mount:` and `hf-mount: error:`; step functions with function-prefixed variables,
      each under a one-sentence comment, in place of the six divider lines and the top-level code; `main` as the list of
      steps, which installs the `EXIT`, `INT`, and `TERM` traps before the first package is installed (the signal traps
      under a comment giving their reason), with `BACKEND` and `INSTALLMOUNTDEPENDENCIES` made readonly once validated
      and `VERSION` after the distribution step, since `/etc/os-release` assigns `VERSION` too; `main "$@"` last; verify
      with `shellcheck -o require-variable-braces,require-double-brackets src/hf-mount/install.sh` reporting nothing, a
      review of the layout against the skeleton, and one default install in a throwaway `debian:12` container that
      leaves the three binaries, `mount.nfs`, and `fusermount3` in place
- [x] 6.2 In `install.sh`, give the `curl` arguments that the latest-release request and the downloads share
      (`--disable` first, then `--silent --show-error --proto '=https' --tlsv1.2 --connect-timeout 30`) one `fetch`
      function; keep calls at `main` → step → helper (today a step calls `install_missing`, which calls `is_installed`);
      branch with `if` wherever a `||` list is not a `fail` or `return` guard (the collection of missing packages, the
      two captures of `curl`'s exit status, the probes for the download tools, the removal of the work directory, the
      creation of `/usr/local/bin`); quote both operands of every `[ … ]` test; hold the package names and the selected
      binaries in positional parameters, so no unquoted expansion is split and no `# shellcheck disable` remains; and
      give `|| true` on the `getconf` probe, on `apt-get clean`, and on `dnf clean all` a comment naming the failure
      mode it handles, or remove it where there is none; verify by review, with
      `grep -c 'shellcheck disable' src/hf-mount/install.sh` printing 0, and with a default install in throwaway
      `debian:12` and `fedora:44` containers
- [x] 6.3 Reword every failure of `install.sh` to `<reason>; <how to fix it>`, starting in lower case and without a
      trailing period, keeping what each spec scenario requires the message to name (the accepted forms or values, the
      requested version, the requested URL, the missing asset, the URL and the status, glibc and the found and required
      versions, the architecture, the distribution); end `apt-get update`, `apt-get install`, and `dnf install` with
      `|| fail`; and write one `hf-mount:` line with `log` for every step that uses the network or changes the image,
      saying what it does, from where, and to where (package installation, the latest-release request, each download,
      the installation into `/usr/local/bin`); verify with runs of `version` set to `v0.13.1` and of `backend` set to a
      value outside its enum in a throwaway `debian:12` container (each prints one `hf-mount: error:` line holding a
      `;`, exits 1, and leaves `/usr/local/bin` as it was) and by reading the log of a default install
- [x] 6.4 Use long options in `install.sh` wherever every compatibility image accepts them (`mktemp --directory`,
      `rm --recursive --force`, `install --directory --mode`, `install --owner --group --mode`, `apt-get --yes`,
      `dpkg-query --show --showformat`, `dnf --assumeyes`, `rpm --query`), and on the commands that run before the glibc
      check (`id -u`, `uname -m`), which must also run on BusyBox for the "musl-based image" scenario, keep a short
      option where BusyBox lacks the long form, under a comment giving that reason; verify with a default install on
      each compatibility image of this machine's architecture and with a run on `alpine` that still ends with the glibc
      message

## 7. Test rework

- [x] 7.1 Restyle `test/hf-mount/test.sh` as `.agents/knowledge/shell-style.md` (Tests) says: `set -euo pipefail`;
      braces on `binary` and `comm`; `[[ … ]]` with `==` inside the helpers, while a comparison passed straight to
      `check` keeps `test`; `version_form` renamed after the behavior it asserts; in `same_release_as_daemon`, each
      `--version` output assigned to a `local` variable and followed by `|| return` before the comparison, so the helper
      fails when either command fails (`check` runs a helper as an `if` condition, where `set -e` does not stop it),
      under a comment saying why the expected value is read at run time (`latest` can move between build and test); a
      comment on `2>/dev/null` in `no_hf_mount_process` and on `-s` in `no_user_allow_other` naming the case each
      covers, or its removal where no compatibility image meets that case; the labels "command -v hf-mount resolves,
      following symbolic links, to /usr/local/bin/hf-mount" and "<binary> is executable by the remote user" in the words
      of "Omitted backend", and "<binary> is owned by root and executable by every user" in the words of "Daemon and
      selected backends are installed", its `root:root 755` comparison unchanged under a comment saying that it is
      stricter than the spec and why (design, Open Questions, 2); every other check's command verifies what it verifies
      today; verify with `shellcheck -o require-variable-braces,require-double-brackets test/hf-mount/test.sh` reporting
      nothing, `just test hf-mount --image debian:12`, and one call of `same_release_as_daemon` with a command that does
      not exist, which must return non-zero
- [x] 7.2 Restyle `test/hf-mount/duplicate.sh` the same way (`set -euo pipefail`, braces, `[[ … ]]` in the helpers,
      `same_release_as_daemon` as in task 7.1); replace the three checks of the first install's options with a
      precondition before the first check that stops the script with exit status 1 and a message naming the option that
      differs when `${VERSION-}` equals `${VERSION__DEFAULT-}`, `${BACKEND-}` is not `nfs`, or
      `${INSTALLMOUNTDEPENDENCIES-}` is not `false` (design, Tests); and label the two release checks in the words of
      "Installing twice" (the later `version` applies to each binary the later `backend` selects); verify with
      shellcheck as in task 7.1, with `just test hf-mount --image debian:12`, and by running the script once with other
      inputs, which stops it before any check
- [x] 7.3 Restyle `test/hf-mount/backend_nfs.sh`, `backend_fuse.sh`, `dependencies_disabled.sh`, and `pinned_version.sh`
      the same way (`set -euo pipefail`, `[[ … ]]` in the helpers, braces on `binary` in `dependencies_disabled.sh`),
      with the labels "fusermount3 was not installed" and "mount.nfs was not installed" restated in the words of "Mount
      dependencies follow the selected backends"; `scenarios.json` and `compatibility.json` stay as they are; verify
      with shellcheck as in task 7.1 on the four scripts, `just validate`, and `just test-scenarios hf-mount`

## 8. Version and documentation

- [x] 8.1 Read `src/hf-mount/NOTES.md` against `.agents/knowledge/feature-authoring.md` (User documentation: grammar,
      clear wording, actual limitations, configuration constraints, no exhaustive hypothetical caveats) and against what
      the rebuilt `install.sh` does, within the design's `NOTES.md` content bounds (whether the notes also name the
      download tools is the design's Open Questions, 3); regenerate `src/hf-mount/README.md` with `just docs`; verify
      with `just docs-check` and by reading the generated README once as a developer who has not read the spec
- [x] 8.2 Keep `version` `1.0.0` in `src/hf-mount/devcontainer-feature.json`, since the feature is unreleased
      (`.agents/knowledge/feature-authoring.md`, Versions); verify with `just validate`

## 9. Verification after the rework

- [x] 9.1 Options, by hand: run `install.sh` with `version` set to the empty string ("Malformed version"), `backend` set
      to a value outside its enum ("Invalid backend"), and `installMountDependencies` set to a value that is neither
      `true` nor `false` ("Invalid installMountDependencies") in throwaway containers; verify that each fails with the
      message its scenario names, that the log shows no download, and that `/usr/local/bin` is left as it was
- [x] 9.2 Re-run the hand checks of tasks 3.1 to 3.4 against the rebuilt `install.sh`; verify that each message still
      names what its scenario requires, that `/usr/local/bin` is left as each scenario says, and that the install-twice
      scenarios give the results of 3.4; repeat 3.5 only if an installed file or the `runArgs` in `NOTES.md` changed
- [x] 9.3 Run `just check` and verify it passes, and that
      `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on `src/hf-mount/install.sh` and
      every `test/hf-mount/*.sh`; then review those scripts against `.agents/knowledge/shell-style.md` and verify that
      every deliberate deviation carries its reason on the line above
- [x] 9.4 Run `just test hf-mount` and verify the autogenerated and install-twice tests pass on every image of the
      compatibility list for this machine's architecture
- [x] 9.5 Run `just test-scenarios hf-mount` and verify every scenario passes
- [x] 9.6 Verify that the pull request's container jobs pass on every image and architecture of the compatibility list
      (arm64 runs only in CI) and that every required check but `spec-archived` is green
- [x] 9.7 Record each Acceptance item and each scenario with its test or hand check, image, architecture, and result in
      the PR's Validation section

## 10. Review follow-up

- [x] 10.1 In `resolve_release` of `src/hf-mount/install.sh`, add `--fail` to the latest-release request, so that it
      fails on an HTTP error status as the design's Goals state for every request (the redirect is still read, not
      followed), and give the `curl` exit status of an HTTP error its own message naming the URL and the status; verify
      with `shellcheck`, also with `-o require-variable-braces,require-double-brackets`, reporting nothing, with a
      default install in throwaway `debian:12` and `ubuntu:22.04` containers that resolves `latest` and leaves the three
      binaries in place, with a copy of the script whose latest-release URL names a path that answers 404 (exit 1 with
      that message, no download in the log, no mount helper installed, `/usr/local/bin` left as it was), and with the
      copy of task 3.2 whose repository has no release, which must still end with the message of "Latest release cannot
      be resolved"
- [x] 10.2 In the design's Goals (TLS alone, never weakened), state what the feature does about certificate checking and
      no more: it passes no flag, uses no configuration file, and sets no environment variable that relaxes it, and it
      leaves the build environment's own certificate settings as the image provides them; add the hand check of task
      10.1 to the design's Hand checks; change no behavior; verify by reading `install.sh` for such a flag, file, or
      variable, by one `curl` request each with `CURL_CA_BUNDLE` and with `SSL_CERT_FILE` set to `/dev/null`, and by
      searching `NOTES.md`, the proposal, the delta spec, this file, and the rest of the design for the stronger claim
- [x] 10.3 Run `just docs` and verify that `src/hf-mount/README.md` does not change, and run `just check` and verify it
      passes
- [x] 10.4 Add one sentence under "What is installed" of `src/hf-mount/NOTES.md` saying that `curl` and
      `ca-certificates` are installed from the image's repositories when the image lacks them, and regenerate
      `src/hf-mount/README.md` with `just docs` (design, Questions answered on 2026-10-05); verify that the README gains
      the same sentence and nothing else, and with one install each in a throwaway `debian:12` container, which lacks
      both packages and must hold both afterwards, and in a throwaway `mcr.microsoft.com/devcontainers/base:ubuntu24.04`
      container, which ships both and whose log must name no package installation
- [x] 10.5 In the design, record the maintainer's four answers of 2026-10-05 under Decisions, each with its rejected
      alternative (they are the points that tasks 7.1 and 8.1 cite as the design's Open Questions, 2 and 3), add the
      download tools and the limit seen with `--fuse-owner-only` to the `NOTES.md` content bounds, and remove the Open
      Questions section; verify by reading `test/hf-mount/test.sh` for the unchanged `root:root 755` comparison, its
      spec-worded label, and its comment, by reading `src/hf-mount/NOTES.md` for the `--fuse-owner-only` sentence, and
      by searching the design and the prose of this file for a sentence that still calls a question open
- [x] 10.6 Run `just check` on the committed tree and verify it passes
