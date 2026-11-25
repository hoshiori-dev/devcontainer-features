# Design

## Context

See proposal.md - Why. The feature follows the `opentofu` feature (archived change `2026-11-13-add-opentofu-feature`): a
static Go binary from upstream's release archives, verified by the checksum list's OpenPGP signature against a key
pinned by fingerprint, installed atomically to `/usr/local/bin`, with prerequisites from the image's own repositories,
on the same six distribution families. What is the same is named, not repeated. What differs: the release host is
upstream's own (`releases.hashicorp.com`) and answers without redirects, the archive is a zip, `latest` comes from
HashiCorp's Checkpoint service, and nothing is requested from an editor. The interface was agreed with the maintainer in
conversation before this change and is recorded in issue #213: one option, `version`, with `1.7.0` as the minimum; no
plugin installation, editor extension, `containerEnv`, mount, or shell completion.

Upstream facts this change relies on, checked on 2026-11-25 against `releases.hashicorp.com` (the release index and
every release from `1.7.0`), `checkpoint-api.hashicorp.com`, `www.hashicorp.com`, and upstream's verification guide
(`developer.hashicorp.com/well-architected-framework/verify-hashicorp-binary`). Verification, package, and run checks
ran in throwaway containers, on amd64:

- `https://releases.hashicorp.com/packer/index.json` lists 141 versions: 136 stable ones from `0.1.0` to `1.16.2`, all
  plain `MAJOR.MINOR.PATCH`, and five pre-releases (`1.9.0-alpha`, `1.11.0-alpha`, `1.11.0-alpha2`, `1.11.0-beta`,
  `1.12.0-alpha1`). 47 stable releases are at or above `1.7.0`; the newest of the previous line is `1.15.4`.
- Each of those 47 publishes `packer_<version>_linux_amd64.zip`, `packer_<version>_linux_arm64.zip`,
  `packer_<version>_SHA256SUMS`, and two signature files, `packer_<version>_SHA256SUMS.sig` and
  `packer_<version>_SHA256SUMS.72D7468F.sig`, which are byte-identical for all 47. Older releases, `1.7.0` among them,
  also carry a `.348FFC4C.sig` by upstream's earlier key, which upstream replaced in 2021.
- The list is plain `sha256sum` output, one line per file of the release (19 for `1.16.2`). The signature is a binary
  detached OpenPGP signature over the whole list.
- `https://www.hashicorp.com/.well-known/pgp-key.txt` answers `200` without a redirect and holds one RSA-4096 primary
  key, user ID "HashiCorp Security (hashicorp.com/security) <security@hashicorp.com>", created 2021-04-19, expiring
  2030-03-01, fingerprint `C874011F0AB405110D02105534365D9472D7468F`, with one encryption subkey, one signing subkey
  that expired in 2022, and one current signing subkey (`374EC75B485913604A831CC7C820C6D5CD27AB87`). Upstream's
  verification guide prints the primary fingerprint and uses this URL and the `.sig` file.
- For all 47 releases, GnuPG reported a good signature of the list whose `VALIDSIG` primary fingerprint is the one
  above, and the list held exactly one entry each for the linux `amd64` and `arm64` archives. GnuPG's status output also
  carries `KEYEXPIRED` lines for the expired subkey; they do not concern the signature.
- Every release URL and the key URL answer `200` directly; a missing release answers `404`. HTML pages on
  `www.hashicorp.com` answered `429` to a script, while the key file answered `200` on every request.
- `https://checkpoint-api.hashicorp.com/v1/check/packer` answers `200`, `application/json`, without a redirect: one line
  of about 300 bytes holding `"current_version":"1.16.2"` once. An unknown product answers `500`.
- The archive of `1.7.0` holds only `packer` (about 129 MB unpacked, 30 MB zipped); the archive of `1.16.2` holds
  `LICENSE.txt` and `packer` (about 104 MB unpacked, 31 MB zipped). The amd64 and arm64 `packer` of both releases are
  static ELF executables (no `PT_INTERP`), and the amd64 ones run on Alpine 3.24.
- `packer version` prints `Packer v<version>` as its first line, for `1.7.0` and `1.16.2`. With network access, an
  outdated release then prints a blank line and an update notice, after asking the Checkpoint service; with
  `CHECKPOINT_DISABLE=1` it asks nothing. Every run, with or without that variable, writes a `checkpoint_signature` file
  under `HOME` (`~/.packer.d` for `1.7.0`, `~/.config/packer` for `1.16.2`, which also creates `~/.cache`).
- With no network, `packer validate` and `packer build` exit 0, for `1.7.0` and `1.16.2`, on a template holding a `null`
  source with `communicator = "none"` and a `shell-local` provisioner that writes a file; both components are built in.
- Tools present before any install:

  | Image                                              | `curl` | `gpg` | `unzip`       | Other `packer`                      |
  | -------------------------------------------------- | ------ | ----- | ------------- | ----------------------------------- |
  | `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | yes    | yes   | yes           | none                                |
  | `debian:12`                                        | no     | no    | no            | none                                |
  | `fedora:44`                                        | yes    | yes   | no            | none                                |
  | `almalinux:9`                                      | yes    | yes   | no            | `/usr/sbin/packer`, cracklib's link |
  | `alpine:3.24`                                      | no     | no    | yes (BusyBox) | none                                |
  | `opensuse/leap:16.0`                               | yes    | yes   | no            | none                                |
  | `archlinux:latest`                                 | yes    | yes   | no            | none                                |

  On every image the default `PATH` is `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, so
  `/usr/local/bin` comes before `/usr/sbin`.
- The package `unzip` exists under that name in every family; after installing it, `unzip` extracted `packer` from the
  `1.16.2` archive on `debian:12`, `fedora:44`, `almalinux:9`, `opensuse/leap:16.0`, and `archlinux:latest`, and
  BusyBox's `unzip` did on `alpine:3.24`. GnuPG's package names and versions per family are those of the `opentofu`
  design.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- HTTPS and no redirects: every request goes through `curl --proto '=https'` without `--location`, and requests only the
  URLs in the URL inventory below, each of which answers directly (Context). Package-manager requests go to the image's
  configured repositories. Checked by reviewing each `curl` call against the inventory, and by the fixture scenario,
  whose `curl` stand-in records each request's arguments and asserts the protocol flag and the absence of a
  redirect-following flag.
- Validate before any change: the option's form, the minimum version, the architecture, the distribution, its package
  manager, and `/usr/local/bin/packer` being absent or a regular file are all checked before any package is installed or
  anything is downloaded. Checked by the fixture scenario, which asserts after each rejected run that no package was
  added and no request was made.
- Verify before use: nothing from the archive is extracted or run before the list's signature is verified, the signer's
  primary fingerprint matches the pinned one, and the archive's digest matches its single entry in the list. Every
  keyring the install uses lives in the install's temporary directory. Checked by the fixture scenario (Tests).
- Only the member `packer` is extracted from the archive, into the temporary directory. Checked by the fixture scenario
  with the `1.16.2`-shaped archive that also holds `LICENSE.txt`, and by the duplicate test's file count in
  `/usr/local/bin`.
- Stage, then rename: the new binary is copied next to the target under a temporary name and renamed over it, on the
  same filesystem. A failure before the rename leaves the earlier binary as it was. Checked by the failed-replacement
  cases of the fixture scenario and by `duplicate.sh`.
- The build-time `packer version` run that reads the installed version uses a `HOME` inside the temporary directory and
  `CHECKPOINT_DISABLE=1`, since every run writes under `HOME` and an outdated release otherwise asks the Checkpoint
  service (Context); only its first line is read. Checked by the "Nothing configured after install" scenario in
  `test.sh`, before `test.sh` runs `packer` itself, and by the fixture scenario's request record.
- Package installs only for missing tools, the cache cleanup, the temporary directory and staged file under one `trap`:
  as in the `opentofu` design, checked the same way. The directories are `${TMPDIR:-/tmp}/packer-feature.XXXXXX` and,
  beside the target, `.packer-feature.XXXXXX`.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream also builds 386, ARM, and ppc64le, but CI has runners only for
  these two.
- Releases before `1.7.0`, pre-releases, and a selector for the newest patch of a `MAJOR.MINOR` line (issue's Out of
  scope; Decisions, Option interface).
- Plugins, a plugin or download cache, shell completion, an editor extension, and any `PACKER_*` or `CHECKPOINT_*`
  variable (the spec's "No Packer plugins or configuration"; Decisions, Nothing configured).
- Removing or renaming cracklib's `/usr/sbin/packer` on RHEL-family images; `/usr/local/bin` comes first on the default
  `PATH`, so the feature's binary wins, and `NOTES.md` names the case where it does not.
- The tools a builder needs at run time (QEMU, Docker, a cloud CLI, `xorriso` for ISO builders): each belongs to its own
  feature or to the user's image.

## Decisions

### Option interface

| Name      | Type     | Default    | Enum or proposals               | Meaning                                                                                                   |
| --------- | -------- | ---------- | ------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","1.15.4"]` | The release to install: `latest`, or a release version at or above `1.7.0`, with or without a leading `v` |

- **`version` default `latest`.** Most users want the current release; a project that needs reproducible builds pins
  `version`. The second proposal, `1.15.4`, is the newest release of the previous line and older than `latest`, so the
  duplicate test's first install is replaced by the second. Rejected: the minimum `1.7.0` as the proposal — a scenario
  covers the minimum, and a release from 2021 is a poor suggestion in the generated README; the current release — it
  equals what `latest` resolves to, so the replace path would never run in CI.
- **Rejected shapes.** A `MAJOR.MINOR` value that selects the newest patch of a line — it needs the release index and
  its own ordering; it can come later as a MINOR without changing `version`'s current values. A `plugins` option —
  agreed against in conversation (Nothing configured). A switch to skip verification — the collection never weakens a
  check.

### Release source

Download the zip archive, `SHA256SUMS`, and `SHA256SUMS.sig` from `https://releases.hashicorp.com/packer/<version>/`,
and the key from `https://www.hashicorp.com/.well-known/pgp-key.txt`. These are the files upstream's verification guide
uses, and they are the same on every distribution.

Rejected: the deb and rpm repositories at `apt.releases.hashicorp.com` and `rpm.releases.hashicorp.com` — a repository
and its key to pin per family with a different pinning syntax per package manager, none for Alpine, openSUSE, or Arch
Linux, and a repository that stays configured in the user's image. The distributions' own packages — Arch Linux packages
Packer in `extra`, Alpine 3.24 does not, and a distribution's package follows its own version. The `hashicorp/packer`
container image — meant to be run or copied from in a Dockerfile, not installed by a feature. GitHub's source archives —
they hold no binary.

### Signature file

Use `packer_<version>_SHA256SUMS.sig`, the file upstream's guide verifies. Rejected: the key-named
`packer_<version>_SHA256SUMS.72D7468F.sig` — identical today (Context), but after a key rotation it would keep verifying
against the replaced key for as long as upstream publishes it, which is the wrong outcome when a key is replaced because
it was exposed, as in 2021. With `.sig`, a rotation fails every install until a feature change pins the new fingerprint
(Risks).

### No redirects

No URL of the inventory redirects (Context), so `curl` runs without `--location` and a redirect answer fails the
install, as in the `rclone` design. Rejected: following redirects over HTTPS as in the `opentofu` design — that design
needs it for GitHub's asset host; here it would only widen the set of hosts a tampered answer could reach.

### Signature verification

As in the `opentofu` design: the key becomes a keyring file through `gpg --dearmor` in a GnuPG home inside the temporary
directory, `gpg --verify` runs with `--no-default-keyring --keyring` and status output, it must exit 0 with no `BADSIG`,
`ERRSIG`, `EXPSIG`, `EXPKEYSIG`, or `REVKEYSIG` and at least one `VALIDSIG`, and the last field of every `VALIDSIG` must
equal `C874011F0AB405110D02105534365D9472D7468F`, a constant in `install.sh`. Only then is the list searched for the
archive's entry, which must occur exactly once, as `<64 hex digits>  <archive name>`.

- Upstream signs with a subkey, so the fingerprint compared is the primary key's, the last `VALIDSIG` field, not the
  signing subkey's first field. A new signing subkey under the same primary key keeps working without a feature change.
- `KEYEXPIRED` is not a failure: the key file carries an expired earlier subkey, and GnuPG reports it on every run
  (Context). A signature made by an expired key is reported as `EXPKEYSIG`, which is a failure.

Rejected: the checksum list alone — upstream signs it, and feature-authoring.md requires the signature then. Shipping
the public key inside the feature — a new signing subkey would then need a feature release. `gpgv` — it needs a binary
keyring, which takes `gpg --dearmor` anyway.

### Resolving latest

Read `https://checkpoint-api.hashicorp.com/v1/check/packer` and take the value of `current_version`. The answer must
hold the text `"current_version":"` exactly once; the value is what follows up to the next `"`, and it must pass the
same validation as an explicit `version`, so a pre-release, an empty value, or anything else fails with the received
value in the message. This needs no JSON parser: the validation, not the extraction, decides what is accepted.

Rejected: `https://releases.hashicorp.com/packer/index.json` — about 450 kB listing every build of 141 versions, with
pre-releases to filter and versions to order in POSIX shell.
`https://api.releases.hashicorp.com/v1/releases/packer/latest` — the same answer inside a 3 kB JSON document that lists
every build; Checkpoint is the service Packer itself asks for its current version. GitHub's latest-release link of
`hashicorp/packer` — GitHub is not where upstream publishes the binaries, so its marker may differ from the release
host's state. Installing `jq` — a prerequisite for one field.

### Minimum version `1.7.0`

The first release with `packer init` and `required_plugins`, which is how plugins are installed today; all 47 releases
from `1.7.0` to `1.16.2` carry a list signed by the pinned key with both archives listed (Context). Rejected: no minimum
— older releases are signed too, but the oldest have no arm64 archive, and each would need checking. `1.10.0`, the first
under the Business Source License — the license is the user's concern, not a technical bound. `1.11.0`, the first
without bundled plugins — it would exclude releases that work.

### Nothing configured

- **No plugins.** Since `1.11.0` Packer bundles almost no plugins; `packer init` downloads those a template requires
  into the user's home. Installing them at build time would write under a home directory and fetch third-party code from
  GitHub that the feature cannot verify beyond Packer's own checks. `NOTES.md` shows `packer init` as a
  `postCreateCommand`.
- **No mount or cache.** Packer keeps plugins under `~/.config/packer/plugins` (`PACKER_PLUGIN_PATH`) and downloaded
  ISOs under `~/.cache/packer` (`PACKER_CACHE_DIR`); both are lost on a rebuild and fetched again, which costs time but
  nothing else. A mount in the feature's metadata cannot be switched off by an option, cannot name the remote user's
  home, and on a volume would need the ownership handling of the `lean` design; only ISO builders gain much. `NOTES.md`
  shows how a user points both variables at a directory in the workspace.
- **No editor extension.** Upstream publishes no Packer extension; `hashicorp.hcl` is generic HCL syntax support, and
  Packer-specific extensions are third-party.
- **No shell completion.** `packer -autocomplete-install` edits each user's shell startup files. `NOTES.md` names the
  command for users who want it.
- **No `CHECKPOINT_DISABLE`.** Packer asks the Checkpoint service on its runs (Context). Setting the variable for every
  user would change upstream's default behind an ordinary-looking install; `NOTES.md` shows the `containerEnv` line.

### Prerequisites

Install only the missing tools, from the image's repositories, in one transaction, and leave them installed, as in the
`opentofu` design. Families are matched by `ID` or `ID_LIKE` as in that design.

| Family            | Packages                                                                 |
| ----------------- | ------------------------------------------------------------------------ |
| Debian and Ubuntu | `curl` `ca-certificates` `gpg` `unzip`                                   |
| Fedora and RHEL   | `curl` `ca-certificates` `gnupg2` `unzip`                                |
| Alpine            | `curl` `ca-certificates` `gpg` `unzip`                                   |
| openSUSE and SUSE | `curl` `ca-certificates-mozilla` `gpg2` `unzip`                          |
| Arch Linux        | `curl` `ca-certificates` `gnupg` `unzip`, through `pacman -Syu --needed` |

A tool counts as present when its command is on `PATH`; BusyBox's `unzip` on Alpine is enough, so `unzip` is not
installed there. Caches are cleaned as in the `opentofu` design. Rejected: extracting with `python3` or `bsdtar` —
neither is on every image either. Removing the tools afterwards — the feature cannot tell which ones another layer also
needs.

### Tests

- `test.sh`, on every compatibility image as its remote user, checks in this order:
  1. "Nothing configured after install", before running `packer`.
  2. `command -v packer`, and the first line of `packer version` against the Checkpoint answer read at test time.
  3. "Template with built-in components", in a temporary directory.
  4. The package-manager caches.

  On `almalinux:9` the second check is also the "Image with another packer command" scenario, and `test.sh` asserts
  there that `/usr/sbin/packer` is still cracklib's link.
- `duplicate.sh` installs `1.15.4`, then the defaults. It asserts the current release and one `packer` in
  `/usr/local/bin`.
- Scenarios, with `scenarioArchitectures` `["amd64","arm64"]`:
  - `test_version_floor` — `alpine:3.24`, `version` `v1.7.0`: a leading `v`, the minimum, BusyBox `unzip`, and musl.
  - `test_version_explicit` — `opensuse/leap:16.0`, `version` `1.15.4`.
  - `fail_contract` — `debian:12`, defaults. Its script moves the build's binary aside, restores it at the end, and runs
    `install.sh` with a `curl` stand-in. The stand-in serves fixtures: the real key, and the real list, signature, and
    archive of `1.7.0`, fetched at the start, plus files the script derives from them. It asserts every rejection and
    verification failure the spec lists that a successful build cannot show, each leaving the target, packages, and the
    temporary directory as they were:
    - a malformed (including a leading zero), pre-release, or below-minimum `version`;
    - a Checkpoint answer without `current_version`, with two, with a pre-release, and with a value below the minimum;
    - a missing release, a list without the architecture's entry, and a missing signature file;
    - an unreachable key;
    - a list altered by one byte;
    - a list signed by a key the script generates, with that key appended to the key file;
    - an archive that differs from its entry;
    - an architecture stand-in for `uname`, an edited and a removed `/etc/os-release`, and a hidden `apt-get`;
    - a directory at `/usr/local/bin/packer`.

    It also asserts the success cases that need fixtures: the same version twice (no archive request; inode and
    modification time unchanged), and an unreadable installed version (a stand-in that exits 1 is replaced).
- Checked by review only: more than one entry for the archive in the list, which no fixture can produce without the
  pinned key; and a redirect answer, which the stand-in covers only by asserting on every request that
  `--proto
  '=https'` is present and no redirect-following flag is. The entry count and the `curl` calls in
  `install.sh` are read against the spec.
- No check by hand is planned: the package-manager branch of every family runs in CI, since each family has a listed
  image that lacks a prerequisite (Context).

## Security review

- **Downloads:** for one version and architecture, the Checkpoint answer (only for `latest`), the key, the list, its
  signature, and the archive. All over HTTPS without redirects, from `checkpoint-api.hashicorp.com`,
  `www.hashicorp.com`, and `releases.hashicorp.com`, hosts upstream controls (URL inventory). Nothing is piped to a
  shell.
- **Verification:** OpenPGP signature of the list by the pinned key, then SHA-256 of the archive against its single
  entry. This detects a tampered archive, list, or key, and a compromised download host. It does not detect a compromise
  of upstream's signing key.
- **Keys:** one fingerprint pinned in `install.sh`; the key is fetched at build time and used only as a keyring file in
  a temporary GnuPG home. A rotation of the primary key fails the install until the feature follows it (Risks).
- **Metadata:** no `customizations`, `containerEnv`, `dependsOn`, `installsAfter`, `mounts`, `capAdd`, `privileged`,
  `securityOpt`, `init`, `entrypoint`, or lifecycle command. The feature never widens what the container may do.
- **Build-time execution:** the verified binary runs as root only to report its version, with `HOME` in the temporary
  directory and `CHECKPOINT_DISABLE=1` (Goals).
- **Files written as root:** `/usr/local/bin/packer`, replaced by rename. A non-regular file there fails the install
  instead of being followed. Nothing is written in a home directory.
- **Options:** `version`, validated before use; no credential, plugin, or path option, by design.
- **Run time, outside the feature:** `packer` asks the Checkpoint service for its current version and alerts, and
  `packer init` downloads plugins from GitHub with Packer's own checksum checks; `NOTES.md` says both.
- **Idempotency and failure behavior:** the spec's "Installing twice" and failure scenarios, reached through the skip
  check, the target check, and staging (Goals), and tested as described under Tests. Every failure exits non-zero, which
  fails the image build.

## Supported images

The planned `test/packer/compatibility.json`, with `"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry
also sets `"remoteUser": "vscode"`:

| Image                                              | Architectures | Why                                                                                      |
| -------------------------------------------------- | ------------- | ---------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64  | The usual dev container base; no prerequisite missing, with a non-root user              |
| `debian:12`                                        | amd64, arm64  | Minimal `apt-get` image; the feature installs `curl`, `gpg`, and `unzip`                 |
| `fedora:44`                                        | amd64, arm64  | `dnf` path; installs `unzip`                                                             |
| `almalinux:9`                                      | amd64, arm64  | RHEL matched through `ID_LIKE`; cracklib's `/usr/sbin/packer` is present                 |
| `alpine:3.24`                                      | amd64, arm64  | musl and BusyBox `unzip`; `apk` path, and proves `install.sh` runs without bash          |
| `opensuse/leap:16.0`                               | amd64, arm64  | `zypper` path; SUSE matched through `ID_LIKE`; installs `unzip`                          |
| `archlinux:latest`                                 | amd64         | `pacman` path; installs `unzip` with a system upgrade; upstream publishes no arm64 image |

Every tag is already listed by other features of the collection for the same architectures.

## URL inventory

Every URL the feature's scripts access, all fetched at build time by `install.sh`; nothing is fetched at container
start. The feature configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `amd64` or `arm64`; `<base>` is `https://releases.hashicorp.com/packer/<version>`.

| URL                                                    | Purpose                  | When                                                   | Verification                                           | Evidence (2026-11-25)                          |
| ------------------------------------------------------ | ------------------------ | ------------------------------------------------------ | ------------------------------------------------------ | ---------------------------------------------- |
| `https://checkpoint-api.hashicorp.com/v1/check/packer` | Resolve `latest`         | Build, only for `latest`; also read by `test.sh`       | TLS; the value must pass version validation            | `200`, JSON, one `current_version`, `1.16.2`   |
| `https://www.hashicorp.com/.well-known/pgp-key.txt`    | Upstream's public key    | Build, unless the requested release is already present | TLS; only the pinned fingerprint is accepted as signer | `200`, no redirect, one primary key (Context)  |
| `<base>/packer_<version>_SHA256SUMS`                   | Checksum list            | Build, unless the requested release is already present | OpenPGP signature by the pinned key                    | `200`; signed and complete for 47 releases     |
| `<base>/packer_<version>_SHA256SUMS.sig`               | Detached signature       | Build, unless the requested release is already present | Is the verification                                    | `200`                                          |
| `<base>/packer_<version>_linux_<arch>.zip`             | Archive holding `packer` | Build, unless the requested release is already present | SHA-256 against its single entry in the list           | `200`; `404` for a release that does not exist |

At run time `packer` contacts the Checkpoint service, the plugin sources a template names, and whatever platforms its
builders use; the feature itself requests nothing.

## Risks / Trade-offs

- [Upstream rotates the primary release key] → Every install fails "verification failed" until a feature change pins the
  new fingerprint, which the spec names. Failing is the intended behavior; a new signing subkey under the same primary
  key needs no change.
- [The pinned key expires on 2030-03-01 unless upstream extends it] → GnuPG then reports the signature as made by an
  expired key and installs fail; upstream extended the expiry before (the key file's self-signature is from 2026), and a
  feature change follows whatever upstream publishes.
- [A tampered Checkpoint answer selects another signed release] → Accepted in the spec. Users who need a specific
  release pin `version`.
- [The Checkpoint service is unavailable or changes its answer's shape] → Installs with `latest` fail with a message
  naming the URL or the value received; a pinned `version` does not ask the service.
- [`www.hashicorp.com` rate-limits the key file as it does its HTML pages] → Not observed for the key file (Context);
  the install would fail naming the URL, and a re-run passes.
- [A release is published between a CI job's build and its test] → That job's comparison with the Checkpoint answer
  fails; a re-run passes.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [On RHEL-family images `/usr/sbin/packer` is cracklib's] → The default `PATH` finds the feature's binary first; a
  `PATH` that omits `/usr/local/bin`, such as a restrictive `sudo` `secure_path`, finds cracklib's instead. `NOTES.md`
  says so; the feature does not touch another package's file.
- [On Arch Linux, a missing prerequisite upgrades the whole image] → Stated in the spec; `archlinux:latest` lacks
  `unzip`, so it happens on every install there unless the image already has it.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.
- [Packer from `1.10.0` is under the Business Source License 1.1] → The feature distributes the install method, not the
  binary; `NOTES.md` names the license so that users check upstream's terms for their use.
- [The binary adds about 105 MB to the image] → Inherent to the tool; no option can shrink it.
