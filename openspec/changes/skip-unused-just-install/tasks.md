# Tasks

## 1. Skip unused installs

- [x] 1.1 Disable just in plan and the shared feature-test action; inspect all three test-mode callers.
- [x] 1.2 Disable just in PR title, checklist, archive-verdict, and Release verify; inspect their script commands.
- [x] 1.3 Update toolchain knowledge and verify it matches the callers and the unchanged installer/default.

## 2. Integration verification

- [x] 2.1 Run just check and record the results and invariant checks in the PR Validation section.
- [ ] 2.2 Inspect executed PR/CI job steps to confirm successful jobs skip rust-just; record the unexecuted Release
      verification limitation in the PR Validation section.
