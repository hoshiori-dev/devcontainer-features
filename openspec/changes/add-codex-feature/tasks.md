# Tasks

Sections 1–4 record the original implementation at `a6c5ac2`. Section 5 tracks the requested revision and awaits renewed
package approval.

## 1. CLI installation

- [x] 1.1 Scaffold the feature at 1.0.0 with Node 24, project volume metadata, and target coverage; verify metadata
      validation.
- [x] 1.2 Implement stable npm release selection and integrity-preserving installation outside state; cover
      exact/latest, invalid input, replacement, and install-twice behavior in tests.

## 2. Private runtime state

- [x] 2.1 Implement build-prepared home links and bounded creation-time mount/path/access checks with confined repair;
      test missing mounts, conflicts, repeated initialization, changed homes/UIDs, and external symlinks.
- [x] 2.2 Select file credential storage while preserving compatible configuration and managed policy; test native CLI
      configuration and conflicting backends without exposing credentials.

## 3. Supported entry points and persistence

- [x] 3.1 Document container-terminal use, optional first-party IDE integrations, volume lifetime and recovery, and
      manual authenticated restoration; verify NOTES and generated English/Chinese documentation.
- [x] 3.2 Verify isolated projects and two fresh containers sharing a volume using private fixtures and actual CLI
      state; record results without state contents.
- [x] 3.3 Record the maintainer's waiver of real sign-in and authenticated session restoration verification in PR
      validation. On 2026-10-22 the maintainer explicitly authorized proceeding without this check; it is waived, not
      executed or reported as an observed pass.

## 4. Integration validation

- [x] 4.1 Run just check, just test codex, and just test-scenarios codex; fix failures and record scenario coverage and
      supported architectures.
- [x] 4.2 Reconcile discussion and prepare the implementation publication and PR validation/checklist for review; retain
      the authenticated-check waiver explicitly. CI and review admission follow the repository's finish workflow.

## 5. Requested compatibility and Node isolation revision

- [ ] 5.1 After renewed package approval, implement the native-package support boundary: reject uncovered systems and
      hardware, warn and attempt covered untested targets, and verify real prerequisite/execution failures.
- [ ] 5.2 Replace npm and the shared Node dependency with checksum-verified complete native packages; rewrite helpers to
      run without Node, and verify companions, standalone execution, integrity failures, staged replacement,
      idempotency, and unchanged global Node state.
- [ ] 5.3 Add composition scenarios for explicit Node/tool versions, a partial Node options object, and an empty Node
      options object; assert upstream defaults and run both Codex and its initializer.
- [ ] 5.4 Run a two-stage image check with Codex installed before the actual Node Feature; verify subsequent explicit
      and default Node configuration, preserved Codex state, and CLI/initializer execution.
- [ ] 5.5 Regenerate documentation, run local checks and affected CI, and replace the superseded PR validation record;
      retain the maintainer's real-account verification waiver.
