# Design

## Context

See [proposal.md](proposal.md) for the outcome and [specs/quarto/spec.md](specs/quarto/spec.md) for the contract. The
collection already has independent `uv` and `latex` Features. Quarto's official Linux tarball supports a common
installation layout across the three selected distributions, avoiding separate deb and rpm installation logic.

Research on 2026-10-21 found that the latest-release API selected `v1.10.19`, with both Linux architecture tarballs and
`quarto-1.10.19-checksums.txt`. Website download content also displayed newer version information; the GitHub API is the
chosen authority for stable release selection, rather than scraping that content. No researched release is hard-coded as
the value of `latest`.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- A root-owned tree and one system symlink identify the active release. Root and non-root smoke tests verify command
  availability and permissions.
- Replacement uses a verified temporary tree and retains the prior managed tree until the new CLI passes its version
  check. Failure scenarios verify that unsuccessful replacement preserves the previous CLI.
- Ownership is explicit: a root-owned marker inside `/opt/quarto` records this Feature's provenance and installed
  version. Conflict scenarios cover unmanaged paths, commands, broken symlinks, and matching-version foreign installs.
- The full official bundle stays together; bundled Deno, Pandoc, and other helpers remain private to Quarto. Command
  checks confirm that the Feature exposes only `quarto`.
- Optional Python and TeX composition changes documentation and scenarios, not the `uv` or `latex` implementation.
  Review the diff and exercise the documented examples in composition scenarios.

**Excluded approaches:**

- No source build, upstream shell installer, added package repository, or distribution-specific Quarto package. Download
  review and install scenarios verify the single tarball path.
- No user-writable CLI installation or persistent volume. Metadata and permission checks verify this boundary.

## Decisions

### Option interface

| Name      | Type     | Default  | Enum / proposals           | Meaning                                                    |
| --------- | -------- | -------- | -------------------------- | ---------------------------------------------------------- |
| `version` | `string` | `latest` | No enum; proposal `latest` | Latest stable or exact stable release, optional leading v. |

`latest` keeps the zero-configuration path useful; exact releases support reproducible builds. Normalize an optional
leading `v` only for exact versions. Reject partial versions and prerelease syntax; check the upstream `prerelease` flag
even for a numeric-looking tag. Separate preview channels and companion-install booleans were rejected during interface
confirmation because those are outside the selected scope.

### Downloads and trust

Use the official release API, tarball, and SHA-256 checksum locations defined in the spec. The API returns release
identity and asset availability, including whether a numeric tag is a prerelease. Download the checksum list and match
exactly one entry for the chosen archive before extraction. The checksum list and metadata rely on TLS; no independent
publisher signature is claimed. API failure, rate limiting, missing assets, missing checksums, and mismatch are errors,
with no fallback to an unchecked archive. GitHub's optional asset digest is not a prerequisite.

Deb/rpm packages were rejected because they require different installation and replacement paths. An installer script
would add an execution and download surface without improving the single-bundle installation.

### Managed installation and conflicts

Use `/opt/quarto` for the extracted bundle and `/usr/local/bin/quarto` for the symlink. Only a tree with the Feature's
root-owned provenance marker qualifies as managed; an existing foreign command remains a conflict even when its version
matches. Check command resolution for root's installation environment and the configured remote user's normal PATH. The
check discovers commands and links without executing a foreign Quarto executable. An occupied destination without valid
provenance fails before replacement.

Compare the selected version with the managed marker and CLI version. A healthy matching installation needs no archive
download. An unhealthy managed installation can be repaired with a fresh verified bundle. Stage changes on the same
filesystem as the managed tree so replacement and rollback can use renames. Validate the staged executable before
activation and retain the old tree until the active executable succeeds. Cleanup removes temporary and backup trees only
after their replacement succeeds. Keeping multiple releases, reusing foreign installs, and overriding an existing
command were rejected during behavior confirmation.

### Platform and test bounds

The initial compatibility candidates match existing collection images:
`mcr.microsoft.com/devcontainers/base:ubuntu24.04` as `vscode`, `debian:12`, and `fedora:44`, each on amd64 and arm64.
The compatibility list is the support authority; implementation must verify these candidates on their native
architectures. All feature scenarios select both architectures. Unsupported platforms include Alpine/musl; no
compatibility shim is installed.

Use the image's existing apt or dnf repositories for missing prerequisites, including curl, CA certificates, tar, gzip,
SHA-256 verification, JSON parsing, and any runtime libraries the selected bundle requires. No package repository or
signing key is added. Runtime feasibility is checked with actual CLI execution and HTML rendering on minimal images.
System prerequisites installed by the Feature remain installed; temporary archives and package-manager caches are
removed.

Cover exact versions with and without a leading `v`, invalid and unavailable versions, numeric prereleases, managed
same-version installs, upgrades and downgrades, renewed `latest` resolution, conflicts, and failed replacements. Use
controlled release/download fixtures for deterministic metadata and failure cases; real-release installation tests
exercise the official paths. Keep test helpers local to `test/quarto/` rather than adding a collection-wide abstraction.

### Documentation and editor integration

`NOTES.md` recommends adding this collection's `uv:1` alongside `quarto:1`. For an existing uv project, the intended
example installs project-local dependencies with `uv add --dev jupyter`, then uses `uv run quarto check jupyter` and
`uv run quarto render example.qmd`. A new-project example explains `uv init` first. Explicitly select the project
interpreter with `QUARTO_PYTHON` if discovery would otherwise choose another environment. The documented workflow must
render a minimal Python cell in a composition scenario before it is claimed to work.

The optional PDF example adds `latex:1`, uses the TeX installation that Feature places on the remote user's PATH, and
renders a simple document with `quarto render example.qmd --to pdf`. It must not invoke `quarto install tinytex`; where
needed, configure Quarto's `latex-tinytex: false` to select the external TeX environment. Verify the exact example in a
composition scenario. These references are full GHCR references in documentation and tests, with the existing major
tags, and add no `dependsOn` or `installsAfter` relationship.

Only `quarto.quarto` is requested in VS Code customizations. No editor settings or language extensions are added.

## Risks / Trade-offs

- API rate limits can stop an otherwise valid installation. Report the metadata failure clearly; a matching installation
  still requires successful version resolution, especially for `latest`.
- A checksum obtained through the same release channel cannot detect compromise of that channel. The spec records the
  unsigned checksum trust boundary rather than presenting it as independent authentication.
- Bundled helpers can change their runtime requirements between Quarto releases. Native compatibility tests and explicit
  version-selection errors provide evidence for the supported image/release combinations; no universal guarantee for
  every historical release is made.
- Documentation composition scenarios add Python and TeX downloads to testing. They validate the promised examples
  without making those downloads part of the Quarto Feature's default installation.
