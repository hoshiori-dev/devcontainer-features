# Tasks

Every task of groups 5 to 7 is a remote write: it waits for the maintainer's command in the conversation, passes the
publish gate, and is named with its command in the pull request's Validation section.

## 1. Label declaration and script

- [x] 1.1 Add `.github/labels.yml` with the five area labels, `good first issue`, and `help wanted`, each with a color
      and a description of at most 100 characters; verify `scripts/sync_labels.ts --check` passes on it
- [x] 1.2 Add `scripts/sync_labels.ts` with `--check`: no network, fails for an empty or malformed list, a color that is
      not six hexadecimal digits, a description over 100 characters, a name used twice in any case, the names `major`,
      `minor`, and `patch`, and a label named by an issue form or `.github/dependabot.yml` that the declaration lacks;
      verify with one unit test per case in `scripts/sync_labels_test.ts`
- [x] 1.3 Add the comparison: names without regard to case with a case-only difference as an update, colors without `#`
      and in lower case, a missing description as empty; verify with unit tests that a matching repository yields no
      difference and that each kind of difference is reported once
- [x] 1.4 Add the application behind `--apply`, through `gh api` against the repository named by `REPO`: validate first
      and write nothing on failure, create and update, then delete an undeclared label only when the list of issues
      filtered by it, in any state, is empty; a label in use is listed, kept, and makes the exit status non-zero;
      `--delete-used` lifts the refusal (9.5 makes it take the label's name) and `--keep-undeclared` skips deletions;
      verify with unit tests over a stubbed API for each path, including that a matching repository causes no write
- [x] 1.5 Add the `labels` recipe to the `justfile`, run `sync_labels.ts --check` from the `validate` recipe after
      `scripts/validate.ts`, and add the recipe to the Validation table of `AGENTS.md`; verify `just validate` fails
      with a broken declaration and passes with the real one, and `just scripts-check` passes

## 2. Workflow

- [x] 2.1 Add `.github/workflows/labels.yml`: started by a push to `main` that changes `.github/labels.yml` and by a
      dispatch, with a job condition on the ref; `permissions: contents: read` at the top and `issues: write` on its one
      job; a checkout of `main` that keeps no credentials; the workflow's token passed to `gh`; one concurrency group
      that cancels nothing; actions pinned by full commit SHA; verify with a unit test in `scripts/checks_test.ts` that
      parses the workflow and checks the triggers, the permissions, the checkout, and the command, which never passes
      `--delete-used` (9.1 adds `--keep-undeclared`)
- [x] 2.2 Add the job to the job map of `.agents/knowledge/github/checks.md` and note there that `gh` comes from the
      runner image; verify the row names the command the job runs

## 3. Forms, Dependabot, and the pull request template

- [x] 3.1 Edit `01-bug.yml` (description covers the harness, the first input takes a feature id or a harness area, the
      base image is not required), `02-feature.yml` (names a behavior change), and `03-task.yml` (names upkeep of a
      feature), and add `04-epic.yml` with the type Epic and the three questions of the design; verify no form sets a
      label, `git diff` shows no changed `label:` of an existing input, and the YAML pre-commit hook passes
- [x] 3.2 Set `labels: ["ci"]` in `.github/dependabot.yml`; verify `sync_labels.ts --check` passes
- [x] 3.3 Name the harness scopes beside the feature id in the first comment of `.github/pull_request_template.md`;
      verify `scripts/check_pr_body.ts` still accepts this pull request's description

## 4. Knowledge base, skill, and authority

- [x] 4.1 In `.agents/knowledge/github-workflow.md`, define the four types, the sub-issue rule of each, the Epic rule,
      the "blocked by" rule, the field rules, and the five areas; move Priority, sub-issues, and labels out of
      "Deliberately not used"; rewrite Triage and Planning view around `is:issue is:open no:label`; add the
      Synchronization rows for an added or renamed area and for a label a form or Dependabot names; add the two checks
      to the harness review; correct the statement about reading issue types; verify each Acceptance item about this
      file against the text
- [x] 4.2 In `.agents/knowledge/git-workflow.md`, replace the harness scope `openspec` with `spec-workflow`; verify
      `git grep -n openspec .agents/knowledge/git-workflow.md` finds no scope
- [x] 4.3 In `.agents/knowledge/github/platform-settings.md`, update the issue types row from the readback, add rows for
      the label set and for the Priority field with its id and the command that reads it back, state the label set as
      the exception to the opening rule, and update the verified date; verify each value against a fresh readback
- [x] 4.4 In the `github-project-workflow` skill, name the calls that set the type, the area label, the parent, and
      "blocked by", give the one call that writes a Priority with its body and the ban on `PUT` and on an empty list,
      say that the agent names the proposed Priority when it asks to publish and reads the label and the Priority back,
      and remove the sentence that forbids priority; verify by reading the Create issues section against the design
- [x] 4.5 Write the tiers of the proposal into `.agents/knowledge/agent-authority.md`, word for word, once the
      maintainer has said who writes them; verify the file holds them, or that the maintainer's commit does
- [x] 4.6 Update the overview in `CONTRIBUTING.md` where it names the forms, and check `SECURITY.md` against the new
      workflow permission; verify both still describe the repository

## 5. Area labels on the repository

- [x] 5.1 Show the maintainer the difference `just labels` prints, and on their command apply the declaration with
      `--apply --keep-undeclared`; verify `gh label list` shows the five area labels as declared and the nine default
      labels still present, and that a second run with the same flags writes nothing

## 6. Test issues

- [x] 6.1 Create a test Epic and a test Feature under it by following the edited skill, the Feature with an area label
      and the Priority the maintainer confirmed; verify by reading the Feature back before anything else is done to it
- [x] 6.2 Measure assumptions 1 to 7 on the two test issues: a Start date beside the Priority, a changed Priority, the
      date cleared with `DELETE`; a creation with a label that does not exist; the filters; the parent and a "blocked
      by" relationship between the two as the page and the API show them; the Feature closed while the Epic is open;
      verify each has an observation and a conclusion, and stop if one the design relies on is refuted
- [x] 6.3 Close both test issues as not planned and post the conclusions for assumptions 1 to 9 as one comment on this
      pull request, 8 and 9 named as not measured with the reason; verify the comment is on the pull request

## 7. Open issues

- [x] 7.1 Create the two Epics, for phase 2 (#56–#60) and phase 3 (#61–#63) of the package-manager features, with the
      `feature` label, and add the eight issues as their sub-issues; verify with `gh issue view --json subIssues`
- [x] 7.2 Mark #61, #62, and #63 as blocked by #56, #57, and #59; verify with `gh issue view --json blockedBy`
- [x] 7.3 Add the area label the proposal gives to each open issue; verify `is:issue is:open no:label` returns nothing
- [x] 7.4 Propose a Priority for each open Feature, Bug, and Task in one list, and write each value the maintainer
      confirms; verify by reading every value back and with the filter of the proposal's Acceptance

## 8. Integration

- [x] 8.1 Record the Priority field's id and the label set in `platform-settings.md` as read back after groups 5 to 7;
      verify the readbacks match the file
- [x] 8.2 Run `just check`, with the OpenSpec version CI pins if the local one differs, and record the result and every
      remote write with its command in the pull request's Validation section; verify each Acceptance item of the
      proposal has its result there

## 9. Review follow-up

- [x] 9.1 Make the workflow pass `--keep-undeclared` and run in this repository only, and say in its comments and in the
      head of `scripts/sync_labels.ts` why no unattended run deletes; verify with the workflow test in
      `scripts/checks_test.ts`
- [x] 9.2 Fail the offline check for a declared name with white space around it, with a comma, or equal to `.` or `..`;
      verify with one unit test over the three cases and over names that stay valid
- [x] 9.3 Bring the proposal, the design, `github-workflow.md` (the harness review), `github/checks.md` (the `sync`
      row), and `github/platform-settings.md` (the Labels row, its readback included) to the above; verify `just labels`
      prints what the row says
- [x] 9.4 On the maintainer's command, delete the seven default labels with `just labels --apply` after reading the
      printed difference; verify `just labels` prints that the labels match and record the row in
      `github/platform-settings.md` as enforced
- [x] 9.5 Make `--delete-used` take the name of the one undeclared label it frees, repeatable and with no form for all
      labels; stop before the first write when a name is empty, is not an undeclared label, or meets
      `--keep-undeclared`; show one selected type in the skill's `gh issue create` call instead of the four joined by
      `|`; verify with unit tests of the split, of the refusals, and of the command line
