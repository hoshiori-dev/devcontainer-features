
# OpenSpec (openspec)

Installs the OpenSpec CLI (openspec) from the npm registry, verifying every package's integrity hash and registry signature, on a Node.js runtime it brings in as a dependency.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/openspec:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The OpenSpec version to install: latest, the version the npm registry names as latest at build time, or one exact published version such as 1.13.1. | string | latest |
| disableUpdateCheck | Run openspec with OPENSPEC_NO_UPDATE_CHECK=1, which skips the version check inside `openspec update`, unless the caller's environment already sets that variable. | boolean | true |
| disableTelemetry | Run openspec with OPENSPEC_TELEMETRY=0, which turns its usage telemetry off, unless the caller's environment already sets that variable. | boolean | false |

## Telemetry and the update check

- **Telemetry is on unless you turn it off.** The OpenSpec CLI sends usage telemetry to
  `https://edge.openspec.dev/batch/`, an endpoint on upstream's domain that PostHog operates. This is upstream's
  default, and the feature keeps it. Set `"disableTelemetry": true` to run `openspec` with `OPENSPEC_TELEMETRY=0`;
  upstream also honors `DO_NOT_TRACK=1` and a truthy `CI`.
- **The update check is off by default** (`disableUpdateCheck`, `OPENSPEC_NO_UPDATE_CHECK=1`). Inside `openspec update`
  the check prints `npm install -g @fission-ai/openspec@latest`. Following it puts a second, unverified copy into nvm's
  global prefix, which comes before `/usr/local/bin` on `PATH` and shadows the installation described here. To move to
  another OpenSpec version, change `version` or rebuild the container.
- Both options only set a default: a variable already set in the caller's environment, even to the empty string, is
  passed to `openspec` unchanged.

## What it installs

- The npm package `@fission-ai/openspec` at `version`, as a root-owned npm project tree in `/usr/local/lib/openspec`,
  and the wrapper `/usr/local/bin/openspec`, which every user can run. `version` is `latest` (the version the npm
  registry names as latest when the image is built) or one exact published version; a range, a partial version, or
  another dist-tag fails the build.
- Node.js comes from the dependency `ghcr.io/devcontainers/features/node:2` with its default options, so adding
  `openspec` alone is enough. The wrapper runs the Node.js binary that was on `PATH` when the feature was installed:
  `nvm use` or `nvm alias default` later does not change the Node.js `openspec` runs on. If that Node.js is removed
  (`nvm uninstall`), `openspec` fails with a message naming the missing binary; rebuild the container.
- The feature never runs `openspec init` or `openspec update` and writes nothing to the workspace or the home directory.
  Run `openspec init` in your project yourself.
- Installing the feature again replaces the installation: the later `version` and options win.

## What is verified

- Every package, OpenSpec and each dependency, is downloaded from `https://registry.npmjs.org/`, whatever registry,
  proxy, or certificate setting the image's environment or npm configuration holds; the feature's Node.js and npm calls
  see none of them.
- npm checks every package against the `sha512` hash the registry publishes for it, and `npm audit signatures` then
  checks every package's registry signature and each published provenance attestation, with keys from Sigstore's TUF
  repository at `https://tuf-repo-cdn.sigstore.dev`. A package that fails any of these fails the build and leaves an
  earlier installation untouched.
- Dependencies are the versions the registry had published when the OpenSpec release was published, so a later build of
  the same `version` does not pick up newer dependency releases. A fix in a dependency arrives with the next OpenSpec
  release.
- No install script of any package runs. The only package code the build runs is `openspec --version`, as an
  unprivileged user.
- What rests on TLS to the registry alone: which version `latest` is, the publish times behind the dependency bound, and
  the hashes themselves. A registry signature shows that the registry published those bytes under that name and version,
  not that the publisher's account was in its owner's hands.
- The Node.js feature is where the chain of trust starts: it pipes nvm's installer into bash and downloads Node.js and
  npm over TLS, and every check above runs on that npm. A `node` or `npm` that the image or an earlier feature puts
  first on `PATH` is used as it is.
- The Node.js installation is group-writable for the `nvm` group, which the remote user joins. The prefix and the
  wrapper are root-owned, but the Node.js binary the wrapper runs is not protected from that user; this matters when
  root runs `openspec` later.

## Build requirements and known failures

- Network: the build needs `registry.npmjs.org` and `tuf-repo-cdn.sigstore.dev`, and the machine running the dev
  container CLI needs `ghcr.io` and `pkg-containers.githubusercontent.com` for the Node.js feature, besides that
  feature's own downloads. If Sigstore's TUF repository cannot be reached, the build fails.
- A private registry or mirror, a build-time HTTP(S) proxy, and an added certificate authority (a TLS-inspecting proxy)
  are not supported. A certificate authority, proxy, or scoped registry in the `npmrc` built into the Node.js
  installation fails the build with a message naming the setting.
- Node.js must be at least what the OpenSpec version requires (20.19.0 for the current releases) and npm at least
  10.8.2. The Node.js feature's default (`lts`) satisfies both.
- Adding your own `ghcr.io/devcontainers/features/node:2` entry with other options installs Node.js a second time, and
  the default ends up at whichever ran last. OpenSpec keeps the Node.js that was current when it installed.
- npm 10.9.9, the npm of Node.js 22, sometimes reports a valid provenance attestation as invalid, in about one build of
  thirteen. The build then fails; building again passes. This was not seen with npm 10.8.2 or npm 11.

## OS support

Debian and Ubuntu images on amd64 and arm64; any other distribution or architecture fails the build with a message
naming it. The tested images are in [test/openspec/compatibility.json](../../test/openspec/compatibility.json).

## Upstream

- Home and README: https://github.com/Fission-AI/OpenSpec
- Installation guide: https://openspec.dev/docs/installation
- CLI reference: https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md
- Changelog: https://github.com/Fission-AI/OpenSpec/blob/main/CHANGELOG.md


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/openspec/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
