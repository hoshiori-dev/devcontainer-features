# Tasks

## 1. Revised specification and environment selection

- [x] 1.1 Reconcile proposal, delta spec, and design with optional uv, first-party Python ordering and interpreter
      reuse; verify with `just spec-check`.
- [x] 1.2 Remove the hard dependency and implement interpreter selection, apt fallback, and optional uv version checks;
      verify metadata and Python reuse/failure observations.

## 2. Installation and documentation

- [x] 2.1 Apply equivalent fixed-source, wheel-only, version-constraint and cache rules to pip and uv; verify both
      redirected-source paths, pinning, hash failures, and proxy observations.
- [x] 2.2 Verify optional skills, install-twice behavior, and offline identical/skill-only installs leave packages
      unchanged on both pip and uv installations.
- [x] 2.3 Update NOTES and generate README with `just docs`; verify `just docs-check` and human documentation review.
- [x] 2.4 Add existing-Python, first-party Python, and unusable-earlier-candidate coverage; run `just test hf-cli` and
      `just test-scenarios hf-cli` on the selected compatibility images.

## 3. Integration and acceptance evidence

- [x] 3.1 Keep uv_and_hf_cli as an explicit optional composition; verify `just test-global` and empty/non-empty
      mounted-volume observations.
- [x] 3.2 Re-run all failure and proxy observations for the revised paths, and record results against Acceptance.
- [x] 3.3 Review implementation against the revised spec and URL inventory, run `just check`, verify selected CI jobs,
      and update the PR description for joint specification and implementation review.
