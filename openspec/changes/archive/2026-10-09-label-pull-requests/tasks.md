# Tasks

## 1. Labels and their declaration

- [x] 1.1 Declare `spec:pending`, `spec:approved`, and `spec:archived` in `.github/labels.yml` with the design's colors
      and a description each, rename the five area labels to `area:<name>`, and point `.github/dependabot.yml` at
      `area:ci`; verify with `just validate` (the label check passes) and `just labels` (it reports the three state
      labels as missing and the five renamed ones as to be created, until the maintainer renames them).

## 2. The script

- [x] 2.1 Write `scripts/sync_pr_labels.ts`: the shebang grants `--allow-run=gh` and the named environment variables
      only; the API layer reads a pull request, its files, a tree, its label events, its comments, and an account's
      permission through `gh api`, and writes labels and the record comment; verify the first line with the unit test of
      task 2.6 and `deno check scripts/`.
- [x] 2.2 Implement the approval package read from a tree (every path of each unarchived change except exactly its
      `tasks.md`, plus the main spec of each capability with a delta, or its absence), the list of unarchived changes
      with their kind, and the refusal of a truncated tree; verify with unit tests for each Acceptance case of the state
      label (changed proposal, design, delta, metadata, added or renamed change, changed main spec with and without a
      delta, `tasks.md` alone, a `tasks.md` elsewhere, archive-only edits, nothing under `openspec/changes/`).
- [x] 2.3 Implement the state decision from the present: label, record comment, label events by id, and the two trees;
      the recording path for the run its own event started (sender, permission, bot, open, directory change, head
      unchanged after the reads, at most one record comment); the withdrawal by hand from the label history; verify with
      unit tests for the recording, each refusal, each withdrawal (also by a bot, in the same second, and after a run
      took the unrecorded label off), and `spec:pending` beside `spec:approved` in a run that does not record.
- [x] 2.4 Implement the path-to-area map with first match wins and a renamed file under both names, the file-list
      cut-short rule (no area label and no `spec:archived`), and the add-only rule for area labels; verify with unit
      tests, including the test that every file `git ls-files` lists matches a row.
- [x] 2.5 Implement the write path: the record first, then labels; one error path that puts `spec:pending` in place of
      `spec:approved` after the labels were read, only `spec:approved` off on a closed pull request, and nothing written
      on a closed pull request by a run that succeeds; the printing form that writes nothing; verify with unit tests for
      a failing read, a truncated tree, and a closed pull request.
- [x] 2.6 Build the record comment from fixed text with each field checked against its pattern, read a record only from
      one comment by `github-actions[bot]` of type `Bot` whose first line has the form, pass pull-request-controlled
      values to `gh api` only as string fields or in a request body and names in a path only percent-encoded, print such
      values only escaped, and accept a number only when it is digits; verify with unit tests using hostile values and
      the test that asserts the shebang on the file.
- [x] 2.7 Add the `pr-labels` recipe to the `justfile`; verify that the recipe prints, without a write, for #124
      `spec:archived`, `area:ci`, `area:scripts`, `area:harness`; for #132 `spec:archived`, `area:harness`; and for #134
      `spec:pending`, `area:ci`, `area:scripts`, `area:spec-workflow`, `area:harness`.

## 3. The workflow

- [x] 3.1 Write `.github/workflows/pr-labels.yml` as the proposal's Acceptance states: `pull_request_target` with the
      five activity types and a dispatch on `main` only; one job `label` in this repository only with `contents: read`
      and `pull-requests: write`, no permission at the top level, a five-minute limit, one concurrency group per pull
      request that cancels nothing; a checkout of the default branch without credentials and no ref; the tool setup
      without just; the script step with the token and the six environment variables; a last step that runs only after a
      failure and removes `spec:approved` with one fixed `gh api` call; verify with the tests of task 3.2.
- [x] 3.2 Add unit tests in `scripts/checks_test.ts` that assert each shape item of the workflow on the file (triggers,
      permissions, job condition, time limit, checkout, token placement, environment variables and no other event field,
      no `${{ }}` in a `run:` line, no secret, no action but the two, the failure step), that no cache action or input
      is named in the workflow or in `setup-tools`, and that no other workflow uses `pull_request_target` or
      `workflow_run`; verify with `just scripts-check`.

## 4. Rules and documents

- [x] 4.1 Edit `agent-authority.md` in the four places What Changes quotes and nowhere else; verify with
      `git diff main -- .agents/knowledge/agent-authority.md` showing only those hunks.
- [x] 4.2 Edit `spec-workflow.md` (Lifecycle, Approval gates, the specification block under Specifications and issues),
      `openspec/config.yaml` (the `tasks.md` rule and the apply guidance), the `github-project-workflow` skill (Take
      work, Create issues with the prefixed label, Finish, how `spec:approved` is read with `just pr-labels` and added
      on instruction), `AGENTS.md` (Core Conventions, Validation, Workflow), `CONTRIBUTING.md`, and the pull request
      template (`Approval:` line and the package-gate checklist item); verify that none still says the package approval
      is given in conversation or that nothing is recorded on GitHub (a search for "in conversation", "in the
      conversation", and "Nothing is recorded" finds only the freeze gate), and that `just spec-check` passes.
- [x] 4.3 Edit `github-workflow.md` (Objects in use, Areas with the prefixed labels and the sentence on pull requests,
      the Specifications block, Synchronization), `github/checks.md` (Rules with the named exception and its bounds, the
      job map, Toolchain pins, Waiting for the archive), `review-guidance.md` and `SECURITY.md` (the accepted risk);
      verify by reading each named place against the Acceptance items.

## 5. Integration

- [x] 5.1 Run `just check` and record each Acceptance item with its result in the pull request's Validation section,
      with the CI run; verify `scripts/check_pr_body.ts --template .github/pull_request_template.md --body-file <body>`
      accepts the description.
