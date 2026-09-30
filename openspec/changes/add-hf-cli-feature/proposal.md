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
- The installer comes from the upstream repository's release tag for that version; the version is pinned and checked
  after installation. The installer itself has no upstream checksum or signature, so this falls short of the
  repository's download-verification rule; whether that is accepted is the design's first open question.
- The feature depends on the `uv` feature, so the installer installs `huggingface_hub` and its dependencies through uv,
  which checks every package file against the digests the Python Package Index publishes; the installer's own upgrade of
  `pip` is checked by pip against the same index digests. The installation writes nothing under the `uv` feature's
  volume path.
- The feature adds the distribution's `python3`, `python3-venv`, and `ca-certificates` when the image lacks them.
- An `installSkill` option lets the installer add the upstream `hf-cli` agent skill for the remote user.
- The container runs with the CLI's daily update check turned off, since the CLI is upgraded by rebuilding with another
  `version`; the design's open questions include whether to keep this.
- The feature has no token, login, or credential option; users authenticate after the container starts, as the issue
  requires.

## Capabilities

### New Capabilities

- `hf-cli`: installing the Hugging Face CLI with the standalone installer, the installer's source, version selection and
  pinning, package verification, the installer's Python, the optional agent skill, the update-check setting, failure
  behavior, and what a second install does.

### Modified Capabilities

None.

## Impact

- Feature ids touched: `hf-cli`, new at version `1.0.0`. No other feature changes, so no other version bump.
- Files: `src/hf-cli/`, `test/hf-cli/`, the new `test/_global/` (`scenarios.json` and the `uv_and_hf_cli` scenario), and
  `openspec/specs/hf-cli/spec.md` at archive. `test/canary.json` gains `hf-cli`, the first feature with an in-repo
  `dependsOn`, as `.agents/knowledge/testing.md` asks (design, open questions).
- Dependencies: `dependsOn` the `uv` feature (`ghcr.io/hoshiori-dev/devcontainer-features/uv:1`). The implementation
  waits until the `uv` feature (#14) is merged; from then on, CI re-tests `hf-cli` whenever `uv` changes.
- Users' images gain a system `python3` with `venv` where they had none, and a virtual environment and `~/.local/bin/hf`
  link in the remote user's home.
- Network at build time: the hosts in the design's URL inventory; nothing at container start.

## Acceptance

**Becomes true:**

- "Default options", "Installer-managed environment", "Shell files untouched", "Latest resolves to a stable release",
  "Image without Python", "No cache left behind", "Anonymous request to the Hub", "Update check off", "Skill disabled",
  and "No token after install" in `specs/hf-cli/spec.md` pass in `test/hf-cli/test.sh` on every image and architecture
  in `test/hf-cli/compatibility.json`, and "Remote user is root or unset" there on the image without a remote user; the
  build-log line of "Latest resolves to a stable release" is recorded in the PR's Validation section.
- "Pinned version", "Skill enabled", and "Redirected sources in the build environment" pass as scenarios in
  `test/hf-cli/scenarios.json`.
- "Different version the second time", "Skill enabled, then disabled", and "No token after install" pass in
  `test/hf-cli/duplicate.sh` on every compatibility image and architecture.
- "Packages installed with the uv feature's uv" and "Nothing left under the uv volume path" pass in the global scenario
  `uv_and_hf_cli`; from this change on, that scenario also checks the `uv` change's (#14) "Later feature runs uv" on
  every change to either feature.
- "Container with the uv volume mounted" passes in `test.sh` with the `uv` feature's volume, and its non-empty case, and
  any mounted-volume scenario the test runner cannot mount, is observed with the method the design's "Test fixtures"
  names and recorded in the PR's Validation section.
- "Installer fetched from its tag" is observed in a build log recorded in the PR's Validation section.
- Every failure scenario of the spec except "Digest mismatch", and "Same options twice", is observed with the method the
  design names for it and recorded in the PR's Validation section.
- "Digest mismatch" holds by the uv and pip behavior the design records and by review that the installer's environment
  carries no source or check setting but the feature's; "Options" holds by review of `devcontainer-feature.json`.
- Every URL the feature, the installer it runs, the tools they call, and its tests access, other than the pulls of the
  test images, appears in the design's URL inventory.
- `test/canary.json` lists `hf-cli` (design, Open Questions, item 8).
- `just check`, `just test hf-cli`, `just test-scenarios hf-cli`, and `just test-global` pass.

**Stays true:**

- No existing feature, spec, or shared script changes, and no existing test except the canary list; the `uv` feature's
  contract is used as it is merged.
- The feature widens nothing the container may do: no `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`,
  `init`, or lifecycle command.
- Nothing the feature installs runs or reaches the network when the container starts.
- No credential, token, or personal data enters the feature, its tests, or its build log.
