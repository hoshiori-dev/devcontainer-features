# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/antigravity/spec.md) for the contract.
[Issue #166](https://github.com/hoshiori-dev/devcontainer-features/issues/166) holds upstream research and confirmed
boundaries. There is no existing antigravity feature. The uv volume helper is a useful reference, but its warning-only
repair result cannot establish private credential availability.

## Goals / Non-Goals

**Goals:**

- Separate application files from runtime state; check with an empty named volume and remote-user CLI execution.
- Restrict ownership repair to the state root and preserve unrelated home/XDG files; check changed-UID, symlink, and
  conflict cases.
- Keep one auditable installation route; check version resolution and integrity-failure behavior.
- Map every enabled IDE backend's container state; check process location and a recreated-container session.

**Non-Goals:**

- A shared persistence framework, host credential forwarding, or changes to existing feature behavior.
- Conditional mounts, community editor adapters, or changing upstream permission/sandbox defaults.

## Decisions

### Installation and dependencies

Resolve the official native platform manifest directly and verify its SHA-512, accepting only the distribution prefix in
the delta. This keeps the installer's verified payload route without executing mutable shell-profile edits. The
reference check fetched 1.4.4, verified SHA-512, and ran version/help and a bounded unauthenticated start in a
network-disabled Debian 12 container. The log selected file token storage because no D-Bus session existed.
GEMINI_FORCE_FILE_STORAGE was also set, but its independent effect was not proved and is not an assumed dependency. Set
documented AGY_CLI_DISABLE_AUTO_UPDATE=true by default.

### Options

None. No options: use the current verified platform manifest. A pinned-version control is omitted until an immutable
install contract is established.

### Runtime state

Map verified owned CLI directories and active plugin-secret storage into /var/lib/antigravity while preserving their
default discovery paths. The reference run observed .gemini/antigravity-cli and .config/antigravity/plugin-secrets.json;
these observations do not establish complete authenticated state coverage. Link only directories confirmed to belong
exclusively to Antigravity. Never link the whole shared .gemini or .config tree. Shared .gemini/config entries require
an upstream-supported mapping that preserves unrelated Gemini data.

Identify application-owned credential-file paths from upstream documentation/source and verify writes and atomic
replacement with synthetic fixtures; do not perform account login or credential refresh tests. A file link that an
atomic write replaces is insufficient. Document shared or external stores that cannot be mapped safely as
consumer-managed; never redirect a shared parent. No host keychain or added keyring service is required by this design.
Google-account, API-key, and ADC authentication are all allowed; external storage is consumer-managed.

Prepare only known link paths during construction; resolve runtime-only paths at container creation. Reuse links to
intended mounted targets. Existing files, directories, dangling links, or links to other targets are actionable
conflicts; preserve their contents. Runtime link creation runs as the remote user; privileged repair stays inside the
state mount and never changes home ownership.

Metadata declares source `antigravity-${devcontainerId}`, target `/var/lib/antigravity`, type `volume`, an
`onCreateCommand` initializer, and ordering after common-utils where user setup matters. It declares no entrypoint,
privileged mode, added capabilities, weakened security profile, or host-home mount. Keep private directories at 0700 and
credentials at 0600. A restrictive runtime umask protects newly created private files.

Prepare mount-point directories with private permissions during the build. Docker may copy their contents and ownership
into a new empty volume; this does not repair an existing volume or establish runtime access. A reused volume with a new
remote UID needs repair using the runtime user's identity and noninteractive sudo where necessary. Repair stays inside
the exact mount and does not follow external symlinks. If it is unavailable, return an actionable failure rather than
success, deletion, or broader access. A single profile is not promised to support simultaneous independent
owners/writers.

The devcontainerId names one configuration on one Docker host. Moving a checkout or changing configuration may select
another volume; NOTES explains inspection and explicit migration. No volume pruning or automatic import of conflicting
home content occurs.

### Initialization timing

In install.sh, use `_REMOTE_USER_HOME` for known home-relative links, not root's `~`. Build-time creation is allowed
before the target volume exists; preserve existing paths and keep account data out of image layers. Runtime-only XDG or
application overrides are resolved by the creation initializer. Mounting an entire home can hide image-prepared links,
so the initializer verifies the effective paths even when build preparation succeeded.

Use only onCreateCommand for automatic readiness work. Check the actual mount (not just directory existence), effective
paths and link targets, state-root ownership/mode, known credential-store permissions, and user read/write/search
access. Use metadata and narrowly scoped access probes without reading credentials or enumerating all conversations.
When healthy, perform no full-tree scan or recursive chown/chmod. A detected mismatch may require repair confined to the
mount under the existing ownership/privacy contract; unavailable repair fails clearly. Do not create or rewrite agent
settings or select a credential backend.

No postStartCommand or postAttachCommand is added for this purpose. The initializer remains idempotent for explicit
reruns. NOTES tells consumers to recreate the container or rerun initialization after changing users, homes, XDG roots,
or mounts. Check healthy-volume and ordinary-restart behavior alongside missing-mount, hidden-link, and changed-UID
cases.

### Editor routes

Candidate first-party routes: Google VS Code extension `Google.google-antigravity` and JetBrains AI's official
Antigravity agent route. The only candidate automatic VS Code ID is `Google.google-antigravity`.

Automatic metadata is included only for a route whose container execution and state mapping are verified. Otherwise the
initial supported route is the integrated container terminal; the official integration is optional manual setup outside
the guarantee. An IDE vendor's built-in ACP client connected to an upstream agent server qualifies; community clients do
not. CLI and IDE stores may be independent. Examples preserve existing settings/registrations, and helpers never edit
the host IDE profile.

### Validation boundary

The initial compatibility list records tested Debian 12 and Ubuntu 24.04 combinations on amd64 and arm64. It is not a
support whitelist: warn and attempt other targets covered by the selected official installation route, and report
missing coverage or actual prerequisite/execution failures clearly.

Use unattended synthetic files to test credential-file contents, private permissions, mounts, separate project
identities, atomic replacement, and recreation with the same volume. Never perform real authentication, token refresh,
browser authorization, or tests requiring API keys or human input. Do not test other authentication forms or interpret
file preservation as proof of account restoration. Preserve the existing non-authentication CLI and state tests.

A two-container check is an unattended host-side script using isolated test volumes and synthetic fixtures; no manual
login or operator step is part of acceptance. Keep the existing scenario runner and required CI checks unchanged; use
the repository's current test capabilities rather than depending on the proposed expected-build-failure metadata.

### Credential and initialization boundary

Preserve upstream credential backend defaults, user configuration, and managed policy. Map application-owned state
folders and retain credential files there; never force a file backend, provision a keyring, or rewrite authentication
settings. Initialization checks only state paths, mounts, ownership, private permissions, and access, without starting
an agent configuration service. NOTES documents retained paths and consumer-managed keyring, external files, and
environment credentials. No authentication workflow or credential-service design is included.

Validate staged executables in an isolated temporary home before replacing a working installation. Keep complete
required runtime payloads outside the state mount. Check that installation and later runtime Feature configuration do
not alter user tool versions or defaults; compare explicit, partial, and empty configurations with runtime-only
controls. Audit first-party installation entry points, artifact/registry locations, and verification sources separately
from base-image repositories and upstream-selected dependency distributors.

## Risks / Trade-offs

- Private files can contain credentials and source text; protect the state root and never print its contents.
- Upstream state layouts can change; verify directory mappings and file replacement without real account access.
- External credential stores, cross-host synchronization, and simultaneous independent writers are consumer-managed.
- File-retention checks do not establish authenticated restoration. An IDE route without verified container-side file
  mapping uses the terminal fallback.
