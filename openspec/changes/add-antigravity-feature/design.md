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

Map owned CLI directories and active plugin-secret storage into /var/lib/antigravity. The reference run observed
.gemini/antigravity-cli and .config/antigravity/plugin-secrets.json. Shared .gemini/config entries need ownership-aware
mapping that preserves unrelated Gemini data. Establish the actual account-token and refresh-write paths during the
authentication feasibility test; do not assume a legacy filename. No host keychain or added keyring service is required
by this design.

Metadata declares source `antigravity-${devcontainerId}`, target `/var/lib/antigravity`, type `volume`, an
`onCreateCommand` initializer, and ordering after common-utils where user setup matters. It declares no entrypoint,
privileged mode, added capabilities, weakened security profile, or host-home mount. Initialize mappings and nonsecret
defaults after mounting, with private directories at 0700 and credentials at 0600. A restrictive runtime umask protects
newly created private files.

Docker copy-up preserves prepared directory ownership for a fresh volume. A reused volume with a new remote UID needs
repair using the runtime user's identity and noninteractive sudo where necessary. Repair stays inside the exact mount
and does not follow external symlinks. If it is unavailable, return an actionable failure rather than success, deletion,
or broader access. A single profile is not promised to support simultaneous independent owners/writers.

The devcontainerId names one configuration on one Docker host. Moving a checkout or changing configuration may select
another volume; NOTES explains inspection and explicit migration. No volume pruning or automatic import of conflicting
home content occurs.

### Editor routes

Candidate first-party routes: Google VS Code extension `Google.google-antigravity` and JetBrains AI's official
Antigravity agent route. The only candidate automatic VS Code ID is `Google.google-antigravity`.

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
result alongside just check, just test antigravity, and just test-scenarios antigravity; this introduces no CI mechanism
or changes to required checks. Fixtures/local mock providers verify state formats without live credentials. Real
authentication and each enabled IDE route require their own result, with no raw credentials or transcripts published.

## Risks / Trade-offs

- Private state can contain credentials and source text; protect the whole root and never print its contents in
  verification output.
- Upstream schemas can change; preserve whole owned directories and still verify resume for supported releases.
- Cross-host synchronization and simultaneous independent writers are outside the design.
- Package/parser checks do not prove authenticated resume. An unverified IDE route takes the terminal fallback;
  unverified CLI credential restoration remains a delivery blocker.

### Account-restoration evidence still required

No Google account was used in the reference run. Delivery requires controlled OAuth login followed by a fresh CLI
process and a fresh container with the same volume, usable token refresh, and saved-conversation resume. Distinguish
account-eligibility failures from storage failures. Publish only the result summary. Failed account restoration cannot
be substituted with API-key/ADC mode or declared passed from backend-selection logs.
