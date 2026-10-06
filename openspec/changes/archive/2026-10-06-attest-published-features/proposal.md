# Proposal

## Why

A user who wants to check a published feature version can compare the GHCR artifact with `src/<id>/` at the tag
`<id>/v<version>`, but nothing proves where the artifact was built: anyone able to push to the package could publish
other content under the same version. A signed provenance attestation lets a user verify, with one command, that the
artifact a version tag points to was published by this repository's Release workflow from a commit on `main`.

## What Changes

- The Release workflow attests the build provenance of every feature version it publishes, signed through GitHub's
  artifact attestations and stored with this repository.
- The attestation covers the feature artifacts a run publishes itself. Versions published before this change stay
  without one until their next version.
- The knowledge base records the new job, its permissions, and how a failed attestation is recovered.
- `README.md`, `README.zh.md`, `SECURITY.md`, and the accepted risks in the review guidance stop saying that published
  artifacts carry no attestation. They say how to verify one, what it proves, and what stays accepted.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This harness change sets `skip_specs: true`; no feature's behavior changes.

## Impact

`.github/workflows/release.yml`, one administration script with its tests, the knowledge files that describe the release
path, the repository's settings, and the accepted risks, and the human documents that mirror them: `README.md`,
`README.zh.md`, and `SECURITY.md`. The workflow gains the `id-token: write` and `attestations: write` permissions in one
job and one more GitHub-owned action. No file under `src/` or `test/` changes, so no feature version changes and this
change publishes nothing by itself. Implements https://github.com/hoshiori-dev/devcontainer-features/issues/100.

## Acceptance

### Becomes true

- A Release run that publishes at least one feature version creates a provenance attestation whose subjects are exactly
  the feature artifacts that run published, each named `ghcr.io/hoshiori-dev/devcontainer-features/<id>` with the digest
  the registry holds for that version.
- For such a version,
  `gh attestation verify oci://ghcr.io/hoshiori-dev/devcontainer-features/<id>:<version> --repo hoshiori-dev/devcontainer-features --signer-workflow hoshiori-dev/devcontainer-features/.github/workflows/release.yml`
  succeeds. This can only be observed on the first release after the merge; its result is recorded on the issue.
- A Release run that publishes nothing creates no attestation and succeeds.
- A run whose attestation fails is red, and the knowledge base says how to recover.
- The knowledge base names the job, its permissions, and the action it uses.
- `README.md` shows the verification command beside the comparison with the tagged source, and says which versions carry
  an attestation and that it proves the origin of a digest, not its version. `README.zh.md` says the same.
- The accepted risks in `.agents/knowledge/review-guidance.md` and in `SECURITY.md` name what stays accepted in place of
  the missing attestation; no file says that published artifacts carry none.
- `just check` passes.

### Stays true

- The job that holds `packages: write` and `contents: write` receives no `id-token` permission, and the job that attests
  holds no write access to packages or repository contents.
- `verify` still runs first and without any write token; publishing and tagging behave as before, and a published
  version is still tagged when its attestation fails.
- Nothing is pushed to GHCR besides what `devcontainer features publish` pushes, so the tags of a feature package stay
  version tags only.
- Every action is pinned by full commit SHA, and only GitHub-owned actions are added.
- No secret is introduced; the workflow keeps using `GITHUB_TOKEN`.
- Rulesets, required checks, lifecycle gates, and agent authority do not change.
