# Design

## Context

- OpenSpec 1.13.2 behavior this design relies on, tried in a throwaway project on 2026-09-30:
  - A markdown table inside a requirement body passes `openspec validate --strict`, and archive merges it cell for cell.
    Strict validation requires a SHALL or MUST in each requirement and at least one scenario.
  - A delta section other than Purpose and the four requirement operations is dropped by archive without a warning, and
    the Purpose of an existing spec cannot change through a delta.
  - Two changes that each MODIFY the same requirement both archive with exit code 0; the later one silently restores
    whatever the earlier one changed elsewhere in that requirement.
  - A MODIFIED or RENAMED requirement must keep every scenario name the current spec has
    (`dist/core/validation/validator.js`, "omits scenario(s) the current spec still has"); a scenario is dropped only by
    removing the requirement and adding one under a new name.
  - `openspec archive <change> -y` applies deltas whether or not the change has a `tasks.md` and whether or not its
    tasks are ticked.
  - `openspec show --json` returns requirement text and scenarios but not requirement names.
- `scripts/check_openspec.ts` already runs from `just spec-check` with `--allow-run=git,openspec` and
  `--allow-write=/tmp` and runs OpenSpec in a temporary copy of the tracked files (`git ls-files`, symlinks skipped).
  `scripts/validate.ts` checks that every `src/<id>/` has a spec but reads no spec content and may run only `git`.
- `scripts/new_feature.ts` scaffolds one `version` string option with default `latest` for every feature.
- No feature has merged: `openspec/specs/` is empty, and every open feature draft carries its spec as an ADDED delta.

## Goals / Non-Goals

**Goals:**

- The format is stated once, in a new "Option requirements" section of `.agents/knowledge/spec-workflow.md`; the config
  rules, `feature-authoring.md`, and `checks.md` point to it. Checked by reading the diff: no other file restates the
  table rows or the value encoding.
- Reading Option requirements and comparing them with option metadata are pure functions over text and parsed JSON in
  the shared module, tested beside it (`scripts/lib/*_test.ts`, like `repo_test.ts`) without file-system or subprocess
  permissions; `scripts/checks_test.ts` keeps covering the scaffold and the script's exit decision. Checked by
  `just scripts-check`.
- The option check builds its own copy by walking `openspec/` in the working tree rather than `git ls-files`, so an
  uncommitted change counts. Checked by a run with a new untracked change present, and `git status` unchanged after it.
- The OpenSpec behaviors the check relies on (Context) are listed in the header comment of `scripts/check_openspec.ts`,
  as the config rules check already lists its own, so they are re-read at the next OpenSpec upgrade. Checked by reading
  the diff.
- Every message names the feature, the option, the field, both values, and the files to fix. Checked by the Acceptance
  runs.

**Non-Goals:**

- Checking that an option change carries the right version bump; the issue leaves it out of scope.
- Machine-checking the syntax of free-form string values (version formats, list grammars); their scenarios stay the
  contract.
- Detecting two active changes that modify the same Option requirement (see Context).
- Editing the open feature drafts.
- Machine-checking a design's option table against its delta spec; the design's format is free, and the package gate
  reviews both side by side.

## Decisions

- **Contract attributes only: name, type, default, `enum` values.** They decide what a consumer may write and what an
  omitted option does. `proposals` are suggestions the tooling shows, `description` is display text, and the variable
  mapping is a convention in `feature-authoring.md`; stating them in specs would copy non-contract data. Rejected:
  describing only "what happens when the option is omitted" in prose — it restates the default less precisely and cannot
  be compared with `devcontainer-feature.json`.
- **One requirement per option**, named `Option <name>` with the bare option name (a RENAMED line already wraps the
  header in backticks). Its body is one SHALL sentence and a `Field | Value` table with the rows `Type`, `Default`, and,
  for an `enum`, `Enum`:

  ```markdown
  ### Requirement: Option failureMode

  The feature SHALL accept the option `failureMode` as declared here.

  | Field   | Value               |
  | ------- | ------------------- |
  | Type    | `string`            |
  | Default | `"closed"`          |
  | Enum    | `["closed","warn"]` |

  #### Scenario: Omitted failureMode

  - **WHEN** the feature is installed without `failureMode`
  - **THEN** ...
  ```

  Rejected: one requirement holding every option — each change restates all of them, and two changes lose updates
  (Context); a table in Purpose — it cannot change through a delta; a separate `## Options` section — archive drops it.
- **`Default` and `Enum` values are JSON literals in code spans** (`"latest"`, `""`, `true`, `["a","b"]`), read with
  `JSON.parse`; `Type` is the bare keyword `boolean` or `string`. The default's JSON type must match the type; `Enum` is
  allowed only for `string`, must hold the default, and is compared in order, since tools list the values in that order.
  A `|` inside a value is written `\|`, as a table cell requires; a value holding a backtick cannot be written and is
  rejected. Rejected: bare text values — an empty default would be an empty cell, and quoting would need its own escape
  rules anyway.
- **An Option requirement's scenarios cover what that option's values do**, at least the omitted case (OpenSpec requires
  one scenario of any kind); behavior that depends on several options gets its own requirement. Scenario names never
  carry a value (`Omitted version`, not `Latest by default`), because a MODIFIED requirement can never drop a scenario
  name. The header prefix `Requirement: Option` is reserved for Option requirements, so a behavior requirement never
  starts with that word.
- **A feature without options has no Option requirement.** The comparison is between sets, so empty equals empty.
  Rejected: a "declares no options" requirement — a scenario that tests nothing.
- **The comparison lives in `scripts/check_openspec.ts`**, which already holds the OpenSpec permissions it needs.
  Rejected: `scripts/validate.ts`, whose permissions would have to grow to run OpenSpec and write to `/tmp`.
- **The spec compared is what archive would produce.** In its copy, the check archives every active change that has both
  `specs/` and a `tasks.md`, in name order with OpenSpec's output suppressed, and reads `openspec/specs/<id>/spec.md`
  for each `src/<id>/`. A refused archive is a failure naming the change and quoting OpenSpec's message; the changes
  after it are still tried, and a feature the failure leaves without a current spec is not compared. A `src/<id>/`
  without a spec in the copy is not compared either: `just validate` owns that rule. Rejected: a delta applier of our
  own — it reimplements OpenSpec's RENAMED and scenario rules and can disagree with the real archive; comparing with
  main specs only — a new feature or an implemented option change would fail until its archive, which happens after
  review.
- **Every Option requirement is read, whatever the phase.** The format check covers main specs and the deltas of every
  active change, `tasks.md` or not, so a malformed requirement is reported while the package gate can still see it;
  `tasks.md` decides only which spec `devcontainer-feature.json` is compared with.
- **`tasks.md` marks when a change's deltas count.** `rules.tasks` lets it exist only after the package gate, so before
  then the implementation has not started and `devcontainer-feature.json` still matches the main spec. Rejected: every
  active change always counts — an option change's draft would be red for its whole package deliberation; reading the
  PR's `Phase:` line — not available to a local `just check`; a marker in `.openspec.yaml` — change metadata is not
  edited by hand.
- **A shared parser in `scripts/lib/`**, used by `check_openspec.ts` and `new_feature.ts`, with no permissions of its
  own. Rejected: exporting it from `check_openspec.ts` — importing that module pulls in its YAML parser and the
  environment reads it needs into `new_feature.ts`. Touching `scripts/lib/` makes CI select the canary set on this PR,
  which is empty today; that cost is accepted.
- **`just new-feature <id>` reads the delta spec of the one active change holding `specs/<id>/`** and writes each Option
  requirement into the metadata (type, default, `enum`, a TODO description) and into `install.sh` as a variable with its
  default. No active change, or more than one, is an error naming them.
- **A design describes the options its change touches**, as a table of every option the change adds, changes, renames,
  or removes: name, type, default, `enum` or `proposals`, and meaning (the draft of `description`), followed by the
  reason for each default and the rejected option shapes. Untouched options are not listed. The delta spec wins where
  the two differ, and the design is frozen at archive, so this restatement never outlives the change. It is the only
  place `proposals` and the meaning are reviewed before `devcontainer-feature.json` exists, and the duplicate test
  depends on the chosen proposals. Rejected: values in the delta spec only, with the design giving reasons — the
  reviewer reads options scattered over one requirement each, and `proposals` have no place at the package gate; listing
  every option — restates the untouched ones for no review benefit.
- **Rule wording and placement.** `rules.specs` swaps "leave their types and defaults to devcontainer-feature.json" for
  a pointer to the format; the `rules.design` entry that already names option changes gains the option table and its
  reasons, so the trigger stays stated once. In `spec-workflow.md`, the Source of truth options row names the Option
  requirements as the rule and the change's design under "Points to it", and the rule under the table that a pointer
  "never restates the fact" gains one exception scoped to that row: a design may list the options its change touches,
  frozen at archive, the delta spec winning where they differ. A note beside the table says `devcontainer-feature.json`
  implements them the way `install.sh` implements behavior and `just spec-check` keeps them equal, so it is neither a
  pointer nor a second source. A second row gives `proposals` and `description` to `devcontainer-feature.json`, with the
  README pointing to it. The Option requirements section also says that writing `tasks.md` turns the comparison on for
  that change, and "Update this file when" gains the format changing (with the shared parser). Artifact operations and
  the package gate's review list name the check and each option's requirement.

## Risks / Trade-offs

- [An OpenSpec upgrade changes archive or requirement parsing] → `spec-workflow.md` already asks for updates when
  OpenSpec is upgraded, and the header comment of `scripts/check_openspec.ts` lists the behaviors to re-verify; the
  parser's tests fail on a format drift of our own.
- [The commit that adds `tasks.md` turns `spec` red until `devcontainer-feature.json` is updated] → Expected: it is the
  first moment the implementation owes the new values; the implementation commit clears it.
- [Two active changes on one feature archive in name order, which may differ from merge order] → Rare with one PR per
  feature change; the check runs again on `main` after each merge.
- [A scenario name carries a value and outlives it] → The format section says why names stay neutral; reviewed at the
  package gate, not machine-checked.
- [A design's option table and its delta spec diverge during the deliberation] → The delta spec wins by rule, the
  package gate reviews both, and a maintainer's requested change is carried into both before the gate closes; an
  archived design that disagrees with a later implementation is history, not contract.
- [The line between an Option requirement and a multi-option behavior requirement blurs] → The format section's example
  and the rule "behavior that depends on several options gets its own requirement".

## Migration Plan

No main spec exists, so nothing on `main` migrates. Each open feature draft adds Option requirements to its own ADDED
delta and gathers its option facts into the design's option table before its package gate closes; the drafts that
already hold `devcontainer-feature.json` copy their values from it and ask the maintainer to confirm the added
requirements.
