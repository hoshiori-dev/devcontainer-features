# Proposal

Implements [#129](https://github.com/hoshiori-dev/devcontainer-features/issues/129).

## Why

`.devcontainer/setup.sh` installs the latest OpenSpec release and CI installs 1.13.2, so the two run different checks:
with 1.14.1, the release a dev container built on 2026-10-08 gets, `just check` fails at `spec-check` on an unchanged
`main` while CI's `spec` job passes. Nothing in the failure names the version as its cause, and once the versions are
tied together nothing would say that the pin has fallen behind: OpenSpec published five releases to npm between
2026-09-09 and 2026-10-05 (UTC).

## What Changes

- **One version.** The dev container installs the OpenSpec version CI installs, with the same options. The install
  command is written in `.github/actions/setup-tools/action.yml` and in `.devcontainer/setup.sh`, and `just check` fails
  when the two differ or when either carries an option the check does not know.
- **Installed version.** `just spec-check` fails before it validates anything when the `openspec` it would run is not
  the pinned version. The failure names both versions and the command that installs the pinned one, so a dev container
  built before this change, or one whose OpenSpec was upgraded by hand, gets one message to act on.
- **Newer release.** Outside CI, a `just check` or `just spec-check` whose checks all pass ends by asking the npm
  registry for the latest OpenSpec release. When it is newer than the pin, the last thing the recipe prints is a notice
  with both versions that tells an agent to ask the maintainer whether to raise the pin. The notice never changes the
  result, and a lookup that fails or times out prints one line and changes nothing either. A failing run ends with its
  own failure and does not look, and neither does CI.
- **Who raises the pin.** A maintainer decides, when they want to. An agent that sees the notice reports it and asks; it
  does not edit the pin, in either file, without that answer. `github/checks.md` (Toolchain pins) holds this rule and
  the steps raising the pin takes.
- **Knowledge base.** `github/checks.md` describes the above instead of a dev container at `@latest`, in Toolchain pins
  and in the `spec` row of its job map; `spec-workflow.md` and the Synchronization row for a tool pin in
  `github-workflow.md` point to it; and the header of `setup-tools/action.yml` no longer says the dev container installs
  its own version.

## Capabilities

### New Capabilities

None. This change edits the harness only (`skip_specs: true`).

### Modified Capabilities

None.

## Impact

- Files: `.devcontainer/setup.sh` (the OpenSpec install line); the comments of `.github/actions/setup-tools/action.yml`;
  a new Deno script with its tests; the `check` and `spec-check` recipes of the `justfile` with their comments;
  `.agents/knowledge/github/checks.md` (Toolchain pins and the job map), `.agents/knowledge/spec-workflow.md`, and
  `.agents/knowledge/github-workflow.md` (the Synchronization row for a tool pin).
- Files checked and left alone: `AGENTS.md` (its Keep In Sync row for an OpenSpec upgrade already sends the reader to
  `spec-workflow.md`, no recipe is added or renamed, and its Validation row lists what `just check` covers, not an
  order), `agent-authority.md`, `CONTRIBUTING.md` (its sentence that the dev container has the tools CI uses becomes
  true for OpenSpec, and its list of what `just check` covers is not an order), `review-guidance.md` (the registry's
  answer is compared and printed, never executed), `SECURITY.md`, `scripts/lib/repo.ts` (`INFRA_PATHS`: the new script
  is no part of the feature-test pipeline), `.github/workflows/ci.yml` (the `spec` job already calls `just spec-check`,
  and no workflow runs `just check`), and the Harness review list of `github-workflow.md` (it still asks whether pins
  are far behind upstream; the review reports, the maintainer decides).
- Feature ids touched: none, so no version bump. No file under `src/`, `test/`, or `openspec/specs/` changes.
- `.devcontainer/` changes only after asking a maintainer (`AGENTS.md`). The maintainer gave the direction of #129 in
  conversation on 2026-10-08; it covers the one install line and nothing else in that folder, and the approval of this
  package confirms it.
- #71, which proposed installing the dev container's tools at the versions CI pins, among other hardening of the
  installers and the pre-commit hooks, was closed as not planned on 2026-10-05. This change takes up its OpenSpec part
  alone. The Deno and devcontainer CLI installers, the pre-commit hook pins, and OpenSpec's telemetry setting in the dev
  container stay as they are.
- `.github/actions/` is test infrastructure (`INFRA_PATHS` in `scripts/lib/repo.ts`), so editing the action's comments
  makes CI run the canary features and the global scenarios on this pull request. The action installs the same tools at
  the same versions as before.
- The pinned version stays 1.13.2. Raising it is a separate decision, and the first notice this change prints will name
  1.14.1 or a later release.
- A new outbound request: the check reads one public document from `registry.npmjs.org`, the host Deno already downloads
  the scripts' pinned `npm:` imports from. It sends nothing but the request, and it runs only outside CI.
- An existing dev container keeps the OpenSpec it has until its user reinstalls or rebuilds; from the merge on,
  `just spec-check` fails there with the command to run.
- Rebuilding a dev container from this branch is left to the maintainer during review: an agent cannot rebuild the
  container it runs in. The Validation section of the pull request says so.

## Acceptance

**Becomes true:**

- `.devcontainer/setup.sh` installs `npm:@fission-ai/openspec` at the version, and with the options,
  `.github/actions/setup-tools/action.yml` installs it with, and `@latest` appears in neither.
- `just check` fails when the two files name different OpenSpec versions or different options of the install command,
  when either names no version of the form `N.N.N`, when either holds the install more than once, and when either gives
  the install an option the check does not know. A unit test covers each case.
- `just spec-check` fails, before OpenSpec validates anything, when the installed `openspec` reports another version
  than the pin; the message holds the installed version, the pinned version, and the command that installs the pinned
  one. A unit test covers the mismatch, and one covers an `openspec` that is missing.
- Outside CI, when every check passes and the registry answer is newer than the pin, the last output of
  `just spec-check` and of `just check` is a notice holding both versions and the instruction to ask the maintainer, and
  the exit status is 0. A unit test covers a newer, an equal, and an older answer, and one run outside CI shows the
  notice as the last output.
- A registry lookup that fails, times out, is redirected, or returns something that is not a version prints one line
  that says it was skipped and changes neither the exit status nor any other check. A unit test covers each.
- A run of `just spec-check` or `just check` in which a check fails prints neither the notice nor the line of a skipped
  lookup.
- In CI the check makes no request to the registry. A unit test covers it.
- The OpenSpec install line of `.devcontainer/setup.sh`, run with a temporary install root, produces an `openspec` that
  prints the pinned version; and in a dev container that has the pinned version, `just check` passes.
- `github/checks.md` says that a maintainer decides when the pin is raised, that an agent asks and does not raise it
  alone, and what raising it takes; it no longer says the dev container installs OpenSpec at `@latest`; and its `spec`
  row names the version check. `spec-workflow.md` names the version check among what `just spec-check` fails on and
  points to that rule, as does the tool pin row of `github-workflow.md`; and the header of
  `.github/actions/setup-tools/action.yml` no longer says the dev container installs its own version.

**Stays true:**

- CI installs OpenSpec 1.13.2 with the permission flags it has today, and the `spec` job runs `just spec-check`.
- `just spec-check` still runs OpenSpec's strict validation and `scripts/check_openspec.ts`, with the results they give
  today for the same OpenSpec version.
- No required check can fail because OpenSpec published a release.
- `just scripts-check` runs with the permissions it has today.
- `OPENSPEC_NO_UPDATE_CHECK` stays set in the dev container, and OpenSpec itself is still allowed no host but
  `edge.openspec.dev`.
- Nothing else in `.devcontainer/` changes, and `.pre-commit-config.yaml` and `.editorconfig` do not change.
- No workflow gains a permission, a trigger, or a step.
- No file under `src/`, `test/`, or `openspec/specs/` changes, and `just check` passes.
