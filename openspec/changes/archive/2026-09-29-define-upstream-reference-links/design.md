# Design

## Context

See proposal.md - Why. OpenSpec 1.13.2, checked in a throwaway repository: a main spec keeps any extra text in its
Purpose and any extra section through `openspec validate --strict` and through archiving other changes; a new
capability's delta Purpose is copied into the main spec; for an existing capability a delta Purpose is ignored with a
warning; any other section in a delta (e.g. `## References`) is dropped without one. No CI check blocks a hand edit of
`openspec/specs/`, and such an edit selects no feature tests. The approval package in Approval gates of
`spec-workflow.md` is the one #7 defined (proposal, delta specs, design when warranted); this change adds one item to
it.

## Goals / Non-Goals

**Goals:**

- The rule text lives in `rules.specs` in brief and in `spec-workflow.md` in full, the rule pointing to the file —
  checked by reading both against each other.
- Only formats OpenSpec keeps are used: Purpose text and Requirements, no extra spec sections — checked by
  `openspec validate --strict` and an archive run on a sample spec.

**Non-Goals:**

- A custom OpenSpec schema or templates.

## Decisions

- **Reference links live in the Purpose.** The "Upstream sources:" list holds the upstream home or README, the
  documentation root, and the installation guide, one `- <label>: <url>` entry each, linking stable entry pages. The
  Purpose opens with its one- or two-sentence description; the list follows. Alternative: a Requirement per link —
  rejected, a link is not observable behavior and has no testable scenario, and the PR's Validation would carry a
  vacuous one. Alternative: a separate `## References` section — rejected, archive drops it from deltas silently.
- **Behavior-shaping sources live only in Requirements.** Download location, checksum or signature verification, and
  signing keys are stated with their URL in a Requirement, so deltas carry them and the package gate reviews them; they
  never also appear in the list. This moves signing keys out of the list.
- **Link-only edits carry no change.** A PR that only adds, updates, or removes entries of the list edits the main spec
  by hand, like a typo fix, and bumps no version; the PR diff is where it is reviewed. Alternative: a `skip_specs`
  change per link edit — rejected, a proposal, tasks, and two gates for one line cost more than the record is worth. A
  change that alters capabilities or leaves the list stale still corrects the Purpose by hand in its own PR, named in
  its proposal.
- **A Purpose correction travels with the approval package.** A main spec is the living contract, so the maintainer
  approves the corrected text, not a promise of it: the hand edit is committed before the draft opens and listed in the
  Approval gates section as part of the package. Alternative: the edit during implementation — rejected, it would change
  a main spec after the package gate without the gate having seen it.
- **Deltas hold only what archive keeps.** `rules.specs` says a delta spec holds `## Purpose` (new capabilities only)
  and the ADDED, MODIFIED, REMOVED, and RENAMED Requirements sections.
- **No custom schema.** Templates cannot be overridden without forking the whole `spec-driven` schema, instructions
  included, which would freeze upstream's instruction changes at each upgrade; `rules` reach the same agent at the same
  point.

## Risks / Trade-offs

- [A hand-edited Purpose skips the package gate] → The exception covers only the "Upstream sources:" list; a link that
  shapes behavior is a Requirement and still needs a change.
- [Upstream URLs rot] → Entries link stable entry pages; a fix is a link-only PR.
- [OpenSpec changes how archive treats Purpose or extra sections] → `spec-workflow.md` already requires re-verifying on
  upgrade; the delta rule names the observed behavior.
