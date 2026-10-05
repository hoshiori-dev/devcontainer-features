# Proposal

Implements [#76](https://github.com/hoshiori-dev/devcontainer-features/issues/76), part of
[#52](https://github.com/hoshiori-dev/devcontainer-features/issues/52).

## Why

`glab`'s install script and tests were written before the shell style guide (`.agents/knowledge/shell-style.md`)
existed, so developers who audit the feature or debug a failed build read code and logs that follow no shared
convention. The #52 audit confirmed problems of the kinds #52 asked about for this feature. Some failures are unclear: a
failing package manager ends the build with only the tool's own output, most messages name a problem without saying how
to fix it, and the last log line reports a binary that cannot run as installed. The latest-release link is built inline
in three places. Comments sit in the wrong place: second-install behavior is in the script header, and decorative
dividers stand in for the step structure. Defensive handling hides what the tests check.

## What Changes

- `src/glab/install.sh` and every shell script under `test/glab/` follow the shell style guide.
- Every build-log line starts with `glab:`, and every failure with `glab: error:`. Neither ends with a period. Every
  failure a developer can fix gives the reason and then how to fix it, and still names everything the spec's scenarios
  require it to name.
- When a package-manager command fails, the build ends with a `glab: error:` line naming the package manager and how to
  fix the problem.
- Each log line for a step that uses the network or changes the image says what the step does, from where, and to where.
  The build log still shows the final URL of each download.
- The last log line reports the installed version and path without running the new binary, so it can no longer report a
  binary that does not run as installed.
- In the tests, each check states one behavior from the spec. Expected values are literals, or are computed at run time
  for a stated reason. When the latest-release link cannot be read, the test fails instead of continuing with an empty
  value. Each scenario script carries its own checks, and `test/glab/checks.sh` holds only the POSIX stand-in for the
  test library and what more than one test script uses.
- Options, download sources, verification, supported images, installed files, and what a second install does stay as
  they are.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. No behavior a Requirement in `openspec/specs/glab/spec.md` covers changes. The rewritten messages keep what the
scenarios require, so the change sets `skip_specs: true`.

## Impact

- Feature `glab`: PATCH, `1.0.0` → `1.0.1`. The change edits files under `src/glab/`, and the only behavior it changes
  is log and failure text, plus the exit status when a package manager fails. feature-authoring.md (Versions) classes
  these as fixes. No option, default, image, or install location changes.
- Files changed: `src/glab/install.sh`; `src/glab/devcontainer-feature.json` (the version only); `test/glab/checks.sh`,
  `test.sh`, `duplicate.sh`, and the eight `version_*.sh` scenario scripts.
- Files unchanged: `src/glab/NOTES.md`; `src/glab/README.md`, which `just docs` regenerates with the same content (it
  carries no version); `test/glab/scenarios.json`; `test/glab/compatibility.json`; `openspec/specs/glab/spec.md`.
- Build logs: anyone who matches the old `glab feature:` prefix in a log has to update. Nothing in this repository
  matches it.
- CI: the PR runs `glab`'s container tests on every image and architecture in its compatibility list. No workflow,
  harness, or `.devcontainer/` file changes.

## Acceptance

**Becomes true:**

- `shellcheck -o require-variable-braces,require-double-brackets` reports nothing on `src/glab/install.sh` or on any
  `*.sh` under `test/glab/`, and `just check` passes.
- A review of `src/glab/install.sh` and every `*.sh` under `test/glab/` against `.agents/knowledge/shell-style.md` finds
  no unmarked deviation; every deliberate one carries a comment giving its reason.
- Every line `install.sh` writes, other than the output of the commands it runs, starts with `glab:`, or with
  `glab: error:` for a failure, and none ends with a period.
- Every failure that the option value, the platform, the package manager, a download, verification, or the archive
  layout causes states a reason, then `;`, then how to fix it.
- Every failure scenario of `openspec/specs/glab/spec.md` still produces a message naming what that scenario requires.
  The design lists the manual checks; each is re-run once, and the results are recorded in the PR's Validation section.
- When a package-manager update or install command fails, the build ends with a `glab: error:` line naming the package
  manager.
- The last line of a successful install names the installed version and `/usr/local/bin/glab`, and `install.sh` does not
  run the new binary after installing it.
- The build log still shows the final URL of each download, as `src/glab/NOTES.md` states.
- No test script swallows a failure to read the latest-release link, no scenario script sources another test script, and
  every assertion in `test/glab/checks.sh` is used by more than one test script.
- `src/glab/devcontainer-feature.json` has version `1.0.1`, and `src/glab/README.md` matches what `just docs` generates.
- `just test glab` and `just test-scenarios glab` pass locally, and the PR's container test jobs pass on amd64 and
  arm64.

**Stays true:**

- No download source changes: `install.sh` and the tests request exactly the URLs in the design's URL inventory.
- TLS and HTTPS-only transport stay as they are, on the request and on every redirect. Checksum verification against the
  release's `checksums.txt` is unchanged. The release publishes no signature, so there is still none to verify.
- Every Requirement and Scenario in `openspec/specs/glab/spec.md` still holds unchanged, including the explicitly empty
  `version` that must fail.
- The feature still installs twice: `duplicate.sh` passes, and the "Installing twice" requirement holds.
- The `version` option keeps its name, type, default, and proposals.
- The installed file, the prerequisites the feature installs, the package-manager cache cleanup, and the temporary and
  staging names the tests look for stay as they are. `test/glab/compatibility.json` and `test/glab/scenarios.json` are
  unchanged.
- Nothing changes outside `src/glab/`, `test/glab/`, and this change.
