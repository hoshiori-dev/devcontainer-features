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
- What this design assumes without a documented statement; the first two are to be observed on this pull request, and
  the third is avoided instead of tested:
  - A required check that no run has reported on the head commit blocks the merge and shows as expected.
  - A job whose `name` is an expression over `needs` reports its check under the evaluated name.
  - When several runs report a check of the same name on one commit, an earlier success may keep satisfying the
    requirement if a later run reports nothing under that name.
- The PR checks run the base commit's copy of their script, while the workflow file comes from the pull request merged
  with `main`. After this change merges, every open pull request therefore runs the new workflow with whatever script
  its base commit holds. Five pull requests are open on 2026-10-06, four of them drafts.
- Deno exits 1 on an uncaught error, the same status the script uses today for "a change is unarchived".
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
- The archived case is observed before this pull request is marked ready, on a throwaway draft pull request that carries
  the workflow and no change, closed unmerged.

**Non-Goals:**

- A description text on the waiting required check, or a pending icon in the pull request list. GitHub offers both only
  for a status written through its API.
- Making the PR checks proof against a pull request that edits the workflow. Review guards those edits today (`pr.yml`,
  header comment) and keeps doing so.
- Fewer PR workflow runs. The triggers stay as they are; `pr-title` and `pr-checklist` need them.

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
  the block depend on the assumption about same-name checks listed under Context.
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
- **The waiting job is named `awaiting-archive`.** It reads as a state in the pull request's check list and shares no
  prefix with a required check.

## Risks / Trade-offs

- **The block is less visible.** The pull request page shows the required check as expected, with no reason beside it,
  and the pull request list may show a passing icon for a blocked pull request. Mitigation: the run's warning annotation
  and the `awaiting-archive` entry in the check list say why; `checks.md` records what was observed. If the list proves
  misleading in practice, a status written through the API is the remedy, as its own change.
- **The name expression may not behave as documented.** If a job is not reported under its evaluated name, an archived
  pull request never satisfies the requirement. Mitigation: the throwaway draft pull request shows the archived case
  before this one is marked ready; if it fails, the change is revised before any merge.
- **A failure before the script runs looks like waiting.** If Deno cannot start the script or fetch its import, it exits
  1 and the pull request reads as waiting with no annotation. The merge stays blocked, never opened; the job log shows
  the error, and a rerun clears a transient one.
- **A pass reported by an edited workflow stands alone.** A pull request can make a job named `spec-archived` succeed by
  editing the workflow, as it can today; with the genuine check withheld instead of failed, no failing check of the same
  name appears beside it. Review of edits under `.github/` remains the guard, and an archive that never happened is
  visible in the diff.
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
