# Design

## Context

- `pull_request_target` runs in the context of the default branch of the base repository: the workflow file and the
  commit checked out by default are `main`'s, whatever branch the pull request targets, and its token can write to a
  pull request from a fork
  ([Events that trigger workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)).
  The same page warns that running untrusted code on this trigger can give it write access. A `pull_request` run from a
  fork gets a read-only token.
- GitHub's labeler runs on this trigger with `contents: read` and `pull-requests: write`, says that
  `pull-requests: write` is enough when every label already exists and that creating a label needs `issues: write`, and
  removes, with `sync-labels`, only labels its configuration names
  ([actions/labeler](https://github.com/actions/labeler)).
- An event caused with a workflow's own token starts no workflow run, so the labels the workflow sets do not start it
  again; a label set with a person's token, in the browser or through `gh`, does. Adding one label and removing another
  in one gesture sends two events, in no promised order.
- Read on 2026-10-09 with the agent's token: the tree of a commit, listed recursively, gives every path with its mode,
  type, and blob id, and says when it is truncated; it is readable through the base repository for the head of a pull
  request from a fork (tried on a public repository); the files of a pull request are listed with status, previous name,
  and at most 3000 entries, and the pull request states how many files it changes; the collaborator permission of an
  account is one request whose `permission` field reads `admin`, `write`, `read`, or `none`; a comment carries the login
  and the type of the account that wrote it; the events of a pull request list every adding and removing of a label with
  an id that grows from one event to the next, its account, the account's type, and a time to the second, so two events
  can share a time and never an id.
- `scripts/check_spec_archived.ts` defines an unarchived change on a checkout: an entry of `openspec/changes` other than
  `archive` that is a directory or a symbolic link.
- A `pull_request_target` run is recorded against `main`'s commit, not the pull request's, so nothing ties a finished
  run to a pull request's head.
- A concurrency group holds one running and one pending run; a newer pending run replaces an older one.
- People with write access can edit and delete anyone's comment; an account with triage permission cannot.
- In this repository the agent works with the maintainer's own account, which has admin permission, and every pull
  request but Dependabot's is opened by it.
- `checks.md` says every CI job runs a command that also runs locally.
- What this design assumes and cannot observe before the merge, because the workflow runs only from the default branch:
  1. A token with `pull-requests: write` and no `issues: write` adds and removes an existing label on a pull request,
     and creates and edits a comment on it.
  2. The same token fails to add a label that does not exist, and creates none.
  3. The token reads the tree of the head commit and the file list of a pull request from a fork.
  4. The token reads the collaborator permission of the account that added a label.
  5. A comment the workflow writes carries the login `github-actions[bot]` and the type `Bot`.
  6. A label added with a person's token starts a run whose event names that person and the head commit of that moment.
  7. The token reads the label events of a pull request, the event that started a run is in that list when the run reads
     it, and a label the workflow sets is listed with an account of the type `Bot`.
  8. On a pull request opened by Dependabot the token can write as `permissions:` grants, or the run needs no write
     because Dependabot's own `ci` label is the one the paths give.

## Goals / Non-Goals

**Goals:**

- A wrong `spec:approved` is the failure to avoid; a wrong `spec:pending` costs one more click. Every case the script
  cannot decide ends in `spec:pending`. Checked by the unit tests of the refusals and of the failing reads.
- An approval is tied to immutable objects: a commit id and the trees under it. Checked by unit tests in which the head
  moves between the event and the reads, and in which the base branch changes.
- Every run decides from the pull request's present state, its label history included, never from what changed since the
  last run, with one named exception that reads its own event: the recording of an approval. Checked by unit tests that
  give the same state under different events and expect the same labels.
- The map from paths to areas has no silent default. Checked by the unit test that every tracked file matches a row.

**Non-Goals:**

- Verifying who decided an approval beyond the account that added the label.
- Protection against someone with write access, who can set any label by hand.
- Keeping a pull request's area labels equal to its paths in both directions.
- Telling work that began before an approval from work whose approval was withdrawn afterwards.

## Decisions

- **One script decides every label.** `scripts/sync_pr_labels.ts` reads a pull request's state through the API, decides
  the labels, and prints them; with `--apply` it writes the difference. Rejected: GitHub's labeler for the areas beside
  a script for the state, which adds an action to the allow-list, a second configuration file, and a second writer of
  labels on the same event for something one pass over a file list does.
- **The record is the approved commit, not a fingerprint.** The comment the workflow keeps holds the commit id, the
  account, and the id of the label event it answers. Each run reads the tree of that commit and the tree of the head and
  compares the approval package in both. The trees are addressed by commit, so a push between two reads cannot change
  what was compared, the base branch does not enter, a restored text compares equal, and a person can open the approved
  commit. Rejected: a hash of the pull request's file list, which is read for whatever the head is at that moment and so
  can record a text other than the one the event named, depends on the base branch, and stops at 3000 files; no record
  at all, comparing the commits before and after each push, which a replaced run turns into a stale approval; a commit
  status, which needs a further write permission; the pull request's description, which people edit.
- **The approval package, read from a tree.** For each entry of `openspec/changes` other than `archive`: when it is a
  directory, every path under it with its mode and blob id, except exactly `openspec/changes/<name>/tasks.md`; and for
  each capability with a delta under `openspec/changes/<name>/specs/<id>/`, the blob id of
  `openspec/specs/<id>/spec.md`, or its absence. Two packages are equal when these lists are. An entry that is not a
  directory, a symbolic link or a submodule, is an unarchived change that cannot be approved. A truncated tree cannot be
  judged. Rejected: every main spec the pull request changes, which needs the file list and its base; the whole of
  `openspec/specs/`, which changes with other people's merges. A merge into `main` that changes the main spec under an
  approved delta does withdraw the approval once the branch takes it in: the text the delta was approved against is no
  longer there.
- **The state is a function of the present.** With an unarchived change at the head: `spec:approved` when the label is
  on the pull request, `spec:pending` is not, exactly one record comment exists and is not withdrawn, the label event it
  answers is the latest adding of `spec:approved` by a person in the pull request's events, no event with a greater id
  has a person removing `spec:approved` or adding `spec:pending`, and the package at its commit equals the package at
  the head; `spec:pending` otherwise, and then a record that exists is marked withdrawn before the labels change. With
  no unarchived change: `spec:archived` when the pull request adds a file under `openspec/changes/archive/`, and no
  state label otherwise.
- **An approval is recorded only by the run its own event started.** That run finds its event in the pull request's
  events, as the latest adding of `spec:approved` by a person, which has to be by the account the event named, and
  refuses when it is not there. It records when that account has `write` or `admin` in the permission field and is not a
  bot, the pull request is open, its head holds an unarchived change that is a directory, and the head is still the
  commit the event named after the trees have been read. It writes the record first, then makes sure `spec:approved` is
  on the pull request and `spec:pending` is not, so that the run of a simultaneous removal of `spec:pending`, which may
  come first and take the unrecorded label off, does not lose the approval. No other run records, a dispatch included.
  This run is the one place where `spec:pending` beside `spec:approved` ends in `spec:approved`. Rejected: recording
  whatever the head is when a later run notices the label, which would approve text the maintainer may not have seen.
- **A withdrawal by hand is read from the label history.** In every run, an event with a greater id than the one the
  record answers, in which a person removed `spec:approved` or added `spec:pending`, makes the record withdrawn,
  whatever the labels are by then and whichever run notices it. Order is by event id, never by time or by a runner's
  clock, so a withdrawal in the same second as the approval is still later. An event whose account is a bot, the
  workflow's own included, is no withdrawal. The recording run reads the events as well before it puts the label back,
  so an approval taken back while that run was waiting is not restored; and when `spec:approved` and `spec:pending` are
  added in one gesture, whichever event has the greater id decides. Rejected: reading the withdrawal from the event that
  started a run, which is lost when that run is replaced while pending.
- **A failed run withdraws.** The script's writes go through one path that, on any error after it has read the labels,
  first tries to put `spec:pending` in place of `spec:approved`. A script that cannot start at all is covered by the
  workflow's last step, which runs only after a failure and removes `spec:approved` with one fixed `gh api` call, on a
  closed pull request as well; the next run that succeeds sets `spec:pending`.
- **The comment is built from fixed text.** Its first line is the record in one fixed form holding a commit id, a login,
  and the id of the label event, each checked against its pattern before it is written; the rest is one of a few fixed
  sentences and a link to the commit. No name of a file, change, label, or branch enters it. A record is read only from
  a comment whose author is `github-actions[bot]` with the type `Bot` and whose first line has that form; more than one
  such comment reads as none. The comment list is read to its end.
- **The gate is read by running the script.** `just pr-labels <n>` prints the state the rules give now, from the label,
  the record, the label events, and the two trees. An agent reads the package gate that way. A label that lags a push, a
  run that failed, and a disabled workflow then all read as `spec:pending`, and no rule has to name a workflow run.
  Rejected: reading the bare label after the run for the head commit, which no API ties to a pull request's head.
- **`implementing` is a function of the file list.** With an unarchived change at the head, the label is on the pull
  request exactly when its file list holds a path, a renamed file's previous name included, that is neither under
  `openspec/changes/` nor the `openspec/specs/<id>/spec.md` of a capability that an unarchived change has a delta for.
  `tasks.md` lies under `openspec/changes/` and so is no implementation. With no unarchived change the label is removed,
  whatever the file list holds: `spec:archived` or no change at all leaves nothing to warn of. Nothing is recorded and
  no label event is read, so a person who sets or removes it by hand is overruled at the next run, and it enters no
  decision about the state. A run that fails leaves it as it is. Rejected: a pair of labels, where the absence of one
  already says the other; a name under `spec:`, which would break the rule of one state label; a check that fails on
  `spec:pending` beside it, which is also what a withdrawn approval over finished work looks like, so that telling the
  two apart needs a second record of history; counting `tasks.md`, which is written before any work and would set the
  label on every approved pull request at once.
- **Area labels are added, never removed.** The workflow adds the area of every changed path. Rejected: setting exactly
  the areas of the paths, which removes a label a person set and goes beyond what #123 settled.
- **The map from paths to areas.** First match wins; a renamed file counts under both names:

  | Path                                                                                                            | Area            |
  | --------------------------------------------------------------------------------------------------------------- | --------------- |
  | `openspec/changes/**`                                                                                           | none            |
  | `src/**`, `test/**`, `openspec/specs/**`                                                                        | `feature`       |
  | `.github/workflows/**`, `.github/actions/**`, `.github/dependabot.yml`                                          | `ci`            |
  | `scripts/**`, `justfile`, `deno.json`                                                                           | `scripts`       |
  | `openspec/**`, `.agents/skills/openspec-*/**`, `.claude/commands/opsx/**`, `.agents/knowledge/spec-workflow.md` | `spec-workflow` |
  | `.agents/**`, `.claude/**`, `.devcontainer/**`, `.github/**`, and a path without `/`                            | `harness`       |

  A change's own files give no area: the work it describes does, so a draft that holds only its specification has no
  area label yet. `test/canary.json` and the compatibility schema go with the tests they steer. A path that matches no
  row gives no label, and the unit test over the tracked files makes a new top-level directory fail `just check` in the
  pull request that adds it. Rejected: `harness` for whatever matches nothing, which would hide a new area. When the
  file list is cut short, which the pull request's own count of changed files shows, no area label and no
  `spec:archived` is decided, and with an unarchived change at the head `implementing` is left as it is; the state of an
  unarchived change does not depend on the list.
- **The workflow.** `.github/workflows/pr-labels.yml`, one job, `label`; its checkable shape is the proposal's
  Acceptance item. One concurrency group per pull request cancels no running run; a pending run can still be replaced by
  a newer one, which is why no decision but the recording depends on a run's own event. The event reaches the script as
  five environment variables, and the dispatch as one number. Rejected: `edited`, which fires for every change of a
  description; a changed base does not matter to an approval, and the areas and `spec:archived` follow at the next push.
  Rejected: `ref: main` on the checkout as in `labels.yml`, since the default checkout is already `main`'s newest commit
  and a test that forbids every `ref` is simpler to keep true.
- **A run that succeeds writes nothing on a closed pull request.** A merged pull request so keeps `spec:archived`. A run
  that fails still takes `spec:approved` off, through the workflow's last step, and on a closed pull request the
  script's own error path does no more than that. The printing form prints what the rules decide for any pull request.
- **`gh api`, and what the shebang does not give.** The rules for passing and printing what a pull request controls are
  the proposal's Acceptance item; the reason for the first is that `-F` reads a file for a value that begins with `@`.
  The script's shebang grants `--allow-run=gh` and the named environment variables. That does not confine a dependency
  (`review-guidance.md`, Accepted risks); the job's token does.
- **Who may dispatch, and the publish gate.** A dispatch only reconciles one pull request and cannot approve, so an
  agent may start one when it reads a state that a missed run explains. Adding `spec:approved` on the maintainer's
  instruction has no text to review; the agent names the pull request and its head commit before it adds the label and
  reads the workflow's comment back afterwards.
- **Colors.** `spec:pending` light yellow, `spec:approved` green, `spec:archived` light blue, `implementing` light
  purple, each with a description for the reader of the list.

## Risks / Trade-offs

- **The workflow is first seen after the merge.** Mitigation: the tests cover every decision and the workflow's shape;
  the printing form runs against real pull requests before the merge; a failed run blocks no merge; the assumptions of
  Context are measured on a test pull request after the merge, on the maintainer's command.
- **`pull_request_target` is one edit away from giving a fork a write token.** A step that checks out the head, or an
  expression of the event in a `run:` line, is that edit. Mitigation: the workflow test fails on either, the exception
  in `checks.md` names the bounds, and both files are read in review.
- **The label approves the head of the moment it is added.** A push that lands seconds before the click is approved with
  it. Mitigation: the comment names the approved commit with a link, and the rule that an agent does not push to a pull
  request that waits at the package gate.
- **A collaborator can forge an approval,** as the proposal's Impact says. The record's account and the comment's author
  are not checked against the pull request's history of events.
- **A replaced run withdraws an approval.** If the run for the adding of `spec:approved` is replaced while pending, the
  next run finds the label without a record and puts `spec:pending` back; the maintainer adds the label again. It takes
  three events on one pull request within one run's time. Re-running an old run of that event, which needs write access,
  records again only if the head is still the commit it named.
- **A second maintainer cannot add a label that is already there.** Approving again after a withdrawal means removing
  and adding it; after a withdrawal the workflow has already removed it.
- **`spec:pending` beside `implementing` is not a verdict.** It shows on a pull request whose work began too early and
  on one whose approved text was edited after the work. Mitigation: the knowledge base says it calls for a look, and the
  record comment says whether an approval was withdrawn.
- **Everything waits for GitHub Actions.** While the workflow cannot run, no approval is recorded and the gate reads as
  pending. See Open Questions.
- **A stale area label stays.** When the last file of an area leaves a pull request, its label remains until someone
  removes it.

## Migration Plan

One pull request. The merge changes `.github/labels.yml`, so the Labels workflow creates the four labels; a pull request
event that arrives before it has finished fails and is repeated by dispatch. The assumptions of Context are measured
after the merge on a test pull request, the fork case by whoever has a fork, and the results go into one comment on this
pull request.

Rollback is a revert: the workflow stops, labels and comments stay, and the knowledge base says again that the package
gate closes in conversation.

## Open Questions

- Whether a maintainer's statement in the conversation still closes the package gate while the workflow cannot run. This
  design says no. Allowing it would mean a sentence that names the outage and holds for that session only.
