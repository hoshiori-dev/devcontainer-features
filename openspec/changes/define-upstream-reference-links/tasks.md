# Tasks

## 1. OpenSpec rules

- [ ] 1.1 In `openspec/config.yaml` `rules.specs`, replace the two upstream rules with the Purpose rule (description
      first, then an "Upstream sources:" list of `- <label>: <url>` reference links) and the Requirement rule
      (behavior-shaping sources, signing keys included, never also in the list), and add the rule that a delta spec
      holds only `## Purpose` (new capabilities) and the four delta sections; verify with
      `openspec instructions specs --change define-upstream-reference-links --json` that the new rules are injected

## 2. Knowledge base

- [ ] 2.1 In `.agents/knowledge/spec-workflow.md`, change the Artifact map cell to "exceptions under Scope", the Source
      of truth row to one place per kind of link, the Scope exception paragraph to the two hand-edit exceptions (stale
      Purpose in a change's PR; link-only PR without a change or version bump), and the feature-specific paragraph to
      name the link kinds and the entry format; verify by reading the section against design.md
- [ ] 2.2 In `.agents/knowledge/references.md`, name documentation among the per-feature facts; verify with
      `git grep -n -i upstream` that no remaining wording contradicts the new rules

## 3. Integration

- [ ] 3.1 In a throwaway OpenSpec repository, write a uv-shaped spec following the new rules (docs links in Purpose,
      download and checksum source in a Requirement) and confirm `openspec validate --strict` passes
- [ ] 3.2 Run `just check` and record the results in the PR's Validation section
