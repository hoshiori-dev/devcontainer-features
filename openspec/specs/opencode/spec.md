# opencode Specification

## Purpose

Installs OpenCode v2 in project dev containers and retains private account and conversation state across container
recreation.

Upstream sources:

- Project: https://github.com/anomalyco/opencode
- Documentation: https://opencode.ai/docs/

## Requirements

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

### Requirement: Native executable installation

The feature SHALL install upstream's native `opencode` executable, the one upstream's native installer installs, at
`/usr/local/bin/opencode`, outside the runtime-state volume. It SHALL neither install nor require npm, Node.js, or
another JavaScript runtime, and SHALL not run upstream's installer script.

#### Scenario: Native executable

- **WHEN** the feature is installed on an image without Node.js or npm
- **THEN** the remote user can run `opencode --version`, and neither `node` nor `npm` was added to the image

#### Scenario: Existing JavaScript tooling

- **WHEN** the image already has Node.js or npm
- **THEN** the feature leaves their versions, global packages, and configuration unchanged

### Requirement: Native package source

The feature SHALL download the platform package `@opencode/cli-<target>` for the selected release from
`https://registry.npmjs.org/`, where `<target>` is `linux-x64` or `linux-arm64`, with the suffix `-baseline` on an
x86_64 CPU without AVX2 and `-musl` on a musl C library, as upstream's native installer selects it. `latest` SHALL mean
the registry's `latest` dist-tag of `@opencode/cli` at build time. Every request SHALL use HTTPS, redirects included.

#### Scenario: Target selection

- **WHEN** the feature is installed on x86_64 with AVX2 and glibc
- **THEN** it installs from `@opencode/cli-linux-x64`

#### Scenario: Resolving latest

- **WHEN** `version` is `latest` and the `latest` dist-tag names a stable 2.x release
- **THEN** that release is installed; any other dist-tag value fails installation before a package is downloaded

### Requirement: Native package verification

The feature SHALL install the executable only when the downloaded package's SHA-512 digest equals the `dist.integrity`
value the registry publishes for that package version, and SHALL rely on TLS alone for that metadata, since upstream
publishes no separate signature for the package.

#### Scenario: Corrupt package

- **WHEN** the downloaded package does not match its published integrity
- **THEN** installation fails without reporting success, and an earlier `/usr/local/bin/opencode` is left as it was

### Requirement: Supported targets

`test/opencode/compatibility.json` SHALL record tested image and architecture combinations. A target covered by the
selected official installation route but absent from that list SHALL receive a warning followed by an installation
attempt. Missing distribution/runtime coverage SHALL fail clearly; actual prerequisite and execution failures SHALL
report their cause without claiming success.

#### Scenario: Tested installation

- **WHEN** a declared target and supported release are selected
- **THEN** the CLI runs successfully as the remote user

#### Scenario: Covered but untested target

- **WHEN** the installation route covers a target absent from the compatibility list
- **THEN** installation warns and attempts installation rather than rejecting it solely for missing test coverage

#### Scenario: Uncovered or unusable target

- **WHEN** no supported artifact/runtime covers the target, or a required prerequisite or executable fails
- **THEN** installation fails clearly with the actual cause

### Requirement: Project-scoped state

The feature SHALL use the named volume `opencode-${devcontainerId}` mounted at `/var/lib/opencode` for private CLI
configuration, credentials, and durable conversations. Executables SHALL not be hidden by this mount. Container identity
changes and another Docker host SHALL not imply automatic state migration.

#### Scenario: Empty volume

- **WHEN** a new project container starts with an empty volume
- **THEN** its private runtime directories become writable by the remote user and the CLI remains executable

#### Scenario: Recreated container

- **WHEN** a fresh container for the same project mounts the previous volume
- **THEN** saved file-backed credentials and conversations remain in their mapped directories

#### Scenario: Independent project

- **WHEN** another project uses a distinct devcontainerId
- **THEN** its default volume and private state are distinct

### Requirement: State directory contract

The feature SHALL link only OpenCode-owned data, configuration, state, and cache directories under the remote user's
effective XDG roots to corresponding subdirectories of `/var/lib/opencode`. It SHALL respect existing XDG root settings
without setting or replacing global `XDG_*` values or linking whole shared XDG roots. Complete databases and companion
files SHALL remain together in their linked application directories.

#### Scenario: Default state paths

- **WHEN** the CLI runs with the feature's default environment
- **THEN** all required private durable state uses the verified mapping into the mounted root

#### Scenario: Real state writes

- **WHEN** the supported CLI or enabled backend saves state, replaces configuration, or atomically replaces a credential
  fixture
- **THEN** required files remain volume-backed and readable by a fresh process and a recreated container without login

### Requirement: State mapping conflicts

Setup SHALL use the actual remote user's effective paths, reuse links to the intended mounts, and create missing links
in fresh containers. Conflicting files, directories, dangling links, or links to another target SHALL cause an
actionable failure, preserving existing content without replacement, import, or deletion. Explicit application state
overrides outside mapped directories SHALL be documented as outside the persistence guarantee.

#### Scenario: Conflicting existing state

- **WHEN** a required mapping encounters an existing file, directory, dangling link, or link to another target
- **THEN** setup reports the conflict and preserves both the existing content and the volume

#### Scenario: Existing correct mapping

- **WHEN** setup is repeated with links already targeting the intended mounted directories
- **THEN** it reuses those links and preserves private state

#### Scenario: Recreated user home

- **WHEN** a fresh container mounts the existing volume under a different remote-user home
- **THEN** setup recreates the required links for that user and the saved state remains available

#### Scenario: Custom XDG roots

- **WHEN** the remote user supplies valid custom XDG roots containing other applications' state
- **THEN** setup maps only OpenCode-owned subdirectories and preserves the root settings and unrelated data

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

Installation SHALL neither log in nor copy host credentials. Real credentials, OAuth codes, and conversations SHALL
remain out of image layers, the checkout, and test/review output. The CLI SHALL retain upstream approval and sandbox
defaults.

#### Scenario: Unauthenticated build

- **WHEN** an image is built without account credentials
- **THEN** installation completes without requesting credentials or storing account state in image layers

#### Scenario: Runtime credential files

- **WHEN** synthetic credential files are written to mapped application state after container creation
- **THEN** those files remain private and volume-backed without being printed by feature helpers

### Requirement: Editor entry points

The feature SHALL document OpenCode VS Code extension `sst-dev.opencode` and JetBrains' built-in ACP client running
`opencode acp`. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent servers
qualify. Separate CLI/IDE login and conversation stores SHALL be allowed.

#### Scenario: Official remote integration

- **WHEN** an official IDE route runs its backend inside the container with mapped private state
- **THEN** that route can retain its own file-backed state across recreation

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

### Requirement: Credential backend choice

The feature SHALL preserve upstream credential backend defaults, user configuration, and managed policy without
selecting or requiring a backend. Credential files in mapped application directories SHALL persist with private
permissions. Keyring services, external credential paths, and environment-supplied secrets SHALL remain consumer
responsibilities; the feature SHALL not configure them.

#### Scenario: File-backed credentials

- **WHEN** synthetic credential files are saved in mapped application directories and the container is recreated
- **THEN** their contents and private permissions remain intact on the same volume

#### Scenario: User-selected backend

- **WHEN** user configuration or managed policy selects a credential backend
- **THEN** state initialization preserves that selection without rewriting or rejecting it solely for backend choice

### Requirement: Unattended credential-file validation

Credential validation SHALL test only file persistence, mounts, permissions, isolation, and recreation using synthetic
fixtures. No test SHALL require interactive login, a real API key, browser authorization, token refresh, or human
assistance. Other authentication forms SHALL not be tested. File-retention results SHALL not be reported as proof of
account authentication or restoration.

#### Scenario: Credential-free execution

- **WHEN** local automation or CI validates credential persistence without account access
- **THEN** fixture checks complete unattended and never request secrets or an authorization URL

### Requirement: Authentication documentation

NOTES.md SHALL explain supported upstream authentication choices, credential-file paths retained by the volume, and how
consumers can persist external stores themselves. It SHALL distinguish retained files from working authentication and
explain that keyring setup, unlocking, and persistence are outside this feature.

#### Scenario: Consumer-managed credentials

- **WHEN** a developer chooses an authentication method
- **THEN** NOTES identifies its file-persistence boundary and any consumer-managed storage

### Requirement: Independent user runtimes

Installation SHALL preserve user runtime versions, paths, package-manager settings, and defaults. Agent-owned runtimes
SHALL remain outside the state volume and SHALL not override user toolchains. Required runtime dependencies SHALL not
inject conflicting options into a separately configured runtime Feature.

#### Scenario: Runtime composition

- **WHEN** a user installs a runtime Feature with explicit, partial, or empty options alongside or after this agent
- **THEN** its settings match the runtime Feature installed alone, and the agent and initializer remain usable
