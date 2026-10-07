# Tasks

## 1. Scenario migration

- [x] 1.1 Classify and rename all 63 remaining scenario keys, scripts, directories, and active references; verify
      unchanged configuration and assertions against the rename mapping.
- [x] 1.2 Remove the migration exception from testing.md and check the CONTRIBUTING overview and scaffold; verify
      documentation consistency and existing scaffold tests.

## 2. Naming validation

- [x] 2.1 Add shared prefix validation to feature and global checks with actionable diagnostics; verify table tests for
      valid prefixes, invalid names, and mixed lists.
- [x] 2.2 Review both feature and global call sites and retain existing reserved-name tests; remove the CLI subprocess
      integration test and Deno execution permission as directed, without adding a replacement test.

## 3. Integration verification

- [x] 3.1 Run just check and inspect just affected; verify source, compatibility, workflow, and fixed CLI names remain
      unchanged.
- [x] 3.2 Run affected feature and global container tests locally or in CI; record each Acceptance item, results, and
      limitations in the PR Validation section.
