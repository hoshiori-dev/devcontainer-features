# Tasks

## 1. install.sh

- [ ] 1.1 Restructure `src/uv/install.sh` into header, constants, option defaults, globals, `log` and `fail`, helpers,
      steps, `main`, `main "$@"`, with `main` calling the steps in today's top-level order; verify by comparing `main`
      with the old top-level order and with shellcheck (default and
      `-o require-variable-braces,require-double-brackets`) reporting nothing
- [ ] 1.2 Rework option validation (`case` patterns for `version`, the redirect's release name, and the digest;
      `grep -E` from a here-document for tool entries; the `IFS=,` / `set -f` split restored before validation); verify
      by running the old and the new validation on the value list of the design's Goals and comparing the outcomes
- [ ] 1.3 Switch messages to `printf`, the `uv:` / `uv: error:` prefixes, and `<reason>; <how to fix it>`; add the log
      lines and the explicit failures (package managers, `sha256sum`, the new binary's version); verify with
      `docker run` that an invalid `version` and an invalid `toolsToInstall` entry holding a backslash fail with status
      1 and the value unchanged in a `uv: error:` line
- [ ] 1.4 Use the long options of the design's "Long options" and the two curl wrappers with today's flags; verify by
      reviewing every `curl` line against the URL inventory and with a default install on `alpine:3.24` and a glibc
      compatibility image under plain `docker run`
- [ ] 1.5 Keep the here-document body of `/etc/profile.d/uv.sh` byte for byte; verify that the installed file equals the
      one the old script writes

## 2. Volume-repair script

- [ ] 2.1 Rename `src/uv/repair-volume.sh` to `src/uv/repair_volume.sh`, restyle it with a header, a readonly constant,
      `warn` with the `uv: warning:` prefix, and a `main` whose every exit returns 0, and copy it from `install.sh` to
      the unchanged installed path; verify with shellcheck and by running it under dash and BusyBox ash as root, as a
      user with a fitting volume, and as a user with a foreign volume and no `sudo`, each exiting 0

## 3. Tests

- [ ] 3.1 Add `test/uv/checks.sh`, a POSIX stand-in for the test library whose `check` returns 1 after recording a
      failure; verify by sourcing it under dash and BusyBox ash with one passing and one failing check
- [ ] 3.2 Restyle `test.sh`, `duplicate.sh`, `pinned_release.sh`, and `changed_uid.sh` to POSIX `sh` sourcing
      `checks.sh`, and remove the bash install from `changed_uid/Dockerfile`; verify with shellcheck (both forms) and by
      parsing each script with dash and BusyBox ash (`sh -n`)
- [ ] 3.3 Restyle `tools.sh`, `runtime_python.sh`, `repair_volume.sh`, and `minimal_image.sh` to bash with
      `set -euo pipefail`, setup outside `check`, and the new warning prefix in `repair_volume.sh`; verify with
      shellcheck (both forms) and `bash -n`

## 4. Version and documentation

- [ ] 4.1 Bump `src/uv/devcontainer-feature.json` to 1.0.1 and run `just docs`; verify that `just docs-check` passes and
      `src/uv/README.md` changes only where `just docs` changes it

## 5. Integration

- [ ] 5.1 Run `just check` in the worktree and verify it passes
- [ ] 5.2 Run `just test uv` in CI after the push and verify every compatibility image passes on both architectures
- [ ] 5.3 Run `just test-scenarios uv` and `just test-scenarios hf-cli` in CI after the push and verify every scenario
      passes
- [ ] 5.4 Run `just test-global` in CI after the push and verify the global scenarios pass
- [ ] 5.5 Record the results of 5.1 to 5.4 against each Acceptance item in the PR's Validation section
