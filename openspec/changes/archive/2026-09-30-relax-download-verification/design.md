# Design

## Context

- **Where the rule lives.** `feature-authoring.md` ("install.sh", lines 40–41) holds the only statement of the rule.
  - `agent-authority.md` (Escalation), `spec-workflow.md` (Approval gates), and `openspec/config.yaml` (`rules.specs`)
    name download sources, checksums, and signing keys as things to review or record.
  - None of them requires a checksum for every download.
  - `spec-workflow.md`'s example Requirement ("SHALL download from … and verify against …") shows a feature that has a
    checksum. It remains a valid example.
  - Verified with `git grep` on 2026-09-30.
- **What upstreams publish.** Research for the feature drafts, 2026-09-30:
  - glab, deno, and uv publish checksum files from the same origin as their binaries.
  - NVIDIA's container toolkit repositories are signed, and the key is published for pinning by fingerprint.
  - hf-mount publishes no checksum. The only hash is the digest GitHub computes for each release asset, read through the
    Releases API, whose anonymous limit is 60 requests an hour.
  - Hugging Face's standalone CLI installer has no checksum or signature.
- **Transport.** A feature's own downloads go over HTTPS. Package-manager traffic may use plain HTTP where the image
  configures it, for example Debian's default sources. There, integrity comes from the signed repository metadata, not
  from TLS.
- **What a same-origin checksum catches.** It detects corrupted or truncated files, and a proxy or cache serving the
  wrong bytes. It does not detect a compromised origin.

## Goals / Non-Goals

**Goals:**

- **A single statement of the rules.** Each rule names what the feature must do and where the lasting fact about a
  weaker check is recorded: the feature's spec. Checked by reading the final text against `openspec/config.yaml`'s
  `rules.specs`, which already sends verification facts to Requirements.
- **Only the one paragraph is edited.** The other `install.sh` bullets (distribution detection, non-interactive
  installs, `_REMOTE_USER`) keep their wording. Checked by `git diff` on `feature-authoring.md`: changed lines are
  limited to the download paragraph.

**Non-Goals:**

- Revising the feature drafts. Each follows in its own PR (issue Out of scope).
- Changing escalation or the gates (`agent-authority.md`, `spec-workflow.md`).
- Codifying the URL inventory that the current feature designs carry. It is a design practice, not a download rule, and
  would need its own change to `openspec/config.yaml`.

## Decisions

- **Tier by who can verify, not by threat.**
  - Package managers and registries verify what they fetch from their signed indexes. The feature's job there is never
    to weaken them.
  - A key the feature relies on is a trust root no tool can check for it, so the key stays pinned by fingerprint. This
    covers repository keys and keys that sign direct downloads.
  - For direct downloads, the feature uses what upstream publishes.

  Rejected:
  - Keeping "verify every download" with per-feature exceptions. The exceptions would outnumber the rule, and each would
    cost a policy discussion.
  - Requiring signatures only. Few upstreams sign release binaries.
- **Verify dynamically, and fail when a published checksum goes missing.** It costs one request, never needs a feature
  release, and turns a truncated download or a proxy's error page into a build failure. Failing instead of falling back
  keeps a proxy that blocks the checksum URL from turning verification off.

  Rejected:
  - Dropping checksum checks entirely. That loses cheap integrity checking.
  - A silent fallback to TLS. That makes verification depend on the network path.
- **Platform digests are optional.** A digest computed by GitHub is not published by upstream, and reading it can need
  an API with its own limits. A feature may use one when that is cheap; the rule does not require it.
- **Per-version hashes need a rule change.** They are the maintenance cost this change removes. Allowing them through
  per-feature approval would make them the easy path back.
- **Documented installer scripts, saved first.** Running a partially downloaded script is the concrete risk of
  `curl | sh`, and saving the script first removes it. What the script downloads is named in the spec, because it
  becomes part of what the feature installs.

  Rejected:
  - Forbidding installer scripts outright. The feature would re-implement the installer and drift from it.
  - Pinning the script by commit. That needs a feature release whenever the installer changes.
- **Sources include the release platform and the official registry.** GitHub release downloads redirect to GitHub's CDN,
  and PyPI and npm serve files from their own hosts. None of these is "a host the upstream controls". Naming them keeps
  the rule satisfiable without accepting arbitrary mirrors.

## Risks / Trade-offs

- [A feature verifies less than before, for example hf-mount without GitHub's digest] → Its spec says so as a
  Requirement, and the package gate reviews it. A same-origin digest never caught a compromised origin, so what is lost
  is corruption detection, and only for upstreams that publish nothing.
- [An installer script changes without a feature release and starts doing something the spec does not name] → The spec
  names what the script downloads. Tests exercise the installed result on every CI run of the feature, so a behavior
  change surfaces when the feature is next tested. Between runs it can go unnoticed, and the maintainer accepts that
  when approving an installer-based design.
- [A reader takes "need not add a second check" as permission to skip a package manager's signature settings] → The "No
  weakening" rule forbids that explicitly, and the package gate reviews every install command.
