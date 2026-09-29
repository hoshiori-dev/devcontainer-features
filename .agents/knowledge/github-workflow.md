# GitHub Workflow

Read this before creating a branch, opening or updating an issue or pull request, applying labels, creating a milestone,
or proposing any new management structure. GitHub is this repository's only remote and task-management platform, so
every rule here is written in GitHub terms.

`hoshiori-dev/devcontainer-features` (organization-owned, public). Maintainers are the repository collaborators with
write access (`gh api repos/hoshiori-dev/devcontainer-features/collaborators`). The organization provides native issue
types (Task / Bug / Feature); the default token cannot read them through the API, so verify them in the UI.

## What this repository is

A collection of Dev Container Features, each developed in `src/<id>/` and published independently to
`ghcr.io/hoshiori-dev/devcontainer-features/<id>` with its own semantic version. Consumers pin a floating major tag
(`:1`), so a merged change that bumps a feature's version reaches every consumer on their next container build without
any action on their side. Acceptance therefore has to be complete before merge, and a bad release is rolled back by
publishing a higher fixed version — a published version cannot be withdrawn from the floating tags.

## Objects in use

| Object                             | Meaning here                                                                                                                                                                   | What is lost without it                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| Issue                              | One independently acceptable outcome: a new feature, a behavior change to one feature, a defect, or a harness task. Typed with the native issue type.                          | The record of why a change exists and who asked for it; PRs would have nothing to close. |
| Pull request                       | Every change to `main`. A draft PR is work in progress — including a draft whose first content is an OpenSpec change awaiting approval — never a placeholder for planned work. | Review, CI feedback, and the single place where acceptance happens.                      |
| Acceptance                         | The required check `ci-gate` passes, the PR's OpenSpec scenarios are verified (see `spec-workflow.md`), and a maintainer merges.                                               | Merge would equal an unchecked release to every consumer.                                |
| Issue types (Task / Bug / Feature) | The kind of work, set by the issue form.                                                                                                                                       | Filtering defects from new work.                                                         |
| Tag `<id>/v<version>`              | Marks the commit a published feature version was built from; created by the release workflow, never by hand (see `git-workflow.md`).                                           | Mapping a GHCR version back to the commit it was built from.                             |
| GHCR package version               | The delivery: what consumers actually install.                                                                                                                                 | — (it is the product).                                                                   |

## Deliberately not used

| Object                                          | Enable when                                                                                                                     |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Milestones                                      | A theme spans several PRs across features and needs a completion view (e.g. "add a language toolchain family").                 |
| GitHub Projects                                 | Three or more people work in parallel and filtered issue lists stop being enough.                                               |
| Priority (org `Priority` issue field or labels) | The open backlog passes about 20 issues, or more than one person picks work from it and order starts to matter.                 |
| Sub-issues                                      | One issue holds parts that each need their own PR and acceptance, and splitting into separate issues loses the shared goal.     |
| Labels beyond GitHub's defaults                 | Filtering by feature or area becomes a routine need; until then the feature id lives in the issue title and the PR title scope. |
| GitHub Releases                                 | Consumers need release notes beyond each feature's generated README; the tag and GHCR version are the release record today.     |
| Discussions                                     | Outside users start asking questions that are not actionable issues.                                                            |

## Decomposition

Create a separate issue only when the piece independently earns its own discussion and acceptance. In practice that is
one issue per feature change: "add feature `foo`", "`foo`: support Alpine", "`foo`: install fails on arm64". Steps
inside that outcome — writing the test scenarios, the compatibility list, the docs — are tasks in the OpenSpec change's
`tasks.md`, not issues. A change that touches a feature and, through `dependsOn`, forces a version bump in its
dependents is still one issue.

## Triage

A maintainer reads new issues as they arrive. An issue leaves triage when it has a type and enough detail to act on
(feature id, image, reproduction for a bug). No automation applies labels.

## Planning view

Filtered issue and PR lists (`is:open type:Bug`, `is:pr is:draft`). Any view is rebuildable; the facts live on issues,
PRs, and the OpenSpec specs.

## Agent authority

Governed by `.agents/knowledge/agent-authority.md`.

## Other contracts

- Branches, merge method, and tags: `.agents/knowledge/git-workflow.md`.
- Specifications, their approval, and archiving: `.agents/knowledge/spec-workflow.md` — a PR's acceptance is the
  scenarios of the OpenSpec change it implements.

## Update this file when

- A second regular contributor joins, or outside contributions start arriving.
- A "not used" trigger fires.
- An object in use goes unused for a sustained period — remove it, do not let it rot.
- How features reach consumers changes (a new registry, a second namespace, pinned-digest consumers).
- GitHub changes what organization-owned public repositories get natively.

## Specifications

The OpenSpec contract lives in `.agents/knowledge/spec-workflow.md`. Because of it:

- the PR template carries the specification block under `## Related work` (`Spec:`, `Phase:`, `Records:`, `Approval:`)
  and checklist items for the two conversational gates and the archive;
- the Feature request and Task forms carry an optional `Specification` field, and their acceptance fields defer to the
  change's scenarios;
- the `github-project-workflow` skill's Take work, Create issues, and Finish steps apply the gates, the reconciliation,
  and the archive-on-command rule;
- the `spec-archived` check (workflow PR, `scripts/check_spec_archived.ts`) fails a ready PR that still holds an
  unarchived change and warns on a draft. No other OpenSpec automation exists: no comment commands, no status labels, no
  archiving job.

A ready PR needs `Phase: implementation`, a `Spec:` line, no reserved line left in Changes or Validation, and every
checklist item ticked except the one `spec-archived` tracks. When the OpenSpec layout or version changes, re-check every
template link and path above.

## Synchronization

| When this changes                                                          | Update in the same PR                                                                                               | Owner                                 |
| -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ------------------------------------- |
| A CI or PR job is renamed or added                                         | `github/checks.md` job map; the `main` ruleset's required checks (maintainer, `github/platform-settings.md`)        | PR author; maintainer for the ruleset |
| A `just` recipe CI calls                                                   | the job that calls it and the `github/checks.md` map                                                                | PR author                             |
| PR template `##` headings or the security item                             | nothing else — `scripts/check_pr_body.ts` reads the template; keep the word "secrets" in the security item          | PR author                             |
| PR template specification block or checklist items                         | `spec-workflow.md` if a gate or the archive rule changed, else revert the template                                  | PR author                             |
| Issue form `type:` values                                                  | organization issue types row in `github/platform-settings.md`                                                       | Maintainer                            |
| Issue form `spec` field or acceptance descriptions                         | `spec-workflow.md` "Specifications and issues"                                                                      | PR author                             |
| `github-project-workflow` Take work / Create issues / Finish               | `spec-workflow.md` and `agent-authority.md` must still agree                                                        | PR author                             |
| A tool pin in `.github/actions/setup-tools/action.yml`                     | run `just check` with that version; OpenSpec's permission flags stay identical to `.devcontainer/setup.sh`          | PR author                             |
| A file the test pipeline uses is added or moved (workflow, action, script) | `INFRA_PATHS` in `scripts/lib/repo.ts`                                                                              | PR author                             |
| The release tag format or namespace                                        | `git-workflow.md`, `scripts/tag_releases.ts`, `.github/workflows/release.yml`, `NAMESPACE` in `scripts/lib/repo.ts` | PR author                             |
| The arch values a compatibility entry may name                             | `RUNNERS` in `scripts/lib/repo.ts` and the `arch` enum in `test/compatibility.schema.json`                          | PR author                             |

## Harness review

Run this review when `AGENTS.md` passes about 120 lines, after every tenth merged feature PR, or when an agent follows a
rule that turns out to be stale. Report findings as an issue (type Task) with keep / update / remove recommendations
before editing anything:

- Every path, command, and job name in `AGENTS.md` and `.agents/knowledge/` still exists and runs.
- Every knowledge file is reached from `AGENTS.md`, and no two files state the same rule.
- Pinned versions — `setup-tools` inputs, `jsr:` / `npm:` imports in `scripts/`, the feature schema URL in
  `scripts/validate.ts`, `REGISTRY_IMAGE` in `scripts/test_feature.ts` — are not far behind upstream.
- The canary set in `test/canary.json` is still small, fast, and representative.
- "Deliberately not used" triggers in this file: has any fired?
