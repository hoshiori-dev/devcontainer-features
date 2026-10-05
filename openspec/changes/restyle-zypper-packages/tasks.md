# Tasks

## 1. install.sh

- [ ] 1.1 Restyle `src/zypper-packages/install.sh` to the POSIX skeleton's layout (design.md, Layout and structure): the
      shared header, libzypp's default paths as readonly constants, `${PACKAGES-}` and the control defaults at the top,
      `log` and `fail`, the helpers `trim` and `check_entry`, one function per step, and `main` holding the entry list
      in its positional parameters; verify that `shellcheck -o require-variable-braces,require-double-brackets` reports
      nothing and that no line is longer than 120 characters
- [ ] 1.2 Give every failure and log line the wording of design.md (Messages and logging), log one line before each step
      that refreshes, reads, or rebuilds metadata, installs, or cleans, and end each `zypper` call with `|| fail`
      carrying `$?`; verify with `docker run` on `opensuse/leap:16.0` that an invalid control, an empty control, each of
      the four refusals, and a `refreshPolicy=never` cache miss exit 1 with their `zypper-packages: error:` line, that a
      name no repository offers exits 1 with zypper's status in the message, and that a default installation and one
      with `refreshPolicy=never` after `cleanup=none` succeed with the log lines of each step
- [ ] 1.3 Verify the paths that must work without bash and without `zypper`: under dash and under BusyBox ash, an empty
      list exits 0 with `no packages listed; nothing to do`, an invalid control and a refused entry exit 1, and a
      non-empty list exits 1 with the `zypper was not found` message naming the distribution; on `opensuse/leap:16.0`
      the same message appears with a `PATH` that holds only `sed` and `tr`
- [ ] 1.4 Compare the restyled script with the one on `main` for the same inputs on `opensuse/leap:16.0`: the same
      entries are accepted and refused, `zypper` receives the same arguments in the same order (recorded by a stub), and
      `LC_ALL` and `ZYPP_CONF` reach `zypper` as they were set
- [ ] 1.5 Raise `version` in `src/zypper-packages/devcontainer-feature.json` to `1.0.1` and run `just docs`; verify that
      `just docs-check` and `just validate` pass and that NOTES.md and the options are unchanged

## 2. Tests

- [ ] 2.1 Restyle `test/zypper-packages/test.sh` and `duplicate.sh` (design.md, Tests): `set -euo pipefail`, one labeled
      `check` per behavior in the spec's words, no unused helper, and the `TODO(#43)` comment in `test.sh`; verify that
      shellcheck with the two optional checks reports nothing and that each script ends with `reportResults`
- [ ] 2.2 Restyle the scenario scripts `listed_packages_*.sh`, `controls_none_*.sh`, `controls_packages_*.sh`,
      `optional_false_*.sh`, `optional_true_*.sh`, and `architecture_*.sh` as bash scripts that assert only through
      labeled `check` calls of the test library, with the glob loops as helpers named after what they assert; verify
      that shellcheck with the two optional checks reports nothing and, with `docker run` on `opensuse/leap:16.0` and a
      stand-in for the test library, that each script passes after the installation its scenario describes and fails
      when its behavior is absent
- [ ] 2.3 Leave `compatibility.json`, `scenarios.json`, and `control_checks.ts` as they are; verify that
      `git diff --stat main -- test/zypper-packages/` lists none of the three

## 3. Integration

- [ ] 3.1 Run `just check` and confirm it passes; record the result in the PR's Validation section
- [ ] 3.2 Run `test/zypper-packages/control_checks.ts`, unchanged, on the amd64 images of the compatibility list and
      confirm every check passes, except the Tumbleweed pin-below check that may report not run; record the result in
      the PR's Validation section
- [ ] 3.3 Confirm that `just test zypper-packages` passes on every image and architecture of the compatibility list in
      CI; record the result in the PR's Validation section
- [ ] 3.4 Confirm that `just test-scenarios zypper-packages` passes in CI; record the result in the PR's Validation
      section
