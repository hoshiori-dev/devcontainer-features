# Spec Delta

## Purpose

Installs Claude Code in project dev containers and retains private account and conversation state across container
recreation.

Upstream sources:

- Project: https://github.com/anthropics/claude-code
- Documentation: https://code.claude.com/docs/en/setup

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the option is omitted
- **THEN** the newest supported stable release is selected

#### Scenario: Explicit version

- **WHEN** a supported release is supplied as MAJOR.MINOR.PATCH
- **THEN** that exact release is installed

#### Scenario: Invalid version

- **WHEN** the value is malformed, prerelease, unavailable, or outside the supported range
- **THEN** installation fails clearly without treating the input as shell syntax

### Requirement: Signed native distribution

The feature SHALL obtain releases from `https://downloads.claude.ai/claude-code-releases/`, resolving `latest` through
its `latest` endpoint. It SHALL install the matching Linux platform's native binary outside the state volume.

#### Scenario: Native package

- **WHEN** a supported release is requested
- **THEN** the matching native CLI is installed without a Node dependency

### Requirement: Release signature and checksum

The feature SHALL verify `manifest.json.sig` and `manifest.json` with the key at
`https://downloads.claude.ai/keys/claude-code.asc`, pinned to fingerprint `31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE`,
then compare the binary SHA-256 with the verified manifest.

#### Scenario: Invalid release signature

- **WHEN** the signature, key fingerprint, checksum, or required verification file is invalid or unavailable
- **THEN** installation fails before replacing a working CLI

### Requirement: Supported targets

The feature SHALL support only the image and architecture combinations declared in
`test/claude-code/compatibility.json`. It SHALL reject an unsupported distribution, architecture, or requested release
before installing the CLI.

#### Scenario: Supported installation

- **WHEN** a declared target and supported release are selected
- **THEN** `claude --version` runs successfully as the remote user

#### Scenario: Unsupported target

- **WHEN** the target is not supported
- **THEN** installation fails with a clear target-specific error

### Requirement: Project-scoped state

The feature SHALL use the named volume `claude-code-${devcontainerId}` mounted at `/var/lib/claude-code` for private CLI
configuration, credentials, and durable conversations. Executables SHALL not be hidden by this mount. Container identity
changes and another Docker host SHALL not imply automatic state migration.

#### Scenario: Empty volume

- **WHEN** a new project container starts with an empty volume
- **THEN** its private runtime directories become writable by the remote user and the CLI remains executable

#### Scenario: Recreated container

- **WHEN** a fresh container for the same project mounts the previous volume
- **THEN** saved credentials and conversations remain available to the CLI

#### Scenario: Independent project

- **WHEN** another project uses a distinct devcontainerId
- **THEN** its default volume and private state are distinct

### Requirement: State directory contract

The feature SHALL prefer linking the supported release's default Claude configuration directory into
`/var/lib/claude-code`, without setting `CLAUDE_CONFIG_DIR`. Before selecting this route it SHALL verify all required
state paths and write behavior, including `.claude.json`. If default-directory links cannot retain complete state, the
feature SHALL use the official `CLAUDE_CONFIG_DIR` route only when verified to retain that complete state and support
the enabled integrations. A single-file link replaced by an atomic write SHALL not satisfy persistence. A release with
no verified complete mapping SHALL fail clearly rather than report persistent state as available.

Mappings SHALL use the actual remote user's effective paths. Setup SHALL reuse links to the intended mounted targets and
create absent links when initializing a fresh container. A conflicting file, directory, dangling link, or link to
another target SHALL cause an actionable failure without replacement, import, or deletion. Caller-provided
`CLAUDE_CONFIG_DIR` SHALL cause an actionable conflict without overwriting the setting or existing state.

#### Scenario: Default state paths

- **WHEN** the CLI runs with the feature's default environment
- **THEN** all required private durable state uses the verified mapping into the mounted root

#### Scenario: Conflicting existing state

- **WHEN** a required mapping encounters an existing file, directory, dangling link, or link to another target
- **THEN** setup reports the conflict and preserves both the existing content and the volume

#### Scenario: Existing correct mapping

- **WHEN** setup is repeated with links already targeting the intended mounted directories
- **THEN** it reuses those links and preserves private state

#### Scenario: Recreated user home

- **WHEN** a fresh container mounts the existing volume under a different remote-user home
- **THEN** setup recreates the required links for that user and the saved state remains available

#### Scenario: Real state writes

- **WHEN** the supported CLI or enabled backend saves state, replaces configuration, or refreshes credentials
- **THEN** required state remains volume-backed and readable by a fresh process and a recreated container

#### Scenario: Caller-provided state home

- **WHEN** the consumer explicitly configures `CLAUDE_CONFIG_DIR`
- **THEN** setup reports the conflict without changing that setting or existing state

#### Scenario: Incomplete default-directory mapping

- **WHEN** the default-directory route cannot retain the actual `.claude.json` and other required state
- **THEN** only a verified complete official configuration-directory route is supported; otherwise the release fails
  clearly without a persistence guarantee

### Requirement: Initialization lifecycle

The feature MAY prepare known state-directory links during image construction. It SHALL perform one readiness check per
container creation through `onCreateCommand`, after mounts are available. That check SHALL verify the expected state
mount, effective user paths, link targets, state-root ownership and private permissions, known credential-store
permissions, and read/write/search access as the actual remote user before reporting readiness. Missing links MAY be
created then; conflicting content SHALL be preserved with an actionable failure.

Normal creation checks SHALL be bounded to these paths; full-tree scans and recursive ownership or permission changes
SHALL occur only when a detected mismatch requires repair within the state mount. The feature SHALL add no automatic
state check to start or attach hooks. Path, user, or mount changes after creation SHALL require container recreation or
an explicit rerun of initialization, as documented.

#### Scenario: Build-prepared link

- **WHEN** a known state path is linked during construction before its volume is mounted
- **THEN** initialization accepts the link once the expected volume is mounted and user access is verified

#### Scenario: Runtime path differs

- **WHEN** the effective runtime home or application state path differs from the prepared path, or a home mount hides it
- **THEN** initialization uses the effective path, creates a missing link there, and preserves any conflicting content

#### Scenario: Missing state mount

- **WHEN** the expected state volume is absent
- **THEN** initialization fails clearly instead of treating writable image storage as persistent state

#### Scenario: Healthy reused volume

- **WHEN** the mounted state has valid mappings, ownership, permissions, and user access
- **THEN** initialization completes without scanning the full tree or recursively changing ownership or permissions

#### Scenario: Detected repair need

- **WHEN** the readiness check detects incompatible ownership, private permissions, or user access
- **THEN** initialization repairs only what is needed within the state mount or fails clearly if safe repair is
  unavailable

#### Scenario: Ordinary restart or attachment

- **WHEN** the initialized container is restarted or an editor attaches again without configuration changes
- **THEN** no feature-provided state scan, recursive repair, or readiness hook runs automatically

### Requirement: Ownership and privacy

Runtime state directories SHALL be private (`0700`) and credential files restricted (`0600`). Reused volumes SHALL be
repaired only within their mounted root, without following links into external paths. Unavailable ownership repair SHALL
report an actionable failure and SHALL not make state world-readable.

#### Scenario: Changed remote UID

- **WHEN** a recreated container uses a different remote-user UID and ownership repair is available
- **THEN** the mounted state remains usable with private permissions and external link targets are unchanged

#### Scenario: Unavailable repair

- **WHEN** the volume is inaccessible and noninteractive privileged repair is unavailable
- **THEN** setup fails clearly without broadening access or deleting state

### Requirement: No build-time account data

Installation SHALL neither log in nor copy host credentials. Runtime credentials, OAuth codes, and conversations SHALL
remain out of image layers, the checkout, and test/review output. The CLI SHALL retain upstream approval and sandbox
defaults.

#### Scenario: Unauthenticated build

- **WHEN** an image is built without account credentials
- **THEN** installation completes without requesting credentials or storing account state in image layers

#### Scenario: Runtime sign-in

- **WHEN** the developer completes authentication after container creation
- **THEN** private credentials are stored in the project volume without being printed by feature helpers

### Requirement: Editor entry points

The feature SHALL document Anthropic VS Code extension `anthropic.claude-code` and JetBrains plugin
`com.anthropic.code.plugin`. Only first-party agent integrations or IDE-vendor built-in clients connected to official
agent servers qualify. Separate CLI/IDE login and conversation stores SHALL be allowed.

#### Scenario: Official remote integration

- **WHEN** an official IDE route runs its backend inside the container with mapped private state
- **THEN** that route can retain its own login and conversations across recreation

#### Scenario: Terminal fallback

- **WHEN** an IDE route cannot meet container-side state persistence
- **THEN** the supported entry point is its container terminal; the official integration is documented only as optional
  manual setup outside the persistence guarantee

#### Scenario: Community client

- **WHEN** only a community plugin or adapter offers an IDE route
- **THEN** the feature neither installs nor configures that plugin

### Requirement: Installing twice

Installing the feature again SHALL preserve runtime state and avoid duplicate profile entries or mappings. A later
explicit release SHALL replace the CLI version; `latest` SHALL re-resolve the supported stable channel at build time. An
already resolved matching version SHALL avoid unnecessary installation.

#### Scenario: Same resolved release

- **WHEN** the feature is installed again with the same resolved release
- **THEN** the CLI remains executable and private state and mappings are preserved

#### Scenario: Changed release

- **WHEN** the feature is installed with another supported release selection
- **THEN** the later selection wins without erasing credentials or conversations

### Requirement: Complete Claude application state

The feature SHALL persist Claude's app state as well as its configured directory, including any `.claude.json` state
used by the supported version. Native self-updates SHALL be disabled by default so an explicit release remains selected
until a new build or user-directed change.

#### Scenario: Claude restart

- **WHEN** the CLI or enabled remote plugin writes credentials, app state, and session history
- **THEN** those stores survive a new container and exact-version installations do not silently update

### Requirement: Supported release range

The feature SHALL accept stable releases at or above 2.1.89; older release formats and unsupported upstream packaging
SHALL fail clearly.

#### Scenario: Release below the supported range

- **WHEN** a release below 2.1.89 is requested
- **THEN** installation fails before changing the installed CLI or runtime state
