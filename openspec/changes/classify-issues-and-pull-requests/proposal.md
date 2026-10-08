# Proposal

Implements [#12](https://github.com/hoshiori-dev/devcontainer-features/issues/12).

## Why

An issue here states almost nothing a list can filter on. The type is the only metadata in use, and it follows no
written rule for the harness: the Bug form admits only a published feature, so harness defects were filed as Tasks (#8,
#47, #69) until #95 and #96 were filed as Bugs against the form. No issue has a label or a field value, 30 of 68 issues
name no feature in their title, and related issues such as #56–#63 are tied together by title wording alone. The
knowledge base defers labels, priority, and sub-issues behind triggers a maintainer decided on 2026-10-08 not to wait
for, after the organization gained an Epic type and defined its fields
([hoshiori-dev/.github#1](https://github.com/hoshiori-dev/.github/issues/1)). The counts include #123, filed since #12
was last edited.

## What Changes

- **Types.** The four issue types have one written meaning in this repository. A Bug is a published feature or the
  harness behaving differently from its specification or documentation. A Feature is a new feature for the collection,
  or a new capability or behavior change of an existing one. A Task is all other planned work, a new capability of the
  harness included. An Epic is one stage of the collection's functionality that takes several issues to deliver.
- **Relationships.** Issues are grouped and ordered with GitHub's relationships. An Epic has Features, Bugs, and Tasks
  as sub-issues and is never a sub-issue itself. A Feature, a Bug, or a Task has no sub-issues: only an Epic has them.
  An issue that cannot start before another is marked as blocked by it.
- **Epics.** An Epic exists on a maintainer's word: the maintainer creates it, tells an agent to, or keeps one that
  arrived through the form. No pull request closes an Epic; the maintainer closes it, or tells an agent to, once its
  sub-issues are closed and the stage's outcome holds.
- **Priority.** An open Feature, Bug, or Task without a Priority has not been triaged. An Epic has none: it is a
  long-running plan, and ordering such plans on a roadmap belongs in GitHub Projects, which stays unused.
- **Other fields.** Effort is not used here. The Start date and Target date of a Feature are a plan and are optional.
  The Target date of an Epic is a goal and is optional.
- **Labels.** A label states the area of an issue: `feature` (a feature under `src/<id>/`, with its tests and its
  specification), `ci` (the workflows, the composite actions, and Dependabot), `scripts` (the Deno scripts and the
  `justfile`), `spec-workflow` (the OpenSpec process, its configuration, and its generated skills), or `harness` (the
  knowledge base, the project skills, the templates and forms, the dev container, and the root documents). A triaged
  issue of any type has at least one, usually one. The kind stays with the type and the order with Priority.
- **Label set.** The repository's labels are declared in one file: the five area labels and the two GitHub shows to new
  contributors, `good first issue` and `help wanted`. The other seven default labels are removed. Agents and the
  workflow change labels only by applying that file.
- **Scope name.** The harness area `openspec` is renamed `spec-workflow`, as an area and as a pull request title scope,
  so that `openspec` names only the feature of that id.
- **Forms.** The Bug form accepts a harness defect, the Feature form names a behavior change, the Task form names upkeep
  of a feature beside harness work, and an Epic form exists.
- **Dependabot.** Its pull requests carry the `ci` label.
- **Authority.** `agent-authority.md` says what an agent sets on an issue. Only the Priority tier was settled in the
  discussion before this package; the rest is proposed here:
  - alone, on an issue it creates or has taken: the type, an existing area label, and the parent and "blocked by"
    relationships the request states;
  - after the maintainer confirms the value, which the agent names when it asks to publish: a Priority;
  - only on a maintainer's command: applying the label declaration, creating or closing an Epic, setting a date field,
    and changing the metadata of an issue it has not taken;
  - only on a maintainer's command that names the label: deleting a label that issues or pull requests still carry;
  - never: creating, renaming, or deleting a label by any means but the declaration, or setting Effort.
- **Knowledge base and skill.** They carry the rules above and name the calls that set each value. The statement that
  the organization's issue types cannot be read with a token is corrected.
- **Open issues.** The 14 open issues are brought to these rules; #123, filed since #12 was written, is one of them and
  is already marked as blocked by #12. The rest of this item is proposed here, not settled before. Two Epics are
  created, one for phase 2 of the package-manager features (#56–#60) and one for phase 3 (#61–#63), and #61, #62, and
  #63 are each marked as blocked by the phase 2 issue of the same feature (#56, #57, #59). Area labels: `feature` for
  #56–#63, #119, and the two Epics; `ci` for #96, #118, and #123; `scripts` for #95; `harness` for #12. Each open
  Feature, Bug, and Task gets the Priority the maintainer confirms.

## Capabilities

### New Capabilities

None. This change edits the harness only (`skip_specs: true`).

### Modified Capabilities

None.

## Impact

- Files: the issue forms under `.github/ISSUE_TEMPLATE/`; `.github/dependabot.yml`; `.github/pull_request_template.md`;
  a new label declaration under `.github/`, with the Deno script that applies and checks it, the script's tests, a
  `just` recipe, and a workflow; `.agents/knowledge/github-workflow.md` (its Synchronization table included),
  `git-workflow.md`, `agent-authority.md`, `github/platform-settings.md`, and `github/checks.md`; the
  `github-project-workflow` skill; the Validation table of `AGENTS.md`; and `CONTRIBUTING.md` where its overview names
  the forms.
- Feature ids touched: none, so no version bump. No file under `src/`, `test/`, or `openspec/specs/` changes, and none
  of the changed files is test infrastructure (`INFRA_PATHS` in `scripts/lib/repo.ts`), so CI selects no feature test.
- Remote state written before the merge, each write on the maintainer's command: the five area labels created; the
  labels and Priority of the open issues; the two Epics with their sub-issues and the "blocked by" relationships; a test
  Epic and a test Feature, closed when their observations are recorded; one comment on this pull request with those
  observations. Reverting the pull request undoes none of it: the labels, values, and relationships stay, and the new
  issues stay unless someone with admin rights deletes them.
- Remote state written by the merge: the workflow's first run removes the seven default labels. They are on nothing, and
  they do not come back with a revert.
- Remote settings: the `main` ruleset, its required checks, and the Actions settings stay as they are. The label set is
  the one setting this change takes over: `platform-settings.md` gains its row, and its opening rule, that agents never
  change a remote setting, gains the label set as its one exception, bound to the tiers above. The organization's types
  and fields were configured in hoshiori-dev/.github#1 and are only read here.
- Workflow permissions: one new workflow holds `issues: write` in one job. It runs on `main` and by dispatch, never on a
  pull request event. A workflow's `permissions:` is security-sensitive surface (`agent-authority.md`, Escalation); it
  is named here so that the approval of this package covers it.
- Authority: the tiers under What Changes are the exact addition to `agent-authority.md`. Its "No self-escalation"
  section forbids an agent to edit that file to relax its own limits and lets work resume only after a maintainer
  explicitly updates the policy. The tiers widen what an agent may do, so the approval of this package has to say
  whether they are accepted. The agent writes them into the file, word for word as they stand here, only on the
  maintainer's explicit instruction in the conversation; without one the maintainer commits that edit, and the
  implementation waits for it. The design gives the risk of each tier.
- Pull requests: their area label is not part of this change (#123). Until that lands, only Dependabot's pull requests
  carry one.
- A pull request opened after the merge uses the scope `spec-workflow` where it would have used `openspec` for the
  harness. No pull request is open besides this one.

## Acceptance

**Becomes true:**

- `.agents/knowledge/github-workflow.md` defines the four types, the sub-issue rule of each, the Epic rule, the "blocked
  by" rule, the field rules, and the five areas as What Changes states them, no longer lists Priority, sub-issues, or
  labels beyond GitHub's defaults under "Deliberately not used", and its Synchronization table names what has to change
  together when an area is added or renamed.
- When this pull request is marked ready, the five area labels exist with the colors and descriptions the declaration
  gives, and the difference the script reports between the declaration and the repository is exactly the removal of the
  seven default labels, each carried by nothing.
- A unit test shows that applying a declaration the repository already matches writes nothing.
- `just check` fails when the declaration is malformed, names a label twice, or names `major`, `minor`, or `patch`, and
  when an issue form or `.github/dependabot.yml` names a label the declaration does not hold. Each case has a unit test.
- No unattended run removes a label that an issue or a pull request carries; a unit test shows the refusal.
- No pull request event can start the workflow that applies the declaration: its triggers are a push to `main` that
  changes the declaration and a dispatch. Its one job holds `issues: write` and `contents: read` and nothing else.
- In `01-bug.yml` the description covers the harness, the base image is not required, and the first input accepts a
  harness area; `02-feature.yml` names a behavior change; `03-task.yml` names upkeep of a feature; a fourth form sets
  the type Epic. No form sets a label.
- `.github/dependabot.yml` names the label `ci`.
- `git-workflow.md` gives `spec-workflow` among the harness scopes and no longer gives `openspec`; the pull request
  template's comment names the harness scopes beside the feature id.
- When this pull request is marked ready: every open issue has the area label What Changes gives it, every open Feature,
  Bug, and Task has a Priority, #56–#63 are sub-issues of the two Epics, #61, #62, and #63 are blocked as stated, and
  `is:issue is:open no:label` returns nothing.
- The filter `is:issue is:open type:"Bug" label:ci field.priority:urgent,high,medium,low` returns the open Bugs in the
  `ci` area.
- The test Feature of the design, read back right after it is created by following the edited skill and before anything
  else is done to it, carries its type, an area label, and the Priority the maintainer confirmed, each set by a call the
  skill names.
- Each assumption the design lists as unmeasured has its conclusion in one comment on this pull request: confirmed or
  refuted by an observation, or named as not measured with the reason.
- `github-workflow.md` and `github/platform-settings.md` no longer say that the organization's issue types are verified
  in the UI only; `platform-settings.md` records the label set, the Epic type, and the Priority field with its id as
  read back.
- `agent-authority.md` holds the tiers of What Changes.
- The Validation section of this pull request names every remote write made for it, with the command that made it.

**Stays true:**

- The `main` ruleset requires `ci-gate`, `pr-title`, `pr-checklist`, `spec-archived`, and `secret-scan`, and nothing
  else.
- No workflow uses `pull_request_target` or `workflow_run`, and no workflow that runs on a pull request event holds a
  write permission. Every workflow declares `permissions:`, and every action is pinned by full commit SHA.
- The organization's issue types and fields are as hoshiori-dev/.github#1 records them; nothing here changes them.
- An issue closed before this change, and every merged pull request, keeps its type and gets no label and no field
  value.
- The Decomposition section of `github-workflow.md` still says that the steps inside one outcome are tasks in the
  OpenSpec change's `tasks.md`, not issues.
- GitHub Projects, milestones, Releases, and Discussions stay under "Deliberately not used".
- Both approval gates and the archive rule are unchanged, and no label records them (#123 proposes that separately).
- `pr-title` accepts the same titles as before: the scope is still not checked against a list.
- Nothing published for this change — the test issues, the Epics, comments, and this pull request — holds a secret, a
  credential, an internal host, or personal data.
- No file under `src/`, `test/`, or `openspec/specs/` changes, and `just check` passes.
