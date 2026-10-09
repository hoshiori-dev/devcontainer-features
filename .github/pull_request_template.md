<!--
The title is the squash commit title: `<type>(<scope>): <subject>`, scope = the feature id, or for a harness change
the area (`ci`, `scripts`, `spec-workflow`, `harness`); omit the scope for a repository-wide change.
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
- Approval: `spec:approved` on this pull request is the package approval, kept by the PR labels workflow while the
  package is unchanged; noted here: each reconciliation of the threads before acting on it, and the archive command

## Validation

<!-- Filled in when the PR is marked ready: each Acceptance item and scenario of the change and its result, and the CI run. -->

_Reserved: filled in when the pull request is marked ready._

## Checklist

- [ ] `just check` passes locally
- [ ] The Acceptance of the linked change's proposal, with the scenarios it points to, is met, or this PR has no
      OpenSpec change
- [ ] This PR carried `spec:approved`, read with `just pr-labels`, before the task list, or it has no OpenSpec change
- [ ] Every task of the change record is done and verified, or the specification is updated — the change is archived
      only on a maintainer's command, and `spec-archived` blocks the merge until it is
- [ ] Every changed feature's `version` is bumped and its README regenerated with `just docs`
- [ ] No secrets, credentials, or personal data in the diff, description, or commits
