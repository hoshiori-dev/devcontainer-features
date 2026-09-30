# Tasks

## 1. Option requirement parser

- [x] 1.1 Add `scripts/lib/options.ts` with pure functions that read every `### Requirement: Option <name>` block of a
      spec's text (its `Type`, `Default`, and optional `Enum` rows, per the design's value encoding) and compare the
      result with a feature's `options` metadata; each problem names the option, the field, and both values; add
      `scripts/lib/options_test.ts` covering a valid block, each malformed case (missing row, unknown type, value not
      JSON, default of the wrong type, `Enum` on a boolean or without the default, escaped `|`), and each difference
      (default, type, `enum` order, option on one side only); verify `just scripts-check` passes

## 2. Option check in spec-check

- [x] 2.1 Extend `scripts/check_openspec.ts`: read every Option requirement in main specs and in every active change's
      deltas; in a temporary copy walked from `openspec/` in the working tree, archive each active change that has both
      `specs/` and a `tasks.md` in name order, reporting a refused archive with OpenSpec's message; compare each
      `src/<id>/devcontainer-feature.json` that has a spec in the copy; fold the result into the exit decision; list the
      relied-on OpenSpec behaviors in the header comment and update the `spec-check` comment in `justfile`; extend the
      `exitCode` tests in `scripts/checks_test.ts`; verify `just spec-check` passes on this branch, and, in a scratch
      copy of the repository, that each Acceptance case of proposal.md (agreeing feature, each kind of difference, a
      change without and with `tasks.md`, a spec without `src/<id>/`, a malformed requirement, a refused archive, an
      untracked change) gives the stated result with `git status` unchanged

## 3. Scaffold

- [x] 3.1 Make `scripts/new_feature.ts` take the options from the Option requirements in the delta spec of the one
      active change holding `specs/<id>/` (an error naming the changes when there is none or more than one), writing
      type, default, `enum`, and a TODO description into the metadata and one variable per option with its default into
      `install.sh`; update its tests in `scripts/checks_test.ts`; verify in a scratch copy that `just new-feature <id>`
      for a change declaring options produces metadata that `just spec-check` accepts once the change has a `tasks.md`

## 4. Rules and knowledge base

- [x] 4.1 In `.agents/knowledge/spec-workflow.md`, add the "Option requirements" section (format, value encoding,
      scenario naming, reserved prefix, when `tasks.md` turns the comparison on), rewrite the Source of truth options
      row with its note on `devcontainer-feature.json`, add the `proposals` / `description` row, add the one exception
      under the table for a design's option table, and update Artifact operations, the package gate's review list, and
      "Update this file when"; verify `just lint` passes
- [x] 4.2 In `openspec/config.yaml`, replace the `rules.specs` entry on types and defaults with a pointer to the format
      and extend the `rules.design` entry on option changes with the option table and its reasons; verify
      `just spec-check` reports every rule reaching OpenSpec and `openspec instructions` shows the new wording
- [x] 4.3 Update `.agents/knowledge/feature-authoring.md` (Metadata, Layout) and the `spec` row of
      `.agents/knowledge/github/checks.md`; verify no file still tells authors to leave option types or defaults out of
      specs (`grep`) and `just lint` passes

## 5. Integration

- [ ] 5.1 Run `just check`, push, and confirm every required check passes on this PR; record each Acceptance item of
      proposal.md with its result in the PR's Validation section
