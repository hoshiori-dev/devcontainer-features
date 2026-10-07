# Tasks

## 1. Staged copy of the installer

- [x] 1.1 In `scripts/lib/stage.ts`, copy `src/<id>/` of the checkout to `test/<id>/_feature/` in the staging directory
      for every staged feature that has a test folder, before any reference is rewritten; verify with a new unit test in
      `scripts/lib/stage_test.ts` that compares the copy with the source tree byte for byte, and with the existing
      staging tests passing unchanged
- [x] 1.2 In `scripts/validate.ts`, reject a path `test/<id>/_feature` in the repository and a scenario named
      `_feature`, naming the path; verify with new unit tests in `scripts/validate_test.ts` and with `just validate`
      passing on this checkout
- [x] 1.3 Document the test type in `.agents/knowledge/testing.md` — the Layout table row, how a scenario runs the
      installer itself, what it can prepare beforehand, which checks it cannot express, the `test_*` / `fail_*` naming
      rule, and that the other features follow it with #117 — and check whether the overview in `CONTRIBUTING.md` still
      holds; verify with `just check`

## 2. apt-packages

- [x] 2.1 Rename the existing scenarios of `test/apt-packages` to `test_*` in `scenarios.json` and in their script
      names, checks unchanged; verify with `just validate`
- [x] 2.2 Add the scenarios and scripts that run `_feature/install.sh` for every check of
      `test/apt-packages/direct_checks.ts` and `control_checks.ts`, each script's header comment naming the
      specification scenarios it checks; verify with `just test-scenarios apt-packages`
- [x] 2.3 Change `src/apt-packages/install.sh` in the working tree so that it accepts one refused entry, run
      `just test-scenarios apt-packages`, record the failing check and its output for the Validation section, and
      discard the edit; verify with `git status` showing no change under `src/`
- [x] 2.4 Delete `test/apt-packages/direct_checks.ts` and `control_checks.ts` and correct the comments that name them;
      verify that `git grep -n -e direct_checks -e control_checks -- test/apt-packages src/apt-packages` finds nothing
      and that `just test apt-packages` and `just test-scenarios apt-packages` pass
- [x] 2.5 Push, and verify in CI that the scenario job of `apt-packages` and the global scenarios pass; record the
      scenario count and the job duration before and after

## 3. apk-packages

- [x] 3.1 Rename the existing scenarios to `test_*`, checks unchanged; verify with `just validate`
- [x] 3.2 Add the scenarios and scripts for every check of the two runners, header comments naming the specification
      scenarios; verify with `just test-scenarios apk-packages`
- [x] 3.3 Delete the two runners and correct the comments that name them; verify with the `git grep` of 2.4 for this
      feature and with `just test apk-packages` and `just test-scenarios apk-packages` passing

## 4. dnf-packages

- [x] 4.1 Rename the existing scenarios to `test_*`, checks unchanged; verify with `just validate`
- [x] 4.2 Add the scenarios and scripts for every check of `control_checks.ts`, header comments naming the specification
      scenarios; verify with `just test-scenarios dnf-packages`
- [x] 4.3 Delete the runner and correct the comments that name it; verify with the `git grep` of 2.4 for this feature
      and with `just test dnf-packages` and `just test-scenarios dnf-packages` passing

## 5. pacman-packages

- [x] 5.1 Rename the existing scenarios to `test_*`, checks unchanged; verify with `just validate`
- [x] 5.2 Add the scenarios and scripts for every check of the two runners, header comments naming the specification
      scenarios; verify with `just test-scenarios pacman-packages`
- [x] 5.3 Delete the two runners and correct the comments that name them; verify with the `git grep` of 2.4 for this
      feature and with `just test pacman-packages` and `just test-scenarios pacman-packages` passing

## 6. zypper-packages

- [x] 6.1 Rename the existing scenarios to `test_*`, checks unchanged; verify with `just validate`
- [x] 6.2 Add the scenarios and scripts for every check of `control_checks.ts`, header comments naming the specification
      scenarios; verify with `just test-scenarios zypper-packages`
- [x] 6.3 Delete the runner and correct the comments that name it; verify with the `git grep` of 2.4 for this feature
      and with `just test zypper-packages` and `just test-scenarios zypper-packages` passing

## 7. Integration

- [x] 7.1 Verify the proposal's Acceptance across the five installers: no runner file is left, the `git grep` of the
      proposal finds no line, every scenario is named `test_*` or `fail_*`, each `fail_*` script asserts a run that
      exits non-zero, no scenario sets `privileged`, `capAdd`, `securityOpt`, `mounts`, or `entrypoint`, and
      `git diff origin/main --stat -- src openspec/specs` is empty
- [x] 7.2 Run `just check`, and `just test <id>` and `just test-scenarios <id>` for the five installers, and
      `just test-global`; record the results, each Acceptance item, and the scenario counts and job durations in the
      PR's Validation section, and open the follow-up issue for the runners of `hf-cli` and `colab-cli` that the PR
      description names
