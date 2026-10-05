# Tasks

## 1. install.sh

- [x] 1.1 Give `src/apt-packages/install.sh` the guide's POSIX layout: the header in the installers' shared pattern,
      `set -eu`, `DEBIAN_FRONTEND` exported as a readonly constant, the five option defaults as `${NAME-default}`, the
      `lists_dir` global with its comment, `log` and `fail`, the helpers `has_index` and `apt_network`, one function per
      step, and a `main` that keeps the parse loop and reads as the steps in the spec's order. Verify that
      `shellcheck -o require-variable-braces,require-double-brackets src/apt-packages/install.sh` reports nothing, that
      no line passes 120 characters, and that calls go at most `main` → step → helper.
- [x] 1.2 Inline `trim`, `describe_system`, and `refuse`, make each option readonly once validated, and keep every
      accepted set. Verify by running the old and the new script under dash and BusyBox ash with the same accepted and
      refused option values and entries on an image without `apt-get`: each pair ends with the same exit status, and an
      empty list still exits 0 there.
- [x] 1.3 Replace every failure message and log line with this feature's instantiation of the shared wording (design,
      Messages and Log lines). Verify in a container that an invalid option prints
      `apt-packages: error: option <name> is "<value>"; …` and exits 1, that a refused entry prints
      `apt-packages: error: refusing the entry '<entry>': …`, and that an image without `apt-get` prints the message
      naming `apt-get`, Debian, Ubuntu, and the detected distribution.
- [x] 1.4 Remove the three pipelines whose status decided an outcome and end every `apt-get`, `apt-config`, and
      `apt-cache` call with `|| fail` and the tool's status in the message. Verify in a container of each compatibility
      image that a failing refresh, installation, cleanup, `apt-config`, and `apt-cache` each end with their
      `apt-packages: error:` line and exit status 1, and that `bc+` and `bc=<absent version>` fail with the name and
      version messages.
- [x] 1.5 Verify in a container of each compatibility image that a default install of `bc,file` succeeds, prints the
      refresh, install, and cleanup lines, and leaves both packages installed and no package index; and that
      `refreshPolicy=never` prints the existing-index line with an index and only the failure without one.
- [x] 1.6 Set the version in `src/apt-packages/devcontainer-feature.json` to `1.1.1` and run `just docs`. Verify that
      `just docs-check` passes and that `src/apt-packages/NOTES.md` and the generated `README.md` are unchanged.

## 2. Tests

- [x] 2.1 Restyle `test/apt-packages/test.sh`: `set -euo pipefail`, `[[ ]]`, braces, labels in the words of "Omitted
      packages", and a comment on the premise that both images ship no index. Verify with
      `shellcheck -o require-variable-braces,require-double-brackets`.
- [x] 2.2 Rewrite `test/apt-packages/duplicate.sh` to assert `bc` and `file` literally and the `cleanup=packages` state
      of the first install, with one comment naming where the devcontainer CLI takes those values. Verify with the same
      shellcheck command; `just test apt-packages` runs it in CI (3.3).
- [x] 2.3 Restyle the five scenario tests `listed_packages_debian.sh`, `listed_packages_ubuntu.sh`,
      `native_architecture.sh`, `recommends_and_whitespace.sh`, and `debconf_question.sh` the same way, each with labels
      in the spec's words and the `docker-clean` comment next to its package-file assertion. Verify with the same
      shellcheck command.
- [x] 2.4 Turn the four `controls_{none,packages}_{0,1}.sh` into bash tests that source the test library, with labels in
      the words of "Only package files are cleaned" and "Feature cleanup is disabled" and no pipeline in the test shell.
      Verify with the same shellcheck command.
- [x] 2.5 Leave `test/apt-packages/scenarios.json`, `compatibility.json`, `direct_checks.ts`, and `control_checks.ts`
      unchanged. Verify that `git diff main --stat` lists none of them and that no test line passes 120 characters.

## 3. Validation

- [x] 3.1 Run `just check` and confirm it passes.
- [x] 3.2 Run `test/apt-packages/direct_checks.ts` and `test/apt-packages/control_checks.ts` on both compatibility
      images on amd64 and confirm every check passes.
- [ ] 3.3 Confirm `just test apt-packages` passes on every compatibility image and architecture (CI runs it after the
      push).
- [ ] 3.4 Confirm `just test-scenarios apt-packages` passes (CI runs it after the push).
- [ ] 3.5 Record the results of 3.1 to 3.4 and each Acceptance item of the proposal in the PR's Validation section.
