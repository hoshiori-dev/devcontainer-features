# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/hermes-agent/spec.md) for the contract.
[Issue #168](https://github.com/hoshiori-dev/devcontainer-features/issues/168) holds upstream research and confirmed
boundaries. There is no existing hermes-agent feature. The uv volume helper is a useful reference, but its warning-only
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

Resolve a stable release (minimum 0.22.2) to its immutable GitHub commit and fetch its matching official source
installer. Use an explicit application directory outside HERMES_HOME, immutable --commit, and
noninteractive/browser/computer-use skip flags. Preserve PM's pinned Python 3.14, Node, uv, and package integrity
checks; include the release's supported ACP capability. The Linux lock delegates runtime artifacts to GitHub
distributions and official Node, plus package registries and the upstream-selected FFmpeg build. These origins and their
checks remain controlled by the selected source commit. Reject an arbitrary moving branch, an unrelated PyPI package, or
a separate unpinned pip bootstrap.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Stable releases at or above 0.22.2, expressed as MAJOR.MINOR.PATCH; no arbitrary commit option.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Leave HERMES_HOME unset by the feature. Locate the supported release's default home in an isolated remote-user home and
link that whole directory to /var/lib/hermes-agent. Retain the whole profile: .env, auth.json, config.yaml, state.db and
companions, memories, skills, sessions, and other durable files. Verify actual saves, configuration replacement,
credential refresh, and enabled ACP discovery through the link. A release that cannot preserve complete required state
through this mapping is unsupported; do not silently switch to a global environment override.

Use an explicit application installation path outside the default home and state volume for the source checkout,
dependencies, and runtimes. Verify an empty volume cannot hide the executable or trigger a second source installation
under the default home. No desktop product, messaging daemon, browser stack, or nested Docker tool backend is enabled.

Resolve home paths for the actual runtime user after mounting. Create only missing links and reuse links to intended
mounted targets. Existing files, directories, dangling links, or links to other targets are actionable conflicts; do not
replace, import, or delete them. Create home links as the remote user, with privileged ownership repair confined to the
mount and never following external links or changing ownership of the home. Recreate links for each fresh container,
including when the remote-user home changes. Caller-provided HERMES_HOME is a conflict requiring consumer resolution;
never rewrite or unset it. Distinguish caller settings from any feature-owned fallback setting.

Metadata declares source `hermes-agent-${devcontainerId}`, target `/var/lib/hermes-agent`, type `volume`, an
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

Candidate first-party routes: VS Code's container terminal and JetBrains' built-in ACP client running the official
`hermes acp` server. No VS Code extension is automatically installed.

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
result alongside just check, just test hermes-agent, and just test-scenarios hermes-agent; this introduces no CI
mechanism or changes to required checks. Fixtures/local mock providers verify state formats without live credentials.
Real authentication and each enabled IDE route require their own result, with no raw credentials or transcripts
published.

## Risks / Trade-offs

- Private state can contain credentials and source text; protect the whole root and never print its contents in
  verification output.
- Upstream schemas can change; preserve whole owned directories and still verify resume for supported releases.
- Cross-host synchronization and simultaneous independent writers are outside the design.
- Package/parser checks do not prove authenticated resume. An unverified IDE route takes the terminal fallback;
  unverified CLI credential restoration remains a delivery blocker.
