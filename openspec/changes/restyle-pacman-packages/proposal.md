# Proposal

Implements [#79](https://github.com/hoshiori-dev/devcontainer-features/issues/79), part of
[#52](https://github.com/hoshiori-dev/devcontainer-features/issues/52).

## Why

The scripts and tests of `pacman-packages` predate `.agents/knowledge/shell-style.md` and do not follow it: the
installer has no `main`, no `log`, a `fail` without the `error:` marker, messages written as several sentences with
trailing periods, a package-manager step that fails without saying what to check, inline cache paths, and a header that
names neither the `cleanup` option nor the reason for POSIX `sh`. The #52 audit also confirmed tests whose intent is
hidden by defensive handling: an install-twice test that re-parses its own input and branches over values the CLI never
passes, two unlabeled scenario scripts, and a host control runner that carries other package managers' dead branches.
The restyle lands before the phase work in #60, which changes the same `install.sh`.

## What Changes

- `src/pacman-packages/install.sh` follows the shell style guide: a POSIX `sh` script with a header naming both options,
  their variables, the cache paths, and why it is POSIX; readonly constants for the cache paths; `log` and `fail`
  helpers; named steps called from `main`.
- Every message the installer itself prints starts with `pacman-packages:`; every failure adds `error:` and reads as one
  `<reason>; <how to fix it>` sentence in lower case without a trailing period, still naming the refused entry, the
  invalid option, or `pacman` and Arch Linux.
- A failing `pacman` transaction ends with a feature message naming the list and what to check, after `pacman`'s own
  output, with exit status 1.
- The feature logs the source of the packages it installs and each cache removal it performs.
- The bash tests use `set -euo pipefail` and `[[ … ]]`; the install-twice test asserts the literal values the CLI's
  duplicate run uses; the two cleanup scenario scripts become labeled checks, and the one for `cleanup=none` also
  asserts that downloaded package files remain; the host control runner holds only the checks this feature's spec has,
  under its scenario names.
- `pacman-packages` version `1.0.0` becomes `1.0.1`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. No behavior a Requirement or Scenario of `openspec/specs/pacman-packages/spec.md` covers changes: the message
texts, log lines, and the exact non-zero status of a failing transaction are outside what its Requirements state, so the
change sets `skip_specs: true`.

## Impact

- Feature `pacman-packages`: PATCH bump `1.0.0` → `1.0.1`. `.agents/knowledge/feature-authoring.md` (Versions) names
  fixes with identical results as PATCH; the change adds no option, image, or install behavior and removes none.
- Files: `src/pacman-packages/install.sh`, `src/pacman-packages/devcontainer-feature.json` (version only),
  `test/pacman-packages/test.sh`, `duplicate.sh`, `listed_packages.sh`, `optional_dependencies_and_whitespace.sh`,
  `controls_packages_0.sh`, `controls_none_0.sh`, and `control_checks.ts`. `NOTES.md`, the generated `README.md`,
  `scenarios.json`, `compatibility.json`, and `direct_checks.ts` stay as they are.
- No other feature, script, workflow, or knowledge file changes. The sibling package-list features (apk, apt, dnf,
  zypper) are restyled in their own changes.

## Acceptance

### Becomes true

- `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on every shell script under
  `src/pacman-packages/` and `test/pacman-packages/`, and no line in them exceeds 120 characters.
- Every test script under `test/pacman-packages/`, `controls_packages_0.sh` and `controls_none_0.sh` included, is bash
  with `set -euo pipefail` and sources `dev-container-features-test-lib`.
- `install.sh` matches the POSIX skeleton's layout in `.agents/knowledge/shell-style.md`: header, `set -eu`, readonly
  constants, option defaults, mutable globals, `log` and `fail`, steps, `main`, `main "$@"`.
- Every line the feature itself prints starts with `pacman-packages:`, and every failure line with
  `pacman-packages: error:`, without a trailing period.
- A refused entry, an invalid `cleanup`, a missing `pacman`, and a failing `pacman` transaction each exit with status 1
  and one message stating the reason and how to fix it.
- A non-empty install logs where the packages come from and each cache directory it empties.
- `test/pacman-packages/duplicate.sh` asserts `bc` and `tree` installed, package files cleaned, and sync databases kept,
  as literals, with no branch over option values.
- The `controls_packages_0` and `controls_none_0` scenarios report labeled checks through `reportResults`;
  `controls_none_0` asserts that downloaded package files remain.
- `test/pacman-packages/control_checks.ts` runs only the checks named after Scenarios of the pacman-packages spec.
- `devcontainer-feature.json` has version `1.0.1`.
- `just check`, `just test pacman-packages`, `just test-scenarios pacman-packages`,
  `test/pacman-packages/direct_checks.ts` (including its alpine checks), and `test/pacman-packages/control_checks.ts`
  pass.

### Stays true

- No change to download sources, TLS, checksum, or signature verification: the feature still requests no URL itself, and
  `pacman` reaches only what the image configures, with `SigLevel` in effect.
- Every existing Requirement and Scenario of `openspec/specs/pacman-packages/spec.md` still holds, including the order
  of checks it fixes: invalid entries are refused before the `pacman` check, and an empty list succeeds without
  `pacman`.
- The feature still installs twice on every compatibility image (`just test pacman-packages`).
- Option names, types, defaults, and accepted values are unchanged; `just spec-check` passes.
- The messages keep the substrings the host checks assert: `refusing the entry '<entry>'`, `pacman was not found`,
  `Arch Linux`, and `cleanup`.
- `test/pacman-packages/compatibility.json` and the scenario keys in `scenarios.json` are unchanged.
