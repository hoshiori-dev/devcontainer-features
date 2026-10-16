# Design

## Context

See proposal.md - Why. The feature follows the shape of `glab` (archived change `2026-10-02-add-glab-feature`): a static
Go binary from upstream's release archives, verified against the release's checksum list, installed atomically to
`/usr/local/bin`. What differs is written below; what is the same is named, not repeated. Upstream facts this change
relies on, checked on 2026-10-15 against github.com (the release API of `betterleaks/betterleaks` with `per_page=100`,
the release files, `.goreleaser.yml` on `main`, `README.md`, and `docs/v2_migration.md`) and by running the `1.0.1`,
`1.9.0`, and `2.0.0-rc.2` amd64 binaries, each verified against its `checksums.txt`:

- The repository has 22 releases, `v1.0.1` (2026-02-20) to `v1.9.0` (2026-09-29) on the v1 line, then `v2.0.0-rc.1`
  (2026-09-30) and `v2.0.0-rc.2` (2026-10-07), both marked pre-release. GitHub's latest-release link redirects (`302`)
  to `https://github.com/betterleaks/betterleaks/releases/tag/v1.9.0`: GoReleaser's `release.prerelease: auto` and
  `make_latest` exclude pre-releases from it. The `main` branch develops v2; v1 lives on the `v1.x` branch. Every tag is
  `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-rc.N`.
- Every release from `v1.0.1` on publishes `betterleaks_<version>_linux_x64.tar.gz` and
  `betterleaks_<version>_linux_arm64.tar.gz` (`.goreleaser.yml` maps `amd64` to `x64`), the darwin and windows
  counterparts, and `checksums.txt` in `sha256sum` format listing every archive. From `v1.3.0` on, `checksums.txt` is
  signed with cosign keyless (`checksums.txt.sigstore.json`, bundle media type
  `application/vnd.dev.sigstore.bundle.v0.3+json`); the `v1.9.0` bundle's certificate names the issuer
  `https://token.actions.githubusercontent.com` and the identity
  `https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/v1.9.0`. Nothing else is signed or
  attested on the release; container images are signed separately.
- The archive holds `betterleaks` (mode 0755, at the root, no `bin/`), `LICENSE`, and `README.md`, the same in `1.0.1`
  and `2.0.0-rc.2`. The binary is static (`CGO_ENABLED=0`, no dynamic loader string), so it runs on glibc and musl
  alike.
- `betterleaks version` prints the bare version (`1.0.1`, `1.9.0`, `2.0.0-rc.2`) and `betterleaks --version` prints
  `betterleaks version <version>`, identical across the three binaries. Run with an empty `HOME` directory, `version`
  writes nothing there in `1.9.0` and `2.0.0-rc.2`. The binary holds no release-check URL, so no update check is
  expected; this was read from the binary's strings, not from the source.
- `betterleaks git <repo>` runs the `git` executable (`exec: "git": executable file not found in $PATH` without it);
  `betterleaks fs <dir>` does not need it. Upstream's own packages are the Homebrew cask and Fedora's package.
- The release download URLs redirect (`302`) once to `release-assets.githubusercontent.com` with a signed, expiring
  query string, then answer `200` (`application/octet-stream` for `checksums.txt`, `application/gzip` for the archive).
- The planned images are the four of `glab`'s compatibility list, whose prerequisites were inspected for that change;
  the same `tar`, `gzip`, `sha256sum`, `mktemp`, and `awk` are relied on here, and `curl`, `ca-certificates`, and `git`
  are installed when missing.
- The devcontainer CLI's duplicate test installs a string option with `proposals` first with the first proposal that is
  not its default, then with the defaults, and passes both values to `duplicate.sh` as `<OPTION>` and
  `<OPTION>__DEFAULT`.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- Every download `install.sh` makes goes through `curl` restricted to HTTPS for the request and every redirect, with
  failing HTTP statuses treated as errors and TLS verification never disabled, and requests only the URLs in the URL
  inventory below; package-manager requests go to the image's configured repositories. A move of GitHub's download
  redirect to another host is accepted for the reason the `glab` design gives, and `install.sh` prints the final URL of
  each download to the build log. Checked by reviewing each `curl` call against the inventory and one CI build log.
- The `version` value is validated against `latest` or `v?MAJOR.MINOR.PATCH(-rc.N)?` (decimal numbers only) before it
  enters a URL, a file name, or a comparison; the tag read from the latest-release redirect passes the same validation,
  the minimum, and the no-pre-release rule. Checked by the manual checks below.
- Every check that needs no network — the option's form, the minimum version, the architecture, the distribution, and
  its package manager — runs before any package is installed or anything is downloaded. Checked by the manual checks
  below on `debian:12`, which still lacks `git` after each of them.
- Package installs are non-interactive, add only the missing ones of `git`, `curl`, `ca-certificates`, and `tar`, and
  clean the package manager's cache (`apt-get` with `DEBIAN_FRONTEND=noninteractive` and `--no-install-recommends`
  followed by removing `/var/lib/apt/lists/*`; `dnf install -y` followed by `dnf clean all`; `apk add --no-cache`).
  Checked by `test.sh`, which asserts on every image that no file remains under `/var/lib/apt/lists`,
  `/var/cache/libdnf5`, or `/var/cache/apk`, whichever exists.
- `devcontainer-feature.json` declares no `containerEnv`, `dependsOn`, `installsAfter`, lifecycle command, or
  privilege-widening key. Checked by reviewing the file.
- Checksum verification selects the single line of `checksums.txt` whose file-name field equals the archive's name
  exactly, fails on zero or several such lines, and hands only that line to `sha256sum -c`. Checked by the digest
  mismatch and missing entry manual checks.
- Downloads live in a directory made with `mktemp -d "${TMPDIR:-/tmp}/betterleaks-feature.XXXXXX"`, the new binary is
  staged as `/usr/local/bin/.betterleaks-feature.XXXXXX`, and one `trap` removes both on every exit. The build-time
  `betterleaks version` call runs with `HOME` set to that temporary directory, so a future release that writes under
  `HOME` leaves nothing in the image. Checked by the "Nothing configured after install" scenario and, after each manual
  check, by an empty listing of `${TMPDIR:-/tmp}/betterleaks-feature.*` and `/usr/local/bin/.betterleaks-feature.*`.
- The staged binary is renamed over `/usr/local/bin/betterleaks`, so a reader sees either the old or the new binary and
  a failed install leaves the old one. Checked by the "Failed second install" manual check.
- The second-install skip runs the installed binary's `betterleaks version`, isolated as above, and treats it as the
  requested version only when the output equals the requested version without its leading `v`. A missing binary, a
  non-zero exit, or any other output counts as not installed and leads to a replace; the check never aborts the install
  under `set -eu`. Checked by the "Same options twice" and "Unreadable installed version" manual checks, and the replace
  path by `duplicate.sh`.
- `test.sh` checks the "Nothing configured after install" scenario before it runs `betterleaks` at all, compares
  `betterleaks version` with the tag the latest-release link names at test time (Decisions), and runs the "Scan of a
  repository" scenario on a repository it creates with one empty commit. Checked by reading `test.sh` in review.
- Scenarios a successful container build cannot show are checked by hand, once each, on amd64, the way the `glab` design
  describes: `install.sh` runs in a throwaway `debian:12` container unless noted, with a `curl` or `uname` wrapper
  placed first on `PATH` where the case needs a tampered response or a foreign architecture. The checks: a malformed
  version (each form the scenario names), a version below the minimum, a release that does not exist, `latest` pointing
  to a pre-release tag and to a malformed tag, a digest mismatch, a missing or duplicated entry, an unsupported
  architecture, `/etc/os-release` removed, an unsupported distribution on `archlinux:latest`, a supported family without
  its package manager on `amazonlinux:2`, a failed second install, the same `version` twice (the build log says the
  version is already installed, and the binary's inode and modification time are unchanged), and an unreadable installed
  version (a stub `/usr/local/bin/betterleaks` that exits 1 is replaced). Each result goes into the PR's Validation
  section. `install.sh` itself carries no test hook.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream builds no other Linux architecture, and CI has runners only for
  these two.
- Verifying the Sigstore bundle of `checksums.txt` (Decisions, Security review).
- Any scan configuration, baseline, pre-commit hook, or `BETTERLEAKS_*` variable (the issue's Out of scope).
- Upstream's Homebrew cask, Fedora package, container image, and `go install` path.
- Shell completions: `betterleaks completion` generates them on demand.
- Removing the prerequisites the feature installed.
- Repeating the manual checks under Goals in CI, for the reason the `glab` design gives.
- Images of a supported family that lack its package manager, and distroless images; the feature fails clearly on them.

## Options

The feature has one option, new in this change; the spec's Option requirement states it.

| Name      | Type     | Default    | Enum or proposals              | Meaning                                                                                                                                   |
| --------- | -------- | ---------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","1.0.1"]` | The release to install: `latest`, or a release version at or above `1.0.1`, a `-rc.N` pre-release included, with or without a leading `v` |

- **Default `latest`.** It follows upstream's releases, about two a month, without a feature release for each, and it
  stays on the stable line through a v2 release-candidate period because GitHub's latest-release link skips
  pre-releases; users who need reproducible builds pin `version` (Risks). The duplicate test installs the first proposal
  that is not the default, `1.0.1`, first and the defaults second (Context), so the second install takes the replace
  path and the first exercises the minimum.
- **Rejected shapes.** An option for a configuration file, a baseline, or a hook — out of scope by the issue, and the
  spec rules it out; an `enum` of release versions — every upstream release would need a feature release, and `latest`
  would be impossible; a `prerelease` boolean that lets `latest` resolve to a release candidate — GitHub's redirect
  cannot express it, so it would need the release API and a JSON parser for one transient period; the current release as
  the second proposal — it equals what `latest` resolves to, so the replace path would never run in CI.

## Decisions

- **Release archive from GitHub's release download URLs.** `releases/download/v<version>/<file>` is the URL the release
  page links and the form GitHub documents for release assets; it redirects once to GitHub's asset host. Rejected:
  Fedora's package — one distribution; Homebrew — not a Linux-container tool here; the container image — a feature
  cannot use a base image, and copying a binary out of it needs a container runtime at build time; `go install` — needs
  a Go toolchain and a long build; the GitHub API's asset URL — needs a JSON parser and offers nothing the download URL
  lacks.
- **Integrity from `checksums.txt`; the Sigstore bundle is not verified.** The checksum list is the only verification of
  the archive upstream publishes, so feature-authoring.md's "Direct downloads" rule requires fetching it at install
  time, verifying the archive against it, and failing when it is missing or unreachable. Upstream also signs
  `checksums.txt` with cosign keyless, and the rule asks for a signature to be verified against a pinned signer identity
  when upstream publishes one. This change does not: verifying a Sigstore bundle needs `cosign` or `sigstore-go`, which
  none of the planned images ships, and downloading one from its own GitHub release would need the verification the
  feature is trying to establish, or a per-version hash the rules forbid. The spec states the resulting bound as a risk
  in the download requirement, so approving the package accepts it; the identity a follow-up would pin is recorded in
  Context (issuer `https://token.actions.githubusercontent.com`, identity
  `https://github.com/betterleaks/betterleaks/.github/workflows/release.yml@refs/tags/v<version>`). Rejected: a
  hand-written check with `openssl` of the bundle's certificate and signature — it can check the signature and the
  certificate's identity but not the chain to the Sigstore root or the transparency-log entry without the Sigstore trust
  root, and a half verification that reads as a full one is worse than a stated gap; `dependsOn` on a feature that
  installs cosign — no such feature exists in the collection; digests pinned in the feature — forbidden by "No
  per-version hashes"; GitHub's asset digest from the API — permitted but not required, and it would add a JSON parser
  for a digest from the same origin as the checksum list.
- **`latest` from the latest-release link, read without following it.** The feature requests
  `https://github.com/betterleaks/betterleaks/releases/latest`, takes the last path segment of the `Location` header
  (absolute or relative), and validates it as a stable version. Rejected: the API's `releases/latest` — a JSON document;
  the release list — needs a parser and the ordering GitHub already applies; following the redirect and parsing HTML.
- **Pre-releases accepted when named, never through `latest`.** Upstream's v2 is in release candidates and documents
  installing one by exact version; a developer trying the migration pins it. The accepted suffix is exactly upstream's
  `-rc.N`, so the validation stays a short pattern. Rejected: rejecting every pre-release — forces `go install` on
  anyone testing v2 during the candidate period; accepting any SemVer pre-release identifier — admits forms upstream has
  never published and widens what reaches a URL.
- **Minimum version `1.0.1`.** The first release; every release since has the same archive names, layout, and `version`
  output. Rejected: a higher minimum — nothing changed that would justify one.
- **Version scenarios, one per image.** Four scenarios, each on a different compatibility image and each asserting the
  installed version: an explicit version on `debian:12`, a leading `v` on `alpine:3.24`, a pre-release on the Ubuntu
  base as its remote user, and an explicit version on `fedora:44`. `scenarioArchitectures` selects amd64 and arm64, so
  each runs on both native runners. Rejected: every version form on every image, as `glab` does — eight scenarios,
  sixteen jobs, for an archive format that is the same on all four images and an installer whose per-image path is the
  package-manager branch that `test.sh` already covers on each.
- **Tests check `latest` against the latest-release link at test time.** `test.sh` (default options) and `duplicate.sh`
  (second install) read the redirect with `curl` and compare its tag with `betterleaks version`; `duplicate.sh` also
  asserts that the version differs from `1.0.1`. Rejected: accepting any valid version — would not catch a wrong
  resolution; recording the resolved version in a file — leaves a file in the image.
- **`/usr/local/bin/betterleaks`, replaced atomically; a POSIX test helper; prerequisites from the image's own
  repositories, only when missing, left installed.** As in the `glab` design, for the same reasons; `git` because
  `betterleaks git` runs it.
- **The scan scenario uses a repository the test creates.** `test.sh` initialises a repository with one empty commit and
  runs `betterleaks git` on it, so the scenario needs no fixture file and no network. Rejected: scanning the test folder
  itself — its scripts may hold strings a future rule flags; scanning a cloned repository — network and an external
  dependency.

## Security review

- **Downloads:** the release archive and `checksums.txt` for one version and architecture, and one header-only request
  for `latest`; all on github.com over HTTPS with one redirect to GitHub's asset host (URL inventory). Nothing is piped
  to a shell. The build-time `betterleaks version` call makes no request (Context).
- **Verification:** SHA-256 of the archive against its exact entry in `checksums.txt`; the checksum list and the
  latest-release link rely on TLS alone. Upstream's Sigstore signature of the checksum list is not verified (Decisions):
  this detects corruption and a mismatched file but not a compromised release pipeline. This is the decision the package
  gate is asked to approve.
- **Keys:** none pinned; the signer identity a follow-up would pin is recorded in Context.
- **Metadata:** `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, `containerEnv`, lifecycle
  commands, `dependsOn`, and `installsAfter` are not declared.
- **Options:** only `version`, validated before use; no credential, configuration, or hook option, by design (issue
  #152).
- **Idempotency:** the spec's "Installing twice" requirement, reached through the skip check and atomic replace (Goals)
  and tested through the `version` proposals (Options).
- **Failure behavior:** the spec's failure scenarios, checked as described under Goals; every failure exits non-zero,
  which fails the image build. The build never runs a scan, so no secret of the build context is read or reported.

## Supported images

The planned `test/betterleaks/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                                |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with most prerequisites present       |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl`, `ca-certificates`, and `git` |
| `alpine:3.24`                                      | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash            |
| `fedora:44`                                        | `dnf` path                                                                         |

The same list as `glab`, whose change verified that all four tags publish amd64 and arm64 images.

## URL inventory

Every URL the feature's scripts access. All are fetched at build time by `install.sh`; the feature fetches nothing at
container start. It configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `x64` or `arm64`. The host of the redirect target in the last row may move (Goals).

| URL                                                                                                                                         | Purpose                                                      | When                                                                        | Verification                                                                            | Evidence (2026-10-15)                                                                                        |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `https://github.com/betterleaks/betterleaks/releases/latest`                                                                                | Resolve `latest` from the `Location` header, not followed    | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` | TLS; the tag must pass the version validation, the minimum, and the no-pre-release rule | `302`, `Location: https://github.com/betterleaks/betterleaks/releases/tag/v1.9.0`                            |
| `https://github.com/betterleaks/betterleaks/releases/download/v<version>/betterleaks_<version>_linux_<arch>.tar.gz`                         | Release archive holding `betterleaks`                        | Build                                                                       | TLS; SHA-256 against its exact entry in `checksums.txt` (integrity only)                | `1.0.1`, `1.9.0`, `2.0.0-rc.2`, x64: `302` to the row below, then `200`; listed for arm64 in `checksums.txt` |
| `https://github.com/betterleaks/betterleaks/releases/download/v<version>/checksums.txt`                                                     | Checksum list for the release                                | Build                                                                       | TLS only; its Sigstore bundle is not verified (Decisions)                               | `302` to the row below, then `200`; holds the `linux_x64` and `linux_arm64` lines                            |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<path>?<signed query>`, redirect target of the two rows above | Where GitHub serves release assets; reached only by redirect | Build                                                                       | As the row that redirected to it                                                        | Final host `release-assets.githubusercontent.com`, `200`, one redirect hop                                   |

The target of the latest-release link (`.../releases/tag/v<version>`) is only read from the header, never fetched. At
run time betterleaks contacts credential providers only when the user asks it to validate or analyze findings; that is
the tool's behavior under the user's control, not a fetch by the feature.

## Risks / Trade-offs

- [`checksums.txt`'s signature is not verified, so a compromised release pipeline or asset host goes undetected] → The
  spec states integrity only; a follow-up change adds verification against the recorded identity once a verifier the
  rules allow is available in the image or in the collection.
- [Upstream publishes a stable `2.0.0` whose CLI differs from v1] → `latest` moves to it on the next build, as it would
  for any tool; `betterleaks version` still prints the bare version in `2.0.0-rc.2`, so the skip check holds. Users pin
  `version`; `NOTES.md` says so and points to the migration guide.
- [Upstream changes the `version` output] → The skip check no longer recognizes it and the second install replaces the
  binary with the same release: correct result, one needless download, until a PATCH release of the feature follows.
- [Upstream renames archives or changes their layout] → The install fails with a clear message instead of installing
  something else; a PATCH release of the feature follows.
- [GitHub changes the latest-release redirect or makes `Location` relative] → The feature reads the last path segment of
  either form and validates it; anything else fails clearly.
- [A release is published between a CI job's build and its test] → That job's comparison with the latest-release link
  fails; a re-run passes. Releases are weeks apart and a job takes minutes.
- [github.com is unreachable or rate-limits the build] → The build fails; there is no mirror.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.
- [GitHub moves its asset host] → Builds keep working over HTTPS with the checksum check; the move is noticed in the
  build log, where `install.sh` prints each download's final URL, and the next change to the feature updates the
  inventory.

## Open Questions

None.
