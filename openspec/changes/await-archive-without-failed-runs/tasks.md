# Tasks

## 1. Archive checker

- [x] 1.1 In `scripts/check_spec_archived.ts`, keep statuses 0 and 1 for `--ready`, report the script's own unexpected
      errors with status 2, and under `--ready` in GitHub Actions name the unarchived changes in a warning annotation
      instead of an error; verify with unit tests in `scripts/checks_test.ts` over no change, an archive only, an
      unarchived change with and without `--ready`, and a changes path that cannot be read
- [x] 1.2 Rewrite the script's header comment, the `spec-status` comment in `justfile`, and its row in the Validation
      table of `AGENTS.md` so that none speaks of a verdict only a ready pull request gets; verify `just spec-status`
      exits 0 and `just spec-status --ready` exits 1 on this branch

## 2. PR workflow

- [x] 2.1 In `.github/workflows/pr.yml`, replace the job `spec-archived` with a deciding job that always runs the base
      commit's checker with `--ready` and maps status 0 to archived, 1 to unarchived, and any other status to a failed
      job, and a second job that needs it, succeeds either way, and is named `spec-archived` only when the output says
      archived and `awaiting-archive` otherwise; verify with a unit test that parses the workflow and checks the name
      expression, the absence of the draft state, and the unchanged `permissions:` and trigger
- [x] 2.2 Verify the step's status mapping by running its shell text locally against a stand-in checker that exits 0, 1,
      and 2

## 3. Documents

- [x] 3.1 Describe the waiting state instead of a red check in `.agents/knowledge/github/checks.md` (required checks,
      job map, Reading a run), `.agents/knowledge/spec-workflow.md`, `.agents/knowledge/github-workflow.md`, the Finish
      step of the `github-project-workflow` skill, the checklist item of `.github/pull_request_template.md`, and
      `CONTRIBUTING.md`; verify `git grep -n -i -w red` over the six finds no line about `spec-archived` or the archive
- [ ] 3.2 Verify `just check` passes with the implementation and the documents in place

## 4. Test pull request

- [ ] 4.1 Open a draft pull request against `main` from a branch cut from this one, titled and described as a test that
      will not be merged and closing no issue, through the publish gate; verify it holds this change unarchived and its
      PR workflow run uses the changed workflow
- [ ] 4.2 Observe the waiting state as a draft and as a ready pull request: the run's conclusion, the annotation, the
      check list, the blocked merge, the pull request list, and the reported checks (design items 1, 2, 5, 6); verify
      each observation has a link to its run or an API readback
- [ ] 4.3 Observe the passing state on a test-only commit that removes the change's directory (item 2); verify
      `spec-archived` reports `success` and no longer blocks the merge
- [ ] 4.4 Measure item 3 with a test-only commit that makes the deciding job fail, and item 4 with a test-only commit
      that makes the job name depend on the draft state; verify each has its run links and a conclusion
- [ ] 4.5 Record in `.agents/knowledge/github/checks.md` what the pull request page and the pull request list show for a
      pull request that waits for its archive, as observed; verify the text matches the readbacks
- [ ] 4.6 Post the conclusions of the eight items as one comment on this pull request through the publish gate — item 7
      from the runs' conclusions and a maintainer's statement, item 8 as not measured because no fork is available, on
      the maintainer's decision of 2026-10-06 — and close the test pull request with a comment that says so; verify the
      comment exists and the test pull request is closed and unmerged

## 5. Integration

- [ ] 5.1 Run `just check`, confirm this pull request has no failed PR workflow run from the commit that changes the
      workflow onward, and record every Acceptance item with its result in this pull request's Validation section
