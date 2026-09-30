# Tasks

## 1. Platform settings

- [x] 1.1 In `.agents/knowledge/github/platform-settings.md`, set the tier of every applied row (merge methods, ruleset
      `main`, bypass actors, legacy branch protection, Actions, secret scanning, push protection, code scanning, private
      vulnerability reporting, Dependabot alerts) to "Enforced (2026-09-30)" and give each a Verify readback that works
      with a maintainer's token; verify by running every `gh api` readback in the table and comparing it with the
      intended state
- [x] 1.2 Record the ruleset parameters GitHub adds on its own (additional approval for unattributed Copilot pull
      requests, all three merge methods allowed by the ruleset), rewrite the token note under the header, and update the
      "Last verified" line; verify by reading `gh api repos/hoshiori-dev/devcontainer-features/rulesets/24225927`
      against the text

## 2. Enforcement register and checks

- [x] 2.1 In `.agents/knowledge/git-workflow.md`, mark the `main` branch row, the merge-method enforcement note, and the
      first three rows of the enforcement register as enforced on 2026-09-30; in `.agents/knowledge/github/checks.md`,
      state that the `main` ruleset requires the five checks; verify with
      `git grep -n -i -E "not yet|yet to apply|until the .main. ruleset|once the .main. ruleset" -- .agents` finding
      nothing about the ruleset or merge settings

## 3. Integration

- [x] 3.1 Run `just check`, mark the PR ready, confirm GitHub reports it blocked while `spec-archived` is red, and
      record each Acceptance item of proposal.md with its result in the PR's Validation section
