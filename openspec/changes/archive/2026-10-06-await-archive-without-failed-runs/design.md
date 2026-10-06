# Design

## Context

- Today the job `spec-archived` in `.github/workflows/pr.yml` runs the base commit's `scripts/check_spec_archived.ts` in
  the pull request's tree. On a draft it lists unarchived changes as a warning and passes; on a ready pull request it
  passes `--ready`, and the script exits 1 when a change is unarchived. That exit fails the job, the run, and the
  required check at once.
- The `main` ruleset requires `spec-archived` by name only; the entry pins no source app (readback in
  `.agents/knowledge/github/platform-settings.md`).
- What GitHub documents, read on 2026-10-06:
  - A notification is sent for a workflow run to the person who triggered it, and an account may limit them to failed
    runs
    ([Notifications for workflow runs](https://docs.github.com/en/actions/concepts/workflows-and-actions/notifications-for-workflow-runs)).
    Nothing filters by job.
  - A skipped job reports "Success" and does not block a merge even when it is a required check
    ([Control jobs with conditions](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions)).
  - A job's `name` may use the `github`, `needs`, `strategy`, `matrix`, `vars`, and `inputs` contexts
    ([Contexts reference](https://docs.github.com/en/actions/reference/workflows-and-actions/contexts), context
    availability).
  - For a pull request from a fork, `permissions:` cannot grant write access
    ([Workflow syntax, `permissions`](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions)).
  - GitHub advises against `pull_request_target` and `workflow_run` with untrusted pull requests
    ([Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use)).
- Measured locally on 2026-10-06 with Deno 2.9.7: an uncaught error, an import that cannot be resolved, and a denied
  permission each end `deno run` with status 1, the status the script uses today for "a change is unarchived"; the
  script `main` holds exits 0 for an unknown flag, with or without an unarchived change, and with `--ready` exits 1 and
  0 for the two cases.
- What this design assumes or guesses without a documented statement or a measurement. The test pull request measures
  each one (Decisions):
  1. A required check that no run has reported on the head commit blocks the merge, and the pull request page shows it
     as expected.
  2. A job whose `name` is an expression over `needs` reports its check under the evaluated name, for both values.
  3. When the deciding job fails, the job that depends on it is skipped and reports under a name other than
     `spec-archived`. The skipped matrix jobs of the CI workflow show their unevaluated expression as a name, which
     suggests the same here.
  4. When several runs report a check of the same name on one commit, an earlier success keeps satisfying the
     requirement if a later run reports nothing under that name. The design avoids depending on the answer, but the
     reason it gives for one verdict for draft and ready rests on it.
  5. The pull request list shows a passing icon for a pull request that waits for its archive.
  6. A withheld check is absent from the reported checks (`gh pr checks`, `statusCheckRollup`), so those report a
     passing pull request.
  7. A successful run in the waiting state sends no failed-run notification.
  8. A pull request from a fork gets the same verdict and the same block.
- The PR checks run the base commit's copy of their script, while the workflow file comes from the pull request merged
  with `main`. After this change merges, every open pull request therefore runs the new workflow with whatever script
  its base commit holds. Five pull requests are open on 2026-10-06, four of them drafts.
- All 48 pull requests so far came from branches of this repository; none came from a fork.

## Goals / Non-Goals

**Goals:**

- A successful check named `spec-archived` exists on a commit only when the checker ran and found no unarchived change.
  Every other outcome — an unarchived change, a checker failure, a cancelled or skipped job — leaves that name without a
  success. Checked by reading the name expression, whose value is `spec-archived` in one case only, and by observing the
  unarchived and the archived case on pull requests.
- The verdict is a function of the commit's tree alone: not of the draft state, the event type, or the token. A check
  reported on a commit then never contradicts a later run on the same commit. Checked by the workflow passing nothing
  from the event to the checker, and by a draft and a ready run on one commit giving the same result.
- The name the job carries while it waits is not a required check and is not added to the ruleset. Checked by the
  ruleset readback in the proposal.
- The workflow reaches the right verdict with the script `main` holds today, so this pull request and the open ones need
  no base that already contains the new script. Checked by this pull request's own runs, which use that script.
- A failure of the checker itself fails the run and is never shown as waiting. Checked by a unit test of the script's
  exit statuses and by reading the workflow's mapping of them.
- The finished pipeline is observed end to end on a test pull request before this one is marked ready (Decisions).
  Checked by its observations standing in this pull request's Validation section and by its state, closed and unmerged.

**Non-Goals:**

- A description text on the waiting required check, or a pending icon in the pull request list. GitHub offers both only
  for a status written through its API.
- Making the PR checks proof against a pull request that edits the workflow. Review guards those edits today (`pr.yml`,
  header comment) and keeps doing so.
- Fewer PR workflow runs. The triggers stay as they are. `pr-title` and `pr-checklist` need `edited`; with the verdict
  no longer read from the draft state, no job needs `ready_for_review` or `converted_to_draft` any more, and dropping
  them is left to a later change.

## Decisions

- **Withhold the check instead of failing it.** One job decides; a second job carries the name `spec-archived` when no
  change is unarchived and another name otherwise, and succeeds either way. While a change is unarchived nothing reports
  the required name, so the ruleset keeps the merge blocked and the run is a success. The path of a passing check is the
  one in use today, a job that succeeds under the required name, so nothing new can stop an archived pull request from
  merging. Rejected:
  - A pending commit status written by the PR workflow. It needs `statuses: write`, moves the ruleset's requirement from
    a job to a status, and cannot be written for a pull request from a fork, pending or successful, so such a pull
    request could never satisfy it.
  - A pending commit status written by a `workflow_run` workflow on `main`. It works for forks and takes the verdict out
    of the pull request's reach, but it is a workflow with write access triggered by untrusted pull requests, the
    pattern `checks.md` forbids for `pull_request_target`; it also needs the ruleset change, and makes the passing path
    depend on an API write.
  - An environment with required reviewers. The job would wait in place, but every run asks the reviewers for a
    deployment review, which replaces one notification with another.
  - Turning off failed-run notifications in the maintainer's account. It hides real failures as well.
- **One verdict for draft and ready.** A pass reported while a pull request is a draft would stay on its commit when the
  pull request becomes ready, and the withheld check could not replace it. Rejected: keeping the draft pass, which makes
  the block depend on the assumption about same-name checks listed under Context. The test pull request refuted that
  assumption on 2026-10-06: a later run that reports nothing under the name does withhold the check again. The decision
  stands on its other ground, a verdict that does not change with the draft state.
- **The exit status carries the verdict, and `--ready` keeps its contract.** The workflow always runs the checker with
  `--ready`: status 0 means archived, status 1 means a change is unarchived, any other status fails the job. The script
  reports its own unexpected errors with a status other than 0 and 1. The script `main` holds today already answers 0
  and 1, which is what makes the transition goal hold. Rejected:
  - A step output written by the script behind a new flag, as `scripts/affected.ts --github` does. Today's script
    ignores an unknown flag and exits 0, so on a base without the new script every pull request would read as waiting,
    this one after its archive included.
  - Reading the script's message text, which ties the workflow to wording.
  - Renaming `--ready` now that drafts get the same verdict. The old script would not know the new name.
- **Two jobs.** A job's name cannot use the `steps` context, so it cannot depend on the job's own steps; it can depend
  on the outputs of a job it `needs`. The deciding job also writes the warning annotation that names the unarchived
  changes. The name expression yields the waiting name unless the deciding job's output says archived, so a failed or
  cancelled deciding job cannot produce the required name.
- **A test pull request exercises the pipeline, then is closed.** Once the implementation is complete, a pull request
  with no purpose beyond the test is opened from a branch cut from this one, against `main`, so the ruleset applies to
  it and it runs the new workflow with the script `main` holds. Its title and description say that it is a test and will
  not be merged, and it closes no issue. It carries this change unarchived, which gives the waiting state, observed as a
  draft and as a ready pull request: the run's conclusion, the annotation, the blocked merge, and what the pull request
  page and the pull request list show. A further commit on its branch removes the change's directory, which gives the
  passing state. That commit stands in for an archive and is not one: it exists only on the test branch, and this pull
  request's change stays unarchived until a maintainer commands the archive. When the observations are recorded, the
  test pull request is closed with a comment that says so; deleting its branch is left to a maintainer
  (`agent-authority.md`). Being temporary exempts it from nothing: its title, description, commits, and comments, the
  test-only commits included, pass the publish gate of the `github-project-workflow` skill before they are published,
  and hold no secret, credential, internal host, or personal data. Rejected: observing only on this pull request, which
  shows the passing state for the first time at its own archive, when a defect would block the merge of the fix.
- **Every unmeasured assumption gets a measured conclusion, recorded on this pull request.** The test pull request
  measures the eight items listed under Context. Where the finished workflow cannot produce the case, a commit that
  exists only on the test branch produces it: a deciding job made to fail for item 3, and for item 4 a job name made to
  depend on the draft state, so that one commit first receives a success under `spec-archived` and then a run that
  reports nothing under it. Item 7 is read from the runs' conclusions by the implementer and from the inbox by a
  maintainer. Item 8 needs a pull request from a fork, which the implementer opens only if a maintainer provides or
  permits the fork. The results are posted as one comment on this pull request before it is marked ready: for each item
  what was done, what was observed with a link to the run or the API readback, and the conclusion — confirmed, refuted,
  or not measured with the reason. A refuted item that the design relies on stops the work: the package is revised and
  the package gate is asked again. The comment passes the same publish gate. An API readback or a log excerpt quoted in
  it is cut down to the fields the conclusion needs, and item 7 is recorded as the maintainer's statement that no
  notification arrived, never as a copy of a notification or of anything from an inbox. Rejected: recording the results
  only in the Validation section, which is rewritten as the description changes, while a comment keeps its date.
- **The waiting job is named `awaiting-archive`.** It reads as a state in the pull request's check list and shares no
  prefix with a required check.

## Risks / Trade-offs

- **The block is less visible.** The pull request page shows the required check as expected, with no reason beside it,
  and the pull request list may show a passing icon for a blocked pull request. Mitigation: the run's warning annotation
  and the `awaiting-archive` entry in the check list say why; `checks.md` records what was observed. If the list proves
  misleading in practice, a status written through the API is the remedy, as its own change.
- **The name expression may not behave as documented.** If a job is not reported under its evaluated name, an archived
  pull request never satisfies the requirement. Mitigation: the test pull request shows the passing state before this
  one is marked ready; if it fails, the change is revised before any merge.
- **The test pull request cannot exercise the new script.** Its checks run the script `main` holds, so the status the
  new script gives its own errors is covered by unit tests only, until the first pull request after the merge.
- **A failure before the script runs would look like waiting.** If Deno cannot fetch the script's import, `deno run`
  exits 1, the status of an unarchived change. Mitigation, added on 2026-10-06 after a review comment on the pull
  request: the deciding job first loads the checker with `deno cache`, which exits non-zero for an import it cannot
  resolve and 0 for the script `main` holds today (both measured locally with Deno 2.9.7), so a load failure fails the
  job instead of reading as waiting. What remains is an uncaught error in the script `main` holds, which exits 1 until
  the script of this change is the base; the merge stays blocked in that case, never opened.
- **A pass reported by an edited workflow stands alone.** A pull request can make a job named `spec-archived` succeed by
  editing the workflow, as it can today; with the genuine check withheld instead of failed, no failing check of the same
  name appears beside it. Review of edits under `.github/` remains the guard, and an archive that never happened is
  visible in the diff.
- **The checker prints names the pull request chose.** A directory name under `openspec/changes/` reaches the log of the
  step that runs the checker, where a line break in it could start a workflow command. Mitigation, added on 2026-10-06
  after the final review: the checker's status leaves that step through a file and the next step writes the job's
  output, so nothing printed can set the verdict whichever script the base holds; the checker of this change also
  escapes the annotation text and counts a symbolic link under `openspec/changes/` as a change, which the script `main`
  holds does not; the other scripts that list changes keep reading directories only.
- **"All checks pass" no longer implies mergeable.** A withheld check is absent from the list of reported checks, so a
  tool that reads only reported checks sees a passing pull request. The Finish step of the `github-project-workflow`
  skill and `checks.md` say that the pull request waits for the archive whatever the reported checks show.
- **Passes reported before this change merges stay on their commits.** A draft that passed under today's workflow keeps
  that success on its head commit. The ruleset requires an up-to-date branch, and merging this change moves `main`, so
  each open pull request needs a new head commit before it can merge, and that commit is judged by the new workflow.

## Migration Plan

Merging the change is the deployment: each pull request runs the new workflow from its next event. Rollback is a revert
of the workflow through a pull request; the script's `--ready` contract is unchanged, so the old workflow runs against
either script.
