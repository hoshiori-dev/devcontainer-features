# Tasks

## 1. Generated feature list

- [x] 1.1 Extend `scripts/docs.ts` to write the feature table between two marker comments in `README.md` (one row per
      feature that is not deprecated, sorted by id, linking `src/<id>/README.md`, description from the metadata) and to
      compare the region in `--check`; verify with unit tests for the table, the region replacement, and missing markers
- [x] 1.2 Make `--check` fail when the feature ids and links in `README.zh.md`'s region differ from the English region;
      verify with a unit test that a missing, extra, or relinked row is reported
- [x] 1.3 Update the `docs` and `docs-check` recipe comments in `justfile`; verify `just --list` shows them and
      `just scripts-check` passes

## 2. Root README

- [x] 2.1 Rewrite `README.md` (description, language link, badges, Usage with the index note, generated Features region,
      Principles and auditing with limits, Contributing, License); verify `just docs` fills the region with all 14
      features and each named measure traces to a rule or workflow
- [x] 2.2 Run every command of the audit steps against a published feature version and record the result for the PR's
      Validation section; verify the comparison reports no difference and the digest reference resolves
- [x] 2.3 Translate the finished `README.md` into `README.zh.md`, section for section, with the authoritative-file line
      and links between the two; verify `just docs-check` passes
- [x] 2.4 Verify the list cannot drift: remove a row, change a description, and remove a row from `README.zh.md`, and
      see `just docs-check` fail each time, then restore

## 3. Threat model and accepted risks in the knowledge base

- [x] 3.1 Replace the execution-risk list in `.agents/knowledge/review-guidance.md` with the threat model (roles, phases
      of shipped code, the risks the collection accepts, the finding rule, accepted risks in a feature's spec); verify
      every category the guidance asks for maps to a row of its table and it holds no example attacks
- [x] 3.2 Widen the accepted-risk rule in `.agents/knowledge/feature-authoring.md` and the `specs` rule in
      `openspec/config.yaml`; verify `just spec-check` reports every rule reaching OpenSpec
- [x] 3.3 Point step 5 of `.github/skills/code-review/SKILL.md` at the guidance's finding rule; verify the skill states
      no threat of its own

## 4. Human documents

- [x] 4.1 Add `CONTRIBUTING.md` (OpenSpec and where a spec lives, the supported coding agents and what each reads, the
      path from issue to release, the validation commands, the sentence for a coding agent); verify it links to no file
      under `.agents/knowledge/` and every rule it mentions has an owning knowledge file
- [x] 4.2 Rewrite `SECURITY.md` (reporting and supported versions unchanged in meaning, the threat model in plain
      language, the sentence for a coding agent); verify it links to no file under `.agents/knowledge/` and holds no
      rule table
- [x] 4.3 Update `AGENTS.md`: the generated region and `README.zh.md` among generated and synchronized files, the Core
      Conventions line on human documents, and the "Keep In Sync" rows; verify every knowledge file the two documents
      summarize is named in the row and no agent-facing file sends an agent to them for a rule

## 5. Integration

- [x] 5.1 Run `just check`; verify it passes and that no file under `src/`, `test/`, or `openspec/specs/` changed
- [ ] 5.2 Record each Acceptance item with its result in the PR's Validation section
