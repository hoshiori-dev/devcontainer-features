# Tasks

## 1. Approval reconciliation and feature setup

- [x] 1.1 Carry the approved offline CLI, uv group access, skill-only reinstall, and Debian 11 fixture corrections into
      the planning artifacts; verify with `just spec-check`.
- [x] 1.2 Scaffold hf-cli at 1.0.0 with exactly the specified options and uv dependency; verify metadata with
      `just validate`.

## 2. Installation and user documentation

- [x] 2.1 Implement platform, user, Python, uv, version, and tagged download checks and the constrained upstream
      installer; verify defaults, pinned version, redirected sources, and all failure observations.
- [x] 2.2 Implement optional skill generation and install-twice behavior; verify duplicate tests and a network-disabled
      same-version skill-only install leave packages unchanged.
- [x] 2.3 Document installation scope, sources, runtime authentication, skills, proxies, and limitations in NOTES.md and
      the root feature table; generate README with `just docs` and verify `just docs-check`.
- [x] 2.4 Add compatibility, default, duplicate, pinned, skill, and redirected-source tests; verify `just test hf-cli`
      and `just test-scenarios hf-cli`.

## 3. Integration and acceptance evidence

- [x] 3.1 Add the uv_and_hf_cli global scenario covering uv's INSTALLER record, environment, empty mounted volume, and
      group write access; verify `just test-global` and empty/non-empty mounted-volume observations.
- [x] 3.2 Observe all specified failure cases, identical reinstall, tagged download logs, and the proxy-only build using
      disposable containers; record results against Acceptance in the PR.
- [x] 3.3 Review the final implementation against the spec and URL inventory, run `just check`, and verify every
      selected CI job passes; complete the PR description.
