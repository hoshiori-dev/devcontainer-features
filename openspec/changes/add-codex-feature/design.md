# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/codex/spec.md) for the contract.
[Issue #163](https://github.com/hoshiori-dev/devcontainer-features/issues/163) holds upstream research and confirmed
boundaries. There is no existing codex feature. The uv volume helper is a useful reference, but its warning-only repair
result cannot establish private credential availability.

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

Use the documented @openai/codex npm package in a feature-owned application prefix. npm verifies registry integrity for
the package and platform payloads. Declare ghcr.io/devcontainers/features/node:2 with Node 24, node-gyp extras disabled,
and pnpmVersion=none. A registry route costs a Node runtime but avoids adding a separate Sigstore verification toolchain
and maintaining direct GitHub asset selection. The node feature's current metadata is major 2 and its version option
accepts 24.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Any stable package release that satisfies the declared target contract.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Set CODEX_HOME=/var/lib/codex. Initialize a minimal runtime config.toml selecting file credentials, preserving
compatible existing settings. A managed policy prohibiting file storage is an actionable conflict. Retain auth.json,
history, complete session stores and companion files; sharing this directory with an IDE is convenient rather than
required.

Metadata declares source `codex-${devcontainerId}`, target `/var/lib/codex`, type `volume`, an `onCreateCommand`
initializer, and ordering after common-utils where user setup matters. It declares no entrypoint, privileged mode, added
capabilities, weakened security profile, or host-home mount. Initialize mappings and nonsecret defaults after mounting,
with private directories at 0700 and credentials at 0600. A restrictive runtime umask protects newly created private
files.

Docker copy-up preserves prepared directory ownership for a fresh volume. A reused volume with a new remote UID needs
repair using the runtime user's identity and noninteractive sudo where necessary. Repair stays inside the exact mount
and does not follow external symlinks. If it is unavailable, return an actionable failure rather than success, deletion,
or broader access. A single profile is not promised to support simultaneous independent owners/writers.

The devcontainerId names one configuration on one Docker host. Moving a checkout or changing configuration may select
another volume; NOTES explains inspection and explicit migration. No volume pruning or automatic import of conflicting
home content occurs.

### Editor routes

Candidate first-party routes: Codex VS Code extension `openai.chatgpt` and JetBrains' official Codex integration. The
only candidate automatic VS Code ID is `openai.chatgpt`.

Automatic metadata is included only for a route whose container execution and state mapping are verified. Otherwise the
initial supported route is the integrated container terminal; the official integration is optional manual setup outside
the guarantee. An IDE vendor's built-in ACP client connected to an upstream agent server qualifies; community clients do
not. CLI and IDE stores may be independent. Examples preserve existing settings/registrations, and helpers never edit
the host IDE profile.

### Validation boundary

The initial compatibility list targets Debian 12 and Ubuntu 24.04 on amd64 and arm64. Only verified combinations are
advertised; Alpine and other libc families are outside this first design. Automated checks cover version selection,
executable availability, integrity failures, install-twice behavior, private state, repair, and conflicts. Isolation
uses two project identities; persistence needs two fresh containers mounting the same volume.

The ordinary scenario runner cannot express a host test with multiple containers. Record a separate manual two-container
result alongside just check, just test codex, and just test-scenarios codex; this introduces no CI mechanism or changes
to required checks. Fixtures/local mock providers verify state formats without live credentials. Real authentication and
each enabled IDE route require their own result, with no raw credentials or transcripts published.

## Risks / Trade-offs

- Private state can contain credentials and source text; protect the whole root and never print its contents in
  verification output.
- Upstream schemas can change; preserve whole owned directories and still verify resume for supported releases.
- Cross-host synchronization and simultaneous independent writers are outside the design.
- Package/parser checks do not prove authenticated resume. An unverified IDE route takes the terminal fallback;
  unverified CLI credential restoration remains a delivery blocker.
