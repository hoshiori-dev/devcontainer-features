# Proposal

## Why

`src/apk-packages/` and `test/apk-packages/` predate `.agents/knowledge/shell-style.md`, so a developer auditing the
feature reads a script with no `main`, unbraced variables, no `log` helper, failure messages that end in a period and
lack a fix, and two package-manager failures that end with apk's own status and no feature message. The #52 audit also
confirmed scattered paths, an unexplained constant, a pipeline whose status decides, and tests whose intent is hidden by
defensive parsing and unlabeled checks. The restyle lands before the phase work in #58, which changes the same
`install.sh`. Implements https://github.com/hoshiori-dev/devcontainer-features/issues/72, part of
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## What Changes

- `src/apk-packages/install.sh` follows the shell style guide's POSIX skeleton: a header naming every option variable
  and why the script is POSIX `sh`, readonly constants for the paths and the cache age it uses, option defaults at the
  top, `log` and `fail`, named steps, and `main "$@"`.
- Every failure message reads `apk-packages: error: <reason>; <how to fix it>`, without a trailing period; an invalid
  control names the option and the value received.
- A failing `apk update` or `apk add` ends with a feature message and exit status 1 instead of apk's own status.
- The steps that change the image but print nothing today (choosing the package cache, using cached indexes under
  `refreshPolicy=never`, and cleanup with `all` or `packages`) each log one line.
- The "apk not found" message names the image's distribution as the `PRETTY_NAME` of its `/etc/os-release`, quotes
  inside the value included, or as an unidentified distribution when the file names none.
- The test scripts follow the guide: one shared POSIX `check` / `reportResults` stand-in, literal expected values,
  labeled checks in the spec's words, and headers naming the scenarios they actually assert.
- `control_checks.ts` is type-checked when it runs, passes `PATH` as its own variable rather than as a control, and
  holds no no-op expression; the comment in `direct_checks.ts` on why a refusal proves validation ran first matches the
  new failure status.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. No behavior that a Requirement of `openspec/specs/apk-packages/spec.md` covers changes: the spec fixes no message
text or log line, and it requires only a non-zero status for the apk failures whose status changes to 1. The change sets
`skip_specs: true`.

## Impact

- Feature id: `apk-packages`, version 1.0.0 → 1.0.1. PATCH (`.agents/knowledge/feature-authoring.md`, Versions): a fix
  of messages, logging, and failure handling under `src/apk-packages/`, with no option, supported image, or install
  result changed.
- Files: `src/apk-packages/install.sh`, `src/apk-packages/devcontainer-feature.json` (version only), and under
  `test/apk-packages/`: `test.sh`, `duplicate.sh`, the eight scenario scripts, a new `checks.sh`, `direct_checks.ts`
  (one comment), and `control_checks.ts`. `NOTES.md`, the generated `README.md`, `scenarios.json`, and
  `compatibility.json` do not change unless the maintainer adopts an optional item from the design.
- No other feature, harness file, workflow, or dev container file changes.

## Acceptance

### Becomes true

- `shellcheck` and `shellcheck -o require-variable-braces,require-double-brackets` report nothing for
  `src/apk-packages/install.sh` and every `test/apk-packages/*.sh`.
- `install.sh` has the layout of the guide's POSIX skeleton, ends with `main "$@"`, and has no line over 120 characters.
- Every line `install.sh` prints itself, apart from apk's output, starts with `apk-packages:`; every failure line starts
  with `apk-packages: error:`, states a reason and a fix separated by `;`, and has no trailing period (wording in
  design.md, Decisions).
- Each image-changing or network step of a run with a non-empty list prints one log line: the package cache in use, the
  index refresh or the use of cached indexes, the install, and the cleanup for `all` and `packages`.
- A failing `apk update` or `apk add` exits with status 1 after a feature message.
- `src/apk-packages/devcontainer-feature.json` has version `1.0.1`.
- `test/apk-packages/checks.sh` holds the POSIX stand-in, and every test script reports all its labeled checks before it
  exits; `duplicate.sh` asserts `file` and `tree` as literals.
- `control_checks.ts` runs with `--check` in its shebang and sets `PATH` with its own `--env` argument.
- `just check`, `just test apk-packages`, and `just test-scenarios apk-packages` pass, and `direct_checks.ts` and
  `control_checks.ts`, run by hand because CI runs neither, pass on every amd64 image of
  `test/apk-packages/compatibility.json`, with results in the PR's Validation section.

### Stays true

- No change to download sources, TLS, checksum, or signature verification: the feature requests no URL itself, apk
  verifies every index and package against the keys the image trusts, and no flag, option, or configuration weakens it.
- Every Requirement and Scenario of `openspec/specs/apk-packages/spec.md` still holds, including the order of checks it
  fixes: controls and entries are validated before the empty-list exit, which comes before the `apk` check.
- The feature still installs twice: `duplicate.sh` passes on every compatibility image and architecture.
- Option names, types, defaults, `enum` values, and the set of accepted values are unchanged.
- For every combination of option values, every apk call receives the same subcommand, the same set of options and
  option arguments, and the same entries in the same order after `--`, as in version 1.0.0.
- Only the entries of `packages` reach apk: arguments given to `install.sh` itself are discarded, as in version 1.0.0.
- The supported images and architectures in `test/apk-packages/compatibility.json` are unchanged.
