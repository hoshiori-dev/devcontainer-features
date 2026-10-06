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
- Since https://github.com/hoshiori-dev/devcontainer-features/pull/105, four files say that published artifacts carry no
  attestation and point at #100: `README.md` and `README.zh.md` (the limits under "Check a published version yourself"),
  `SECURITY.md`, and the accepted risks in `review-guidance.md`. `AGENTS.md` (Keep In Sync) has `README.zh.md` follow
  `README.md`, and `SECURITY.md` follow the accepted risks, in the same pull request. The README's check compares the
  artifact with the source at the tag `<id>/v<version>` using `bash`, `git`, `curl`, and `tar` only.

## Goals / Non-Goals

**Goals:**

- A user verifies, with one command and no trust in the package's write permissions, the origin of the artifact a
  version tag points to. Checked on the first release after the merge.
- The token that can write packages and tags is never in a job that can request a signing identity. Checked by reading
  the workflow's `permissions:` blocks.
- The step that decides what is attested is tested without a release. Checked by unit tests of the script over publish
  outputs: several published, none published, a malformed object, and an id or digest outside its pattern.

**Non-Goals:**

- Attesting versions already on GHCR, the collection metadata package, or anything a feature downloads.
- Storing attestations in GHCR, SBOMs, or signing with long-lived keys.
- Binding a version to its digest inside the attestation; see Risks.

## Decisions

### Attest in a separate job, from the publish job's own output

`publish` captures the JSON that `devcontainer features publish` prints and exposes the published features and their
digests as a job output. A new job `attest` depends on `publish`, has only `id-token: write` and `attestations: write`,
checks out nothing it does not need, and runs `actions/attest` over a checksums file built from that output. It is
skipped when the output names no feature.

A Deno script under `scripts/` turns the publish JSON into the subject list. It accepts only the shape described in
Context, with every feature id matching `ID_PATTERN` (`scripts/new_feature.ts`) and every digest matching `sha256:`
followed by 64 lowercase hexadecimal digits, and fails on anything else. A change in the CLI's output then stops the
release visibly instead of attesting the wrong thing, and no value can add a line to the checksums file or carry
anything but a name and a digest into the job that signs. It is added to `INFRA_PATHS` like the other files of the
release path.

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

### The documents change with the workflow

`README.md` gains the verification as its own step beside the comparison with the tagged source, and `README.zh.md`
follows. The command passes `--source-digest` with the commit of the tag `<id>/v<version>`, which the comparison has
already cloned, so it checks the version as well as the origin. The step stays apart from the comparison's commands:
those need no `gh`, and they remain the only check for a version published before this change. The limits beside it say
which versions carry an attestation and what one proves.

The accepted risk "published artifacts carry no signature or provenance attestation" leaves `review-guidance.md` and
`SECURITY.md`. Two remain in its place: a version published before this change has no attestation until its next
version, and an attestation binds a digest to its origin, not to a version tag.

Rejected: leaving the documents to a later pull request. #105 was merged with these statements pointing here, and they
turn false with the first attested release.

### Action pin

`actions/attest` is pinned by full commit SHA with its version in a comment, as `github-workflow.md` requires;
Dependabot proposes its updates.

## Risks / Trade-offs

- The first real exercise is a release on `main`. The script is unit-tested and the workflow is read carefully, but an
  error in the step's wiring shows only then, leaving that release's versions unattested until their next bump.
- Verification depends on GitHub's attestation service and on `gh`; a user without them falls back to comparing the
  artifact with the tagged source.
- An attestation binds a digest to the workflow and commit that published it, not to a version: its subject carries the
  package name and the digest, and `gh attestation verify` matches on the digest. Whoever can write to the package can
  point a version tag at another digest this workflow published, an older version for one, and the command still
  succeeds. The attestation narrows that actor from any content to content this repository released. A user who needs
  the version as well passes `--source-digest` with the commit of the tag `<id>/v<version>`, or compares the artifact
  with the tagged source, and pins the digest. The README's command does the first; the review guidance lists the rest
  as an accepted risk.
- The documents describe a command before any attestation exists. Until a feature's next version, the command finds
  nothing for it, and the README says so. If the first release shows the command or its flags to be wrong, the fix
  corrects the documents too. Whether `gh attestation verify` needs a signed-in `gh` for a public repository is checked
  then and stated in the README.
- An attestation proves which workflow and commit published an artifact, not that the content is harmless. The source at
  the tagged commit still has to be read.
