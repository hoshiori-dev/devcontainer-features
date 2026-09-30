# Design

## Context

- OpenSpec 1.13.2 parses `config.yaml` with the `yaml` npm package (dependency `^2.8.3`, resolved to 2.9.1 in the dev
  container and pinned for CI in `.github/actions/setup-tools/action.yml`). Its `rules` handling, read from
  `dist/core/project-config.js` on 2026-09-30:
  - `rules` that is not a mapping: warns `Invalid 'rules' field in config (must be object)` and drops every rule;
  - a value that fails `z.array(z.string())`: warns
    `Rules for '<artifact>' must be an array of strings, ignoring this
    artifact's rules` and drops that artifact's
    rules, keeping the other artifacts';
  - empty strings: warns `Some rules for '<artifact>' are empty strings, ignoring them` and drops only those entries;
  - artifact ids are not restricted; an unknown id is kept and never used.
- Reproduced on 2026-09-30 in a throwaway repository: with `- Entries use - <label>: <url> form.` under `rules.specs`,
  `openspec validate --all --strict` exits 0, and `openspec instructions specs` returns no `rules` field while
  `openspec instructions design` still returns the design rules.
- `scripts/check_openspec.ts` is the project's OpenSpec check and already runs from `just spec-check`; today it only
  compares OpenSpec's generated files with a fresh `openspec init --tools claude`.
- The scripts use no YAML parser yet.

## Goals / Non-Goals

**Goals:**

- The check flags exactly the rules OpenSpec 1.13.2 would drop or ignore, listed in Context, and nothing it accepts.
  Checked by unit tests built from those four cases plus a valid block, and by the current `config.yaml` passing.
- The decision is a pure function over the parsed YAML value, exported from `scripts/check_openspec.ts` and tested in
  `scripts/checks_test.ts`; the script's main block only reads the file and prints what the function returns. Checked by
  the tests needing no file system or subprocess permission beyond what `just scripts-check` grants.
- Each message names the path OpenSpec uses (`rules.<artifact>`), the 1-based entry number, and the YAML type found, so
  the entry can be found without reading OpenSpec's source. Checked by the Acceptance run.
- The rules check runs before the `openspec init` comparison and both report, so one `just spec-check` shows every
  problem. Checked by the Acceptance run with a malformed rule, where the generated-files result still prints.

**Non-Goals:**

- Unknown artifact ids under `rules` (a typo such as `spec:` for `specs:`). OpenSpec accepts them silently too, but
  catching them needs the schema's artifact list; a follow-up issue can take it.
- `operations.<id>.guidance`, which OpenSpec drops the same way; the issue scopes this change to `rules`.
- Treating OpenSpec's stderr warnings as failures in general.

## Decisions

- **Parse `config.yaml` directly instead of watching OpenSpec's stderr.** Rejected: running `openspec instructions` per
  artifact and failing on its warning, which depends on OpenSpec's wording, needs an existing change to ask instructions
  for, and runs once per artifact. The direct check depends only on the file's structure, which is OpenSpec's documented
  config format.
- **Parse with the parser OpenSpec uses**, `npm:yaml@2.9.1` pinned inline, so the check reads plain scalars, quoting,
  and edge cases (tags, anchors, merge keys) exactly as OpenSpec does. Rejected: `jsr:@std/yaml`, a different
  implementation whose edge-case results could disagree with OpenSpec's and let a dropped rule pass. A later OpenSpec
  that moves to another `yaml` release does not require moving this pin: plain YAML 1.2 structure is stable across the
  2.x line.
- **Extend `scripts/check_openspec.ts` instead of adding a script.** It is already the project's OpenSpec check and a
  step of `just spec-check`; a second script would add a recipe line and a permission set for a few lines of logic. Its
  header comment grows to name both checks.
- **Flag empty strings too.** OpenSpec drops them one by one with a warning, so a rule written as `- ""` or a stray `-`
  (parsed as null, which fails the array check) never reaches an agent either.

## Risks / Trade-offs

- [A future OpenSpec changes what it accepts, for example numbers coerced to strings] → The check would then be stricter
  than OpenSpec, which fails safe; `spec-workflow.md` already asks to re-verify behavior when OpenSpec is upgraded, and
  the Context above names the file to re-read.
- [A new npm import needs Deno's cache] → CI already resolves `npm:` imports for `scripts/validate.ts`; the first `spec`
  run on this PR shows the import resolves there.
