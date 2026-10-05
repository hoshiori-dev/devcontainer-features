# Tasks

## 1. Checks

- [x] 1.1 Add `.shellcheckrc` at the repository root enabling `require-variable-braces` and `require-double-brackets`;
      verify that plain `shellcheck` reports SC2250 and SC2292 on a sample bash script with an unbraced variable and a
      `[ … ]` test, and neither on a POSIX `sh` script that tests with `[ … ]` and braces its variables
- [x] 1.2 In `.agents/knowledge/shell-style.md`, replace the sentence that asks authors to run the two checks by hand
      with one that says `.shellcheckrc` enables them wherever shellcheck runs; verify that no other file tells authors
      to pass the two checks by hand

## 2. Integration

- [x] 2.1 Run `just check` and confirm it passes with no file under `src/` or `test/` changed; record the results in the
      PR's Validation section
