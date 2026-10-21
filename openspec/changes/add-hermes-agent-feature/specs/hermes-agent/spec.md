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

The feature SHALL support only the image and architecture combinations declared in
`test/hermes-agent/compatibility.json`. It SHALL reject an unsupported distribution, architecture, or requested release
before installing the CLI.

#### Scenario: Supported installation

- **WHEN** a declared target and supported release are selected
- **THEN** `hermes --version` runs successfully as the remote user

#### Scenario: Unsupported target

- **WHEN** the target is not supported
- **THEN** installation fails with a clear target-specific error

### Requirement: Project-scoped state

The feature SHALL use the named volume `hermes-agent-${devcontainerId}` mounted at `/var/lib/hermes-agent` for private
CLI configuration, credentials, and durable conversations. Executables SHALL not be hidden by this mount. Container
identity changes and another Docker host SHALL not imply automatic state migration.

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

The feature SHALL configure `HERMES_HOME=/var/lib/hermes-agent`. Explicit upstream state overrides outside this root
SHALL be documented as outside the persistence guarantee. Existing conflicting files or directories SHALL not be
silently replaced or imported.

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

The feature SHALL document VS Code's container terminal and JetBrains' built-in ACP client running the official
`hermes acp` server. Only first-party agent integrations or IDE-vendor built-in clients connected to official agent
servers qualify. Separate CLI/IDE login and conversation stores SHALL be allowed.

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
