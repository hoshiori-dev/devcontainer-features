# Tasks

## 1. Feature

- [ ] 1.1 Scaffold `src/openspec/` and `test/openspec/` with `just new-feature openspec` and verify that the generated
      `devcontainer-feature.json` declares exactly the options `version` (`string`, default `"latest"`),
      `disableUpdateCheck` (`boolean`, default `true`), and `disableTelemetry` (`boolean`, default `false`), as the
      Option requirements state
- [ ] 1.2 Complete `src/openspec/devcontainer-feature.json`: version `1.0.0`, `name`, a one-sentence `description`,
      `documentationURL`, a description per option, the `version` proposals `["latest","1.13.1"]`, and `dependsOn`
      `ghcr.io/devcontainers/features/node:2` with options `{}` (design, Options and Decisions - Runtime); verify with
      `just validate` and `just spec-check`, and by reading the file for the absence of `installsAfter`, `mounts`,
      `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, `containerEnv`, and lifecycle commands
- [ ] 1.3 Write the checks of `src/openspec/install.sh` that run before any network access (`#!/usr/bin/env bash`,
      `set -euo pipefail`, `umask 022`), in the design's order: the distribution (`ID` or `ID_LIKE` naming `debian`) and
      the architecture (amd64 or arm64), each failure naming what was found; the `version` format (`latest` or one exact
      version), the failure saying that only `latest` or an exact version is accepted; Node.js on `PATH`, the failure
      naming 20.19.0; npm on `PATH` at 10.8.2 or newer, the failure naming the required version and the one found;
      verify with `shellcheck` and by running each failure in a throwaway container (tasks 4.1, 4.5, 4.6)
- [ ] 1.4 Write the download settings and the version selection of `install.sh`: every Node.js and npm call under
      `env -i` with `PATH` and a `HOME` in a temporary directory that a trap removes; the npm flags of design - Goals
      (registry, `--strict-ssl=true`, two distinct empty configuration files, `--ignore-scripts`, `--engine-strict`,
      `--no-audit`, `--no-update-notifier`, a cache in the temporary directory); the `npm config list --json` check
      (`strict-ssl`, `registry`, `ca`, `cafile`, `proxy`, `https-proxy`, no key ending in `:registry`) failing with the
      key's name before the first download; one read of `https://registry.npmjs.org/@fission-ai%2fopenspec` with `fetch`
      and `redirect: 'error'`, selecting `dist-tags.latest` or the exact version, which must match the exact-version
      pattern, be a key of `versions`, and have a publish time that parses as a date; the found Node.js compared with
      the selected version's `engines.node`; verify with `shellcheck`, by review against design - Goals (no other
      download tool, no OS package, no URL outside the URL inventory, no switch that weakens verification), and by the
      runs of tasks 4.1, 4.3, 4.4, and 4.5
- [ ] 1.5 Write the install, verification, and replacement of `install.sh`: `npm install` of the selected version with
      `--before=<its publish time>` into a staging directory next to `/usr/local/lib/openspec`; the lockfile checks (the
      entry `node_modules/@fission-ai/openspec` at exactly the selected version and without an alias `name`, every other
      entry's `resolved` under `https://registry.npmjs.org/`, the failure naming the entry); `npm audit signatures` on
      the install's cache with `--prefer-offline`; `openspec --version` of the staged tree as uid and gid 65534 through
      `setpriv`, under `env -i` with telemetry and the update check off; only then the prefix replaced as a whole and
      the wrapper `/usr/local/bin/openspec` rewritten, which runs the Node.js binary resolved at install time and
      exports `OPENSPEC_NO_UPDATE_CHECK=1` and `OPENSPEC_TELEMETRY=0` only when the option is true and the caller has
      not set the variable; verify with `shellcheck`, by review against design - Goals, and by a build on `debian:12` in
      which `openspec --version` prints the selected version
- [ ] 1.6 Write `src/openspec/NOTES.md`: telemetry first, with its endpoint and the option that turns it off; the update
      check and why it is off by default (an `npm install -g` copy shadows the wrapper); what is verified and what rests
      on TLS alone; the hosts a build needs, and that a private registry, mirror, proxy, or added certificate authority
      is not supported; the Node.js feature as the bootstrap of the chain of trust, its group-writable installation, a
      consumer's own `node:2` entry with other options, and the pinned install-time Node.js; the intermittent audit
      failure of npm 10.9.9; the supported images; then regenerate `src/openspec/README.md` with `just docs` and verify
      that `just docs-check` passes

## 2. Container tests

- [ ] 2.1 Write `test/openspec/compatibility.json` with `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (`amd64`,
      `arm64`, `remoteUser` `vscode`) and `debian:12` (`amd64`, `arm64`); verify with `just validate` and against
      design - Security review surface, Supported images
- [ ] 2.2 Write `test/openspec/test.sh` for the default options: "Fresh container" before anything runs `openspec` (no
      OpenSpec configuration, npm cache, or npm log of the build in the remote user's home, no `openspec/` directory or
      agent skill files in the workspace); `command -v openspec` resolving to the root-owned wrapper, the root-owned
      prefix holding `package.json`, `package-lock.json`, and `node_modules/`; "Omitted version" and "Verified install"
      (`openspec --version`, as the remote user, equal to the registry's `latest` read at test time); "Omitted
      disableUpdateCheck", "Caller's update-check value wins", and "Omitted disableTelemetry" through the environment
      probe; verify with `shellcheck` and `just test openspec`
- [ ] 2.3 Write `test/openspec/duplicate.sh` ("Different options the second time"): after a first install with `version`
      `1.13.1`, `disableUpdateCheck` false, and `disableTelemetry` true and a second with the defaults,
      `openspec --version` prints the registry's `latest`, the probe shows the second install's environment, and exactly
      one installation is reachable (one `openspec` on `PATH`, no staging directory left); verify with `shellcheck` and
      `just test openspec`
- [ ] 2.4 Write `test/openspec/scenarios.json` and its scripts, each scenario once per compatibility image: non-default
      options (`version` `1.13.2`, `disableUpdateCheck` false, `disableTelemetry` true: "Exact version", "Dependency
      released later" by comparing the registry publish time of every `package-lock.json` entry with that of the
      installed OpenSpec version, "Update check left to the user", "Telemetry disabled", "Caller's telemetry value
      wins"); the defaults written out, with a second Node.js installed through nvm and made the default in the script
      ("Update check disabled", "Telemetry left to the user", "Current Node.js switched later"); and a `build` scenario
      whose Dockerfile writes `@fission-ai:registry=` with an unreachable host into root's `~/.npmrc` ("Registry
      configured in the image": the build succeeds and every `package-lock.json` entry resolves under
      `https://registry.npmjs.org/`); verify with `just validate`, `shellcheck`, and `just test-scenarios openspec`

## 3. Repository README

- [ ] 3.1 Add the `openspec` row under "## Features" in the root `README.md`, with the id linking to `src/openspec/` and
      a one-sentence description, replacing "No features have been published yet."; verify with
      `deno fmt --check README.md` and by reading the section

## 4. Local runs of the failing builds

Each run executes the staged `src/openspec/install.sh` unchanged, as root, with the option environment variables, on
amd64 (design, Decisions - Tests); the exact command and its result go to the PR's Validation section.

- [ ] 4.1 In a container kept from `just test openspec --preserve` on `debian:12`: "Unknown version" (`9.9.9`),
      "Malformed version" (`^1.7.0`, `1`, `beta`), and "Same options twice"; verify the stated message and exit status
      of each failure, that the malformed values fail without a request, that the installed version, wrapper, and prefix
      are the same before and after each failure, and that the second identical install succeeds and prints the same
      version
- [ ] 4.2 "Verification failure", signing keys unreachable: in a container started with
      `--add-host tuf-repo-cdn.sigstore.dev:127.0.0.1` from an image committed from such a kept container, installing a
      version other than the one present; verify that the install fails naming the signature verification and that
      `openspec --version`, the wrapper, and the prefix are unchanged
- [ ] 4.3 "Verification failure" and "Package altered during the install only", altered registry answers: with
      `registry.npmjs.org` mapped to a local TLS proxy that forwards to the registry and a `node` wrapper first on
      `PATH` that also trusts the proxy's test certificate authority, one run each in which the proxy alters, for one
      dependency, its tarball (`EINTEGRITY`); its tarball and `dist.integrity` in every answer (invalid registry
      signature); both in its first answer only (invalid registry signature on the install's cache); its `dist.tarball`,
      pointing to another host that serves the same bytes (the lockfile check, naming the entry); and one run that
      alters `dist-tags.latest` to a value that is not an exact version (fails before npm installs anything); verify
      that each run fails as stated and leaves `openspec --version`, the wrapper, and the prefix unchanged
- [ ] 4.4 "Certificate checking weakened by the environment" and "Certificate settings built into npm": the same proxy
      without the `node` wrapper, with `NODE_EXTRA_CA_CERTS` naming the test certificate authority,
      `NODE_OPTIONS=--use-openssl-ca` with `SSL_CERT_FILE` naming it, `NODE_TLS_REJECT_UNAUTHORIZED=0`, and
      `npm_config_strict_ssl=false` in the environment, and verify that the install fails on the proxy's certificate at
      the registry document read; then, without the proxy, a `cafile` line written into the npmrc built into npm, and
      verify that the install fails before any download, naming the key
- [ ] 4.5 "No Node.js" in a plain `debian:12` container; "Node.js too old" in `node:20.18-bookworm-slim`; "npm missing
      or too old" in `node:20.19.0-bookworm-slim` with its npm replaced by 10.8.1, and again with npm taken off `PATH`;
      verify the stated message of each
- [ ] 4.6 "Unsupported distribution" in `fedora:44` and "Unsupported architecture" in `debian:12` run with
      `--platform linux/ppc64le` under qemu user emulation; verify that each fails naming the distribution or
      architecture found, before any download

## 5. Validation

- [ ] 5.1 Run `just check` and verify it passes
- [ ] 5.2 Run `just test openspec` and verify the autogenerated and install-twice tests pass on every image of the
      compatibility list (arm64 in CI)
- [ ] 5.3 Run `just test-scenarios openspec` and verify every scenario passes
- [ ] 5.4 Record each Acceptance item and each scenario of the delta spec with its test or local run, image,
      architecture, and result in the PR's Validation section
