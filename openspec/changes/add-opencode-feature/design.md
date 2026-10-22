# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/opencode/spec.md) for the contract.
[Issue #165](https://github.com/hoshiori-dev/devcontainer-features/issues/165) holds upstream research and confirmed
boundaries. There is no existing opencode feature. The uv volume helper is a useful reference, but its warning-only
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

Use @opencode/cli from its official npm registry, resolving a stable 2.x version before installation. The observed
current package is 2.1.2, with native payloads under @opencode/cli-*. npm retains integrity checking. Do not inherit the
obsolete Codex shared Node 24 dependency design. Determine whether the supported npm launcher requires Node even when
its payload is native; if required, isolate that runtime without injecting shared Node Feature options or changing user
toolchains. Verify the runtime source and integrity before implementation. Reject the v1 opencode-ai package and its
GitHub asset names; the GitHub Latest entry is not the authoritative v2 channel.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Stable 2.x releases only; reject every other major and prereleases.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Use separate data/config/state/cache subdirectories under /var/lib/opencode, linked at the remote user's
OpenCode-specific XDG paths when their effective roots are known. Resolve each path from the effective configured XDG
roots and the supported v2 release; respect those roots without setting XDG_* globally. Never link the entire shared XDG
root. Preserve full credential/session SQL databases and WAL/SHM files in their owned directories. A v1 auth.json-only
cache is insufficient; no v1 migration is included. Test real database writes and reopen operations through the links,
plus coexistence with unrelated application directories under both default and custom XDG roots.

Prepare only known link paths during construction; resolve runtime-only paths at container creation. Reuse links to
intended mounted targets. Existing files, directories, dangling links, or links to other targets are actionable
conflicts; preserve their contents. Runtime link creation runs as the remote user; privileged repair stays inside the
state mount and never changes home ownership.

Metadata declares source `opencode-${devcontainerId}`, target `/var/lib/opencode`, type `volume`, an `onCreateCommand`
initializer, and ordering after common-utils where user setup matters. It declares no entrypoint, privileged mode, added
capabilities, weakened security profile, or host-home mount. Keep private directories at 0700 and credentials at 0600. A
restrictive runtime umask protects newly created private files.

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

Candidate first-party routes: OpenCode VS Code extension `sst-dev.opencode` and JetBrains' built-in ACP client running
`opencode acp`. The only candidate automatic VS Code ID is `sst-dev.opencode`.

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
