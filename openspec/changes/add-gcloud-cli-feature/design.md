# Design

## Context

See [proposal.md](proposal.md) for motivation and [the delta](specs/gcloud-cli/spec.md) for the behavioral contract.

Upstream facts verified on 2026-11-24 against first-party Google Cloud sources
(`https://docs.cloud.google.com/sdk/docs/install-sdk.md.txt`, `https://docs.cloud.google.com/sdk/gcloud.md.txt`,
`https://docs.cloud.google.com/sdk/docs/components.md.txt`,
`https://docs.cloud.google.com/sdk/docs/downloads-versioned-archives.md.txt`,
`https://docs.cloud.google.com/docs/authentication/gcloud.md.txt`), repository metadata, and throwaway containers:

- **First-party doc verification**: `docs.cloud.google.com` serves a TLS certificate issued by Google Trust Services
  (`WE2`) with SAN `DNS:*.cloud.google.com`, `Google Frontend` headers, and `rel="canonical"` pointing from `.md.txt`
  endpoints to their HTML counterparts (`install-sdk`, `gcloud`).
- **Current release and retention**: `594.0.1` (`2026-11-22`). APT and YUM repositories retain package versions
  published within the last 365 days.
- **APT repository (`https://packages.cloud.google.com/apt`)**:
  - `dists/cloud-sdk/InRelease` is OpenPGP-signed by `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`
    (`Artifact Registry Repository Signer <artifact-registry-repository-signer@google.com>`, RSA-2048,
    `https://packages.cloud.google.com/apt/doc/apt-key.gpg`, one primary public key).
  - Package versions use `<version>-0`, except `kubectl` which uses epoch `1:<version>-0`.
  - Both `amd64` and `arm64` publish `google-cloud-cli` and component packages
    (`google-cloud-cli-gke-gcloud-auth-plugin`, `kubectl`, `google-cloud-cli-cbt`, `google-cloud-cli-skaffold`, etc.);
    `all`-arch packages provide emulator and App Engine packages. Tested live on `debian:12`.
- **DNF repository (`https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-{x86_64,aarch64}`)**:
  - Signed by `https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg`, which holds one RSA-4096 primary
    public key (`C5F744A098136F40C370E8493156C631B64936F9`, `Google Cloud v10 RPM Package Signing Key v1`, SHA-512
    self-signature, expires `2038-06-01`).
  - Tested live on `almalinux:9`, `almalinux:10`, and `fedora:44` with `CLOUDSDK_SKIP_PY_COMPILATION=1`:
    `google-cloud-cli` (`594.0.1-1.el10`) requires only `/bin/sh` (unlike `el9`, no `libxcrypt-compat.x86_64` is
    required) and installs cleanly with `gpgcheck=1` and `repo_gpgcheck=0`.
  - Setting `repo_gpgcheck=1` fails on `almalinux:10` and `fedora:44` (`Bad PGP signature`) because `repomd.xml.asc` is
    still signed by `yum-key.gpg` (`35BAA0B3...`, RSA-2048), which EL10/Fedora 44 crypto policy rejects, while
    `almalinux:9` accepts it. Meanwhile the legacy `el9` key `rpm-package-key.gpg`
    (`3749E1BA95A86CE054546ED2F09C394C3E1BA8D5`) uses a 2015 RSA-2048 key with a SHA-1 self-signature, which modern
    RPM/Fedora rejects. Using `cloud-sdk-el10-<arch>` with `gpgcheck=1` and `repo_gpgcheck=0` therefore matches Google's
    own documented `el10` configuration and works across `almalinux:9`, `almalinux:10`, and `fedora:44`.
- **Linux archive fallback (`dl.google.com` and `storage.googleapis.com/cloud-sdk-release`)**:
  - Latest archive URLs:
    `https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-{x86_64,arm}.tar.gz`.
  - Versioned archive URLs:
    `https://storage.googleapis.com/cloud-sdk-release/google-cloud-cli-<version>-linux-{x86_64,arm}.tar.gz` (verified
    `HTTP 200` for `594.0.1` and historical `587.0.0` on both `x86_64` and `arm`).
  - Sibling `.sha256`, `.sha256sum`, `.asc`, and `.sig` URLs all return `HTTP 404`; upstream publishes SHA-256 values
    only inside the HTML/Markdown quickstart table for the latest release, not as a machine-readable release checksum
    asset.
  - Verified live on `opensuse/leap:16.0`: bundled Python `3.14.9` runs directly without installing a separate Python
    runtime.
- **State and configuration behavior**:
  - Verified live on `debian:12`: `gcloud` resolves its global config directory to `$HOME/.config/gcloud` even when
    `XDG_CONFIG_HOME` differs, and respects `CLOUDSDK_CONFIG`.
  - Writing config via `gcloud config set` when `$HOME/.config/gcloud` is a symlink to `/var/lib/gcloud-cli/config`
    writes cleanly into the target directory (`active_config`, `configurations/config_default`, `gce`, `logs/`) without
    replacing the symlink.
  - Both `gcloud auth login` (`credentials.db`, `access_tokens.db`, `legacy_credentials/`) and
    `gcloud auth application-default login` (`application_default_credentials.json`) store their files inside
    `$HOME/.config/gcloud`.

## Goals / Non-Goals

**Goals (each with how it is checked):**

- **Bash dialect across shipped and test scripts (`install.sh`, `initialize.sh`, tests)**: shipped scripts use
  `#!/usr/bin/env bash` with `set -euo pipefail`, and test scripts source `dev-container-features-test-lib`,
  prioritizing readability and auditability per `shell-style.md`. Checked by `shellcheck` in `just check`.
- **HTTPS on every hop**: all `curl` calls pass `--proto '=https' --proto-redir '=https'` and hit only URLs in the URL
  inventory; repository configs use HTTPS `baseurl`/APT sources. Checked by code inspection and a `curl` stub in
  `fail_contract`.
- **Validate before mutation**: OS/architecture, option syntax (`version`, `components`), fallback prerequisites, and
  target path sanity are validated before touching repositories, downloading archives, or installing packages. Checked
  by `fail_contract`.
- **Single-key fingerprint pinning on Plan A**: key downloads are inspected in a temporary `GNUPGHOME` to verify exactly
  one primary public key matching the pinned fingerprint before writing keyring/repo files. Checked by `fail_contract`
  (tampered/multi-key fixtures).
- **Atomic replacement on Plan B**: archives extract and run `gcloud version` inside a temporary directory and `HOME`
  before moving `/usr/local/share/google-cloud-sdk` into place and linking `/usr/local/bin/{gcloud,bq,gsutil,...}`.
  Checked by `fail_contract` and `duplicate.sh`.
- **Private, bounded state persistence**: `$HOME/.config/gcloud` links to `/var/lib/gcloud-cli/config` on named volume
  `gcloud-cli-${devcontainerId}`; healthy volumes initialize without `find` or `sudo`, and ownership repair stays
  strictly inside `/var/lib/gcloud-cli` (`find -P -xdev`). Checked by `test_state` and
  `test/gcloud-cli/manual/state_persistence.sh`.
- **Zero build residue**: package caches (`apt`, `dnf`, `zypper`) and temporary directories (`GNUPGHOME`, staging dirs)
  are cleaned on every exit via `trap`. Checked in `test.sh` and `fail_contract`.

**Non-Goals:**

- Architectures outside `amd64`/`x86_64` and `arm64`/`aarch64` (such as 32-bit `x86` or non-Linux OSes).
- Images without `bash` (such as stock Alpine Linux / musl images); the feature uses Bash for readability and never
  installs `bash` into a user's image.
- Build-time `gcloud auth`, service-account impersonation setup, or host `~/.config/gcloud` bind mounts.
- Host keyring / Secret Service provisioning or D-Bus session management.
- Installing VS Code extensions automatically (`GoogleCloudTools.cloudcode` is documented optionally in `NOTES.md`).
- Supporting `CLOUDSDK_CONFIG` overrides into the named volume (explicitly rejected as a state conflict).

## Decisions

### Option interface

| Name         | Type     | Default    | Proposals                               | Meaning                                                                             |
| ------------ | -------- | ---------- | --------------------------------------- | ----------------------------------------------------------------------------------- |
| `version`    | `string` | `"latest"` | `["latest","590.0.0"]`                  | Release to install: `latest` or an exact `MAJOR.MINOR.PATCH` version                |
| `components` | `string` | `""`       | `["","kubectl,gke-gcloud-auth-plugin"]` | Comma-separated gcloud CLI component IDs to install alongside the base CLI packages |

- **Why `version` defaults to `"latest"`**: Google strongly recommends the current release in its documentation, and
  APT/YUM retain only the last 365 days of releases, so `"latest"` stays evergreen while pinned versions remain
  reproducible within the upstream retention window (or on archive fallback via `cloud-sdk-release`). Proposal
  `"590.0.0"` is an older existing release so `duplicate.sh` exercises replacing an older version with `latest`.
- **Why `components` defaults to `""`**: the base `google-cloud-cli` installation already provides `gcloud`, `bq`,
  `gsutil`, `alpha`, `beta`, and `preview` (~400 MB unpacked) without adding heavy extras like `kubectl`, emulators, or
  App Engine SDKs unless requested.
- **Rejected option shapes**:
  - Boolean flags per popular component (`installKubectl`, `installGkeAuthPlugin`): hard to maintain as components
    evolve; a single `components` string handles any published component uniformly.
  - Accepting raw OS package names (`google-cloud-cli-...`) directly in `components`: couples user configs to Plan A vs
    Plan B packaging differences. Canonical gcloud component IDs work identically across both routes.
  - Project/account/auth options or a toggle to disable Plan B fallback or GPG checks: violates build-time no-credential
    rules and collection integrity rules.

### Primary APT and DNF route (Plan A)

- **Debian/Ubuntu (`ID` or `ID_LIKE` matching `debian` or `ubuntu` with `apt-get`)**: installs `ca-certificates`,
  `curl`, `gnupg` only if missing; downloads `apt-key.gpg`, verifies exactly one primary public key matching
  `35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3`, writes `/usr/share/keyrings/cloud.google.gpg`, writes
  `/etc/apt/sources.list.d/google-cloud-sdk.list` (`signed-by`), and installs `google-cloud-cli` plus mapped component
  packages with `CLOUDSDK_SKIP_PY_COMPILATION=1` and `--allow-downgrades` (for second-install downgrades). When
  `version != "latest"`, packages pin `=<version>-0` (`kubectl=1:<version>-0`).
- **Fedora/RHEL (`ID` or `ID_LIKE` matching `fedora` or `rhel` with `dnf`)**: installs `ca-certificates`, `curl`,
  `gnupg2` only if missing; downloads `rpm-package-key-v10.gpg`, verifies exactly one primary public key matching
  `C5F744A098136F40C370E8493156C631B64936F9`, writes `/etc/pki/rpm-gpg/RPM-GPG-KEY-google-cloud-rpm-v10`, imports into
  RPM, writes `/etc/yum.repos.d/google-cloud-sdk.repo` pointing at `cloud-sdk-el10-<arch>` with `gpgcheck=1` and
  `repo_gpgcheck=0`, and installs with `CLOUDSDK_SKIP_PY_COMPILATION=1`. When `version != "latest"`, pins
  `-<version>-1.el10`. When `version == "latest"` on a second install, runs `dnf upgrade` after `dnf install` (and
  `dnf downgrade` when switching to an older explicit version).
- **Rejected alternatives**:
  - `cloud-sdk-el9-*` with `rpm-package-key.gpg`: uses a 2015 SHA-1 self-signed key rejected by Fedora 44 / RHEL 10.
  - `repo_gpgcheck=1` on `cloud-sdk-el10-*`: fails on `almalinux:10` and `fedora:44` due to upstream signing
    `repomd.xml.asc` with RSA-2048 `yum-key.gpg` (documented in Context).
  - Bundling GPG keys inside `src/gcloud-cli/`: pinning full fingerprints while fetching upstream's key URL keeps
    rotation explicit and follows `nvidia-container-toolkit`.

### Archive fallback with warning (Plan B)

- **Trigger**: Linux `x86_64` or `aarch64` when `ID`/`ID_LIKE` matches neither Debian/Ubuntu with `apt-get` nor
  Fedora/RHEL with `dnf` (e.g. `opensuse/leap:16.0`, `archlinux`, or custom bash-capable glibc distributions). Emits
  `gcloud-cli: warning: distribution "<os_id>" is outside supported APT and DNF repositories; falling back to official Linux archive`
  to stderr/stdout without failing.
- **Prerequisites**: installs missing `curl`, `ca-certificates` (`ca-certificates-mozilla` on SUSE), `tar`, and `gzip`
  via `zypper --non-interactive` or `pacman -Syu --needed` if present; if an unknown fallback image lacks a supported
  package manager and misses prerequisites, fails clearly naming them.
- **Install & components**: extracts into staging under `/usr/local/share/.gcloud-cli-install.XXXXXX`, runs
  `gcloud version` in temporary `HOME`, installs requested `components` via
  `CLOUDSDK_CORE_DISABLE_PROMPTS=1 HOME=<tmp> /staging/bin/gcloud components install --quiet <ids...>`, atomically swaps
  `/usr/local/share/google-cloud-sdk`, and links `/usr/local/share/google-cloud-sdk/bin/{gcloud,bq,gsutil,...}` (plus
  `kubectl` or component binaries present in `bin/`) into `/usr/local/bin/` with `ln -sf`.
- **Second install skip/replace**: if `/usr/local/share/google-cloud-sdk` already exists and `gcloud version` matches an
  explicit `version` AND all requested `components` binaries/components are already installed, skip re-downloading the
  archive; otherwise install the new archive and components cleanly.
- **Rejected alternatives**:
  - Hard-failing outside APT/DNF: explicitly rejected by user requirement in favor of warning + fallback.
  - Scraping SHA-256 from `install-sdk.md.txt`: fragile HTML/Markdown doc scraping that only covers `latest` and breaks
    on doc layout changes; upstream provides no versioned `.sha256` asset.

### Component mapping across routes

| Component ID               | Plan A (APT / DNF package)            | Plan B (`gcloud components install`) |
| -------------------------- | ------------------------------------- | ------------------------------------ |
| `alpha`, `beta`, `preview` | Already bundled in `google-cloud-cli` | Installed via `gcloud components`    |
| `kubectl`                  | `kubectl` (`1:<ver>-0` on APT)        | `kubectl`                            |
| `bigtable`                 | `google-cloud-cli-bigtable-emulator`  | `bigtable`                           |
| `cloud-datastore-emulator` | `google-cloud-cli-datastore-emulator` | `cloud-datastore-emulator`           |
| `gcd-emulator`             | `google-cloud-cli-datastore-emulator` | `gcd-emulator`                       |
| `cloud-firestore-emulator` | `google-cloud-cli-firestore-emulator` | `cloud-firestore-emulator`           |
| `cloud-spanner-emulator`   | `google-cloud-cli-spanner-emulator`   | `cloud-spanner-emulator`             |
| `<other-id>`               | `google-cloud-cli-<other-id>`         | `<other-id>`                         |

Component validation rejects empty items, whitespace, leading/trailing/repeated commas, or characters outside
`[a-z0-9-]` (preventing option injection into package managers or `gcloud components install`).

### Runtime state and initialization timing

Follows the `antigravity` / `claude-code` state pattern:

- Named volume `gcloud-cli-${devcontainerId}` mounted at `/var/lib/gcloud-cli`; `installsAfter`:
  `["ghcr.io/devcontainers/features/common-utils"]`; `onCreateCommand`:
  `"/usr/local/share/gcloud-cli-feature/initialize"`.
- Build time (`install.sh`): resolves `_REMOTE_USER` / `_REMOTE_USER_HOME`, verifies `/var/lib/gcloud-cli` and
  `${_REMOTE_USER_HOME}/.config/gcloud` have no conflicting targets, creates `/var/lib/gcloud-cli` (`0700`) and
  `/var/lib/gcloud-cli/config` (`0700`) owned by remote user, creates symlink
  `${_REMOTE_USER_HOME}/.config/gcloud -> /var/lib/gcloud-cli/config`, and installs `initialize` (`0755`) to
  `/usr/local/share/gcloud-cli-feature/initialize`.
- Creation time (`initialize`):
  - Runs as the remote user via `onCreateCommand` (and supports `--repair <uid> <gid>` via noninteractive `sudo`).
  - Fails if `/var/lib/gcloud-cli` is a symlink or not a mountpoint (`mountpoint -q`).
  - Fails if `CLOUDSDK_CONFIG` is non-empty and does not resolve to `$HOME/.config/gcloud` or
    `/var/lib/gcloud-cli/config`.
  - Fails if `$HOME/.config/gcloud` exists as a non-symlink, dangling link, or link to another target, preserving it
    untouched.
  - Rejects symlinks at `/var/lib/gcloud-cli/config` or known credential files (`config/credentials.db`,
    `config/access_tokens.db`, `config/application_default_credentials.json`, `config/legacy_credentials`) before any
    `chmod`/`chown`.
  - Checks ownership (`stat -c %u`) and private modes (`0700` for state root and `config`; `0600` for `credentials.db`,
    `access_tokens.db`, `application_default_credentials.json`) without scanning the tree when healthy; repairs
    mode-only mismatches directly without `sudo`, and invokes `find -P /var/lib/gcloud-cli -xdev` only when ownership
    mismatches require UID repair.
  - Probes write access with a temporary file in `/var/lib/gcloud-cli/config` and creates missing `$HOME/.config/gcloud`
    symlink if absent (e.g., if `$HOME` was mounted over the image home).
- **Why link `$HOME/.config/gcloud` instead of setting `CLOUDSDK_CONFIG`**: upstream tools, libraries, and third-party
  integrations (including ADC discovery and `antigravity`) read `~/.config/gcloud` directly by default; linking
  preserves exact upstream discovery paths while keeping `CLOUDSDK_CONFIG` unset and leaving unrelated `~/.config/*`
  directories outside the volume.
- **No `postStartCommand` / `postAttachCommand`**: ordinary restarts and editor attachments incur zero overhead.

### Bash dialect

`src/gcloud-cli/install.sh`, `src/gcloud-cli/initialize.sh`, and all test scripts use `#!/usr/bin/env bash` with
`set -euo pipefail` (and standard `dev-container-features-test-lib` in tests) for readability and auditability. Images
without `bash` (such as stock Alpine) are intentionally excluded rather than installing `bash` into user images or
dropping to POSIX `sh` (`shell-style.md`).

### Tests

- `test/gcloud-cli/compatibility.json`: `scenarioArchitectures: ["amd64", "arm64"]`; 6 images (table below).
- `test/gcloud-cli/test.sh` (bash sourcing `dev-container-features-test-lib`): verifies `gcloud version`, `bq version`,
  `gsutil version` as remote user on default PATH, binaries outside `/var/lib/gcloud-cli`, untouched shell profiles,
  repo configs on APT/DNF, clean package caches, and no temp residue.
- `test/gcloud-cli/duplicate.sh`: installs `version="590.0.0"` and `components="kubectl"`, then installs defaults
  (`version="latest"`, `components=""`), verifying the latest version is active, no duplicate repo files exist, and
  state mappings remain intact.
- Scenarios (`scenarios.json`, `scenarioArchitectures: ["amd64", "arm64"]`):
  - `test_components_apt` (`debian:12`, `components: "kubectl,gke-gcloud-auth-plugin,alpha"`): verifies `kubectl` and
    `gke-gcloud-auth-plugin` binaries and `gcloud alpha --help`.
  - `test_components_dnf` (`fedora:44`, `components: "kubectl,gke-gcloud-auth-plugin,beta"`): verifies DNF component
    mapping and execution.
  - `test_pinned_version` (`mcr.microsoft.com/devcontainers/base:ubuntu24.04`, `remoteUser: "vscode"`,
    `version: "590.0.0"`, `components: "kubectl"`): verifies exact version pinning on Plan A for both `google-cloud-cli`
    and `kubectl`.
  - `test_fallback_components` (`opensuse/leap:16.0`, `version: "590.0.0"`, `components: "kubectl,alpha"`): verifies
    warning emission, archive fallback, version pinning, and `gcloud components install`.
  - `test_state` (`mcr.microsoft.com/devcontainers/base:ubuntu24.04`, `remoteUser: "vscode"`, `--network=none`):
    exercises `initialize`, healthy-volume no-scan/no-sudo check, missing-mount failure, real `gcloud config set`
    writes, atomic replacement of synthetic `credentials.db`/`access_tokens.db`/`application_default_credentials.json`,
    unrelated `~/.config` coexistence, link conflict preservation, `CLOUDSDK_CONFIG` conflict, mode repair without
    `sudo`, changed-UID repair without touching external symlink targets, unavailable-repair failure, and state symlink
    protection.
  - `fail_contract` (`debian:12`): uses stubbed `curl`/system commands to verify pre-mutation rejections (malformed
    version, malformed components, unsupported arch, missing `/etc/os-release`), GPG key fingerprint mismatch/multi-key
    rejection, fallback missing prerequisites, failed archive preserving prior CLI, and clean temp/cache cleanup.
- Unattended two-container synthetic-fixture check: `test/gcloud-cli/manual/state_persistence.sh` (non-networked,
  creates two isolated test volumes, verifies real `gcloud config set` + synthetic credential bytes/modes persist across
  container recreation and stay isolated per volume).

## Security review

- **Downloads**: HTTPS only (`--proto '=https' --proto-redir '=https'`) from Google-controlled endpoints
  (`packages.cloud.google.com`, `dl.google.com`, `storage.googleapis.com`). Nothing is piped into a shell.
- **Verification**: Plan A pins full OpenPGP primary fingerprints (`35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3` for APT,
  `C5F744A098136F40C370E8493156C631B64936F9` for DNF) and verifies single-primary public key count before writing repo
  files. DNF `repo_gpgcheck=0` (metadata freshness relies on TLS; RPM verifies every package) and Plan B archive +
  `gcloud components install` TLS-only trust are explicitly documented as accepted risks in the spec.
- **Metadata**: declares `installsAfter`, named volume `gcloud-cli-${devcontainerId}`, and `onCreateCommand` only; no
  `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, `containerEnv`, or recurring lifecycle hooks.
- **Build-time execution**: `gcloud` runs at build time only for version check / `components install` on Plan B, always
  with an isolated temporary `HOME`. No build-time auth or host credential copying occurs.
- **Privacy**: state root and `config` use `0700`; known credential stores (`credentials.db`, `access_tokens.db`,
  `application_default_credentials.json`) use `0600`; repair never traverses outside `/var/lib/gcloud-cli` (`-P -xdev`)
  and never prints credential contents.

## Supported images

Planned `test/gcloud-cli/compatibility.json` (`scenarioArchitectures: ["amd64", "arm64"]`):

| Image                                              | Architectures | Route  | Notes                                                        |
| -------------------------------------------------- | ------------- | ------ | ------------------------------------------------------------ |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64  | Plan A | `remoteUser: "vscode"`; standard Ubuntu dev container base   |
| `debian:12`                                        | amd64, arm64  | Plan A | Minimal APT image without preinstalled `curl` or `gnupg`     |
| `almalinux:9`                                      | amd64, arm64  | Plan A | RHEL 9 family matched via `ID_LIKE`; DNF with `el10` repo    |
| `almalinux:10`                                     | amd64, arm64  | Plan A | RHEL 10 family; verifies `rpm-package-key-v10.gpg`           |
| `fedora:44`                                        | amd64, arm64  | Plan A | Fedora DNF 5 + strict crypto policy                          |
| `opensuse/leap:16.0`                               | amd64, arm64  | Plan B | Warning + archive fallback on glibc (`zypper` prerequisites) |

## URL inventory

All URLs below are fetched at image build time over HTTPS only (`--proto '=https' --proto-redir '=https'`); nothing is
fetched by feature helpers at container start.

| URL                                                                                                     | Purpose                         | Route  | Verification                                                 | Evidence (2026-11-24)                        |
| ------------------------------------------------------------------------------------------------------- | ------------------------------- | ------ | ------------------------------------------------------------ | -------------------------------------------- |
| `https://packages.cloud.google.com/apt/doc/apt-key.gpg`                                                 | APT repository signing key      | Plan A | Single primary public key; pinned fingerprint `35BAA0B3...`  | `200`, RSA-2048 public key                   |
| `https://packages.cloud.google.com/apt`                                                                 | APT `cloud-sdk main` repository | Plan A | Signed `InRelease` verified by APT against pinned key        | `200`, `594.0.1-0` (`kubectl` `1:594.0.1-0`) |
| `https://packages.cloud.google.com/yum/doc/rpm-package-key-v10.gpg`                                     | RPM v10 repository signing key  | Plan A | Single primary public key; pinned fingerprint `C5F744A0...`  | `200`, RSA-4096 public key                   |
| `https://packages.cloud.google.com/yum/repos/cloud-sdk-el10-{x86_64,aarch64}`                           | DNF `cloud-sdk` repository      | Plan A | RPM `gpgcheck=1` against pinned key (`repo_gpgcheck=0`, TLS) | `200`, `594.0.1-1.el10`                      |
| `https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-{x86_64,arm}.tar.gz` | Latest Linux fallback archive   | Plan B | HTTPS/TLS only (no upstream checksum/signature asset)        | `200` for both `x86_64` and `arm`            |
| `https://storage.googleapis.com/cloud-sdk-release/google-cloud-cli-<version>-linux-{x86_64,arm}.tar.gz` | Pinned Linux fallback archive   | Plan B | HTTPS/TLS only (no upstream checksum/signature asset)        | `200` for `594.0.1` and `587.0.0`            |
| `https://dl.google.com/dl/cloudsdk/channels/rapid/...` (via `gcloud components install`)                | Fallback additional components  | Plan B | HTTPS/TLS inside `gcloud components`                         | Verified `components-2.json` and `v594.0.1`  |

## Risks / Trade-offs

- [Upstream rotates APT or RPM v10 signing keys] -> Key fingerprint verification fails cleanly before touching package
  sources until a feature update pins the new fingerprint.
- [Upstream retains only 365 days of packages in APT/YUM] -> Pinning a version older than 365 days on Plan A fails with
  a clear version-unavailable message (`NOTES.md` documents the 365-day window).
- [DNF `repo_gpgcheck=0` leaves `repomd.xml` metadata verified by TLS only] -> Every installed RPM package is still
  OpenPGP-verified (`gpgcheck=1`) against the pinned RSA-4096 key; accepted and documented in the spec.
- [Plan B Linux archives have no detached signatures or standalone checksums] -> Relies on HTTPS/TLS to
  Google-controlled hosts (`dl.google.com`, `storage.googleapis.com`); accepted and documented in the spec.
- [State directory layout assumes `$HOME/.config/gcloud`] -> Users overriding `CLOUDSDK_CONFIG` outside the mapped
  directory receive an explicit conflict error rather than silent ephemeral state (`NOTES.md` documents this boundary).
