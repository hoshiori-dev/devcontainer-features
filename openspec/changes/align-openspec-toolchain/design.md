# Design

## Context

See [proposal.md](proposal.md) for scope and acceptance. CI pins OpenSpec 1.13.2; local setup installs latest. The npm
registry reports stable 1.14.3 on 2026-10-23. Raw Markdown inventory finds 122 descriptions over 500 characters across
16 capabilities; the selected release's parser supplies the authoritative measurements.

## Goals / Non-Goals

- Preserve full contracts rather than only existing scenario coverage: compare every original obligation with the
  resulting complete specification, including conditions, exceptions, normative strength and accepted-risk reasons.
- Keep names, option tables and original scenarios unchanged: mechanically compare MODIFIED blocks with the baseline and
  verify option metadata against an applied preview.
- Keep every description within the tool's limit: measure using the selected release's parser and strict-validate both
  delta files and the resulting complete specifications.
- Keep the approval package separate from implementation: no tasks, toolchain edits, generated-file refresh, or main
  spec edits belong to the initial draft. Check its file list before publication.

## Decisions

### Compress prose before extracting independently named obligations

Preserve each original requirement anchor and all of its scenarios under a MODIFIED requirement. Extract independently
readable obligations into ADDED requirements with focused scenarios when concise phrasing cannot preserve all details.
Keep explicit qualifications in normative text rather than relying on examples to carry them. Use named cross-references
where an extracted requirement is needed to understand the retained one. The baseline is main, not the #176 preview;
clarifications of native package-manager behavior are separate changes, even if they appear more accurate.

Raising the limit, disabling strictness, moving obligations solely into scenarios, or silently dropping details would
not preserve the selected contract. Frozen archives remain historical records; this migration concerns current
contracts.

### One authoritative OpenSpec pin

Keep `.github/actions/setup-tools/action.yml` as the authoritative exact OpenSpec pin. The OpenSpec install line in
`.devcontainer/setup.sh` reads that installation target directly rather than independently tracking latest. Other tool
pins and environment configuration remain outside the migration.

At acceptance, compare `openspec --version` with the shared pin and query the npm registry's stable version. Report a
mismatch or unsuccessful lookup as an incomplete check; do not automatically raise the pin. These constraints guide the
upgrade review and add no version checker, update notification, or enforcement mechanism to the repository.

Duplicated local and CI constants were rejected because they can drift. Automatically installing latest was rejected
because a validation-rule change must be reviewed before it becomes required.

### Generated integrations and knowledge follow the selected release

Regenerate only through `openspec init --tools claude`, not `openspec update`, and compare the result with a fresh
scratch initialization. Reverify CLI flags and the archive/option-comparison behavior relied on by
`scripts/check_openspec.ts`; update its version-specific comments, the verified version/date in spec-workflow.md, and
the toolchain guidance in github/checks.md. Check CONTRIBUTING.md still accurately summarizes the workflow. Run the same
`just check` locally and in CI; no alternative strictness or length exemptions are introduced.

### Independent review of applied specifications

A writer prepares the deltas. A separate reviewer reads baseline and resulting whole specs, reports exact semantic
inconsistencies, and returns them to the writer until all are resolved. The coordinating review then verifies structural
preservation, description lengths, references, strict validation, and option equality. Reviewer previews are disposable:
apply deltas in an isolated worktree only, never synchronize the working branch's main specs before archive authority.
Remove verification worktrees and temporary files after review and confirm the worktree registry has no leftovers.

## Risks / Trade-offs

- The #176 preview overlaps these deltas. It remains a review reference, not a prerequisite to merge first. Archiving
  both packages unchanged would duplicate extracted obligations; reconcile or retire the preview before either archive.

- Extracted obligations increase navigation and scenario count. Prefer compression when sufficient, retain explicit
  references, and review the whole applied spec rather than judging shorter blocks alone.
- Passing parser checks does not prove semantic equivalence. Independent clause-by-clause review and coordinator
  verification supplement validation; unresolved meaning differences block publication of the package.
- Other open feature PRs may introduce long descriptions or conflict with these anchors. Inventory their current heads
  and strict-validation findings in the review record and coordinate their reconciliation before claiming the broader
  #129 rewrite complete. They retain their own approval packages; this PR does not silently rewrite another author's
  pending contract.
- The upgraded validator rejects the old main specs before archive. Report this as a migration state, prove both current
  CI compatibility and the isolated upgraded preview, and require the complete final `just check` after authorized
  archive.

## Open feature PR inventory

Snapshot on 2026-10-23: all four other open feature approval packages have zero descriptions over 500 characters using
OpenSpec 1.14.3's parser (maximum lengths: 441, 441, 424 and 416 characters respectively). Their contracts are not
copied into this change.

| PR   | Head                                       | Capability   | Descriptions over 500 |
| ---- | ------------------------------------------ | ------------ | --------------------: |
| #171 | `edac7ac6db6337c18caae7916f32b204d3855a30` | opencode     |                     0 |
| #172 | `3d590b3085045f68d27456da1a7e774918b9f67d` | antigravity  |                     0 |
| #173 | `975193ac010f4efe5ddd2524d85a842c0e3d4486` | pi           |                     0 |
| #174 | `c29b5649e87a93fbaddda92c7c91977bd12fa969` | hermes-agent |                     0 |

## Rewrite coverage

Baseline: `52bb16e`. Counts below cover the approval-package deltas; original scenarios remain under their owners.

| Capability                 | Original requirements | Modified | Added | Preserved original scenarios |
| -------------------------- | --------------------: | -------: | ----: | ---------------------------: |
| `apk-packages`             |                    22 |       10 |    27 |                           57 |
| `apt-packages`             |                    29 |       10 |    18 |                           64 |
| `betterleaks`              |                     7 |        3 |     7 |                           14 |
| `colab-cli`                |                    10 |        1 |     1 |                            4 |
| `deno`                     |                    13 |        4 |    14 |                           23 |
| `dnf-packages`             |                    26 |       13 |    24 |                           70 |
| `firewall`                 |                    28 |       17 |    23 |                           48 |
| `gitleaks`                 |                     7 |        4 |     8 |                           18 |
| `glab`                     |                     9 |        3 |     5 |                           13 |
| `hf-cli`                   |                    15 |        7 |    17 |                           25 |
| `hf-mount`                 |                     9 |        3 |     5 |                           12 |
| `nvidia-container-toolkit` |                     7 |        6 |     9 |                           20 |
| `openspec`                 |                    11 |        5 |    12 |                           19 |
| `pacman-packages`          |                    18 |       11 |    40 |                           48 |
| `uv`                       |                    16 |       11 |    28 |                           42 |
| `zypper-packages`          |                    28 |       14 |    27 |                           84 |
