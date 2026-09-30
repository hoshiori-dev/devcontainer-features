# Proposal

Implements [#35](https://github.com/hoshiori-dev/devcontainer-features/issues/35).

## Why

`.agents/knowledge/feature-authoring.md` requires every download to be verified against a published checksum or a
signature whose key is pinned by fingerprint, and forbids `curl | sh` from an unpinned source. Applied literally, the
rule costs more than it protects:

- A checksum served from the same origin as the binary adds no protection against tampering. Whoever can change the
  binary can change the checksum, and TLS already protects the transport.
- Where upstream publishes no checksum, the only literal way to comply is a per-version hash table in the feature. That
  table breaks `latest` and needs a feature release for every upstream release, when a feature should keep working as
  upstream moves on.
- Features that install through a package manager or registry already get that tool's verification. The rule does not
  say so, so designs debate adding a second check.

The open drafts show the cost. `hf-mount` (#18, draft PR #31) reads GitHub's API asset digest and so becomes exposed to
the anonymous API rate limit. The `hf-cli` draft for #17 (not yet published) would need an exception to the rule to run
Hugging Face's documented standalone installer.

## What Changes

The download rule in `feature-authoring.md` ("install.sh") is replaced by these rules:

- **Sources.** Every URL a feature requests itself is named in its spec, uses HTTPS on every hop including redirects,
  and points to one of three places: a host the upstream controls, the release platform the upstream publishes through
  (GitHub or GitLab releases and their download redirects), or the official registry the upstream publishes to. It never
  points to a third-party mirror or repackaging. Traffic to repositories the image itself configures falls under the
  package-manager rule.
- **No weakening.** A feature never disables or weakens certificate, signature, or integrity checking, whether through a
  flag, an option, a configuration file, or an environment variable. This covers `curl`, `wget`, package managers,
  registries' clients, and installer scripts.
- **Package managers and registries.** A package fetched from a signed repository or a registry index is verified by the
  tool that fetches it, and the feature need not add a second check. A package file the feature downloads itself is a
  direct download.
- **Added repositories.** A repository the feature adds has its signing key pinned by full fingerprint and checked
  before use.
- **Direct downloads.**
  - When upstream publishes a checksum or signature for the version and asset being installed, the feature fetches it at
    install time and verifies against it.
  - A signature is checked against a key pinned by full fingerprint, or a pinned signer identity for keyless signing.
  - If upstream publishes one for that version but it is missing or unreachable at install time, the install fails.
  - When upstream publishes none for that version, the feature installs relying on TLS alone. Its spec states this as a
    Requirement.
  - A digest computed by the hosting platform rather than by upstream, such as GitHub's asset digest, may be used but is
    not required.
- **No per-version hashes.** A feature carries no hash tied to one upstream version. An exception needs a change to this
  rule.
- **Installer scripts.** An installer script that upstream documents is fetched only from an upstream location and saved
  to a file before it runs, never piped into a shell. Unless upstream publishes a checksum or signature for it, its spec
  states that the script's content is not verified. The spec also names what the script downloads.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This change edits the harness only (`skip_specs: true`).

## Impact

- Files: `.agents/knowledge/feature-authoring.md`.
- Feature ids touched: none, so no version bump. No feature exists on `main` yet.
- The approval packages already drafted against the old rule are revised in their own PRs after this one merges. For
  example, #18 (draft PR #31) can drop the API digest. Any revision reopens that PR's package gate and needs a fresh
  approval.
- CI: nothing selects container tests; the `lint` job checks the Markdown formatting.
- Out of scope: `.devcontainer/setup.sh` pipes an installer into `sh`. It is the repository's own dev container, not a
  feature, so this rule does not govern it. Changing `.devcontainer/` needs a maintainer's separate decision
  (`AGENTS.md`).

## Acceptance

**Becomes true:**

- `feature-authoring.md` states each of the seven rules under What Changes.
- No rule forces a feature release for an upstream release. Checked by reading the rules: each depends only on data
  fetched at install time or on a key fingerprint or signer identity. A key rotation is the one accepted case that needs
  a feature release.
- No harness file contradicts the new rules. Checked by reading each hit of
  `git grep -n -i -E "verify every download|curl \| ?sh|checksum|signature|fingerprint|pinned|verif"` over `.agents/`
  (excluding the generated `.agents/skills/openspec-*`), `AGENTS.md`, `README.md`, `openspec/config.yaml`,
  `scripts/new_feature.ts`, and `.github/`.

**Stays true:**

- `git diff --name-only origin/main...HEAD` lists only `.agents/knowledge/feature-authoring.md` and files under
  `openspec/changes/relax-download-verification/`. So `agent-authority.md`, `spec-workflow.md`, `AGENTS.md`,
  `openspec/config.yaml`, and CI are unchanged.
- Download sources and verification remain security-sensitive surface in `agent-authority.md`. A change to them still
  escalates to a maintainer, and the package gate still reviews downloads, checksums, and signing keys.
- Where a feature verifies nothing beyond TLS, that fact is visible at the package gate, in its spec's Requirements.
- A signing key is pinned by full fingerprint wherever a feature relies on one, both for repositories it adds and for
  signatures on direct downloads.
- `just check` passes, and every required check passes on this PR.
