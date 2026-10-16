# Tasks

## 1. Installation and metadata

- [x] 1.1 Scaffold latex at version 1.0.0 with the approved options and compatibility matrix; verify metadata with just
      validate and just spec-check.
- [x] 1.2 Implement platform and option validation, signed OS dependencies, verified TinyTeX bundles, and user-owned
      installation; verify fresh-install, failure, ownership, and download scenarios.
- [x] 1.3 Implement profile/language package selection, font maps, caches, PATH, and repeat installation; verify actual
      compilation and replacement tests.
- [x] 1.4 Document package management, persistence, font/template limits, and the timing contract in NOTES.md; verify
      documented commands against the installed environment.

## 2. Behavioral coverage and editor guidance

- [x] 2.1 Add default and duplicate tests covering common tools, CJK PDFs, bibliography, highlighting, package
      management, and replaced files/packages; pass on every compatibility image and native architecture.
- [x] 2.2 Add profile, language, custom repository/package, incompatible-tree, option/platform failure, and integrity
      scenarios; verify all scenarios including full on both reference architectures.
- [x] 2.3 Add copyable LaTeX Workshop configuration and test its recipes; verify no editor settings are modified.
- [x] 2.4 Generate feature and root documentation with just docs and translate the root feature-list change into
      README.zh.md; verify just docs-check.

## 3. Integration and acceptance

- [x] 3.1 Run just check, just test latex, and just test-scenarios latex; resolve failures and record results against
      the proposal's Acceptance in the PR.
- [x] 3.2 Record the maintainer's acceptance of proceeding without additional reference timing evidence for this PR; the
      documented 180-second budget is not independently reverified by this revision.
- [x] 3.3 Review the final diff, pass the publication gate, push, and verify CI; reconcile approval and discussions,
      fill the PR description, and mark ready only when every Acceptance item is met.

## 4. Revised installation order

- [x] 4.1 Replace every target TinyTeX tree from the current archive, verify rollback, and refresh old command links.
- [x] 4.2 Verify last-installation-wins behavior for identical, smaller, full, and unmanaged installations; document it
      in NOTES.md.

- [x] 4.3 Include xecjk in Japanese-only installations and verify Japanese XeLaTeX compilation independently of Chinese
      support; retain the language-switching scenario as regression coverage.
- [x] 4.4 Retry failed default-route package installations through CTAN's router, bound tlmgr connection time, and retry
      GitHub transfers on every error; verify the retry path and the single attempt for a custom repository.
- [x] 4.5 Restrict the shared PATH bridge to TinyTeX binaries, bump the feature to 1.0.1, and verify that unrelated
      executables in the target user's .local/bin are not exposed through it.
