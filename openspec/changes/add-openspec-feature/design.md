# Design

## Context

See proposal.md - Why. The behavior is in `specs/openspec/spec.md`; this file records how it is reached and what was
checked on 2026-09-30 to choose it.

- **Package.** `@fission-ai/openspec` 1.13.2 is `dist-tags.latest` (published 2026-09-23; 1.13.1 was published
  2026-09-17); the other tags are `next=0.3.0` (stale) and `beta=1.6.0-beta.1`. It is pure JavaScript with no `os` or
  `cpu` field, `bin` `openspec` → `bin/openspec.js` (`#!/usr/bin/env node`), `engines.node` `>=20.19.0` (1.12.0 through
  1.13.2), 10 runtime dependencies resolving to 70 packages, none with an install script. The tarball ships no
  `npm-shrinkwrap.json`, so dependency versions resolve within the declared ranges at install time.
- **Registry endpoints.** `GET /{package}/{version}` accepts a version or `latest` and answers 404 for an unpublished
  version (probed with `9.9.9`); it also answers for any other dist-tag (`beta`), which is why the format of `version`
  is checked before asking.
- **Integrity and signatures.** Every version's `dist` carries a `sha512` `integrity` and `signatures` over
  `<name>@<version>:<integrity>`. npm's fetcher takes `dist.integrity` from the manifest and rejects a tarball that does
  not match it with `EINTEGRITY` (https://github.com/npm/pacote/blob/main/lib/registry.js, the `dist` handling in
  `manifest()`; the `integrity` option in https://github.com/npm/pacote/blob/main/README.md). All signatures of 1.13.2
  use keyid `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U` (`ecdsa-sha2-nistp256`, no expiry). The same key is the
  TUF target `registry.npmjs.org/keys.json` in Sigstore's public-good TUF repository (valid from 2025-01-13) and is
  listed at the registry's keys endpoint; the previous key `SHA256:jl3bwswu80PjjokCgh0o2w5c2U4LhQAE57gj9cz1kzA` expired
  2025-01-29. 1.13.2 also carries a SLSA v1 provenance attestation built by `Fission-AI/OpenSpec`
  `.github/workflows/release-prepare.yml` on `refs/heads/main`.
- **npm's verifier.** `npm audit signatures` verifies registry signatures and provenance attestations of an installed
  tree and exits non-zero on an invalid or missing signature; a package without an attestation is not an error. It takes
  the registry keys from the Sigstore TUF repository (`@sigstore/tuf`, default mirror
  `https://tuf-repo-cdn.sigstore.dev`, root metadata shipped inside npm) and falls back to the registry's keys endpoint
  only when TUF has no target for the registry (`TUF_FIND_TARGET_ERROR`), not when the mirror is unreachable: with
  `tuf-repo-cdn.sigstore.dev` mapped to `127.0.0.1` the audit failed with `ECONNREFUSED` and exit 1 (npm bundled with
  Node.js 22.23.3). Attestation verification is offline against the TUF `trusted_root.json`; the Rekor and Fulcio URLs
  in npm's bundle are used only for signing. It refuses global installs (`EAUDITGLOBAL`, observed with npm 11.19.0), and
  works on a project tree: `npm install --prefix <dir>` of 1.13.2 followed by `npm audit signatures --prefix <dir>`
  reported 70 verified registry signatures and 22 verified attestations.
- **npm configuration.** A `--registry` flag does not override a scoped `@scope:registry=` line from a user or global
  npmrc: with `@fission-ai:registry=https://example.invalid/` in `/root/.npmrc`, `npm install --registry=…` failed with
  `ENOTFOUND`. `--userconfig` and `--globalconfig` both set to `/dev/null` make npm exit
  (`double-loading config
  "/dev/null" as "global", previously loaded as "user"`); two distinct empty files work and
  ignored the same `/root/.npmrc`, and all 70 `package-lock.json` entries then resolved under
  `https://registry.npmjs.org/`. Without `--no-audit` and `--no-update-notifier`, `npm install` also posts to the
  registry's bulk advisory endpoint and fetches the `npm` packument.
- **Node.js feature.** `ghcr.io/devcontainers/features/node` is at 2.1.0 (GHCR tags `2`, `2.0`, `2.0.0`, `2.1`,
  `2.1.0`); major 2 is current. It installs Node.js with nvm under `/usr/local/share/nvm`, links `current` to the
  default version, and sets `PATH=/usr/local/share/nvm/current/bin:${PATH}` in `containerEnv`. Its option defaults are
  `version` `lts` (it also accepts `none`), `nodeGypDependencies` true (apt build tools), `pnpmVersion` `latest`,
  `nvmVersion` `latest`, `npmVersion` `none`, `installYarnUsingApt` false. It detects apt, dnf, microdnf, and yum only
  (no Alpine). The devcontainer CLI (0.89.0) emits each feature's `containerEnv` as `ENV` before that feature's layer,
  so the Node.js on `PATH` is visible to features installed after it. Per the Dev Container feature-dependencies spec,
  two entries of one feature are equal only with equal options, so a consumer's own `node:2` entry with other options
  installs Node.js a second time.
- **Duplicate test.** The devcontainer CLI's duplicate test (0.89.0, without `--permit-randomization`, which this
  repository does not pass) sets a string option with `proposals` to the first proposal that is not the default, and a
  boolean to the negation of its default. Two identical feature entries are merged into one install, so "Same options
  twice" cannot be produced through the CLI.
- **OpenSpec's runtime network.** Telemetry posts to `https://edge.openspec.dev/batch/`, a PostHog-managed reverse proxy
  on upstream's domain. The update check runs only inside `openspec update`; it asks
  `https://registry.npmjs.org/@fission-ai/openspec/latest` (or `npm_config_registry` when the environment sets it) and
  follows cross-host HTTPS redirects. For an install that is not npm's global tree, which the prefix below is not, it
  prints an upgrade command (`npm install -g @fission-ai/openspec@latest` for npm) instead of running it (upstream
  `docs/cli.md`, `src/core/version-check.ts` `buildUpgradeCommandLines`, `canSelfUpgrade`). `OPENSPEC_NO_UPDATE_CHECK`
  (any value, even empty) skips the check; `OPENSPEC_TELEMETRY=0` or `DO_NOT_TRACK=1` disables telemetry and also the
  check; both are off under a truthy `CI` and when the global config sets `telemetry.enabled: false`.
  `openspec --version` exits before the telemetry hook and wrote nothing to an empty `HOME` (1.13.2, telemetry on).
- **Prior art.** `.devcontainer/setup.sh` installs the CLI with Deno and fetches Deno with an unpinned `curl … | sh`;
  nothing of it is reused, and it stays unchanged (out of scope).

## Goals / Non-Goals

**Goals:**

- `openspec` lives in a root-owned prefix `/usr/local/lib/openspec`, installed there as an npm project tree
  (`package.json`, `package-lock.json`, `node_modules/`), and is reached only through the root-owned wrapper
  `/usr/local/bin/openspec`. Checked by `test.sh` (the path `command -v openspec` resolves to, ownership, and a non-root
  remote user running it) and `duplicate.sh`.
- All network access at build time goes through the dependency's Node.js and npm, to the hosts in the URL inventory
  only; the feature adds no OS package and no other download tool. Checked by review of `install.sh` against the URL
  inventory.
- npm runs with `--registry=https://registry.npmjs.org/`, `--userconfig` and `--globalconfig` set to two distinct empty
  files in a temporary directory, `--ignore-scripts`, `--engine-strict`, `--no-audit`, `--no-update-notifier`, and a
  cache in that temporary directory, which is removed on exit, success or failure; no `npm_config_*` variable of the
  environment (any letter case) reaches npm. After the install, every entry of `package-lock.json` other than the root
  must have a `resolved` URL starting with `https://registry.npmjs.org/`, or the install fails naming the entry. Checked
  by review of `install.sh`, by a `build` scenario whose Dockerfile writes `@fission-ai:registry=` with an unreachable
  host into root's `~/.npmrc` and still installs, and by `test.sh` asserting the remote user's home holds no npm cache
  or log from the build.
- A new tree is installed and verified in a staging directory next to the prefix and replaces the prefix only after the
  lockfile check and `npm audit signatures` pass; a failed install leaves the previous prefix and wrapper as they were.
  `install.sh` has no switch or environment hook that weakens or skips verification. Checked by review of `install.sh`
  and by the verification-failure run under Decisions - Tests.
- The wrapper `exec`s the Node.js binary resolved (symlinks followed) from `PATH` at install time with the package's
  `bin/openspec.js`, passes the caller's environment through unchanged, and exports `OPENSPEC_NO_UPDATE_CHECK` /
  `OPENSPEC_TELEMETRY` only when the option is true and the variable is unset (`${VAR+set}` test, so an empty value
  counts as set). Checked by the option scenarios with the environment probe under Decisions - Tests, and by a scenario
  that switches nvm's default after the build.
- Every install replaces the prefix and rewrites the wrapper; there is no skip for an already installed version. Checked
  by `duplicate.sh`: with the `version` proposals under Options, the first install is always 1.13.1 and the second the
  newer `latest`, which exercises the replacement on every run.
- `install.sh` uses `#!/usr/bin/env bash` with `set -euo pipefail` (bash is in every listed image) and checks, in this
  order, the distribution and architecture, the `version` format, and the presence of Node.js, all before any network
  access; the found Node.js is compared with the resolved version's `engines.node` before npm runs. Checked by
  shellcheck in `just check` and the local runs under Decisions - Tests.
- The build-time `openspec --version` check runs the staged tree with `OPENSPEC_TELEMETRY=0`,
  `OPENSPEC_NO_UPDATE_CHECK=1`, and `HOME` and `XDG_CONFIG_HOME` pointing into the temporary directory, so it cannot
  write to root's home, which is the remote home on `debian:12`. Checked by review and by the "Fresh container" test on
  `debian:12`.

**Non-Goals:**

- Installing Node.js itself, or choosing its version: the Node.js feature does both.
- Supporting a private registry or mirror at build time.
- Supporting an HTTP(S) proxy at build time: the version lookup uses Node.js `fetch`, which does not read
  `HTTP(S)_PROXY` by default, while npm does.
- Following new OpenSpec releases after the build; `openspec update` or a self-upgrade inside the container.
- Pinning dependency versions below `@fission-ai/openspec` (upstream ships no shrinkwrap).
- Running any `openspec` command at build or start time other than `--version` for verification.

## Options

All three options are new; the delta spec's Option requirements are normative.

| Name                 | Type      | Default    | Enum or proposals               | Meaning                                                                    |
| -------------------- | --------- | ---------- | ------------------------------- | -------------------------------------------------------------------------- |
| `version`            | `string`  | `"latest"` | proposals `["latest","1.13.1"]` | OpenSpec version to install: `latest` or one exact published version       |
| `disableUpdateCheck` | `boolean` | `true`     | none                            | Run `openspec` with `OPENSPEC_NO_UPDATE_CHECK=1` unless the caller sets it |
| `disableTelemetry`   | `boolean` | `false`    | none                            | Run `openspec` with `OPENSPEC_TELEMETRY=0` unless the caller sets it       |

Defaults:

- **`version` `"latest"`.** Follows upstream's install command (`npm install -g @fission-ai/openspec@latest`) and the
  proposal's "following the latest release"; a consumer who needs a reproducible build names an exact version. The
  proposal `1.13.1` is a published version older than `latest`, so `duplicate.sh` replaces one version with another
  (Goals).
- **`disableUpdateCheck` `true`.** Inside `openspec update`, the check prints `npm install -g …@latest` for this install
  (Context); following it lands a second copy in nvm's global prefix, earlier on `PATH` than `/usr/local/bin`, which
  shadows the verified installation.
- **`disableTelemetry` `false`.** Telemetry keeps upstream's opt-out default; the option makes opting out one line.

Rejected option shapes:

- `version` accepting ranges (`^1.7.0`) — the installed version would depend on the build date without the consumer
  seeing it.
- `version` accepting partial versions (`1`) or dist-tags other than `latest` (`beta`) — npm reads a partial version as
  a range; `latest` is the one moving target the feature accepts on purpose, and the other tags are not kept current
  (`next=0.3.0` is stale, `beta=1.6.0-beta.1` is older than `latest`; Context).
- `version` as an `enum` — every OpenSpec release after the feature's would need a feature release before it could be
  installed.
- A registry or mirror option — the source is pinned to the one the spec names (Non-Goals, Risks).
- A Node.js version option — the Node.js feature chooses it (Non-Goals).

## Decisions

- **Runtime: Node.js through `dependsOn` on `ghcr.io/devcontainers/features/node:2`, with options `{}`.** The maintainer
  chose Node.js; it is upstream's primary install path, `npm audit signatures` verifies registry signatures and
  provenance, and the Node.js feature is first-party and maintained. `{}` accepts that feature's defaults, including
  `nodeGypDependencies` (apt build tools) and pnpm `latest`; other options would make a consumer's own `node:2` `{}`
  entry a second Node.js install. Rejected: Deno through this repository's planned `deno` feature (#16) with upstream's
  permission set — sandboxed, but not yet published and outside the maintainer's choice; a Node.js binary downloaded by
  this feature — would duplicate the Node.js feature and its verification; `installsAfter` instead of `dependsOn` — a
  consumer would have to add Node.js by hand.
- **Dedicated prefix instead of `npm install -g`.** A global install lands in nvm's per-version prefix, so it disappears
  from `PATH` when the current Node.js changes, and `npm audit signatures` refuses global trees. A project tree in
  `/usr/local/lib/openspec` survives nvm switches and can be audited. Rejected: `npm install -g --prefix` — installs
  outside nvm but still cannot be audited; `npx` at run time — downloads on every cold start, unverified.
- **Wrapper runs the install-time Node.js.** The package's shebang `#!/usr/bin/env node` would follow whatever Node.js
  is current, which a project's `.nvmrc` or `nvm use` can drop below 20.19.0. Pinning the resolved binary keeps
  `openspec` on a Node.js that passed `--engine-strict`. Rejected: `node` from `PATH` at run time — breaks silently when
  the current version is too old; a separate Node.js only for OpenSpec — duplicates the dependency.
- **Verification: npm's own registry checks, `npm audit signatures` on top, no keyid pin.** Every package comes from the
  npm registry's index, so `feature-authoring.md` (Downloads: package managers and registries) leaves its verification
  to npm, which checks every tarball against the `sha512` `dist.integrity` of its manifest (Context). That checksum
  comes from the same host as the tarball, so on its own it rests on TLS to `registry.npmjs.org`; `npm audit signatures`
  adds the registry's ECDSA signature over each package's name, version, and integrity, and each published provenance
  attestation, with keys delivered through TUF from the root shipped inside npm. A missing or invalid signature, or an
  invalid attestation, fails; a missing attestation does not (spec: Verify every installed package). The registry is
  npm's default, not a repository the feature adds, so the rule's fingerprint pin does not apply. The two requests that
  rest on TLS alone, the version lookup and npm's fallback keys endpoint, are stated as Requirements, as the rule's
  direct-download clause asks (spec: Install the requested version; Verify every installed package). Trade-off of not
  pinning the keyid `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`: a registry key rotation passes through TUF
  instead of failing every build until a feature release. Rejected: integrity only — what the rule requires at minimum,
  but it trusts nothing beyond TLS to the registry; the keyid pin in `install.sh` — adds no trust root beyond TUF,
  breaks builds on a legitimate rotation, and needs every package's manifest signatures read again by `install.sh`;
  verifying the top-level signature in `install.sh` with a key embedded in the script — covers one of 70 packages and
  re-implements what npm already does for all.
- **Version resolution.** `latest` reads `.version` from the registry's `latest` endpoint; an exact version is checked
  against `/{package}/{version}` so a 404 fails with a clear message before npm runs. The format check comes first
  because the endpoint also answers dist-tags. Rejected: ranges — see Options; `npm view` — returns the full packument
  and hides the 404 behind npm's own error text.
- **Options applied in the wrapper, not `containerEnv` or `/etc/profile.d`.** `containerEnv` cannot depend on options,
  and a profile script misses non-login shells and agent tools; the wrapper applies them to every invocation.
- **Platform gate: Debian and Ubuntu, amd64 and arm64.** These are the images tested
  (`test/openspec/compatibility.json`, planned below); the package itself would run on any distribution the Node.js
  feature supports, including RHEL-family images, and adding one later with tests is a MINOR bump. On an image the
  Node.js feature does not support (Alpine), that dependency fails before the gate runs.
- **Tests.** CI (`test.sh`, `duplicate.sh`, `scenarios.json`, all on `compatibility.json` images) covers the scenarios
  whose build succeeds:
  - Option values are read with an environment probe, `NODE_OPTIONS=--require=<probe.cjs> openspec --version`, where the
    probe prints the `OPENSPEC_*` variables and exits before OpenSpec loads (observed with 1.13.2). No test runs any
    other `openspec` command than `--version` and the probe, and the "Fresh container" checks of the home directory run
    before either.
  - `test.sh` compares `openspec --version` with the registry's `latest` read at test time; a release published between
    build and test fails the job, and a rerun fixes it.
  - "Current Node.js switched later" installs a second Node.js with nvm in its scenario script and makes it the default.
  - "Registry configured in the image" is a `build` scenario (Goals, npm configuration).

  The scenarios that fail the build, and "Same options twice", are shown in the PR's Validation section by running the
  staged `src/openspec/install.sh` as root with the option environment variables, on amd64:
  - Unknown (`9.9.9`) and malformed (`^1.7.0`, `1`, `beta`) versions, and "Same options twice": in a container kept from
    `just test openspec --preserve` on `debian:12`; the installed version, wrapper, and prefix are compared before and
    after.
  - Verification failure: in a container started with `--add-host tuf-repo-cdn.sigstore.dev:127.0.0.1` (the audit then
    fails, Context) from an image committed from such a kept container, installing a version other than the one present;
    the earlier `openspec --version` is unchanged afterwards.
  - No Node.js: a plain `debian:12` container.
  - Node.js too old: a Debian 12 image with Node.js 20.18 on `PATH` (the official `node:20.18-bookworm-slim`).
  - Unsupported distribution: a Fedora image, which has bash and which the Node.js feature supports.
  - Unsupported architecture: `debian:12` run with `--platform linux/s390x` under qemu user emulation registered through
    binfmt_misc.

### Security review surface

- **Downloads:** only the npm registry (the package, its dependencies, their attestations) and Sigstore's TUF CDN, all
  over HTTPS; see URL inventory. No `curl | sh`, no OS package, no repository added to the image.
- **Verification:** see Decisions - Verification; the source of every package is checked in `package-lock.json`, and a
  failure is fatal and leaves the previous state.
- **Keys:** none stored in the feature. Registry keys and the Sigstore trust root come through TUF, anchored in the TUF
  root shipped with npm, which the Node.js feature installs.
- **Code execution at build:** no package lifecycle script runs (`--ignore-scripts`); only `openspec --version` runs, as
  a check, with telemetry and the update check off.
- **Metadata:** `dependsOn` `ghcr.io/devcontainers/features/node:2` (the runtime; justified above). No `installsAfter`,
  `containerEnv`, `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, or lifecycle command: the
  feature needs no privilege beyond the root build step and does nothing at start.
- **Idempotency:** one prefix, replaced as a whole on every install; the wrapper overwritten; the temporary directory
  removed by a trap. Outcome: spec, Install twice.
- **Supported images (planned `test/openspec/compatibility.json`):** `mcr.microsoft.com/devcontainers/base:ubuntu24.04`
  (amd64, arm64; `remoteUser` `vscode`) and `debian:12` (amd64, arm64); both publish both architectures, and both are
  within what the Node.js feature supports.
- **Failure behavior:** spec scenarios; how each is shown: Decisions - Tests.

## URL inventory

Every URL the feature's scripts access at build time, plus what the installed CLI contacts at run time depending on the
options. The feature's scripts access no URL at container start. "Verified" is a read-only GET or `curl -sSIL` on
2026-09-30 with the observed status and final host. `--no-audit` and `--no-update-notifier` keep npm from contacting
`POST https://registry.npmjs.org/-/npm/v1/security/advisories/bulk` and `https://registry.npmjs.org/npm`, which are
therefore not listed.

| URL / template                                                                                                                                                                                                                          | Purpose                                                                               | When                                                          | Integrity / authenticity                                                                             | Official source evidence                                                                                                                                                                                                                       | Verified                                                                                                                                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ghcr.io/devcontainers/features/node:2`                                                                                                                                                                                                 | `dependsOn`: Node.js and npm                                                          | build (resolved by the dev container CLI)                     | OCI manifest digest; pinned by the consumer's lockfile if any                                        | https://github.com/devcontainers/features/tree/main/src/node                                                                                                                                                                                   | 2026-09-30: tags list has `2`, `2.1`; `manifests/2` 200; `devcontainer-feature.json` 2.1.0; hosts `ghcr.io` (incl. `ghcr.io/token`), layer blob 307 to `pkg-containers.githubusercontent.com` (GitHub)          |
| `https://registry.npmjs.org/@fission-ai/openspec/latest`                                                                                                                                                                                | Resolve `version=latest`                                                              | build                                                         | TLS alone (spec: Install the requested version); selects a version, which the rows below then verify | https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md (`GET /{package}/{version}`, "a version number or `latest`")                                                                                                                    | 2026-09-30: 200 `application/json`, `.version` 1.13.2, host `registry.npmjs.org`                                                                                                                                |
| `https://registry.npmjs.org/@fission-ai/openspec/<version>`                                                                                                                                                                             | Check that an exact version exists                                                    | build                                                         | TLS alone (spec: Install the requested version); 404 fails the build                                 | same as above                                                                                                                                                                                                                                  | 2026-09-30: `1.13.2` 200, `9.9.9` 404, host `registry.npmjs.org`                                                                                                                                                |
| `https://registry.npmjs.org/<package>` (scoped: `@scope%2fname`)                                                                                                                                                                        | Package metadata npm resolves the tree from, for OpenSpec and each dependency         | build                                                         | HTTPS; carries each version's `dist.integrity` and `dist.signatures`, checked below                  | https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md (`GET /{package}`); upstream install command `npm install -g @fission-ai/openspec@latest` in https://github.com/Fission-AI/OpenSpec                                             | 2026-09-30: `@fission-ai%2fopenspec` 200, host `registry.npmjs.org`; install trial fetched only this host                                                                                                       |
| `https://registry.npmjs.org/<name>/-/<basename>-<version>.tgz`                                                                                                                                                                          | Package tarballs                                                                      | build                                                         | `sha512` `dist.integrity` checked by npm; registry ECDSA signature over name, version, integrity     | REGISTRY-API.md (`dist.tarball`, "usually in the form of `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`")                                                                                                                          | 2026-09-30: `openspec-1.13.2.tgz` 200 `application/octet-stream`, host `registry.npmjs.org`                                                                                                                     |
| `https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>` (scoped: `@scope%2fname`)                                                                                                                                           | Provenance attestations checked by `npm audit signatures`                             | build                                                         | Sigstore bundles verified against the TUF `trusted_root.json`                                        | https://github.com/npm/pacote/blob/main/lib/registry.js (fetches the pathname of `dist.attestations.url` from the configured registry); https://github.com/npm/cli/blob/latest/docs/lib/content/commands/npm-audit.md                          | 2026-09-30: `@fission-ai%2fopenspec@1.13.2` 200, host `registry.npmjs.org`                                                                                                                                      |
| `https://tuf-repo-cdn.sigstore.dev/` + `<n>.root.json`, `timestamp.json`, `<n>.snapshot.json`, `<n>.targets.json`, `<n>.registry.npmjs.org.json`, `targets/registry.npmjs.org/<sha256>.keys.json`, `targets/<sha256>.trusted_root.json` | Registry signing keys and Sigstore trust root for `npm audit signatures`              | build                                                         | TUF metadata chain signed back to the root shipped inside npm                                        | https://github.com/npm/cli/blob/latest/lib/utils/verify-signatures.js (keys via `@sigstore/tuf`); https://github.com/sigstore/sigstore-js/blob/main/packages/tuf/src/index.ts (`DEFAULT_MIRROR_URL`); https://github.com/sigstore/root-signing | 2026-09-30: `timestamp.json` 200, `165.snapshot.json`, `8.registry.npmjs.org.json`, `14.targets.json`, and both hashed targets 200, host `tuf-repo-cdn.sigstore.dev`; keys target lists keyid `SHA256:DhQ8…C7U` |
| `https://registry.npmjs.org/-/npm/v1/keys`                                                                                                                                                                                              | Fallback key source, used by npm only when TUF has no target for the registry         | build (fallback only)                                         | TLS alone (spec: Verify every installed package)                                                     | https://github.com/npm/cli/blob/latest/docs/lib/content/commands/npm-audit.md ("Public signing keys are provided at `registry-host.tld/-/npm/v1/keys`")                                                                                        | 2026-09-30: 200, host `registry.npmjs.org`; keyid `SHA256:DhQ8…C7U`, `expires` null                                                                                                                             |
| `https://edge.openspec.dev/batch/`                                                                                                                                                                                                      | OpenSpec CLI telemetry (PostHog), not contacted by the feature's scripts              | run time, only while telemetry is on                          | HTTPS                                                                                                | https://github.com/Fission-AI/OpenSpec/blob/main/src/telemetry/index.ts (`POSTHOG_HOST`, `${POSTHOG_HOST}/batch/`)                                                                                                                             | 2026-09-30: `/batch/` HEAD 400 (`server: envoy`); DNS resolves to a PostHog-managed proxy (`proxy-us.posthog.com`), so PostHog operates it on upstream's domain                                                 |
| `https://registry.npmjs.org/@fission-ai/openspec/latest`                                                                                                                                                                                | OpenSpec CLI update check (same URL as row 2), not contacted by the feature's scripts | run time, only inside `openspec update` while the check is on | HTTPS; follows cross-host HTTPS redirects                                                            | https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md (the `openspec update` version check; `npm_config_registry`); https://github.com/Fission-AI/OpenSpec/blob/main/src/core/version-check.ts (`DEFAULT_REGISTRY`)                     | see row 2                                                                                                                                                                                                       |

The Node.js feature's own downloads (nvm, Node.js, pnpm, and apt packages) belong to that feature and are not listed.

## Risks / Trade-offs

- [Dependency versions float within upstream's ranges; a compromised dependency release would be installed] → Every
  package must carry a valid registry signature; no install script runs; a new OpenSpec release is only picked up by
  `latest` at build time. Upstream ships no shrinkwrap, so pinning deeper would mean maintaining a lock per OpenSpec
  version here.
- [`npm audit signatures` verifies the registry's current manifest for each name and version, not the bytes npm
  downloaded] → npm already checked each tarball against the same manifest's `integrity` seconds earlier, and a
  published version's integrity cannot change on the registry.
- [TUF or Sigstore's CDN unreachable, or a package without a signature] → The build fails closed. A consumer behind a
  firewall needs `registry.npmjs.org` and `tuf-repo-cdn.sigstore.dev` from the build, and `ghcr.io` and
  `pkg-containers.githubusercontent.com` where the dev container CLI runs (NOTES.md says so).
- [No private registry, mirror, or build-time proxy support] → Pinned on purpose so the source is the one the spec
  names; a consumer who needs one cannot use this version of the feature.
- [The install-time Node.js is removed later (`nvm uninstall`)] → The wrapper fails with a message naming the missing
  binary; reinstalling the feature or rebuilding fixes it.
- [A consumer's own `node:2` entry with other options installs Node.js twice; the default alias ends up at whichever ran
  last] → OpenSpec pins the Node.js current when it installs, and `--engine-strict` rejects one below 20.19.0; NOTES.md
  names the interaction.
- [An `openspec` installed later with `npm install -g` lands earlier on `PATH` and shadows the wrapper] → The update
  check that prints that command is off by default; NOTES.md says so.
- [First feature of the repository] → Validation, test staging, the CI matrix, and the Release workflow run on a real
  feature for the first time; failures there are fixed in the PR that surfaces them, as harness changes with their own
  review.

## Open Questions

Decided above, but listed for explicit confirmation when the package is approved:

- **No registry keyid pin.** Decisions - Verification relies on the package-manager and registry clause of
  `feature-authoring.md` (Downloads) and adds `npm audit signatures` without pinning
  `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`; pinning it would make a key rotation fail the build.
