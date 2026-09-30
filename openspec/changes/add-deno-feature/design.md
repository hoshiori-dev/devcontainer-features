# Design

## Context

See proposal.md - Why. The behavior contract is `specs/deno/spec.md`; this document names how it is reached. Facts below
were checked on 2026-09-30 unless marked otherwise.

- `deno` is the repository's first feature: `src/` does not exist yet, and the README says no feature has been
  published. `just new-feature deno` scaffolds `version` (default `latest`) and the two images planned below.
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
- `debian:12` ships bash and `libgcc_s` but no `curl`, `unzip`, or CA bundle; `base:ubuntu-24.04` has all three through
  the common-utils feature it is built with. `bash` is an Essential package on Debian and Ubuntu, so every image that
  passes the platform checks has it; stock `alpine` has no bash, so a `#!/usr/bin/env bash` script fails there with
  `env: can't execute 'bash'` before its first line runs.
- The Dev Container CLI's duplicate test (CLI 0.89.0) gives a string option with `proposals` the first proposal that is
  not the default, unless `--permit-randomization` is passed, which `scripts/test_feature.ts` does not do.
- Prior art `ghcr.io/devcontainers-extra/features/deno` 1.0.4 verifies no checksum, fails a second install on a plain
  `ln -s`, and does not install `unzip`; nothing is taken from it.

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
- Every platform and option check runs before the first network access, apt included, so each failure scenario of
  Supported platforms and Version selection downloads nothing. Checked by the order in the scripts and the hand runs of
  those scenarios.
- `install.sh` is POSIX `sh` with `set -eu` and holds only the platform checks; once they pass it `exec`s `bash` on a
  script in `src/deno/scripts/` that holds the rest with `set -euo pipefail`, so an image without bash still gets the
  platform message. Checked by shellcheck in `just check` and the hand run on `alpine`.
- `/usr/local/bin/deno` is replaced by a rename within `/usr/local/bin` from a uniquely named staging file there, never
  written in place and never moved across filesystems; downloads live in a `mktemp -d` directory; an `EXIT` trap removes
  both, so a failure leaves no stray file (spec: Failed installation leaves the previous Deno). Packages apt installed
  before a later failure stay, as Prerequisite packages allows. Checked by the hand failure runs listing
  `/usr/local/bin` and the temporary directory afterwards.
- A second run acts only where the result would differ: the download is skipped, with a log line saying the version is
  already installed, when the second field of the first line of `/usr/local/bin/deno --version` equals the resolved
  version; `mkdir -p` and the ownership rule are re-applied; no file is appended to. Checked by:
  - `test/deno/duplicate.sh`: the `version` proposals are `latest` and `2.8.0`, so the duplicate test installs `2.8.0`
    and then `latest` (Context), always two different versions, and asserts the version `latest` resolved to;
  - a `build` scenario from `debian:12` whose Dockerfile places a stub `/usr/local/bin/deno` that reports `2.8.0` and a
    plain executable in `/usr/local/share/deno/bin`, and which installs `version` `2.8.0`: the test asserts the stub is
    unchanged and the executable still runs by name;
  - a second `build` scenario with the same Dockerfile that installs `latest`: the test asserts the real Deno replaced
    the stub and the executable still runs by name.
- apt runs only when one of `curl`, `ca-certificates`, `unzip` is missing — `command -v` for `curl` and `unzip`,
  `dpkg-query` reporting `ca-certificates` as installed for the CA bundle — non-interactively, and its lists are removed
  afterwards. Checked by the tests on `debian:12` (all missing, all present afterwards) and a `build` scenario from
  `base:ubuntu-24.04` whose Dockerfile saves the `dpkg-query -W` listing; its test compares that listing with the one
  after installation.
- The metadata holds `options.version`, the three `containerEnv` entries of the security review below, and the one
  `installsAfter` entry of Decisions, and nothing else that widens the container. `PATH` gets
  `/usr/local/share/deno/bin` after the image's own entries, so nothing the remote user writes there shadows a system
  command for root or later build steps. Checked by review against this document and `just validate`.

**Non-Goals:**

- The LTS channel, release candidates, and canary builds (served only from `dl.deno.land`).
- Partial versions such as `2.9`, which need the release list from the GitHub API.
- Distributions outside the Debian family, musl-based images, and a glibc transplant for them.
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
  `DENO_INSTALL_ROOT=/usr/local/share/deno` and `PATH=${PATH}:/usr/local/share/deno/bin`; the directory tree, `bin`
  included, is owned by `_REMOTE_USER` when `id -u` finds that user and it is not root, otherwise by root. Rejected:
  prepending the directory to `PATH`, which would let the remote user shadow `ls`, `git`, or `deno` for root shells and
  root lifecycle commands — a widening on images where that user has no `sudo`; the cost of appending is that a global
  tool named like a system command runs only by full path. Rejected: Deno's default `$HOME/.deno/bin`, which
  `containerEnv` cannot put on `PATH` because it is static JSON and the home is known only at build time. Rejected:
  editing shell rc files, which non-login and non-interactive processes skip and which needs marker guards. Rejected: a
  group-writable directory with a new group, more moving parts for the single remote user a dev container has.
- **`DENO_NO_UPDATE_CHECK=1`.** The feature owns the version; the update notice would point users to `deno upgrade`,
  which replaces a root-owned binary and bypasses verification.
- **Prerequisites from apt, only when missing, kept afterwards.** `curl`, `ca-certificates`, and `unzip` through
  `apt-get install --no-install-recommends`. Rejected: Python's `zipfile` or busybox `unzip`, neither guaranteed in the
  images. Rejected: removing them afterwards, which could remove packages the user or another feature relies on.
- **POSIX `sh` entry point, bash for the rest.** The maintainer chose bash; `install.sh` stays POSIX only so the
  platform checks run on images that lack bash, and hands over with `exec bash`. Rejected: bash throughout, which fails
  on stock Alpine before any check. Rejected: POSIX `sh` throughout, which gives up `pipefail` for the download and
  verification logic.
- **Platform checks from the system.** The C library check (`getconf GNU_LIBC_VERSION`; failure means not glibc, so the
  musl message) precedes every other check, so a musl image never gets a distribution or architecture message. The other
  checks each give their own message: `/etc/os-release` (`ID` or `ID_LIKE` naming `debian` or `ubuntu`), the glibc
  version against 2.27, and `uname -m` (`x86_64` → amd64, `aarch64` or `arm64` → arm64). Rejected: the command
  `dpkg --print-architecture`, which would tie the architecture check to the package manager; it is used nowhere else.
- **`installsAfter: ["ghcr.io/devcontainers/features/common-utils"]`, no `dependsOn` (maintainer decision).** It orders
  this feature after common-utils when both are installed, so a remote user common-utils creates exists before the
  ownership rule runs; it installs nothing on its own and adds no privilege. The ref carries no tag because the Dev
  Container spec does not allow an `installsAfter` entry to be pinned to a tag or digest; `just validate` checks only
  in-repo refs, and `feature-authoring.md`'s "major tag" rule for external features applies to `dependsOn`. The Dev
  Container CLI resolves that ref's metadata at build time (URL inventory). Rejected: no `installsAfter`, which leaves a
  user common-utils creates in the same build with a root-owned tools tree. Rejected: `dependsOn`, which would install
  common-utils, and its user and packages, for every user of this feature.
- **One spelling of an exact version (maintainer decision).** `version` accepts `latest` or `X.Y.Z`; `v2.9.7` fails like
  any other value, with the message naming the accepted forms. Rejected: accepting the `v` prefix as a second spelling,
  which complicates the option's proposals and error message for no new capability.

## Supported images

Planned `test/deno/compatibility.json` (the spec never lists images):

| Image                                               | Arch         | `remoteUser` | Covers                                                                 |
| --------------------------------------------------- | ------------ | ------------ | ---------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | amd64, arm64 | `vscode`     | Prerequisites present; non-root remote user owns the global tools tree |
| `debian:12`                                         | amd64, arm64 | (none, root) | Prerequisites missing; root owns the global tools tree                 |

Both have glibc well above 2.27 (2.39 and 2.36). Every scenario image is `base:ubuntu-24.04` or `debian:12` on amd64,
including the `build` scenarios named in Goals. `test.sh` compares `deno --version` with the latest pointer read at test
time (Risks).

## Verifying failure scenarios

A failing build cannot be a feature test, so each failure scenario of the spec is a hand run recorded in the PR's
Validation with the image, the input, the exit status, and the message. Every hand run executes the unmodified
`src/deno/install.sh`, either through the Dev Container CLI with a scratch configuration or as root in `docker run` with
`src/deno` mounted and the option passed as `VERSION`. Where a download must misbehave, the run image puts a test-only
`curl` wrapper in `/usr/local/sbin`, ahead of `/usr/bin` on `PATH`; it alters only the named response, so no option or
environment variable of the feature redirects anything.

| Spec scenario                          | Trigger                                                                                                                           |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Partial version rejected               | `version` `2.9` on `debian:12`                                                                                                    |
| Malformed latest-release pointer       | `version` `latest`; the wrapper returns `not-a-version` for `release-latest.txt`                                                  |
| Archive checksum mismatch              | The wrapper flips one byte of the archive                                                                                         |
| Executable checksum mismatch           | The wrapper serves a repacked archive with an altered `deno` and a `.zip.sha256sum` computed for that archive                     |
| Release without both checksum files    | `version` `2.5.0`, `2.0.0`, and `1.46.3`                                                                                          |
| Unknown version                        | `version` `9.9.9`                                                                                                                 |
| Failure over an existing installation  | Every wrapper run starts from an image where the feature already installed `2.8.0`; afterwards `deno --version` and both listings |
| musl-based image                       | `alpine`                                                                                                                          |
| Distribution outside the Debian family | `fedora`                                                                                                                          |
| glibc older than 2.27                  | `debian:9` (glibc 2.24)                                                                                                           |
| Unsupported architecture               | `debian:12` as `linux/s390x` under QEMU user emulation, when the host has it; otherwise recorded as checked by review only        |
| Root or absent remote user (absent)    | `_REMOTE_USER` set to a user that does not exist, on `debian:12`                                                                  |

## Security review

- **Downloads:** three files per install from GitHub releases (plus one `HEAD` request on the archive URL when a
  checksum file is missing), one pointer from `dl.deno.land` when `version` is `latest`, and apt packages from the
  image's own sources when a prerequisite is missing (URL inventory).
- **Verification:** SHA-256 of the archive before extraction and of the executable before installation, both against
  checksum files of the same release; the latest pointer is format-checked, and whatever release it names is verified
  the same way. The pointer and the checksum files themselves rest on TLS alone, which the spec states in its Version
  selection and Verified download requirements, as `feature-authoring.md` (Downloads) demands.
- **Keys:** none. Deno signs nothing the feature can check without extra tooling; authenticity rests on TLS to
  `github.com` and `release-assets.githubusercontent.com` (Risks).
- **Metadata:** `containerEnv` only — `DENO_INSTALL_ROOT` and `PATH` so global tools land on `PATH` for every shell,
  appended so they never shadow a system command, and `DENO_NO_UPDATE_CHECK` so Deno never offers to replace the
  verified binary. No `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, lifecycle commands, or
  `dependsOn`; `installsAfter` names common-utils only for ordering (Decisions).
- **Idempotency:** Goals above; the spec's Installing twice requirement is what `duplicate.sh` and the two reinstall
  `build` scenarios assert.
- **Failure behavior:** the spec's Version selection, Verified download, Failed installation, and Supported platforms
  requirements; every failure exits non-zero with a message on stderr and leaves the previous binary.

## URL inventory

Every URL the feature's scripts access. `<version>` is the resolved `X.Y.Z`; `<target>` is `x86_64-unknown-linux-gnu` or
`aarch64-unknown-linux-gnu`. Nothing is accessed at container start: the feature defines no lifecycle command, and
Deno's own update check is disabled. The one OCI ref the feature names, in `installsAfter`, is resolved by the Dev
Container CLI, not by the feature's scripts.

| URL / template                                                                                                            | Purpose                                                            | When                                                                                                     | Integrity / authenticity                                                                                                                                      | Official source evidence                                                                                                                                                                                                                                  | Verified                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| `https://dl.deno.land/release-latest.txt`                                                                                 | Resolve `latest` to a version                                      | Build, only when `version` is `latest`                                                                   | HTTPS; body must match `^v[0-9]+\.[0-9]+\.[0-9]+$` after trimming; unsigned, so it can only select another published release, which is then checksum-verified | https://github.com/denoland/deno_install/blob/41d4676f8677ec16449b9e2303e7bd52ed81f03b/install.sh (reads it to resolve the latest version); https://docs.deno.com/runtime/fundamentals/stability_and_releases/ ("Deno's download server at dl.deno.land") | 2026-09-30: HTTP 200, no redirect, final host `dl.deno.land`, body `v2.9.7`                                           |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip`                                         | Release archive holding the `deno` executable                      | Build, unless the requested version is installed; a `HEAD` request only, when a checksum file is missing | SHA-256 against the `.zip.sha256sum` row; the extracted executable against the `deno-<target>.sha256sum` row                                                  | https://docs.deno.com/runtime/getting_started/installation/ (Manual download: archives at github.com/denoland/deno/releases, Linux asset names)                                                                                                           | 2026-09-30: `v2.9.7`, both targets, HTTP 200 after a redirect to `release-assets.githubusercontent.com`; `v9.9.9` 404 |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.zip.sha256sum`                               | Checksum of the archive                                            | Build, before the archive                                                                                | HTTPS only; same release as the archive, so integrity, not authenticity; name field must equal the asset name                                                 | https://docs.deno.com/runtime/getting_started/installation/ ("Each asset has a matching `.sha256sum` file")                                                                                                                                               | 2026-09-30: `v2.9.7`, both targets, HTTP 200, final host `release-assets.githubusercontent.com`, `<hex>  <asset>.zip` |
| `https://github.com/denoland/deno/releases/download/v<version>/deno-<target>.sha256sum`                                   | Checksum of the extracted executable                               | Build, before the archive                                                                                | HTTPS only; same release as the archive; name field must equal `deno`                                                                                         | https://github.com/denoland/deno/releases/expanded_assets/v2.9.7 and `https://api.github.com/repos/denoland/deno/releases/tags/v2.9.7` (asset list of the release)                                                                                        | 2026-09-30: `v2.9.7`, both targets, HTTP 200, final host `release-assets.githubusercontent.com`, `<hex>  deno`        |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<id>/<uuid>?…`                              | Redirect target of the three GitHub rows (signed, short-lived URL) | Build, followed from the rows above                                                                      | TLS; content checked as in the rows above                                                                                                                     | https://api.github.com/meta (lists `release-assets.githubusercontent.com` among GitHub's domains)                                                                                                                                                         | 2026-09-30: observed as the final host of all six `v2.9.7` Linux asset URLs                                           |
| `ghcr.io/devcontainers/features/common-utils` (OCI ref in `installsAfter`)                                                | Order this feature after common-utils when both are installed      | Build, by the Dev Container CLI resolving the feature set; installs nothing unless the user installs it  | OCI registry over HTTPS; the CLI reads its metadata only, and nothing from it runs unless the user installs common-utils                                      | https://github.com/devcontainers/features/tree/main/src/common-utils (official reference collection, published to `ghcr.io/devcontainers/features`)                                                                                                       | 2026-09-30: `devcontainer features info manifest` (CLI 0.89.0) returned the manifest, `common-utils` version `2.7.0`  |
| The image's configured apt sources (for the planned images `deb.debian.org`, `archive.ubuntu.com`, or `ports.ubuntu.com`) | `curl`, `ca-certificates`, `unzip` when missing                    | Build, only when one is missing                                                                          | apt's signed `Release` files with the keys the image ships; the feature adds no source and no key                                                             | Not applicable: the image, not the feature, chooses these hosts                                                                                                                                                                                           | Not fetched: depends on the image                                                                                     |

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
- [`test.sh` reads the latest pointer at test time, so a Deno release between build and test fails that run once] →
  Accepted: the window is minutes and a rerun passes; capturing the value at build time would need the feature to write
  state only a test reads.
- [The failure scenarios are hand runs, so CI does not guard them against regressions] → Accepted: a failing build
  cannot be a feature test; review of each change to the scripts re-checks the order of checks and the verification.
- [Upstream renames assets or moves downloads] → The download fails loudly; the fix is a PATCH that updates the
  Requirement's URL.

## Open Questions

None. The maintainer decided both questions of the approved package (Decisions: `installsAfter`, one spelling of an
exact version).
