# Design

## Context

- Non-local action references today: `actions/checkout@v7` 14 times (`ci.yml` 8, `pr.yml` 3, `release.yml` 2,
  `secret.yml` 1); `denoland/setup-deno@<sha> # v2.0.5` in `.github/actions/setup-tools/action.yml`;
  `trufflesecurity/trufflehog@<sha> # v3.97.9` in `secret.yml`. The composite actions under `.github/actions/` use no
  other remote action.
- `actions/checkout` tag `v7` points to commit `3d3c42e5aac5ba805825da76410c181273ba90b1`, the same commit as `v7.0.1`
  (read from `gh api repos/actions/checkout/git/matching-refs/tags/v7` on 2026-09-30).
- GitHub documents that the pinning setting covers every action, GitHub-authored ones included, and that only reusable
  workflows may still be referenced by tag
  ([Managing GitHub Actions settings for a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)).
  It does not say whether local actions (`./…`) are exempt, or how it treats the workflows GitHub generates for CodeQL
  default setup and Dependabot.
- Dependabot updates actions referenced as `owner/repo@<commit>` and rewrites a version comment on the same line
  ([Keeping your actions up to date with Dependabot](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/keeping-your-actions-up-to-date-with-dependabot)).
  `.github/dependabot.yml` already covers `/` and `.github/actions/*` weekly.
- The `main` ruleset has no bypass actors, so a merge needs every required check green on the PR.

## Goals / Non-Goals

**Goals:**

- Pin to the commit the tag resolves to today, so behavior does not change; checked by comparing each SHA with
  `gh api repos/<owner>/<repo>/git/matching-refs/tags/<tag>`.
- Write every pin as `@<40-hex sha> # v<full version>`; checked by the `git grep` in the proposal's Acceptance.
- Never leave `main` in a state where its workflows cannot run; checked by turning the setting on only while the pinned
  workflows are green on this PR and by reading the first runs after it.

**Non-Goals:**

- A repository check that fails a PR adding a tag reference. The setting already fails such a run, and the failing run
  blocks the merge through the required checks.
- Pinning reusable workflows, Deno imports, or container images; they have their own pins or none are used.

## Decisions

- **Enforce while the PR is open, not after merge.** With the setting on, `pull_request` runs of this PR use its pinned
  workflow files and pass, while tag-referencing runs elsewhere fail. Turning it on before merge lets this PR prove the
  workflows pass under enforcement and record the tier in the same PR, as `git-workflow.md` asks. Rejected: turning it
  on after merge, which leaves a follow-up PR only to record the tier and verifies the setting only on `main`; turning
  it on before the pins exist, which fails every run including this PR's, with no bypass to recover.
- **Keep the explicit allowed-actions list.** Pinning freezes the code of an allowed action; the list decides which
  publishers may run at all, and adding one stays a maintainer action. Rejected: allowing all Marketplace verified
  creators, which widens trust to every partner organization and leaves review as the only gate for a new action.
- **Full version in the comment** (`# v7.0.1`, not `# v7`), so the comment names the release the SHA is and Dependabot
  has an exact version to update from.

## Risks / Trade-offs

- **Generated workflows may not comply.** CodeQL default setup and Dependabot runs are workflows GitHub writes; if the
  setting blocks them, code scanning or update PRs stop. Mitigation: after the setting is on, confirm a CodeQL analysis
  on this PR and the next Dependabot run succeed; if either fails, the maintainer turns the setting off and the row
  records why.
- **Local actions may be rejected.** If `./.github/actions/...` fails under the setting, the rerun on this PR shows it
  before merge; the maintainer turns the setting off and the change is revised.
- **A window where other branches fail.** Between turning the setting on and merging, any other branch's run with a tag
  reference fails; no other PR is open on 2026-09-30, and rebasing onto the merged `main` fixes one opened later.
