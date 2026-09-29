# Tasks

## 1. Artifact roles in the knowledge base

- [x] 1.1 Add an "Artifact roles" section to `.agents/knowledge/spec-workflow.md` after the Artifact map: the role of
      proposal, specs, design, and tasks, the invariant test, the information test, and the two Acceptance lists; verify
      by reading it against proposal.md - What Changes
- [x] 1.2 Align the rest of `spec-workflow.md`: Source of truth (acceptance of every change is its proposal's
      Acceptance, pointing to scenarios for feature behavior), Lifecycle (propose stops before `tasks.md`; tasks written
      after approval), Approval gates (the package is proposal, delta specs, and design when warranted; `tasks.md` does
      not exist yet), Specifications and issues (no `tasks.md` link in a draft); verify with
      `git grep -n "tasks.md" .agents/knowledge/spec-workflow.md` that no line contradicts the new timing

## 2. OpenSpec rules

- [x] 2.1 In `openspec/config.yaml`, add the approval condition as the first `rules.tasks` rule, and add
      `rules.proposal` and `rules.design` rules that state the roles briefly and point to the Artifact roles section;
      verify with `openspec instructions proposal|design|tasks --change write-tasks-after-approval --json` that each
      shows the new rules

## 3. Workflow skill, PR template, issue form

- [x] 3.1 In `.agents/skills/github-project-workflow/SKILL.md` step 3, open the draft without `tasks.md` (delete one a
      flow wrote early) and, after the reconciliation, write it through `openspec instructions tasks` before
      implementing; verify by reading the step against spec-workflow.md - Lifecycle
- [x] 3.2 In `.github/pull_request_template.md`, `.github/ISSUE_TEMPLATE/03-task.yml`, `02-feature.yml`, and the
      synchronization list of `.agents/knowledge/github-workflow.md`, point acceptance to the proposal's Acceptance;
      verify `scripts/check_pr_body.ts` still passes on #7's body and `git grep -n "tasks.md" -- .github` shows no
      acceptance role left for `tasks.md`

## 4. Integration

- [x] 4.1 In a throwaway OpenSpec repository carrying this `openspec/config.yaml`, follow the generated propose skill
      for a small change and confirm it writes no `tasks.md`, ends the proposal with both Acceptance lists, and reports
      the package as ready
- [x] 4.2 Run `just check` and record each Acceptance item of proposal.md with its result in the PR's Validation section

## 5. Review fixes

- [x] 5.1 Point the remaining acceptance definitions to the proposal's Acceptance: `github-workflow.md` (Acceptance row,
      Other contracts) and the gate report in `agent-authority.md`; verify with `git grep -n "scenario"` over the
      knowledge base that no line names scenarios as the whole acceptance
- [x] 5.2 Give the information test a destination for a change without specs (the knowledge base); verify by reading
      Artifact roles in `spec-workflow.md`
- [x] 5.3 Limit the feature-only `rules.tasks` rules to feature changes; verify with
      `openspec instructions tasks --change write-tasks-after-approval --json`
- [x] 5.4 Open the draft in the workflow skill only once the approval package is committed, and split the PR template's
      gate item so a ready PR can tick it truthfully (the archive half is the item `spec-archived` tracks); verify by
      reading step 3 and the checklist against `github-workflow.md`
