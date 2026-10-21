# Design

## Context

The preview targets only `hf-mount` and `pacman-packages`; see [proposal.md](proposal.md) for scope and acceptance.
OpenSpec 1.14.3 measures the parsed description before scenarios, including option tables. The original specifications
contain 3 and 11 descriptions over 500 characters respectively. The repository's CI still uses OpenSpec 1.13.2.

## Goals / Non-Goals

- Preserve original requirement anchors and their complete scenario blocks byte-for-byte before formatting; compare
  original and delta blocks, then compare normalized scenario content after formatting.
- Keep extracted behavior inside ADDED requirements with a SHALL statement and a focused scenario; validate the delta
  and a combined preview of each resulting main specification with OpenSpec 1.14.3 in strict mode.
- Retain every option table unchanged; compare the option requirements against the original metadata.
- Keep the draft limited to planning artifacts. No tasks, main-spec edits, implementation changes, tool upgrade, or
  archive are part of this review package; verify the diff contains only this change directory.

## Decisions

### Compress small descriptions; split independent obligations

`hf-mount` demonstrates a short rewrite and a download contract split into asset selection, latest-release resolution,
and transport trust. `pacman-packages` demonstrates the harder case: target syntax, native resolution, trust, and
configuration lifetime become separately named obligations. Existing scenarios stay under their original requirements so
no original coverage disappears; new scenarios illustrate the extracted obligations.

Moving all qualifications into scenarios was rejected because constraints must remain explicit in requirement text.
Replacing native behavior with a simpler contract was rejected because this preview must preserve current semantics.
Raising the tool pin, dropping strictness, and modifying all features were excluded from the selected preview.

The ADDED blocks describe extracted existing behavior, not new feature capabilities. Delta specs are necessary here
because the requested change specifically restructures existing requirement blocks; this is not an ordinary document
edit to be represented by `skip_specs: true`. Main specifications continue to change only through the archive flow.

### Preserve source ownership and accepted risks

Existing URLs that define behavior stay in requirement descriptions, each at one location per resulting capability.
Native behavior and its risks stay together: selecting older package versions, explicit access to a sync-only
repository, repeated version alternation, unverified downloads or databases, and temporary configuration limits remain
explicit. No upstream behavior is reinterpreted or expanded; the original specifications are the baseline for this
editorial change. Implementation and existing tests are cross-checks, not a reason to silently change an accepted
contract.

### Review the cost of smaller blocks

The combined preview has 11 `hf-mount` requirements (9 before) and 42 `pacman-packages` requirements (18 before). The 26
new blocks each need a scenario. Smaller descriptions therefore increase navigation and scenario volume; this preview
deliberately makes that cost visible rather than presenting the character limit as a free readability gain.

Archive appends extracted requirements after existing ones. The resulting pacman contract therefore needs more
navigation; named requirement references guide the reader, but this cost remains part of the maintainer's decision.

## Description lengths

Lengths below use OpenSpec 1.14.3's parser. The after column measures the retained requirement; extracted obligations
are listed in the next section, each with its own description no longer than 500 characters. These numbers are not
claims about total document-size reduction.

| Capability        | Retained requirement                                                  | Before | After |
| ----------------- | --------------------------------------------------------------------- | -----: | ----: |
| `hf-mount`        | Option version                                                        |    574 |   450 |
| `hf-mount`        | Downloads come from the upstream GitHub release and rely on TLS alone |   1077 |   446 |
| `hf-mount`        | Installing twice                                                      |    501 |   383 |
| `pacman-packages` | Full system upgrade                                                   |   1499 |   491 |
| `pacman-packages` | Entries are validated before anything changes                         |   1670 |   495 |
| `pacman-packages` | Entries select packages as pacman matches them                        |   3345 |   478 |
| `pacman-packages` | Package index refresh                                                 |    662 |   269 |
| `pacman-packages` | Repository authentication stays in effect                             |   1278 |   463 |
| `pacman-packages` | Packager key import                                                   |   1224 |   408 |
| `pacman-packages` | Clean package caches                                                  |    638 |   416 |
| `pacman-packages` | Installing the feature twice                                          |   1921 |   462 |
| `pacman-packages` | Installation controls are validated before changes                    |    875 |   458 |
| `pacman-packages` | Parallel downloads are bounded                                        |   2541 |   448 |
| `pacman-packages` | Unsupported download controls stay native                             |    702 |   340 |

## Split map

| Original requirement                                                            | Extracted requirements                                                                                                                                                                                                |
| ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| hf-mount: Downloads come from the upstream GitHub release and rely on TLS alone | Latest release resolution; Download transport and credentials                                                                                                                                                         |
| pacman: Full system upgrade                                                     | Upgrade replacements; Listed entries may select older versions                                                                                                                                                        |
| pacman: Entries are validated before anything changes                           | Accepted target syntax; Accepted repository qualifier syntax; Slash validation diagnostics; Relative paths resembling qualified targets                                                                               |
| pacman: Entries select packages as pacman matches them                          | Qualified target resolution; Unknown repositories fail after synchronization; Qualified targets are not pins; Explicit repository reach; older-version selection is owned by Listed entries may select older versions |
| pacman: Package index refresh                                                   | Unsigned database trust                                                                                                                                                                                               |
| pacman: Repository authentication stays in effect                               | Image repository configuration is preserved; Temporary configuration preserves trust                                                                                                                                  |
| pacman: Packager key import                                                     | Packager key lookup identity; Packager Web Key Directory lookup; Packager keyserver fallback                                                                                                                          |
| pacman: Clean package caches                                                    | Custom cache paths remain unmanaged                                                                                                                                                                                   |
| pacman: Installing the feature twice                                            | Download controls do not persist; Repeated target selection can alternate versions                                                                                                                                    |
| pacman: Installation controls are validated before changes                      | Accepted parallel download values                                                                                                                                                                                     |
| pacman: Parallel downloads are bounded                                          | Temporary download configuration; Download configuration lifecycle; Effective parallel download value is confirmed; Parallel download accepted risks                                                                  |

The other retained requirements need only compression. No option is added, changed, renamed, or removed, so there is no
changed-option table.

## Risks / Trade-offs

- Splitting can hide interactions across blocks. Original integration scenarios remain in place and the split map
  identifies where extracted obligations live; semantic review compares each original description with all its parts.
- More requirements create more reading and maintenance work. The maintainer reviews this concrete sample before any
  expansion to the rest of the collection.
- Passing validation proves structural validity and length, not semantic equivalence. Independent reader review checks
  whether the proposed text preserves each original obligation and accepted risk.
- Repository-wide 1.14.3 validation still fails on untouched main specs, and generated-file checks require CI's pinned
  version. This PR does not claim to fix #129; targeted 1.14.3 checks and the full checks under 1.13.2 serve different
  purposes.
