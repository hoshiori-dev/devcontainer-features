# Design

## Context

- The organization's configuration, read from the API on 2026-10-08
  ([hoshiori-dev/.github#1](https://github.com/hoshiori-dev/.github/issues/1)): the types Epic, Feature, Bug, and Task;
  the single-select field Priority (id 28240578; Urgent, High, Medium, Low), public; the single-select field Effort and
  the date fields Start date and Target date, visible to organization members only. Pinned fields: Priority and Effort
  on Feature, Bug, and Task; Start date and Target date on Feature; Target date on Epic. A pinned field is offered on an
  issue, not required. A token with the `read:org` scope reads all of this (`gh api orgs/hoshiori-dev/issue-types`,
  `gh api orgs/hoshiori-dev/issue-fields`, and `pinnedFields` of `IssueType` in GraphQL).
- The repository on 2026-10-08: 68 issues (42 Task, 23 Feature, 3 Bug), 14 of them open; nine labels, GitHub's defaults,
  none applied to anything, and no file on `main` names one; no pull request open before this one; every issue and pull
  request so far opened by one account.
- What GitHub documents, read on 2026-10-08:
  - An issue form sets `type`, `labels`, `assignees`, and `projects`, never an issue field, and a label it names that
    does not exist is not added
    ([Syntax for issue forms](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms),
    [Adding and managing issue fields](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-and-managing-issue-fields)).
  - Field values are read and written under `/repos/{owner}/{repo}/issues/{issue_number}/issue-field-values`, with push
    access. A value names its field by numeric id and, for a single select, its option by name. `PUT` replaces every
    value of the issue, and `POST` with an empty list clears them
    ([REST API endpoints for issue field values](https://docs.github.com/en/rest/issues/issue-field-values)).
  - Issues are filtered with `type:"Bug"` and `field.priority:high,medium`; the documented sort keys hold no field
    ([Filtering and searching issues and pull requests](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/filtering-and-searching-issues-and-pull-requests)).
  - A parent issue holds up to 100 sub-issues, eight levels deep
    ([Adding sub-issues](https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/adding-sub-issues)).
  - Applying a label needs the triage role; creating, editing, or deleting one needs write access
    ([Repository roles for an organization](https://docs.github.com/en/organizations/managing-user-access-to-your-organizations-repositories/managing-repository-roles/repository-roles-for-an-organization)).
  - Dependabot ignores a configured label that does not exist, and adds `major`, `minor`, or `patch` when labels of
    those names exist
    ([Dependabot options reference](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference)).
  - An issue can be deleted by someone with admin rights once the organization allows it
    ([Deleting an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/administering-issues/deleting-an-issue)).
- Read from the `--help` of `gh` 2.102.0, the version in the dev container: `gh issue create` takes `--type`, `--label`,
  `--parent`, `--blocked-by`, and `--blocking`; `gh issue edit` takes `--type`, `--add-label`, `--parent`,
  `--add-sub-issue`, `--add-blocked-by`, and `--add-blocking`; neither has a flag for an issue field. The runners take
  `gh` from their image, which no file here pins.
- The `validate` job of `ci.yml` calls `just validate` on a pull request and `scripts/validate.ts` directly on a push to
  `main`. `ci.yml` is test infrastructure (`INFRA_PATHS`); the `justfile` is not.
- A concurrency group holds one running and one pending run; a newer pending run replaces an older one (`checks.md`,
  Release path).
- The skill tells an agent to build an issue body from the forms' `### <label>` headings, so a form's input labels are
  part of what an agent mirrors.
- GitHub limits a label's description to 100 characters, so the declaration cannot hold an area's full definition.
- What this design assumes without a documented statement or a measurement. The test issues measure 1 to 7 before any
  other issue is written to (Decisions); 8 and 9 cannot be produced before the merge:
  1. `POST` to the field-values endpoint with one field sets that field and leaves the issue's other fields alone.
  2. A second `POST` for a field that already has a value replaces the value, and `DELETE` clears it.
  3. The token the agent works with can write a field value. That it can create a label is shown by the first
     application of the declaration.
  4. `type:`, `label:`, and `field.priority:` combine in one filter, and `no:label` finds the issues without a label.
     Whether any filter finds an issue without a Priority is recorded with it; nothing here relies on one.
  5. `gh issue create --label` fails for a label that does not exist, and creates no issue.
  6. An Epic stays open when its last open sub-issue closes.
  7. A sub-issue added with `--parent` and a relationship added with `--add-blocked-by` are what the issue page and the
     API show.
  8. Dependabot applies the `ci` label to the pull requests it opens.
  9. The workflow's token can delete a label, and sees a label on a closed issue or on a pull request when it counts
     use.

## Goals / Non-Goals

**Goals:**

- A reference to a label the declaration does not hold cannot merge. Checked by the offline check running in
  `just check` and in the `validate` job of a pull request. `main` accepts changes only through pull requests, so the
  push run that skips the recipe has nothing new to catch.
- The workflow always applies the declaration `main` holds. Checked by its checkout naming `main` instead of the commit
  that started the run, so that rerunning an old run cannot apply an old declaration.
- The bound on who starts the workflow is a pull request event, not a person. A dispatch by someone with write access is
  outside it: that person can already edit labels and issues directly.
- The script changes the labels of this repository and of no other. Checked by the repository being named in every call
  from the constant `REPO` (`scripts/lib/repo.ts`), never taken from the clone's remote.
- A field is written without touching the issue's other fields. Checked by the skill giving the one call to use, and by
  assumption 1 being measured before it is used on an open issue.
- The headings an agent mirrors from the forms stay as they are. Checked by `git diff` showing no changed `label:` of an
  existing input.
- The areas are defined in one place. Checked by `github-workflow.md` holding the definitions, and by the declaration,
  `git-workflow.md`, the pull request template, and the skill naming the areas without defining them.

**Non-Goals:**

- A label on a pull request, a label for the specification state, and any workflow on a pull request event: #123.
- Checking a pull request title's scope against a list. No title has broken the convention, and a list would have to
  read `src/` from the pull request while the checker runs from the base commit.
- A label per feature. The feature id stays in the issue title; `feature` says only that the area is a feature.
- A way to rename a label and keep it on the issues that carry it. No label is renamed now; the five area labels are
  new.
- Types or labels on issues closed before this change and on merged pull requests, and retyping #8, #47, and #69.
- A roadmap view over the Epics.

## Decisions

- **The label set is a YAML file, `.github/labels.yml`, applied by `scripts/sync_labels.ts`.** Each entry has a name, a
  color, and a description. The script compares the declaration with the repository and prints the difference; with
  `--apply` it writes it. `--apply` first runs the validation of `--check` and writes nothing if it fails: the list is
  not empty, a color is six hexadecimal digits, a description has at most 100 characters. Names compare without regard
  to case, in the duplicate and reference checks too, and a name that differs only in case is updated to the declared
  spelling; colors compare without a leading `#` and in lower case, and a missing description as an empty one. It calls
  the REST API through `gh api`, never the `gh label` subcommands, so an unpinned `gh` on a runner changes nothing; `gh`
  takes the maintainer's login locally and the workflow's token in CI. `just labels` runs it. Rejected:
  - `gh label clone` from a template repository. It adds and never deletes, so the seven default labels would stay.
  - A third-party action. It needs an entry in the allowed list and a pin for something a short Deno script does.
  - An entry that names the label it replaces, so that a rename keeps the label on its issues. Nothing needs it now, and
    it brings cases of its own (both names present, the old name declared elsewhere).
- **Deleting is the guarded part.** `--apply` creates what is missing and updates what differs first. It then deletes an
  undeclared label only when no issue and no pull request, open or closed, carries it, which it reads from the list of
  issues filtered by that label, not from search; a label in use is listed, left alone, and makes the run exit non-zero.
  `--delete-used` lifts the refusal and `--keep-undeclared` skips every deletion. A changed name reads as one deletion
  and one creation and is caught the same way. Rejected: printing the difference and deleting anyway, which shows the
  loss in a log after it happened.
- **A workflow applies the declaration after it merges.** `.github/workflows/labels.yml` runs on a push to `main` that
  changes the declaration, and on a dispatch; a job condition on the ref makes a dispatch from another ref do nothing,
  as in `release.yml`. Its one job holds `issues: write` beside `contents: read`, checks out `main` without keeping
  credentials, passes the workflow's token to `gh`, and runs `sync_labels.ts --apply`. One concurrency group lets a
  running application finish; a pending run a newer one replaces is no loss, since each applies what `main` holds.
  `checks.md` gains the job and notes that `gh` comes from the runner image. Rejected:
  - Applying only by hand. The declaration and the repository would drift at the first forgotten run.
  - Applying on the pull request. It would put a write token within reach of a pull request, and a pull request from a
    fork gets none.
  - Running also when the script changes. The decision was the declaration and a dispatch; a changed script is applied
    by a dispatch when a maintainer wants it.
- **Before the merge only the five area labels are created; the merge removes the seven.** The labels have to exist for
  the open issues to be labelled and the acceptance filters to be read, and a workflow that is not on `main` cannot run.
  On the maintainer's command, given after reading the printed difference, the declaration is applied from the branch
  with `--keep-undeclared`. The removal of the seven default labels is left to the workflow's first run, so it happens
  only if the pull request merges, and that run exercises creating nothing but deleting under the workflow's token
  (assumption 9). Rejected:
  - Applying the whole declaration before the merge. The seven labels would be gone even if the pull request were
    rejected.
  - Merging the declaration first and bringing the open issues to the rules in a second pull request, which leaves this
    one unable to show its own acceptance.
- **The declaration is checked offline, inside `just validate`.** `sync_labels.ts --check` uses no network and runs
  nothing. Rejected:
  - A step of its own in `ci.yml`. That file is test infrastructure, so the edit would run the canary feature tests for
    a check that concerns no feature.
  - A unit test that reads the repository's files. The check has to be a command as well, for `just check` and before an
    application, so one implementation in `--check` serves both.
- **No form sets a label, so one filter is the triage list.** The rule is the proposal's: an open Feature, Bug, or Task
  without a Priority is not triaged. No documented filter finds a missing Priority, so the working list is
  `is:issue is:open no:label`: an issue from a form arrives with its type and nothing else, and triage sets the area
  label and, where the type takes one, the Priority together. An Epic takes a label as well, so that it leaves the list
  and shares the area filter with its sub-issues. Rejected: the Feature and Epic forms setting `feature`, after which a
  Feature from the form would carry a label and no Priority and drop out of the list.
- **Who sets what.**

  | Value                  | Issue from a form        | Issue an agent creates                                 |
  | ---------------------- | ------------------------ | ------------------------------------------------------ |
  | Type                   | The form                 | `--type`                                               |
  | Area label             | The maintainer at triage | `--label`                                              |
  | Priority               | The maintainer at triage | The agent proposes it; written after the confirmation  |
  | Parent, blocked by     | The maintainer           | `--parent`, `--blocked-by`, as the request states them |
  | Target date of an Epic | The maintainer           | Only on the maintainer's command                       |

  The agent names the Priority it proposes in the message that asks for the go-ahead to publish, not only inside the
  reviewed payload, so the go-ahead confirms a value the maintainer has read. Rejected: a default Priority written
  without asking, which would leave most issues at Medium and say nothing.
- **An Epic from the form is a proposal.** Blank issues are off and the forms are public, so anyone can file one. At
  triage the maintainer keeps it, retypes it, or closes it; an Epic nobody has kept gets no sub-issues. Rejected: no
  Epic form, which #12 asks for and which would leave a maintainer without a form of their own.
- **Priority is written with one call.** The skill gives it: `POST` to the issue's field-values endpoint with a list of
  exactly one value, the field's id and the option's name. It forbids `PUT` and an empty list, each of which clears the
  issue's other values, and reads the value back. `platform-settings.md` records the field's id with the command that
  reads it back. A recreated field gets a new id, and the write then fails loudly instead of setting a wrong value.
  Rejected: looking the id up by name on every write, which costs a second call and the `read:org` scope for a value
  that changes only when the organization rebuilds the field.
- **The forms keep their input labels.** The Bug form's first input stays "Feature" and its description takes a feature
  id or a harness area. The Epic form asks for the outcome of the stage, the issues expected under it, and what it
  leaves out.
- **Two test issues measure the assumptions first, then are closed.** After the area labels exist and before any open
  issue is written to, a test Epic and a test Feature under it are created by following the edited skill; their texts
  say they are tests. A Feature is used because Priority and both dates are pinned on it. For 1 and 2 it gets a
  Priority, then, on the maintainer's command, a Start date, then a changed Priority, then the date is cleared with
  `DELETE`; for 5, once the test Feature has been read back, a creation with a label that does not exist is attempted,
  and an issue it creates against expectation is closed and reported; for 6 the Feature is closed while the Epic is
  open. Both are closed as not planned when the observations are recorded, and they keep their labels and values; the
  maintainer may delete them. Their texts pass the publish gate like any other. The results go into one comment on this
  pull request before it is marked ready: for each assumption what was done, what was observed, and the conclusion. A
  refuted assumption this design relies on stops the work before the open issues are touched, and the package is
  revised. Rejected: measuring on the open issues themselves, which finds a wrong assumption only after it has written
  to them.

## Risks / Trade-offs

- **The removal of the seven labels is first seen after the merge.** Before it, only the printed difference shows it.
  Mitigation: the labels are on nothing, the refusal would stop the run if that changed, and a maintainer reads the
  first run; a failure is fixed forward and leaves at worst seven unused labels.
- **A declared label may not exist yet.** The offline check compares references with the declaration, not with the
  repository. Between a merge and the workflow's run, or after a failed run, a label Dependabot names, or one a later
  form names, can be missing, and both skip it without an error. Mitigation: a failed run is visible, and the next one
  creates the label.
- **A label made in the UI stops the workflow's deletions.** Someone with write access can still create a label by hand;
  once it is on an issue, each later run creates and updates as declared, leaves that label, and fails. That is the
  intended signal: the label is added to the declaration or removed by a maintainer.
- **The tiers widen what an agent may do.** Setting the type, a label, and relationships alone means a wrong one is
  published before anyone reads it; each is visible on the issue, reversible, and bounded to issues the agent created or
  took. Writing a Priority moves from never to after a confirmation; a wrong value misorders work until someone notices,
  which naming the value in the request for the go-ahead is meant to prevent. Applying the declaration on command
  creates labels and, with `--delete-used`, removes one from every issue that has it, which cannot be undone; that flag
  needs a command that names the label.
- **The triage list depends on someone reading it.** An issue from a form has no label and no Priority until a
  maintainer sets them, and nothing blocks on it. Mitigation: the harness review in `github-workflow.md` gains a check
  that `is:issue is:open no:label` is empty and that no open Epic is left without an open sub-issue.
- **An agent-created issue can lack a Priority and still leave the list.** It gets its label at creation and its
  Priority in a second call; if that call fails, the issue has a label and no Priority. Mitigation: the skill reads both
  back after creating an issue.
- **Assumptions 8 and 9 stay unmeasured until after the merge.** If Dependabot drops the label, its pull request has
  none, as today. If the workflow's token cannot delete, the first run fails with the seven labels still there.
- **`issues: write` is more than labels.** It allows editing and closing issues. Mitigation: the job runs reviewed code
  from `main`, on no pull request event, with no input from an issue or a pull request.
- **Priority has no order in a list.** A filter narrows by value, but nothing sorts by it. This is accepted.

## Migration Plan

Three constraints order the work; the steps themselves belong to the task list. The area labels exist before any issue
is labelled and before the skill or Dependabot names one. The test issues are measured before any open issue is written
to. Every remote write waits for the maintainer's command.

Rollback is a revert through a pull request. It restores the files and nothing else: what the proposal lists as remote
state stays. After a revert the workflow file is gone, so nothing runs, and the removed default labels can be created
again by hand.

## Open Questions

- The colors and descriptions of the five area labels. They change nothing else and are settled when the declaration is
  written.
- The titles of the two Epics. They are proposed with the backfill and pass the publish gate.
