# Proposal

Implements [#206](https://github.com/hoshiori-dev/devcontainer-features/issues/206).

## Why

Developers and coding agents need the Google Cloud CLI (`gcloud`, `bq`, `gsutil`, plus optional components such as
`kubectl` and `gke-gcloud-auth-plugin`) inside project dev containers without losing private configuration, CLI
authentication state, and Application Default Credentials (`~/.config/gcloud`) whenever containers are rebuilt. The
`antigravity` feature's notes already point consumers to a Google Cloud CLI feature for persisting Application Default
Credentials.

## What Changes

- Add a new independent feature `gcloud-cli` at version `1.0.0`.
- Install Google Cloud CLI (`gcloud`, `bq`, `gsutil`) on `PATH` for every user, preferring Google's signed APT and DNF
  package repositories when the distribution supports them and falling back with a warning to Google's official Linux
  tar.gz archives for distributions outside APT and DNF.
- Support pinning a release with `version` and installing additional components with `components`.
- Persist private project-scoped `~/.config/gcloud` state (CLI configurations, CLI auth stores, and Application Default
  Credentials) in a named volume with creation-time readiness checks and bounded ownership repair, without build-time
  credentials or recurring start/attach hooks.
- Support installing twice on the same image with the same or different options.
- Add `test/gcloud-cli/` coverage and update generated READMEs and `README.zh.md` during implementation.

## Capabilities

### New Capabilities

- `gcloud-cli`: installation via signed APT and DNF repositories with Linux archive fallback, version and component
  selection, project-scoped private state persistence, idempotent reinstallation, and failure handling.

### Modified Capabilities

None.

## Impact

- Feature ids touched: `gcloud-cli`, new at version `1.0.0`.
- Planned files at implementation: `src/gcloud-cli/` (`devcontainer-feature.json`, `install.sh`, `initialize.sh`,
  `NOTES.md`, generated `README.md`), `test/gcloud-cli/` (`compatibility.json`, `test.sh`, `duplicate.sh`,
  `scenarios.json` with scenario scripts, and `manual/state_persistence.sh`), root `README.md` (generated feature list),
  and `README.zh.md` (translated row). `test/canary.json` is not touched.
- Metadata: `installsAfter` (`ghcr.io/devcontainers/features/common-utils`), `mounts` (`gcloud-cli-${devcontainerId}`
  mounted at `/var/lib/gcloud-cli`), and `onCreateCommand` (`/usr/local/share/gcloud-cli-feature/initialize`); no
  `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, `postStartCommand`, `postAttachCommand`, or
  `containerEnv`.
- Security: the delta spec states the two accepted TLS-only risks (DNF `repo_gpgcheck=0` for metadata freshness;
  fallback Linux archive and `gcloud components install` downloads).
- Implementation planning: `tasks.md` will be written only after `spec:approved` closes the package gate on the draft
  pull request.

## Acceptance

### Becomes true

- Every scenario in [the `gcloud-cli` delta](specs/gcloud-cli/spec.md) holds on every applicable image and architecture
  in `test/gcloud-cli/compatibility.json` via `test.sh`, `duplicate.sh`, and scenarios (with unattended
  synthetic-fixture recreation and isolation verified by `test/gcloud-cli/manual/state_persistence.sh`), and results are
  recorded in the pull request's Validation section.
- `test/gcloud-cli/compatibility.json` lists the exact images and architectures planned in [design.md](design.md)
  (`## Supported images`).
- `src/gcloud-cli/devcontainer-feature.json` declares version `1.0.0`, `src/gcloud-cli/NOTES.md` covers routes, options,
  state volume and migration, authentication boundaries, and optional editor integration, `src/gcloud-cli/README.md` and
  root `README.md` match `just docs`, and `README.zh.md` carries the translated row.
- `just check`, `just test gcloud-cli`, `just test-scenarios gcloud-cli`, and pull request container jobs on amd64 and
  arm64 pass.

### Stays true

- Existing features and their state remain unchanged, including when installed together with `gcloud-cli`.
- No real credentials, OAuth tokens, service account keys, or account identifiers ever enter the checkout, image layers,
  test logs, or published review artifacts.
- No shell startup files are edited by the feature, and no privileged mode, added capabilities, weakened security
  profile, host-home mount, or recurring start/attach state hook is introduced.
- `just check` and all required pull request checks pass.
