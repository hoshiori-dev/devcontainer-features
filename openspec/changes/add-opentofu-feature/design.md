# Design

## Context

See proposal.md - Why. The feature follows the `gitleaks` and `rclone` features (archived changes
`2026-10-16-add-gitleaks-feature` and `2026-11-09-add-rclone-feature`): a static Go binary from upstream's release
archives, verified before it is installed atomically to `/usr/local/bin`, with prerequisites from the image's own
repositories. Like `gitleaks`, it downloads from GitHub releases and resolves `latest` from GitHub's latest-release
link. Like `rclone`, it verifies the checksum list's OpenPGP signature against a key pinned by fingerprint. Like `uv`
and `lean`, it supports the openSUSE and Arch Linux families too. What is the same is named, not repeated. The interface
was agreed with the maintainer in conversation before this change and is recorded in issue #200: one option, `version`;
no `containerEnv`, volume, plugin cache, `terraform` alias, or shell completion; the official VS Code extension; all six
distribution families of the `uv` design.

Upstream facts this change relies on, checked on 2026-11-13 against `github.com/opentofu/opentofu` (release API, all
pages), `get.opentofu.org`, and `opentofu.org/docs/v1.13/intro/install/`. Verification, package, and run checks ran in
throwaway containers, on amd64:

- The newest release GitHub marks as latest is `v1.13.9` (2026-11-05);
  `https://github.com/opentofu/opentofu/releases/latest` answers `302` to `.../releases/tag/v1.13.9`. Upstream maintains
  more than one line at a time: `v1.12.12` was published the same day, 23 seconds earlier. Pre-releases use tags such as
  `v1.13.0-alpha1`, `v1.13.0-beta1`, and `v1.13.0-rc1`.
- There are 75 stable releases from `v1.6.0` (2024-01-10) to `v1.13.9`, all plain `vMAJOR.MINOR.PATCH` tags. From
  `v1.6.3` on, every one of the 72 publishes `tofu_<version>_linux_amd64.tar.gz` and
  `tofu_<version>_linux_arm64.tar.gz`, `tofu_<version>_SHA256SUMS`, and `tofu_<version>_SHA256SUMS.gpgsig`. `v1.6.0` to
  `v1.6.2` publish the same files except the `.tar.gz` archives: their Linux archives are zip only.
- `tofu_<version>_SHA256SUMS` is plain `sha256sum` output for every file of the release. The `.gpgsig` file is a binary
  detached OpenPGP signature over the whole list. Releases also carry cosign signatures (`.sig` and `.pem`) for keyless
  verification against the identity
  `https://github.com/opentofu/opentofu/.github/workflows/release.yml@refs/heads/v<MAJOR>.<MINOR>`.
- `https://get.opentofu.org/opentofu.asc` answers `200` without a redirect and holds one RSA-4096 primary key with one
  encryption subkey. The primary key was created 2023-11-15, has no expiry, carries the user ID "OpenTofu (This key is
  used to sign opentofu providers) <core@opentofu.org>", and has the fingerprint
  `E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80`. Upstream's standalone installer (`opentofu/get.opentofu.org`,
  `static/install-opentofu.sh`) pins this fingerprint as its default, and so does `opentofu/tofudl`
  (`branding/branding.go`); the installation guide does not print it.
- For all 72 releases from `v1.6.3` to `v1.13.9`, GnuPG reported a good signature of the list whose primary key
  fingerprint is the one above, and the list held exactly one entry each for the linux `amd64` and `arm64` `.tar.gz`
  archives.
- Every `.../releases/download/v<version>/<file>` URL answers `302` to
  `https://release-assets.githubusercontent.com/...` with a short-lived signed query string. A missing release answers
  `404`.
- The archive holds `CHANGELOG.md`, `LICENSE`, `README.md`, and `tofu` (about 110 MB unpacked for `v1.13.9`). The
  `arm64` `tofu` of `v1.6.3` and the `amd64` `tofu` of `v1.13.9` are static ELF executables (no `PT_INTERP`), and the
  `amd64` `tofu` of both releases runs on Alpine 3.24.
- `tofu version` prints `OpenTofu v<version>` and then `on linux_<arch>`, for `v1.6.3` and `v1.13.9`, with no network.
  Each run creates an empty `~/.terraform.d` in `HOME`. With no network, `tofu init`, `tofu apply -auto-approve`, and
  `tofu output -raw` succeed on a configuration holding only a constant output, leaving `terraform.tfstate` in the
  working directory.
- Tools present before any install: the Ubuntu base image, `fedora:44`, `almalinux:9`, `opensuse/leap:16.0`, and
  `archlinux:latest` have `curl`, `gpg`, `tar`, and `gzip`. `debian:12` has `tar` and `gzip` but neither `curl` nor
  `gpg` (only `gpgv`). `alpine:3.24` has BusyBox `tar` and `gzip` but neither `curl` nor `gpg`.
- After installing the missing packages (`gpg` on Debian and Alpine, `gnupg2` on Fedora and AlmaLinux, `gpg2` on
  openSUSE, `gnupg` on Arch Linux), `gpg --dearmor` of the key and `gpg --verify` of the `v1.13.9` list against the
  resulting keyring file succeeded with GnuPG 2.2.40 (Debian 12), 2.3.3 (AlmaLinux 9), 2.4.4 (Ubuntu 24.04), 2.4.9
  (Fedora 44, Alpine 3.24, Arch Linux), and 2.5.5 (openSUSE Leap 16.0). Debian's and Alpine's minimal `gpg` packages
  have no `gpg-agent`; verifying against a keyring file needs none.
- Upstream's VS Code extension is `opentofu.vscode-opentofu` ("OpenTofu (official)", `opentofu/vscode-opentofu`). It
  bundles its language server and runs `tofu` from `PATH` for formatting.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- HTTPS on every hop: every request goes through `curl --proto '=https' --proto-redir '=https'` and requests only the
  URLs in the URL inventory below; redirects are followed only for the release downloads, which GitHub serves from its
  asset host. Package-manager requests go to the image's configured repositories. Checked by reviewing each `curl` call
  against the inventory, and by the fixture scenario, whose `curl` stand-in records each request's arguments and asserts
  the protocol flags.
- Validate before any change: the option's form, the minimum version, the architecture, the distribution, its package
  manager, and `/usr/local/bin/tofu` being absent or a regular file are all checked before any package is installed or
  anything is downloaded. Checked by the fixture scenario, which asserts after each rejected run that no package was
  added and no request was made.
- Verify before use: nothing from the archive is extracted or run before the list's signature is verified, the signer's
  primary fingerprint matches the pinned one, and the archive's digest matches its single entry in the list. Every
  keyring the install uses lives in the install's temporary directory. Checked by the fixture scenario (Tests).
- Stage, then rename: the new binary is copied next to the target under a temporary name and renamed over it, on the
  same filesystem. A failure before the rename leaves the earlier binary as it was. Checked by the failed-replacement
  cases of the fixture scenario and by `duplicate.sh`.
- The build-time `tofu version` run that reads the installed version uses a `HOME` inside the temporary directory, since
  each run creates `~/.terraform.d` (Context), so it writes nothing to a real home. Checked by the "Nothing configured
  after install" scenario in `test.sh`, before `test.sh` runs `tofu` itself.
- Package installs only for missing tools, the cache cleanup, the temporary directory and staged file under one `trap`,
  and the skip check on the parsed first line of `tofu version`: as in the `gitleaks` design, checked the same way. The
  directories are `${TMPDIR:-/tmp}/opentofu-feature.XXXXXX` and, beside the target, `.opentofu-feature.XXXXXX`.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream also builds 386 and ARM, but CI has runners only for these two.
- Releases before `1.6.3`, pre-releases, and a selector for the newest patch of a `MAJOR.MINOR` line (issue's Out of
  scope; Decisions, Option interface).
- A `terraform` command, shell completion, a provider plugin cache, and any `TF_*` or `TOFU_*` variable (the spec's "No
  OpenTofu configuration"; Decisions, Nothing configured).
- Installing git: `tofu` needs it only for `git::` module sources, and `NOTES.md` says so.
- Removing a `tofu` that the image's package manager installed at `/usr/bin/tofu`; `/usr/local/bin` comes first on the
  default `PATH`, so the feature's binary wins.

## Decisions

### Option interface

| Name      | Type     | Default    | Enum or proposals                | Meaning                                                                                                   |
| --------- | -------- | ---------- | -------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","1.12.12"]` | The release to install: `latest`, or a release version at or above `1.6.3`, with or without a leading `v` |

- **`version` default `latest`.** Most users want the release upstream currently recommends; a project that needs
  reproducible builds pins `version`. The second proposal, `1.12.12`, is the newest release of the previous maintained
  line and older than `latest`, so the duplicate test's first install is replaced by the second. Rejected: the minimum
  `1.6.3` as the proposal — a scenario covers the minimum, and a release of an unmaintained line is a poor suggestion in
  the generated README; the current release — it equals what `latest` resolves to, so the replace path would never run
  in CI.
- **Rejected shapes.** A `MAJOR.MINOR` value that selects the newest patch of a line — useful because upstream maintains
  several lines, but it needs the full release list from the GitHub API and its own validation; it can come later as a
  MINOR without changing `version`'s current values. A `terraformAlias` boolean, a completion option, or a plugin cache
  option — agreed against in conversation (Nothing configured). A switch to skip verification — the collection never
  weakens a check.

### Release source

Download the `.tar.gz` archive, `SHA256SUMS`, and `SHA256SUMS.gpgsig` from
`https://github.com/opentofu/opentofu/releases/download/v<version>/`, and the key from
`https://get.opentofu.org/opentofu.asc`. These are the files upstream's standalone installer and installation guide use,
and they are the same on every distribution.

Rejected: upstream's `install-opentofu.sh` — 1362 lines that do what this feature does, with no signature of its own,
and it would still need its options pinned to verify. The deb and rpm repositories at `packages.opentofu.org` — two
signing keys per family to pin, a different pinning syntax per package manager, and none for Alpine, whose package is
only in `edge/community`, a repository a stable image should not mix in. Upstream's `.deb`, `.rpm`, and `.apk` files —
the `.tar.gz` is needed for openSUSE and Arch Linux anyway, so they would only add paths. The zip archives — they need
`unzip` and gain only `1.6.0` to `1.6.2`. Snap, Homebrew, and the `ghcr.io/opentofu/opentofu` image — no snapd or
Homebrew in a container, and the image is meant to be copied from in a Dockerfile, not installed by a feature.

### Following redirects over HTTPS only

The release downloads redirect to GitHub's asset host with a signed query string (Context), so they are followed, with
`--proto-redir '=https'` refusing any non-HTTPS hop, as in the `gitleaks` design. Each final URL is logged without its
query string, so a host change shows in the build log. The latest-release link is read without following it, and the key
URL does not redirect. Rejected: refusing redirects as in the `rclone` design — GitHub's asset host is part of how
upstream publishes, and the signature check, not the host, establishes authenticity.

### Signature verification

Fetch the key and the list's signature into the temporary directory, turn the key into a keyring file with
`gpg --dearmor` in a GnuPG home there, and run `gpg --verify` on the signature and the list with
`--no-default-keyring --keyring` naming that file and status output. It must exit 0, report no `BADSIG`, `ERRSIG`,
`EXPSIG`, `EXPKEYSIG`, or `REVKEYSIG`, and report at least one `VALIDSIG`. The last field of every `VALIDSIG` (the
primary key fingerprint) must equal `E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80`, a constant in `install.sh`. Only then is
the list searched for the archive's entry, which must occur exactly once, as `<64 hex digits>  <archive name>`.

- The signature is detached and covers the whole list, so unlike the `rclone` design there is no unsigned text to keep
  out of the lookup.
- Checking the actual signer's primary fingerprint, not the key file's content, means a key file holding extra keys
  cannot widen what is accepted, so the key file's key count is not checked.
- Importing the key instead would start `gpg-agent`, which Debian's and Alpine's minimal `gpg` packages lack (Context).

Rejected: cosign keyless verification — no image has `cosign`, and installing it would need its own verified download
for one check that GnuPG already provides with a signature upstream publishes for the same file. The checksum list alone
— upstream signs it, and feature-authoring.md requires the signature then. Shipping the public key inside the feature —
key rotation would then need a feature release even when upstream publishes the new key in the documented place;
fetching it and pinning the fingerprint is what `rclone` and `claude-code` do. `gpgv` — it needs a binary keyring, which
takes `gpg --dearmor` anyway. GitHub's asset digest — computed by the platform from the same upload, so it adds nothing
to the signature.

### Resolving latest

Read the redirect of `https://github.com/opentofu/opentofu/releases/latest` without following it, and take the tag from
the last path segment, as in the `gitleaks` design. The tag must pass the same validation as an explicit `version`, so a
pre-release tag fails. Rejected: `https://api.github.com/repos/opentofu/opentofu/releases/latest`, which upstream's
installer reads — the same answer as JSON, under the API's unauthenticated rate limit, which CI runners share.
`https://get.opentofu.org/tofu/api.json` — an undocumented format that needs a JSON parser in the image. The highest
version among all tags — it needs the full release list and would ignore which line upstream marks as current.

### Minimum version `1.6.3`

The first release with `.tar.gz` archives; all 72 releases from `1.6.3` to `1.13.9` carry a list signed by the pinned
key with both archives listed (Context). Rejected: `1.6.0` — a zip path and an `unzip` prerequisite for three releases
of a line upstream no longer maintains. A later floor — no technical reason, and a user who pins an old release knows
why.

### Nothing configured

- **No plugin cache.** Providers are downloaded into the project's `.terraform/`, which lives in the workspace and
  survives a rebuild. A shared cache helps only across root modules, and on a volume it would need the ownership
  handling of the `lean` design. `NOTES.md` shows the `TF_PLUGIN_CACHE_DIR` setting a user can add.
- **No `terraform` command.** It would collide with a real Terraform installed by another feature, and
  `terraform version` would report OpenTofu.
- **No shell completion.** `tofu -install-autocomplete` edits each user's shell startup files, and a file in
  `/etc/bash_completion.d` is read only where bash-completion is installed. `NOTES.md` names the command for users who
  want it.

### Prerequisites

Install only the missing tools, from the image's repositories, in one transaction, and leave them installed, as in the
`gitleaks` design. Families are matched by `ID` or `ID_LIKE` as in the `uv` design.

| Family            | Packages                                                                      |
| ----------------- | ----------------------------------------------------------------------------- |
| Debian and Ubuntu | `curl` `ca-certificates` `gpg` `tar` `gzip`                                   |
| Fedora and RHEL   | `curl` `ca-certificates` `gnupg2` `tar` `gzip`                                |
| Alpine            | `curl` `ca-certificates` `gpg` `tar` `gzip`                                   |
| openSUSE and SUSE | `curl` `ca-certificates-mozilla` `gpg2` `tar` `gzip`                          |
| Arch Linux        | `curl` `ca-certificates` `gnupg` `tar` `gzip`, through `pacman -Syu --needed` |

A tool counts as present when its command is on `PATH`; BusyBox's `tar` and `gzip` on Alpine are enough. Caches are
cleaned as in the `uv` design. Rejected: removing the tools afterwards — the feature cannot tell which ones another
layer also needs.

### Editor

`customizations.vscode.extensions` requests `opentofu.vscode-opentofu` and no settings. `NOTES.md` shows
`-opentofu.vscode-opentofu` for users who do not want it.

### Tests

- `test.sh`, on every compatibility image as its remote user, checks in this order:
  1. "Nothing configured after install", before running `tofu`.
  2. The first line of `tofu version` against the latest-release link read at test time.
  3. "Configuration without providers", in a temporary directory.
  4. The package-manager caches.
- `duplicate.sh` installs `1.12.12`, then the defaults. It asserts the latest release and one `tofu` in
  `/usr/local/bin`.
- Scenarios, with `scenarioArchitectures` `["amd64","arm64"]`:
  - `test_version_floor` — `alpine:3.24`, `version` `v1.6.3`: a leading `v`, the minimum, BusyBox `tar`, and musl.
  - `test_version_explicit` — `opensuse/leap:16.0`, `version` `1.12.12`.
  - `fail_contract` — `debian:12`, defaults. Its script moves the build's binary aside, restores it at the end, and runs
    `install.sh` with a `curl` stand-in. The stand-in serves fixtures: the real key, and the real list, signature, and
    archive of `1.6.3`, fetched at the start, plus files the script derives from them. It asserts every rejection and
    verification failure the spec lists that a successful build cannot show, each leaving the target, packages, and the
    temporary directory as they were:
    - a malformed, pre-release, or below-minimum `version`;
    - a latest-release link to a pre-release tag;
    - a missing release, a list without the architecture's entry, and a missing signature file;
    - an unreachable key;
    - a list altered by one byte;
    - a list signed by a key the script generates, with that key appended to the key file;
    - an archive that differs from its entry;
    - an architecture stand-in for `uname`, an edited and a removed `/etc/os-release`, and a hidden `apt-get`;
    - a directory at `/usr/local/bin/tofu`.

    It also asserts the success cases that need fixtures: the same version twice (no archive request; inode and
    modification time unchanged), and an unreadable installed version (a stand-in that exits 1 is replaced).
- Checked by review only: more than one entry for the archive in the list, which no fixture can produce without the
  pinned key, and the redirect to a non-HTTPS URL, which the stand-in covers only by asserting `--proto-redir '=https'`
  on every request. The entry count and the `curl` calls in `install.sh` are read against the spec.
- Checked by hand, once: the package-manager branch of the families whose listed images lack no prerequisite. On
  `fedora:44`, `almalinux:9`, `opensuse/leap:16.0`, and `archlinux:latest`, `tar` is removed without its dependents
  (`rpm -e --nodeps`, `pacman -Rdd`), `install.sh` runs, and the PR records that it installed `tar` and left the cache
  clean.

## Security review

- **Downloads:** for one version and architecture, the latest-release link (only for `latest`), the key, the list, its
  signature, and the archive. All over HTTPS on every hop, from `github.com` with GitHub's asset host and from
  `get.opentofu.org` (URL inventory). Nothing is piped to a shell.
- **Verification:** OpenPGP signature of the list by the pinned key, then SHA-256 of the archive against its single
  entry. This detects a tampered archive, list, or key, and a compromised download host. It does not detect a compromise
  of upstream's signing key.
- **Keys:** one fingerprint pinned in `install.sh`; the key is fetched at build time and used only as a keyring file in
  a temporary GnuPG home. A rotation fails the install until the feature follows it (Risks).
- **Metadata:** one VS Code extension; no `containerEnv`, `dependsOn`, `installsAfter`, `mounts`, `capAdd`,
  `privileged`, `securityOpt`, `init`, `entrypoint`, or lifecycle command. The feature never widens what the container
  may do.
- **Build-time execution:** the verified binary runs as root only to report its version, with `HOME` in the temporary
  directory (Goals).
- **Files written as root:** `/usr/local/bin/tofu`, replaced by rename. A non-regular file there fails the install
  instead of being followed. Nothing is written in a home directory.
- **Options:** `version`, validated before use; no credential, backend, or path option, by design.
- **Idempotency and failure behavior:** the spec's "Installing twice" and failure scenarios, reached through the skip
  check, the target check, and staging (Goals), and tested as described under Tests. Every failure exits non-zero, which
  fails the image build.

## Supported images

The planned `test/opentofu/compatibility.json`, with `"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base
entry also sets `"remoteUser": "vscode"`:

| Image                                              | Architectures | Why                                                                                    |
| -------------------------------------------------- | ------------- | -------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64  | The usual dev container base; `apt-get` path with a non-root user                      |
| `debian:12`                                        | amd64, arm64  | Minimal `apt-get` image; the feature installs `curl` and `gpg`, and GnuPG 2.2 verifies |
| `fedora:44`                                        | amd64, arm64  | `dnf` path                                                                             |
| `almalinux:9`                                      | amd64, arm64  | RHEL matched through `ID_LIKE`; GnuPG 2.3                                              |
| `alpine:3.24`                                      | amd64, arm64  | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash                |
| `opensuse/leap:16.0`                               | amd64, arm64  | `zypper` path; SUSE matched through `ID_LIKE`; GnuPG 2.5                               |
| `archlinux:latest`                                 | amd64         | `pacman` path; upstream publishes no arm64 image                                       |

Every tag is already listed by other features of the collection for the same architectures.

## URL inventory

Every URL the feature's scripts access, all fetched at build time by `install.sh`; nothing is fetched at container
start. The feature configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `amd64` or `arm64`; `<base>` is `https://github.com/opentofu/opentofu/releases/download/v<version>`.

| URL                                                    | Purpose                | When                                                   | Verification                                           | Evidence (2026-11-13)                                        |
| ------------------------------------------------------ | ---------------------- | ------------------------------------------------------ | ------------------------------------------------------ | ------------------------------------------------------------ |
| `https://github.com/opentofu/opentofu/releases/latest` | Resolve `latest`       | Build, only for `latest`; also read by `test.sh`       | TLS; the redirect's tag must pass version validation   | `302` to `.../releases/tag/v1.13.9`, not followed            |
| `https://get.opentofu.org/opentofu.asc`                | Upstream's public key  | Build, unless the requested release is already present | TLS; only the pinned fingerprint is accepted as signer | `200`, no redirect, one primary key (Context)                |
| `<base>/tofu_<version>_SHA256SUMS`                     | Checksum list          | Build, unless the requested release is already present | OpenPGP signature by the pinned key                    | `302` to the asset host; signed and complete for 72 releases |
| `<base>/tofu_<version>_SHA256SUMS.gpgsig`              | Detached signature     | Build, unless the requested release is already present | Is the verification                                    | `302` to the asset host                                      |
| `<base>/tofu_<version>_linux_<arch>.tar.gz`            | Archive holding `tofu` | Build, unless the requested release is already present | SHA-256 against its single entry in the list           | `302` to the asset host                                      |

The asset host is `https://release-assets.githubusercontent.com`, reached only through GitHub's redirects. At run time
`tofu` contacts whatever registries, providers, and backends the user's configuration names; the feature itself requests
nothing.

## Risks / Trade-offs

- [Upstream rotates the release key] → Every install fails "verification failed" until a feature change pins the new
  fingerprint, which the spec names. Failing is the intended behavior.
- [Upstream marks a release of an older line as latest, for example a patch published after the newer line's] → `latest`
  installs that release; it is still signed and at or above the minimum. Users who need a line pin `version`; `NOTES.md`
  says how `latest` is chosen.
- [A tampered latest-release redirect selects another signed release] → Accepted in the spec. Users who need a specific
  release pin `version`.
- [GitHub moves its asset host] → Redirects are followed over HTTPS only, and the signature check does not depend on the
  host, so the install keeps working; the build log shows the new host.
- [A release is published between a CI job's build and its test] → That job's comparison with the latest-release link
  fails; a re-run passes.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [On Arch Linux, a missing prerequisite upgrades the whole image] → Stated in the spec; `archlinux:latest` lacks no
  prerequisite, so it happens only on a trimmed image.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.
- [The binary adds about 110 MB to the image] → Inherent to the tool; no option can shrink it.
