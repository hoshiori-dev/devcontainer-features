## Telemetry and the update check

- **Telemetry is on unless you turn it off.** The OpenSpec CLI sends usage telemetry to
  `https://edge.openspec.dev/batch/`, an endpoint on upstream's domain that PostHog operates. This is upstream's
  default, and the feature keeps it. Set `"disableTelemetry": true` to run `openspec` with `OPENSPEC_TELEMETRY=0`;
  upstream also turns telemetry off when `DO_NOT_TRACK=1` or a truthy `CI` is set.
- **The update check is off by default**: `disableUpdateCheck` is `true`, which runs `openspec` with
  `OPENSPEC_NO_UPDATE_CHECK=1`. Inside `openspec update`, the check prints `npm install -g @fission-ai/openspec@latest`.
  Following it puts a second, unverified copy into nvm's global prefix, which comes before `/usr/local/bin` on `PATH`
  and shadows the installation described here. To move to another OpenSpec version, set `version` and rebuild the
  container.
- Both options only set a default: a variable already set in the caller's environment, even to the empty string, is
  passed to `openspec` unchanged.
- `disableTelemetry` and `disableUpdateCheck` take `true` or `false`; any other value fails the build.

## What it installs

- The npm package `@fission-ai/openspec` at `version`, as a root-owned npm project tree in `/usr/local/lib/openspec`,
  and the root-owned command `/usr/local/bin/openspec`, which every user can run.
- `version` is `latest` (the version the npm registry names as latest when the image is built) or one exact published
  version such as `1.13.1`. A range (`^1.7.0`), a partial version (`1`), another dist-tag (`beta`), or an empty value
  fails the build.
- Node.js comes from the dependency `ghcr.io/devcontainers/features/node:2` with its default options, so adding
  `openspec` alone is enough. `openspec` runs on the Node.js binary that was first on `PATH` when the feature was
  installed: `nvm use` or `nvm alias default` later does not change the Node.js it runs on. If that Node.js is removed
  (`nvm uninstall`), `openspec` fails with a message naming the missing binary; rebuild the container.
- The feature never runs `openspec init` or `openspec update` and writes nothing to the workspace or the home directory.
  Run `openspec init` in your project yourself.
- Installing the feature again replaces the installation: the later `version`, `disableUpdateCheck`, and
  `disableTelemetry` win.

## What is verified

- Every package, OpenSpec and each dependency, is downloaded from `https://registry.npmjs.org/`, whatever registry,
  proxy, or certificate setting the image's environment or npm configuration holds; the feature's Node.js and npm calls
  see none of them.
- npm checks every package against the `sha512` hash the registry publishes for it, and `npm audit signatures` then
  checks every package's registry signature and each published provenance attestation, with keys from Sigstore's TUF
  repository at `https://tuf-repo-cdn.sigstore.dev`. A package that fails any of these checks fails the build, and an
  earlier installation stays as it was.
- Dependencies are installed at the versions the registry had published when the OpenSpec release was published, so a
  later build of the same `version` does not pick up newer dependency releases. The cost is that a fix in a dependency
  arrives only with the next OpenSpec release.
- No install script of any package runs. The only package code the build runs is `openspec --version`, as an
  unprivileged user.

## Build requirements and known failures

- Network: the build needs `registry.npmjs.org` and `tuf-repo-cdn.sigstore.dev`, and the machine running the dev
  container CLI needs `ghcr.io` and `pkg-containers.githubusercontent.com` for the Node.js feature, besides that
  feature's own downloads. If Sigstore's TUF repository cannot be reached, the build fails.
- A private registry or mirror, a build-time HTTP(S) proxy, and an added certificate authority (a TLS-inspecting proxy)
  are not supported. The feature does not use the settings that would configure them: the build's proxy and certificate
  variables (such as `HTTPS_PROXY` and `NODE_EXTRA_CA_CERTS`), `npm_config_*` variables, and the user, global, and
  project `.npmrc` files.
- Node.js must be at least what the OpenSpec version requires (20.19.0 for the current releases) and npm at least
  10.8.2; otherwise the build fails with a message naming the versions. The Node.js feature's default (`version` `lts`)
  satisfies both.
- Adding your own `ghcr.io/devcontainers/features/node:2` entry with other options installs Node.js a second time, and
  the default Node.js ends up being the one installed last. OpenSpec keeps the Node.js that was first on `PATH` when it
  was installed.
- npm 10.9.9, the npm of Node.js 22 (the Node.js feature's `version` set to `22`), sometimes reports a valid provenance
  attestation as invalid, in about one build of thirteen. The build then fails; building again passes. This was not seen
  with npm 10.8.2 or npm 11.

## OS support

Debian and Ubuntu images on amd64 and arm64, tested on the images in
[test/openspec/compatibility.json](../../test/openspec/compatibility.json). Other Debian derivatives, whose
`/etc/os-release` names `debian` in `ID_LIKE`, are accepted but not tested. Any other distribution or architecture fails
the build with a message naming it.

## Upstream

- Home and README: https://github.com/Fission-AI/OpenSpec
- Installation guide: https://openspec.dev/docs/installation
- CLI reference: https://github.com/Fission-AI/OpenSpec/blob/main/docs/cli.md
- Changelog: https://github.com/Fission-AI/OpenSpec/blob/main/CHANGELOG.md
