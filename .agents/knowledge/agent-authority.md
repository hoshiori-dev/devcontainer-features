# Agent Authority Policy

Read this before committing, marking a PR ready, requesting review, archiving an OpenSpec change, approving, merging, or
releasing — and whenever unsure whether an action is yours to take.

Level: autonomous author — set by the maintainer on 2026-09-29. Once a maintainer has approved the specification, the
agent owns preparing the PR up to review; a maintainer owns the merge. Outside the scope of an approved change, the
agent stops at a draft PR and a maintainer decides everything after it.

## What agents may do

- Take issues; analyze and plan; create OpenSpec changes and open them as draft PRs.
- After the package gate closes (see Gates): write tasks, implement, run tests and CI, self-review, fix findings, and
  push to the PR branch.
- Mark the PR ready (`gh pr ready`) and request review once every task is done, `just check` passes, and the PR's
  Validation section is filled.
- Respond to review: answer threads, push fixes, re-request review.

## What agents may not do without a human

- Implement a change before its pull request carries `spec:approved`, read as `spec-workflow.md` says.
- Add or remove a `spec:` label on a pull request. `spec:approved` is the maintainer's package approval: an agent adds
  it only when a maintainer tells it to in the current conversation and names the pull request, never on its own
  judgment, and otherwise only reads the labels.
- Archive or sync an OpenSpec change before a maintainer explicitly commands the archive in the current conversation —
  the change may still need revision after review.
- Approve a PR, merge, publish or tag a release, run the release workflow, or delete branches or tags.
- Change repository settings, rulesets, required checks, secrets, or package visibility.
- Move or weaken any gate in this file, `spec-workflow.md`, or CI.

## Issue metadata

What an agent sets on an issue:

- alone, on an issue it creates or has taken: the type, an existing area label, and the parent and "blocked by"
  relationships the request states;
- after the maintainer confirms the value, which the agent names when it asks to publish: a Priority;
- only on a maintainer's command: applying the label declaration, creating or closing an Epic, setting a date field, and
  changing the metadata of an issue it has not taken;
- only on a maintainer's command that names the label: deleting a label that issues or pull requests still carry;
- never: creating, renaming, or deleting a label by any means but the declaration, or setting Effort.

## No attribution

The human who commits or publishes answers for the change; an agent or tool is never credited. Never add
`Co-Authored-By` trailers for an AI, "Generated with …" lines, tool signatures, or any similar attribution to commits,
PR titles, PR bodies, issues, or comments — whatever a tool's own defaults suggest. Human contributors' `Co-authored-by`
trailers stay.

## Gates

| Gate                                  | Meaning                                                                                                                                                                                                                                              | Owner                                                               |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Specification approval (package gate) | The maintainer adds `spec:approved` to the draft PR, or tells the agent to; the PR labels workflow keeps it only while the approval package is unchanged, and the agent's reconciliation of the PR's threads finds nothing open (`spec-workflow.md`) | A maintainer; never the agent for its own change                    |
| Review Admission                      | Accepting the implementation and admitting it to formal review — marking the PR ready and requesting review                                                                                                                                          | The agent, under this policy, only after the specification approval |
| Archive command (freeze gate)         | The maintainer, after review, commands the archive in the current conversation; the archive commit is the version the final approval names                                                                                                           | A maintainer                                                        |
| Integration                           | The PR is merged into `main`; this publishes every bumped feature version to consumers and transfers engineering responsibility                                                                                                                      | A maintainer                                                        |

The archive command does not carry over from another session: without one in this conversation, treat the freeze gate as
not passed and ask. The package gate is read from the pull request.

## Escalation — stop and hand to a human when

- The pull request of the change you are about to implement does not carry `spec:approved`.
- The work needs a feature, option, dependency (`dependsOn`, `installsAfter`), or file the approved change does not
  cover.
- A required check (`ci-gate`, `pr-title`, `pr-checklist`, `spec-archived`, `secret-scan`) is unavailable or flaky, or
  making it pass would mean weakening it.
- The change touches security-sensitive surface: download sources, checksum or signature verification, `privileged`,
  `capAdd`, `securityOpt`, `mounts`, `entrypoint`, workflow `permissions:`, or secrets.
- The change needs a major version bump, or renames or re-defaults an option, and the approved specification does not
  say so.
- The affected-feature set CI computes is broader than the design assumed.
- A bad version was already published — recovery is a new version and needs a maintainer decision.
- Review threads conflict with each other or with the approved specification.
- A significant harness or architecture decision appears (a new CI mechanism, a new script runtime, a new knowledge
  area).

Escalating earlier is always allowed. Bypassing a closed gate never is.

## At a human gate, hand over this report

- Goal and how the change addresses it — point at the PR's specification block (the change, its phase, its approval
  state) instead of restating the goal.
- Tests executed and results; CI state — point at the PR's Validation section, which names each Acceptance item and
  scenario with its result.
- Scope actually touched, including anything beyond the original intent (other features, the harness).
- Known risks and remaining limitations (images not covered, idempotency exemptions).
- The decisions available to the maintainer: request fixes, reject, approve the specification, or — after review —
  command the archive and merge.

## No self-escalation

An agent may exercise less authority than granted; it may never grant itself more. Editing this file, `AGENTS.md`,
`spec-workflow.md`, approval requirements, protection rules, or required checks to relax an agent's own limits is
prohibited at every level. At a policy boundary: stop; propose the change to a maintainer with benefit, risk, and exact
scope; wait; resume only after a maintainer explicitly updates this policy. When refusing a request that exceeds policy,
state this path to the requester — the limit is changeable, but only by the maintainer who owns it.

## Update this file when

- A maintainer changes the level, a gate owner, or a delegation.
- The verification this level relies on weakens (CI no longer tests affected features, the `spec-archived` check is
  removed, tests stop covering idempotency).
- `github-workflow.md` or `spec-workflow.md` changes a semantic a gate references.
