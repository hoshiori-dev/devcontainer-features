<!--
The title is the squash commit title: `<type>(<scope>): <subject>`, scope = the feature id.
Never add AI or tool attribution anywhere in this pull request.
-->

## What and why

<!-- The outcome this PR makes true once merged, and why it matters. Not the diff. -->

## Changes

<!-- Filled in when the PR is marked ready: where and what, briefly — permalinks to the commits. -->

_Reserved: filled in when the pull request is marked ready._

## Related work

<!-- Closes #N — the closing keyword drives the issue lifecycle. -->

- Spec: [openspec/changes/NAME/](link to the change on this branch) — or "none" and why (Dependabot bump, typo)
- Phase: specification
- Records: proposal.md, specs/FEATURE/spec.md, design.md when warranted; tasks.md follows approval
- Approval: package deliberation open on this draft — a maintainer reviews the package here and closes it in
  conversation; tasks and the implementation follow the reconciled package

## Validation

<!-- Filled in when the PR is marked ready: each scenario of the change and its result, and the CI run. -->

_Reserved: filled in when the pull request is marked ready._

## Checklist

- [ ] `just check` passes locally
- [ ] Acceptance criteria of the linked issue, or the scenarios of the linked change record, are met
- [ ] The package deliberation was closed in conversation before the task list, and the implementation deliberation
      before the archive, or this PR has no OpenSpec change
- [ ] Every task of the change record is done and verified, or the specification is updated — the change is archived
      only on a maintainer's command, and `spec-archived` stays red until it is
- [ ] Every changed feature's `version` is bumped and its README regenerated with `just docs`
- [ ] No secrets, credentials, or personal data in the diff, description, or commits
