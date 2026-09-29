# Git Branching Contract

Read this before creating a branch, opening a pull request, merging, or creating a tag.

Model: GitHub Flow. Selected because every feature has exactly one published line — GHCR floating tags (`:1`, `:1.2`)
only move forward — and there is no deployment chain, so `main` is the only long-lived branch.

## Long-lived branches

| Branch | Meaning                                                                                             | Accepts merges from | Protection tier                                                                                                  |
| ------ | --------------------------------------------------------------------------------------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `main` | Every commit is releasable: pushing a commit that bumps a feature's version publishes that version. | Pull requests only  | Convention until the `main` ruleset in `.agents/knowledge/github/platform-settings.md` is applied, then enforced |

Do not create any other long-lived branch (`develop`, `next`, per-feature lines). Needing one means the model changed,
which is a maintainer decision recorded here first.

## Short-lived branches

- With an issue: `gh issue develop -c <number>` creates and checks out the branch; take the generated name
  (`<number>-<title-slug>`) as is.
- Without an issue (rare: bootstrap or emergency harness fixes): `<type>/<short-description>`, where `<type>` is a
  Conventional Commits type, e.g. `chore/harness-bootstrap`.
- Cut from the current `main`; merged into `main`; deleted on merge (repository setting, see
  `github/platform-settings.md`).
- A branch must finish its outcome before merge. There is no shipping dark here: a merged version bump is published
  immediately, and a new feature is published as soon as it lands. Keep unfinished work in a draft PR.
- Keep the branch current with `main` by merging or rebasing `main` into it; the ruleset requires an up-to-date branch
  before merge, so the PR's test run covers what will actually land.

## Tags and versions

- Format: `<feature-id>/v<MAJOR>.<MINOR>.<PATCH>`, e.g. `node/v1.4.0`. Version scheme: SemVer, one independent version
  per feature, read from `src/<id>/devcontainer-feature.json`.
- Created only by the release workflow on `main`, after the version is published to GHCR. Never create, move, or delete
  one by hand.
- No other tags exist; the repository as a whole has no version.

## Merge method

| Contribution origin         | Method | Why                                                                                                                     |
| --------------------------- | ------ | ----------------------------------------------------------------------------------------------------------------------- |
| Branch in this repository   | Squash | One reviewed unit per change on `main`; the PR title becomes the commit title, so history reads as the list of changes. |
| Fork or outside contributor | Squash | Same; the contributor's own commits do not need to follow the title convention.                                         |

Enforcement: only squash merge is enabled (repository setting). The squash commit title is the PR title and must follow
Conventional Commits: `<type>(<scope>)[!]: <subject>`.

- `<scope>` is the feature id for a change to one feature (`feat(node): add pnpm option`); for a harness change use the
  area (`ci`, `scripts`, `openspec`, `harness`); omit it for repository-wide changes.
- `!` marks a breaking change and goes with a major version bump of that feature.
- Human contributors keep their `Co-authored-by` trailers in the squash message. Never add AI or tool attribution to
  commits, PR titles, or PR bodies — see `agent-authority.md`.

## Hotfix path

1. Branch from the current `main` (`gh issue develop -c <bug-issue>`).
2. Fix, bump the feature's PATCH version, open the PR; CI tests the affected features.
3. Squash-merge into `main`; the release workflow publishes the new version and tags it.

Recovery is always roll-forward: publish a higher fixed version. A published version cannot be withdrawn from the
floating tags consumers use.

## Enforcement register

| Rule                                                                                             | Tier                                  | Readback                                                                                                                                   | Upgrade trigger                                                              |
| ------------------------------------------------------------------------------------------------ | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------- |
| Changes reach `main` only through PRs; no force push or deletion                                 | Convention (ruleset not yet applied)  | `gh api repos/hoshiori-dev/devcontainer-features/rulesets`                                                                                 | A maintainer applies the `main` ruleset                                      |
| `ci-gate`, `pr-title`, `pr-checklist`, `spec-archived` pass on an up-to-date branch before merge | Convention (ruleset not yet applied)  | same                                                                                                                                       | same                                                                         |
| Squash only; branch deleted on merge                                                             | Convention (settings not yet changed) | `gh api repos/hoshiori-dev/devcontainer-features --jq '{allow_squash_merge,allow_merge_commit,allow_rebase_merge,delete_branch_on_merge}'` | A maintainer changes the merge settings                                      |
| PR title follows Conventional Commits                                                            | Check `pr-title`                      | the PR's checks                                                                                                                            | —                                                                            |
| Tags created only by the release workflow                                                        | Convention                            | `git ls-remote --tags origin` against the release workflow's runs                                                                          | A hand-made tag appears — then add a tag ruleset restricting `*/v*` creation |

When a maintainer applies a setting, change its tier here to "Enforced" in the same PR.

## Update this file when

- A long-lived branch is proposed or the model changes.
- The repository's protection, ruleset, or merge-method settings change.
- The release workflow's trigger branch or tag format changes; `.github/workflows/release.yml` and this file must name
  the same branch and tag format.
