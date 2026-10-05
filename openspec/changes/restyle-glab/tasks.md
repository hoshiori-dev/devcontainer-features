# Tasks

## 1. Install script

- [ ] 1.1 Rebuild `src/glab/install.sh` on the POSIX skeleton's layout (header without second-install behavior, readonly
      constants including `LATEST_URL`, the apt-lists path and the staging template, `VERSION="${VERSION-latest}"`,
      mutable globals, `log` and `fail` with `printf` and the `glab:` prefix, step functions with one-sentence comments,
      `main`, `main "$@"`), with `VERSION` made readonly in `main` after the platform step and the traps installed
      before the work directory is created; verify with
      `shellcheck -o require-variable-braces,require-double-brackets src/glab/install.sh` and a review against design.md
      (Script structure, Constants and the option variable, Comments)
- [ ] 1.2 Inline `has_package`, `reports_version`, `run_glab`, and `download` into their steps, keep `fetch`,
      `normalize_version`, and `version_at_least` as helpers, collect the missing prerequisites in positional
      parameters, branch presence checks with `if`, and read the `dpkg-query` status in a condition; verify by review
      that calls go at most `main` → step → helper, that no `# shellcheck disable` remains, and with a default install
      on `debian:12`, whose log names the installed packages
- [ ] 1.3 Reword every failure to `<reason>; <how to fix it>` as design.md (Failure messages) lists, end
      `apt-get update`, `apt-get install`, `dnf install`, and `apk add` with `|| fail`, and write the log lines of
      design.md (Log lines), the last one without running the new binary; verify with hand runs of an empty, a
      malformed, and a below-minimum `version` (each prints its `glab: error:` line and exits 1 before anything is
      installed) and of a default install whose last line names the version and `/usr/local/bin/glab`
- [ ] 1.4 Switch to the long options design.md (Long options) lists and keep the short ones BusyBox or mawk needs;
      verify with a default install on `alpine:3.24`, `debian:12`, and `fedora:44`
- [ ] 1.5 Leave `src/glab/NOTES.md` unchanged; verify with `git diff --stat origin/main -- src/glab/NOTES.md` printing
      nothing

## 2. Tests

- [ ] 2.1 Restyle `test/glab/checks.sh`: `printf`, the lower-case `failed`, prefixed function variables, the comment on
      `check` and `reportResults`, `glab_reports_version` in place of `equals` and `installed_version`, and only the
      stand-in, `as_root`, `glab_quiet`, and the assertions more than one script uses; verify with
      `shellcheck -o require-variable-braces,require-double-brackets test/glab/checks.sh` and by running its helpers
      under dash and BusyBox ash
- [ ] 2.2 Restyle `test/glab/test.sh`: `set -eu`, `latest` computed once at the top with its reason,
      `no_token_variables` and `package_caches_empty` defined before their checks, the status of `find` checked, and the
      cache and leftover labels in the words of the delta spec's "Leave no build residue"; verify with shellcheck as
      above and `just test
      glab`
- [ ] 2.3 Restyle `test/glab/duplicate.sh`: `set -eu`, `latest` computed once at the top, the option inputs as a
      precondition that stops the script, `only_one_glab` defined before its check, and the leftover label in the words
      of "Leave no build residue"; verify with shellcheck as above and `just test glab`
- [ ] 2.4 Give each of the eight `test/glab/version_*.sh` scenario scripts its own two checks with the literal
      `1.119.0`, sourcing only `checks.sh`; leave `test/glab/scenarios.json` and `test/glab/compatibility.json`
      unchanged; verify with `grep -L 'checks.sh' test/glab/version_*.sh` printing nothing,
      `git diff --stat
      origin/main -- test/glab/scenarios.json test/glab/compatibility.json` printing nothing, and
      `just test-scenarios
      glab`

## 3. Version and documentation

- [ ] 3.1 Set the version in `src/glab/devcontainer-feature.json` to `1.0.1` and regenerate `src/glab/README.md` with
      `just docs`; verify with `just validate` and `just docs-check`

## 4. Integration checks

- [ ] 4.1 Run `just check`; verify it passes, and that `shellcheck -o require-variable-braces,require-double-brackets`
      reports nothing on `src/glab/install.sh` and every `test/glab/*.sh`
- [ ] 4.2 Re-run the manual checks design.md (Goals) lists for the failure scenarios, with the empty `version` and a
      failing package-manager command added; verify each prints the part its scenario requires and leaves
      `/usr/local/bin/glab` as the scenario says
- [ ] 4.3 Run `just test glab` and `just test-scenarios glab`, and confirm the PR's container test jobs pass on amd64
      and arm64; verify every job is green
- [ ] 4.4 Record the results of 4.1 to 4.3 and of every Acceptance item in the PR's Validation section; verify each item
      of the proposal's `## Acceptance` is named there with its result
