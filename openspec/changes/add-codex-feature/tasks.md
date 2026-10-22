# Tasks

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
