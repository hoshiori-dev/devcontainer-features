# Spec Delta

## Purpose

Installs OpenCode v2 in project dev containers and retains private account and conversation state across container
recreation.

Upstream sources:

- Project: https://github.com/anomalyco/opencode
- Documentation: https://opencode.ai/docs/

## ADDED Requirements

### Requirement: Option version

The feature SHALL accept the option `version` as declared here.

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the option is omitted
- **THEN** the newest stable 2.x release is selected

#### Scenario: Explicit version

- **WHEN** a supported release is supplied as MAJOR.MINOR.PATCH
- **THEN** that exact release is installed

#### Scenario: Invalid version

- **WHEN** the value is malformed, prerelease, unavailable, or outside the supported range
- **THEN** installation fails clearly without treating the input as shell syntax

### Requirement: Official registry installation

The feature SHALL install `@opencode/cli` through npm from `https://registry.npmjs.org/`, preserving npm integrity
verification. It SHALL declare `ghcr.io/devcontainers/features/node:2` with Node 24 as a dependency. Its CLI
installation and dependencies SHALL remain outside the runtime-state volume.

#### Scenario: Registry package

- **WHEN** the resolved package is installed
- **THEN** npm verifies registry integrity and the remote user can run the CLI

#### Scenario: Corrupt registry payload

- **WHEN** npm rejects the downloaded package integrity
- **THEN** installation fails without reporting success

### Requirement: Supported targets

The feature SHALL support only the image and architecture combinations declared in `test/opencode/compatibility.json`.
It SHALL reject an unsupported distribution, architecture, or requested release before installing the CLI.

#### Scenario: Supported installation

- **WHEN** a declared target and supported release are selected
- **THEN** `opencode --version` runs successfully as the remote user

#### Scenario: Unsupported target

- **WHEN** the target is not supported
- **THEN** installation fails with a clear target-specific error

### Requirement: Project-scoped state

The feature SHALL use the named volume `opencode-${devcontainerId}` mounted at `/var/lib/opencode` for private CLI
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

The feature SHALL configure `app-specific XDG directories linked below /var/lib/opencode`. Explicit upstream state
overrides outside this root SHALL be documented as outside the persistence guarantee. Existing conflicting files or
directories SHALL not be silently replaced or imported.

#### Scenario: Default state paths

- **WHEN** the CLI runs with the feature's default environment
- **THEN** its private durable state is under the mounted root

#### Scenario: Conflicting existing state

- **WHEN** a required state mapping conflicts with unrelated existing content
- **THEN** setup reports the conflict and preserves both the existing content and the volume

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

The feature SHALL document OpenCode VS Code extension `sst-dev.opencode` and JetBrains' built-in ACP client running
`opencode acp`. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent servers
qualify. Separate CLI/IDE login and conversation stores SHALL be allowed.

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

### Requirement: V2 release boundary

Only stable OpenCode 2.x releases SHALL be accepted. The complete v2 credential and session databases and their
companion files SHALL be retained; a v1 auth.json-only persistence scheme SHALL not count as support.

#### Scenario: Unsupported major

- **WHEN** a version outside stable 2.x is requested
- **THEN** installation rejects it rather than installing or migrating v1

#### Scenario: Database-backed session

- **WHEN** a v2 session is saved and the container is recreated
- **THEN** the CLI can reopen the retained credential/session stores
