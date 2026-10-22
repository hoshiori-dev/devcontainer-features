# Spec Delta

## Purpose

Installs OpenAI Codex in project dev containers and retains private account and conversation state across container
recreation.

Upstream sources:

- Project: https://github.com/openai/codex
- Documentation: https://learn.chatgpt.com/docs/codex/cli

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

### Requirement: Official registry installation

The feature SHALL install `@openai/codex` through npm from `https://registry.npmjs.org/`, preserving npm integrity
verification. It SHALL declare `ghcr.io/devcontainers/features/node:2` with Node 24 as a dependency. Its CLI
installation and dependencies SHALL remain outside the runtime-state volume.

#### Scenario: Registry package

- **WHEN** the resolved package is installed
- **THEN** npm verifies registry integrity and the remote user can run the CLI

#### Scenario: Corrupt registry payload

- **WHEN** npm rejects the downloaded package integrity
- **THEN** installation fails without reporting success

### Requirement: Supported targets

The feature SHALL support only the image and architecture combinations declared in `test/codex/compatibility.json`. It
SHALL reject an unsupported distribution, architecture, or requested release before installing the CLI.

#### Scenario: Supported installation

- **WHEN** a declared target and supported release are selected
- **THEN** `codex --version` runs successfully as the remote user

#### Scenario: Unsupported target

- **WHEN** the target is not supported
- **THEN** installation fails with a clear target-specific error

### Requirement: Project-scoped state

The feature SHALL use the named volume `codex-${devcontainerId}` mounted at `/var/lib/codex` for private CLI
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

The feature SHALL leave `CODEX_HOME` unset by the feature and link the actual remote user's `~/.codex` to
`/var/lib/codex`. It SHALL preserve the entire volume-backed Codex home, including skills stored there, and leave
`~/.agents/skills` unchanged and outside this volume's persistence guarantee. Existing conflicting paths and an
explicitly configured `CODEX_HOME` SHALL cause an actionable setup failure without replacement, import, deletion, or
environment modification.

#### Scenario: Default state paths

- **WHEN** the CLI runs with the feature's default environment
- **THEN** its default `~/.codex` path resolves to the mounted root without a feature-defined `CODEX_HOME`

#### Scenario: Conflicting existing state

- **WHEN** the home path is a regular file, directory, dangling link, or link to another target
- **THEN** setup reports the conflict and preserves both the existing content and the volume

#### Scenario: Existing correct link

- **WHEN** setup finds `~/.codex` already linked to the intended mount
- **THEN** it reuses the link and preserves the mounted contents

#### Scenario: Recreated home link

- **WHEN** a fresh container mounts the existing volume under a different remote-user home
- **THEN** setup creates the link in that home and retains the saved state and Codex-home skills

#### Scenario: Explicit Codex home

- **WHEN** the consumer explicitly configures `CODEX_HOME`
- **THEN** setup reports the conflict and leaves that setting and all existing state untouched

#### Scenario: Separate user skills

- **WHEN** the remote user has `~/.agents/skills`
- **THEN** setup leaves that directory and its contents untouched

### Requirement: Initialization lifecycle

The feature MAY prepare known state-directory links during image construction. It SHALL run one readiness check per
container creation via `onCreateCommand`, after mounts are available. Missing runtime links MAY be created then;
conflicting content SHALL be preserved with an actionable failure.

#### Scenario: Build-prepared link

- **WHEN** a known state path is linked during construction before its volume is mounted
- **THEN** initialization accepts the link once the expected volume is mounted and user access is verified

#### Scenario: Runtime path differs

- **WHEN** the effective runtime home or application state path differs from the prepared path, or a home mount hides it
- **THEN** initialization uses the effective path, creates a missing link there, and preserves any conflicting content

### Requirement: State readiness checks

Before reporting readiness, the creation check SHALL verify the expected state mount, effective user paths, link
targets, state-root ownership and private permissions, known credential-store permissions, and read/write/search access
as the actual remote user.

#### Scenario: Missing state mount

- **WHEN** the expected state volume is absent
- **THEN** initialization fails clearly instead of treating writable image storage as persistent state

### Requirement: Bounded state repair

Normal creation checks SHALL be bounded to the readiness paths. Full-tree scans and recursive ownership or permission
changes SHALL occur only when a detected mismatch requires repair within the state mount.

#### Scenario: Healthy reused volume

- **WHEN** the mounted state has valid mappings, ownership, permissions, and user access
- **THEN** initialization completes without scanning the full tree or recursively changing ownership or permissions

#### Scenario: Detected repair need

- **WHEN** the readiness check detects incompatible ownership, private permissions, or user access
- **THEN** initialization repairs only what is needed within the state mount or fails clearly if safe repair is
  unavailable

### Requirement: No recurring initialization

The feature SHALL add no automatic state check to start or attach hooks. Path, user, or mount changes after creation
SHALL require container recreation or an explicit rerun of initialization, as documented.

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

The feature SHALL document Codex VS Code extension `openai.chatgpt` and JetBrains' official Codex integration. Only
first-party agent integrations or IDE-vendor built-in clients connected to official agent servers qualify. Separate
CLI/IDE login and conversation stores SHALL be allowed.

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

### Requirement: File credential backend

The default container configuration SHALL select Codex's file credential store in CODEX_HOME. Existing compatible
configuration SHALL be preserved; a conflicting managed/keyring-only policy SHALL fail clearly instead of silently
exporting credentials or weakening policy.

#### Scenario: File authentication

- **WHEN** Codex signs in under the feature's default configuration
- **THEN** the credential cache is volume-backed and readable by a fresh CLI process

#### Scenario: Conflicting managed backend

- **WHEN** a managed policy prohibits the required file backend
- **THEN** setup reports the incompatibility without replacing the managed policy
