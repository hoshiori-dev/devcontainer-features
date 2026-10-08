# GitHub Workflow

Read this before creating a branch, opening or updating an issue or pull request, applying labels, creating a milestone,
or proposing any new management structure. GitHub is this repository's only remote and task-management platform, so
every rule here is written in GitHub terms.

`hoshiori-dev/devcontainer-features` (organization-owned, public). Maintainers are the repository collaborators with
write access (`gh api repos/hoshiori-dev/devcontainer-features/collaborators`). The organization provides native issue
types (Epic / Feature / Bug / Task) and issue fields; a token with the `read:org` scope reads them
(`gh api orgs/hoshiori-dev/issue-types`, `gh api orgs/hoshiori-dev/issue-fields`).

## What this repository is

A collection of Dev Container Features, each developed in `src/<id>/` and published independently to
`ghcr.io/hoshiori-dev/devcontainer-features/<id>` with its own semantic version. Consumers pin a floating major tag
(`:1`), so a merged change that bumps a feature's version reaches every consumer on their next container build without
any action on their side. Acceptance therefore has to be complete before merge, and a bad release is rolled back by
publishing a higher fixed version — a published version cannot be withdrawn from the floating tags.

## Objects in use

| Object                                    | Meaning here                                                                                                                                                                                                                                                                                                                                                                                                        | What is lost without it                                                                  |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Issue                                     | One independently acceptable outcome, or, as an Epic, the stage that groups several. Typed with one of the four native issue types.                                                                                                                                                                                                                                                                                 | The record of why a change exists and who asked for it; PRs would have nothing to close. |
| Pull request                              | Every change to `main`. A draft PR is work in progress — including a draft whose first content is an OpenSpec change awaiting approval — never a placeholder for planned work.                                                                                                                                                                                                                                      | Review, CI feedback, and the single place where acceptance happens.                      |
| Acceptance                                | The required check `ci-gate` passes, the Acceptance of the PR's OpenSpec change is verified (see `spec-workflow.md`), and a maintainer merges.                                                                                                                                                                                                                                                                      | Merge would equal an unchecked release to every consumer.                                |
| Issue types (Epic / Feature / Bug / Task) | The kind of work, set by the issue form. Bug: a published feature or the harness behaves differently from its specification or documentation. Feature: a new feature for the collection, or a new capability or behavior change of an existing one. Task: all other planned work, a new capability of the harness included. Epic: one stage of the collection's functionality that takes several issues to deliver. | Filtering defects from new work.                                                         |
| Epic                                      | Groups the issues of one stage as its sub-issues and shows how far the stage is (Epics).                                                                                                                                                                                                                                                                                                                            | The shared goal of related issues; they would be tied together by title wording alone.   |
| Sub-issues                                | The parent of an issue: an Epic's Features, Bugs, and Tasks; no other type has sub-issues (Relationships).                                                                                                                                                                                                                                                                                                          | Progress of a stage read from one issue.                                                 |
| "Blocked by" relationship                 | An issue that cannot start before another is marked as blocked by it (Relationships).                                                                                                                                                                                                                                                                                                                               | The order between issues; work would start on something that cannot finish.              |
| Priority field                            | When an open Feature, Bug, or Task is worked on, relative to other work: Urgent, High, Medium, or Low (Fields).                                                                                                                                                                                                                                                                                                     | Picking the next issue from a filter instead of from memory.                             |
| Target date of an Epic                    | The date a stage aims at; a goal, optional (Fields).                                                                                                                                                                                                                                                                                                                                                                | A stated horizon for a stage.                                                            |
| Area labels                               | The part of the repository an issue concerns (Areas). The kind stays with the type and the order with Priority.                                                                                                                                                                                                                                                                                                     | Filtering by area; the title alone does not say it.                                      |
| Tag `<id>/v<version>`                     | Marks the commit a published feature version was built from; created by the release workflow, never by hand (see `git-workflow.md`).                                                                                                                                                                                                                                                                                | Mapping a GHCR version back to the commit it was built from.                             |
| GHCR package version                      | The delivery: what consumers actually install.                                                                                                                                                                                                                                                                                                                                                                      | — (it is the product).                                                                   |

## Areas

A label states the area of an issue and nothing else. This section is the one definition of the areas; every other file
names them, and `.github/labels.yml` repeats each in the hover text of its label (Synchronization).

| Label           | Covers                                                                                                      |
| --------------- | ----------------------------------------------------------------------------------------------------------- |
| `feature`       | A feature under `src/<id>/`, with its tests and its specification. The feature id stays in the issue title. |
| `ci`            | The workflows, the composite actions, and Dependabot.                                                       |
| `scripts`       | The Deno scripts and the `justfile`.                                                                        |
| `spec-workflow` | The OpenSpec process, its configuration, and its generated skills.                                          |
| `harness`       | The knowledge base, the project skills, the templates and forms, the dev container, and the root documents. |

A triaged issue of any type has at least one area label, usually one. An Epic carries the area of its sub-issues.

The repository's labels are exactly the set `.github/labels.yml` declares, and they change only by applying that file
(`github/platform-settings.md`, Labels row). Who may apply it, and what an agent sets on an issue alone, is in
`agent-authority.md`.

## Relationships

| Type               | Sub-issues                | Parent                             |
| ------------------ | ------------------------- | ---------------------------------- |
| Epic               | Features, Bugs, and Tasks | None: an Epic is never a sub-issue |
| Feature, Bug, Task | None                      | An Epic                            |

An issue that cannot start before another is marked as blocked by it.

## Epics

- An Epic exists on a maintainer's word: the maintainer creates it, tells an agent to, or keeps one that arrived through
  the form.
- An Epic from the form is a proposal. At triage the maintainer keeps it, retypes it, or closes it; an Epic nobody has
  kept gets no sub-issues.
- No pull request closes an Epic: write `Closes #<n>` only for its sub-issues. The maintainer closes the Epic, or tells
  an agent to, once its sub-issues are closed and the stage's outcome holds.

## Fields

| Field                                | Rule                                                                                                                                                                                        |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Priority                             | An open Feature, Bug, or Task without one is not triaged. An Epic has none: it is a long-running plan, and ordering such plans on a roadmap belongs in GitHub Projects, which stays unused. |
| Effort                               | Not used here; leave it empty.                                                                                                                                                              |
| Start date, Target date of a Feature | A plan; optional.                                                                                                                                                                           |
| Target date of an Epic               | A goal; optional.                                                                                                                                                                           |

The field ids and what each type offers are in `github/platform-settings.md`; the call that writes a Priority is in the
`github-project-workflow` skill (Create issues).

## Deliberately not used

| Object          | Enable when                                                                                                                     |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Milestones      | A theme spans several PRs across features and needs a completion view (e.g. "add a language toolchain family").                 |
| GitHub Projects | Three or more people work in parallel and filtered issue lists stop being enough, or the Epics need a roadmap that orders them. |
| GitHub Releases | Consumers need release notes beyond each feature's generated README; the tag and GHCR version are the release record today.     |
| Discussions     | Outside users start asking questions that are not actionable issues.                                                            |

## Decomposition

Create a separate issue only when the piece independently earns its own discussion and acceptance. In practice that is
one issue per feature change: "add feature `foo`", "`foo`: support Alpine", "`foo`: install fails on arm64". Steps
inside that outcome — writing the test scenarios, the compatibility list, the docs — are tasks in the OpenSpec change's
`tasks.md`, not issues. A change that touches a feature and, through `dependsOn`, forces a version bump in its
dependents is still one issue.

A Task has no sub-issues: a batch of small work is one Task per piece that gets its own pull request, each naming the
others it belongs with. An Epic is used when a stage of the collection takes several such outcomes to deliver (for
example one phase of the package-manager features); the Epic holds the stage's outcome and each sub-issue its own.

## Triage

The working list is `is:issue is:open no:label`. An issue from a form arrives with its type and nothing else: no form
sets a label, and no automation applies labels to issues. A maintainer reads the list and, once an issue has enough
detail to act on (feature id, image, reproduction for a bug), sets:

- the area label (Areas), on an issue of any type;
- the Priority, on a Feature, Bug, or Task (Fields).

Set both together: no documented filter finds a missing Priority, so an issue with a label and no Priority has left the
list untriaged. An Epic from the form is decided as Epics states.

## Planning view

Filtered issue and PR lists. Any view is rebuildable; the facts live on issues, PRs, and the OpenSpec specs.

| List                                      | Filter                                                            |
| ----------------------------------------- | ----------------------------------------------------------------- |
| Triage                                    | `is:issue is:open no:label`                                       |
| Work to pick, by type, area, and Priority | `is:issue is:open type:"Bug" label:ci field.priority:urgent,high` |
| Work in progress                          | `is:pr is:draft`                                                  |

A filter narrows by Priority; nothing sorts by it.

## Agent authority

Governed by `.agents/knowledge/agent-authority.md`.

## Other contracts

- Branches, merge method, and tags: `.agents/knowledge/git-workflow.md`.
- Specifications, their approval, and archiving: `.agents/knowledge/spec-workflow.md` — a PR's acceptance is the
  proposal's Acceptance of the OpenSpec change it implements, with the scenarios it points to.

## Update this file when

- A second regular contributor joins, or outside contributions start arriving.
- A "not used" trigger fires.
- An object in use goes unused for a sustained period — remove it, do not let it rot.
- How features reach consumers changes (a new registry, a second namespace, pinned-digest consumers).
- GitHub changes what organization-owned public repositories get natively.

## Specifications

The OpenSpec contract lives in `.agents/knowledge/spec-workflow.md`. Because of it:

- the PR template carries the specification block under `## Related work` (`Spec:`, `Phase:`, `Records:`, `Approval:`)
  and checklist items for the package gate and the archive command;
- the Feature request and Task forms carry an optional `Specification` field, and their acceptance fields defer to the
  change's proposal Acceptance and the scenarios it points to;
- the `github-project-workflow` skill's Take work, Create issues, and Finish steps apply the gates, the reconciliation,
  and the archive-on-command rule;
- the `spec-archived` check (workflow PR, `scripts/check_spec_archived.ts`) is withheld from a PR that still holds an
  unarchived change, draft or ready, which blocks its merge without failing the run (`github/checks.md`, Waiting for the
  archive). No other OpenSpec automation exists: no comment commands, no status labels, no archiving job.

A ready PR needs `Phase: implementation`, a `Spec:` line, no reserved line left in Changes or Validation, and every
checklist item ticked except the one `spec-archived` tracks. When the OpenSpec layout or version changes, re-check every
template link and path above.

## Synchronization

| When this changes                                                          | Update in the same PR                                                                                                                                                                                                                                             | Owner                                            |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------ |
| A CI or PR job is renamed or added                                         | `github/checks.md` job map; the `main` ruleset's required checks (maintainer, `github/platform-settings.md`)                                                                                                                                                      | PR author; maintainer for the ruleset            |
| A `just` recipe CI calls                                                   | the job that calls it and the `github/checks.md` map                                                                                                                                                                                                              | PR author                                        |
| PR template `##` headings or the security item                             | nothing else — `scripts/check_pr_body.ts` reads the template; keep the word "secrets" in the security item                                                                                                                                                        | PR author                                        |
| PR template specification block or checklist items                         | `spec-workflow.md` if a gate or the archive rule changed, else revert the template                                                                                                                                                                                | PR author                                        |
| Issue form `type:` values                                                  | organization issue types row in `github/platform-settings.md`                                                                                                                                                                                                     | Maintainer                                       |
| An area is added, renamed, or redefined                                    | `.github/labels.yml` (the name and its hover text), the definitions under Areas here, the harness scopes in `git-workflow.md`, the comment at the top of `.github/pull_request_template.md`, the first input's description in `.github/ISSUE_TEMPLATE/01-bug.yml` | PR author; a maintainer commands the application |
| A label named by an issue form or `.github/dependabot.yml`                 | `.github/labels.yml` must declare it (`just validate` checks it)                                                                                                                                                                                                  | PR author                                        |
| The organization recreates the Priority field                              | its id in `github/platform-settings.md` and in the `github-project-workflow` skill                                                                                                                                                                                | Maintainer                                       |
| Issue form `spec` field or acceptance descriptions                         | `spec-workflow.md` "Specifications and issues"                                                                                                                                                                                                                    | PR author                                        |
| `github-project-workflow` Take work / Create issues / Finish               | `spec-workflow.md` and `agent-authority.md` must still agree                                                                                                                                                                                                      | PR author                                        |
| An action is added to or changed in a workflow or composite action         | pin it by full commit SHA with its version in a comment (`@<sha> # vX.Y.Z`); a third-party action is added to the allowed list in `github/platform-settings.md` by a maintainer first                                                                             | PR author; maintainer for the allowed list       |
| A tool pin in `.github/actions/setup-tools/action.yml`                     | run `just check` with that version; OpenSpec's permission flags stay identical to `.devcontainer/setup.sh`                                                                                                                                                        | PR author                                        |
| A file the test pipeline uses is added or moved (workflow, action, script) | `INFRA_PATHS` in `scripts/lib/repo.ts`                                                                                                                                                                                                                            | PR author                                        |
| The release tag format or namespace                                        | `git-workflow.md`, `scripts/tag_releases.ts`, `.github/workflows/release.yml`, `REPO` in `scripts/lib/repo.ts`                                                                                                                                                    | PR author                                        |
| The arch values a compatibility entry may name                             | `RUNNERS` in `scripts/lib/repo.ts` and the `arch` enum in `test/compatibility.schema.json`                                                                                                                                                                        | PR author                                        |

## Harness review

Run this review when `AGENTS.md` passes about 120 lines, after every tenth merged feature PR, or when an agent follows a
rule that turns out to be stale. Report findings as an issue (type Task) with keep / update / remove recommendations
before editing anything:

- Every path, command, and job name in `AGENTS.md` and `.agents/knowledge/` still exists and runs.
- Every knowledge file is reached from `AGENTS.md`, and no two files state the same rule.
- Pinned versions — `setup-tools` inputs, `jsr:` / `npm:` imports in `scripts/`, the feature schema URL in
  `scripts/validate.ts`, `REGISTRY_IMAGE` in `scripts/test_feature.ts`, the TruffleHog image in
  `.github/workflows/secret.yml` — are not far behind upstream.
- The canary set in `test/canary.json` is still small, fast, and representative.
- "Deliberately not used" triggers in this file: has any fired?
- `is:issue is:open no:label` is empty.
- No open Epic is left without an open sub-issue.
