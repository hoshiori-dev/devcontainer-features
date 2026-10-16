# Design

## Context

See proposal.md - Why. The feature follows the `betterleaks` feature (archived change
`2026-10-15-add-betterleaks-feature`), itself derived from `glab`: a static Go binary from upstream's release archives,
verified against the release's checksum list, installed atomically to `/usr/local/bin`. What differs is written below;
what is the same is named, not repeated. Upstream facts this change relies on, checked on 2026-10-16 against github.com
(the release API of `gitleaks/gitleaks` with `per_page=100`, two pages; the release files; `.goreleaser.yml` and
`README.md` on `master`) and by running the `8.2.0`, `8.8.0`, `8.12.0`, `8.16.2`, `8.18.0`, and `8.30.1` amd64 binaries,
each verified against its checksum file:

- The README's first line is a warning that Gitleaks is feature complete, that future releases are security patches
  only, and that the author's focus moved to Betterleaks. The repository is not archived; the last push was 2026-09-30,
  and the latest release `v8.30.1` dates from 2026-03-21. GitHub's latest-release link redirects (`302`) to
  `https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1`.
- Every v8 release publishes `gitleaks_<version>_linux_x64.tar.gz` (`.goreleaser.yml` replaces `amd64` with `x64`), and
  from `v8.2.0` (2021-12-09) on also `gitleaks_<version>_linux_arm64.tar.gz`, beside armv6, armv7, x32, darwin, and
  windows builds, together with `gitleaks_<version>_checksums.txt` in `sha256sum` format listing every archive. No
  release carries a signature, bundle, SBOM, or attestation, and `.goreleaser.yml` has no `signs` section. Three tags
  `v8.15.1-test`, `-test2`, `-test3` (marked pre-release, no arm64 archive) sit among the regular ones; no `-rc` tag
  exists.
- The archive holds `gitleaks` (mode 0755, at the root), `LICENSE`, and `README.md`, the same in `8.2.0` and `8.30.1`.
  The binary is static (no `PT_INTERP` or `PT_DYNAMIC` program header) and `8.30.1` runs on `alpine:3.24`.
- `gitleaks version` prints the bare version in every binary run (`8.2.0` to `8.30.1`), and `gitleaks --version` prints
  `gitleaks version <version>`. Run with an empty `HOME`, `version` writes nothing there. The binary holds no
  release-check URL, so no update check is expected.
- `gitleaks git <repo>` runs the `git` executable (`exec: "git": executable file not found in $PATH` without it);
  `gitleaks dir <path>` does not need it. Scans exit 1 on findings by default (`--exit-code`, README) and 0 otherwise.
- The release download URLs redirect once to `release-assets.githubusercontent.com` with a signed, expiring query
  string, as for betterleaks.
- The planned images are the four of the `betterleaks` and `glab` compatibility lists; the same prerequisites apply.
- The devcontainer CLI's duplicate test installs a string option with `proposals` first with the first proposal that is
  not its default, then with the defaults.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- Every download `install.sh` makes goes through `curl` restricted to HTTPS for the request and every redirect, with
  failing HTTP statuses treated as errors and TLS verification never disabled, and requests only the URLs in the URL
  inventory below; package-manager requests go to the image's configured repositories. A move of GitHub's download
  redirect to another host is accepted for the reason the `glab` design gives, and `install.sh` prints the final URL of
  each download, without its signed query string, to the build log. Checked by reviewing each `curl` call against the
  inventory and one CI build log.
- The `version` value is validated against `latest` or `v?MAJOR.MINOR.PATCH` (decimal numbers only) before it enters a
  URL, a file name, or a comparison; the tag read from the latest-release redirect passes the same validation and the
  minimum. Checked by the manual checks below.
- Every check that needs no network — the option's form, the minimum version, the architecture, the distribution, its
  package manager, and the target path being absent or a regular file — runs before any package is installed or anything
  is downloaded. Checked by the manual checks below on `debian:12`, which still lacks `git` after each of them.
- Package installs, the cache cleanup, the metadata without `containerEnv`, `dependsOn`, `installsAfter`, lifecycle
  command, or privilege-widening key, the checksum selection of exactly one entry, the temporary directory and staged
  binary under one `trap`, the build-time `gitleaks version` call with `HOME` in the temporary directory, the atomic
  rename, and the skip check on the bare version output: as in the `betterleaks` design, checked the same way; the
  directories are `${TMPDIR:-/tmp}/gitleaks-feature.XXXXXX` and `/usr/local/bin/.gitleaks-feature.XXXXXX`.
- `test.sh` checks the "Nothing configured after install" scenario before it runs `gitleaks` at all, compares
  `gitleaks version` with the tag the latest-release link names at test time, and runs the "Scan of a repository"
  scenario on a repository it creates with one empty commit, asserting the exit status alone. Checked by reading
  `test.sh` in review.
- Scenarios a successful container build cannot show are checked by hand, once each, on amd64, the way the `glab` design
  describes: a malformed version (each form the scenario names), a version below the minimum, a release that does not
  exist, `latest` pointing to a `-test` tag and to a malformed tag, a digest mismatch, a missing or duplicated entry, an
  unsupported architecture, `/etc/os-release` removed, an unsupported distribution on `archlinux:latest`, a supported
  family without its package manager on `amazonlinux:2`, a failed second install, the same `version` twice (inode and
  modification time unchanged), an unreadable installed version (a stub that exits 1 is replaced), and a directory at
  the target (fails naming the path, directory left empty). Each result goes into the PR's Validation section.
  `install.sh` itself carries no test hook.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream also builds armv6, armv7, and x32, but CI has runners only for
  these two.
- Releases before `8.2.0`, which have no arm64 archive; upstream's v7 and earlier use other names and a different CLI.
- Any scan configuration, baseline, pre-commit hook, or `GITLEAKS_*` variable (the issue's Out of scope).
- Upstream's Homebrew formula, container images, and `go install` path.
- Authenticity of the release beyond what github.com's TLS gives: upstream publishes no signature and no key to pin.
- Repeating the manual checks under Goals in CI, for the reason the `glab` design gives.
- Images of a supported family that lack its package manager, and distroless images; the feature fails clearly on them.

## Options

The feature has one option, new in this change; the spec's Option requirement states it.

| Name      | Type     | Default    | Enum or proposals              | Meaning                                                                                                   |
| --------- | -------- | ---------- | ------------------------------ | --------------------------------------------------------------------------------------------------------- |
| `version` | `string` | `"latest"` | proposals `["latest","8.2.0"]` | The release to install: `latest`, or a release version at or above `8.2.0`, with or without a leading `v` |

- **Default `latest`.** Upstream's releases are now rare security patches, so `latest` costs nothing in churn and keeps
  a container on the patched release; users who need the exact version their pipeline pins set `version` to it, which is
  the feature's main use (`NOTES.md` says so). The duplicate test installs the first proposal that is not the default,
  `8.2.0`, first and the defaults second (Context), so the second install takes the replace path and the first exercises
  the minimum.
- **Rejected shapes.** An option for a configuration file, a baseline, or a hook — out of scope by the issue, and the
  spec rules it out; an `enum` of release versions — every upstream release would need a feature release, and `latest`
  would be impossible; a pre-release suffix as `betterleaks` accepts — upstream publishes no release candidates, only
  the three `-test` tags, which nobody should pin; the current release as the second proposal — it equals what `latest`
  resolves to, so the replace path would never run in CI.

## Decisions

- **Release archive from GitHub's release download URLs, integrity from the per-release checksum file.** As for
  `betterleaks`, with the checksum file named `gitleaks_<version>_checksums.txt`. The checksum file is the only
  verification upstream publishes, so feature-authoring.md's "Direct downloads" rule requires fetching it at install
  time, verifying the archive against it, and failing when it is missing or unreachable; it is unsigned and served from
  the same origin, so the spec states that it relies on TLS alone, as that rule requires. Rejected: digests pinned in
  the feature — forbidden by "No per-version hashes"; the Homebrew formula, the container images, and `go install` — for
  the reasons the `glab` design gives; GitHub's asset digest from the API — permitted but not required, and it would add
  a JSON parser for a digest from the same origin as the checksum file.
- **`latest` from the latest-release link, read without following it, validated as a plain release version.** The link
  skips pre-releases, so the `-test` tags cannot reach it; the validation rejects them anyway should one be marked a
  release. Rejected: the API's `releases/latest` and the release list — a JSON parser for nothing the redirect lacks.
- **Minimum version `8.2.0`.** The first release with a `linux_arm64` archive; every release since has the same archive
  names, layout, checksum file name, and `version` output (Context). Rejected: `8.0.0` with an amd64-only range — a
  version that installs on one architecture and fails on the other is a trap.
- **Version scenarios, one per image.** Four scenarios, each on a different compatibility image and each asserting the
  installed version: an explicit version on `debian:12` and on `fedora:44`, a leading `v` on `alpine:3.24` and on the
  Ubuntu base as its remote user. `scenarioArchitectures` selects amd64 and arm64, so each runs on both native runners.
  Rejected: every version form on every image, for the reason the `betterleaks` design gives.
- **Tests check `latest` against the latest-release link at test time**, as for `betterleaks`; `duplicate.sh` also
  asserts that the version differs from `8.2.0`.
- **The maintenance mode is documented, not enforced.** `NOTES.md` opens with upstream's status, the parity purpose, and
  the recommendation of `betterleaks`; the feature itself behaves like any other installer. Rejected: a build-time
  warning in the log — nobody reads a successful build's log; `deprecated: true` in the metadata — the feature is new
  and intended for use, and that flag hides it from the index and tools; a hard dependency on `betterleaks` — a user who
  installs gitleaks for parity does not need a second scanner.
- **`/usr/local/bin/gitleaks`, replaced atomically, with the target checked to be absent or a regular file; a POSIX test
  helper; prerequisites from the image's own repositories, only when missing, left installed.** As in the `betterleaks`
  design, for the same reasons; `git` because `gitleaks git` runs it.
- **The scan scenario uses a repository the test creates and asserts the exit status alone.** As for `betterleaks`:
  upstream documents exit 1 on findings, and its log wording is not a contract.

## Security review

- **Downloads:** the release archive and the checksum file for one version and architecture, and one header-only request
  for `latest`; all on github.com over HTTPS with one redirect to GitHub's asset host (URL inventory). Nothing is piped
  to a shell. The build-time `gitleaks version` call makes no request (Context).
- **Verification:** SHA-256 of the archive against its exact entry in the checksum file; the checksum file and the
  latest-release link rely on TLS alone, stated in the spec. This detects corruption and a mismatched file but not a
  compromised release pipeline.
- **Keys:** none; upstream signs nothing, so there is no key or identity to pin.
- **Metadata:** `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, `containerEnv`, lifecycle
  commands, `dependsOn`, and `installsAfter` are not declared.
- **Options:** only `version`, validated before use; no credential, configuration, or hook option, by design (issue
  #155).
- **Idempotency:** the spec's "Installing twice" requirement, reached through the skip check, the target check, and the
  atomic replace (Goals) and tested through the `version` proposals (Options).
- **Failure behavior:** the spec's failure scenarios, checked as described under Goals; every failure exits non-zero,
  which fails the image build. The build never runs a scan.
- **Maintenance mode:** a scanner that receives security patches only still receives them; the feature installs the
  release the user names or the latest patched one, and the documentation tells users where upstream's attention went.

## Supported images

The planned `test/gitleaks/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                                |
| -------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with most prerequisites present       |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl`, `ca-certificates`, and `git` |
| `alpine:3.24`                                      | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash            |
| `fedora:44`                                        | `dnf` path                                                                         |

The same list as `betterleaks` and `glab`, whose changes verified that all four tags publish amd64 and arm64 images.

## URL inventory

Every URL the feature's scripts access. All are fetched at build time by `install.sh`; the feature fetches nothing at
container start. It configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `x64` or `arm64`. The host of the redirect target in the last row may move (Goals).

| URL                                                                                                                                         | Purpose                                                      | When                                                                        | Verification                                                               | Evidence (2026-10-16)                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `https://github.com/gitleaks/gitleaks/releases/latest`                                                                                      | Resolve `latest` from the `Location` header, not followed    | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` | TLS; the tag must pass the version validation and the minimum              | `302`, `Location: https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1`            |
| `https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_linux_<arch>.tar.gz`                                  | Release archive holding `gitleaks`                           | Build                                                                       | TLS; SHA-256 against its exact entry in the checksum file (integrity only) | `8.2.0` and `8.30.1`, x64: `302` to the row below, then `200`; arm64 listed in the file |
| `https://github.com/gitleaks/gitleaks/releases/download/v<version>/gitleaks_<version>_checksums.txt`                                        | Checksum file for the release                                | Build                                                                       | TLS only; unsigned, same origin as the archive                             | `302` to the row below, then `200`; holds the `linux_x64` and `linux_arm64` lines       |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<path>?<signed query>`, redirect target of the two rows above | Where GitHub serves release assets; reached only by redirect | Build                                                                       | As the row that redirected to it                                           | Final host `release-assets.githubusercontent.com`, `200`, one redirect hop              |

The target of the latest-release link (`.../releases/tag/v<version>`) is only read from the header, never fetched. At
run time gitleaks contacts no host on its own.

## Risks / Trade-offs

- [Upstream stops publishing releases altogether, or archives the repository] → Existing releases and their checksum
  files stay downloadable from GitHub; `latest` keeps resolving to the last one. The feature keeps working until GitHub
  removes the assets; `NOTES.md` already tells users to move to `betterleaks`.
- [A security fix lands in a release whose archive names or `version` output change] → The install fails with a clear
  message, or the skip check replaces the binary needlessly; a PATCH release of the feature follows.
- [The checksum file is unsigned and served from the same origin, so a compromised release pipeline goes undetected] →
  The spec states integrity only; upstream has announced no signing, and the collection's `betterleaks` feature is the
  path users are pointed to.
- [GitHub changes the latest-release redirect or makes `Location` relative] → The feature reads the last path segment of
  either form and validates it; anything else fails clearly.
- [A release is published between a CI job's build and its test] → That job's comparison with the latest-release link
  fails; a re-run passes. Releases are months apart now.
- [github.com is unreachable or rate-limits the build] → The build fails; there is no mirror.
- [`latest` makes builds non-reproducible] → Users pin `version`, which is the parity use case; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.
- [GitHub moves its asset host] → Builds keep working over HTTPS with the checksum check; the move is noticed in the
  build log, and the next change to the feature updates the inventory.

## Open Questions

None.
