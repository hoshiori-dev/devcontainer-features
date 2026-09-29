---
name: github-project-workflow
description: >-
  Runs this repository's GitHub issue and pull-request lifecycle: taking or creating an issue,
  opening the draft PR with its OpenSpec change, reconciling after a maintainer's approval,
  finishing and marking a PR ready, archiving on command, publishing anything to GitHub, and
  diagnosing a failing check. Use when taking, creating, updating, or completing an issue or pull
  request; before any gh write (issue, PR, comment); or when a CI check is red. Not for changing
  this repository's lifecycle policy, rulesets, or required checks without a maintainer's approval.
---

# devcontainer-features GitHub Workflow

Tool path: authenticated `gh`; `gh api` for comments and review threads. Every metadata change (assignee, type, state)
is an explicit call — GitHub has no slash commands. This skill applies `.agents/knowledge/github-workflow.md` (objects
in use), `.agents/knowledge/git-workflow.md` (branches, titles), `.agents/knowledge/spec-workflow.md` (the OpenSpec
gates), and `.agents/knowledge/agent-authority.md` (what you may do alone).

## Take work

1. Read the issue; confirm it is open and its outcome is concrete. If another identity is assigned, stop and ask. An
   issue with no OpenSpec change yet is taken by committing the change to the draft PR first (step 3) and stopping there
   until a maintainer closes the package deliberation in conversation; the change's scenarios are then the acceptance
   criteria. A harness or tooling issue gets a change with `skip_specs: true`; a typo or dependency bump needs none.
2. Assign yourself (`gh issue edit <n> --add-assignee @me`), re-read, and confirm you are the sole assignee.
3. `gh issue develop -c <n>` to create and check out the linked branch; push it and open a draft PR immediately
   (`gh pr create --draft`) with `Closes #<n>` and a body built from `.github/pull_request_template.md`. The draft PR is
   the claim and the work log. The draft opens once the approval package is complete — the proposal, the delta specs,
   and `design.md` when warranted, created through OpenSpec's propose flow and passing `just spec-check`; a `tasks.md`
   the tool generated alongside is pushed but marked as after-approval and kept out of the review — and the body's
   `Phase:` line reads `specification` while Changes and Validation keep their reserved line. Then stop. The maintainer
   discusses on the PR and directs changes in conversation; push each through the publish gate. When the maintainer
   closes the package deliberation in conversation, read the PR's comments
   (`gh api repos/hoshiori-dev/devcontainer-features/issues/<n>/comments`) and its review threads with their resolution
   state (the GraphQL `reviewThreads` connection, field `isResolved`); list every unresolved thread, every adjustment
   requested in the discussion that the change does not carry, and every pair of conclusions that contradict each other;
   ask the maintainer to confirm them; and start the tasks and the implementation only when nothing is open or the open
   items are confirmed. Record the closing on the `Approval:` line. The same reconciliation runs again at the
   implementation deliberation, before the archive.
4. Keep the PR description current; comment major discoveries and decisions. The repository is public: credentials,
   tokens, internal hosts, and personal data never go into an issue, PR, commit, or log.
5. Abandon by un-assigning, closing the draft with a status comment, and leaving the issue open.

## Create issues

An issue opens when the requirement appears, carrying the raw requirement and no acceptance criteria; it links the
OpenSpec change once that exists. Issues derived from a change's tasks are optional, one per task that independently
earns its own state, each naming the scenarios it closes. Never copy acceptance criteria into an issue.

Non-interactive creation ignores the forms: build the body by mirroring the form's `### <label>` headings
(`.github/ISSUE_TEMPLATE/01-bug.yml`, `02-feature.yml`, `03-task.yml`) and set the form's type in the same call:
`gh issue create --title "…" --body-file body.md --type Bug|Feature|Task`. Milestones, Projects, and priority are
deliberately not used (`github-workflow.md`); never create them.

## Publish gate

GitHub publication cannot be reliably undone: bodies, comments, commit messages, tags, and their notification copies
survive deletion, and public content is indexed within minutes. Every remote or publishable write passes this gate.

1. Assemble the exact final payload as files in a scratch directory outside the repository. For a pull request include
   `title.txt`, `body.md`, `commits.txt` from `git log BASE..HEAD --format=full`, `diff.patch` from
   `git diff BASE...HEAD`, and every attachment — a PR publishes its commit messages and diff, not only its description.
2. Review that directory independently: dispatch a clean-context subagent whose whole prompt is the review instruction,
   or, without subagent support, re-read every file from disk and note `Review mode: file-only (not clean-context)`.
   Judge only what the files contain, never what you remember intending to publish.
3. The review checks every line for credentials and secrets, real personal data, internal-only hosts/URLs/identifiers,
   unrelated or generated content in the diff, AI or tool attribution (`Co-Authored-By` for an AI, "Generated with …"),
   @-mentions and cross-references that would notify uninvolved people, and regret-worthy wording. It ends with exactly
   `SAFE TO PUBLISH: YES` or `SAFE TO PUBLISH: NO`; any secret, personal-data, internal-context, or attribution finding
   means NO.
4. Treat anything other than a verbatim `SAFE TO PUBLISH: YES` as NO. Fix every finding, rebuild the directory, and
   review again. A secret that reaches GitHub is compromised even after deletion — tell a maintainer so it is rotated.
5. Confirm applicable approval, execute non-interactively, and read the result back. Published content must be
   byte-identical to the reviewed content; any edit after the verdict requires a fresh review.

## Finish

1. Run `just check`, and for a feature change `just test <id>` and `just test-scenarios <id>` (docker is available in
   the dev container). All CI checks green — `.agents/knowledge/github/checks.md` maps jobs to commands; diagnose a red
   run with `.agents/skills/github-project-workflow/scripts/run_log_digest.ts --run-id <id>`. Never fetch full logs,
   never weaken a check.
2. Complete the PR checklist and update the final description. Set the `Phase:` line to `implementation`; replace the
   reserved line of Changes with permalinks to the commits (the exact lines for a local change, the whole file or
   directory for a broad one) and the reserved line of Validation with each scenario and its result, linking the CI run;
   and confirm every task of the change is ticked. Then follow `.agents/knowledge/agent-authority.md`: green checks are
   evidence, not acceptance. Under it you may mark the PR ready (`gh pr ready`) and request review once the package gate
   closed in this conversation, then hand the maintainer the report it defines. Marking ready opens the implementation
   deliberation, so `spec-archived` is red until the archive commit lands: that red is the merge block, not a defect.
   Archive only when the maintainer commands it in the conversation: the `openspec-archive-change` skill
   (`/opsx:archive`), `just spec-check`, commit, push. A commit after the archive commit spends the closing; say so and
   ask again. Auto-merge is not used; never edit the policy, protections, or required checks to unblock yourself —
   propose the change to a maintainer instead.
3. A maintainer merges; the closing keyword closes the linked issue — verify it closed. Merging a version bump publishes
   it: the Release workflow publishes to GHCR and tags `<id>/v<version>` (`checks.md`).
