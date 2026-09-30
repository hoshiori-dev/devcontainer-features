# Tasks

## 1. Rule text

- [x] 1.1 Replace the download paragraph in `.agents/knowledge/feature-authoring.md` ("install.sh") with the seven rules
      under the proposal's What Changes, and leave the other `install.sh` bullets unchanged; verify by reading the diff
      of that file, which touches only the download paragraph, and by checking each of the seven rules against the
      proposal
- [x] 1.2 Run `deno fmt --check` and confirm the Markdown formatting passes

## 2. Consistency

- [x] 2.1 Run
      `git grep -n -i -E "verify every download|curl \| ?sh|checksum|signature|fingerprint|pinned|verif" -- .agents ':!.agents/skills/openspec-*' AGENTS.md README.md openspec/config.yaml scripts/new_feature.ts .github`
      and read each hit; verify that none contradicts the new rules
- [x] 2.2 Run `git diff --name-only origin/main...HEAD` and verify it lists only
      `.agents/knowledge/feature-authoring.md` and files under `openspec/changes/relax-download-verification/`

## 3. Validation

- [x] 3.1 Run `just check` and verify it passes
- [x] 3.2 Record each Acceptance item and its result in the PR's Validation section
