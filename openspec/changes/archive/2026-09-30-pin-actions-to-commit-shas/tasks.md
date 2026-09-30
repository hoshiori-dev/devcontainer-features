# Tasks

## 1. Pins

- [x] 1.1 Replace every `actions/checkout@v7` in `.github/workflows/ci.yml`, `pr.yml`, `release.yml`, and `secret.yml`
      with `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`; verify the SHA against
      `gh api repos/actions/checkout/git/matching-refs/tags/v7` and that `git grep -n -E "uses: [^.][^@]*@" -- .github`
      lists only 40-character SHAs followed by a `# v…` comment

## 2. Knowledge base

- [x] 2.1 In `.agents/knowledge/github/platform-settings.md`, add SHA pinning to the Actions row's intended state with
      the readback `gh api repos/hoshiori-dev/devcontainer-features/actions/permissions --jq .sha_pinning_required`, and
      set its tier to "Enforced (2026-09-30)"; verify by running the readback
- [x] 2.2 In `.agents/knowledge/github/checks.md`, state in the toolchain pins note and in Rules that every action,
      `actions/*` included, is pinned by full commit SHA with its version in a comment and that the repository setting
      enforces it; in the Synchronization table of `.agents/knowledge/github-workflow.md`, add the row for adding or
      changing an action; verify with `git grep -n -i "major tag\|outside .actions/\*." -- .agents` finding no line
      about actions

## 3. Integration

- [x] 3.1 Run `just check`, push, and confirm the CI, PR, and Secret Scanning workflows and the CodeQL analysis pass on
      this PR with the setting on; record each Acceptance item of proposal.md with its result in the PR's Validation
      section
