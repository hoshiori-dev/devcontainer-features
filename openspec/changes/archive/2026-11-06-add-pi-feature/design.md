# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/pi/spec.md) for the contract.
[Issue #167](https://github.com/hoshiori-dev/devcontainer-features/issues/167) holds upstream research and confirmed
boundaries. There is no existing pi feature. The uv volume helper is a useful reference, but its warning-only repair
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

Install upstream's native executable, not the npm package. Every stable release publishes `pi-linux-x64.tar.gz`,
`pi-linux-arm64.tar.gz`, and a `SHA256SUMS` that lists every asset; the feature downloads the archive for the target,
verifies its `SHA256SUMS` entry, and extracts it. The initial supported release is 1.3.0 or newer.

Observed on 2026-10-23 at v1.4.0 (latest stable, read and inspected, `--version` run with no Node.js or npm on `PATH`):
the archive holds one `pi/` directory whose `pi` is a single executable compiled with Bun, linked against glibc only
(highest symbol `GLIBC_2.17`). Beside it are the files it loads at runtime (`theme/`, `export-html/`, `assets/`,
`photon_rs_bg.wasm`, `native/linux/prebuilds/<arch>/*.node`, `package.json`), which it finds from the executable's own
location. The feature installs the whole directory atomically to `/usr/local/lib/pi` and links `/usr/local/bin/pi` to
it, outside the state mount; the link is accepted only if those files load through it. No musl build is published, so
musl targets fail coverage. If a native archive fails on a proposed target, that target fails coverage rather than
silently changing distribution. The binary has no self-update method (`pi update` prints the releases URL instead), so
it never replaces itself; new versions come from reinstalling the feature.

Rejected:

- Upstream's installer (`https://pi.dev/install.sh`, read on 2026-10-23, not executed): it requires Node.js 22.19 or
  newer and npm, can install Node.js itself through the distro package manager or a download, installs the npm package
  under `~/.pi/agent/install`, and may append a `PATH` line to shell startup files. It never uses the native archive.
- `@earendil-works/pi-coding-agent` through npm: needs Node.js 22.19 or newer and npm. The feature would have to install
  them or depend on a Node feature. Either way it could pin or override the Node.js version a user configures with their
  own Node feature, or install a global package into that user's toolchain. The native archive is the same CLI without
  that coupling. `NOTES.md` records the direct download and this reason (proposal, Acceptance).
- The Nix flake: needs Nix in the container, a package-manager dependency of its own.

Pi packages are a runtime concern of the user, not of the feature. `pi install npm:<pkg>` and `pi install git:<url>` run
whichever `npm` (or the `npmCommand` setting) and `git` are on `PATH`, installing into `~/.pi/agent/npm` inside the
agent directory rather than a global prefix. Without npm the command fails with "Executable not found in $PATH" and
nothing else breaks. The feature provides neither npm nor git for this; NOTES tells users to add their own Node or git
feature if they want such packages.

### Options

| Name    | Type   | Default    | Enum / proposals             | Meaning                                      |
| ------- | ------ | ---------- | ---------------------------- | -------------------------------------------- |
| version | string | `"latest"` | No enum; proposals: `latest` | Stable channel or explicit MAJOR.MINOR.PATCH |

Supported selections: Stable releases at or above 1.3.0.

The default follows the supported stable channel rather than embedding today's release. A single option avoids
conflicting channel/version combinations; there is no arbitrary URL or source-ref option.

### Runtime state

Leave PI_CODING_AGENT_DIR unset by the feature. Locate the supported release's default agent directory in an isolated
remote-user home, then link that whole directory to /var/lib/pi/agent. Verify auth.json, settings, skills, the user
package directory (with a fixture that needs no npm), and default sessions use the linked directory through real save
and replacement operations. Keep the base CLI outside this home. A release that cannot preserve complete required state
through this mapping is unsupported; do not silently switch to a global environment override. Explicit session-directory
overrides outside the volume remain outside the guarantee. Do not migrate deprecated owner/package identities or install
community bridges.

Prepare only known link paths during construction; resolve runtime-only paths at container creation. Reuse links to
intended mounted targets. Existing files, directories, dangling links, or links to other targets are actionable
conflicts; preserve their contents. Runtime link creation runs as the remote user; privileged repair stays inside the
state mount and never changes home ownership. Caller-provided PI_CODING_AGENT_DIR is a conflict requiring consumer
resolution; never rewrite or unset it. Distinguish caller settings from any feature-owned fallback setting.

Metadata declares source `pi-${devcontainerId}`, target `/var/lib/pi`, type `volume`, an `onCreateCommand` initializer,
and ordering after common-utils where user setup matters. It declares no entrypoint, privileged mode, added
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

Candidate first-party routes: integrated container terminal in VS Code and JetBrains; no first-party IDE extension was
verified. No VS Code extension is automatically installed.

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
