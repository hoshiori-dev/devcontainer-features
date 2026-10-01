# Spec Delta

## Purpose

Installs the OpenSpec CLI (`openspec`), published on npm as `@fission-ai/openspec`, on a Node.js runtime the feature
brings in as a dependency, and puts it on `PATH` for every user of the container.

Upstream sources:

- Home and README: https://github.com/Fission-AI/OpenSpec
- Installation guide: https://openspec.dev/docs/installation
- Changelog: https://github.com/Fission-AI/OpenSpec/blob/main/CHANGELOG.md

## ADDED Requirements

### Requirement: Install the requested version

The feature SHALL install the npm package `@fission-ai/openspec` at the version the `version` option names, downloading
it and every one of its dependencies from the public npm registry at https://registry.npmjs.org/, regardless of any
registry configured in the image, and SHALL make `openspec` runnable from `PATH` by every user of the container, the
remote user included. The feature SHALL read the version to install, its publish time, and the Node.js version it
requires from the package's registry document at https://registry.npmjs.org/@fission-ai%2fopenspec, relying on TLS alone
and following no redirect; that document only selects what is installed, and the packages are then verified as "Verify
every installed package" requires. The build SHALL fail when the registry names anything other than an exact version as
`latest`, and when the package installed as `@fission-ai/openspec` is not that package at exactly the selected version.

#### Scenario: Registry configured in the image

- **WHEN** the image's environment or its user or global npm configuration names another registry, for all packages or
  for the `@fission-ai` scope, before the feature is installed
- **THEN** every package the feature installs is downloaded from https://registry.npmjs.org/, or the build fails with a
  message naming the package that came from elsewhere

### Requirement: Option version

The feature SHALL accept the option `version` as declared here, holding either `latest`, which resolves to the version
the registry names as latest at build time, or one exact published version (`MAJOR.MINOR.PATCH` with an optional
pre-release suffix).

| Field   | Value      |
| ------- | ---------- |
| Type    | `string`   |
| Default | `"latest"` |

#### Scenario: Omitted version

- **WHEN** the feature is installed without `version`, or with `version` set to `latest`
- **THEN** `openspec --version`, run as the remote user, prints the version the registry named as `latest` when the
  image was built

#### Scenario: Exact version

- **WHEN** the feature is installed with `version` set to a published version such as `1.13.2`
- **THEN** `openspec --version`, run as the remote user, prints exactly that version

#### Scenario: Unknown version

- **WHEN** the feature is installed with `version` set to a well-formed version the registry does not publish
- **THEN** the build fails with a message naming the requested version, before the feature changes any installed file

#### Scenario: Malformed version

- **WHEN** the feature is installed with `version` set to a range, a partial version, or a dist-tag other than `latest`
  (for example `^1.7.0`, `1`, or `beta`)
- **THEN** the build fails before downloading anything, with a message saying that only `latest` or an exact version is
  accepted

### Requirement: Bound dependencies to the release time

The feature SHALL install each dependency of `@fission-ai/openspec` at a version that satisfies the range upstream
declares and that the registry published no later than the OpenSpec version being installed. A dependency release
published after that OpenSpec version SHALL NOT be installed. The publish times come from the registry over TLS alone.

#### Scenario: Dependency released later

- **WHEN** a dependency of the installed OpenSpec version has a release within upstream's range that the registry
  published after that OpenSpec version
- **THEN** the installed version of that dependency is one the registry published no later than the OpenSpec version

### Requirement: Verify every installed package

The feature SHALL verify every package it installs, `@fission-ai/openspec` and each of its dependencies, against the
`sha512` integrity hash the npm registry publishes for that version, and SHALL verify each package's npm registry
signature, and its provenance attestations where the registry publishes them at
`https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>`, with the registry signing keys and the Sigstore
trust root served at https://tuf-repo-cdn.sigstore.dev by Sigstore's public-good TUF repository, which npm uses. When
that TUF repository has no target for the npm registry, the registry signing keys SHALL come from
https://registry.npmjs.org/-/npm/v1/keys, relying on TLS alone. The integrity hashes reach the build from the registry
over TLS alone; the signature check SHALL run on the npm cache the install filled, so that npm checks the signatures of
the package documents the install took those hashes from; this holds only while npm reads those documents from that
cache, which the feature does not enforce, and the feature makes no comparison of its own. A package whose integrity
does not match, whose registry signature is missing or invalid, or whose published provenance attestation is invalid
SHALL fail the build; a package published without a provenance attestation SHALL NOT fail the build for that reason. The
command `openspec` SHALL never reach a package that did not pass. During the build, no install script of a package SHALL
run, and the only package code that runs SHALL be `openspec --version`, as an unprivileged user and never as root.

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

### Requirement: Ignore the image's download settings

The feature SHALL make its build-time requests with full certificate checking against the certificate authorities of the
Node.js found on `PATH`, which it trusts as it is, and nothing else the image holds SHALL change that: no environment
variable of the build other than `PATH`, and no user, global, or project npm configuration, SHALL reach the feature's
Node.js and npm calls, and a certificate authority, proxy, or scoped registry set in the npm configuration built into
the Node.js installation SHALL fail the build before any package is downloaded.

#### Scenario: Certificate checking weakened by the environment

- **WHEN** the build's environment holds settings that weaken or extend certificate checking in Node.js or npm (for
  example `NODE_TLS_REJECT_UNAUTHORIZED=0`, `NODE_EXTRA_CA_CERTS`, `NODE_OPTIONS`, or `npm_config_strict_ssl=false`)
- **THEN** the feature's requests ignore them, and a registry certificate that only those settings would accept fails
  the build

#### Scenario: Certificate settings built into npm

- **WHEN** the npm configuration built into the Node.js installation sets a certificate authority, a proxy, or a scoped
  registry
- **THEN** the build fails before any package is downloaded, with a message naming the setting

### Requirement: Run on a supported Node.js

The feature SHALL depend on the first-party Node.js feature `ghcr.io/devcontainers/features/node` and SHALL run
`openspec` on the Node.js found on `PATH` when the feature was installed. It SHALL fail the build when no Node.js is
found, when no npm is found with it or that npm is older than 10.8.2, the npm that Node.js 20.19.0 ships, or when the
found Node.js is older than the requested OpenSpec version requires (20.19.0 for the current releases). Switching the
default or current Node.js afterwards (for example with `nvm use` or `nvm alias default`) SHALL NOT change the Node.js
that `openspec` runs on.

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

The feature SHALL accept the option `disableUpdateCheck` as declared here and, while it is true, SHALL run `openspec`
with `OPENSPEC_NO_UPDATE_CHECK=1`, the variable upstream's CLI reference
(https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md) defines, unless `OPENSPEC_NO_UPDATE_CHECK` is already set
in the caller's environment, in which case the caller's value SHALL be kept; while it is false, the feature SHALL NOT
set `OPENSPEC_NO_UPDATE_CHECK`.

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

### Requirement: Option disableTelemetry

The feature SHALL accept the option `disableTelemetry` as declared here and, while it is true, SHALL run `openspec` with
`OPENSPEC_TELEMETRY=0`, the variable upstream's CLI reference
(https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md) defines, unless `OPENSPEC_TELEMETRY` is already set in
the caller's environment, in which case the caller's value SHALL be kept; while it is false, the feature SHALL NOT set
`OPENSPEC_TELEMETRY`.

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

### Requirement: Leave the workspace and home untouched

The feature SHALL NOT run `openspec init`, `openspec update`, or any other `openspec` command that writes project or
user files, at build time or at container start, and SHALL leave nothing it created in the remote user's home directory
or the workspace, npm caches and logs of the build included.

#### Scenario: Fresh container

- **WHEN** a container is built with the feature and started
- **THEN** the remote user's home holds no OpenSpec configuration and no npm cache or log that the feature created, and
  the workspace holds no `openspec/` directory or agent skill files that the feature created

### Requirement: Install twice

Installing the feature a second time in the same image SHALL succeed, with the same or with different options. The later
install's `version`, `disableUpdateCheck`, and `disableTelemetry` SHALL win, and exactly one OpenSpec installation SHALL
remain reachable as `openspec`.

#### Scenario: Same options twice

- **WHEN** the feature is installed twice with the same options
- **THEN** both installs succeed and `openspec --version` prints the version the options name

#### Scenario: Different options the second time

- **WHEN** the feature is installed with a non-default `version`, `disableUpdateCheck`, and `disableTelemetry`, and then
  again with their defaults
- **THEN** both installs succeed, `openspec --version` prints the version the second install resolved, and the
  `openspec` process sees the environment the second install's options define

### Requirement: Fail on unsupported platforms

The feature's install step SHALL fail the build before it downloads anything when the image's distribution is not Debian
or Ubuntu (`ID` or `ID_LIKE` in `/etc/os-release` naming `debian`) or its architecture is not amd64 or arm64, with a
message naming the distribution or architecture it found. The images the feature supports are listed in
`test/openspec/compatibility.json`.

#### Scenario: Unsupported distribution

- **WHEN** the feature's install step runs on an image whose `/etc/os-release` names neither Debian nor a Debian
  derivative
- **THEN** the build fails with a message naming the distribution found, before the feature downloads anything

#### Scenario: Unsupported architecture

- **WHEN** the feature's install step runs on an image whose architecture is neither amd64 nor arm64
- **THEN** the build fails with a message naming the architecture found, before the feature downloads anything
