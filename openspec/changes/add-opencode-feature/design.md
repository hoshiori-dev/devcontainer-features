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
current package is 2.1.2, with native payloads under @opencode/cli-*. npm retains integrity checking. Declare the same
Node 24 dependency and disabled extras as Codex, so co-installation shares a consistent runtime. Reject the v1
opencode-ai package and its GitHub asset names; the GitHub Latest entry is not the authoritative v2 channel.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Stable 2.x releases only; reject every other major and prereleases.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Use separate data/config/state/cache subdirectories under /var/lib/opencode, linked at the remote user's
OpenCode-specific XDG paths after mounting. Resolve each path from the effective configured XDG roots and the supported
v2 release; respect those roots without setting XDG_* globally. Never link the entire shared XDG root. Preserve full
credential/session SQL databases and WAL/SHM files in their owned directories. A v1 auth.json-only cache is
insufficient; no v1 migration is included. Test real database writes and reopen operations through the links, plus
coexistence with unrelated application directories under both default and custom XDG roots.

Resolve home paths for the actual runtime user after mounting. Create only missing links and reuse links to intended
mounted targets. Existing files, directories, dangling links, or links to other targets are actionable conflicts; do not
replace, import, or delete them. Create home links as the remote user, with privileged ownership repair confined to the
mount and never following external links or changing ownership of the home. Recreate links for each fresh container,
including when the remote-user home changes.

Metadata declares source `opencode-${devcontainerId}`, target `/var/lib/opencode`, type `volume`, an `onCreateCommand`
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

Candidate first-party routes: OpenCode VS Code extension `sst-dev.opencode` and JetBrains' built-in ACP client running
`opencode acp`. The only candidate automatic VS Code ID is `sst-dev.opencode`.

Automatic metadata is included only for a route whose container execution and state mapping are verified. Otherwise the
initial supported route is the integrated container terminal; the official integration is optional manual setup outside
the guarantee. An IDE vendor's built-in ACP client connected to an upstream agent server qualifies; community clients do
not. CLI and IDE stores may be independent. Examples preserve existing settings/registrations, and helpers never edit
the host IDE profile.

### Validation boundary

The initial compatibility list targets Debian 12 and Ubuntu 24.04 on amd64 and arm64. Only verified combinations are
advertised; Alpine and other libc families are outside this first design. Automated checks cover version selection,
executable availability, integrity failures, install-twice behavior, private state, repair, link conflicts,
default/custom path discovery, real writes and atomic replacement, and recreated home links. Isolation uses two project
identities; persistence needs two fresh containers mounting the same volume.

The ordinary scenario runner cannot express a host test with multiple containers. Record a separate manual two-container
result alongside just check, just test opencode, and just test-scenarios opencode; this introduces no CI mechanism or
changes to required checks. Fixtures/local mock providers verify state formats without live credentials. Real
authentication and each enabled IDE route require their own result, with no raw credentials or transcripts published.

## Risks / Trade-offs

- Private state can contain credentials and source text; protect the whole root and never print its contents in
  verification output.
- Upstream schemas can change; preserve whole owned directories and still verify resume for supported releases.
- Cross-host synchronization and simultaneous independent writers are outside the design.
- Package/parser checks do not prove authenticated resume. An unverified IDE route takes the terminal fallback;
  unverified CLI credential restoration remains a delivery blocker.
