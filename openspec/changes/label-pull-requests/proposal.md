# Proposal

Implements [#123](https://github.com/hoshiori-dev/devcontainer-features/issues/123).

## Why

A pull request shows neither where its specification stands nor which areas it touches. Both approval gates close in
conversation, and the only trace on GitHub is a line the agent writes into the description, so an approval is asked for
again in the next session; nothing withdraws an approval when the approved text changes afterwards; a pull request that
waits for its archive looks like a mergeable one in the list; and the area labels #12 gave to issues reach a pull
request only when someone remembers them. The maintainer settled the direction in #123 on 2026-10-08.

## What Changes

- **Three specification-state labels.** `spec:pending`, `spec:approved`, and `spec:archived`. A pull request whose head
  holds an unarchived OpenSpec change carries `spec:pending` or `spec:approved`; one that holds none and adds a file
  under `openspec/changes/archive/` carries `spec:archived`; any other has none. It never has two.
- **`spec:approved` is the package approval.** The maintainer adds it to the pull request, or tells an agent to. A
  workflow records the approval in one comment it keeps on the pull request: the commit that was approved, the account
  that added the label, and which label event it answers. Recording it takes `spec:pending` off. The approval survives
  the end of a session.
- **An approval lasts as long as the approved text.** The approval package is every file of each unarchived change but
  its `tasks.md`, together with the main spec of each capability the change has a delta for, which is where the hand
  correction of a Purpose that `spec-workflow.md` counts into the package lives. When the package at the pull request's
  head differs from the package at the approved commit, `spec:approved` gives way to `spec:pending`. Writing or ticking
  `tasks.md` withdraws nothing.
- **An approval the workflow cannot stand behind is not kept.** `spec:approved` is recorded only when an account with
  write access added it, on an open pull request with an unarchived change, at the commit the pull request still has
  when the record is written. In every run but the one that records it, `spec:approved` without a record that matches,
  or beside `spec:pending`, gives way to `spec:pending`, and a run that fails takes `spec:approved` off. A person who
  removes `spec:approved` or adds `spec:pending` withdraws the approval, whichever run notices it. An account with
  triage permission cannot approve: `spec-workflow.md` defines a maintainer as a collaborator with write access.
- **The gate is read by recomputing it.** The same script, run for a pull request without writing, prints the state the
  rules give it now. An agent reads the package gate that way and never from the bare label, so a label that lags a
  push, or a workflow that did not run, reads as not approved.
- **Area labels on pull requests.** The workflow adds the area labels of the paths a pull request changes, one or
  several. It never removes an area label and leaves every other label alone.
- **One workflow keeps both.** It runs when a pull request is opened, reopened, updated, or relabelled, and by dispatch
  for one pull request. It runs on `pull_request_target`, as GitHub's own labeler does, so that it can label a pull
  request from a fork.
- **A named exception to "Never use `pull_request_target`".** `checks.md` keeps the rule and names this one workflow
  with the bounds that make it safe: it runs the default branch's script and never checks out, fetches, or runs anything
  of the pull request; it reads what it needs through the API; what a pull request controls reaches it as data; its
  token holds `contents: read` and `pull-requests: write`; it uses no secret.
- **The package gate is recorded on GitHub.** The rules say that `spec:approved`, read as above, closes the package gate
  on a pull request that holds an OpenSpec change, in place of a sentence in the conversation. The freeze gate is
  unchanged: the archive is commanded in conversation and has no label. The reconciliation of the pull request's threads
  before acting on an approval is unchanged.
- **The `Approval:` line stays, with a narrower job.** It no longer records the package approval. It keeps what no label
  holds: each reconciliation and the archive command. The checklist item of the template that speaks of a deliberation
  closed in conversation names the label. `Phase:`, which #123 named beside it, is left unchanged: it says whether the
  description is still the specification's or already the implementation's, which no label says.
- **Authority.** `agent-authority.md` changes in these places and no other:
  - under "What agents may not do without a human", the first entry becomes "Implement a change before its pull request
    carries `spec:approved`, read as `spec-workflow.md` says.", and this entry is added:

    > Add or remove a `spec:` label on a pull request. `spec:approved` is the maintainer's package approval: an agent
    > adds it only when a maintainer tells it to in the current conversation and names the pull request, never on its
    > own judgment, and otherwise only reads the labels.

  - the Meaning of the package gate becomes "The maintainer adds `spec:approved` to the draft PR, or tells the agent to;
    the PR labels workflow keeps it only while the approval package is unchanged, and the agent's reconciliation of the
    PR's threads finds nothing open (`spec-workflow.md`)";
  - the sentence after the Gates table becomes "The archive command does not carry over from another session: without
    one in this conversation, treat the freeze gate as not passed and ask. The package gate is read from the pull
    request.";
  - the first entry under Escalation becomes "The pull request of the change you are about to implement does not carry
    `spec:approved`.".

## Capabilities

### New Capabilities

None. This change edits the harness only (`skip_specs: true`).

### Modified Capabilities

None.

## Impact

- Files: a new workflow under `.github/workflows/`; a new Deno script with its tests, and workflow tests in
  `scripts/checks_test.ts`; `.github/labels.yml` (three labels); a `just` recipe; `.github/pull_request_template.md`
  (the `Approval:` line and one checklist item); `openspec/config.yaml` (the rule for `tasks.md` and the guidance for
  apply, which name the conversation); `.agents/knowledge/spec-workflow.md` (Lifecycle, Approval gates, and the
  specification block under Specifications and issues), `agent-authority.md` (as above), `github-workflow.md` (Objects
  in use, Areas, the sentence that there are no status labels, the specification block, Synchronization),
  `github/checks.md` (Rules, the job map, Toolchain pins, Waiting for the archive), and `review-guidance.md` (one
  accepted risk, below); the `github-project-workflow` skill (Take work, Finish, and how the label is read and added);
  `AGENTS.md` (Core Conventions, Validation, Workflow); `SECURITY.md` (the same accepted risk in its overview);
  `CONTRIBUTING.md` where it says how a specification is approved.
- Checked and left alone: `github/platform-settings.md`, `git-workflow.md`, `README.md`, `README.zh.md`,
  `.github/skills/`, `scripts/lib/repo.ts` (`INFRA_PATHS`), `scripts/check_pr_body.ts`, and the generated OpenSpec
  skills.
- Feature ids touched: none, so no version bump. No file under `src/`, `test/`, or `openspec/specs/` changes.
- Workflow permissions and trigger: one new workflow on `pull_request_target` whose one job holds `contents: read` and
  `pull-requests: write`. Both are security-sensitive surface (`agent-authority.md`, Escalation) and the trigger is the
  one `checks.md` forbids; they are named here so that the approval of this package covers them.
- Authority: four files that an agent may not edit to relax its own limits change here: `agent-authority.md`,
  `spec-workflow.md`, `AGENTS.md`, and, as a file maintainers own, `openspec/config.yaml`. The change narrows in one
  place: an agent may not touch a `spec:` label on its own judgment. It relaxes in five: an approval carries over from
  one session to the next; the maintainer need not be in the conversation to approve; the comparison of the branch with
  the approved commit moves from the agent to the workflow; an agent gains one write, adding `spec:approved` on
  instruction; and an agent may dispatch the workflow for one pull request, which reconciles and cannot approve. The
  approval of this package has to accept each. Separately from it, the agent edits these files only when the maintainer
  says so in the conversation, which is the maintainer's delegation and is asked for in so many words.
- A new accepted risk: someone with write access to the repository can forge an approval, by adding the label themselves
  or by writing a comment that looks like the workflow's from a workflow on their own branch. A pull request from a fork
  can do neither. `review-guidance.md` and `SECURITY.md` say so.
- In this repository the agent works with the maintainer's own account, so a label it adds is recorded under the
  maintainer's name and the workflow cannot tell the two apart. What makes it the maintainer's approval is the rule in
  `agent-authority.md`.
- The workflow does not run on the pull request that adds it: `pull_request_target` takes the workflow from the default
  branch. This pull request's own package approval is given in conversation, under the rule it replaces. Every
  Acceptance item below is checkable before the merge and stops at the script and at the workflow's file. What the
  running workflow shows on a real pull request, one from a fork included, is measured after the merge on the
  maintainer's command; the design lists what is measured, and a refuted assumption is fixed forward or the workflow is
  reverted.
- Remote state written by the merge: the Labels workflow creates the three labels. From then on the new workflow writes
  labels and one comment on pull requests. A revert stops it and leaves labels and comments where they are.
- A pull request open at the merge gets its labels at its next event or by dispatch. An approval given in conversation
  before the merge is carried over by the maintainer adding the label. None is open today.
- One question is left to the approval (design, Open Questions): whether a maintainer's statement in the conversation
  still closes the package gate while the workflow cannot run. As proposed it does not.
- No required check is added: `spec-archived` remains what blocks a merge, and a failed run of the new workflow blocks
  no merge. It does read as not approved.

## Acceptance

**Becomes true:**

- `.github/labels.yml` declares `spec:pending`, `spec:approved`, and `spec:archived`, and `just check` passes with them.
- For a pull request state given to it, the script decides the state label as What Changes states. A unit test covers
  each of these: an unarchived change and no record gives `spec:pending`; a record whose package equals the head's keeps
  `spec:approved`; a changed proposal, design, delta spec, or change metadata, an added or renamed change, and a changed
  main spec of a capability the change has a delta for each give `spec:pending`; a changed
  `openspec/changes/<name>/tasks.md` alone keeps `spec:approved`, while a file of that name elsewhere in the change does
  not; a changed main spec of another capability keeps `spec:approved`; `spec:pending` beside `spec:approved`, in a run
  that does not record, gives `spec:pending`; no unarchived change and an added archived change gives `spec:archived`;
  an unarchived change appearing again gives `spec:pending`; an edit or removal under the archive alone, and a pull
  request that touches nothing under `openspec/changes/`, give no state label; no result holds two state labels.
- An approval is recorded as What Changes states. A unit test covers the recording: `spec:approved` added by an account
  with write access at the unchanged head, with `spec:pending` present, gives a record of that commit, that account, and
  that label event, `spec:approved` kept, and `spec:pending` removed; and when another run took the unrecorded label off
  first, the recording run puts it back and the next run keeps it. A unit test covers each refusal: the label added by
  an account whose permission is below write, by a bot, at a commit that is no longer the head when the record is
  written, on a closed pull request, with no unarchived change, and with a change that is a symbolic link or anything
  but a directory; and the label present with no record, with a withdrawn record, with a record of another commit whose
  package differs, with a record that answers an earlier adding of the label by a person than the latest, and with more
  than one record comment. A unit test covers each withdrawal by hand, read from the label history: `spec:pending`
  added, and `spec:approved` removed, each also when the recording run comes after it, when no run was started by it,
  and when it shares its second with the approval; the same events made by a bot withdraw nothing.
- A run on a pull request that carries `spec:approved` and cannot finish its reads ends without `spec:approved`, and on
  an open pull request with `spec:pending` when the script could still write: a unit test covers a failing read and a
  tree the API reports as truncated. A file list cut short decides no area label and no `spec:archived`, and a run that
  succeeds writes nothing on a closed pull request; a unit test covers each.
- The record comment holds nothing a pull request named: a unit test builds it for a change and files whose names hold
  comment, mention, and workflow-command syntax and finds none of it in the body. A record is accepted only from one
  comment written by `github-actions[bot]`, of type `Bot`, whose first line has the fixed form.
- The script maps every path to its areas as the design's table gives them, counts a renamed file under both names, and
  a unit test fails when a file tracked in the repository matches no row of the map.
- The script adds the area labels of the changed paths and removes none: a unit test shows an area label that the paths
  do not give, and a label outside the five and the three, both left alone.
- The script passes a value a pull request controls to `gh api` only as a string field or in a request body, and a name
  in a path only percent-encoded; it prints such a value only escaped; it accepts a dispatch number only when it is
  digits. A unit test covers each with hostile values.
- The workflow's triggers are `pull_request_target` with the activity types opened, reopened, synchronize, labeled, and
  unlabeled, and a dispatch that runs on `main` only. Its one job runs in this repository only, holds `contents: read`
  and `pull-requests: write` and nothing else, checks out the default branch without credentials, names no ref,
  repository, or path of the pull request in any step, has no `${{ }}` expression in a `run:` line, passes the pull
  request's number, the event's action, label, sender, and head commit, and for a dispatch its number input, as
  environment variables and no other field of the event, ends with a step that runs only after a failure and removes
  `spec:approved`, and uses no secret and no action but the checkout and the repository's own tool setup. A unit test
  asserts each of these on the workflow file.
- No other workflow uses `pull_request_target` or `workflow_run`: a unit test over every workflow file asserts it and
  names this workflow as the one exception.
- The script's printing form makes no write and prints, for #124, `spec:archived`, `ci`, `scripts`, and `harness`; for
  #132, `spec:archived` and `harness`; and for this pull request, while its change is unarchived, `spec:pending`, `ci`,
  `scripts`, `harness`, and `spec-workflow`.
- `checks.md` keeps "Never use `pull_request_target`" and names the one exception with its bounds; its job map holds the
  new job with the command that runs locally; Toolchain pins lists the job among those that run a script directly;
  Waiting for the archive says what the labels show in the list.
- `spec-workflow.md`, `agent-authority.md`, the skill, `openspec/config.yaml`, `AGENTS.md`, `CONTRIBUTING.md`, and the
  template's checklist name `spec:approved`, read by recomputing, as what closes the package gate; none still says that
  the package approval is given in conversation or that nothing is recorded on GitHub. `agent-authority.md` holds the
  texts of What Changes and differs from `main` in nothing else.
- `github-workflow.md` lists the three labels among the objects in use, no longer says that a label states the area of
  an issue and nothing else or that there are no status labels, says that a pull request gets its area labels from its
  paths, and its Synchronization table names what changes with the map.
- `review-guidance.md` and `SECURITY.md` state the accepted risk of Impact.
- The `Approval:` line of the template asks for the reconciliations and the archive command and no longer for the
  package approval, and `scripts/check_pr_body.ts` accepts a description built from the template.
- `AGENTS.md` lists the new recipe in its Validation table.

**Stays true:**

- The freeze gate: the archive is commanded by a maintainer in the current conversation, has no label, and no workflow
  archives.
- An agent never passes the package gate on a change it wrote: it adds `spec:approved` only on the maintainer's explicit
  instruction.
- Before acting on an approval the agent reads the pull request's comments and review threads, and proceeds only when
  nothing is open or the maintainer has confirmed the open items in the conversation.
- The `main` ruleset requires `ci-gate`, `pr-title`, `pr-checklist`, `spec-archived`, and `secret-scan`, and nothing
  else. `spec-archived` and `awaiting-archive` behave as before.
- No workflow that runs on a `pull_request` event holds a write permission. Every workflow declares `permissions:`, and
  every action is pinned by full commit SHA.
- No step of any workflow checks out, fetches, or runs a pull request's code with a write token.
- Labels on issues are set by people and agents as `agent-authority.md` says; no automation labels an issue.
- The Labels workflow and `scripts/sync_labels.ts` are unchanged apart from the three declared labels.
- The `Phase:` line of the pull request template is unchanged.
- No file under `src/`, `test/`, or `openspec/specs/` changes, and `just check` passes.
