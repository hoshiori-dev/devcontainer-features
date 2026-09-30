# Tasks

## 1. Rules check

- [x] 1.1 Export a pure function from `scripts/check_openspec.ts` that takes the parsed `config.yaml` value and returns
      a problem for each case in the design's Context (`rules` not a mapping; a `rules.<artifact>` value not a list; an
      entry not a string; an empty-string entry), each naming `rules.<artifact>`, the 1-based entry number, and the YAML
      type found, with the quoting hint; add unit tests in `scripts/checks_test.ts` for each case and for a valid rules
      block and a config without `rules`; verify `just scripts-check` passes
- [x] 1.2 In the main block of `scripts/check_openspec.ts`, read and parse `openspec/config.yaml` with `npm:yaml@2.9.1`,
      report a read or parse error as a problem, run the rules check before the `openspec init` comparison, and report
      both; update the script's header comment and the `spec-check` recipe comment in `justfile`; verify
      `just spec-check` passes on the current `config.yaml`, and that in a local copy with an unquoted rule containing a
      colon followed by a space under `rules.specs` it exits non-zero naming `rules.specs` and the entry while the
      generated-files result still prints

## 2. Knowledge base

- [x] 2.1 State that `just spec-check` also checks `config.yaml`'s rules in `.agents/knowledge/spec-workflow.md`
      (Artifact operations) and in the `spec` row of `.agents/knowledge/github/checks.md`; verify `just lint` passes

## 3. Integration

- [x] 3.1 Run `just check`, push, and confirm every required check passes on this PR; record each Acceptance item of
      proposal.md with its result in the PR's Validation section
