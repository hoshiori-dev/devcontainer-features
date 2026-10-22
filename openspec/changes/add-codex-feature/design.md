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
the package and platform payloads. Keep the npm route and provide a private Node 24 bootstrap runtime at
`/usr/local/share/codex-runtime`, outside both user Node installations and the state volume. Invoke its Node/npm and
Codex launcher through explicit paths; never register it with NVM or expose it through global PATH or shell profiles.
Use this same private runtime for native configuration helpers, so later user Node changes cannot break initialization.

Fetch official Linux runtime archives from `https://nodejs.org/dist/`, verify their corresponding official
`SHASUMS256.txt` before extraction or execution, and retain normal TLS verification. Resolve the Node 24 release from
the official release directory, then use its versioned archive URL to avoid a moving-alias download race. Reuse a valid
private runtime on repeated installation. Missing platform payloads or runtime execution failures remain real upstream
errors; they are distinct from an untested-target warning. Obtain missing download/extraction prerequisites through an
available distribution package manager, with a clear error when this is not possible.

The previous shared Node Feature dependency is rejected because different options are separate installation nodes, not
an override merge. With CLI 0.89.0, both explicit Node 22 and an empty Node options object resolve before Codex's Node
24 dependency. That second installation can replace the user's active runtime and default alias. An empty shared
dependency would still conflict with explicitly configured Node instances. Requiring consumers to supply Node would
remove standalone installation; the private runtime preserves it without changing user Node configuration.

Sources for this decision:

- [Feature dependency equality and option resolution](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md#definition-feature-equality)
- [Official Node Feature defaults](https://github.com/devcontainers/features/blob/main/src/node/devcontainer-feature.json)
- [Node release downloads and verification](https://nodejs.org/en/download)

Do not declare `dependsOn` for the shared Node Feature. Ordering after a user Node Feature may use `installsAfter`,
without injecting options. Validate explicit tool versions, partially specified options, and an empty options object;
check the upstream default NVM alias and tool availability, not just a coincidentally equal Node major version. A
separate two-stage image check installs Codex first and then the actual Node Feature to verify later reconfiguration.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Any stable package release that satisfies the declared target contract.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Leave CODEX_HOME unset by the feature. Resolve the intended remote user's home and prepare `~/.codex -> /var/lib/codex`.
This preserves the default path expected by Codex and tools that install skills there. Initialize a minimal runtime
config.toml selecting file credentials, preserving compatible existing settings. A managed policy prohibiting file
storage is an actionable conflict. Retain the entire directory, including auth.json, history, complete session stores
and companion files, and skills; sharing this directory with an IDE is convenient rather than required. The separate
`~/.agents/skills` discovery location is unchanged and is not persisted by this volume.

An absent link is created; an existing link to the intended mount is reused. A regular file, directory, dangling link,
or link to another target is an actionable conflict: do not replace, import, or delete it. An explicitly configured
CODEX_HOME is also a conflict requiring consumer resolution; do not rewrite or unset it. Creation-time initialization
verifies the effective home and fills any missing link; privileged repair is restricted to the mounted state root and
never changes the user's home ownership.

Metadata declares source `codex-${devcontainerId}`, target `/var/lib/codex`, type `volume`, an `onCreateCommand`
initializer, and ordering after common-utils where user setup matters. It declares no entrypoint, privileged mode, added
capabilities, weakened security profile, or host-home mount. Initialize missing nonsecret defaults after mounting, with
private directories at 0700 and credentials at 0600. A restrictive runtime umask protects newly created private files.

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
mount under the existing ownership/privacy contract; unavailable repair fails clearly. Initialize only absent defaults.

No postStartCommand or postAttachCommand is added for this purpose. The initializer remains idempotent for explicit
reruns. NOTES tells consumers to recreate the container or rerun initialization after changing users, homes, XDG roots,
or mounts. Check healthy-volume and ordinary-restart behavior alongside missing-mount, hidden-link, and changed-UID
cases.

### Editor routes

Candidate first-party routes: Codex VS Code extension `openai.chatgpt` and JetBrains' official Codex integration. The
only candidate automatic VS Code ID is `openai.chatgpt`.

Automatic metadata is included only for a route whose container execution and state mapping are verified. Otherwise the
initial supported route is the integrated container terminal; the official integration is optional manual setup outside
the guarantee. An IDE vendor's built-in ACP client connected to an upstream agent server qualifies; community clients do
not. CLI and IDE stores may be independent. Examples preserve existing settings/registrations, and helpers never edit
the host IDE profile.

### Validation boundary

The initial compatibility list records verified Debian 12 and Ubuntu 24.04 combinations on amd64 and arm64. It is not an
allowlist: warn and attempt normal installation on other targets. Test that unlisted target metadata reaches an actual
installation attempt; do not assert early rejection solely because a distribution or architecture is unlisted. Missing
assets, failed checksums, missing prerequisites, and incompatible executables still fail with the actual diagnostic. No
success guarantee is added for Alpine or other libc families. Automated checks cover version selection, executable
availability, integrity failures, install-twice behavior, private state, repair, home-link recreation, unchanged skill
paths, explicit CODEX_HOME conflicts, existing-path conflicts, and the Node isolation scenarios. Keep the CI test
architecture unchanged; use normal feature scenarios for composition and a separate two-stage image result for later
Node installation. Isolation uses two project identities; persistence needs two fresh containers mounting the same
volume.

The ordinary scenario runner cannot express a host test with multiple containers. Record a separate manual two-container
result alongside just check, just test codex, and just test-scenarios codex; this introduces no CI mechanism or changes
to required checks. Fixtures/local mock providers verify state formats without live credentials. Each enabled IDE route
requires its own result, with no raw credentials or transcripts published. The maintainer waived real-account
restoration verification for this change on 2026-10-22; retain that explicit exception without presenting fixture
results as proof of authenticated restoration.

## Risks / Trade-offs

- Private state can contain credentials and source text; protect the whole root and never print its contents in
  verification output.
- Upstream schemas can change; preserve whole owned directories and still verify resume for supported releases.
- Cross-host synchronization and simultaneous independent writers are outside the design.
- Package/parser checks do not prove authenticated resume. An unverified IDE route takes the terminal fallback. The
  maintainer's real-account verification waiver leaves that result unobserved for this change.
