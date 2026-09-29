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

- `openspec/config.yaml` `rules.specs`: the Purpose's "Upstream sources:" list holds reference links only, one
  `- <label>: <url>` entry each; behavior-shaping sources, signing keys included, are Requirements and stay out of the
  list; a delta spec holds only the sections archive keeps.
- `.agents/knowledge/spec-workflow.md`: the Artifact map and Source of truth rows name one place per kind of link; Scope
  of specifications gains a second hand-edit exception — a PR that only edits the "Upstream sources:" list carries no
  change and bumps no version — and names the link kinds and entry format.
- `.agents/knowledge/references.md`: its pointer to feature specs names documentation among the per-feature facts.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Feature ids touched: none, so no version bump. No feature exists yet, so no spec needs migrating.
- Affects how every future feature spec records upstream links, and which PRs need an OpenSpec change.

## Acceptance

- `openspec instructions specs --json` for a change shows rules that put reference links (home or README, documentation,
  installation guide) in the Purpose's "Upstream sources:" list as `- <label>: <url>`, put behavior-shaping sources
  (signing keys included) only in Requirements, and limit a delta spec to the sections archive keeps.
- `spec-workflow.md` permits a PR that only edits the "Upstream sources:" list without an OpenSpec change or version
  bump, and its Source of truth row names one place per kind of link; `references.md` agrees.
- A uv-shaped spec written to these rules passes `openspec validate --strict`, and `just check` passes.
