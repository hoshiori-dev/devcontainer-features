# Design

## Context

See proposal.md - Why. The feature follows the `gitleaks` and `act` features (archived changes
`2026-10-16-add-gitleaks-feature` and `2026-10-23-add-act-feature`): a static Go binary from upstream's release
archives, verified before it is installed atomically to `/usr/local/bin`, with prerequisites from the image's own
repositories. It differs in three ways. Upstream signs the checksum list, so the verification is an OpenPGP signature
with a pinned key, as in the `claude-code` feature. It installs shell completions. It optionally installs the FUSE
helper `hf-mount` also installs. What is the same is named, not repeated. The interface was agreed with the maintainer
in conversation before this change: a CLI with an optional mount helper that is off by default; completions always
installed, with no option; no man page; minimum release `1.63.0`; no beta builds. It is recorded in issue #194.

Upstream facts this change relies on, checked on 2026-11-09 against `downloads.rclone.org`, `rclone.org`,
`beta.rclone.org`, and `github.com/rclone/rclone` (release API, all pages; `cmd/cmd.go` and `cmd/genautocomplete/` at
`v1.76.0`; `docs/content/changelog.md` on `master`). Verification and package checks ran in throwaway containers. The
`rclone` binaries themselves were inspected, not run (Open Questions):

- The newest stable release is `v1.76.0` (2026-11-06); `https://downloads.rclone.org/version.txt` answers `200` with the
  single line `rclone v1.76.0`. Upstream releases about monthly. Of 134 GitHub releases not marked pre-release, the 41
  from `v1.63.0` (2023-06-30) to `v1.76.0` are plain `vMAJOR.MINOR.PATCH` tags; before `v1.47.0`, tags mostly drop the
  patch number (`v1.46`).
- Each release directory `https://downloads.rclone.org/v<version>/` holds `rclone-v<version>-linux-<arch>.zip` for
  `amd64`, `arm64`, `386`, `arm`, `arm-v6`, `arm-v7`, `mips`, and `mipsle`, the matching `.deb` and `.rpm` files, and
  `MD5SUMS`, `SHA1SUMS`, and `SHA256SUMS`. None of the URLs the feature uses redirects; a missing release answers `404`.
- `SHA256SUMS` is an OpenPGP clearsigned message (`Hash: SHA1`) whose signed text is `sha256sum` output for every file
  of the release. For all 41 releases from `v1.63.0` to `v1.76.0`, GnuPG 2.4.4 reported a good signature whose primary
  key fingerprint is `FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA`, and the signed text held exactly one entry each for the
  linux `amd64` and `arm64` zip archives.
- `https://rclone.org/KEYS` holds two public keys. One is the DSA-1024 key `FBF737EC…54FA` (created 2001-09-27, no
  expiry), which https://rclone.org/release_signing/ documents as the release key. The other is an RSA-4096 key
  `E3B358DC858FB307F48170B9CB0DBEBC5F32C81D` (created 2022-09-16), which signs no release checked.
- `gpg --verify` of the `v1.76.0` list with that key list succeeded on Debian 12 (GnuPG 2.2.40), Ubuntu 24.04 (2.4.4),
  Fedora 44 (2.4.9), and Alpine 3.24 (2.4.9). The minimal package `gpg`, without `gpg-agent`, is enough on Debian and
  Alpine for `--dearmor` and for `--decrypt` against the resulting keyring file, which prints the signed text (47 lines
  for `v1.76.0`); `--import` fails there, since it starts `gpg-agent` (found during implementation).
- The zip holds `rclone-v<version>-linux-<arch>/` with `rclone`, `rclone.1`, `README.txt`, `README.html`, and
  `git-log.txt`. Both the `amd64` and the `arm64` `rclone` of `v1.76.0` are static ELF executables (no `PT_INTERP`), so
  they need no particular C library.
- `rclone version` prints `rclone <fs.Version>` as its first line, where `fs.Version` is `v<version>` for a release
  (`cmd/cmd.go`, `ShowVersion`). `genautocomplete` was renamed `completion` in `v1.63.0` and kept as an alias; an output
  file `-` writes to stdout since `v1.54.0`; fish is supported since `v1.52.0`. Without an output file, upstream writes
  to `/etc/bash_completion.d/rclone`, `/usr/share/zsh/vendor-completions/_rclone`, and
  `/etc/fish/completions/rclone.fish`.
- Completion lookup, checked with a stand-in completion file. In `mcr.microsoft.com/devcontainers/base:ubuntu24.04`,
  bash-completion 2.11 is loaded by `/etc/bash.bashrc` and the `vscode` user's `.bashrc`, and it loads a file from
  `/usr/local/share/bash-completion/completions/` on demand. The `vscode` user's interactive zsh (oh-my-zsh) has
  `/usr/local/share/zsh/site-functions` on `fpath`, as zsh has on Debian 12, Fedora 44, and Alpine 3.24. fish 4.6 on
  Fedora 44, fish on Alpine 3.24, and fish on Debian 12 search `/etc/fish/completions` and
  `/usr/share/fish/vendor_completions.d`, but not `/usr/local/share/fish/vendor_completions.d`.
- Tools present before any install: the Ubuntu base image has `curl`, `gpg`, and `unzip`. `debian:12` has none of the
  three, only `gpgv`. `fedora:44` has `curl` and `gpg` but no `unzip`. `alpine:3.24` has BusyBox `unzip` but no `curl`
  or `gpg`. No `man` works in any of them: the base image's `/usr/bin/man` is the minimized-image placeholder.
- The `fuse3` package installs `fusermount3`, owned by root with the set-user-ID bit, on all four images. On Fedora 44
  it is at `/usr/sbin/fusermount3`, where `/usr/sbin` is a link to `bin`. rclone looks for `fusermount3` or `fusermount`
  on `PATH` and then in `/bin:/usr/bin`.
- `beta.rclone.org` publishes beta builds without any checksum list. Upstream's `install.sh` reads `version.txt`,
  downloads `rclone-current-linux-<arch>.zip`, verifies nothing, and installs to `/usr/bin/rclone`.

## Goals / Non-Goals

**Constraints and invariants of this approach:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- Two upstream hosts and no redirects: every request goes through `curl` with HTTPS only and fails on a redirect, and
  requests only the URLs in the URL inventory below. Package-manager requests go to the image's configured repositories.
  Checked by reviewing each `curl` call against the inventory, and by the fixture scenario, whose `curl` stand-in
  records each request's arguments, asserts the HTTPS-only and no-redirect flags, and answers one request with a
  redirect.
- Validate before any change: the options' form, the minimum version, the architecture, the distribution, its package
  manager, and each target path (`/usr/local/bin/rclone` and the three completion files) being absent or a regular file
  are all checked before any package is installed or anything is downloaded. Checked by the fixture scenario on
  `debian:12`, which asserts after each rejected run that no package was added and no request was made.
- Verify before use: nothing from the archive is extracted or run before the checksum list's signature is verified, the
  signer's primary fingerprint matches the pinned one, and the archive's digest matches its single entry in the signed
  text. Every keyring the install uses lives in the install's temporary directory. Checked by the fixture scenario
  (Decisions, Tests).
- Stage everything, then rename: the new binary and the three completion files are produced next to their targets under
  temporary names, from the staged binary, before any target is replaced; each replacement is a rename on the same
  filesystem. A failure before the renames leaves every earlier file as it was. Checked by the failed-replacement cases
  of the fixture scenario and by `duplicate.sh`.
- Build-time `rclone` runs (reading the installed version, generating completions) use `HOME`, `XDG_CONFIG_HOME`,
  `XDG_CACHE_HOME`, and `RCLONE_CONFIG` inside the temporary directory, so they write nothing to a real home and read no
  real configuration. Checked by the "Nothing configured after install" scenario in `test.sh`, before `test.sh` runs
  `rclone` itself.
- Package installs only for missing tools, the cache cleanup, the temporary directory and staged files under one `trap`,
  and the skip check on the parsed first line of `rclone version`: as in the `gitleaks` design, checked the same way.
  The directories are `${TMPDIR:-/tmp}/rclone-feature.XXXXXX` and, beside each target, `.rclone-feature.XXXXXX`.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream also builds 386, ARM, and MIPS, but CI has runners only for these
  two.
- Releases before `1.63.0`, beta builds, and `rclone-current-*` archives (the issue's Out of scope).
- The man page: no tested image has a working `man`, and `rclone help` prints the same text.
- `rclone nfsmount`, `rclone serve` daemons, systemd units, and starting or checking a mount; granting the container
  mount privileges or editing `/etc/fuse.conf` (the spec's "Mounts left to the user").
- Any rclone configuration, remote, credential, or `RCLONE_*` variable (the spec's "No rclone configuration").
- Removing an rclone that the image's package manager installed at `/usr/bin/rclone`; `/usr/local/bin` comes first on
  the default `PATH`, so the feature's binary wins.
- Repeating in CI a real FUSE mount, which needs `--device /dev/fuse` and `SYS_ADMIN` that no scenario may declare
  (testing.md, Running the installer); it is a manual check (Tests).

## Decisions

### Option interface

| Name                       | Type      | Default    | Enum or proposals               | Meaning                                                                                                    |
| -------------------------- | --------- | ---------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `version`                  | `string`  | `"latest"` | proposals `["latest","1.70.0"]` | The release to install: `latest`, or a release version at or above `1.63.0`, with or without a leading `v` |
| `installMountDependencies` | `boolean` | `false`    | —                               | Install `fuse3`, which provides the `fusermount3` helper `rclone mount` needs                              |

- **`version` default `latest`.** rclone ships provider fixes monthly, so the newest stable release is what most users
  want; a project that needs reproducible builds pins `version`. The second proposal, `1.70.0`, is older than `latest`,
  so the duplicate test's first install is replaced by the second. Rejected: the minimum `1.63.0` as the proposal — a
  scenario covers the minimum, and a three-year-old release is a poor suggestion in the generated README; the current
  release — it equals what `latest` resolves to, so the replace path would never run in CI.
- **`installMountDependencies` default `false`.** Most use of rclone in a dev container is copy, sync, and serve, which
  need no FUSE helper. A mount needs container settings only the user can add, and `fusermount3` is a set-user-ID root
  executable that should not reach every image that never mounts. Changing the default later to `true` would only add
  behavior. The duplicate test installs `true` first and `false` second, which exercises "Mount dependencies enabled,
  then disabled".
- **Rejected shapes.** `installFuse` as the name — the `hf-mount` feature already uses `installMountDependencies` for
  the same purpose, and one name across the collection reads better. An enum of mount backends — `nfsmount` is out of
  scope, and a one-value enum is a boolean. Detecting `/dev/fuse` at build time — the build container never has it,
  whatever the run-time settings. An option for completions or for the shells to cover — agreed against in conversation;
  it would double the test surface for files that do nothing where a shell is absent. An option for a configuration
  path, remote, or credential — the spec rules it out.

### Release source

Download the zip archive and `SHA256SUMS` from `https://downloads.rclone.org/v<version>/`, and resolve `latest` from
`https://downloads.rclone.org/version.txt`. This is the host upstream's installation guide, signing guide, and
`install.sh` all name. It serves every file directly, so the inventory is exact and redirects can be refused (below).

Rejected: GitHub release assets — the same files, but behind a redirect to GitHub's asset host, for no gain over the
host upstream documents. Upstream's `install.sh` — it is meant to be piped into a shell, which feature-authoring.md
forbids, and it verifies nothing. Distribution packages — upstream warns they are often out of date, and they differ per
distribution. Upstream's `.deb` and `.rpm` files — Alpine needs the zip anyway, so they would only add a second path.
Snap — no mount under strict confinement, and no snapd in a container. The `rclone/rclone` image — not a CLI on `PATH`.
`go install` — a Go toolchain for one binary. Beta builds — no checksum list, so they would rely on TLS alone.

### No redirects

Every request passes `--proto '=https'` and fails on a 3xx without contacting its target, as in the `blender` design. No
URL in the inventory redirects (Context), so following redirects would only admit hosts the inventory does not name.
Rejected: following HTTPS redirects as in the `gitleaks` design — that design needs GitHub's asset host; here, a
redirect upstream adds later fails the install clearly and a PATCH release of the feature follows.

### Signature verification

Fetch `https://rclone.org/KEYS` and `SHA256SUMS` into the temporary directory, and turn the key list into a keyring file
with `gpg --dearmor` in a GnuPG home there. Importing it instead would start `gpg-agent`, which the minimal `gpg`
packages of Debian and Alpine do not include, while verifying needs no agent. Then run `gpg --decrypt` on the list
against that keyring alone, with status output. It must exit 0, report no `BADSIG`, `ERRSIG`, `EXPSIG`, `EXPKEYSIG`, or
`REVKEYSIG`, and report at least one `VALIDSIG`. The last field of every `VALIDSIG` (the primary key fingerprint) must
equal `FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA`, a constant in `install.sh`. Only the text `--decrypt` prints is
searched for the archive's entry, which must occur exactly once, as
`<64 hex digits>  rclone-v<version>-linux-<arch>.zip`.

- Reading the signed text, not the file, matters: lines outside the signature block are not covered by the signature,
  yet `gpg --verify` would still report it good (the spec's "Entry outside the signed text").
- Checking the primary fingerprint of the actual signer, not the key list, matters too: the key list holds a second key
  (Context), and a list holding any number of keys must not widen what is accepted.
- No GnuPG option is added that weakens a check. If a future GnuPG refuses DSA-1024 or SHA-1, the install fails (the
  spec's "rclone signing key strength").

Rejected: the `claude-code` design's check that the key file holds exactly one key — upstream's key list holds two, and
pinning the signer's fingerprint is the stronger check. Shipping the public key inside the feature — it would remove the
`rclone.org` request, but key rotation would then need a feature release even when upstream re-signs with the new key in
a documented place; fetching the key from upstream and pinning its fingerprint is what `claude-code` does. `gpgv` — it
needs a binary keyring, which takes `gpg --dearmor` anyway. `MD5SUMS` or `SHA1SUMS` — weaker digests under the same
signature. GitHub's asset digest — computed by the platform from the same upload, so it adds nothing to the signature.

### Minimum version `1.63.0`

The first release with the `completion` command; output to stdout and fish completions came earlier. All 41 releases
from `1.63.0` to `1.76.0` carry a list signed by the pinned key with both archives listed (Context). Rejected: `1.47.0`,
the first three-part tag — older releases need `genautocomplete`, have no fish completions before `1.52.0`, and cannot
write to stdout before `1.54.0`, which means branches and scenarios for releases nobody should start a dev container
with. `1.54.0` with the `genautocomplete` alias — it relies on an alias upstream may drop, and gains releases more than
three years old.

### Completions

Generate each script from the staged binary with `rclone completion <shell> -` and write it as described under "Stage
everything, then rename":

| Shell | Path                                                  | Why there                                                                                       |
| ----- | ----------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| bash  | `/usr/local/share/bash-completion/completions/rclone` | bash-completion's on-demand directory under `/usr/local`, so it costs nothing at shell start    |
| zsh   | `/usr/local/share/zsh/site-functions/_rclone`         | On zsh's default `fpath` on every tested distribution and in the base image's oh-my-zsh         |
| fish  | `/usr/share/fish/vendor_completions.d/rclone.fish`    | fish's directory for third-party completions; fish does not search `/usr/local/share` (Context) |

Missing parent directories are created with mode `0755`; files get mode `0644`. The files are regenerated on every
successful install, including when the binary is kept, so they always match the binary in place.

Rejected: upstream's default paths — `/etc/bash_completion.d` is sourced eagerly at every interactive bash start, and
`/usr/share/zsh/vendor-completions` is a Debian-only `fpath` entry. `/etc/fish/completions` — it is the administrator's
override directory and outranks vendor completions, so a file there would hide a user's or administrator's choice.
`/usr/local/share/fish/vendor_completions.d` — agreed first in conversation, then dropped after the check above showed
fish does not read it. Generating only for shells present at build time — a shell installed by a later feature or layer
would get no completion. Installing bash-completion — it changes every user's shell, beyond what this feature is for.

### Mount helper

When `installMountDependencies` is `true`, add `fuse3` to the same package-manager transaction as the prerequisites; the
package name is the same in all four families. Nothing else changes: no `/etc/fuse.conf` edit, no group membership, no
device node. `NOTES.md` gives the settings, as the `hf-mount` NOTES do:

- `runArgs`: `--cap-add=SYS_ADMIN` and `--device=/dev/fuse`, plus `--security-opt=apparmor=unconfined` under AppArmor,
  or `--privileged` as the broad alternative.
- A non-root mount uses the set-user-ID `fusermount3`. `--allow-other` also needs `user_allow_other` in
  `/etc/fuse.conf`, which the user adds.
- An existing rclone configuration can be brought in by mounting the host's `~/.config/rclone` in the user's own
  configuration.
- `rclone selfupdate` replaces the binary the feature manages; the next feature install puts the requested release back.

Rejected: setting `user_allow_other` — it changes a system-wide FUSE policy for every user, which the spec leaves to the
user, as `hf-mount` does. Declaring `capAdd`, `privileged`, or a device in the metadata — every image with the feature
would gain them, mounting or not.

### Prerequisites

Install only the missing tools, from the image's repositories, in one transaction with `fuse3` when requested, and leave
them installed, as in the `gitleaks` design. `curl` comes from package `curl`. CA certificates come from
`ca-certificates`. `gpg` comes from `gpg` on Debian, Ubuntu, and Alpine, and from `gnupg2` on Fedora. `unzip` comes from
`unzip`; BusyBox's `unzip` on Alpine is enough. Rejected: removing the tools afterwards — the feature cannot tell which
ones another layer also needs. Extracting with something other than `unzip` (`bsdtar`, Python) — `unzip` is the smallest
package that reads zip on all four families.

### Tests

- `test.sh`, on every compatibility image as its remote user, checks in this order:
  1. "Nothing configured after install", before running `rclone`.
  2. The first line of `rclone version` against `version.txt` at test time, and "Copy between local directories".
  3. The three completion files against `rclone completion <shell> -`, and that no package added bash-completion, zsh,
     or fish where the image had none.
  4. Where the image's interactive bash loads bash-completion and where zsh is present (the base image), loading the
     completion as the remote user.
  5. That `fusermount3` is absent where the image had none, and the package-manager caches.
- `duplicate.sh` installs `1.70.0` with `installMountDependencies` `true`, then the defaults. It asserts the newest
  release, completion files matching it, one `rclone` in `/usr/local/bin`, and `fusermount3` present, owned by root,
  with the set-user-ID bit, and on the remote user's `PATH`.
- Scenarios, with `scenarioArchitectures` `["amd64","arm64"]`:
  - `test_version_floor` — `alpine:3.24`, `version` `v1.63.0`: a leading `v`, the minimum, BusyBox `unzip`, and
    completions generated by the oldest supported release.
  - `test_version_explicit` — `fedora:44`, `version` `1.70.0`.
  - `test_mount_dependencies` — the Ubuntu base image as `vscode`, `installMountDependencies` `true`: `fusermount3` on
    the `PATH`, no `rclone` process, no FUSE mount, and no `user_allow_other` line added after the container starts.
  - `fail_contract` — `debian:12`, defaults. Its script moves the build's binary and completion files aside, restores
    them at the end, and runs `install.sh` with a `curl` stand-in. The stand-in serves fixtures: the real key list, real
    signed lists of two releases fetched at the start, and archives the script builds. It asserts every rejection and
    verification failure the spec lists that a successful build cannot show, each leaving targets, packages, and the
    temporary directory as they were:
    - a malformed, beta, or below-minimum `version`, and an invalid `installMountDependencies`;
    - a version file with other content;
    - a missing release, a missing architecture, and a redirect;
    - an unreachable key list;
    - a signed text altered by one byte, and an unsigned list;
    - a list signed by a key the script generates, with that key appended to the key list;
    - an archive entry only outside the signed text (one release's real list served for another release, plus an
      appended line);
    - a digest mismatch;
    - GnuPG refusing SHA-1, through a `gpg` wrapper that adds `--weak-digest SHA1`;
    - an architecture stand-in for `uname`, an edited and a removed `/etc/os-release`, and a hidden `apt-get`;
    - a directory at the binary's path and at a completion path.

    It also asserts the success cases that need fixtures: the same version twice (no archive request; inode and
    modification time unchanged), and an unreadable installed version (a stand-in that exits 1 is replaced).
- Checked by review only: more than one entry for the archive in the signed text, which no fixture can produce without
  the pinned key. The entry count in `install.sh` is read against the spec.
- Checked by hand, once, on amd64: a real `rclone mount` of a local directory through a `:local:` remote, as root and as
  `vscode`, in a dev container with the `runArgs` from `NOTES.md` and `installMountDependencies` `true`. The result goes
  into the PR's Validation section.

## Security review

- **Downloads:** for one version and architecture, the version file (only for `latest`), the key list, the checksum
  list, and the archive. All are on two upstream hosts over HTTPS, and every redirect is refused (URL inventory).
  Nothing is piped to a shell.
- **Verification:** OpenPGP signature of the checksum list by the pinned key, then SHA-256 of the archive against its
  single entry in the signed text. This detects a tampered archive, list, or key list, and a compromised download host.
  It does not detect a compromise of upstream's signing key. The key's weakness (DSA-1024, SHA-1) is stated in the spec.
- **Keys:** one fingerprint pinned in `install.sh`; the key list is fetched at build time and used only as a keyring
  file in a temporary GnuPG home. A rotation fails the install until the feature follows it (Risks).
- **Metadata:** no `containerEnv`, `dependsOn`, `installsAfter`, `mounts`, `capAdd`, `privileged`, `securityOpt`,
  `init`, `entrypoint`, or lifecycle command. The feature never widens what the container may do.
- **Set-user-ID binary:** `installMountDependencies` adds the distribution's `fusermount3`, set-user-ID root, from the
  image's own signed repositories, and only on request.
- **Build-time execution:** the verified binary runs as root to report its version and print completions, with every
  home and configuration path in the temporary directory (Goals).
- **Files written as root:** `/usr/local/bin/rclone` and three completion files in system directories, each replaced by
  rename. A non-regular file at any of these paths fails the install instead of being followed. Nothing is written in a
  home directory.
- **Options:** `version`, validated before use, and a boolean; no credential, remote, or path option, by design.
- **Idempotency and failure behavior:** the spec's "Installing twice" and failure scenarios, reached through the skip
  check, the target checks, and staging (Goals), and tested as described under Tests. Every failure exits non-zero,
  which fails the image build.

## Supported images

The planned `test/rclone/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                                            |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with a non-root user, bash-completion, and zsh    |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl`, `gpg`, `unzip`, and certificates         |
| `alpine:3.24`                                      | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash and the binary on musl |
| `fedora:44`                                        | `dnf` path, and `fusermount3` under the merged `/usr/sbin`                                     |

The same list as `gitleaks` and `act`, whose changes verified that all four tags publish amd64 and arm64 images.

## URL inventory

Every URL the feature's scripts access, all fetched at build time by `install.sh`; nothing is fetched at container
start. The feature configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `amd64` or `arm64`.

| URL                                                                          | Purpose                          | When                                                   | Verification                                                     | Evidence (2026-11-09)                                                 |
| ---------------------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------- | --------------------------------------------------------------------- |
| `https://downloads.rclone.org/version.txt`                                   | Resolve `latest`                 | Build, only for `latest`; also read by the tests       | TLS; the content must be one line passing the version validation | `200`, no redirect, `rclone v1.76.0`                                  |
| `https://rclone.org/KEYS`                                                    | Upstream's public keys           | Build, unless the requested release is already present | TLS; only the pinned fingerprint is accepted as signer           | `200`, no redirect, two keys (Context)                                |
| `https://downloads.rclone.org/v<version>/SHA256SUMS`                         | Signed checksum list             | Build, unless the requested release is already present | OpenPGP signature by the pinned key                              | `200`, no redirect; signed and complete for all 41 releases (Context) |
| `https://downloads.rclone.org/v<version>/rclone-v<version>-linux-<arch>.zip` | Release archive holding `rclone` | Build, unless the requested release is already present | SHA-256 against its single entry in the signed text              | `200`, no redirect, `application/zip` for `1.63.0` and `1.76.0`       |

At run time rclone contacts whatever remotes the user configures; the feature itself requests nothing.

## Risks / Trade-offs

- [Upstream rotates the release key, for example to the RSA key already in the key list] → Every install fails
  "verification failed" until a feature change pins the new fingerprint, which the spec names. Failing is the intended
  behavior; the release signing page is the source to check.
- [A future GnuPG rejects DSA-1024 or SHA-1 signatures by default] → The install fails on images with that GnuPG; the
  spec forbids weakening the check. A feature change follows whatever upstream publishes instead.
- [A tampered version file selects an older signed release] → Accepted in the spec. Users who need a specific release
  pin `version`.
- [`downloads.rclone.org` starts redirecting] → The install fails clearly; a PATCH release of the feature updates the
  inventory after checking the new host.
- [The fish file lives under `/usr/share`, which distribution packages own] → It is a vendor directory meant for this. A
  later distribution `rclone` package would overwrite the file with its own, which is harmless.
- [Completions are inert where bash-completion, zsh, or fish is missing] → Accepted; `NOTES.md` says which package
  activates them.
- [`rclone selfupdate` or a distribution package changes the effective rclone] → `selfupdate` replaces
  `/usr/local/bin/rclone`; the next feature install restores the requested release. A package's `/usr/bin/rclone` is
  shadowed by the feature's on the default `PATH`. `NOTES.md` says both.
- [A release is published between a CI job's build and its test] → That job's comparison with `version.txt` fails; a
  re-run passes. Releases are weeks apart.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.

## Open Questions

- What `rclone completion <shell> -` and `rclone version` print to stderr with no configuration file. The binaries were
  not run during this research. The approach captures stdout only and isolates every configuration path (Goals), so the
  answer changes neither the spec nor the plan. The first implementation step confirms it.
