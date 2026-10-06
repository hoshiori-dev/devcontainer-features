# Proposal

Implements [#111](https://github.com/hoshiori-dev/devcontainer-features/issues/111).

## Why

A pull request is marked ready before its change is archived, so the required check `spec-archived` fails for the whole
implementation deliberation, and each push or edit of the description produces another failed PR workflow run. GitHub
notifies the person who triggered a run when it fails. On 2026-10-05 the PR workflow had 48 failed runs, each with
`spec-archived` as its only failed job, while the CI workflow had none: every failed-run notification of that day
reported a state `spec-workflow.md` calls "not a defect", and a real failure would have arrived among them unnoticed. A
maintainer asked on 2026-10-06 for the merge block to stay and the failed runs to go.

## What Changes

- A pull request that holds an unarchived OpenSpec change is still blocked from merging by the required check
  `spec-archived`, but its PR workflow run concludes successfully: waiting for the archive is no longer a failure.
- The run still says why the pull request waits, naming each unarchived change.
- The check gives the same answer for a draft and for a ready pull request. Today a draft passes with a warning; after
  this change a draft that holds an unarchived change waits like a ready one.
- A failed PR workflow run means a defect again: a wrong title, an incomplete description, or the archive checker itself
  failing.
- The documents that describe `spec-archived` as red until the archive describe the waiting state instead:
  `.agents/knowledge/github/checks.md`, `.agents/knowledge/spec-workflow.md`, `.agents/knowledge/github-workflow.md`,
  the Finish step of the `github-project-workflow` skill, the checklist item of `.github/pull_request_template.md`, and
  `CONTRIBUTING.md`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `.github/workflows/pr.yml`; `scripts/check_spec_archived.ts` and its tests; the `spec-status` comment in
  `justfile` and its row in the Validation table of `AGENTS.md`; the six documents named above.
- Feature ids touched: none, so no version bump. `pr.yml` is not test infrastructure (`INFRA_PATHS` in
  `scripts/lib/repo.ts`), so CI selects no feature test for this change.
- Remote settings: none. The `main` ruleset and its required checks stay as they are.
- A test pull request is opened to exercise the changed workflow and closed without merging; it leaves a closed pull
  request and its branch behind.
- Open pull requests: each receives the changed workflow with its next run. A draft that passed `spec-archived` with a
  warning shows the waiting state from then on.

## Acceptance

**Becomes true:**

- On a pull request that holds an unarchived change, draft or ready, the PR workflow run concludes `success`, and its
  annotations name the unarchived change.
- On that pull request, once ready, GitHub reports the merge as blocked with `spec-archived` as the unmet required
  check.
- On the commit that archives the change, `spec-archived` reports `success` and no longer blocks the merge.
- A failure of the archive checker itself — an error other than finding an unarchived change — ends the run as a
  failure.
- From the commit that changes the workflow onward, this pull request has no failed PR workflow run whose only failed
  job concerns the unarchived change.
- None of the six documents calls the waiting state red: `git grep -n -i -w red` over them finds no line about
  `spec-archived` or the archive.
- `.agents/knowledge/github/checks.md` states what the pull request page and the pull request list show for a pull
  request that waits for its archive, as observed on the test pull request.
- A test pull request, opened once the implementation is complete and serving no purpose beyond exercising the changed
  workflow, showed the waiting state and the passing state; its observations are in this pull request's Validation
  section, and it is closed.
- Every assumption the design lists as unmeasured has its conclusion in a comment on this pull request: confirmed or
  refuted by a measurement on the test pull request, or named as not measured with the reason.

**Stays true:**

- A pull request that holds an unarchived change cannot be merged, whatever the outcome of the PR workflow run: a
  success, a failure, a cancellation, or no run at all.
- The `main` ruleset requires `ci-gate`, `pr-title`, `pr-checklist`, `spec-archived`, and `secret-scan`, and nothing
  else (`gh api repos/hoshiori-dev/devcontainer-features/rulesets/24225927`).
- The PR workflow keeps `permissions: contents: read` and its `pull_request` trigger; no workflow uses
  `pull_request_target` or `workflow_run`, and none writes to the repository on behalf of a pull request.
- The verdict comes from the base commit's copy of `scripts/check_spec_archived.ts` (`.github/actions/base-checks`).
- A pull request from a fork gets the same verdict and the same block as one from a branch of this repository.
- No workflow archives a change; the archive follows a maintainer's command, and both approval gates are unchanged.
- `just spec-status` lists the unarchived changes and exits zero; with `--ready` it exits non-zero when one exists.
- `pr-title`, `pr-checklist`, `ci-gate`, and `secret-scan` behave as before.
- The test pull request is never merged, and `main` receives nothing from it.
- No file under `src/`, `test/`, or `openspec/specs/` changes, and `just check` passes.
