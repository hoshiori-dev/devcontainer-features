# Design

## Context

See proposal.md - Why. `glab` is the first feature of the collection: `src/` does not exist yet. The Goal that accepts a
move of GitLab's download redirect to another host answers the maintainer's source-audit comment on PR #28, which notes
that `--proto-redir =https` restricts the scheme of a redirect but not its host. Upstream facts this change relies on,
checked on 2026-09-30 against gitlab.com (the release API of project `34675721`, the release files themselves,
`.goreleaser.yml` at `v1.120.0`, and `internal/config/config_file.go`, `internal/config/schema.go`, and
`internal/commands/version/version.go` of `gitlab-org/cli`, plus their `v1.47.0`, `v1.53.0`, and `v1.54.0` counterparts
where named), and by running the `v1.120.0` and `v1.47.0` amd64 binaries, each verified against its `checksums.txt`,
with a temporary `GLAB_CONFIG_DIR`:

- The latest release is `v1.120.0` (2026-09-29); releases come about weekly. None of the last 100 releases (`v1.40.0` to
  `v1.120.0`, release API with `per_page=100`) has a tag other than `vMAJOR.MINOR.PATCH`, although `.goreleaser.yml`
  sets `release.prerelease: auto`.
- Linux archives are named `glab_<version>_linux_<arch>.tar.gz` from `v1.47.0` (2024-10-02) on; `v1.46.0` and earlier
  used `glab_<version>_Linux_x86_64.tar.gz` and `Linux_arm64`. Upstream also builds 386, armv6, ppc64le (from
  `v1.48.0`), and s390x.
- The archive holds `bin/glab` (mode 0755), `README.md`, `LICENSE`, and `CHANGELOG.md`, the same in `v1.47.0`; no man
  pages (only upstream's deb, rpm, and apk packages carry them).
- The binary is static (`CGO_ENABLED=0`; ELF without `PT_INTERP` or `PT_DYNAMIC`), so it runs on glibc and musl alike.
  Upstream's packages declare `git` as their one dependency.
- `checksums.txt` is in `sha256sum` format (`<digest>␠␠<file name>`) and lists every release file. There is no Linux
  signature of any kind: no `signs` or cosign section in `.goreleaser.yml`, no `.sig`, `.pem`, `.asc`, bundle, SBOM, or
  attestation file among the release files; `scripts/sign-binary.sh` signs only the macOS and Windows builds.
- glab needs a writable configuration directory for every command, `--version` included: with an unwritable `HOME` it
  exits 2 with `failed to create config directory`. `GLAB_CONFIG_DIR` overrides the location (`config_file.go`, in
  `v1.47.0` too). Run with it, `v1.120.0` wrote `config.yml`, `aliases.yml`, and `config.lock` there and `v1.47.0` wrote
  `config.yml` and `aliases.yml`; run without it or `XDG_CONFIG_HOME`, `v1.120.0` wrote the same files to
  `$HOME/.config/glab-cli`.
- The version output changed in `v1.54.0` (commit `7f0fcd27d`): from then on `glab --version` and `glab version` both
  print `glab <version> (<commit>)` (`v1.120.0` printed `glab 1.120.0 (78790114c)` for each); `v1.47.0` to `v1.53.x`
  print `Current glab version: <version>`, in `v1.53.0` optionally followed by `(<build date>)` (`v1.47.0` printed
  `Current glab version: 1.47.0`).
- The update check: `check_update` defaults to true. `v1.120.0` reads `GLAB_CHECK_UPDATE` or `CHECK_UPDATE`
  (`schema.go`); `v1.47.0` reads only `CHECK_UPDATE`, and without it `glab --version` requested
  `https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases?page=1&per_page=1` and printed an update notice, while
  with `CHECK_UPDATE=false` it printed only the version. `telemetry` defaults to true (`GLAB_SEND_TELEMETRY`, usage data
  sent to the user's GitLab instance).
- `glab auth status` with no token and no reachable network exits 1 after requesting `https://gitlab.com/api/v4/user`
  (`v1.120.0`, run behind an unreachable proxy), so tests cannot use it offline.
- The planned images (inspected on 2026-09-30, the Docker Hub ones through their `public.ecr.aws/docker/library/` mirror
  because Docker Hub rate-limited the check): `tar`, `gzip`, `sha256sum`, `mktemp`, and `awk` are present on all four;
  `curl` is missing on `debian:12` and `alpine:3.24`, and `git` on all but the Ubuntu base. `fedora:44` runs dnf5, whose
  cache is `/var/cache/libdnf5` and holds no file after `dnf clean all`; the base image's `/var/lib/apt/lists` and
  `debian:12`'s are empty, and `alpine:3.24`'s `/var/cache/apk` is empty.
- The devcontainer CLI's duplicate test (0.89.0, `devContainersSpecCLI.js`) installs a string option with `proposals`
  first with the first proposal that is not its default, then with the defaults, and passes both values to
  `duplicate.sh` as `<OPTION>` and `<OPTION>__DEFAULT`.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entries of the compatibility list.
- Every download `install.sh` itself makes goes through `curl` restricted to HTTPS for the request and every redirect,
  with failing HTTP statuses treated as errors and TLS verification never disabled (feature-authoring.md, download rules
  "Sources" and "No weakening"), and requests only the URLs in the URL inventory below; package-manager requests go to
  the image's configured repositories. Checked by reviewing each `curl` call in `install.sh` against the inventory.
- A move of GitLab's download redirect (the generic package URL the release permalinks redirect to) to another host,
  such as object storage or a CDN, is accepted: `install.sh` restricts every hop to HTTPS but not to a host, because TLS
  and the published checksum still apply to what it downloads, and the feature should keep working as upstream
  infrastructure changes. feature-authoring.md's "Sources" rule admits the release platform's download redirects.
  `install.sh` prints the final URL of each download (`curl`'s `%{url_effective}`) to the build log, so the host in use
  is visible. Checked by reviewing `install.sh` and one CI build log.
- The `version` value is validated against `latest` or `v?MAJOR.MINOR.PATCH` (decimal numbers only) before it enters a
  URL, a file name, or a comparison, and the version read from the latest-release redirect passes the same validation
  and minimum. Checked by the manual checks below.
- Every check that needs no network — the option's form, the minimum version, the architecture, the distribution, and
  its package manager — runs before any package is installed or anything is downloaded. Checked by the manual checks
  below on `debian:12`, which still lacks `git` after each of them.
- Package installs are non-interactive, add only the missing ones of `git`, `curl`, `ca-certificates`, and `tar`, and
  clean the package manager's cache (`apt-get` with `DEBIAN_FRONTEND=noninteractive` and `--no-install-recommends`
  followed by removing `/var/lib/apt/lists/*`; `dnf install -y` followed by `dnf clean all`; `apk add --no-cache`).
  `gzip`, which GNU `tar -z` runs, is not installed: every planned image ships it (Context). Checked by `test.sh`, which
  asserts on every image that no file remains under `/var/lib/apt/lists`, `/var/cache/libdnf5`, or `/var/cache/apk`,
  whichever exists.
- `devcontainer-feature.json` declares no `containerEnv`, `dependsOn`, or `installsAfter`: `/usr/local/bin` is on
  `PATH`, and the prerequisites come from the image's own repositories. Checked by reviewing the file.
- Checksum verification selects the single line of `checksums.txt` whose file-name field equals the archive's name
  exactly, fails on zero or several such lines, and hands only that line to `sha256sum -c`. Checked by the digest
  mismatch and missing entry manual checks.
- Downloads and the build-time glab configuration directory live in directories made with
  `mktemp -d "${TMPDIR:-/tmp}/glab-feature.XXXXXX"` (a template BusyBox accepts too), and the new binary is staged as
  `/usr/local/bin/.glab-feature.XXXXXX`; one `trap` removes all of them on every exit, success or failure. Every
  build-time `glab` call runs with `GLAB_CONFIG_DIR` set to such a directory, with both `GLAB_CHECK_UPDATE=false` and
  `CHECK_UPDATE=false` (older releases read only the latter; Context), and with `GLAB_SEND_TELEMETRY=false`, and none of
  these variables is persisted. Checked by the "Nothing configured after install" scenario and, after each manual check,
  by an empty listing of `${TMPDIR:-/tmp}/glab-feature.*` and `/usr/local/bin/.glab-feature.*`.
- The staged binary is renamed over `/usr/local/bin/glab`, so a reader sees either the old or the new binary and a
  failed install leaves the old one. Checked by the "Failed second install" manual check.
- The second-install skip runs the installed binary's `glab --version`, isolated as above, and treats it as the
  requested version only when the output is `glab <version> (…` or `Current glab version: <version>`, optionally
  followed by `(…`. A missing binary, a non-zero exit, or any other output counts as not installed and leads to a
  replace; the check never aborts the install under `set -eu`. Checked by the "Same options twice" and "Unreadable
  installed version" manual checks, and the replace path by `duplicate.sh`.
- `test.sh` checks the "Nothing configured after install" scenario before it runs `glab` at all, since a `glab` call as
  the remote user creates `~/.config/glab-cli`. It compares `glab --version` with the version the latest-release
  permanent link names at test time (Decisions). Checked by reading `test.sh` in review.
- Scenarios a successful container build cannot show are checked by hand, once each, on amd64: `install.sh` runs in a
  throwaway `debian:12` container unless noted, with a `curl` or `uname` wrapper placed first on `PATH` where the case
  needs a tampered response or a foreign architecture. The checks: a malformed version, a version below the minimum, a
  release that does not exist, `latest` pointing to a pre-release tag, a digest mismatch, a missing or duplicated entry,
  an unsupported architecture, `/etc/os-release` removed, an unsupported distribution on `archlinux:latest` (`ID=arch`,
  no `ID_LIKE`), a supported family without its package manager on `amazonlinux:2` (`ID_LIKE` includes `fedora`, only
  `yum`), a failed second install, the same `version` twice (the second build log says the version is already installed,
  and the binary's inode and modification time are unchanged), and an unreadable installed version (a stub
  `/usr/local/bin/glab` that exits 1 is replaced). Each result goes into the PR's Validation section. `install.sh`
  itself carries no test hook. The maintainer accepted this manual-only coverage for this change (Non-Goals).

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream builds four more, but CI has runners only for these two.
- Releases before `1.47.0`, which use the old archive names.
- Authentication, a GitLab host, or any glab configuration (the issue's Out of scope).
- Authenticity of the release beyond what gitlab.com's TLS gives: upstream publishes no signature and no key to pin.
- Man pages and shell completions: the archive has no man pages, and `glab completion` generates completions on demand.
- Removing the prerequisites the feature installed.
- Repeating the manual checks under Goals in CI: a successful container build cannot show a failure, and a test hook in
  `install.sh` would ship to users. A later change can add `build` scenarios with a Dockerfile if a regression shows up.
- Images of a supported family that lack its package manager (Amazon Linux 2 and CentOS 7 have only `yum`), and
  distroless images; the feature fails clearly on them.

## Options

The feature has one option, new in this change; the spec's Option requirement states it.

| Name      | Type     | Default    | Enum or proposals               | Meaning                                                                                                    |
| --------- | -------- | ---------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","1.47.0"]` | The release to install: `latest`, or a release version at or above `1.47.0`, with or without a leading `v` |

- **Default `latest`.** It follows upstream's weekly releases without a feature release for each; users who need
  reproducible builds pin `version` (Risks). The duplicate test installs the first proposal that is not the default,
  `1.47.0`, first and the defaults second (Context), so the second install takes the replace path, and the first
  exercises the minimum and the older version output.
- **Rejected shapes.** An option for a login, a token, or a GitLab host — out of scope by the issue, and the spec rules
  it out; an `enum` of release versions — every upstream release would need a feature release, and `latest` would be
  impossible; the current release as the second proposal — it equals what `latest` resolves to, so the second install
  would skip and the replace path would never run in CI; a release between the two proposals — it tests nothing `1.47.0`
  does not.

## Decisions

- **Release archive from the GitLab release permalinks.** The feature downloads
  `/-/releases/v<version>/downloads/<file>` on gitlab.com, which GitLab documents as a stable link that keeps working
  when the file's physical location moves. Rejected: upstream's deb, rpm, and apk packages — three code paths that mix
  package-manager state with a manual install and make the second install harder, for man pages only; distribution
  repositories and Homebrew — they lag and cannot pin an upstream release; `go install` — needs a Go toolchain and a
  long build; copying from upstream's container image — a feature cannot use a base image; the generic package registry
  URL the permalink redirects to — an implementation detail GitLab may move.
- **Integrity from `checksums.txt`, stated as integrity only.** It is the only verification upstream publishes for
  Linux, so feature-authoring.md's "Direct downloads" rule requires fetching it at install time, verifying the archive
  against it, and failing when it is missing or unreachable; the spec says it does not establish authenticity. The
  checksum list itself and the latest-release link have nothing upstream publishes to verify them against, so the spec
  states that they rely on TLS alone, as that rule requires. Rejected: digests pinned in the feature — the "No
  per-version hashes" rule forbids them, every upstream release would need a feature release, and `latest` would be
  impossible; skipping verification — the "Direct downloads" rule forbids it once upstream publishes a checksum.
- **`latest` from the release page's permanent link, read without following it.** The feature requests
  `/-/releases/permalink/latest`, takes the last path segment of the `Location` header (absolute or relative), and
  validates it as a version. Rejected: the API's permanent link — it answers with a relative redirect to a JSON document
  that would need a JSON parser; the API's release list — needs a parser and ordering rules GitLab already applies;
  following the redirect and parsing HTML.
- **Minimum version `1.47.0`.** The first release with today's archive names and layout; older values fail with a clear
  message. Rejected: a second naming scheme for releases from before October 2024.
- **Tests resolve `command -v glab` instead of comparing its text.** On `fedora:44`, `/usr/local/sbin` is a symbolic
  link to `bin` and comes first on `PATH`, so `command -v glab` prints `/usr/local/sbin/glab` for the same file; the
  implementation found this, and the two scenarios were reworded for the maintainer's renewed approval. Rejected:
  changing `PATH` or installing elsewhere for that image, which the design rules out.
- **A POSIX test helper instead of `dev-container-features-test-lib`.** The Dev Container CLI's test library needs bash
  (it declares arrays), and `alpine:3.24` ships none, so `test/glab/checks.sh` provides the same `check` and
  `reportResults` interface in POSIX `sh` and every test script sources it. `.agents/knowledge/testing.md` names the CLI
  library; this is a recorded exception for images without bash. Rejected: installing bash in the test image, which
  would change what the feature is tested against.
- **Tests check `latest` against the permanent link at test time.** `test.sh` (default options) and `duplicate.sh`
  (second install) read the same permanent link with `curl` and compare its version with `glab --version`;
  `duplicate.sh` also asserts that the version differs from `1.47.0`. Rejected: accepting any valid version at or above
  `1.47.0` — it would not catch a wrong resolution; recording the resolved version in a file — leaves a file in the
  image.
- **`/usr/local/bin/glab`, replaced atomically.** On `PATH` for every user on all planned images, so no `containerEnv`
  is needed, and outside the package manager's files. Rejected: `/usr/bin` — the package manager's territory; a per-user
  directory — not on `PATH` for other users.
- **Build-time glab calls isolated.** A temporary `GLAB_CONFIG_DIR` keeps glab from creating `/root/.config/glab-cli` or
  failing on an unwritable home; `GLAB_CHECK_UPDATE=false` and `CHECK_UPDATE=false` keep those calls from contacting
  gitlab.com for an update check; `GLAB_SEND_TELEMETRY=false` keeps them from sending usage data. Whether
  `glab --version` sends usage data without an authenticated host was not verified; the variable makes the answer
  irrelevant at no cost. Rejected: checking the version by file checksum or a marker file — the binary's own output is
  what the spec asserts; setting only `GLAB_CHECK_UPDATE=false` — releases up to at least `v1.47.0` ignore it.
- **Prerequisites from the image's own repositories, only when missing, left installed.** `git` because glab needs it at
  run time (upstream's packages depend on it); `curl`, `ca-certificates`, and `tar` because the install needs them.
  Rejected: `dependsOn` on another feature — adds an external dependency for four packages; removing them afterwards —
  could remove what the user or another feature relies on, and `git` must stay.
- **`curl` only.** One download path; `curl` is installed when missing. Rejected: a `wget` fallback — a second code path
  with different redirect and protocol flags.
- **Distribution families by `ID` or `ID_LIKE`, then the family's package manager.** `debian` and `ubuntu` map to
  `apt-get`, `fedora` to `dnf`, `alpine` to `apk`; a missing `/etc/os-release` or any other family fails, and so does a
  matched family whose package manager is not on `PATH`, before anything is installed. Rejected: matching `ID` only —
  rejects derivatives that use the same package manager for no gain, since the binary is static; falling back to `yum`
  or whichever manager is present — a fourth code path for images outside the compatibility list; ignoring the
  distribution when every prerequisite is present — the repository rule is to fail clearly on an unsupported one.

## Security review

- **Downloads:** the release archive and `checksums.txt` for one version and architecture, and one header-only request
  for `latest`; all on gitlab.com over HTTPS (URL inventory), a move of the download redirect to another host accepted
  (Goals). Nothing is piped to a shell. Build-time `glab` calls make no request (Decisions).
- **Verification:** SHA-256 of the archive against its exact entry in `checksums.txt`; unsigned and same-origin, so it
  detects corruption and a mismatched file but not a compromised release pipeline (Risks). `checksums.txt` and the
  latest-release link rely on TLS alone, stated in the spec.
- **Keys:** none; upstream signs no Linux artifact, so there is no key or fingerprint to pin.
- **Metadata:** `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, and `entrypoint` are not declared — the CLI
  needs no extra privilege or process. `containerEnv` is not declared — `/usr/local/bin` is already on `PATH`, and no
  glab variable is set for users. No lifecycle command. `dependsOn` and `installsAfter` are not declared — the
  prerequisites come from the image's own repositories.
- **Options:** only `version`, validated before use; no credential, token, or host option, by design (issue #13).
- **Idempotency:** the spec's "Installing twice" requirement, reached through the skip check and atomic replace (Goals)
  and tested through the `version` proposals (Options).
- **Failure behavior:** the spec's failure scenarios, checked as described under Goals; every failure exits non-zero,
  which fails the image build.

## Supported images

The planned `test/glab/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]`; the Ubuntu base entry also
sets `"remoteUser": "vscode"` (the image's non-root user, uid 1000), so the tests run once as a non-root user, and the
others run as root:

| Image                                              | Why                                                                                |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with most prerequisites present       |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl`, `ca-certificates`, and `git` |
| `alpine:3.24`                                      | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash            |
| `fedora:44`                                        | `dnf` path                                                                         |

All four tags publish amd64 and arm64 images (Docker Hub tag API and the MCR manifest, 2026-09-30); `alpine:3.24` and
`fedora:44` are the current `alpine:3` and `fedora:latest`.

## URL inventory

Every URL the feature's scripts access. All are fetched at build time by `install.sh`; the feature fetches nothing at
container start (it declares no lifecycle command or entrypoint). It configures no package repository: `git`, `curl`,
`ca-certificates`, and `tar` come from the repositories the image already has. It has no `dependsOn` or `installsAfter`,
so no feature OCI reference. `<version>` has no leading `v`; `<arch>` is `amd64` or `arm64`. The host of the redirect
target in the last row may move (Goals).

| URL / template                                                                                                                                                      | Purpose                                                                       | When                                                                                    | Integrity / authenticity                                                                                                                      | Official source evidence                                                                                                                                                                                                        | Verified                                                                                                                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest`                                                                                                     | Resolve `latest` to a version from the `Location` header, not followed        | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` (Decisions) | TLS; the version read from it must pass the version validation and minimum; it only selects which release's archive and checksums are fetched | https://docs.gitlab.com/user/project/releases/#permanent-link-to-latest-release                                                                                                                                                 | 2026-09-30: `302`, `Location: https://gitlab.com/gitlab-org/cli/-/releases/v1.120.0` (host gitlab.com)                                                                |
| `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/glab_<version>_linux_<arch>.tar.gz`                                                              | Release archive holding `bin/glab`                                            | Build                                                                                   | TLS; SHA-256 against its exact entry in `checksums.txt` (integrity only; no signature exists)                                                 | The release's `direct_asset_url` in https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/releases/v1.120.0 equals this template; https://docs.gitlab.com/user/project/releases/release_fields/#permanent-links-to-release-assets | 2026-09-30: `1.120.0` and `1.47.0`, amd64 and arm64: `302` to the row below, then `200` (`application/gzip`); `1.46.0`: `404`                                         |
| `https://gitlab.com/gitlab-org/cli/-/releases/v<version>/downloads/checksums.txt`                                                                                   | Checksum list for the release                                                 | Build                                                                                   | TLS only; unsigned, same origin as the archive                                                                                                | The same release API response lists it with this `direct_asset_url`; `checksum.name_template: "checksums.txt"` in https://gitlab.com/gitlab-org/cli/-/raw/v1.120.0/.goreleaser.yml                                              | 2026-09-30: `1.120.0` and `1.47.0`: `302` to the row below, then `200`; holds the `linux_amd64` and `linux_arm64` `.tar.gz` lines; a missing release (`9.9.9`): `404` |
| `https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/<version>/<file>` (dots percent-encoded as `%2E`), redirect target of the two rows above | Where GitLab serves the archive and `checksums.txt`; reached only by redirect | Build                                                                                   | As the row that redirected to it                                                                                                              | https://docs.gitlab.com/user/packages/generic_packages/; `gitlab_urls.use_package_registry: true` in the `.goreleaser.yml` above                                                                                                | 2026-09-30: final host gitlab.com, `200`, one redirect hop                                                                                                            |

The target of the latest-release permanent link (`https://gitlab.com/gitlab-org/cli/-/releases/v<version>`) is only read
from the header, never fetched. At run time glab itself contacts GitLab hosts when the user runs it (update checks, API
calls, telemetry to the user's instance); that is the tool's behavior under the user's control, not a fetch by the
feature.

## Risks / Trade-offs

- [`checksums.txt` is unsigned and served from the same origin, so a compromised release pipeline or package registry
  goes undetected] → The spec states integrity only; if upstream starts signing Linux artifacts, a follow-up change adds
  signature verification with a pinned key.
- [Upstream publishes a pre-release tag that the latest-release link points to] → The version validation rejects it and
  the `latest` build fails with a clear message until a regular release follows; users can pin `version`. No such tag
  exists among the last 100 releases (Context).
- [Upstream renames archives or changes their layout] → The install fails with a clear message instead of installing
  something else; a PATCH release of the feature follows.
- [Upstream changes the version output again] → The skip check no longer recognizes the version and the second install
  replaces the binary with the same release: correct result, one needless download, until a PATCH release of the feature
  follows.
- [GitLab changes the permanent link's status code or makes `Location` relative] → The feature reads the last path
  segment of either form and validates it; anything else fails clearly.
- [A release is published between a CI job's build and its test] → That job's comparison with the permanent link fails;
  a re-run passes. Releases come about weekly and a job takes minutes, so this is rare.
- [gitlab.com is unreachable or rate-limits the build] → The build fails; there is no mirror.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → It is accepted because its
  package manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.
- [GitLab moves its download redirect to another host] → Builds keep working over HTTPS with the checksum check, but the
  URL inventory and the design's evidence go stale. The move is noticed in the build log, where `install.sh` prints each
  download's final URL (Goals), and when the next change to the feature re-checks its URLs; that change updates the
  inventory, and the spec if a named URL changed.

## Open Questions

None.
