# Spec Delta

## Purpose

Installs Nous Research Hermes Agent in project dev containers and retains private account and conversation state across
container recreation.

Upstream sources:

- Project: https://github.com/NousResearch/hermes-agent
- Documentation: https://hermes-agent.nousresearch.com/docs/

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

### Requirement: Upstream source installer

The feature SHALL resolve stable releases and release commits through
`https://api.github.com/repos/NousResearch/hermes-agent/` and fetch the matching installer from
`https://raw.githubusercontent.com/NousResearch/hermes-agent/`. The saved installer SHALL run non-interactively against
that immutable commit, with code and runtimes outside the state volume.

#### Scenario: Resolved source commit

- **WHEN** the requested release resolves to a supported immutable commit
- **THEN** the matching installer and source checkout use that commit

#### Scenario: Source resolution failure

- **WHEN** the tag, commit, or installer cannot be resolved or fetched
- **THEN** installation fails without claiming the requested version is installed

### Requirement: Installer verification and runtime sources

The installer SHALL retain upstream PM's verified runtime downloads and registry checks. The installer itself relies on
HTTPS because no independently published script signature/checksum was established; this risk is accepted to use the
documented source installation. No per-release digest SHALL be embedded in the feature.

#### Scenario: Runtime integrity failure

- **WHEN** upstream verification of a runtime or dependency fails
- **THEN** the feature fails rather than disabling verification

### Requirement: Pinned Python and uv distribution

PM SHALL fetch uv from `https://github.com/astral-sh/uv/releases/download/` and Python from
`https://github.com/astral-sh/python-build-standalone/releases/download/`, verifying each against the SHA-256 in the
selected Hermes commit's fetched PM lock. Missing or mismatched digests SHALL fail installation.

#### Scenario: Runtime artifact verification

- **WHEN** the installer prepares Python or uv
- **THEN** the artifact comes from its declared distribution prefix and matches its upstream lock digest

### Requirement: Node and package registry distribution

PM SHALL fetch Node from `https://nodejs.org/dist/` with its fetched PM-lock SHA-256 verified. npm and Python
dependencies SHALL use `https://registry.npmjs.org/`, `https://pypi.org/`, and `https://files.pythonhosted.org/`,
preserving registry integrity and locked dependency checks.

#### Scenario: Runtime package verification

- **WHEN** the installer prepares Node or registry dependencies
- **THEN** it retains the upstream lock and integrity checks and fails if required verification fails

### Requirement: Ripgrep and FFmpeg distribution

PM SHALL fetch ripgrep from `https://github.com/BurntSushi/ripgrep/releases/download/` and FFmpeg from
`https://github.com/BtbN/FFmpeg-Builds/releases/download/`, checking the fetched Hermes PM-lock SHA-256 for each. Trust
in Hermes' selected FFmpeg distributor is accepted because its documented installer depends on that build and locks its
contents; it is not an unverified mirror chosen by this feature.

#### Scenario: Auxiliary CLI runtime verification

- **WHEN** the installer prepares ripgrep or FFmpeg
- **THEN** the artifact matches its lock digest and the declared distribution prefix, or installation fails

### Requirement: Lean default installation

The feature SHALL enable the CLI and official ACP capability without requesting desktop, browser, or computer-use
assets, starting messaging services, or enabling a nested Docker backend.

#### Scenario: Lean source installation

- **WHEN** the feature installs Hermes and its ACP capability
- **THEN** no desktop build, Chromium download, messaging service, or nested Docker backend is enabled

### Requirement: Supported targets

`test/hermes-agent/compatibility.json` SHALL record tested image and architecture combinations. A target covered by the
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

The feature SHALL use the named volume `hermes-agent-${devcontainerId}` mounted at `/var/lib/hermes-agent` for private
CLI configuration, credentials, and durable conversations. Executables SHALL not be hidden by this mount. Container
identity changes and another Docker host SHALL not imply automatic state migration.

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

The feature SHALL link the verified default Hermes home to `/var/lib/hermes-agent`, leaving `HERMES_HOME` unset. It
SHALL keep the whole profile volume-backed, including file-backed credentials, configuration, skills, memories,
databases and companions, and sessions, or fail clearly. Source checkout, dependencies, and runtimes SHALL remain
outside the home and state volume.

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
actionable failure, preserving existing content without replacement, import, or deletion. Caller-provided `HERMES_HOME`
SHALL fail clearly without changing the setting or existing state.

#### Scenario: Conflicting existing state

- **WHEN** a required mapping encounters an existing file, directory, dangling link, or link to another target
- **THEN** setup reports the conflict and preserves both the existing content and the volume

#### Scenario: Existing correct mapping

- **WHEN** setup is repeated with links already targeting the intended mounted directories
- **THEN** it reuses those links and preserves private state

#### Scenario: Recreated user home

- **WHEN** a fresh container mounts the existing volume under a different remote-user home
- **THEN** setup recreates the required links for that user and the saved state remains available

#### Scenario: Caller-provided state home

- **WHEN** the consumer explicitly configures `HERMES_HOME`
- **THEN** setup reports the conflict without changing that setting or existing state

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

The feature SHALL document VS Code's container terminal and JetBrains' built-in ACP client running the official
`hermes acp` server. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent
servers qualify. Separate CLI/IDE login and conversation stores SHALL be allowed.

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

### Requirement: Official ACP server

The feature SHALL include the upstream-supported ACP capability and make `hermes acp --check` succeed without account
credentials. VS Code SHALL use its container terminal; JetBrains SHALL use its own built-in ACP client only where
container state persistence is verified.

#### Scenario: Offline ACP readiness

- **WHEN** the installed CLI is checked without provider credentials
- **THEN** hermes acp --check succeeds without starting a model request

#### Scenario: Separate interface sessions

- **WHEN** CLI and eligible JetBrains ACP sessions are saved independently
- **THEN** each retains its own durable state without requiring cross-interface handoff

### Requirement: Supported release range

The feature SHALL accept stable releases at or above 0.22.2; older release formats and unsupported upstream packaging
SHALL fail clearly.

#### Scenario: Release below the supported range

- **WHEN** a release below 0.22.2 is requested
- **THEN** installation fails before changing the installed CLI or runtime state

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
