# Spec Delta

## Purpose

Installs Google Antigravity CLI in project dev containers and retains private account and conversation state across
container recreation.

Upstream sources:

- Project: https://antigravity.google/product/antigravity-cli
- Documentation: https://antigravity.google/docs/overview

## ADDED Requirements

### Requirement: Verified platform manifest

The feature SHALL resolve the current Linux platform manifest from
`https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/`, download its archive only from
`https://storage.googleapis.com/antigravity-public/antigravity-cli/`, and verify its SHA-512. Manifest and payload
redirects SHALL retain HTTPS.

#### Scenario: Current platform

- **WHEN** installation resolves the current supported platform manifest
- **THEN** the manifest's SHA-512 verifies before the CLI is installed outside the state volume

#### Scenario: Invalid manifest payload

- **WHEN** the URL is outside the allowed distribution prefix, verification data is missing, or the digest mismatches
- **THEN** installation fails before replacing a working CLI

### Requirement: Supported targets

`test/antigravity/compatibility.json` SHALL record tested image and architecture combinations. A target covered by the
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

The feature SHALL use the named volume `antigravity-${devcontainerId}` mounted at `/var/lib/antigravity` for private CLI
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

The feature SHALL link only verified Antigravity-owned directories into `/var/lib/antigravity`, retaining upstream
default discovery paths. It SHALL NOT link the entire shared `.gemini` or `.config` tree.

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

### Requirement: Safe shared state mappings

Shared files SHALL use only upstream-supported mappings that preserve unrelated tools' data under synthetic writes and
atomic replacement. A file link replaced by atomic writes SHALL NOT count as persistence. Stores that cannot be mapped
safely SHALL remain consumer-managed and documented in NOTES; the feature SHALL not redirect shared parent directories
or broaden ownership to include them.

#### Scenario: Unsafe shared store

- **WHEN** an external or shared credential store cannot be mapped without affecting unrelated application data
- **THEN** the feature preserves that data and documents consumer-managed persistence outside its mapped directories

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

The feature SHALL document Google VS Code extension `Google.google-antigravity` and JetBrains AI's official Antigravity
agent route. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent servers
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

A repeated installation SHALL re-resolve the current supported platform manifest, preserve private state and mappings,
and avoid duplicate shell entries. If the resolved CLI version is unchanged it SHALL avoid unnecessary replacement; if
upstream's current version changes the newly verified version SHALL replace the CLI.

#### Scenario: Same current release

- **WHEN** the feature is installed again and the manifest resolves to the installed version
- **THEN** the CLI and private state remain usable without duplicate mappings or unnecessary replacement

#### Scenario: Changed current release

- **WHEN** the feature is installed again and the manifest resolves to a newer supported version
- **THEN** the newly verified CLI replaces the executable while credentials and conversations remain intact

### Requirement: Authentication choice and update policy

Google-account, API-key, and ADC authentication SHALL be allowed without imposing a login method. Credential files in
mapped application directories SHALL be retained; external ADC paths, environment variables, and keyrings SHALL remain
consumer-managed. Upstream self-updates SHALL be disabled by default for the installed build.

#### Scenario: Authentication selection

- **WHEN** the consumer selects Google-account, API-key, or ADC authentication
- **THEN** the feature leaves that selection unchanged and documents which credential files its mappings retain

### Requirement: Additional Antigravity private stores

State coverage SHALL include the CLI token/session stores and any active Antigravity plugin-secret store under the
user's `.config/antigravity`. The feature SHALL preserve unrelated Gemini configuration and SHALL not require a host
keychain or an extra keyring service.

#### Scenario: Plugin credential storage

- **WHEN** the upstream backend writes plugin secrets outside its CLI data directory
- **THEN** the store remains private and volume-backed

#### Scenario: Gemini coexistence

- **WHEN** another tool uses the user's .gemini tree
- **THEN** Antigravity setup leaves unrelated data unchanged

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
