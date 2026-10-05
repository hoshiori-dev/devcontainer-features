# Design

## Context

See proposal.md - Why. The behavior is in `specs/openspec/spec.md`; this file records how it is reached and what was
checked on 2026-09-30 and 2026-10-01 to choose it.

- **Package.** `@fission-ai/openspec` 1.13.2 was `dist-tags.latest` on 2026-09-30 (published 2026-09-23T21:47Z; 1.13.1
  was published 2026-09-17); the other tags are `next=0.3.0` (stale) and `beta=1.6.0-beta.1`. It is pure JavaScript with
  no `os` or `cpu` field, `bin` `openspec` → `bin/openspec.js` (`#!/usr/bin/env node`), `engines.node` `>=20.19.0`
  (1.12.0 through 1.13.2), 10 runtime dependencies resolving to 70 packages, none with an install script. The tarball
  ships no `npm-shrinkwrap.json`, so dependency versions resolve within the declared ranges at install time. 1.14.0
  became `latest` on 2026-09-30T22:54Z with the same `engines.node`, dependency ranges, signing keyid, and provenance;
  the observations below were made with 1.13.2.
- **Registry document.** `GET https://registry.npmjs.org/@fission-ai%2fopenspec` answers 200 `application/json` without
  a redirect (157 kB, 51 versions on 2026-10-01): `dist-tags`, every published version under `versions` with its
  `engines` and `dist`, and each version's publish time under `time` (`time["1.13.2"]` is `2026-09-23T21:47:05.420Z`). A
  dist-tag is not a key of `versions`, so an unpublished version (`9.9.9`) and a tag (`beta`) both read as not published
  there. `GET /{package}/{version}` is smaller but also answers for any dist-tag and carries no publish time.
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
  reported 70 verified registry signatures and 22 verified attestations. The same counts and the same failure with the
  mirror unreachable were observed with npm 10.8.2, the npm bundled with Node.js 20.19.0. The verifier skips a package
  whose spec is not a registry spec (a git or URL dependency), and it asks for the manifest of each installed name and
  version without comparing it with the `integrity` in `package-lock.json`
  (https://github.com/npm/cli/blob/latest/lib/utils/verify-signatures.js, `getValidPackageInfo`, `verifySignatures`).
  With npm 10.9.9 (Node.js 22.23.3), an audit that starts without a TUF cache, as every build does, reported one or two
  valid attestations as invalid in 7 of 90 runs, with and without `--prefer-offline`; a second audit on the same cache
  passed in all 4 cases tried, and 30 runs that started with a filled TUF cache all passed. npm 10.8.2 and 11.19.0
  passed 50 of 50 runs each.
- **Dependency bound.** `npm install --before=<time>` resolves every package, the named one included, to the newest
  version in range whose `time` is not later than the bound (`isBefore` in npm-pick-manifest compares with `<=`) and
  makes npm request full package documents. With the bound at the publish time of 1.13.2, the install gave the same 70
  packages, none published after the bound and two older than an unbounded install chose on 2026-10-01 (`ansi-regex`
  6.3.0 for 6.4.0, `string-width` 8.2.2 for 8.3.0); `npm audit signatures` then verified 70 signatures and 22
  attestations. The bound reads each package document's `time` map, which no registry signature covers, and a version
  without a `time` entry counts as inside the bound. `min-release-age` is a configuration key in npm 11.19.0 and not in
  10.8.2.
- **Altered registry answers.** `registry.npmjs.org` was mapped to a local TLS proxy that forwards to the registry, and
  a `node` wrapper first on `PATH` added `--use-openssl-ca` with the proxy's test certificate authority next to
  Node.js's own; npm ran with the flags under Goals. An altered tarball of one dependency failed the install with
  `EINTEGRITY`. An altered tarball with a matching `dist.integrity` in its package document installed, and
  `npm audit signatures` then failed with "1 package has an invalid registry signature". With the alteration made only
  during the install and unaltered answers afterwards, the audit failed the same way on the install's cache, with and
  without `--prefer-offline` (it read the package document from that cache and sent no second request for it), and
  passed on a fresh cache. These three gave the same results with npm 10.8.2, 10.9.9, and 11.19.0. A `dist.tarball`
  rewritten to another host serving the same bytes installed and left that URL as the entry's `resolved` in
  `package-lock.json` (npm 10.9.9).
- **npm configuration.** A `--registry` flag does not override a scoped `@scope:registry=` line from a user or global
  npmrc: with `@fission-ai:registry=https://example.invalid/` in `/root/.npmrc`, `npm install --registry=…` failed with
  `ENOTFOUND`. `--userconfig` and `--globalconfig` both set to `/dev/null` make npm exit
  (`double-loading config
  "/dev/null" as "global", previously loaded as "user"`); two distinct empty files work and
  ignored the same `/root/.npmrc`, and all 70 `package-lock.json` entries then resolved under
  `https://registry.npmjs.org/`. Without `--no-update-notifier`, `npm install` also fetches the `npm` packument; with it
  and `--no-audit`, the debug log of the install holds 141 requests, all GETs of package documents and tarballs on
  `registry.npmjs.org` (npm 10.9.9 and 11.19.0; the bulk advisory POST that `--no-audit` rules out did not appear with
  or without the flag). npm also reads an `npmrc` built into its own installation directory, which neither flag
  replaces; the Node.js 22.23.3 release ships none. A value there loses to a command-line flag (`strict-ssl=false`
  against `--strict-ssl=true`), while `cafile`, `https-proxy`, and a scoped registry stay in effect, and
  `npm config list --json` with the same flags shows them. An upper-case `NPM_CONFIG_STRICT_SSL=false` reaches npm too.
  With `NODE_EXTRA_CA_CERTS` naming a test certificate authority in the environment, Node.js `fetch` and
  `npm install --strict-ssl=true` both accepted a local proxy's certificate for `registry.npmjs.org`; under `env -i`
  with only `PATH` and `HOME` both failed with `UNABLE_TO_VERIFY_LEAF_SIGNATURE`, and both work against the registry.
- **Node.js feature.** `ghcr.io/devcontainers/features/node` is at 2.1.0 (GHCR tags `2`, `2.0`, `2.0.0`, `2.1`,
  `2.1.0`); major 2 is current. It installs Node.js with nvm under `/usr/local/share/nvm`, links `current` to the
  default version, and sets `PATH=/usr/local/share/nvm/current/bin:${PATH}` in `containerEnv`. Its option defaults are
  `version` `lts` (it also accepts `none`), `nodeGypDependencies` true (apt build tools), `pnpmVersion` `latest`,
  `nvmVersion` `latest`, `npmVersion` `none`, `installYarnUsingApt` false. It detects apt, dnf, microdnf, and yum only
  (no Alpine). The devcontainer CLI (0.89.0) emits each feature's `containerEnv` as `ENV` before that feature's layer,
  so the Node.js on `PATH` is visible to features installed after it. Per the Dev Container feature-dependencies spec,
  two entries of one feature are equal only with equal options, so a consumer's own `node:2` entry with other options
  installs Node.js a second time. Its `install.sh` pipes nvm's installer from `raw.githubusercontent.com` into bash
  (`curl … | bash`, nvm `latest` by default) and makes `/usr/local/share/nvm` and everything under `versions`
  group-writable for the `nvm` group, which the remote user joins.
- **Unprivileged check.** `setpriv` belongs to util-linux, an essential package, and is present in `debian:12` and
  `mcr.microsoft.com/devcontainers/base:ubuntu24.04`. In a Debian 12 container,
  `setpriv --reuid=65534 --regid=65534 --clear-groups --no-new-privs` ran `openspec --version` of a tree under a
  world-readable directory and wrote nothing (1.13.2); the same `setpriv` call ran in a `RUN` step of a `docker build`
  on `debian:12`.
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
  `/usr/local/bin/openspec`. The two locations and their ownership are the spec's (Install the requested version,
  Scenario "Installed locations"); the npm project tree and the wrapper are how this design reaches them. Checked by
  `test.sh`, under labels in the words of that scenario (the path `command -v openspec` resolves to, ownership, and a
  non-root remote user running it), and by `duplicate.sh`.
- All network access at build time goes through the dependency's Node.js and npm, to the hosts in the URL inventory
  only; the feature adds no OS package and no other download tool. Checked by review of `install.sh` against the URL
  inventory.
- Node.js and npm run under `env -i` with `PATH`, a `HOME` in a temporary directory, and nothing else of the build's
  environment, so no `NODE_*`, `npm_config_*` (any letter case), proxy, or certificate variable reaches them. npm runs
  with `--registry=https://registry.npmjs.org/`, `--strict-ssl=true`, `--userconfig` and `--globalconfig` set to two
  distinct empty files in that temporary directory, `--ignore-scripts`, `--engine-strict`, `--no-audit`,
  `--no-update-notifier`, and a cache in that temporary directory, which is removed on exit, success or failure. Every
  npm call names its project directory with `--prefix`, an empty directory in that temporary directory until the staging
  tree exists and the staging tree afterwards, so npm reads no project `npmrc` from the build's working directory. A
  failed registry read or npm install says that the build's proxy and certificate variables and the user, global, and
  project npm configuration are not used (Non-Goals). Checked by review of `install.sh`, by a `build` scenario whose
  Dockerfile writes `@fission-ai:registry=` with an unreachable host into root's `~/.npmrc` and still installs, by the
  certificate-settings run under Decisions - Tests, whose message is recorded, and by `test.sh` asserting the remote
  user's home holds no npm cache or log from the build.
- The registry document is read once, with Node.js `fetch` and `redirect: 'error'`. `latest` is its `dist-tags.latest`;
  the selected version must match the exact-version pattern the `version` option is checked against, be a key of
  `versions`, and have a `time` entry that parses as a date, or the install fails before npm installs anything. Checked
  by review and by the unknown-version, malformed-version, and altered-`latest` runs.
- npm installs `@fission-ai/openspec@<version>` with `--before=<that version's publish time>`, so no installed package
  is newer than the OpenSpec version. Checked by the exact-version scenario, whose script compares the registry publish
  time of every entry of the installed `package-lock.json` with that of the installed OpenSpec version.
- After the install, `package-lock.json` must hold `node_modules/@fission-ai/openspec` at exactly the selected version
  and without an alias `name`, and every entry other than the root must have a `resolved` URL starting with
  `https://registry.npmjs.org/`, or the install fails naming the entry. `npm audit signatures` skips a package that does
  not come from a registry, so this check is what keeps a git or URL dependency out. The `resolved` check is shown by
  the rewritten-tarball-URL run under Decisions - Tests; the version and alias check by review.
- A new tree is installed and verified in a staging directory next to the prefix and replaces the prefix only after the
  lockfile checks, `npm audit signatures`, and the `openspec --version` check pass. `npm audit signatures` runs on the
  cache the install filled, with `--prefer-offline`, so that npm verifies the package documents the install took each
  `integrity` from (Context, Altered registry answers). A failed install leaves the previous prefix and wrapper as they
  were. `install.sh` has no switch or environment hook that weakens or skips verification. Checked by review of
  `install.sh` and by the verification-failure runs under Decisions - Tests.
- The wrapper `exec`s the Node.js binary resolved (symlinks followed) from `PATH` at install time with the package's
  `bin/openspec.js`, passes the caller's environment through unchanged, and exports `OPENSPEC_NO_UPDATE_CHECK` /
  `OPENSPEC_TELEMETRY` only when the option is true and the variable is unset (`${VAR+set}` test, so an empty value
  counts as set). No option value is written into the wrapper: each boolean option only decides whether one fixed line
  is present, the selected version does not appear in it, and the only text that varies is the resolved Node.js path,
  written as one single-quoted word. `install.sh` itself runs the literal command `node` under its clean environment for
  the version probe, the registry read, and the lockfile checks; the resolved path is data, written into the wrapper and
  the log, and is passed to `setpriv` only for the `openspec --version` check, which must run the binary the wrapper
  pins, under a comment that marks that call. Checked by review of the wrapper's here-document and of the Node.js calls
  in `install.sh`, by the option scenarios with the environment probe under Decisions - Tests, and by a scenario that
  switches nvm's default after the build.
- Every install replaces the prefix and rewrites the wrapper; there is no skip for an already installed version. This
  departs on purpose from "skip an install when the requested version is already present" in
  `.agents/knowledge/feature-authoring.md` (Idempotency): a skip would keep a tree this run did not verify and would
  still have to rewrite the wrapper for changed options, and one path is easier to audit than two. Checked by
  `duplicate.sh`: with the `version` proposals under Options, the first install is always 1.13.1 and the second the
  newer `latest`, which exercises the replacement on every run; the script stops with a message when its inputs are not
  these (Decisions - Tests).
- `install.sh` and every shell script under `test/openspec/` follow `.agents/knowledge/shell-style.md`; bash
  (`#!/usr/bin/env bash` with `set -euo pipefail`) is the dialect because every listed image ships it. `main` of
  `install.sh` checks, in this order, the distribution and architecture, every option value (`version`: `latest` or one
  exact version; `disableUpdateCheck` and `disableTelemetry`: `true` or `false`), and the presence of Node.js, of npm
  10.8.2 or newer, and of `setpriv`, all before any network access and before it creates anything outside its temporary
  directory, the staging directory included, and then, still before any network access, that no directory is at the
  wrapper's path, where the wrapper could not be put; the final move of the wrapper uses `--no-target-directory`, which
  the `mv` of both listed images has, so it never descends into a directory (an npm that new runs only on a Node.js that
  has `fetch`; the spec fixes no order between the platform and the option checks, so the script's stays; `setpriv` is
  part of the essential util-linux on every distribution the gate admits, so the spec has no scenario for it). Each
  option takes its default in the form `${NAME-default}`, so an explicitly empty value reaches its check and fails. The
  message for a missing Node.js names 20.19.0, a constant in `install.sh`; the found Node.js is compared with the
  selected version's `engines.node` before npm installs anything. Checked by `just check`, by
  `shellcheck -o require-variable-braces,require-double-brackets` reporting nothing for `src/openspec/install.sh` and
  every `test/openspec/*.sh`, by review of the scripts against the guide, and by the local runs under Decisions - Tests.
- `install.sh` names its trust surface as readonly constants at the top: the registry URL `https://registry.npmjs.org/`
  and the package name every request of its own is built from, the TUF mirror `https://tuf-repo-cdn.sigstore.dev` that
  the audit's log line and failure hint name (Decisions on the open questions), and every path it creates or modifies
  outside its temporary directory: the prefix `/usr/local/lib/openspec`, the wrapper `/usr/local/bin/openspec`, the
  staging directory `/usr/local/lib/openspec.staging.XXXXXX`, the set-aside copy of a previous prefix
  `/usr/local/lib/openspec.previous.XXXXXX`, and the unfinished wrapper `/usr/local/bin/openspec.new`; the last three
  are removed on every exit. No constant takes the name of an `/etc/os-release` key. Checked by review: outside the
  header comment and the constants, `install.sh` holds no `https://` and no `/usr/local` literal.
- Log and failure lines follow `.agents/knowledge/shell-style.md` (Logging and failure) with the prefixes `openspec:`
  and `openspec: error:`, the failures the inline Node.js programs print included; npm's own output is not prefixed.
  Each failure a developer can fix keeps the content its spec scenario names. One log line precedes each step that uses
  the network or changes the image: the read of the registry document (its URL), `npm install` (package, version,
  publish-time bound, registry, staging directory), `npm audit signatures` (the registry and the TUF mirror), the
  replacement of the prefix, and the writing of the wrapper. Checked by the local runs under Decisions - Tests and by
  reading the build log of `just test openspec`.
- The build-time `openspec --version` check runs the staged tree as uid and gid 65534 without supplementary groups
  (`setpriv --reuid=65534 --regid=65534 --clear-groups --no-new-privs`), under `env -i` with `PATH`,
  `OPENSPEC_TELEMETRY=0`, `OPENSPEC_NO_UPDATE_CHECK=1`, and `HOME` and `XDG_CONFIG_HOME` pointing into the temporary
  directory, which that user cannot write; `install.sh` sets `umask 022`, so that user can read the staged tree. No
  package code runs as root during the build, and the check cannot write to root's home, which is the remote home on
  `debian:12`. Checked by review and by the "Fresh container" test on `debian:12`.

**Non-Goals:**

- Installing Node.js itself, or choosing its version: the Node.js feature does both.
- Supporting a private registry or mirror at build time.
- Supporting an HTTP(S) proxy or an added certificate authority at build time: the feature's Node.js and npm calls do
  not see the environment's proxy or certificate variables.
- Following new OpenSpec releases after the build; `openspec update` or a self-upgrade inside the container.
- Pinning dependency versions beyond the publish-time bound (upstream ships no shrinkwrap).
- Running any `openspec` command at build or start time other than `--version` for verification.

## Options

All three options are new; the delta spec's Option requirements are normative.

| Name                 | Type      | Default    | Enum or proposals               | Meaning                                                                                                                           |
| -------------------- | --------- | ---------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `version`            | `string`  | `"latest"` | proposals `["latest","1.13.1"]` | OpenSpec version to install: `latest` or one exact published version; any other value, an empty one included, fails               |
| `disableUpdateCheck` | `boolean` | `true`     | none                            | Run `openspec` with `OPENSPEC_NO_UPDATE_CHECK=1` unless the caller sets it; `true` or `false`, any other value, even empty, fails |
| `disableTelemetry`   | `boolean` | `false`    | none                            | Run `openspec` with `OPENSPEC_TELEMETRY=0` unless the caller sets it; `true` or `false`, any other value, even empty, fails       |

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
- Accepting `yes`, `1`, or another case of `true` for a boolean option, or reading an empty value of any option as its
  default — guessing what the developer meant, which `.agents/knowledge/shell-style.md` (Logging and failure) forbids;
  the spec defines no alternative form for any option, so `install.sh` rewrites none.

## Decisions

- **Runtime: Node.js through `dependsOn` on `ghcr.io/devcontainers/features/node:2`, with options `{}`.** The maintainer
  chose Node.js; it is upstream's primary install path, `npm audit signatures` verifies registry signatures and
  provenance, and the Node.js feature is first-party and maintained. `{}` accepts that feature's defaults, including
  `nodeGypDependencies` (apt build tools) and pnpm `latest`; other options would make a consumer's own `node:2` `{}`
  entry a second Node.js install. Rejected: Deno through this repository's `deno` feature with upstream's permission set
  — sandboxed, but outside the maintainer's choice; a Node.js binary downloaded by this feature — would duplicate the
  Node.js feature and its verification; `installsAfter` instead of `dependsOn` — a consumer would have to add Node.js by
  hand.
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
  attestation, with keys delivered through TUF from the root shipped inside npm. The audit verifies a manifest, not the
  installed files; run on the install's cache with `--prefer-offline`, it verifies the package documents whose
  `integrity` the install enforced, which ties the two for as long as npm reuses the cached documents (Context, Altered
  registry answers; Risks), and the feature adds no comparison of its own. A registry signature shows that the registry
  published those bytes under that name and version, not that the publisher's account was its owner's (Risks). A missing
  or invalid signature, or an invalid attestation, fails; a missing attestation does not (spec: Verify every installed
  package). The registry is npm's default, not a repository the feature adds, so the rule's fingerprint pin does not
  apply. What rests on TLS alone — the registry document read, the publish times behind the bound, the integrity hashes,
  and npm's fallback keys endpoint — is stated in Requirements, as the rule's direct-download clause asks (spec: Install
  the requested version; Bound dependencies to the release time; Verify every installed package). Trade-off of not
  pinning the keyid `SHA256:DhQ8wR5APBvFHLF/+Tc+AYvPOdTpcIDqOhxsBHRwC7U`: a registry key rotation passes through TUF
  instead of failing every build until a feature release; the maintainer confirmed this choice in the package
  deliberation. Rejected: integrity only — what the rule requires at minimum, but it trusts nothing beyond TLS to the
  registry; the keyid pin in `install.sh` — adds no trust root beyond TUF, breaks builds on a legitimate rotation, and
  needs every package's manifest signatures read again by `install.sh`; verifying the top-level signature in
  `install.sh` with a key embedded in the script — covers one of 70 packages and re-implements what npm already does for
  all; verifying every registry signature in `install.sh` against the `integrity` in `package-lock.json` — ties
  signature and installed files without relying on npm's cache, but re-implements npm's verifier and needs the keys
  fetched through TUF by `install.sh`.
- **Dependencies bounded by the release's publish time.** Without a bound, each build takes whatever upstream's ranges
  allow that day, including a release pushed from a hijacked maintainer account an hour earlier (`chalk`, which 1.13.2
  declares as `^5.6.2`, had one on 2025-09-08). `--before` with the OpenSpec version's own publish time installs what
  existed when upstream released, leaves only releases made before upstream's own, and keeps a later build of the same
  `version` from picking up newer releases. Cost: a dependency fix published after the OpenSpec release arrives only
  with the next OpenSpec release. Rejected: unbounded ranges — a compromised release is installed the day it appears; a
  lockfile per OpenSpec version kept in this repository — the feature would need a release before each OpenSpec release
  could be installed; a delay behind the newest release (`min-release-age`) — relative to the build date, so two builds
  of one `version` differ, and unknown to npm 10.
- **A clean environment instead of a deny-list.** `env -i` with `PATH` and `HOME` keeps out every variable that changes
  how Node.js or npm check certificates, pick a registry, or load code, and makes the lookup and npm treat proxies the
  same way. This is not a boundary against the image: `PATH` passes, so a `node` or `npm` the image puts first is run as
  it is (Risks). It stays because one `env -i` call gives every build the same registry and the same certificate checks.
  Rejected: unsetting the known variables (`NODE_TLS_REJECT_UNAUTHORIZED`, `NODE_EXTRA_CA_CERTS`, `NODE_OPTIONS`,
  `npm_config_*`) — misses any variable a later Node.js or npm adds.
- **Build-time check as an unprivileged user.** `openspec --version` is the only package code the build runs, and
  `--ignore-scripts` does not stop code that runs when a module loads. Running it as uid 65534 keeps a compromised
  dependency from acting as root in the image build; the same code still runs as the remote user on first use, which no
  build-time measure changes. `setpriv` comes with util-linux on every image the platform gate admits and needs nothing
  beyond what a root build step has (Context, Unprivileged check). Rejected: running the check as root — it needs no
  privilege; reading the version from `package.json` without running the CLI — a build could then succeed with a CLI
  that does not start.
- **Version resolution: one read of the registry document.** `dist-tags.latest`, whether an exact version exists, its
  `engines.node`, and its publish time come from one request that rests on TLS alone, checked as under Goals. An
  unpublished version and a dist-tag both fail as not published, with a clear message, before npm installs anything; the
  format check still comes first, so a malformed value fails without any request. Rejected: `GET /{package}/{version}` —
  a smaller answer, but it answers dist-tags too and has no publish time, so the bound would need a second request;
  ranges — see Options; `npm view` — hides a missing version behind npm's own error text.
- **Options applied in the wrapper, not `containerEnv` or `/etc/profile.d`.** `containerEnv` cannot depend on options,
  and a profile script misses non-login shells and agent tools; the wrapper applies them to every invocation.
- **Platform gate: Debian and Ubuntu, amd64 and arm64.** These are the images tested
  (`test/openspec/compatibility.json`, planned below); the package itself would run on any distribution the Node.js
  feature supports, including RHEL-family images, and adding one later with tests is a MINOR bump. On an image the
  Node.js feature does not support (Alpine), that dependency fails before the gate runs.
- **Tests.** CI (`test.sh`, `duplicate.sh`, `scenarios.json`, all on `compatibility.json` images) covers the scenarios
  whose build succeeds:
  - `test.sh` and `duplicate.sh` run on every listed image and architecture; the scenarios run on amd64 and arm64, which
    `compatibility.json` selects with `"scenarioArchitectures": ["amd64", "arm64"]` (`.agents/knowledge/testing.md`,
    Compatibility list), so every scenario the Acceptance points to is shown on both.
  - Each scenario script carries its own checks and sources only `dev-container-features-test-lib` and the feature's
    shared assertion file, `lib.sh`; the two images of one scenario repeat their check lines.
  - `lib.sh` holds only assertions that several scripts use, named after what they assert (the environment an `openspec`
    process sees, the Node.js it runs on, the version `openspec` reports, the version of the installed package, every
    package from the public registry, one installation), and the probe call those assertions share; each script that
    needs the registry's `latest` reads it itself, under a comment saying why it is computed at run time.
  - A test states its own premise as a precondition that stops the script with a message, not as a check: the option
    values of the two installs in `duplicate.sh` (`1.13.1`, false, true, then `latest`, true, false), another registry
    for the `@fission-ai` scope in root's npm configuration in the registry scenario, a later release in range for a
    dependency of 1.13.2 in the exact-version scenario, and, after the switch, a current Node.js other than the one
    `openspec` was installed with. A setup action, installing and switching Node.js with nvm, runs as a plain command.
  - Option values are read with an environment probe, `NODE_OPTIONS=--require=<probe.cjs> openspec --version`, where the
    probe prints the `OPENSPEC_*` variables and exits before OpenSpec loads (observed with 1.13.2). No test runs any
    other `openspec` command than `--version` and the probe, and the "Fresh container" checks of the home directory run
    before either.
  - `test.sh` compares `openspec --version` with the registry's `latest` read at test time; a release published between
    build and test fails the job, and a rerun fixes it.
  - "Current Node.js switched later" installs a second Node.js with nvm in its scenario script and makes it the default.
  - "Registry configured in the image" is a `build` scenario (Goals, the clean environment).
  - "Dependency released later" is checked in the exact-version scenario (Goals, `--before`).

  The scenarios that fail the build, and "Same options twice", are shown in the PR's Validation section by running the
  staged `src/openspec/install.sh` as root with the option environment variables, on amd64:
  - Unknown (`9.9.9`) and malformed (an empty value, `^1.7.0`, `1`, `beta`) versions, an invalid `disableUpdateCheck`
    and an invalid `disableTelemetry` (`yes`, `TRUE`, `1`, an empty value), and "Same options twice": in a container
    kept from `just test openspec --preserve` on `debian:12`; the installed version, wrapper, and prefix are compared
    before and after.
  - Verification failure, signing keys unreachable: in a container started with
    `--add-host tuf-repo-cdn.sigstore.dev:127.0.0.1` (the audit then fails, Context) from an image committed from such a
    kept container, installing a version other than the one present; the earlier `openspec --version` is unchanged
    afterwards.
  - Verification failure, altered registry answers: in such a container with `registry.npmjs.org` mapped to a local TLS
    proxy that forwards to the registry, and a `node` wrapper first on `PATH` that makes Node.js also trust the proxy's
    test certificate authority (Context, Altered registry answers). The proxy and the wrapper are test tools outside
    `src/openspec/`, and `install.sh` runs unchanged. One run each, in which the proxy alters, for one dependency: its
    tarball (npm's `EINTEGRITY`); its tarball and `dist.integrity` in every answer (invalid registry signature); both in
    its first answer only ("Package altered during the install only"); its `dist.tarball`, pointing to another host that
    serves the same bytes (the lockfile check, naming the entry). One more run alters `dist-tags.latest` of the OpenSpec
    document to a value that is not an exact version (the build fails before npm installs anything). Each run fails and
    leaves the earlier `openspec --version`, wrapper, and prefix unchanged.
  - Certificate settings: the same proxy without the `node` wrapper, with `NODE_EXTRA_CA_CERTS` naming the test
    certificate authority, `NODE_OPTIONS=--use-openssl-ca` with `SSL_CERT_FILE` naming it,
    `NODE_TLS_REJECT_UNAUTHORIZED=0`, and `npm_config_strict_ssl=false` in the environment (the build fails on the
    proxy's certificate at the registry document read, with a message saying that the build's proxy and certificate
    variables and the user, global, and project npm configuration are not used; that npm's requests ignore the same
    settings rests on Context, npm configuration, and on review of the `env -i` calls).
  - No Node.js: a plain `debian:12` container; nothing of the feature is under `/usr/local/lib` or `/usr/local/bin`
    afterwards.
  - Node.js too old: a Debian 12 image with Node.js 20.18 on `PATH` (the official `node:20.18-bookworm-slim`).
  - npm missing or too old: the official `node:20.19.0-bookworm-slim` with its npm replaced by 10.8.1, and again with
    npm taken off `PATH`.
  - Unsupported distribution: `fedora:44` (Docker Official Image), which has bash and which the Node.js feature
    supports.
  - Unsupported architecture: `debian:12` run with `--platform linux/386`, with `install.sh` started under `linux32` so
    that `uname` names the image's `i686`; an amd64 host runs that image without emulation.

### Security review surface

- **Downloads:** only the npm registry (the package, its dependencies, their attestations) and Sigstore's TUF CDN, all
  over HTTPS, with the build's environment other than `PATH` and the user, global, and project npm configuration kept
  out (Goals) and the npmrc built into the Node.js installation left in effect (Risks); see URL inventory. The feature's
  own scripts run no `curl | sh`, add no OS package, and add no repository to the image.
- **Verification:** see Decisions - Verification and Decisions - Dependencies bounded; the source of every package is
  checked in `package-lock.json`, and a failure is fatal and leaves the previous state.
- **Keys:** none stored in the feature. Registry keys and the Sigstore trust root come through TUF, anchored in the TUF
  root shipped with npm. Node.js, npm, and that root arrive through the Node.js feature, which downloads them over TLS
  after piping nvm's installer into bash; this feature's verification is no stronger than that bootstrap (Risks).
- **Code execution at build:** no package lifecycle script runs (`--ignore-scripts`); only `openspec --version` runs, as
  a check, as uid 65534, with telemetry and the update check off. No package code runs as root.
- **Metadata:** `dependsOn` `ghcr.io/devcontainers/features/node:2` (the runtime; justified above). No `installsAfter`,
  `containerEnv`, `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, or lifecycle command: the
  feature needs no privilege beyond the root build step and does nothing at start.
- **Configuration:** the three options are the whole customization surface, and none takes a path, a URL, a command, or
  a user. `version` is matched as a whole against `latest` or the exact-version pattern before anything uses it and
  reaches Node.js and npm only as a quoted argument; the two booleans are matched against `true` and `false` and select
  fixed lines of the wrapper. No option value is evaluated or written into a script the feature generates (the wrapper),
  and no option changes a privilege or a download source, so an ordinary-looking value cannot trigger execution, a
  privilege change, or data exposure beyond what its description states (`.agents/knowledge/feature-authoring.md`,
  Developer trust and readability). What `"openspec": {}` does beyond installing the CLI: it installs Node.js through
  `dependsOn` with that feature's defaults, an installation the remote user can write through the `nvm` group
  (Decisions - Runtime; Risks); it leaves OpenSpec's telemetry on (Options; Risks); and it turns the update check off.
  The dependency and both defaults are in the metadata, and NOTES.md states the telemetry default first.
- **Idempotency:** one prefix, replaced as a whole on every install; the wrapper overwritten; the temporary directory,
  the staging directory, the set-aside previous prefix, and the unfinished wrapper removed by a trap. Outcome: spec,
  Install twice.
- **Supported images (planned `test/openspec/compatibility.json`):** `mcr.microsoft.com/devcontainers/base:ubuntu24.04`
  (amd64, arm64; `remoteUser` `vscode`) and `debian:12` (amd64, arm64); both publish both architectures, and both are
  within what the Node.js feature supports; `scenarioArchitectures` selects both architectures for the scenarios.
- **Failure behavior:** spec scenarios; how each is shown: Decisions - Tests.

### Decisions of 2026-10-05

The maintainer decided these points in conversation on 2026-10-05, when the package was revised for the requirements
added to the knowledge base after its approval (`.agents/knowledge/shell-style.md`,
`.agents/knowledge/review-guidance.md`, and the sections of `feature-authoring.md` and `testing.md` added since). They
settle the points named here and do not close the package gate for the revised package.

- **The image's download settings stay ignored.** Requirement "Ignore the image's download settings" stays, with the one
  edit the next point names; the clean environment is not a boundary against the image and is kept for what it gives
  every build (A clean environment instead of a deny-list). Rejected: narrowing or dropping the requirement.
- **No check of the npmrc built into npm.** The requirement ends at the feature's Node.js and npm calls, Scenario
  "Certificate settings built into npm" is removed, and "regardless of any registry configured in the image" stays as
  approved; what that leaves is under Risks. Rejected: keeping a check that only a prepared image reaches.
- **An invalid boolean value fails the build.** Both boolean Option requirements say that any value other than `true` or
  `false`, an empty one included, fails, each with a scenario (Options; Goals). Rejected: stating it only in this
  design.
- **An explicitly empty `version` fails.** Scenario "Malformed version" lists the empty value. Rejected: stating it only
  as a bound of this design.
- **NOTES.md carries no threat analysis.** What rests on TLS alone, the Node.js feature as the start of the chain of
  trust, and its group-writable installation stay in the spec and under Risks and leave NOTES.md, whose "What is
  verified" says what a developer acts on. Rejected: keeping the three statements in NOTES.md.
- **The scenarios run on both architectures.** `test/openspec/compatibility.json` declares `scenarioArchitectures` amd64
  and arm64, so the Acceptance holds as approved (Tests). Rejected: narrowing the Acceptance to amd64.
- **The installed locations are in the spec.** Requirement "Install the requested version" names
  `/usr/local/lib/openspec` and `/usr/local/bin/openspec`, owned by root and writable only by root, with Scenario
  "Installed locations", so the tests' labels have the spec's words (Goals). Rejected: keeping the checks as marked
  deviations labelled in this design's words.
- **A test's premise is a precondition.** A check of a test's own premise becomes a precondition that stops the script
  with a message, and a setup action runs as a plain command (Tests). Rejected: comments only.
- **Each scenario script carries its own checks.** It sources only the test library and the feature's shared assertion
  file (Tests). Rejected: keeping the shared scenario bodies as a marked deviation.
- **The shared test file holds only assertions.** Each script that needs the registry's `latest` reads it itself
  (Tests). Rejected: keeping value helpers there as a marked deviation.
- **`install.sh` runs the literal command `node`.** The resolved path is data, passed to `setpriv` only for the version
  check that must run the binary the wrapper pins (Goals). Rejected: keeping the variable in every call.
- **No skip for an already installed version.** Every install replaces the prefix, for the reason Goals gives. Rejected:
  skipping when the lockfile already holds the selected version.
- **The security review surface assesses the configuration.** It gains the bullet on whether ordinary option values can
  trigger execution, a privilege change, or data exposure (Security review surface, Configuration). Rejected: leaving
  the assessment out of the design.

### Decisions after the review of the ready pull request

The maintainer decided these points in conversation on 2026-10-05, on comments an automated reviewer left on the ready
pull request.

- **The claims about ignored npm configuration name the layers the feature isolates.** The spec's Requirements "Install
  the requested version" and "Ignore the image's download settings", proposal.md - What Changes, Security review
  surface - Downloads, and "What is verified" in `src/openspec/NOTES.md` say that no environment variable of the build
  other than `PATH` and no user, global, or project npm configuration reaches the feature's Node.js and npm calls, and
  that the npmrc built into the Node.js installation is part of the installation the feature trusts as it is and is not
  ignored (Risks). This replaces "regardless of any registry configured in the image", which the decisions of 2026-10-05
  kept, and answers the open question on the proposal's sentence with its option (b), extended to the spec. No script
  changes, and the check of the built-in npmrc stays out. Rejected: keeping the broader sentences and reading them as
  covering only the isolated layers.
- **A directory at the wrapper's path fails the install.** `mv --force` would put the new wrapper inside it and report
  success with a command that does not run, after the previous prefix was replaced. `install.sh` fails before any
  network access, with a message saying to remove the directory, and the final move cannot descend into a directory
  (Goals). The spec gains no clause: no install of this feature and no listed image produces that state, and the build
  fails as it does for any image the feature cannot be installed on. Checked by the local run recorded in the PR's
  Validation section. Rejected: removing the directory — it is not the feature's to delete.

### Decisions on the open questions

The maintainer decided these two points in conversation on 2026-10-05. They were the questions the revision left outside
the decisions of 2026-10-05, and the package was already written for the answer each got, so no script, test, or spec
changes. No question is open. Like the decisions above, the answers settle the points named here and do not close the
package gate for the revised package.

- **`install.sh` names the TUF mirror.** `.agents/knowledge/shell-style.md` asks that a step that uses the network logs
  from where (Logging and failure) and that every external URL is a readonly constant (Options are data), and npm
  requests `https://tuf-repo-cdn.sigstore.dev` during `npm audit signatures`. The mirror is a readonly constant that the
  audit's log line and its failure hint name; the script never passes it to npm (Goals). Rejected: keeping the URL out
  of the script, with a log line that names only the registry and a failure hint that points to npm's report, which
  leaves a network step without its source in the log.
- **The leftover checks and the repeated "Fresh container" checks stay under the labels they have.** The spec says
  "exactly one OpenSpec installation SHALL remain reachable as `openspec`" (Install twice) and states "Fresh container"
  for a started container; it has no sentence on what an install leaves behind or on what running the installed CLI
  writes. `test.sh` and `duplicate.sh` check that no staging directory, set-aside prefix, or unfinished wrapper is left
  next to the installation, under the words of Requirement "Install twice", read as one installation with nothing staged
  or set aside next to it; `test.sh` repeats two "Fresh container" checks after `openspec --version` and the probe ran,
  under the words of "Fresh container", with a comment saying that it repeats them after the CLI ran. Rejected: a
  sentence in Requirement "Install twice" that nothing else of an install remains next to the installed locations, with
  a scenario, as `restyle-glab` did with "Leave no build residue", which adds a contract for checks the tests already
  carry; dropping one or both groups and leaving them to review of `install.sh`, which removes checks the tests carry
  today.

## URL inventory

Every URL the feature's scripts access at build time, plus what the installed CLI contacts at run time depending on the
options. The feature's scripts access no URL at container start. "Verified" is a read-only GET or `curl -sSIL` on the
date given, with the observed status and final host. With `--no-audit` and `--no-update-notifier`, npm contacts neither
`POST https://registry.npmjs.org/-/npm/v1/security/advisories/bulk` nor `https://registry.npmjs.org/npm` (Context, npm
configuration), which are therefore not listed.

| URL / template                                                                                                                                                                                                                          | Purpose                                                                                              | When                                                          | Integrity / authenticity                                                                                                                          | Official source evidence                                                                                                                                                                                                                       | Verified                                                                                                                                                                                                        |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ghcr.io/devcontainers/features/node:2`                                                                                                                                                                                                 | `dependsOn`: Node.js and npm                                                                         | build (resolved by the dev container CLI)                     | OCI manifest digest; pinned by the consumer's lockfile if any                                                                                     | https://github.com/devcontainers/features/tree/main/src/node                                                                                                                                                                                   | 2026-09-30: tags list has `2`, `2.1`; `manifests/2` 200; `devcontainer-feature.json` 2.1.0; hosts `ghcr.io` (incl. `ghcr.io/token`), layer blob 307 to `pkg-containers.githubusercontent.com` (GitHub)          |
| `https://registry.npmjs.org/@fission-ai%2fopenspec`                                                                                                                                                                                     | Select the version (`dist-tags.latest` or an exact one) and read its publish time and `engines.node` | build                                                         | TLS alone, no redirect followed (spec: Install the requested version); selects a version and a bound, and the rows below then verify the packages | https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md (`GET /{package}`)                                                                                                                                                              | 2026-10-01: 200 `application/json`, no redirect, `dist-tags.latest` 1.14.0, `time` holds every version, host `registry.npmjs.org`                                                                               |
| `https://registry.npmjs.org/<package>` (scoped: `@scope%2fname`)                                                                                                                                                                        | Package metadata npm resolves the tree from, for OpenSpec and each dependency                        | build                                                         | HTTPS; carries each version's `dist.integrity` and `dist.signatures`, checked below                                                               | https://github.com/npm/registry/blob/main/docs/REGISTRY-API.md (`GET /{package}`); upstream install command `npm install -g @fission-ai/openspec@latest` in https://github.com/Fission-AI/OpenSpec                                             | 2026-09-30: `@fission-ai%2fopenspec` 200, host `registry.npmjs.org`; install trial fetched only this host                                                                                                       |
| `https://registry.npmjs.org/<name>/-/<basename>-<version>.tgz`                                                                                                                                                                          | Package tarballs                                                                                     | build                                                         | `sha512` `dist.integrity` checked by npm; registry ECDSA signature over name, version, integrity                                                  | REGISTRY-API.md (`dist.tarball`, "usually in the form of `https://registry.npmjs.org/<name>/-/<name>-<version>.tgz`")                                                                                                                          | 2026-09-30: `openspec-1.13.2.tgz` 200 `application/octet-stream`, host `registry.npmjs.org`                                                                                                                     |
| `https://registry.npmjs.org/-/npm/v1/attestations/<name>@<version>` (scoped: `@scope%2fname`)                                                                                                                                           | Provenance attestations checked by `npm audit signatures`                                            | build                                                         | Sigstore bundles verified against the TUF `trusted_root.json`                                                                                     | https://github.com/npm/pacote/blob/main/lib/registry.js (fetches the pathname of `dist.attestations.url` from the configured registry); https://github.com/npm/cli/blob/latest/docs/lib/content/commands/npm-audit.md                          | 2026-09-30: `@fission-ai%2fopenspec@1.13.2` 200, host `registry.npmjs.org`                                                                                                                                      |
| `https://tuf-repo-cdn.sigstore.dev/` + `<n>.root.json`, `timestamp.json`, `<n>.snapshot.json`, `<n>.targets.json`, `<n>.registry.npmjs.org.json`, `targets/registry.npmjs.org/<sha256>.keys.json`, `targets/<sha256>.trusted_root.json` | Registry signing keys and Sigstore trust root for `npm audit signatures`                             | build                                                         | TUF metadata chain signed back to the root shipped inside npm                                                                                     | https://github.com/npm/cli/blob/latest/lib/utils/verify-signatures.js (keys via `@sigstore/tuf`); https://github.com/sigstore/sigstore-js/blob/main/packages/tuf/src/index.ts (`DEFAULT_MIRROR_URL`); https://github.com/sigstore/root-signing | 2026-09-30: `timestamp.json` 200, `165.snapshot.json`, `8.registry.npmjs.org.json`, `14.targets.json`, and both hashed targets 200, host `tuf-repo-cdn.sigstore.dev`; keys target lists keyid `SHA256:DhQ8…C7U` |
| `https://registry.npmjs.org/-/npm/v1/keys`                                                                                                                                                                                              | Fallback key source, used by npm only when TUF has no target for the registry                        | build (fallback only)                                         | TLS alone (spec: Verify every installed package)                                                                                                  | https://github.com/npm/cli/blob/latest/docs/lib/content/commands/npm-audit.md ("Public signing keys are provided at `registry-host.tld/-/npm/v1/keys`")                                                                                        | 2026-09-30: 200, host `registry.npmjs.org`; keyid `SHA256:DhQ8…C7U`, `expires` null                                                                                                                             |
| `https://edge.openspec.dev/batch/`                                                                                                                                                                                                      | OpenSpec CLI telemetry (PostHog), not contacted by the feature's scripts                             | run time, only while telemetry is on                          | HTTPS                                                                                                                                             | https://github.com/Fission-AI/OpenSpec/blob/main/src/telemetry/index.ts (`POSTHOG_HOST`, `${POSTHOG_HOST}/batch/`)                                                                                                                             | 2026-09-30: `/batch/` HEAD 400 (`server: envoy`); DNS resolves to a PostHog-managed proxy (`proxy-us.posthog.com`), so PostHog operates it on upstream's domain                                                 |
| `https://registry.npmjs.org/@fission-ai/openspec/latest`                                                                                                                                                                                | OpenSpec CLI update check, not contacted by the feature's scripts                                    | run time, only inside `openspec update` while the check is on | HTTPS; follows cross-host HTTPS redirects                                                                                                         | https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md (the `openspec update` version check; `npm_config_registry`); https://github.com/Fission-AI/OpenSpec/blob/main/src/core/version-check.ts (`DEFAULT_REGISTRY`)                     | 2026-10-01: 200 `application/json`, no redirect, `.version` 1.14.0, host `registry.npmjs.org`                                                                                                                   |

The Node.js feature's own downloads (nvm, Node.js, pnpm, and apt packages) belong to that feature and are not listed.

## Risks / Trade-offs

- [A dependency release from a compromised publisher lies within upstream's ranges] → A registry signature does not
  help: the registry signs whatever an authenticated publisher uploads. Resolution is bounded to the OpenSpec version's
  publish time, so only a release that predates upstream's own is installed; no install script runs, and the one
  build-time run of package code is unprivileged. What remains: a compromised release published before upstream's is
  installed, and its code runs as the remote user when `openspec` is first used.
- [The bound keeps a dependency's later fix out until upstream releases again; a dependency version deprecated or
  unpublished afterwards changes the resolution or leaves a range without a version; the publish times rest on TLS to
  the registry alone] → Accepted: the tree is the one upstream released with unless the registry withdrew part of it,
  the fix arrives with the next OpenSpec release, an unresolvable range fails the build in npm, and a forged publish
  time can at worst lift the bound for that package, which is today's unbounded behavior.
- [`npm audit signatures` verifies manifests, not the installed files] → It runs on the install's cache with
  `--prefer-offline`, where npm verifies the package documents the install enforced each `integrity` from, and the
  altered-answer runs show it (Decisions - Tests). This rests on npm's cache behavior: if a later npm fetched the
  documents again, an alteration made only during the install would pass, as it does on a fresh cache, and the installed
  files would rest on TLS to the registry alone. The spec states that the feature makes no comparison of its own.
- [The chain of trust starts at the Node.js feature, which pipes nvm's installer into bash and downloads Node.js and npm
  over TLS, with nvm `latest` by default] → Not something this feature can strengthen: npm, its bundled TUF root, and
  Node.js's certificate authorities are what every check here runs on. The Node.js installation is also group-writable
  for the `nvm` group, which the remote user joins, so "root-owned" covers the prefix and the wrapper, not the Node.js
  binary the wrapper runs; that matters when root runs `openspec` later. `PATH` is the one variable the feature lets
  through, so a `node` or `npm` that the image or an earlier feature put first on `PATH` is run as it is, with the
  certificate authorities and code it brings.
- [An npmrc built into the Node.js installation sets a certificate authority, a proxy, or a scoped registry] → Part of
  the Node.js installation the feature trusts as it is, and no flag replaces that file (Context, npm configuration). The
  lockfile check still fails an entry whose `resolved` URL is outside `https://registry.npmjs.org/`; a scoped registry
  that keeps tarball URLs on that host is not detected.
- [The build cannot switch to uid 65534, for example in a user namespace that does not map it] → The build fails at the
  `openspec --version` check instead of running package code as root; there is no fallback.
- [npm 10.9.9, which Node.js 22 ships, intermittently fails the audit on valid attestations (Context, npm's verifier)] →
  The build fails closed, about one time in thirteen there, and a rebuild passes; the Node.js feature's default (`lts`)
  brings npm 11, where it was not seen. NOTES.md names it. Not adopted: repeating a failed audit once on the same cache
  — it passed whenever tried, but it would answer a verification failure with a second try for a defect of one npm line.
- [TUF or Sigstore's CDN unreachable, or a package without a signature] → The build fails closed. A consumer behind a
  firewall needs `registry.npmjs.org` and `tuf-repo-cdn.sigstore.dev` from the build, and `ghcr.io` and
  `pkg-containers.githubusercontent.com` where the dev container CLI runs (NOTES.md says so).
- [No private registry, mirror, build-time proxy, or added certificate authority (a TLS-inspecting proxy)] → Pinned on
  purpose so the source is the one the spec names; a consumer who needs one cannot use this version of the feature.
- [The install-time Node.js is removed later (`nvm uninstall`)] → The wrapper fails with a message naming the missing
  binary; reinstalling the feature or rebuilding fixes it.
- [A consumer's own `node:2` entry with other options installs Node.js twice; the default alias ends up at whichever ran
  last] → OpenSpec pins the Node.js current when it installs, and `--engine-strict` rejects one below 20.19.0; NOTES.md
  names the interaction.
- [An `openspec` installed later with `npm install -g` lands earlier on `PATH` and shadows the wrapper] → The update
  check that prints that command is off by default; NOTES.md says so.
- [Telemetry is on unless the consumer opts out, and goes to a PostHog-operated endpoint on upstream's domain] →
  Upstream's default, kept (Options). NOTES.md states it first, with the endpoint and the option that turns it off.
