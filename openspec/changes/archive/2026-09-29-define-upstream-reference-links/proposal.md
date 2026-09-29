# Proposal

Implements [#4](https://github.com/hoshiori-dev/devcontainer-features/issues/4).

## Why

Each feature's spec should hold the upstream project's reference links (home or README, documentation root, installation
guide), and the Purpose's "Upstream sources:" list is the place for them. The rules around that list leave three gaps,
observed with OpenSpec 1.13.2:

- Archive ignores a delta's Purpose for an existing capability, so the list changes only by hand, and the hand-edit
  exception in `.agents/knowledge/spec-workflow.md` covers only replacing an upstream source; adding or removing a link
  has no compliant path.
- Archive silently drops any section of a delta spec other than `## Purpose` and the delta sections, so a
  `## References` section written in a change is lost.
- The list is told to include signing keys, while behavior-shaping sources belong in Requirements, and the
  source-of-truth table allows either, so one URL can live in two places.

## What Changes

- Every kind of upstream link has one place in a feature's spec: reference links (upstream home or README, documentation
  root, installation guide) in the Purpose's "Upstream sources:" list as `- <label>: <url>`; behavior-shaping sources
  (download location, checksum or signature verification, signing keys) only in Requirements.
- Adding, updating, or removing an entry of the "Upstream sources:" list has a documented path: a PR that edits only the
  list carries no OpenSpec change and bumps no version; a change that leaves the list stale corrects it by hand in its
  own PR.
- A hand correction of a main spec's Purpose that a change carries is committed with the change's approval package, so
  the package gate reviews the corrected text itself, not only the proposal's mention of it.
- Delta specs hold only the sections archive keeps, so no link written in a change is silently lost.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `openspec/config.yaml` (`rules.specs`), `.agents/knowledge/spec-workflow.md` (Artifact map, Source of truth,
  Approval gates, Scope of specifications), `.agents/knowledge/references.md`.
- Feature ids touched: none, so no version bump. No feature exists yet, so no spec needs migrating.
- Affects how every future feature spec records upstream links, and which PRs need an OpenSpec change.

## Acceptance

**Becomes true:**

- `openspec instructions specs --json` for a change shows rules that put reference links in the Purpose's "Upstream
  sources:" list as `- <label>: <url>`, put behavior-shaping sources (signing keys included) only in Requirements, and
  limit a delta spec to the sections archive keeps.
- `spec-workflow.md` names one place per kind of link and permits a PR that only edits the "Upstream sources:" list
  without an OpenSpec change or version bump; `references.md` agrees with it.
- `spec-workflow.md` lists a hand correction of a main spec's Purpose among the files of the approval package, committed
  before the draft PR opens.
- A uv-shaped spec written to these rules passes `openspec validate --strict`.

**Stays true:**

- A behavior-shaping upstream source still reaches the spec only through a change and the package gate.
- Project-wide references stay in `.agents/knowledge/references.md`.
- No approval gate or check changes; `just check` passes.
