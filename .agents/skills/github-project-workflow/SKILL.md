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

Tool path: authenticated `gh`; `gh api` for comments and review threads. Every metadata change (assignee, type, label,
parent, blocked by, Priority, state) is an explicit call — GitHub has no slash commands. This skill applies
`.agents/knowledge/github-workflow.md` (objects in use), `.agents/knowledge/git-workflow.md` (branches, titles),
`.agents/knowledge/spec-workflow.md` (the OpenSpec gates), and `.agents/knowledge/agent-authority.md` (what you may do
alone).

## Take work

1. Read the issue; confirm it is open and its outcome is concrete. If another identity is assigned, stop and ask. An
   issue with no OpenSpec change yet is taken by committing the change to the draft PR first (step 3) and stopping there
   until the pull request carries `spec:approved`; the proposal's Acceptance, with the scenarios it points to, is then
   the acceptance criteria. A harness or tooling issue gets a change with `skip_specs: true`; a typo, a dependency bump,
   or an edit of only a spec's "Upstream sources" list needs none.
2. Assign yourself (`gh issue edit <n> --add-assignee @me`), re-read, and confirm you are the sole assignee.
3. `gh issue develop -c <n>` to create and check out the linked branch; once the approval package is committed, push it
   and open a draft PR (`gh pr create --draft`) with `Closes #<n>` and a body built from
   `.github/pull_request_template.md`. The draft PR is the claim and the work log. The draft opens once the approval
   package is complete — the proposal, the delta specs, `design.md` when warranted, and any Purpose correction the
   change carries (`spec-workflow.md`, Scope of specifications), created through OpenSpec's propose flow and passing
   `just spec-check`; no `tasks.md` (the flow stops before it; delete one it wrote anyway) — and the body's `Phase:`
   line reads `specification` while Changes and Validation keep their reserved line. Then stop. The maintainer discusses
   on the PR and directs changes in conversation; push each through the publish gate. The package approval is the label
   `spec:approved` on the pull request (`spec-workflow.md`, Approval gates), read by recomputing it, never from the bare
   label: `just pr-labels <pr>` prints the state the rules give the pull request now, and anything but `spec:approved`
   is not approved. When it prints `spec:approved`, read the PR's comments
   (`gh api repos/hoshiori-dev/devcontainer-features/issues/<pr>/comments`, where `<pr>` is the pull request number, not
   the issue's: a PR's conversation lives under the issues API with its own number) and its review threads with their
   resolution state (the GraphQL `reviewThreads` connection, field `isResolved`); list every unresolved thread, every
   adjustment requested in the discussion that the change does not carry, and every pair of conclusions that contradict
   each other; ask the maintainer to confirm them; and only when nothing is open or the open items are confirmed, write
   `tasks.md` from `openspec instructions tasks --change <name> --json` and implement. Record each reconciliation on the
   `Approval:` line. The same reconciliation runs again at the implementation deliberation, before the archive. An agent
   never adds `spec:approved` on its own judgment. When a maintainer tells you in the current conversation to add it and
   names the pull request, name the pull request and its head commit in your reply, add the label
   (`gh pr edit <pr> --add-label spec:approved`), and read the workflow's record back with `just pr-labels <pr>`: the
   comment it keeps names the approved commit. When `just pr-labels <pr>` disagrees with the labels on the pull request
   and a missed run explains it, a dispatch reconciles that one pull request and cannot approve
   (`gh workflow run pr-labels.yml -f number=<pr>`).
4. Keep the PR description current; comment major discoveries and decisions. The repository is public: credentials,
   tokens, internal hosts, and personal data never go into an issue, PR, commit, or log.
5. Abandon by un-assigning, closing the draft with a status comment, and leaving the issue open.

## Create issues

An issue opens when the requirement appears, carrying the raw requirement and no acceptance criteria; it links the
OpenSpec change once that exists. Issues derived from a change's tasks are optional, one per task that independently
earns its own state, each naming the Acceptance items or scenarios it closes. Never copy acceptance criteria into an
issue.

Non-interactive creation ignores the forms: build the body by mirroring the form's `### <label>` headings
(`.github/ISSUE_TEMPLATE/01-bug.yml`, `02-feature.yml`, `03-task.yml`, `04-epic.yml`) and set the form's type and the
area label in the same call:

```sh
gh issue create --title "…" --body-file body.md --type <type> --label area:<area>
```

- `<type>` is the form's type: Bug, Feature, Task, or Epic.
- `area:<area>` is one of the labels `github-workflow.md` defines (Areas), prefix included: `area:feature`, `area:ci`,
  `area:scripts`, `area:spec-workflow`, or `area:harness`. A label that does not exist makes the call fail: stop and
  report it, never create a label (`agent-authority.md`).
- Add `--parent <n>` and `--blocked-by <n>` when the request states the relationship (`github-workflow.md`,
  Relationships); on an existing issue use `gh issue edit <n> --parent <m>` and `--add-blocked-by <m>`.
- An Epic is created only on a maintainer's word (`github-workflow.md`, Epics) and gets no Priority.
- Priority, on a Feature, Bug, or Task: name the value you propose in the message that asks for the go-ahead to publish,
  not only inside the reviewed payload. After the go-ahead, write it with exactly this call — one value, the option by
  name (Urgent, High, Medium, Low):

  ```sh
  echo '{"issue_field_values":[{"field_id":28240578,"value":"High"}]}' |
    gh api -X POST repos/hoshiori-dev/devcontainer-features/issues/<n>/issue-field-values --input -
  ```

  Never send `PUT` and never an empty list: each clears the issue's other values. Never set Effort.
- Read back the type, the labels, and the Priority, and report a missing one:
  `gh issue view <n> --json issueType,labels` and
  `gh api repos/hoshiori-dev/devcontainer-features/issues/<n>/issue-field-values`.

Milestones and Projects are deliberately not used (`github-workflow.md`); never create them.

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
   directory for a broad one) and the reserved line of Validation with each Acceptance item and scenario and its result,
   linking the CI run; and confirm every task of the change is ticked. Then follow
   `.agents/knowledge/agent-authority.md`: green checks are evidence, not acceptance. Under it you may mark the PR ready
   (`gh pr ready`) and request review once `just pr-labels <pr>` prints `spec:approved` for the pull request, then hand
   the maintainer the report it defines. Marking ready opens the implementation deliberation, and the PR waits for its
   archive: the PR workflow run succeeds, and `spec-archived` is withheld until the archive commit lands. Its absence is
   the merge block, not a defect, and the reported checks show a passing PR all the while (`checks.md`, Waiting for the
   archive), so never report such a PR as mergeable; the PR labels workflow shows the wait in the list as
   `spec:approved`, and the archive commit turns it into `spec:archived`. Archive only when the maintainer commands it
   in the conversation: the `openspec-archive-change` skill (`/opsx:archive`), `just spec-check`, commit, push, and note
   the command on the `Approval:` line. A commit after the archive commit spends the closing; say so and ask again.
   Auto-merge is not used; never edit the policy, protections, or required checks to unblock yourself — propose the
   change to a maintainer instead.
3. A maintainer merges; the closing keyword closes the linked issue — verify it closed. Merging a version bump publishes
   it: the Release workflow publishes to GHCR and tags `<id>/v<version>` (`checks.md`).
