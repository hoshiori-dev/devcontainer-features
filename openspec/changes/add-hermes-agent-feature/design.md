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

Prefer a native install; none exists for a Linux CLI, so the source installer is the closest route. Observed on
2026-10-23 at v0.22.5 (scripts, PM, and docs read, not executed): GitHub releases v0.22.0 to v0.22.5 carry no assets;
self-contained bundles ship only as the macOS and Windows desktop apps, and Linux desktop packaging is disabled in the
release workflow. The source installer is upstream's only supported Linux CLI route and it does not use system package
managers. It downloads a pinned, SHA-256-checked uv and ignores any uv on `PATH`; PM (Hermes' in-repo package and
runtime manager, `pm/`) then installs private Python, Node, npm, uv, ripgrep, and FFmpeg from `pm/lock.json` into its
own tool store and strips `UV_*`, `PYTHON*`, `VIRTUAL_ENV`, `npm_config_*`, and `NODE_*` from its child processes. Node
builds the TUI and web frontends; the core CLI and ACP server are Python.

The installer still has side effects on the user's tooling, which the feature prevents or the release is unsupported:

- `wire_shell_path` runs in the products stage even with `--non-interactive` and appends a `~/.local/bin` `PATH` line to
  bash, zsh, and fish startup files; `expose_cli` publishes the `hermes`, `hermes-acp`, and `hermes-agent` launchers
  there (`cli.expose_on_path: false` disables it). Only those launchers reach `PATH`, never PM's `node` or `python`. The
  feature exposes the launchers through `/usr/local/bin` instead and leaves shell startup files unchanged.
- The bootstrap looks for a uv-managed Python 3.14, then a host one (`uv python find --system`), and otherwise runs
  `uv python install`, which writes into uv's per-user managed-Python directory, the one the user's own uv uses. That uv
  inherits the build environment unfiltered, so the user's `UV_*` settings can redirect it. The feature runs the
  installer with a sanitized environment, keeps the bootstrap inside the application directory (for example through
  `UV_PYTHON_INSTALL_DIR`; unverified), and never requires a host Python.
- PM's tool store, uv cache, and download partials default to under `~/.hermes`, which the state mapping moves into the
  volume. The feature places them in the application directory (`HERMES_RUNTIME_DIR`, which upstream's own Docker image
  sets; whether source launchers honor it is unverified) and verifies an empty volume cannot hide them.
- On glibc images without `libatomic.so.1`, PM runs the distro package manager. The feature installs `libatomic1` itself
  first, as an OS package, not a language package manager.

Rejected:

- `pip`, `pipx`, or `uv tool install hermes-agent` from PyPI: upstream lists PyPI installs as unsupported, and the PyPI
  package stops at 0.19.0. It would also make the feature depend on a Python and package manager that could pin or
  override the versions a user configures with their own Python or uv feature.
- The npm package `hermes-agent`: an unofficial third-party bridge, needing Node.js and npm and so the same coupling
  with a user's Node feature.
- Homebrew: listed as unsupported upstream, and a package manager the image does not otherwise need.
- The Docker image `nousresearch/hermes-agent`: a whole image, not something a Feature installs; it also links PM's
  `python3`, `node`, and `npm` into `/usr/local/bin`, which would shadow a runtime Feature.
- The Nix flake: needs Nix in the container, and upstream no longer lists it as an explicitly supported route.

`NOTES.md` records why the feature uses the source installer with private runtimes instead of a package manager
(proposal, Acceptance).

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
synthetic credential-file replacement, and enabled ACP discovery through the link. A release that cannot preserve
complete required state through this mapping is unsupported; do not silently switch to a global environment override.

Use an explicit application installation path outside the default home and state volume for the source checkout,
dependencies, and runtimes. Verify an empty volume cannot hide the executable or trigger a second source installation
under the default home. No desktop product, messaging daemon, browser stack, or nested Docker tool backend is enabled.

Prepare only known link paths during construction; resolve runtime-only paths at container creation. Reuse links to
intended mounted targets. Existing files, directories, dangling links, or links to other targets are actionable
conflicts; preserve their contents. Runtime link creation runs as the remote user; privileged repair stays inside the
state mount and never changes home ownership. Caller-provided HERMES_HOME is a conflict requiring consumer resolution;
never rewrite or unset it. Distinguish caller settings from any feature-owned fallback setting.

Metadata declares source `hermes-agent-${devcontainerId}`, target `/var/lib/hermes-agent`, type `volume`, an
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

Candidate first-party routes: VS Code's container terminal and JetBrains' built-in ACP client running the official
`hermes acp` server. No VS Code extension is automatically installed.

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
