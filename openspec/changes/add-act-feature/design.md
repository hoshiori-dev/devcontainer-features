# Design

## Context

See proposal.md - Why. The feature follows the `gitleaks` feature (archived change `2026-10-16-add-gitleaks-feature`),
itself derived from `betterleaks` and `glab`: a static Go binary from upstream's release archives, verified against the
release's checksum list, installed atomically to `/usr/local/bin`. What differs is written below; what is the same is
named, not repeated. The interface (the options, their defaults, the environment variable, and the absence of a Docker
dependency) was agreed with the maintainer in conversation before this change and is recorded in issue #181. Upstream
facts this change relies on, checked on 2026-10-23 against github.com (the release API of `nektos/act`, all pages; the
release files of `v0.2.23`, `v0.2.50`, `v0.2.70`, `v0.2.80`, and `v0.2.89`; `.goreleaser.yml`, `cmd/root.go`, and
`cmd/notices.go` on `master`) and by running the `0.2.23` and `0.2.89` amd64 binaries, each verified against its
checksum file:

- The latest release is `v0.2.89` (2026-06-01); GitHub's latest-release link redirects (`302`) to
  `https://github.com/nektos/act/releases/tag/v0.2.89`. Upstream releases monthly. Of 97 releases, every one from
  `v0.2.3` on is a plain `vMAJOR.MINOR.PATCH` tag not marked pre-release; `v0.2.0` to `v0.2.2` are marked pre-release.
- `.goreleaser.yml` builds with `CGO_ENABLED=0` and names archives `act_Linux_x86_64.tar.gz` and
  `act_Linux_arm64.tar.gz` (beside armv6, armv7, i386, riscv64, darwin, and windows builds), with `checksums.txt` in
  `sha256sum` format listing every archive. `act_Linux_arm64.tar.gz` first appears in `v0.2.23` (2021-06-11); `v0.2.22`
  and earlier have no arm64 archive. No release carries a signature, bundle, SBOM, or attestation.
- The archive holds `act` (mode 0755, at the root), `LICENSE`, and `README.md`, the same in `0.2.23` and `0.2.89`. The
  `0.2.89` binary runs on `alpine:3.24`.
- `act --version` prints `act version <version>` in both binaries run. Run with an empty `HOME`, it creates the empty
  directory `$HOME/.config/act` (the XDG library creates the parent of the configuration file it resolves).
- act reads its arguments from `$XDG_CONFIG_HOME/act/actrc` (default `~/.config/act/actrc`), then `~/.actrc`, then
  `./.actrc`. When none of them yields a `-P` and none is given on the command line, a run (not `--list`) shows an
  interactive prompt for Large, Medium, or Micro and writes the matching `-P` lines to the first location; without a
  terminal the prompt fails with `level=fatal msg=EOF` (reproduced with `0.2.89`, `act --dryrun`, stdin from
  `/dev/null`). With a configuration file holding a `-P ubuntu-latest=…` line the same run succeeds. The lines written
  per choice are those the spec lists; Micro writes `node:16-buster-slim` and `node:16-bullseye-slim`.
- `cmd/notices.go` requests `https://api.nektosact.com/notices` on each run unless `ACT_DISABLE_VERSION_CHECK` is `1`.
- act talks to the Docker Engine API through the socket `DOCKER_HOST` or the default `/var/run/docker.sock` names; it
  does not run the `docker` CLI. `act --list` and its parsing work without a reachable engine.
- `ghcr.io/devcontainers/features/docker-in-docker` declares `privileged: true` and an `entrypoint`, and its
  `install.sh` accepts only the Debian and RHEL/Fedora/Azure Linux families, not Alpine.
- The planned images are the four of the `gitleaks` compatibility list; the same prerequisites apply, minus `git`.
- The devcontainer CLI's duplicate test installs a string option first with the first `proposals` or `enum` value that
  is not its default, then with the defaults.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `#!/bin/sh` with `set -eu`, since Alpine ships no bash. Checked by shellcheck in `just check`
  and by the Alpine entry of the compatibility list.
- Every download goes through `curl` restricted to HTTPS for the request and every redirect, requests only the URLs in
  the URL inventory below, and prints each final URL without its signed query string, as in the `gitleaks` design.
  Checked by reviewing each `curl` call against the inventory and one CI build log.
- The `version` value is validated against `latest` or `v?MAJOR.MINOR.PATCH` (decimal numbers only) before it enters a
  URL, a file name, or a comparison; the tag read from the latest-release redirect passes the same validation and the
  minimum. `defaultImage` is matched against its three values before anything else happens. Checked by the manual checks
  below.
- Every check that needs no network — the options' form, the minimum version, the architecture, the distribution, its
  package manager, the target path being absent or a regular file, and, when `defaultImage` is not `none`, the
  configuration path being absent or a regular file — runs before any package is installed or anything is downloaded.
  Checked by the manual checks below on `debian:12`, which still lacks `curl` after each of them.
- The configuration file is written after the binary is in place, to a temporary file in its own directory that is then
  renamed over it, with ownership set to the remote user's UID and primary GID before the rename. Only directories the
  feature creates are given to the remote user; existing ones keep their owner. Checked by the
  `test_default_image_medium` scenario as the `vscode` user and by reading `install.sh` in review.
- The build-time `act --version` call runs with `HOME` and `XDG_CONFIG_HOME` in the install's temporary directory and
  `ACT_DISABLE_VERSION_CHECK=1`, so it creates nothing in a real home and makes no request. Checked by the "Nothing else
  configured after install" scenario in `test.sh`, before `test.sh` runs `act` itself.
- Package installs (`curl`, `ca-certificates`, and `tar` only when missing), the cache cleanup, the checksum selection
  of exactly one entry, the temporary directory and staged binary under one `trap`, the atomic rename, and the skip
  check on the parsed `act --version` output: as in the `gitleaks` design, checked the same way; the directories are
  `${TMPDIR:-/tmp}/act-feature.XXXXXX` and `/usr/local/bin/.act-feature.XXXXXX`.
- `test.sh` checks the "Nothing else configured after install" scenario first, compares `act --version` with the tag the
  latest-release link names at test time, checks `ACT_DISABLE_VERSION_CHECK`, checks that neither `docker` nor `dockerd`
  resolves, and runs `act --list` on a repository it creates with one workflow, asserting the exit status and that the
  job id appears. Checked by reading `test.sh` in review.
- The `defaultImage` scenarios compare the configuration file byte for byte with the lines in the spec and, for
  `medium`, run `act --dryrun` with stdin from `/dev/null` on a repository the script creates, asserting exit 0. A dry
  run creates no container and needs no engine (Context). Checked by reading the scenario scripts in review.
- Scenarios a successful container build cannot show are checked by hand, once each, on amd64, the way the `gitleaks`
  design describes: a malformed version (each form the scenario names), a version below the minimum, a release that does
  not exist, `latest` pointing to a malformed tag, a digest mismatch, a missing or duplicated entry, an unsupported
  architecture, `/etc/os-release` removed, an unsupported distribution on `archlinux:latest`, a supported family without
  its package manager on `amazonlinux:2`, a failed second install, the same `version` twice (inode and modification time
  unchanged), an unreadable installed version (a stub that exits 1 is replaced), a directory at the target, and a
  directory at the configuration path with `defaultImage=medium` (fails naming the path, directory left as it was). Each
  result goes into the PR's Validation section. `install.sh` itself carries no test hook.
- "Running a job with a Docker Engine" needs a privileged container, which no scenario may declare (testing.md, Running
  the installer). It is checked by hand once on amd64: a dev container with docker-in-docker and this feature, a
  workflow with one `echo` step, `act -P ubuntu-latest=node:24-bookworm-slim`, expecting exit 0 and the echoed text. The
  result goes into the PR's Validation section.

**Non-Goals:**

- Architectures other than amd64 and arm64: upstream also builds armv6, armv7, i386, and riscv64, but CI has runners
  only for these two.
- Releases before `0.2.23`, which have no arm64 archive.
- Installing, configuring, or checking a container engine (the issue's Out of scope); `NOTES.md` explains the choices.
- The `micro` default image, runner images other than the ones act's own prompt writes, and keeping those lines current
  with newer Ubuntu labels: a user who needs `ubuntu-24.04` adds a `-P` line to their own configuration.
- The `gh act` extension, IDE extensions, `.secrets`, `.env`, `.vars`, and event payload files.
- Authenticity of the release beyond what github.com's TLS gives, and of the runner images act pulls at run time.
- Repeating the manual checks under Goals in CI, for the reason the `glab` design gives.
- Images of a supported family that lack its package manager, and distroless images; the feature fails clearly on them.

## Options

The feature has two options, both new in this change; the spec's Option requirements state them.

| Name           | Type     | Default    | Enum or proposals                | Meaning                                                                                                    |
| -------------- | -------- | ---------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `version`      | `string` | `"latest"` | proposals `["latest","0.2.80"]`  | The release to install: `latest`, or a release version at or above `0.2.23`, with or without a leading `v` |
| `defaultImage` | `string` | `"none"`   | enum `["none","medium","large"]` | Runner images to preselect in the remote user's act configuration file; `none` writes no file              |

- **`version` default `latest`.** act releases monthly with fixes for GitHub Actions compatibility, so the newest
  release is what most users want; a project that needs reproducible builds pins `version`. The second proposal,
  `0.2.80`, is an older release than `latest`, so the duplicate test's first install is replaced by the second.
  Rejected: the minimum `0.2.23` as the second proposal — a four-year-old release is a poor suggestion in the generated
  README, and the minimum's arm64 archive was verified by hand (Context); the current release — it equals what `latest`
  resolves to, so the replace path would never run in CI.
- **`defaultImage` default `none`.** The feature writes nothing into a home directory unless asked, as the collection's
  other installers; a developer at a terminal answers act's prompt once. Changing the default later to a value that
  writes a file would only add behavior, while the reverse would remove it from users relying on it. The duplicate test
  installs `medium` first and `none` second, which exercises "Default images selected, then none".
- **`micro` left out.** Upstream maps it to `node:16` images, which are end of life; offering it would endorse them.
  Rejected: remapping `micro` to a current Node image — the option's promise is "what act's own prompt writes", and a
  remapped value would silently diverge from upstream's documentation.
- **Rejected shapes.** A free-form string of `-P` lines or an image name — a configuration that runs arbitrary images is
  visible in `devcontainer.json` either way, but a free-form value needs parsing and escaping into a file, and a user
  with custom images keeps their own `actrc` in the repository (`./.actrc`), which act already reads; a boolean
  `configureDefaults` — it hides which images are selected; an option for secrets or variables — out of scope by the
  issue, and the spec rules it out.

## Decisions

- **Release archive from GitHub's release download URLs, integrity from the per-release checksum file.** As in the
  `gitleaks` design, with the checksum file named `checksums.txt` and the architectures named `x86_64` and `arm64`.
  Rejected: upstream's `install.sh` piped from `raw.githubusercontent.com` — the documented one-liner pipes into a
  shell, which feature-authoring.md forbids, and the script fetches the same archive and checksum file the feature
  fetches directly; Homebrew, the AUR, COPR, and Nix — none covers all four planned distributions; `go install` — a Go
  toolchain for one binary; the `gh act` extension — needs `gh` and installs per user.
- **`latest` from the latest-release link, read without following it, validated as a plain release version.** As in the
  `gitleaks` design.
- **Minimum version `0.2.23`.** The first release with a `linux_arm64` archive; the archive names, layout, checksum file
  name, and `--version` output are the same from there to `0.2.89` (Context). Rejected: a higher minimum such as
  `0.2.60` — nothing in the tested range differs, so a higher bound only takes choices away from users pinning an old
  pipeline; `0.2.0` with an amd64-only range — a version that installs on one architecture and fails on the other is a
  trap.
- **No dependency on a Docker feature, ordered after both of `devcontainers/features`.** act needs a Docker Engine API,
  not a particular one. `dependsOn` on docker-in-docker would make every act user's container privileged and add its
  entrypoint, give a second daemon and a conflicting socket to users of docker-outside-of-docker or a remote
  `DOCKER_HOST`, make the feature uninstallable on Alpine, and force every test of this feature to run privileged.
  `installsAfter` costs nothing when neither is present and keeps ordering deterministic when one is; `NOTES.md` shows
  both combinations and says why neither is a dependency. Rejected: `dependsOn` on docker-in-docker — the reasons above;
  `dependsOn` on docker-outside-of-docker — it needs the host's socket mounted, which only the user's configuration can
  provide; a build-time or start-time check for a socket — the daemon of docker-in-docker starts only with the
  container, and act's own error when the socket is missing names it.
- **`ACT_DISABLE_VERSION_CHECK=1` in `containerEnv`.** The same reasoning as `DENO_NO_UPDATE_CHECK` in the `deno`
  feature: the feature manages the version, and the request leaves the container on every run. Rejected: leaving it to
  the user — every user would want it, and a user who wants the notices sets the variable to `0` in their own
  `containerEnv`, which overrides the feature's.
- **Configuration at `<home>/.config/act/actrc`.** It is the location act's own prompt writes to and the first act reads
  (Context). Rejected: `~/.actrc` — act reads it too, but it would sit beside a file the prompt may later create in the
  XDG location; `/etc/act/actrc` or a wrapper script — act has no system-wide location, and a wrapper would change what
  `act` is; reading `XDG_CONFIG_HOME` at build time — the build environment says nothing about the running container's.
- **A later `none` leaves the configuration file.** The feature cannot tell a file it wrote from one a user or another
  layer wrote, and deleting a user's file is worse than keeping a stale one. The spec states it.
- **Replace an existing regular configuration file, refuse anything else.** A user who sets `defaultImage` asks for that
  content; a symbolic link or directory at the path is unexpected and following it as root could write elsewhere, so the
  install fails naming the path, as the target check does for `/usr/local/bin/act`.
- **`/usr/local/bin/act`, replaced atomically, with the target checked to be absent or a regular file; a POSIX test
  helper; prerequisites from the image's own repositories, only when missing, left installed.** As in the `gitleaks`
  design, for the same reasons, without `git`: act reads repositories with its own Go library.
- **Scenarios.** Version scenarios as in the `gitleaks` design, with `0.2.80`: an explicit version on `debian:12` and on
  `fedora:44`, a leading `v` on `alpine:3.24` and on the Ubuntu base as its remote user. `test_default_image_medium` on
  the Ubuntu base as `vscode` (ownership, content, dry run without a terminal) and `test_default_image_large` on
  `alpine:3.24` as root (content in root's home). `scenarioArchitectures` selects amd64 and arm64.

## Security review

- **Downloads:** the release archive and the checksum file for one version and architecture, and one header-only request
  for `latest`; all on github.com over HTTPS with one redirect to GitHub's asset host (URL inventory). Nothing is piped
  to a shell. The build-time `act --version` call makes no request (Goals).
- **Verification:** SHA-256 of the archive against its exact entry in the checksum file; the checksum file and the
  latest-release link rely on TLS alone, stated in the spec. This detects corruption and a mismatched file but not a
  compromised release pipeline.
- **Keys:** none; upstream signs nothing, so there is no key or identity to pin.
- **Metadata:** `containerEnv` sets one variable that turns a request off; `installsAfter` names two features and only
  orders them. `mounts`, `capAdd`, `privileged`, `securityOpt`, `init`, `entrypoint`, lifecycle commands, and
  `dependsOn` are not declared. The feature never widens what the container may do; a user who adds docker-in-docker
  accepts its privileges in their own configuration, and `NOTES.md` says so.
- **Runner images:** `defaultImage` writes the names of third-party images (`catthehacker/ubuntu`) that act pulls from
  Docker Hub at run time and runs workflow steps in. The feature only writes the names act's own prompt writes; the spec
  states the accepted risk. A workflow run by act can do anything the Docker Engine allows, which is act's nature and
  the user's choice to invoke.
- **Files written as root in a home directory:** one file and the missing directories on its path, owned by the remote
  user afterwards; a non-regular file at the path fails the install instead of being followed (Decisions).
- **Options:** `version`, validated before use, and `defaultImage`, an `enum`; no credential, secret, or payload option,
  by design.
- **Idempotency:** the spec's "Installing twice" requirement, reached through the skip check, the target check, the
  atomic replace, and the configuration rules (Decisions), tested through the duplicate test (Options).
- **Failure behavior:** the spec's failure scenarios, checked as described under Goals; every failure exits non-zero,
  which fails the image build. The build never runs a workflow or pulls an image.

## Supported images

The planned `test/act/compatibility.json`, every entry with `"arch": ["amd64", "arm64"]` and
`"scenarioArchitectures": ["amd64", "arm64"]`; the Ubuntu base entry also sets `"remoteUser": "vscode"`:

| Image                                              | Why                                                                     |
| -------------------------------------------------- | ----------------------------------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | The usual dev container base; `apt-get` path with a non-root user       |
| `debian:12`                                        | Minimal `apt-get` image; the feature installs `curl` and certificates   |
| `alpine:3.24`                                      | musl and BusyBox; `apk` path, and proves `install.sh` runs without bash |
| `fedora:44`                                        | `dnf` path                                                              |

The same list as `gitleaks`, `betterleaks`, and `glab`, whose changes verified that all four tags publish amd64 and
arm64 images.

## URL inventory

Every URL the feature's scripts access. All are fetched at build time by `install.sh`; the feature fetches nothing at
container start. It configures no package repository and has no feature OCI reference. `<version>` has no leading `v`;
`<arch>` is `x86_64` or `arm64`. The host of the redirect target in the last row may move (Goals).

| URL                                                                                                                                         | Purpose                                                      | When                                                                        | Verification                                                               | Evidence (2026-10-23)                                                              |
| ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------- | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| `https://github.com/nektos/act/releases/latest`                                                                                             | Resolve `latest` from the `Location` header, not followed    | Build, only for `version=latest`; also read by `test.sh` and `duplicate.sh` | TLS; the tag must pass the version validation and the minimum              | `302`, `Location: https://github.com/nektos/act/releases/tag/v0.2.89`              |
| `https://github.com/nektos/act/releases/download/v<version>/act_Linux_<arch>.tar.gz`                                                        | Release archive holding `act`                                | Build                                                                       | TLS; SHA-256 against its exact entry in the checksum file (integrity only) | `0.2.23` and `0.2.89`, x86_64: `302` to the row below, then `200`; digest equal    |
| `https://github.com/nektos/act/releases/download/v<version>/checksums.txt`                                                                  | Checksum file for the release                                | Build                                                                       | TLS only; unsigned, same origin as the archive                             | `200`; one `act_Linux_arm64.tar.gz` line in `0.2.23`, `0.2.50`, `0.2.70`, `0.2.89` |
| `https://release-assets.githubusercontent.com/github-production-release-asset/<path>?<signed query>`, redirect target of the two rows above | Where GitHub serves release assets; reached only by redirect | Build                                                                       | As the row that redirected to it                                           | Final host `release-assets.githubusercontent.com`, one redirect hop                |

The target of the latest-release link (`.../releases/tag/v<version>`) is only read from the header, never fetched. At
run time act contacts Docker Hub through the engine when a job needs an image, and `api.nektosact.com` only when a user
sets `ACT_DISABLE_VERSION_CHECK` to something other than `1`; the feature itself requests neither.

## Risks / Trade-offs

- [Upstream changes the lines its prompt writes, for example adding `ubuntu-24.04`] → The feature keeps writing the
  lines in its spec until a feature change follows; users add labels in their own `./.actrc`. A difference is visible by
  comparing `cmd/root.go` with the spec.
- [`catthehacker/ubuntu` stops publishing a tag the configuration names] → act fails to pull that image for jobs on that
  label; the feature cannot fix a third-party image and the next feature change can follow upstream's prompt.
- [`XDG_CONFIG_HOME` set at run time to another directory] → act prompts again; the spec states it, and `NOTES.md` says
  where the file is.
- [A user installs no Docker feature] → The build succeeds and `act` fails at run time naming the missing socket;
  `NOTES.md` explains the two combinations.
- [A release changes the archive names or the `--version` output] → The install fails clearly, or the skip check
  replaces the binary needlessly; a PATCH release of the feature follows.
- [The checksum file is unsigned and served from the same origin, so a compromised release pipeline goes undetected] →
  The spec states integrity only; upstream has announced no signing.
- [A release is published between a CI job's build and its test] → That job's comparison with the latest-release link
  fails; a re-run passes. Releases are a month apart.
- [GitHub changes the latest-release redirect, moves its asset host, or is unreachable] → As in the `gitleaks` design.
- [`latest` makes builds non-reproducible] → Users pin `version`; `NOTES.md` says so.
- [A distribution derivative accepted through `ID_LIKE` is not in the compatibility list] → Accepted because its package
  manager matches, but only listed images are supported; `NOTES.md` points to the compatibility list.

## Open Questions

None.
