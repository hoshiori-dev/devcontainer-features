# Design

## Context

See proposal.md - Why. The behavior contract is `specs/deno/spec.md`; this document names how it is reached. Facts below
were checked on 2026-09-30 unless marked otherwise.

- `deno` is the repository's first feature: `src/` does not exist yet, and the README says no feature has been
  published. `just new-feature deno` scaffolds `version` (Options) and the two Debian-family images of Supported images.
- Latest stable release: `v2.9.7`, published 2026-09-17 (`gh api repos/denoland/deno/releases/latest`);
  `https://dl.deno.land/release-latest.txt` returns `v2.9.7` followed by a newline, with the `v`. The LTS pointer
  `https://dl.deno.land/release-lts-latest.txt` returns `v2.9.3`; per Deno's stability page, a bare version always names
  the stable build, and LTS builds with the same number are different binaries served from `dl.deno.land`.
- Linux assets are glibc builds only: `deno-x86_64-unknown-linux-gnu.zip` and `deno-aarch64-unknown-linux-gnu.zip`
  (about 41.6 MB and 39.8 MB), each holding a single `deno` entry with mode 0755. The v2.9.7 binaries require at most
  `GLIBC_2.27` and need only glibc libraries plus `libgcc_s.so.1`; Deno builds against an Ubuntu 18.04 (bionic) sysroot
  and has no musl build (its own Alpine image transplants glibc).
- Checksum files have the `sha256sum` format, `<64 hex>␠␠<name>`: `<asset>.zip.sha256sum` names the archive, and
  `deno-<target>.sha256sum` names `deno` and holds the hash of the extracted executable (known only from its name field
  and the release asset list; no Deno document describes it). Availability differs by release, counted from the asset
  names that `gh api --paginate repos/denoland/deno/releases` lists for all 388 stable releases on both Linux targets,
  and spot-checked with HTTP requests for `2.0.0`, `2.5.0`, `2.7.14`, `2.8.0`, and `1.46.3`:

  | Releases                    | `.zip.sha256sum` | `deno-<target>.sha256sum` |
  | --------------------------- | ---------------- | ------------------------- |
  | `2.7.14`, `2.8.0` and later | yes              | yes                       |
  | `2.0.1` to `2.7.13`         | yes              | no                        |
  | `2.0.0`                     | no               | yes                       |
  | `1.x` and earlier           | no               | no                        |

  Under the maintainer's decision that both files are verified, 13 releases are installable today and every future one
  is. For every release checked, the archive URL answers a `HEAD` request with 200 when the archive exists (`1.46.3`,
  `2.0.0`) and with 404 when it does not (`9.9.9`), so a missing checksum file can be told apart from an unknown
  version.
- Deno publishes no `.sig`, `.asc`, or attestation assets. The `immutable` field of the same release listing is true for
  `2.5.7` and for `2.6.5` onwards and false for every older release; GitHub signs a release attestation for immutable
  releases, which `gh release verify-asset` checks.
- Deno's current installer (`denoland/deno_install`, `install.sh` at commit `41d4676f`) resolves the latest version from
  `release-latest.txt` and downloads stable archives from GitHub releases, stating that
  `dl.deno.land/release/<version>/` also serves the LTS channel and can hold an LTS-marked binary under a stable version
  number. The script behind `https://deno.land/install.sh` still downloads from `dl.deno.land`.
- `deno --version` prints `deno 2.9.7 (stable, release, x86_64-unknown-linux-gnu)` on its first line (Deno 2.9.7 in the
  dev container).
- `DENO_INSTALL_ROOT` sets where `deno install --global` places executables, in its `bin` subdirectory (default
  `$HOME/.deno`); `DENO_NO_UPDATE_CHECK` turns off Deno's update check; `DENO_DIR` (cache, default `$HOME/.cache/deno`)
  is left alone.
- The Dev Container spec applies `containerEnv` as Dockerfile `ENV` before the feature's `install.sh` runs, so its
  values are in effect during installation and in every process of the container, and `${PATH}` expands.
- `debian:12` ships bash and `libgcc_s` but no `curl`, `unzip`, or CA bundle; `base:ubuntu24.04` has all three through
  the common-utils feature it is built with. `bash` is an Essential package on Debian and Ubuntu; in the Fedora and
  openSUSE families it was present in every image probed (Platform research below), which is evidence, not a guarantee.
  Stock `alpine` has no bash, so a `#!/usr/bin/env bash` script fails there with `env: can't execute 'bash'` before its
  first line runs.
- The Dev Container CLI's duplicate test (CLI 0.89.0) gives a string option with `proposals` the first proposal that is
  not the default, unless `--permit-randomization` is passed, which `scripts/test_feature.ts` does not do.
- The Dev Container CLI changes the remote user's UID and GID after the features are installed. The maintainer reported
  that PR #30's CI failed: "the tools tree is owned by vscode" (`test.sh`, `duplicate.sh`, and the `exact_version`
  scenario) failed on the Ubuntu base image (then tagged `base:ubuntu-24.04`), amd64 and arm64, while the same tests
  passed locally. The failing containers ran from images tagged `-features-uid`. CLI 0.89.0 builds that image from its
  `scripts/updateUID.Dockerfile` when `updateRemoteUserUID` is not `false`, on a Linux host, for a remote user other
  than root: it rewrites that user's UID and GID in `/etc/passwd` to the host user's, rewrites the GID of that user's
  primary group in `/etc/group`, and runs `chown -R` on the home folder only. GitHub-hosted runners run as UID 1001, so
  `vscode` changed from 1000 to 1001 and lost the `/usr/local/share/deno` tree the feature had given to UID 1000;
  locally the host UID is 1000 and nothing changed. Every user whose host UID is not 1000 gets the same result.
  Supplementary group members in `/etc/group` are stored by user name, which the rewrite leaves alone.
- First-party precedent: `devcontainers/features` `src/node/install.sh` (commit `96405515`) creates a system group `nvm`
  when missing ("Create nvm group to the user's UID or GID to change while still allowing access to nvm"), adds the user
  to it, and gives its directory group `nvm` with `g+rws`.
- Prior art `ghcr.io/devcontainers-extra/features/deno` 1.0.4 verifies no checksum, fails a second install on a plain
  `ln -s`, and does not install `unzip`; nothing is taken from it.

### Platform research (2026-09-30)

Gathered for the maintainer's decision to widen the supported families (Decisions). Labels: **[T]** ran on amd64 on
2026-09-30; **[I]** inferred from manifests, documents, or sibling branches, not run. Nothing ran on arm64: the host has
neither an arm64 runner nor emulation.

- Method [T]: in each image below, a probe listed `/etc/os-release`, `getconf GNU_LIBC_VERSION`, `ldd --version`, the
  commands present, and which of the four CA bundle paths of the spec is a non-empty file, then ran the
  checksum-verified Deno 2.9.7 x86_64 binary (`--version`, `eval`). PR #30's own `install.sh` ran on `debian:13`,
  `debian:13-slim`, and `ubuntu:26.04` (installed Deno 2.9.7) and on `fedora:44`, `alpine:3.24`,
  `cgr.dev/chainguard/wolfi-base`, `amazonlinux:2`, and `archlinux:latest` (each rejected).
- Supported families, all with bash and `libgcc_s.so.1`, all running Deno 2.9.7 [T]:

  | Family   | Images probed                                                                                                                                                                                                                                                       | glibc     | `ID` / `ID_LIKE`                                                                                                                               | Manager                                                                                     | Missing of `curl`, `unzip`, CA bundle                   | CA bundle paths present                                                                                                                 |
  | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
  | Debian   | `debian:12`, `debian:13` (and `-slim`), `ubuntu:22.04`, `ubuntu:24.04`, `ubuntu:26.04`; devcontainers `base:ubuntu24.04`, `noble`, `jammy`, `trixie`, `bookworm`, `ubuntu26.04`, and the `javascript-node`, `typescript-node`, and `python` tags on Debian 12 or 13 | 2.35–2.43 | `debian`; `ubuntu` / `debian`                                                                                                                  | `apt-get`                                                                                   | all three on plain images; none on devcontainers images | `/etc/ssl/certs/ca-certificates.crt` where present                                                                                      |
  | Fedora   | `fedora:43`, `fedora:44`; `almalinux:8`, `:9`, `:10`; `rockylinux/rockylinux:8`, `:9`, `:10`; `quay.io/centos/centos:stream9`, `stream10`; `oraclelinux:8`, `:9`, `:10`; UBI 8, 9, 10; `amazonlinux:2023`                                                           | 2.28–2.43 | `fedora`; `almalinux`, `rocky` / `rhel centos fedora`; `centos` / `rhel fedora`; `rhel` / `fedora` or `centos fedora`; `ol`, `amzn` / `fedora` | `dnf` (on Fedora, `dnf`, `yum`, and `microdnf` are links to dnf5 [I, dnf-packages Context]) | `unzip` only                                            | EL and Amazon Linux: `/etc/pki/tls/certs/ca-bundle.crt`; `fedora:44`: only `/etc/ssl/certs/ca-certificates.crt` and `/etc/ssl/cert.pem` |
  | openSUSE | `opensuse/leap:15.6`, `opensuse/leap:16.0`, `opensuse/tumbleweed`                                                                                                                                                                                                   | 2.38–2.44 | `opensuse-leap` / `suse opensuse`; `opensuse-tumbleweed` / `opensuse suse`                                                                     | `zypper`                                                                                    | `unzip` only                                            | `/etc/ssl/ca-bundle.pem`                                                                                                                |

- Minimal Fedora-family images — `almalinux:10-minimal`, `rockylinux/rockylinux:10-minimal`, `oraclelinux:10-slim`,
  `ubi9/ubi-minimal`, `ubi10/ubi-minimal` — have `curl`, a CA bundle, and `microdnf` but no `dnf`, and lack `unzip` [T].
- Outside the three families [T]: `amazonlinux:2` has glibc 2.26, and Deno 2.9.7 fails there with
  ``version `GLIBC_2.27' not found``; `archlinux:latest` (`ID=arch`, no `ID_LIKE`, `pacman`) runs Deno, and its image is
  published for amd64 only [I, manifest]; `azurelinux/base/core:3.0` (`ID=azurelinux`) and `cbl-mariner/base/core:2.0`
  (`ID=mariner`) run Deno, with `tdnf` and no `ID_LIKE`; `cgr.dev/chainguard/wolfi-base` runs Deno but has no bash,
  `getconf`, or `ldd` (its glibc 2.43 is read from the Wolfi package index [I]), and PR #30's `install.sh` reports it as
  musl-based; Alpine has a `/lib/ld-musl-*` loader and cannot run Deno. SUSE Linux Enterprise BCI images (`ID=sles`,
  `ID_LIKE=suse`) are published for amd64 and arm64 [I, manifest] and were not probed.
- `debian:11` (glibc 2.31) reached its end of life on 2026-08-31; `apt-get install` there fails with 404 from
  `debian-security` [T], so an end-of-life release of a supported family passes the platform checks and fails at its
  package manager.
- Deno's TLS uses the Mozilla roots built into the binary unless `DENO_TLS_CA_STORE=system` is set, so the CA bundle is
  needed only by the feature's `curl` (upstream research of 2026-09-30: `cli/lib/args.rs` at v2.9.7 and the environment
  variables page; `fetch` succeeded on `ubuntu:18.04` without a bundle [T]). Deno 2.9.7 runs on glibc 2.27 exactly
  (`ubuntu:18.04`) [T]; the aarch64 binaries need at most `GLIBC_2.27` too (`readelf -V`) [I for arm64 at run time].
- dnf facts from the `dnf-packages` change (branch `21-add-feature-dnf-packages`, design Context, checked 2026-09-30 on
  `fedora:44` with dnf5 5.4.3.0 and `almalinux:9` with dnf 4.14.0) [I here]: `--setopt=install_weak_deps=False` works in
  both generations; `dnf clean all` leaves an empty `/var/cache/libdnf5` (dnf5) and only `packages.db`,
  `expired_repos.json`, `tempfiles.json`, and `.gpgkeyschecked.yum` in `/var/cache/dnf` (dnf 4.14); every enabled
  repository's key is already in the RPM keyring, and `-y` also confirms importing a key a repository names. EL8's dnf
  was not checked.
- zypper facts from the `zypper-packages` change (branch `24-add-feature-zypper-packages`, design Context, checked
  2026-09-30 on `opensuse/leap:16.0` and `opensuse/tumbleweed`) [I here]: both images ship no `find`, `diff`, or `cmp`;
  `zypper install` alone refreshes through autorefresh, skips a failing repository, installs from the rest, and exits
  106 afterwards; `zypper --non-interactive refresh` exits 4 when any enabled repository fails;
  `zypper --non-interactive clean --all` leaves no file under `/var/cache/zypp`; in non-interactive mode zypper rejects
  a repository key the RPM database does not already hold.
- Implementation verification on 2026-10-03 (Asia/Tokyo): `dnf clean all` on `almalinux:9` leaves empty repository
  directories in addition to the four state files above; recursive inspection found no other file. The cache check
  therefore checks contents, allowing empty directories, rather than rejecting directories themselves. On `fedora:44`,
  `/usr/local/sbin` is a symlink to `bin`, so `command -v deno` returns `/usr/local/sbin/deno` because that PATH entry
  comes first; `readlink -f` identifies the same `/usr/local/bin/deno` executable. The tests check the canonical path.
  These corrections preserve the prerequisite-cache and installation-location contracts.
- Image configuration (`docker buildx imagetools inspect`) [I]: `fedora:44`, `almalinux:9`, and `almalinux:8` set
  `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`; `opensuse/leap:16.0` sets no `Env`, so Docker's
  default `PATH` applies. Its `created` field (2025-08-26) is a fixed timestamp; its labels name a build of 2026-09-28.
  `base:ubuntu24.04` is image 3.0.8, built on 2026-09-10 (read on 2026-10-01); the tag `base:ubuntu-24.04`, which
  earlier drafts named, was last built on 2025-10-16 (2.0.5) and is no longer rebuilt. All six images of Supported
  images publish amd64 and arm64.
- Arch Linux supports only full upgrades: the Arch Wiki says to never run `pacman -Sy`, and `pacman -Sy <package>` is an
  unsupported partial upgrade (https://wiki.archlinux.org/title/System_maintenance, as cited by the `pacman-packages`
  change, branch `23-add-feature-pacman-packages`) [I here], so installing `unzip` there means `pacman -Syu`.
- Precedent: the `glab` change (branch `13-add-feature-glab`, `src/glab/install.sh`) picks the package manager from the
  first word of `ID`, then `ID_LIKE`, that names a supported family.

## Goals / Non-Goals

**Goals:**

- Nothing is extracted or installed that was not verified: the archive's SHA-256 matches its `.zip.sha256sum` before
  `unzip` runs, and the extracted executable's SHA-256 matches `deno-<target>.sha256sum` before it is staged in
  `/usr/local/bin`. Each checksum file must hold one line whose name field equals the expected name (the asset name, or
  `deno`); the feature compares the hash field with its own `sha256sum` of the file it downloaded and never lets a
  checksum file choose which path is checked. Checked by reviewing `install.sh` and by the hand runs in Verifying
  failure scenarios.
- The scripts access only the URLs in the URL inventory below, over HTTPS; no option or environment variable redirects a
  download. Every request goes through `curl` with `--proto '=https' --proto-redir '=https'` and `--fail`, so a redirect
  cannot fall back to HTTP and an HTTP error status fails the request. Checked by running
  `grep -rn 'https\?://' src/deno` and a review of every `curl` call against the inventory.
- Every platform, option, and prerequisite check runs before the first network access, the package manager's included,
  so each failure scenario of Supported platforms, Option version, and Prerequisite packages downloads nothing; for
  Resolving latest only the pointer is fetched and no release archive is downloaded. Checked by the order in the scripts
  and the hand runs of those scenarios.
- `install.sh` is a single Bash script with `set -euo pipefail`. Supported images must already have Bash; the feature
  does not install it or provide custom errors on images without it. Platform checks run before option, prerequisite,
  and download handling. Distribution errors name the supported families. Checked by shellcheck, the compatibility
  matrix, and the hand runs below. A `main` function orders platform and option checks, prerequisites, version
  resolution, verified downloads, and installation. Each step keeps its working variables local; only platform selection
  and exit-trap state are shared.
- `/usr/local/bin/deno` is replaced by a rename within `/usr/local/bin` from a uniquely named staging file there, never
  written in place and never moved across filesystems; downloads live in a `mktemp -d` directory; an `EXIT` trap removes
  both, so a failure leaves no stray file (spec: Failed installation leaves the previous Deno). Packages the package
  manager installed before a later failure stay, as Prerequisite packages allows. Checked by the hand failure runs
  listing `/usr/local/bin` and the temporary directory afterwards.
- A second run acts only where the result would differ: the download is skipped, with a log line saying the version is
  already installed, when the second field of the first line of `/usr/local/bin/deno --version` equals the resolved
  version; `mkdir -p` and the group rule of Decisions are re-applied; no file is appended to. Checked by:
  - `test/deno/duplicate.sh`: the `version` proposals are `latest` and `2.8.0`, so the duplicate test installs `2.8.0`
    and then `latest` (Context), always two different versions, and asserts the version `latest` resolved to;
  - a `build` scenario from `debian:12` whose Dockerfile places a stub `/usr/local/bin/deno` that reports `2.8.0` and a
    plain executable in `/usr/local/share/deno/bin`, and which installs `version` `2.8.0`: the test asserts the stub is
    unchanged and the executable still runs by name;
  - a second `build` scenario with the same Dockerfile that installs `latest`: the test asserts the real Deno replaced
    the stub and the executable still runs by name.
- A package manager runs only when `curl` or `unzip` (`command -v`) or a CA bundle (the spec's four paths) is missing,
  and it is the family's own: exactly the install and clean-up calls of Decisions, non-interactive, with the clean-up
  run from the `EXIT` trap once the manager ran, on failure too. When one is missing and the family's manager is absent,
  the script fails before any network access (spec: Package manager missing). Checked by:
  - `test.sh` on every compatibility image and architecture: `curl` and `unzip` through `command -v`, a CA bundle
    through the four paths, and no repository metadata or package file left: `/var/lib/apt/lists` holds nothing but
    `lock`, `partial`, and `auxfiles`, and `/var/cache/apt/archives` holds no `*.deb` (a bash glob, not `find`);
    `/var/cache/dnf` and `/var/cache/libdnf5` hold no repository metadata or downloaded package: empty directories are
    allowed, and dnf 4 keeps only the four top-level state files named in Context; `/var/cache/zypp` holds no file;
  - the `build` scenario from `base:ubuntu24.04` whose Dockerfile saves the `dpkg-query -W` listing; its test compares
    that listing with the one after installation;
  - review of every package-manager call against Decisions, and the hand run "Package manager missing".
- `test.sh` and `duplicate.sh` call no `find` (openSUSE images ship none, Context) and no other command whose absence
  would turn a check into a silent pass: a check whose command is missing fails. The two tools directories are checked
  with `stat`, never recursively, and staging files in `/usr/local/bin` with a bash glob. Checked by review and by one
  run of `duplicate.sh`'s staging check that fails on purpose with a staging file present.
- The metadata holds `options.version`, the three `containerEnv` entries of the security review below, and the one
  `installsAfter` entry of Decisions, and nothing else that widens the container. `PATH` gets
  `/usr/local/share/deno/bin` after the image's own entries, so nothing the remote user writes there shadows a system
  command for root or later build steps. Checked by review against this document and `just validate`.

**Non-Goals:**

- The LTS channel, release candidates, and canary builds (served only from `dl.deno.land`).
- Partial versions such as `2.9`, which need the release list from the GitHub API.
- Distributions outside the Debian, Fedora, and openSUSE families (Arch Linux, Azure Linux and CBL-Mariner, Wolfi, SUSE
  Linux Enterprise and its BCI images), musl-based images, and a glibc transplant for them.
- Installing a missing prerequisite on an image whose only package manager is `microdnf`, such as `ubi9/ubi-minimal`
  (Decisions).
- A shared `DENO_DIR` cache; each user keeps Deno's default.
- Removing the prerequisite packages after installation.
- Anything `deno upgrade` does; it downloads outside the inventory and follows the binary's own channel.

## Decisions

- **Download from GitHub releases.** The archive and both checksum files come from
  `github.com/denoland/deno/releases/download/`. Rejected: `dl.deno.land/release/<version>/`, which mirrors the same
  stable files today but also serves LTS builds that can replace a stable build under the same number (upstream
  installer's comment), and would add a second download host. Rejected: upstream's installer
  `https://deno.land/install.sh`, which `feature-authoring.md` (Downloads) allows only saved to a file, never piped into
  a shell, with the spec stating that its content is not verified unless upstream publishes a checksum or signature for
  it; the script it serves also downloads from `dl.deno.land` (Context), bypassing the two checksum checks this feature
  makes. Rejected: distribution packages, which Deno's installation guide calls community maintained and often behind,
  with no official apt repository. Rejected: the npm `deno` package, which needs Node.js.
- **Resolve `latest` from `release-latest.txt`.** The endpoint upstream's own installer uses; one unauthenticated GET
  with a one-line body. After surrounding whitespace is removed, its value must match `^v[0-9]+\.[0-9]+\.[0-9]+$` before
  any URL is built from it. Rejected: the GitHub API, rate-limited to 60 unauthenticated requests per hour per IP, which
  CI runners and corporate NATs share, and JSON parsing without `jq` in the image. Rejected: reading the `Location` of
  `github.com/.../releases/latest`, a web redirect rather than a documented interface.
- **Verify both checksum files (maintainer decision).** The archive checksum protects `unzip` from a tampered archive;
  the executable checksum confirms the extraction produced the published binary. Both files come from the same release
  as the archive, so they prove integrity, and TLS to GitHub is the authenticity anchor. The cost is the installable
  range in Context. Rejected: requiring the archive checksum always and the executable checksum only when the release
  publishes it, which would open `2.0.1` to `2.7.13` (84 releases) at the same level of assurance; the maintainer chose
  both files, and a later MINOR change can revisit it. `feature-authoring.md` (Downloads) would also allow a release
  that publishes no checksum on TLS alone, stated as a Requirement; this feature is stricter and installs none. Rejected
  for v1: GitHub's release attestation, which covers only immutable releases and needs `gh` or Sigstore tooling in every
  image; a later MINOR change can add it. Rejected: `sha256sum -c` on the downloaded checksum file, which lets the
  file's name field pick the path to check.
- **Tell a missing checksum file from an unknown version.** Both checksum files are fetched before the archive. When
  either returns 404, one `HEAD` request on the archive URL decides the message: if the archive exists, the message
  names every missing checksum file (both for `1.x`, `.zip.sha256sum` for `2.0.0`, `deno-<target>.sha256sum` for `2.0.1`
  to `2.7.13`); if it does not, the message names the requested version and target. Rejected: treating every 404 as an
  unknown version, which misleads users of the 84 releases that exist but lack a checksum file.
- **Install as `/usr/local/bin/deno`.** Already on `PATH` for every user and named by Deno's installation guide as the
  system-wide choice. Rejected: `$HOME/.deno/bin` of the remote user, invisible to root and other users. Rejected: a
  versioned directory with a symlink, which adds a second path to keep consistent and is where the prior art broke on a
  second install.
- **Atomic replacement in place.** Stage the verified executable in `/usr/local/bin` under a unique hidden name with
  mode 0755, then rename it over `deno`. Rejected: writing `/usr/local/bin/deno` directly, which leaves a truncated
  binary on interruption and fails with "text file busy" while it runs. Rejected: `mv` from the temporary directory,
  which copies instead of renaming when `/tmp` is another filesystem.
- **Global tools in `/usr/local/share/deno`, appended to `PATH`.** `containerEnv` sets
  `DENO_INSTALL_ROOT=/usr/local/share/deno` and `PATH=${PATH}:/usr/local/share/deno/bin`; who may write the directory
  follows the next decision. Rejected: prepending the directory to `PATH`, which would let the remote user shadow `ls`,
  `git`, or `deno` for root shells and root lifecycle commands — a widening on images where that user has no `sudo`; the
  cost of appending is that a global tool named like a system command runs only by full path. Rejected: Deno's default
  `$HOME/.deno/bin`, which `containerEnv` cannot put on `PATH` because it is static JSON and the home is known only at
  build time. Rejected: editing users' shell rc files, which non-login and non-interactive processes skip and which
  needs marker guards.
- **Write access through a `deno` group (maintainer's CI report).** When `id -u` finds `_REMOTE_USER` and it is not
  root, the feature first checks any existing `deno` group before prerequisites or downloads. It rejects supplementary
  members other than `_REMOTE_USER` and any account using its GID as a primary group, including `_REMOTE_USER`: the CLI
  remaps that user's primary GID without updating the tools directories. The error names the account and leaves
  membership and the directories unchanged. An empty existing group or one containing only the remote user as a
  supplementary member is reused. The feature creates a system group `deno` if it is missing, adds `_REMOTE_USER` to it
  if not yet a member, and gives `/usr/local/share/deno` and `/usr/local/share/deno/bin` owner root, group `deno`, and
  mode 2775, so both are group-writable and new entries inherit the group. Membership is recorded by name, so it
  survives the CLI's UID and GID change (Context), as the node feature's `nvm` group does. When the remote user is root
  or absent, the feature creates no group and both directories are owned by root with mode 0755. A second install
  re-applies the group, owner, and mode to the two directories, never recursively, so tools already in `bin` keep their
  owner; creating the group and adding the member happen only when missing. Checked by `test.sh`, `duplicate.sh`, and
  the `exact_version` scenario asserting the owner, group, mode, and membership and installing a global tool as the
  remote user — on GitHub-hosted runners, where the CLI's own change to UID 1001 applies — and by a scenario on
  `base:ubuntu24.04` (`remoteUser` `vscode`) whose test changes `vscode`'s UID and GID with the same `/etc/passwd` and
  `/etc/group` edits as `updateUID.Dockerfile` through the image's `sudo`, then installs a global tool as `vscode` in a
  new process, so the remap is covered on a host whose UID is 1000 too; and by a `build` scenario from `almalinux:9`
  whose Dockerfile adds a user `devuser` with `useradd -m` and names it `remoteUser`, asserting group `deno`, mode 2775,
  the membership, and a global tool installed as `devuser`, so the group rule also runs outside Ubuntu, on dnf 4 only
  (every other added image runs as root; Risks). Rejected: making the tree owned by the remote user, the approved rule,
  which the CLI's UID change breaks because it chowns the home folder only. Rejected: mode 1777, which lets every user
  of the container write the directory on `PATH`. Rejected: a lifecycle command that chowns the tree at container start,
  which runs as the remote user without the privilege to chown a tree it does not own, and adds a lifecycle command to
  the metadata. Review fix approved in conversation on 2026-10-04 (Asia/Tokyo): fail on existing-group conflicts instead
  of granting unrelated accounts access or reusing a primary group. `test/deno/group_conflicts.sh` mounts the unmodified
  installer into a Debian 12 container and verifies the three conflict cases before any package or download request,
  safe reuse of an empty group, safe reinstall with supplementary membership after UID/GID remapping, and the
  root/absent-user paths. It is a host-side test run directly; failing builds cannot be CLI feature scenarios.
- **A feature-owned `/etc/profile.d/deno.sh` for login shells.** Debian's `/etc/profile` sets `PATH` from scratch, so a
  login shell on `debian:12` (`bash -l`) loses the `containerEnv` entry; the implementation found this while testing,
  and the maintainer chose this fix at the implementation review. The feature writes the whole file on every install
  (never appends to it), and the file appends `/usr/local/share/deno/bin` to `PATH` only when it is absent, so a second
  install adds nothing and a shell that already has the entry keeps one copy. Checked by a test that runs a global tool
  by name in `bash -l` as the remote user on `debian:12` and counts the directory in `PATH`. Rejected: narrowing the
  spec to shells that inherit the container environment, which leaves login shells on Debian without the tools.
  Rejected: editing `/etc/profile` or users' rc files.
- **`DENO_NO_UPDATE_CHECK=1`.** The feature owns the version; the update notice would point users to `deno upgrade`,
  which replaces a root-owned binary and bypasses verification.
- **Three families: Debian, Fedora, openSUSE (maintainer decision, 2026-09-30).** Deno needs only glibc 2.27 or newer
  and `libgcc_s` (Context), and within these families the images differ only in how a missing prerequisite is installed;
  outside Debian, only `unzip` was ever missing (Platform research). Rejected: Debian and Ubuntu only, the approved
  package's scope, which rejects images Deno runs on for no reason of Deno's. Rejected: Arch Linux, which installs a
  package only with `pacman -Syu`, a full system upgrade as the side effect of one prerequisite, on an image published
  for amd64 only. Rejected: Azure Linux and CBL-Mariner, a fourth manager (`tdnf`) and no `ID_LIKE`. Rejected: Wolfi,
  with `apk`, no bash, and no `getconf`. Rejected: matching the word `suse`, which would admit SUSE Linux Enterprise and
  BCI images nobody probed and whose repositories may not carry `unzip`; `opensuse` alone matches Leap (`suse opensuse`)
  and Tumbleweed (`opensuse suse`).
- **Family from `ID`, then `ID_LIKE`, the first word naming one wins.** `debian` and `ubuntu` name the Debian family;
  `fedora`, `rhel`, and `centos` the Fedora family, which covers CentOS Stream and UBI through `ID` and AlmaLinux, Rocky
  Linux, Oracle Linux, and Amazon Linux 2023 through `ID_LIKE`; `opensuse` the openSUSE family. It follows the `glab`
  change's loop (Context). Rejected: probing for package-manager commands, because images carry several (Fedora links
  `dnf`, `yum`, and `microdnf` to dnf5) and a manager alone does not name a family (`tdnf`).
- **`dnf` only in the Fedora family; no `microdnf`, no `yum` (maintainer decision, 2026-09-30).** Rejected: falling back
  to `microdnf` on minimal images, a different tool with different options whose `--setopt` support on EL8 to EL10 is
  unverified and which CI would cover in one generation only; the `dnf-packages` change rejects it too. On such an image
  a missing `unzip` fails with the Package manager missing message, and a user adds `unzip` to the image first.
  Rejected: a `yum` branch, which no supported image reaches: every probed Fedora-family image with glibc 2.27 or newer
  has `dnf` or `microdnf`, and `amazonlinux:2` fails the glibc check first.
- **Package manager required only when something is missing, checked before any network access.** Rejected: requiring it
  always, which would reject images that already have all three prerequisites, such as a minimal image with `unzip`
  added.
- **Exact package-manager calls.** Only the missing ones among `curl`, the CA package (`ca-certificates`;
  `ca-certificates-mozilla` for zypper, unverified because no planned image lacks a bundle), and `unzip` are named; they
  are constants, so no `--` is needed. The clean-up runs from the `EXIT` trap once the manager ran.

  | Manager | Install                                                                                                                   | Clean-up                                            |
  | ------- | ------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
  | apt     | `export DEBIAN_FRONTEND=noninteractive`, then `apt-get update` and `apt-get install -y --no-install-recommends <missing>` | `apt-get clean`, then `rm -rf /var/lib/apt/lists/*` |
  | dnf     | `dnf install -y --setopt=install_weak_deps=False <missing>`                                                               | `dnf clean all`                                     |
  | zypper  | `zypper --non-interactive refresh`, then `zypper --non-interactive --no-refresh install --no-recommends <missing>`        | `zypper --non-interactive clean --all`              |

  Rejected: zypper's autorefresh inside `install`, which skips a failing repository, installs from the rest, and fails
  only afterwards (Context); the strict refresh fails before anything is installed. Rejected: deleting dnf's cache
  directories by hand, which must track two layouts. Rejected: installing recommended or weak dependencies, which widen
  the image for nothing the feature uses.
- **CA bundle by file.** A bundle is present when one of the spec's four paths is a non-empty file (`-s` follows
  symlinks). Rejected: `dpkg-query`, `rpm -q`, or another package query per family: the package names differ, and an
  installed package is not the file `curl` reads. Rejected: one path per family, which `fedora:44` breaks (it lacks the
  EL path, Context). Rejected: a trial TLS request, which is network access before the checks.
- **Prerequisites from the family's package manager, only when missing, kept afterwards.** Rejected: Python's `zipfile`
  or busybox `unzip`, neither guaranteed in the images. Rejected: removing them afterwards, which could remove packages
  the user or another feature relies on.
- **One Bash installation script; Bash must already exist (maintainer decision, 2026-10-02).** Development images
  without Bash are outside the support boundary. The earlier POSIX entry point existed only to provide platform errors
  on those images; removing that guarantee removes the need for a helper script. Bash retains arrays, regular
  expressions, and `pipefail` for installation and verification.
- **Platform checks from the system.** The C library check (`getconf GNU_LIBC_VERSION`) precedes every other check, so a
  musl image never gets a distribution or architecture message: no glibc version and a `/lib/ld-musl-*` loader give the
  musl message, no glibc version without one gives the "not identified" message. The other checks each give their own
  message: `/etc/os-release` (the family, above), the glibc version against 2.27, and `uname -m` (`x86_64` → amd64,
  `aarch64` or `arm64` → arm64). Rejected: treating every `getconf` failure as musl, which misreports Wolfi (Context).
  Rejected: the command `dpkg --print-architecture`, which would tie the architecture check to one package manager.
- **`installsAfter: ["ghcr.io/devcontainers/features/common-utils"]`, no `dependsOn` (maintainer decision).** It orders
  this feature after common-utils when both are installed, so a remote user common-utils creates exists before the group
  rule runs; it installs nothing on its own and adds no privilege. The ref carries no tag because the Dev Container spec
  does not allow an `installsAfter` entry to be pinned to a tag or digest; `just validate` checks only in-repo refs, and
  `feature-authoring.md`'s "major tag" rule for external features applies to `dependsOn`. The Dev Container CLI resolves
  that ref's metadata at build time (URL inventory). Rejected: no `installsAfter`, which leaves a user common-utils
  creates in the same build with a root-owned tools tree. Rejected: `dependsOn`, which would install common-utils, and
  its user and packages, for every user of this feature.

## Options

The delta spec's Option requirement is the contract; `proposals` and `description` live in
`src/deno/devcontainer-feature.json`.

| Name      | Type     | Default    | Enum or proposals              | Meaning                                                                                               |
| --------- | -------- | ---------- | ------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","2.8.0"]` | Deno release to install: `latest`, resolved from `release-latest.txt` at build time, or exact `X.Y.Z` |

- **Default `latest`.** proposal.md (Why) asks for the version the container's author chooses or the latest release, so
  a configuration that omits `version` follows upstream's current stable release. The trade-off is the pointer race in
  Risks, which a pinned `version` avoids.
- **Proposals, not an enum.** Every exact release with both checksum files is valid, and each new release adds one.
  `2.8.0` is the first proposal that is not the default, so the duplicate test installs it (Context, Goals).
- **One spelling of an exact version (maintainer decision).** `version` accepts `latest` or `X.Y.Z`; `v2.9.7` fails like
  any other value, with the message naming the accepted forms. Rejected: accepting the `v` prefix as a second spelling,
  which complicates the option's proposals and error message for no new capability.
- Rejected: partial versions such as `2.9` and the LTS, release candidate, and canary channels (Non-Goals). Rejected: an
  option that takes a download URL, a mirror, or credentials, which would let configuration redirect a verified download
  (Goals).

## Supported images

Planned `test/deno/compatibility.json` (the spec never lists images): the two approved images, one image per added
family or package-manager generation, and the glibc-floor canary; six images on two architectures, twelve CI jobs plus
the scenario job.

| Image                                              | Arch         | `remoteUser` | Covers                                                                                                    |
| -------------------------------------------------- | ------------ | ------------ | --------------------------------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64 | `vscode`     | Prerequisites present; non-root remote user in group `deno`, its UID changed in CI                        |
| `debian:12`                                        | amd64, arm64 | (none, root) | apt: `curl`, `unzip`, and the CA bundle missing; root owns the global tools tree                          |
| `fedora:44`                                        | amd64, arm64 | (none, root) | dnf5, family from `ID`; only `unzip` missing; CA bundle only outside the EL path                          |
| `almalinux:9`                                      | amd64, arm64 | (none, root) | dnf 4, family from `ID_LIKE`; only `unzip` missing; CA bundle at the EL path                              |
| `almalinux:8`                                      | amd64, arm64 | (none, root) | glibc floor canary (maintainer decision): glibc 2.28, the lowest in scope; EL8's dnf; only the EL CA path |
| `opensuse/leap:16.0`                               | amd64, arm64 | (none, root) | zypper; only `unzip` missing; CA bundle at `/etc/ssl/ca-bundle.pem`; no `find`; no `PATH` in its config   |

The lowest glibc in the list is 2.28 (`almalinux:8`), one minor release above the floor; Deno 2.9.7 ran on 2.27 itself
only in `ubuntu:18.04` (Context), a release out of standard support. On amd64 the Deno binary ran on all six [T]; the
feature ran on the first two in PR #30's local runs and CI, on both architectures, before this revision. On the four
added images the feature's run is inferred, and so is every arm64 run of this revision, until CI runs (Verification).

**Six images, no seventh.** The maintainer left a seventh image to the evidence: a second Fedora-family code path, if
one exists. The Fedora family's branches in the feature are the family match (by `ID` or through `ID_LIKE`), the CA path
found, and the dnf generation with its cache layout: `fedora:44` covers dnf5 with the family from `ID` and no EL path,
`almalinux:9` dnf 4 with the family from `ID_LIKE` and the EL path, and `almalinux:8` the same path at the glibc floor.
Rejected: `amazonlinux:2023`, `oraclelinux:9`, and `rockylinux/rockylinux:9`, which take the family through `ID_LIKE`
like `almalinux:9`, and `quay.io/centos/centos:stream9` and `ubi9/ubi`, which take it from `ID` like `fedora:44`: each
has `dnf`, `curl`, and a CA bundle at a path already covered, so none reaches a branch the list does not (that their
`dnf` is dnf 4 is inferred from their EL or Amazon Linux base). Rejected: a `microdnf`-only image, which is unsupported
(Decisions); its failure is a hand run.

Every scenario image is `base:ubuntu24.04` or `debian:12` on amd64, including the `build` scenarios named in Goals,
except the `build` scenario from `almalinux:9` for the group rule (Decisions). `test.sh` compares `deno --version` with
the latest pointer read at test time (Risks).

## Verification

Maintainer decision (2026-09-30), in place of a full local `just test deno` that `openspec/config.yaml` (`rules.tasks`)
asks for, for this feature only: `just test deno` runs locally only with `--image` for `base:ubuntu24.04` and
`debian:12` on amd64. The four added images and every arm64 job are verified by CI's jobs on the PR, each result
recorded in the PR's Validation section. Rejected: a full local `just test deno`, which pulls all six images, while CI
runs the same jobs on both architectures.

The decision names neither the scenario job, which now also builds from `almalinux:9` (Supported images), nor the hand
runs of Verifying failure scenarios, which use Alpine with Bash, Debian with `getconf` hidden, `archlinux:latest`,
`debian:9`, and `almalinux:9` locally; both are Open Question 1.

## Verifying failure scenarios

A failing build cannot be a feature test, so each failure scenario of the spec is a hand run recorded in the PR's
Validation with the image, the input, the exit status, and the message. Every hand run executes the unmodified
`src/deno/install.sh`, either through the Dev Container CLI with a scratch configuration or as root in `docker run` with
`src/deno` mounted and the option passed as `VERSION`. Where a download must misbehave, the run image puts a test-only
`curl` wrapper in `/usr/local/sbin`, ahead of `/usr/bin` on `PATH`; it alters only the named response, so no option or
environment variable of the feature redirects anything.

| Spec scenario                         | Trigger                                                                                                                           |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Partial version rejected              | `version` `2.9` on `debian:12`                                                                                                    |
| Malformed latest-release pointer      | `version` `latest`; the wrapper returns `not-a-version` for `release-latest.txt`                                                  |
| Archive checksum mismatch             | The wrapper flips one byte of the archive                                                                                         |
| Executable checksum mismatch          | The wrapper serves a repacked archive with an altered `deno` and a `.zip.sha256sum` computed for that archive                     |
| Release without both checksum files   | `version` `2.5.0`, `2.0.0`, and `1.46.3`                                                                                          |
| Unknown version                       | `version` `9.9.9`                                                                                                                 |
| Failure over an existing installation | Every wrapper run starts from an image where the feature already installed `2.8.0`; afterwards `deno --version` and both listings |
| musl-based image                      | `alpine` with Bash installed                                                                                                      |
| C library not identified              | `debian:12` with `getconf` hidden                                                                                                 |
| Unsupported distribution              | `archlinux:latest`                                                                                                                |
| glibc older than 2.27                 | `debian:9` (glibc 2.24)                                                                                                           |
| Unsupported architecture              | `almalinux:9` as `linux/s390x` under QEMU user emulation, when the host has it; otherwise recorded as checked by review only      |
| Package manager missing               | `almalinux:9` with `/usr/bin/dnf*` and `/usr/bin/yum` removed, so it lacks `unzip` and `dnf`                                      |
| Root or absent remote user (absent)   | `_REMOTE_USER` set to a user that does not exist, on `debian:12`                                                                  |

## Security review

- **Downloads:** three files per install from GitHub releases (plus one `HEAD` request on the archive URL when a
  checksum file is missing), one pointer from `dl.deno.land` when `version` is `latest`, and packages from the image's
  own repositories through its family's package manager when a prerequisite is missing (URL inventory). The feature adds
  no repository and no key. Under `-y`, dnf imports on first use a key a configured repository names; on `fedora:44` and
  `almalinux:9` every enabled repository's key is already in the RPM keyring (Context), so no import is expected there;
  EL8 was not checked (Risks). zypper in non-interactive mode never trusts a new key on its own.
- **Verification:** SHA-256 of the archive before extraction and of the executable before installation, both against
  checksum files of the same release; the latest pointer is format-checked, and whatever release it names is verified
  the same way. The pointer and the checksum files themselves rest on TLS alone, which the spec states in its Resolving
  latest and Verified download requirements, as `feature-authoring.md` (Downloads) demands.
- **Keys:** none. Deno signs nothing the feature can check without extra tooling; authenticity rests on TLS to
  `github.com` and `release-assets.githubusercontent.com` (Risks).
- **Metadata:** `containerEnv` only — `DENO_INSTALL_ROOT` and `PATH` so global tools land on `PATH` for every shell,
  appended so they never shadow a system command, and `DENO_NO_UPDATE_CHECK` so Deno never offers to replace the
  verified binary. No `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, lifecycle commands, or
  `dependsOn`; `installsAfter` names common-utils only for ordering (Decisions). Outside the metadata, the feature
  writes one root-owned file, `/etc/profile.d/deno.sh`, that only appends the tools directory to `PATH` in login shells
  (Decisions).
- **Users and groups:** one new system group, `deno`, created only for a non-root remote user; its only member the
  feature adds is the remote user, and it grants write access to `/usr/local/share/deno` and its `bin` only (Decisions).
  Before reusing an existing group, its supplementary and primary-group users are checked to reject unrelated accounts
  and the remote user's primary group; the check precedes package installation and Deno downloads.
- **Idempotency:** Goals above; the spec's Installing twice requirement is what `duplicate.sh` and the two reinstall
  `build` scenarios assert. The group and the membership are created only when missing, and a second install re-applies
  the group, owner, and mode of the two directories (Decisions).
- **Failure behavior:** the spec's Option version, Resolving latest, Verified download, Failed installation, and
  Supported platforms requirements; every failure exits non-zero with a message on stderr and leaves the previous
  binary.

## URL inventory

Every URL the feature's scripts access. `<version>` is the resolved `X.Y.Z`; `<target>` is `x86_64-unknown-linux-gnu` or
`aarch64-unknown-linux-gnu`. Nothing is accessed at container start: the feature defines no lifecycle command, and
Deno's own update check is disabled. The one OCI ref the feature names, in `installsAfter`, is resolved by the Dev
Container CLI, not by the feature's scripts.

| URL / template                                                                                                                                                                                             | Purpose                                                            | When                                                                                                     | Integrity / authenticity                                                                                                                                          | Official source evidence                                                                                                                                                                                                                                  | Verified                                                                                                              |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `https://dl.deno.land/release-latest.txt`                                                                                                                                                                  | Resolve `latest` to a version                                      | Build, only when `version` is `latest`                                                                   | HTTPS; body must match `^v[0-9]+\.[0-9]+\.[0-9]+$` after trimming; unsigned, so it can only select another published release, which is then checksum-verified     | https://github.com/denoland/deno_install/blob/41d4676f8677ec16449b9e2303e7bd52ed81f03b/install.sh (reads it to resolve the latest version); https://docs.deno.com/runtime/fundamentals/stability_and_releases/ ("Deno's download server at dl.deno.land") | 2026-09-30: HTTP 200, no redirect, final host `dl.deno.land`, body `v2.9.7`                                           |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip`                                                                                                                          | Release archive holding the `deno` executable                      | Build, unless the requested version is installed; a `HEAD` request only, when a checksum file is missing | SHA-256 against the `.zip.sha256sum` row; the extracted executable against the `deno-<target>.sha256sum` row                                                      | https://docs.deno.com/runtime/getting_started/installation/ (Manual download: archives at github.com/denoland/deno/releases, Linux asset names)                                                                                                           | 2026-09-30: `v2.9.7`, both targets, HTTP 200 after a redirect to `release-assets.githubusercontent.com`; `v9.9.9` 404 |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`                                                                                                                | Checksum of the archive                                            | Build, before the archive                                                                                | HTTPS only; same release as the archive, so integrity, not authenticity; name field must equal the asset name                                                     | https://docs.deno.com/runtime/getting_started/installation/ ("Each asset has a matching `.sha256sum` file")                                                                                                                                               | 2026-09-30: `v2.9.7`, both targets, HTTP 200, final host `release-assets.githubusercontent.com`, `<hex>  <asset>.zip` |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`                                                                                                                    | Checksum of the extracted executable                               | Build, before the archive                                                                                | HTTPS only; same release as the archive; name field must equal `deno`                                                                                             | https://github.com/denoland/deno/releases/expanded_assets/v2.9.7 and `https://api.github.com/repos/denoland/deno/releases/tags/v2.9.7` (asset list of the release)                                                                                        | 2026-09-30: `v2.9.7`, both targets, HTTP 200, final host `release-assets.githubusercontent.com`, `<hex>  deno`        |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<id>/<uuid>?…`                                                                                                               | Redirect target of the three GitHub rows (signed, short-lived URL) | Build, followed from the rows above                                                                      | TLS; content checked as in the rows above                                                                                                                         | https://api.github.com/meta (lists `release-assets.githubusercontent.com` among GitHub's domains)                                                                                                                                                         | 2026-09-30: observed as the final host of all six `v2.9.7` Linux asset URLs                                           |
| `ghcr.io/devcontainers/features/common-utils` (OCI ref in `installsAfter`)                                                                                                                                 | Order this feature after common-utils when both are installed      | Build, by the Dev Container CLI resolving the feature set; installs nothing unless the user installs it  | OCI registry over HTTPS; the CLI reads its metadata only, and nothing from it runs unless the user installs common-utils                                          | https://github.com/devcontainers/features/tree/main/src/common-utils (official reference collection, published to `ghcr.io/devcontainers/features`)                                                                                                       | 2026-09-30: `devcontainer features info manifest` (CLI 0.89.0) returned the manifest, `common-utils` version `2.7.0`  |
| The image's configured apt, dnf, or zypper repositories (for the Debian-family images `deb.debian.org`, `archive.ubuntu.com`, or `ports.ubuntu.com`; for the others the hosts their repository files name) | `curl`, the CA package, `unzip` when missing                       | Build, only when one is missing                                                                          | apt's signed `Release` files, dnf's package signatures, or zypper's signed `repomd.xml`, with the keys the image ships; the feature adds no repository and no key | Not applicable: the image, not the feature, chooses these hosts                                                                                                                                                                                           | Not fetched: depends on the image                                                                                     |

## Risks / Trade-offs

- [The checksum files come from the same place as the archive, so a compromised release is not detected] → TLS to GitHub
  is the anchor, as for every checksum-verified feature; GitHub's release attestation is the upgrade path once it is
  worth tooling in the image (Decisions).
- [`release-latest.txt` can name a version before its GitHub assets are uploaded] → The download fails with a missing
  file and the previous binary stays; rebuilding later succeeds. A pinned `version` avoids it.
- [The latest pointer could name an LTS-only or yanked version] → It is format-checked, and a version without both
  checksum files on GitHub fails before anything is installed.
- [An executable already at `/usr/local/bin/deno` with the requested version but from another source, such as an LTS
  build, is kept] → Accepted: the skip rule compares versions only; a user who needs this feature's binary installs a
  different version once or removes the file.
- [Requiring both checksum files excludes releases `2.0.1` to `2.7.13`] → The failure names the missing file; a later
  MINOR change can open that range (Decisions).
- [A non-root remote user created after this feature runs gets a root-owned tools tree] → `deno install --global` then
  needs `sudo`; `installsAfter` orders this feature after common-utils, the usual creator of that user, and a user
  created by anything ordered later still gets the root-owned tree.
- [Files a global tool creates are owned by the user who ran `deno install --global`, after a UID change the new UID,
  and the setgid bit gives new entries group `deno` but passes itself on to new directories only; whether a new file or
  directory is group-writable depends on that user's umask] → Accepted: the remote user installs and replaces its own
  tools, and write access to `bin` is what removing or adding an entry needs.
- [`test.sh` reads the latest pointer at test time, so a Deno release between build and test fails that run once] →
  Accepted: the window is minutes and a rerun passes; capturing the value at build time would need the feature to write
  state only a test reads.
- [The failure scenarios are hand runs, so CI does not guard them against regressions] → Accepted: a failing build
  cannot be a feature test; review of each change to the scripts re-checks the order of checks and the verification.
- [Upstream renames assets or moves downloads] → The download fails loudly; the fix is a PATCH that updates the
  Requirement's URL.
- [Nothing of this revision has run on arm64, and the feature has not run on the four added images] → CI runs every
  image on both architectures before the PR is marked ready (Verification), and a red job keeps it from being marked
  ready.
- [dnf's `-y` also confirms importing a key a configured repository names, and EL8's keyring was not checked] →
  Accepted: the feature adds no repository; a key that fails verification still fails the install.
- [A failing enabled zypper repository] → The strict refresh fails the build before anything is installed (Decisions).
- [The group rule runs in no openSUSE or dnf5 job (every such image runs as root), and whether `opensuse/leap:16.0`
  ships `groupadd` and `usermod` was not probed] → A missing tool fails the build loudly for a non-root remote user;
  NOTES.md names the requirement. The `build` scenario from `almalinux:9` covers the rule on dnf 4 only.
- [openSUSE images ship no `find`, and a `$(find …)` check passes silently when `find` is missing] → The tests call no
  `find` (Goals).
- [`opensuse/leap:16.0` sets no `PATH` in its configuration, so whether `containerEnv`'s `${PATH}` yields the six system
  entries there is inferred] → `test.sh`'s `PATH` check runs on it in CI.
- [An end-of-life release of a supported family, such as Debian 11, passes the platform checks and fails at its package
  manager] → Accepted: the failure is loud; NOTES.md says that only current releases are expected to work.
- [A bundle at one of the four paths that `curl` was not built to read] → `curl` fails TLS loudly on the first request,
  before anything is downloaded from Deno.
- [The glibc floor of 2.27 comes from Deno's current build (Context), and a later release could raise it] → The current
  script runs the staged executable's `--version` before the rename, so such a release fails the installation and leaves
  the previous binary; a PATCH raises the check.

## Open Questions

1. The maintainer's verification decision names `just test deno` and two local images. Does `just test-scenarios deno`,
   which now includes a `build` scenario from `almalinux:9`, run locally as `rules.tasks` asks, or is it, like the added
   images, verified by CI's scenario job only? And do the failure hand runs on Alpine with Bash, Debian with `getconf`
   hidden, `archlinux:latest`, `debian:9`, and `almalinux:9` (the last also as `linux/s390x` and with `dnf` removed),
   which a failing build cannot move to CI, run locally?

The maintainer decided the other questions (Decisions: `installsAfter`, the three families, `dnf` only; Options: one
spelling of an exact version; Supported images: `almalinux:8`; Verification).

## Revision of 2026-09-30

This revision widens the approved package to three families, drops `microdnf`, adds `almalinux:8`, and records the
verification decision; `tasks.md` is revised after the maintainer approves it again, and the version stays `1.0.0`.
