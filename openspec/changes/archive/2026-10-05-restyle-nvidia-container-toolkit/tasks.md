# Tasks

## 1. install.sh

- [x] 1.1 Restructure `src/nvidia-container-toolkit/install.sh` to the bash skeleton (header, `set`, readonly constants
      including `DNF_REPO_FILE` and `ZYPPER_REPO_FILE`, option defaults, lower-case globals, `log`, `fail`, step
      functions, `main`, `main "$@"`; trap armed in `main`; no divider comments) and verify by review that no executable
      code sits between functions and that `shellcheck -o require-variable-braces,require-double-brackets` reports
      nothing for the file
- [x] 1.2 Replace `find_gpg` and the `GPG` path with one gpg helper calling the literal `gpg` or `gpg2` with `--batch`,
      and move the recurring zypper, dnf, and apt-get argument sets into one function per tool; verify by `grep` that no
      command name comes from a variable and no `--batch`, `--non-interactive`, `--assumeyes`, or
      `--no-install-recommends` remains outside those functions
- [x] 1.3 Switch `log` and `fail` to the `nvidia-container-toolkit:` and `nvidia-container-toolkit: error:` prefixes
      with `printf`, word every developer-fixable failure as `<reason>; <how to fix it>` without a trailing period, and
      log one line before each network or image step; verify by `grep` over the messages and by a default install with
      `docker run` whose log names the key download, the key write, the repository write, the toolkit install, and the
      cache cleanup
- [x] 1.4 Validate `CONFIGUREDOCKER` (default `${CONFIGUREDOCKER-true}`, anchored match against `true` and `false`,
      readonly right after) with the other options, keep `VERSION` readonly only after the platform step, and verify
      with `docker run` that `yes`, `TRUE`, `1`, and an empty value fail with exit status 1 and a message naming the
      value before the image changes, and that an empty `version` still fails
- [x] 1.5 Give the prerequisite refresh and install, `apt-get update`, `zypper refresh`, each family's toolkit install,
      and dnf's upgrade their own `|| fail`, drop the `failed` flag, and word the `latest` install failure without
      blaming a missing version; verify with `docker run` that a version the repository does not offer fails with a
      message naming the version and the architecture
- [x] 1.6 Write the dnf and zypper repository files from one literal here-document each and verify with `docker run` on
      `fedora:44` and `registry.opensuse.org/opensuse/leap:16.0` that the written files are byte-identical to the ones
      the 1.0.0 script writes
- [x] 1.7 Verify with `docker run` that an unsupported distribution fails with a message naming `ID` and `ID_LIKE`
      before any key or repository is added

## 2. Tests

- [x] 2.1 Restyle `test/nvidia-container-toolkit/helpers.sh` (readonly constants, braced variables, `printf`, `if`
      blocks instead of `|| { …; }`, output captured before matching, the repository query unmasked with the package
      manager's stderr let through and failing on apt and dnf when the repository cannot be reached,
      `repository_file_is_expected` comparing the whole file with a literal per family, `repository_listed` moved out)
      and verify that `shellcheck -o require-variable-braces,require-double-brackets` reports nothing for it
- [x] 2.2 Restyle `test.sh` with `set -euo pipefail`, `candidate` and its run-time comment, and `repository_listed`
      checking the base URL on every family (dnf through `dnf repo info`); verify with shellcheck as in 2.1 and by
      running the dnf query in `fedora:44` against the repository file the feature writes
- [x] 2.3 Restyle `duplicate.sh` (inline reason, archived design path, `candidate`) and verify with shellcheck as in 2.1
- [x] 2.4 Restyle the nine scenario scripts (`docker_disabled.sh` with `[[ … || … ]]`, `docker_in_docker.sh` keeping its
      `seq` loop) and verify with shellcheck as in 2.1; `scenarios.json`, `compatibility.json`, the scenario
      Dockerfiles, and `NOTES.md` stay unchanged, checked with `git diff --stat main`

## 3. Version and documentation

- [x] 3.1 Bump `src/nvidia-container-toolkit/devcontainer-feature.json` from 1.0.0 to 1.0.1 (PATCH), run `just docs`,
      and verify that `src/nvidia-container-toolkit/README.md` is unchanged or changed only by the generator

## 4. Integration

- [x] 4.1 Run `just check` and verify it passes
- [x] 4.2 Run `just test nvidia-container-toolkit` in CI after the push and verify every compatibility image passes
- [x] 4.3 Run `just test-scenarios nvidia-container-toolkit` in CI after the push and verify every scenario passes
- [x] 4.4 Record the results of 4.1 to 4.3 and of the manual failure runs (empty `version`, `configureDocker` `yes` and
      empty, a version the repository does not offer, an unsupported distribution) in the PR's Validation section
