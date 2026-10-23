# Spec Delta

## MODIFIED Requirements

### Requirement: Install the requested version

The feature SHALL install the exact selected OpenSpec npm package for every container user.

#### Scenario: Registry configured in the image

- **WHEN** the image's environment or its user or global npm configuration names another registry, for all packages or
  for the `@fission-ai` scope, before the feature is installed
- **THEN** every package the feature installs is downloaded from https://registry.npmjs.org/, or the build fails with a
  message naming the package that came from elsewhere

#### Scenario: Installed locations

- **WHEN** the feature is installed
- **THEN** `command -v openspec` resolves to `/usr/local/bin/openspec`, the package `@fission-ai/openspec` and its
  dependencies are under `/usr/local/lib/openspec`, and that file and everything under that directory are owned by root
  and writable only by root

### Requirement: Verify every installed package

The feature SHALL verify every installed package before exposing the `openspec` command.

#### Scenario: Verified install

- **WHEN** the feature is installed and every package passes verification
- **THEN** the build succeeds and `openspec --version` prints the requested version

#### Scenario: Verification failure

- **WHEN** any installed package fails its integrity or signature verification
- **THEN** the build fails with a message naming the verification that failed, and an `openspec` installed earlier in
  the same image stays as it was

#### Scenario: Package altered during the install only

- **WHEN** the registry document and the tarball of a package are altered while the feature installs it, the registry
  answers unaltered afterwards, and npm reads that package's document from the cache the install filled
- **THEN** the build fails on that package's registry signature

### Requirement: Run on a supported Node.js

The feature SHALL install OpenSpec only with a compatible Node.js and npm.

#### Scenario: No Node.js

- **WHEN** the feature's install step runs while no Node.js is on `PATH`
- **THEN** the build fails with a message saying that Node.js is required and naming the minimum version

#### Scenario: Node.js too old

- **WHEN** the feature is installed while the Node.js on `PATH` is older than the requested OpenSpec version requires
  and its npm is 10.8.2 or newer
- **THEN** the build fails with a message naming the found and the required Node.js version

#### Scenario: npm missing or too old

- **WHEN** the feature is installed while no npm is on `PATH`, or the npm on `PATH` is older than 10.8.2
- **THEN** the build fails with a message naming the required npm version and the one found, if any

#### Scenario: Current Node.js switched later

- **WHEN** the remote user makes a different installed Node.js the current one after the build
- **THEN** `openspec --version` still prints the installed version, running on the Node.js it was installed with

### Requirement: Option disableUpdateCheck

The feature SHALL accept `disableUpdateCheck` to control the upstream update-check variable.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `true`    |

#### Scenario: Omitted disableUpdateCheck

- **WHEN** the feature is installed without `disableUpdateCheck` and `openspec` runs with `OPENSPEC_NO_UPDATE_CHECK`
  unset
- **THEN** the `openspec` process sees `OPENSPEC_NO_UPDATE_CHECK=1`

#### Scenario: Update check disabled

- **WHEN** the feature is installed with `disableUpdateCheck` true and `openspec` runs with `OPENSPEC_NO_UPDATE_CHECK`
  unset
- **THEN** the `openspec` process sees `OPENSPEC_NO_UPDATE_CHECK=1`

#### Scenario: Caller's update-check value wins

- **WHEN** the feature is installed with `disableUpdateCheck` true and `openspec` runs with `OPENSPEC_NO_UPDATE_CHECK`
  set to the empty string in the caller's environment
- **THEN** the `openspec` process sees `OPENSPEC_NO_UPDATE_CHECK` set to the empty string

#### Scenario: Update check left to the user

- **WHEN** the feature is installed with `disableUpdateCheck` false
- **THEN** the `openspec` process sees `OPENSPEC_NO_UPDATE_CHECK` exactly as the caller's environment has it, unset when
  the caller has not set it

#### Scenario: Invalid disableUpdateCheck

- **WHEN** the feature is installed with `disableUpdateCheck` set to a value that is neither `true` nor `false`, such as
  `yes`, `TRUE`, `1`, or an empty value
- **THEN** the build fails before downloading anything, with a message naming the option and the value

### Requirement: Option disableTelemetry

The feature SHALL accept `disableTelemetry` to control the upstream telemetry variable.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted disableTelemetry

- **WHEN** the feature is installed without `disableTelemetry`
- **THEN** the `openspec` process sees `OPENSPEC_TELEMETRY` exactly as the caller's environment has it, unset when the
  caller has not set it

#### Scenario: Telemetry disabled

- **WHEN** the feature is installed with `disableTelemetry` true and `openspec` runs with `OPENSPEC_TELEMETRY` unset
- **THEN** the `openspec` process sees `OPENSPEC_TELEMETRY=0`

#### Scenario: Caller's telemetry value wins

- **WHEN** the feature is installed with `disableTelemetry` true and `openspec` runs with `OPENSPEC_TELEMETRY=1` in the
  caller's environment
- **THEN** the `openspec` process sees `OPENSPEC_TELEMETRY=1`

#### Scenario: Telemetry left to the user

- **WHEN** the feature is installed with `disableTelemetry` false
- **THEN** the `openspec` process sees `OPENSPEC_TELEMETRY` exactly as the caller's environment has it, unset when the
  caller has not set it

#### Scenario: Invalid disableTelemetry

- **WHEN** the feature is installed with `disableTelemetry` set to a value that is neither `true` nor `false`, such as
  `yes`, `TRUE`, `1`, or an empty value
- **THEN** the build fails before downloading anything, with a message naming the option and the value

## ADDED Requirements

### Requirement: OpenSpec registry metadata selection

The feature SHALL read the selected version, publish time, and required Node.js version from
`https://registry.npmjs.org/@fission-ai%2fopenspec`, relying on TLS alone and following no redirect. The document
selects the package only; package verification is governed by “Verify every installed package.” A `latest` response that
names anything other than an exact version SHALL fail.

#### Scenario: Registry document is not a direct response

- **WHEN** the package metadata request redirects
- **THEN** the feature does not follow the redirect

### Requirement: OpenSpec package source and placement

The feature SHALL download `@fission-ai/openspec` and all dependencies from `https://registry.npmjs.org/`, ignoring
registry settings from the build environment and user, global, or project npm configuration. It SHALL install under
`/usr/local/lib/openspec`, provide `/usr/local/bin/openspec`, and keep that command and directory tree root-owned and
writable only by root. The installed package SHALL match the exact selected package name and version.

#### Scenario: Alternate npm registry configured

- **WHEN** the environment or npm configuration names another registry
- **THEN** all packages still come from the public npm registry and the selected exact package is installed

### Requirement: Verify OpenSpec package integrity

The feature SHALL verify `@fission-ai/openspec` and every dependency against its registry-published `sha512` integrity
hash. Hashes are received over TLS alone; npm's signature check SHALL run on the install-populated cache and checks the
package documents from which npm obtained those hashes. The feature does not enforce cache reads or compare hashes
itself.

#### Scenario: Package integrity mismatch

- **WHEN** any installed package fails its registry `sha512` check
- **THEN** the build fails and the command cannot reach that package

### Requirement: OpenSpec registry signing keys

Registry signing keys and Sigstore trust root SHALL come from Sigstore's public-good TUF repository at
`https://tuf-repo-cdn.sigstore.dev`. If it has no npm registry target, keys SHALL come from
`https://registry.npmjs.org/-/npm/v1/keys` over TLS alone.

#### Scenario: TUF repository lacks npm target

- **WHEN** Sigstore's TUF repository has no target for the npm registry
- **THEN** the registry signing keys come from the npm keys endpoint over TLS

### Requirement: OpenSpec package signatures and provenance

The feature SHALL verify each package's npm registry signature and any published provenance at
`https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>`. Missing or invalid signatures and invalid published
attestations fail; absence of a provenance attestation alone SHALL NOT fail.

#### Scenario: Provenance is not published

- **WHEN** a package has no provenance attestation but has valid integrity and registry signature
- **THEN** the build does not fail for the missing attestation

### Requirement: OpenSpec package execution during build

The command SHALL never reach a package that failed verification. No package install script SHALL run during the build;
the only package code run SHALL be `openspec --version` as an unprivileged user, never root.

#### Scenario: Package code execution is restricted

- **WHEN** OpenSpec is installed and checked during the build
- **THEN** install scripts do not run and only unprivileged `openspec --version` executes

### Requirement: OpenSpec Node.js and npm compatibility

The feature SHALL depend on `ghcr.io/devcontainers/features/node` and bind OpenSpec to the Node.js on `PATH` at
installation. Fail if Node.js or its npm is missing, npm is below `10.8.2`, or Node.js is below the selected release's
requirement (currently `20.19.0`). Later changes to default/current Node.js, including `nvm use` or `nvm alias default`,
SHALL NOT change the Node.js OpenSpec runs on.

#### Scenario: Node.js selection later changes

- **WHEN** the user switches default or current Node.js after feature installation
- **THEN** `openspec` continues to run on the Node.js selected during installation

### Requirement: OpenSpec update-check environment

When `disableUpdateCheck` is true, run OpenSpec with `OPENSPEC_NO_UPDATE_CHECK=1` unless the caller already set that
variable, whose value SHALL win. When false, the feature SHALL NOT set it. Values other than `true` or `false`,
including empty, fail the build. The variable name is defined by the upstream CLI reference at
`https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md`.

#### Scenario: Caller sets update-check variable

- **WHEN** update checks are disabled and the caller already sets `OPENSPEC_NO_UPDATE_CHECK`
- **THEN** OpenSpec receives the caller's value

### Requirement: OpenSpec telemetry environment

When `disableTelemetry` is true, run OpenSpec with `OPENSPEC_TELEMETRY=0` unless the caller already set that variable,
whose value SHALL win. When false, the feature SHALL NOT set it. Values other than `true` or `false`, including empty,
fail the build. The variable name is defined by the upstream CLI reference at
`https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md`.

#### Scenario: Caller sets telemetry variable

- **WHEN** telemetry is disabled and the caller already sets `OPENSPEC_TELEMETRY`
- **THEN** OpenSpec receives the caller's value
