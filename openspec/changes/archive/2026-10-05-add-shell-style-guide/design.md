# Design

## Context

- Baseline: the Google Shell Style Guide, https://google.github.io/styleguide/shellguide.html, read on 2026-10-05. The
  decisions below were made with the maintainer in conversation on 2026-10-05.
- State on `main` at ee9c14c: 123 tracked `*.sh` files. Of the shipped scripts, eight use POSIX `sh` (the five package
  installers, glab, uv, and uv's volume repair script) and three use bash. deno, hf-cli, and uv use four-space
  indentation, although `.editorconfig` sets two for `*.sh`. Only deno defines a `main`. Logging prefixes differ in
  every feature. `.editorconfig` carries shfmt-only keys (`binary_next_line`, `switch_case_indent`) that no tool
  enforces.
- shellcheck 0.9.0 (dev container and CI runner) offers nine optional checks. Running `require-variable-braces` and
  `require-double-brackets` over the tracked scripts today reports 1,150 findings in 69 files (1,092 SC2250, 58 SC2292).
- `dev-container-features-test-lib` (devcontainer CLI 0.89.0) is bash. Its `check` and `reportResults` work under
  `set -u`, and `test/deno/group_conflicts.sh` already runs with `set -euo pipefail`. glab's POSIX tests use their own
  stand-in library because BusyBox ash cannot parse it.
- Guiding principle, from the maintainer: a shipped script exists so that developers who configure a dev container, and
  developers who use one someone else configured, can see exactly what happens and trust the feature author. It does not
  exist to handle every conceivable input. Option behavior must be clear, so that an option cannot become a way to take
  over the environment. Other ways a configuration author could inject behavior are out of a feature's reach. Clear
  logs, clear logic, and early failure help developers fix their configuration. Test scripts describe the behavior
  contract to feature developers and auditing users, so readability matters more than defensiveness.

## Goals / Non-Goals

**Goals:**

- The guide is self-contained: an agent or contributor applies it without opening the Google guide. Checked by review of
  the guide against the decisions below.
- Each shell rule lives in one place. `feature-authoring.md`, `testing.md`, the review guidance, and the review skill
  link to the guide. Checked by searching those files for restated shebang, `set`, and style rules.
- The scaffold follows the guide from the first commit of a new feature. Checked by scaffolding a sample id into a
  temporary checkout and running shellcheck with the two optional checks.

**Non-Goals:**

- Restyling existing scripts (#52), adding a `.shellcheckrc`, adding shfmt, or changing `.editorconfig`.
- Changing any feature's behavior or the download, checksum, signature, and installer rules.

## Decisions

Each item gives the rule, then the rejected alternatives. "Shipped" means scripts under `src/`.

### Scope and form

- **Coverage.** Shipped scripts, test scripts, and the `scripts/new_feature.ts` templates. Rejected: also
  `.devcontainer/setup.sh` and justfile recipes. The first is protected configuration, and the recipes are one-liners.
- **Form.** One self-contained, concise knowledge file, `.agents/knowledge/shell-style.md`: one line per rule, short
  good/bad examples where a rule needs one, no restated Google rationale. Rejected: only the differences from Google
  (readers need two documents, and the guide drifts as Google's changes); a full restatement (context cost for agents).
- **Long-lived rules only.** The refactor's order and checklists belong to #52's work. The guide says that a restyle
  follows the usual version and OpenSpec rules and adds no transition chapter. Rejected: a migration chapter deleted
  after the refactor.
- **Transition.** New files follow the guide. An edit to a file not yet restyled keeps that file's style until its
  restyle, so no file mixes two styles. Rejected: guide style for every edited line, which would leave such files
  half-converted.
- **Deviations.** Every `# shellcheck disable=` and every deliberate deviation carries a reason on the line above it.
  File-wide disables are not allowed. The guide whitelists the standard directives: `# shellcheck source=/dev/null` for
  `/etc/os-release` and the test library, and `# shellcheck shell=…` in sourced files. Rejected: line-level disables
  without a reason.

### Dialect and enforcement

- **Dialect (#49).** POSIX `sh` with `set -eu` is required when a listed image ships no bash, and allowed when the
  feature's purpose calls for broad image compatibility. Bash with `set -euo pipefail` is recommended otherwise. The
  guide has a common part, a bash part, and a POSIX part. Rejected: bash only (Alpine images would have bash installed
  for style's sake, which changes users' images); POSIX only (gives up arrays, `[[ ]]`, and `local`).
- **Tests use the same `set` options.** Rejected: keeping the starter template's `set -e`, which lets unset variables
  and failures inside pipelines pass silently.
- **Enforcement.** shellcheck, plus the optional checks `require-variable-braces` and `require-double-brackets`. The
  guide documents the local command (`shellcheck -o require-variable-braces,require-double-brackets`), and the last
  restyle PR under #52 adds the `.shellcheckrc` that turns them on everywhere. Rejected: shfmt in CI or for a one-time
  pass (declined; it needs protected configuration); `check-extra-masked-returns` (too noisy for intentional cases) and
  the other optional checks; turning them on in this change with a mechanical fix of all 1,150 findings (touches every
  feature, then the structural restyle touches them again); a per-file allowlist (adds CI machinery).

### Formatting

- **Indentation and line length.** Two spaces, matching `.editorconfig` and Google. The limit is 120 characters,
  matching `.editorconfig`; a line holding only a long URL or path may exceed it. Rejected: four spaces; 80 (Google);
  100.
- **Layout (Google defaults).** `; then` and `; do` stay on the line of the keyword. `|`, `&&`, and `||` start the
  continuation line, which matches `.editorconfig`'s `binary_next_line`. No `function` keyword. `$(…)`, `(( ))`, and
  `$(( ))` only.
- **Short-circuits.** `cmd || fail …`, `cmd || return`, and `[[ … ]] || fail …` are used only as guards; other branching
  uses `if`. A one-line `if` holds one simple command. Rejected: `if` blocks everywhere (validation code gets much
  longer); no restriction.
- **No decorative section dividers.** Named functions and the comment above each one are the sections. Rejected: one
  standard `# ---` divider format.

### Variables

- **Expansion.** Named variables are always written `"${var}"`. Special parameters (`$1`, `$@`, `$?`) stay unbraced.
  Rejected: braces only when needed (a judgment call no lint can enforce).
- **Quoting.** Google's rules as written. Rejected: quoting every expansion, including assignments and `case` subjects.
- **Function-local variables.** Bash uses `local`, declared separately from any command substitution. POSIX prefixes
  them with the full function name (`version_at_least_a`), and `main`'s with `main_`. Rejected: `local` in POSIX scripts
  (not POSIX and needs a SC3043 disable in every file); unprefixed names kept apart by care; a short prefix declared per
  function; a leading underscore.
- **Naming.** Upper case only for readonly constants, exported variables, and option variables. Mutable globals, locals,
  and functions use lower snake_case. Rejected: all globals upper case.
- **readonly.** Every constant is readonly and defined at the top. Option variables become readonly right after
  validation. Values are rewritten only where the spec defines an accepted alternative form, for example glab's leading
  `v`. Rejected: readonly only for trust-related constants; no requirement.
- **Trust surface at the top.** External URLs, signing-key fingerprints, and every path the feature creates or modifies
  outside a temporary directory are readonly constants at the top of a shipped script.

### Structure and comments

- **`main`.** A shipped script that defines a function has a `main` as its last function, and the file ends with
  `main "$@"`. `main` reads as the list of steps. A function is a named step or a helper called from several places, so
  no single-use thin wrapper, and calls go at most main → step → helper. Tests are exempt. Rejected: no `main` anywhere;
  `main` in tests too.
- **Libraries.** A shipped script sources only `/etc/os-release` (in a subshell, so it cannot overwrite option variables
  such as `VERSION`) and the feature's own library files under `src/<id>/`. A complex feature may split its code this
  way, and the split files ship and are audited like the rest. Most features need no split. A library is named `*.sh`,
  has no shebang, is not executable, and starts with `# shellcheck shell=…`. Tests source the test library and their own
  helpers.
- **File header of `install.sh`.** It says what is installed, from where, and to where; the run context and the
  environment variable each option arrives in; and, for POSIX `sh`, why. Rejected: a summary of second-install behavior,
  which the spec already states and which would drift from it.
- **Function comments.** One prose sentence for a non-obvious function, covering what it does, its arguments, its
  output, and its return status. Rejected: Google's structured block, for every function or only for libraries.
- **TODO.** `TODO(#<issue>)`.
- **File names.** Repository source files use snake_case, including shipped ones (the restyle renames
  `src/uv/repair-volume.sh`). Paths installed into images are behavior and stay as the spec defines them. Rejected:
  snake_case for new files only; kebab-case.

### Commands, output, and failure

- **Logging helpers.** `log` writes to stdout. `fail` writes to stderr and exits 1. The prefixes are `<id>:` and
  `<id>: error:`. Messages start in lower case and have no trailing period or timestamp, since build logs carry their
  own times. Rejected: `<id> feature:` (existing deno and glab style); timestamps; only requiring stderr.
- **What to log.** One line per step that changes the image or uses the network: what, from where, to where. Output of
  state-changing commands is never sent to `/dev/null`; only probes such as `command -v` are.
- **`printf` and `echo`.** Output that includes an expansion uses `printf '%s\n'`, and fixed text may use `echo`.
  Rejected: `printf` everywhere; no rule; requiring `printf` only inside `log`, `fail`, and file writes.
- **Long options.** Shipped scripts prefer long options, except where an implementation on a target image (BusyBox)
  lacks them. Tests are free to use either. Rejected: long options in tests too; no rule.
- **Reused argument sets.** A function in both dialects, for example `fetch() { curl --proto '=https' … "$@"; }`. Arrays
  hold only dynamic lists such as package names. Rejected: arrays in bash and functions in POSIX.
- **Options are data.** `main` validates every option and platform precondition first, with anchored patterns (`case`,
  `[[ =~ ]]`), and changes nothing in the image before validation passes. Option values reach commands only as quoted
  arguments, never through `eval`, `sh -c`, `source`, or generated code. The only exception is an option whose name,
  spec, and description all state that it is a hook or configuration script; the feature logs what it runs.
- **No obscure constructs in shipped scripts.** No `eval`, aliases, indirect expansion (`${!var}`), command names built
  from variables, encoded blobs, or `set -x`.
- **Failure handling.** A step that can fail for a reason the developer can fix (download, verification, package
  manager, unsuitable configuration or image) ends in `|| fail "<reason>; <how to fix>"`; anything else is left to
  `set -e`. Known failure modes such as network interruptions, a temporarily unavailable source, or a known distribution
  difference get explicit handling, with a comment naming the failure mode, and within the sources and behavior the spec
  allows. No catch-all hides unknown errors to keep a feature limping along. Input outside the forms the spec accepts
  fails; the script never guesses what it meant. Rejected: an explicit `fail` on every external command; leaving this to
  judgment.

### Tests

- A check's label states one behavior in the spec's words, and its command verifies exactly that.
- Expected values are literals where possible. A value computed at run time (for example the current latest release) has
  a comment saying why.
- Helpers are named after the behavior they assert and may sit right before the check that uses them. A one-line
  `bash -c` pipeline may be inlined in `check`; anything longer becomes a function.
- A few repeated lines are better than an abstraction across files. A shared helper file holds only assertions that
  several scripts of the same feature use.
- Tests need no `main` and no long options. All other rules apply, except those written only for shipped scripts.

## Risks / Trade-offs

- [Until the last restyle, CI does not enforce the two optional checks] → The guide gives the local command, and review
  applies the guide to new files.
- [Prefixing POSIX locals with the full function name makes names long] → This pushes toward short function names.
  Accepted, because the rule is mechanical and cannot collide.
- [The guide sits next to scripts that do not follow it yet] → The transition rule keeps each file consistent, and #52
  restyles them.
- [Copilot may not load the guide even when the review skill names it] → Same limitation as the existing skill. Human
  review remains the gate.

## Migration Plan

None in this change. The `.shellcheckrc` and the restyle of existing scripts follow under #52.
