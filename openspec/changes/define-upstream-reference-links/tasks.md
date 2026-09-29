# Tasks

## 1. OpenSpec rules

- [x] 1.1 In `openspec/config.yaml` `rules.specs`, replace the two upstream rules with the Purpose rule (description
      first, then an "Upstream sources:" list of `- <label>: <url>` reference links to stable entry pages) and the
      Requirement rule (behavior-shaping sources, signing keys included, never also in the list), and add the rule that
      a delta spec holds only `## Purpose` (new capabilities) and the four delta sections, pointing to
      `spec-workflow.md` for hand edits; verify with
      `openspec instructions specs --change define-upstream-reference-links --json`

## 2. Knowledge base

- [x] 2.1 In `.agents/knowledge/spec-workflow.md`: the Artifact map cell becomes "exceptions under Scope"; the Source of
      truth row names one place per kind of link; Approval gates adds a hand correction of a main spec's Purpose to the
      approval package, committed before the draft opens; Scope of specifications states the two hand-edit exceptions (a
      change that reshapes capabilities or leaves the list stale; a PR that only edits the list, with no change and no
      version bump) and the link kinds and entry format; verify by reading each passage against proposal.md - Acceptance
- [x] 2.2 In `.agents/knowledge/references.md`, name documentation among the per-feature facts; verify with
      `git grep -n -i upstream` that no remaining wording contradicts the new rules

## 3. Integration

- [x] 3.1 In a throwaway OpenSpec repository, write a uv-shaped spec to the new rules (reference links in Purpose,
      download and checksum source in a Requirement) and confirm `openspec validate --strict` passes
- [x] 3.2 Run `just check` and record each Acceptance item of proposal.md with its result in the PR's Validation section

## 4. Review fixes

- [x] 4.1 Name a Purpose correction a change carries wherever the approval package is listed — Lifecycle in
      `spec-workflow.md` and step 3 of the workflow skill — and let Artifact operations allow the two hand edits of a
      main spec's Purpose; verify by reading them against Approval gates and Scope of specifications
- [x] 4.2 List an edit of only a spec's "Upstream sources" list among the PRs that need no change in step 1 of the
      workflow skill; verify against Scope of specifications
- [x] 4.3 Make the reference-link kinds examples of links that do not shape behavior (changelog included) in
      `rules.specs` and `spec-workflow.md`; verify with
      `openspec instructions specs --change define-upstream-reference-links --json` that all specs rules are injected
