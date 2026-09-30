# Proposal

Implements [#9](https://github.com/hoshiori-dev/devcontainer-features/issues/9).

## Why

A tag such as `actions/checkout@v7` can be moved to other code at any time; only a full-length commit SHA names
immutable code. The two third-party actions are already pinned by SHA, but `actions/checkout` is referenced by major tag
in all four workflows, and nothing stops a later edit from adding a tag reference again. A maintainer decided on
2026-09-30 to require SHA pins for every action and to let the repository setting enforce it, while keeping the explicit
allowed-actions list.

## What Changes

- Every non-local `uses:` under `.github/` names a full-length commit SHA with the version on the same line as a comment
  (`@<sha> # vX.Y.Z`), so Dependabot's weekly GitHub Actions updates keep both current.
- The Actions row of `.agents/knowledge/github/platform-settings.md` adds "every action pinned to a full-length commit
  SHA" (`sha_pinning_required`) to its intended state, with its readback; the allowed-actions list is unchanged.
- The pinning rule is stated where a workflow author reads it: the toolchain pins note in
  `.agents/knowledge/github/checks.md` and the Synchronization table of `.agents/knowledge/github-workflow.md` (a new
  action is pinned by SHA and, if third-party, added to the allowed list by a maintainer first).
- The setting is on and recorded as enforced before this change merges: a maintainer turns it on once this PR's pinned
  workflows are green, and the reruns on this PR show every workflow passing under it.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `.github/workflows/ci.yml`, `pr.yml`, `release.yml`, `secret.yml`;
  `.agents/knowledge/github/platform-settings.md`, `.agents/knowledge/github/checks.md`,
  `.agents/knowledge/github-workflow.md`.
- Feature ids touched: none, so no version bump. `ci.yml` is test infrastructure, so CI selects the canary set, which is
  empty while no feature exists.
- Remote settings: a maintainer turns `sha_pinning_required` on while this PR is open; until it merges, a workflow run
  from any other branch that still uses a tag fails (no other PR is open today).

## Acceptance

**Becomes true:**

- `git grep -n -E "uses: [^.][^@]*@" -- .github` lists only references whose ref is a 40-character commit SHA followed
  by a `# v…` comment.
- `platform-settings.md` states SHA pinning in the Actions row's intended state with the readback
  `gh api repos/hoshiori-dev/devcontainer-features/actions/permissions --jq .sha_pinning_required`.
- With the setting on, that readback returns `true`, the CI, PR, and Secret Scanning workflows rerun on this PR pass,
  and the Actions row reads "Enforced" with the date.

**Stays true:**

- The allowed-actions list stays GitHub-owned actions plus `denoland/setup-deno` and `trufflesecurity/trufflehog`.
- Each pinned action runs the same release it ran before (`actions/checkout` v7), so no job's behavior changes.
- Local actions (`./.github/actions/...`) keep their path references.
- `just check` passes, and every required check passes on this PR.
