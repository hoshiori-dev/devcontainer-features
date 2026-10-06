# Proposal

## Why

The root `README.md` tells a user how to reference a feature and little else: it gives no reason to trust a feature and
no way to check one, and its hand-maintained feature list already misses `firewall` and `colab-cli`. A human contributor
has no document of their own; the workflow lives in agent-facing knowledge files. `SECURITY.md` and the review guidance
ask for security review without saying which threats count, so findings about inputs no attacker controls are reported
next to real ones.

## What Changes

- `README.md` is rewritten for human readers, short and current in form. For users: how to reference a feature, a note
  that the collection is not in the containers.dev index yet, the feature list with a link to each feature's README, the
  development principles, and how to audit a feature instead of trusting its authors. For developers: coding agents are
  sent to `AGENTS.md`, humans to `CONTRIBUTING.md`.
- The feature list in `README.md` is generated from each feature's metadata by `just docs`, and `just check` fails when
  it is stale.
- `README.zh.md` is a Chinese translation of the finished English README, made by the coding agent and not by a script.
  The English file is authoritative, and `just check` fails when the two list different features.
- `CONTRIBUTING.md` is added for human contributors: spec-driven development with OpenSpec, where a feature's spec
  lives, the coding agents the harness supports, and the path from issue to release. It summarizes and links to the
  knowledge files; it restates no rule.
- `SECURITY.md` keeps private reporting and the latest-version-only policy and gains the threat model: what counts as a
  threat for shipped code, for test code, and for administration code, and what does not.
- The review guidance and the Copilot review skill require a security finding to name the scenario that makes it a
  threat under that model.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`; no feature's behavior changes.

## Impact

Root documents, `scripts/docs.ts` and its recipe, the knowledge files and agent entrypoint that name generated files and
review rules, and the Copilot review skill. No file under `src/` or `test/` changes, so no feature version changes.
Implements https://github.com/hoshiori-dev/devcontainer-features/issues/99 and supersedes the hand-maintained list of
https://github.com/hoshiori-dev/devcontainer-features/issues/39. Attesting published artifacts is
https://github.com/hoshiori-dev/devcontainer-features/issues/100 and is not part of this change.

## Acceptance

### Becomes true

- `README.md` shows a user how to reference a feature, states that the collection is not in the containers.dev index yet
  and that the reference is typed by hand, and lists every feature under `src/` that is not deprecated, each linking to
  its README.
- `README.md` names the development principles and the measures that exist today, and gives steps a user can follow to
  compare a published feature version with this repository's source. Every command in those steps was run and its result
  recorded in the PR's Validation section.
- `README.md` states the limits: published artifacts carry no signature or provenance attestation, and where an upstream
  publishes no checksum a download relies on TLS alone. It does not say a feature is a sandbox against a malicious
  configuration.
- `README.md` sends coding agents to `AGENTS.md` and human contributors to `CONTRIBUTING.md`.
- Adding, renaming, retiring, or re-describing a feature without running `just docs` makes `just check` fail, and so
  does a feature list in `README.zh.md` that differs from the English one.
- `README.zh.md` carries the same sections as `README.md`, in Chinese, and says the English file is authoritative.
- `CONTRIBUTING.md` covers OpenSpec and the location of a feature's spec, the supported coding agents (Codex, Google
  Antigravity, Claude Code) and what each reads, the issue-to-release workflow, and the validation commands; each rule
  it mentions links to the knowledge file that owns it.
- `SECURITY.md` states the threat model for shipped, test, and administration code. The review guidance and the Copilot
  review skill point to it and require each security finding to state its scenario under that model.
- `just check` passes.

### Stays true

- No file under `src/` or `test/` changes, and no feature version changes.
- Private vulnerability reporting and the latest-version-only support policy keep their meaning.
- The download, integrity, and "Developer trust and readability" rules in `feature-authoring.md` keep their meaning, and
  exposed secrets and private personal data remain the highest-priority review findings.
- Each rule has one owner: no rule is stated in both a human document and a knowledge file.
- `.devcontainer/`, `.pre-commit-config.yaml`, `.editorconfig`, CI workflows, required checks, lifecycle gates, and
  agent authority do not change.
- Repository content other than `README.zh.md` is English, and nothing carries secrets, private data, or tool
  attribution.
