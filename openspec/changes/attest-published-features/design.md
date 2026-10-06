# Design

## Context

- The decisions below are proposed to the maintainer on 2026-10-06; the change touches workflow `permissions:` and the
  release path, so it waits for the maintainer's decision (`agent-authority.md`, Escalation).
- `devcontainer features publish` (CLI 0.89.0) prints one JSON object on standard output when it finishes: a key per
  feature, holding `{ "publishedTags": [...], "digest": "sha256:…", "version": "…" }` for a version it published in that
  run and `{}` for a version that already existed. Read from the CLI's bundled source on 2026-10-06.
- `actions/attest` v4.2.2 (GitHub-owned; `actions/attest-build-provenance` v4 is a wrapper around it) creates a SLSA
  build provenance attestation, signs it with a Sigstore certificate issued for the workflow run, and stores it through
  the GitHub attestations API. It needs `id-token: write` and `attestations: write`. Its `subject-checksums` input takes
  a file of digest and name pairs and creates one attestation for all of them. Its `push-to-registry` input, off by
  default, would also store the attestation in the registry.
- `gh attestation verify oci://<ref> --repo <owner>/<repo>` resolves the reference to a digest and looks the attestation
  up through the GitHub API; `--signer-workflow` pins the workflow that signed it.
- The repository allows GitHub-owned actions (`platform-settings.md`), so no allow-list change is needed. Artifact
  attestations are available to public repositories on every current plan.
- The Release workflow runs only on `main`, so the attestation step cannot be exercised by a pull request.

## Goals / Non-Goals

**Goals:**

- A user verifies a version's origin with one command and no trust in the package's write permissions. Checked on the
  first release after the merge.
- The token that can write packages and tags is never in a job that can request a signing identity. Checked by reading
  the workflow's `permissions:` blocks.
- The step that decides what is attested is tested without a release. Checked by unit tests of the script over publish
  outputs: several published, none published, a malformed object.

**Non-Goals:**

- Attesting versions already on GHCR, the collection metadata package, or anything a feature downloads.
- Storing attestations in GHCR, SBOMs, or signing with long-lived keys.
- Documenting verification for users (#99).

## Decisions

### Attest in a separate job, from the publish job's own output

`publish` captures the JSON that `devcontainer features publish` prints and exposes the published features and their
digests as a job output. A new job `attest` depends on `publish`, has only `id-token: write` and `attestations: write`,
checks out nothing it does not need, and runs `actions/attest` over a checksums file built from that output. It is
skipped when the output names no feature.

A Deno script under `scripts/` turns the publish JSON into the subject list. It accepts only the shape described in
Context and fails on anything else, so a change in the CLI's output stops the release visibly instead of attesting the
wrong thing. It is added to `INFRA_PATHS` like the other files of the release path.

Rejected: attesting inside `publish` — one job would hold package and tag write access together with the signing
identity. Rejected: resolving digests from the registry after publishing — the run would attest whatever the tag points
to at that moment, which need not be what the run pushed.

### Subjects are the feature artifacts this run published

Each subject is named `ghcr.io/hoshiori-dev/devcontainer-features/<id>` and carries the manifest digest the CLI
reported. Versions that already existed are not attested: this run did not build them, and a provenance statement about
them would be false. The collection metadata package is left out; it installs nothing.

### Attestations stay in GitHub's attestation store

`push-to-registry` stays off. Pushing would add referrer artifacts to each feature package, and on registries without
the referrers API that takes the form of extra tags; a feature package's tags are read as versions by Dev Container
tooling, and nothing besides the CLI's publish should write to them. Verification through the GitHub API needs no
registry copy.

### A failed attestation is recovered by rolling forward

Publishing and tagging finish before `attest` starts. If `attest` fails, the run is red and the version exists without
an attestation. Rerunning only `attest` in the same run retries it with the same output. If that cannot succeed, the fix
is the repository's usual recovery: a higher version, which the next release attests. A later run never attests an
earlier run's artifact.

### Action pin

`actions/attest` is pinned by full commit SHA with its version in a comment, as `github-workflow.md` requires;
Dependabot proposes its updates.

## Risks / Trade-offs

- The first real exercise is a release on `main`. The script is unit-tested and the workflow is read carefully, but an
  error in the step's wiring shows only then, leaving that release's versions unattested until their next bump.
- Verification depends on GitHub's attestation service and on `gh`; a user without them falls back to comparing the
  artifact with the tagged source.
- An attestation proves which workflow and commit published an artifact, not that the content is harmless. The source at
  the tagged commit still has to be read.
