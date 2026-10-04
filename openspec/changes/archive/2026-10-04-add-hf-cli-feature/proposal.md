# Proposal

Implements [#17](https://github.com/hoshiori-dev/devcontainer-features/issues/17).

## Why

A dev container that works with Hugging Face models and datasets needs the `hf` command. Hugging Face recommends its
standalone installer for the CLI, but as documented it is a `curl | bash` of a mutable URL that installs the newest
release, edits shell rc files, and verifies nothing itself, and running it by hand in every container gives
unreproducible builds. The collection has no feature that installs the CLI the upstream way while pinning its version
and keeping the image's shell files and build inputs under control.

## What Changes

- A new feature `hf-cli` installs the Hugging Face CLI (`hf`) with the upstream standalone installer, for the remote
  user, at the `huggingface_hub` version its `version` option selects, and puts `hf` on the `PATH` of the remote user
  and root. The installation is the one the installer documents, so the CLI recognizes it as installer-managed.
- The installer comes from the upstream repository's release tag for that version and runs from a saved file, as the
  repository's rule for installer scripts allows; upstream publishes no checksum or signature for it, so its content is
  not verified, and the build log records the tag and the file's SHA-256. The version is pinned and checked after
  installation.
- The feature has no hard feature dependency. The upstream installer uses an existing supported uv, or pip when uv is
  absent; both paths install wheels from fixed PyPI sources and check index digests.
- The feature reuses a usable Python, preferring the first-party Python feature when selected. It prepares distribution
  Python and venv support only when needed, and CA certificates when missing; it never downloads or compiles Python.
- An `installSkill` option adds the upstream `hf-cli` agent skill for the remote user; enabling it for an already
  installed version generates it with that CLI without reinstalling packages.
- Build-time CLI checks and skill generation run offline, without auxiliary Hub requests or cache writes; runtime Hub
  access remains available.
- The container runs with the CLI's daily update check turned off, since the CLI is upgraded by rebuilding with another
  `version`.
- The package sources are fixed: the build environment's index or mirror settings do not apply, while a build behind a
  proxy keeps working.
- The feature has no token, login, or credential option; users authenticate after the container starts, as the issue
  requires.
- The repository's root `README.md` lists `hf-cli` under "Features": one row whose id links to `src/hf-cli/`, with a
  one-sentence description; the first row replaces "No features have been published yet.".

## Capabilities

### New Capabilities

- `hf-cli`: installing the Hugging Face CLI with the standalone installer, the installer's source, version selection and
  pinning, package verification, the installer's Python, the optional agent skill, the update-check setting, failure
  behavior, and what a second install does.

### Modified Capabilities

None.

## Impact

- Feature ids touched: `hf-cli`, new at version `1.0.0`. No other feature changes, so no other version bump.
- Files: `src/hf-cli/`, `test/hf-cli/`, the new `test/_global/` (`scenarios.json` and the `uv_and_hf_cli` scenario),
  `openspec/specs/hf-cli/spec.md` at archive, and the root `README.md` (one row under "Features").
- Canary membership in `test/canary.json` is left to the maintainer; this change does not touch it.
- Dependencies: no `dependsOn`; `installsAfter` orders after the first-party Python feature and this collection's uv
  feature when the user selects them. Both are optional.
- Users' images gain a system `python3` with `venv` where they had none, and a virtual environment and `~/.local/bin/hf`
  link in the remote user's home.
- Network at build time: the hosts in the design's URL inventory, through the build's proxy when it sets one; nothing at
  container start.

## Acceptance

**Becomes true:**

- "Default options", "Installer-managed environment", "Shell files untouched", "Omitted version", "Image without
  Python", "No cache left behind", "Anonymous request to the Hub", "Update check off", "Omitted installSkill", and "No
  token after install" in `specs/hf-cli/spec.md` pass in `test/hf-cli/test.sh` on every image and architecture in
  `test/hf-cli/compatibility.json`, and "Remote user is root or unset" there on the image without a remote user; the
  build-log line of "Omitted version" is recorded in the PR's Validation section.
- "Pinned version", "Skill enabled", and "Redirected sources in the build environment" pass as scenarios in
  `test/hf-cli/scenarios.json`, including the pip path and a separate uv combination with redirected build sources.
- "uv missing" passes in the default tests; "Existing usable Python", "First-party Python selected", and "Earlier Python
  unusable" pass in dedicated scenarios and disposable-container observations. Both pip and uv paths retain version
  pinning, wheel-only installation, verified fixed sources, proxy routing, and idempotency.
- "Different version the second time", "Skill enabled, then disabled", and "No token after install" pass in
  `test/hf-cli/duplicate.sh` on every compatibility image and architecture.
- "Packages installed with the uv feature's uv" and "Nothing left under the uv volume path" pass in the global scenario
  `uv_and_hf_cli`; from this change on, that scenario also checks the `uv` change's (#14) "Later feature runs uv" on
  every change to either feature.
- "Container with the uv volume mounted" passes in the global scenario with the explicitly selected uv feature, and its
  empty and non-empty cases are observed with the method the design's "Test fixtures" names and recorded in the PR's
  Validation section.
- "Installer fetched from its tag" is observed in a build log recorded in the PR's Validation section.
- Every failure scenario of the spec except "Digest mismatch", and "Same options twice" and "Build behind a proxy", are
  each observed with the method the design names for it and recorded in the PR's Validation section.
- "Digest mismatch" holds by the uv and pip behavior the design records and by review that the installer's environment
  carries no source or check setting but the feature's; "Options" holds by review of `devcontainer-feature.json`.
- Every URL the feature, the installer it runs, the tools they call, and its tests access, other than the pulls of the
  test images, appears in the design's URL inventory.
- The root `README.md` has one row for `hf-cli` under "## Features", its id linking to `src/hf-cli/` and a one-sentence
  description, and no longer says "No features have been published yet."; this is separate from the generated
  `src/hf-cli/README.md`.
- `just check`, `just test hf-cli`, `just test-scenarios hf-cli`, and `just test-global` pass.

**Stays true:**

- No existing feature, spec, shared script, or test changes; the `uv` feature's contract is used as it is merged.
- The feature widens nothing the container may do: no `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`,
  `init`, or lifecycle command.
- Nothing the feature installs runs or reaches the network when the container starts.
- No credential, token, or personal data enters the feature, its tests, or its build log.
