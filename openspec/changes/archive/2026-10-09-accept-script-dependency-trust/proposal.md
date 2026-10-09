# Proposal

Implements [#131](https://github.com/hoshiori-dev/devcontainer-features/issues/131).

## Why

The administration scripts run what their dependencies' publishers release, with no lock file, and nothing in the
knowledge base says whether that is accepted. The threat model names "a dependency that the scripts, workflows, or
development environment run", the Accepted risks list is introduced as what the collection accepts "for every feature",
and so a review reports the missing lock file each time it meets a job with a write token, as one did on #124. The
maintainer decided on 2026-10-08 that a risk which needs a widely used, well-maintained publisher to be compromised is
acceptable here, as it already is for what the features install.

## What Changes

- **One accepted risk for administration tooling.** `review-guidance.md` gains, beside the list the collection accepts
  for every feature, a list for administration tooling with one entry:

  > A dependency of an administration script that comes from a widely used, well-maintained publisher (the Deno standard
  > library on JSR, for example) is trusted as published when the script imports it by exact version. What that package
  > imports in turn, from whatever publisher, is its publisher's choice and resolves within the ranges it declares, and
  > the repository keeps no lock file. Report an import without an exact version, and a directly imported package whose
  > publisher does not meet that bar.

- **The overview follows.** `SECURITY.md` says the same in its list of the risks the project knows about and accepts.

## Capabilities

### New Capabilities

None. This change edits the harness only (`skip_specs: true`).

### Modified Capabilities

None.

## Impact

- Files: `.agents/knowledge/review-guidance.md` (Accepted risks) and `SECURITY.md` (the risks we know about and accept).
- Feature ids touched: none, so no version bump. No file under `src/`, `test/`, or `openspec/specs/` changes.
- No script, workflow, permission, or setting changes, and `deno.json` keeps `"lock": false`. The exposure is what it is
  on `main` today: the `publish` job of `release.yml` and, once #124 merges, the Labels workflow each run a script that
  reaches `jsr:@std/internal` through a range.
- A review that finds the missing lock file no longer reports it. It still reports an import without an exact version
  and a directly imported package whose publisher is outside the entry's bound.
- `CONTRIBUTING.md` was checked and stays: it names a dependency bump as a kind of pull request and does not speak of
  accepted risks.

## Acceptance

**Becomes true:**

- `review-guidance.md` holds the entry above, word for word, in a list for administration tooling under Accepted risks,
  and the list for features keeps its five entries.
- `SECURITY.md` names the same risk and its bound among the risks the project knows about and accepts.

**Stays true:**

- The threat model's Administration row still names a dependency the scripts, workflows, or development environment run.
- The rule that a risk one feature accepts is stated in its spec, and that one the spec does not state is reported, is
  unchanged.
- `deno.json` keeps `"lock": false`, no lock file is added, and no script's imports change.
- No workflow gains or loses a permission, a trigger, or a step.
- No file under `src/`, `test/`, or `openspec/specs/` changes, and `just check` passes.
