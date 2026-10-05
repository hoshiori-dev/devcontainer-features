# Tasks

## 1. Guide rules

- [x] 1.1 In `.agents/knowledge/shell-style.md`, require reading `/etc/os-release` before an option variable it also
      assigns becomes readonly, and give option defaults as `${NAME-default}` with the stated exception for options
      whose spec makes empty mean the default; verify by reading both rules next to the os-release bullet and the
      readonly bullet
- [x] 1.2 Replace the validate-first rule with: every check before any image change, in the order the spec fixes, only
      for preconditions the run needs; verify the wording against the apk-packages spec's order of checks
- [x] 1.3 Add the rule on command substitutions inside another command's arguments under Commands; verify the example
      shows the failing and the correct form

## 2. Skeletons

- [x] 2.1 Give both skeletons a `detect_platform` step that reads `ID` from `/etc/os-release` before `validate_options`,
      and `${VERSION-latest}` defaults; verify that both pass shellcheck with both optional checks (the POSIX one also
      with `--shell=sh` and `dash -n`), that an explicitly empty `VERSION` fails validation, and that detection succeeds
      against an `/etc/os-release` that assigns `VERSION`

## 3. Scaffold

- [x] 3.1 Switch the option defaults in `scripts/new_feature.ts` to `${NAME-default}` and update
      `scripts/checks_test.ts`; verify `deno test scripts/checks_test.ts` passes and a scaffolded sample passes
      shellcheck with both optional checks

## 4. Integration

- [x] 4.1 Run `just check` and confirm it passes; record the results in the PR's Validation section
