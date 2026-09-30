# Proposal

Implements [#16](https://github.com/hoshiori-dev/devcontainer-features/issues/16).

## Why

A dev container that develops with Deno needs the `deno` executable on `PATH` for the remote user, at a version the
container's author chooses or the latest release. The collection has no feature for it, and the existing third-party
feature verifies no download and fails when installed twice, which this repository's conventions forbid.

## What Changes

- A new feature `deno` installs a verified Deno CLI system-wide at the version the `version` option selects.
- Tools installed with `deno install --global` run by name for every user, and the remote user installs them without
  root.
- Unsupported images are rejected clearly.
- The repository README lists `deno` as its first feature.

The contract for the feature's behavior is `specs/deno/spec.md`.

## Capabilities

### New Capabilities

- `deno`: installing the Deno CLI, version selection, download verification, the global tools location and container
  environment, supported platforms and failure behavior, and installing twice.

### Modified Capabilities

None.

## Impact

- Feature ids touched: `deno`, new at version `1.0.0`.
- Files: `src/deno/` (`devcontainer-feature.json`, `install.sh`, `scripts/`, `NOTES.md`, generated `README.md`),
  `test/deno/` (`compatibility.json`, `test.sh`, `duplicate.sh`, `scenarios.json` with its scripts and `build` scenario
  folders), `README.md` (Features section), and, depending on an open question in design.md, `test/canary.json`.
  `openspec/specs/deno/spec.md` appears at archive.
- `test/canary.json` is a test-infrastructure path, so if it changes, CI also runs the canary set and the global
  scenarios for this change.
- No other feature, script, workflow, or knowledge file changes.

## Acceptance

**Becomes true:**

- Every scenario of the `deno` delta spec (`specs/deno/spec.md`) holds, each recorded with its result in the PR's
  Validation section: the scenarios of a successful installation on every image and architecture listed in
  `test/deno/compatibility.json`, and each failure scenario by the hand run design.md (Verifying failure scenarios)
  names for it. The issue's acceptance sketch is covered by the scenarios "Latest version", "Exact version", and
  "Different version the second time".
- `test/deno/compatibility.json` holds the images and architectures planned in design.md (Supported images), and
  `just test deno` and `just test-scenarios deno` pass on them.
- `src/deno/devcontainer-feature.json` declares id `deno` at version `1.0.0`, the metadata named in design.md and
  nothing wider, and `src/deno/README.md` is the output of `just docs`.
- The repository README's Features section lists `deno`.

**Stays true:**

- No script pipes a downloaded script into a shell, and nothing is installed from a download that was not verified.
- The feature installs no Deno packages or project dependencies at build time.
- No option takes credentials or a download URL.
- No other feature's files, versions, or specs change, and `just check` passes.
