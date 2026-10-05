# Proposal

## Why

`src/apt-packages/` and `test/apt-packages/` predate `.agents/knowledge/shell-style.md`, and the #52 audit confirmed
that the feature's failures are hard to act on: refresh and install failures end with APT's exit status and no line from
the feature, a failing `apt-config` or `apt-cache` is reported as a missing directory, name, or version, the entry
refusal is a 336-character grammar dump, no option failure shows the value that was given, and the duplicate test
re-derives its expected values instead of stating them. The package-list features are restyled before their phase 2 and
phase 3 work (#56, #61), which changes the same `install.sh`, so no file mixes two styles. Implements
https://github.com/hoshiori-dev/devcontainer-features/issues/73, part of
https://github.com/hoshiori-dev/devcontainer-features/issues/52.

## What Changes

- `install.sh` and every test script under `test/apt-packages/` follow the shell style guide: a `main` that reads as the
  feature's steps, constants and option defaults at the top, `log` and `fail` with the `apt-packages:` prefix, long
  options where both images' tools have them, and no pipeline whose status decides anything.
- Every failure the developer can fix prints one `apt-packages: error: <reason>; <how to fix it>` line on stderr and
  exits with status 1: invalid options and entries (with the given value), an image without `apt-get` (with the detected
  distribution), an unusable index directory, `refreshPolicy=never` without an index, an inexact name or version, and a
  failed refresh, install, or cleanup. A failed refresh or install now exits 1 instead of APT's 100; APT's own messages
  still print above the feature's line.
- The feature logs one line before each step that changes the image or uses the network: refreshing the index,
  installing, and each cleanup mode that deletes files. Existing log lines keep their wording without the trailing
  period.
- The tests state their expected values as literals and their labels in the spec's words, and the four `controls_*.sh`
  checks report through the test library like the other scenarios.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. No Requirement or Scenario of `apt-packages` changes: the spec fixes exit status 1 and the named entry, option, or
`apt-get` with Debian and Ubuntu where it fixes a message, and only "a non-zero status" for refresh and install
failures, so the new wording, log lines, and status 1 stay inside it. The change sets `skip_specs: true`.

## Impact

- Feature `apt-packages`: version 1.1.0 → 1.1.1 (PATCH). `feature-authoring.md` Versions: a change under `src/<id>/`
  bumps the version, and a restyle that changes message text and a failure's non-zero status without changing an option,
  a supported image, or what install does is a fix, not new behavior.
- Files: `src/apt-packages/install.sh`, `src/apt-packages/devcontainer-feature.json` (version only), and the shell tests
  `test/apt-packages/test.sh`, `duplicate.sh`, `listed_packages_debian.sh`, `listed_packages_ubuntu.sh`,
  `native_architecture.sh`, `recommends_and_whitespace.sh`, `debconf_question.sh`, and
  `controls_{none,packages}_{0,1}.sh`.
- Unchanged: `NOTES.md` (so the generated `README.md` too), `scenarios.json`, `compatibility.json`, the host runners
  `direct_checks.ts` and `control_checks.ts`, the spec, and every other feature.

## Acceptance

### Becomes true

- `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on `src/apt-packages/install.sh` and
  on every `*.sh` under `test/apt-packages/`, and every line of them is within 120 characters.
- Every `fail` line has the form `apt-packages: error: <reason>; <how to fix it>`, every `log` line the form
  `apt-packages: <message>`, each message starting in lower case and without a trailing period.
- A refused option names the option in camelCase and shows the given value; a refused entry shows the entry verbatim;
  the message for an image without `apt-get` names `apt-get`, Debian, Ubuntu, and the detected distribution.
- A failed `apt-get update`, `apt-get install`, or `apt-get clean`, and a failing `apt-config` or `apt-cache` call, ends
  with an `apt-packages: error:` line naming that step and exit status 1; a failing `apt-config` or `apt-cache` is no
  longer reported as an empty directory or a missing name or version.
- The build output shows an `apt-packages:` line before every index refresh, the installation, and every cleanup that
  deletes files.
- `test/apt-packages/duplicate.sh` asserts literal packages and cache state, and each check label in the shell tests
  states one behavior in the spec's words.
- `src/apt-packages/devcontainer-feature.json` has version `1.1.1`.
- `just check`, `just test apt-packages`, and `just test-scenarios apt-packages` pass, and
  `test/apt-packages/direct_checks.ts` and `test/apt-packages/control_checks.ts` pass on both compatibility images on
  amd64, with their output recorded in the PR's Validation section.

### Stays true

- Download sources, TLS, checksum, and signature verification do not change: the feature still fetches nothing itself,
  takes packages only from the repositories the image configures, and passes no option that weakens APT's repository
  authentication.
- Every existing Requirement and Scenario of `openspec/specs/apt-packages/spec.md` still holds, including the order of
  checks it fixes: controls and entries before any package-manager call, the empty-list exit before the `apt-get` check,
  and the exact-name check after the index is ready and before installation.
- The feature still installs twice (`just test apt-packages` runs `duplicate.sh`).
- An accepted entry still reaches `apt-get` only as one argument after `--`, and no option value or entry is ever
  evaluated as shell code.
- The accepted forms of every option and entry are unchanged: no value accepted today is refused, and no value refused
  today is accepted.
- An empty package list still succeeds on an image without bash or `apt-get`.
- Options, defaults, and supported images are unchanged.
