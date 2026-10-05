# Proposal

Implements [#81](https://github.com/hoshiori-dev/devcontainer-features/issues/81), part of
[#52](https://github.com/hoshiori-dev/devcontainer-features/issues/52).

## Why

`src/zypper-packages/install.sh` and the scripts under `test/zypper-packages/` predate
`.agents/knowledge/shell-style.md`. The #52 audit confirmed for this feature the problems the guide exists to prevent: a
failing `zypper` call ends the build with no line of the feature's own saying which step failed or what to do, the steps
that refresh, install, and clean log nothing, the cache paths the script reads are literals in the middle of the file,
the entry allowlist carries two layers that do the same job, comments explain how instead of why, and the scenario
scripts hide which behavior failed behind bare commands and a found-flag loop. The phase 2 and phase 3 work (#59, #63)
changes the same `install.sh`, so the restyle lands first.

## What Changes

- `src/zypper-packages/install.sh` and every script under `test/zypper-packages/` follow
  `.agents/knowledge/shell-style.md`; `install.sh` stays POSIX `sh`, and every line it writes itself starts with
  `zypper-packages:`, failures with `zypper-packages: error:`.
- Every message starts in lower case without a trailing period, and every failure the developer can fix says how to fix
  it. Each message still names what the spec says it names: the option, the entry, or `zypper` and openSUSE. The wording
  follows the template the five package-list installers share.
- The feature logs one line before each step that refreshes, reads, or rebuilds repository metadata, installs, or cleans
  caches.
- A failing `zypper` call ends with a `zypper-packages: error:` line that names the step, keeps zypper's exit status in
  its text, and exits 1.
- `test.sh`, `duplicate.sh`, and the scenario scripts report each behavior they assert as its own labeled check, in the
  spec's words.
- The feature's version moves from `1.0.0` to `1.0.1`. Options, supported images, package selection, refresh, cleanup,
  and verification behave as before.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. No behavior that a Requirement of `openspec/specs/zypper-packages/spec.md` covers changes, so the change sets
`skip_specs: true`.

## Impact

- Feature ids touched: `zypper-packages`, PATCH bump `1.0.0` → `1.0.1`. Reason (`feature-authoring.md`, Versions): every
  change under `src/<id>/` raises the version, and this one changes message text, adds log lines, and turns zypper's
  failure statuses into status 1, all of which the spec leaves open (it asks only for a non-zero status there); no
  option, image, or install result changes, so no MINOR or MAJOR applies.
- Files: `src/zypper-packages/install.sh`; the `version` in `src/zypper-packages/devcontainer-feature.json`;
  `src/zypper-packages/README.md` only if `just docs` changes it; `test/zypper-packages/test.sh`, `duplicate.sh`,
  `listed_packages_*.sh`, `controls_none_*.sh`, `controls_packages_*.sh`, `optional_false_*.sh`, `optional_true_*.sh`,
  and `architecture_*.sh`.
- Not touched: `NOTES.md`, `scenarios.json`, `compatibility.json`, `control_checks.ts` (left to #50), the spec, other
  features, scripts, workflows, and test infrastructure. No other feature depends on `zypper-packages`, and no global
  scenario installs it.
- Tumbleweed arm64 stays out of `compatibility.json`: #43 asked to restore it on the next `zypper-packages` change, and
  the maintainer set that request aside for this change (design.md, Open Questions).

## Acceptance

### Becomes true

- `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on `src/zypper-packages/install.sh`
  and on every `test/zypper-packages/*.sh`; no line of `install.sh` is longer than 120 characters.
- Every line `install.sh` writes itself starts with `zypper-packages:`, and every failure line with
  `zypper-packages: error:`; each starts in lower case and has no trailing period.
- Before each metadata refresh, cached-metadata check, parsed-cache build, install, and cache cleanup (`cleanup=all` or
  `packages`), the output holds a `zypper-packages:` line naming that step; an empty list logs that there is nothing to
  do.
- When `zypper` fails during the repository listing, refresh, cached-metadata rebuild, install, or cleanup, the feature
  exits 1 with a `zypper-packages: error:` line that names the step and zypper's exit status.
- Every test script under `test/zypper-packages/` asserts only through labeled `check` calls of the test library and
  ends with `reportResults`.
- `devcontainer-feature.json` has version `1.0.1`; `just check` passes.

### Stays true

- No change to download sources, TLS, checksum, or signature verification: every `zypper` call keeps its subcommand and
  options (no option is added or removed), and the feature adds, removes, or changes no URL, repository, service, key,
  or zypp configuration.
- Every existing Requirement and Scenario of `openspec/specs/zypper-packages/spec.md` still holds, notably those of
  "Installation controls are validated before changes" (an empty control value included), "Option packages", "Entries
  are validated before anything changes", "Image without zypper", and "Repository metadata refresh".
- The feature still installs twice: `duplicate.sh` passes on every image of the compatibility list.
- Option names, types, defaults, and `enum` values are unchanged; `just spec-check` passes.
- `zypper` receives the same entries, in the same order, as separate arguments after `--`.
- With `refreshPolicy=never` the feature downloads no metadata, and its own output holds none of `Downloading`,
  `Retrieving repository`, or `fetch http`.
- `test/zypper-packages/compatibility.json` and `scenarios.json` are unchanged; `just test zypper-packages` and
  `just test-scenarios zypper-packages` pass.
- `test/zypper-packages/control_checks.ts`, unchanged, passes on the amd64 images of the compatibility list, except the
  Tumbleweed pin-below check that may report not run, as the feature's first change approved.
