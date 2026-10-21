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

The feature SHALL support only the image and architecture combinations declared in
`test/antigravity/compatibility.json`. It SHALL reject an unsupported distribution, architecture, or requested release
before installing the CLI.

#### Scenario: Supported installation

- **WHEN** a declared target and supported release are selected
- **THEN** `agy --version` runs successfully as the remote user

#### Scenario: Unsupported target

- **WHEN** the target is not supported
- **THEN** installation fails with a clear target-specific error

### Requirement: Project-scoped state

The feature SHALL use the named volume `antigravity-${devcontainerId}` mounted at `/var/lib/antigravity` for private CLI
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

The feature SHALL configure `owned Antigravity directories linked below /var/lib/antigravity`. Explicit upstream state
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

The feature SHALL document Google VS Code extension `Google.google-antigravity` and JetBrains AI's official Antigravity
agent route. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent servers
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

A repeated installation SHALL re-resolve the current supported platform manifest, preserve private state and mappings,
and avoid duplicate shell entries. If the resolved CLI version is unchanged it SHALL avoid unnecessary replacement; if
upstream's current version changes the newly verified version SHALL replace the CLI.

#### Scenario: Same current release

- **WHEN** the feature is installed again and the manifest resolves to the installed version
- **THEN** the CLI and private state remain usable without duplicate mappings or unnecessary replacement

#### Scenario: Changed current release

- **WHEN** the feature is installed again and the manifest resolves to a newer supported version
- **THEN** the newly verified CLI replaces the executable while credentials and conversations remain intact

### Requirement: Google account restoration

The CLI SHALL retain Google-account login and durable conversations using upstream file storage across new CLI processes
and container recreation. API-key or ADC authentication SHALL not substitute for this behavior. Upstream self-updates
SHALL be disabled by default for the installed build.

#### Scenario: Account restoration

- **WHEN** a developer has signed in with Google OAuth, exits, and starts a fresh container using the same volume
- **THEN** the CLI restores the account, can refresh credentials, and can resume a retained conversation without
  repeating OAuth

#### Scenario: File backend selection

- **WHEN** the headless container has no D-Bus session
- **THEN** the upstream CLI selects file storage; this observation alone does not establish account restoration

#### Scenario: No alternate-auth substitution

- **WHEN** Google account restoration fails for the selected release
- **THEN** the feature remains unready for delivery rather than substituting an API key or ADC mode

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
