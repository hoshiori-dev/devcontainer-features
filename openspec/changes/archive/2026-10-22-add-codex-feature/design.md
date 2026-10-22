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

Use complete official native packages (`codex-package-<target>.tar.gz`) in the feature-owned application prefix
`/usr/local/share/codex`. Resolve `latest` to a stable release, then use that exact release for both the archive and
`codex-package_SHA256SUMS`; verify the archive before extraction or execution. Fetch release metadata from the GitHub
API and assets from OpenAI's GitHub Releases with normal HTTPS verification. Missing archives or verification data fail
clearly. Retain the package layout and companion executables rather than extracting only the main binary. Validate a
staged package before replacing a working installation; matching installed releases can be reused.

Do not execute the upstream standalone installer unchanged: its default application location is inside Codex home, which
this feature persists as runtime state. Keep the existing launcher and private umask while adapting it to the native
package layout. Use shell and jq for installation metadata and state initialization. Do not probe the app-server
configuration protocol or require its availability to install a release. Install missing prerequisites through an
available distribution package manager; report unavailable prerequisites clearly. Neither installation nor
initialization may require Node or npm.

The shared Node Feature dependency is rejected because different options are separate installation nodes, not an
override merge. With CLI 0.89.0, both explicit Node 22 and an empty Node options object resolve before Codex's Node 24
dependency. The explicit-version build ends with Node 24 and its default alias, overriding the requested Node 22. An
empty shared dependency would still conflict with explicitly configured Node instances. Requiring consumers to supply
Node removes standalone installation. A private Node runtime isolates settings but adds a separate runtime to maintain;
the maintainer selected native packages instead.

Sources for this decision:

- [Official installation routes and native releases](https://github.com/openai/codex#installation)
- [Official standalone installer package selection and layout](https://chatgpt.com/codex/install.sh)
- [Feature dependency equality and option resolution](https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md#definition-feature-equality)
- [Official Node Feature defaults](https://github.com/devcontainers/features/blob/main/src/node/devcontainer-feature.json)

Do not declare `dependsOn` for the shared Node Feature. Ordering after a user Node Feature may use `installsAfter`,
without injecting options. Validate explicit tool versions, partially specified options, and an empty options object;
compare default aliases and tools with the same upstream Node Feature installed alone. A separate two-stage image check
installs Codex first and then the actual Node Feature to verify later reconfiguration.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Any stable package release that satisfies the declared target contract.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Leave CODEX_HOME unset by the feature. Resolve the intended remote user's home and prepare `~/.codex -> /var/lib/codex`.
This preserves the default path expected by Codex and tools that install skills there. Leave credential backend
defaults, user configuration, and managed policy to Codex; do not create or rewrite config.toml or reject a selected
backend. File credentials persist through this mapping. Consumers selecting keyring manage its service, unlocking, and
persistence separately; this feature provides no keyring setup. Retain the entire directory, including auth.json,
history, complete session stores and companion files, and skills; sharing this directory with an IDE is convenient
rather than required. The separate `~/.agents/skills` discovery location is unchanged and is not persisted by this
volume.

An absent link is created; an existing link to the intended mount is reused. A regular file, directory, dangling link,
or link to another target is an actionable conflict: do not replace, import, or delete it. An explicitly configured
CODEX_HOME is also a conflict requiring consumer resolution; do not rewrite or unset it. Creation-time initialization
verifies the effective home and fills any missing link; privileged repair is restricted to the mounted state root and
never changes the user's home ownership.

Metadata declares source `codex-${devcontainerId}`, target `/var/lib/codex`, type `volume`, an `onCreateCommand`
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
mount under the existing ownership/privacy contract; unavailable repair fails clearly. Do not initialize Codex settings.

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

The initial compatibility list records verified Debian 12 and Ubuntu 24.04 combinations on amd64 and arm64. Native
package coverage determines support: the selected release must publish a matching Linux package for the system and
hardware. Current Linux packages cover x86_64 and aarch64 using musl targets. Missing native coverage is unsupported;
there is no npm, private Node, or source-build fallback. A covered target outside the tested list receives a warning and
an installation attempt. This distinction supersedes the earlier proposal to attempt every architecture. Package
availability does not establish successful execution on every distribution; prerequisite and runtime failures report
their actual cause.

Automated checks cover version selection, complete native-package execution, checksum failures, unsupported targets,
covered but untested targets, installation without global Node, install-twice behavior, private state, repair, home-link
recreation, unchanged skill paths, explicit CODEX_HOME conflicts, existing-path conflicts, and Node isolation. Keep the
CI test architecture unchanged; use normal feature scenarios for composition and a separate two-stage image result for
later Node installation. Isolation uses two project identities; persistence needs two fresh containers mounting the same
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
