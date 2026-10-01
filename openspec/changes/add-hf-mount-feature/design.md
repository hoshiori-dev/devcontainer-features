# Design

## Context

Research for this change, re-checked against upstream on 2026-09-30; items marked 2026-10-01 were checked on that day:

- Latest upstream release: `v0.13.1` (2026-09-29). 32 releases since `v0.0.1` (2026-03-23), six in September 2026 alone
  (Releases API listing). Every release carries raw ELF assets named `<binary>-<arch>-linux` (`hf-mount`,
  `hf-mount-nfs`, `hf-mount-fuse`; `x86_64`, `aarch64`); since `v0.3.0` there is also
  `hf-mount-fuse-sidecar-<arch>-linux`, which serves only the Kubernetes CSI driver and shares the `hf-mount-fuse`
  prefix. The upstream README's "Manual download" table lists the same six Linux names.
- Upstream publishes no checksum file, no signature, and no build attestation (the attestations API returns 404); its
  `release.yml` ends with `gh release create "$TAG" artifacts/*`. The GitHub Releases API reports a `digest`
  (`sha256:<hex>`) for every asset, which GitHub computes on upload and serves from the same origin as the binary; the
  feature does not use it (Decisions, Source).
- `https://github.com/huggingface/hf-mount/releases/latest` answers 302 with the `Location`
  `https://github.com/huggingface/hf-mount/releases/tag/v0.13.1`; for a repository without a release the same path
  answers 302 to `…/releases`, which names no tag (2026-10-01). GitHub documents the link form in
  https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases.
- A download answers 302 to `release-assets.githubusercontent.com` and then 200 with a `Content-Length`; a release that
  does not exist and an asset name missing from an existing release both answer 404 (2026-10-01).
- The binaries target `*-unknown-linux-gnu`, are built on `ubuntu-22.04` runners, and need glibc 2.34 or later (highest
  symbol version on both architectures). The daemon links `libc.so.6` and `libgcc_s.so.1`; the backends also link
  `libm.so.6`. OpenSSL is vendored and nothing links libfuse: the FUSE backend uses its fuser fork's pure-Rust mount
  path. No musl build exists.
- The daemon starts `hf-mount-nfs` (default) or `hf-mount-fuse` (`--fuse`) from its own directory first, then from
  `PATH`.
- `hf-mount --version` prints `hf-mount 0.13.1`; `hf-mount status` with no daemon prints `No running daemons` to stderr,
  exits 0, and creates nothing. Both were run with no network in `mcr.microsoft.com/devcontainers/base:ubuntu24.04`, as
  root and as `vscode`, with the `v0.13.1` x86_64 daemon (2026-10-01).
- Runtime needs, from upstream source: the NFS backend calls `mount.nfs` (`nfs-common` on Debian and Ubuntu, `nfs-utils`
  on Fedora; the README's "no system dependencies" is wrong on Linux) and, as non-root, runs it and `umount` through
  `sudo -n`. The FUSE backend tries `mount(2)` on `/dev/fuse` for every user and falls back to `fusermount3` from
  `fuse3`; it mounts with `allow_other` unless `--fuse-owner-only` is given, which for non-root needs `user_allow_other`
  in `/etc/fuse.conf`. Any mount needs `CAP_SYS_ADMIN` and seccomp/AppArmor profiles that allow `mount`; FUSE also needs
  `/dev/fuse`. The feature metadata schema has no `devices` property, so only `privileged` could expose `/dev/fuse` from
  the feature itself.
- The duplicate test of devcontainer CLI 0.89.0 installs the feature twice in one build: first with the first value of
  each `enum` and `proposals` list that is not the default and with every boolean negated, then with no options (the
  defaults). With the options below that is `backend=nfs`, `installMountDependencies=false`, `version=0.13.1`, then
  `both`, `true`, `latest`. A scenario cannot install one feature twice.
- Images: `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (glibc 2.39, ships `curl`; 2026-10-01), `debian:12` (2.36),
  `ubuntu:22.04` (2.35), `fedora:44` (2.43) have amd64 and arm64 manifests; `debian:11` and `ubuntu:20.04` have 2.31.
  `nfs-common` and `fuse3` (Debian, Ubuntu) and `nfs-utils` and `fuse3` (Fedora) exist for both architectures.
- The base image tags `ubuntu24.04` and `noble` name one image (version 3.0.8, built 2026-09-10); the hyphenated
  `ubuntu-24.04` that `scripts/new_feature.ts` writes names another, version 2.0.5, built 2025-10-16 (2026-10-01).
- `hf-mount` reads `HF_TOKEN` or `--token-file` itself, so the feature needs no credential and no `hf-cli` dependency.

## Goals / Non-Goals

**Goals:**

- TLS alone, never weakened. Upstream publishes nothing to verify against, so no download is checked beyond TLS (spec:
  Downloads come from the upstream GitHub release and rely on TLS alone). Every request fails on an HTTP error status
  and on a non-HTTPS URL or redirect (`--proto =https` and `--proto-redir =https`), and no flag, configuration file, or
  environment variable relaxes certificate checking. Download redirects are followed without pinning their host, since
  GitHub has served release downloads from both `release-assets.githubusercontent.com` and
  `objects.githubusercontent.com`. Checked by review of the `curl` flags.
- All or nothing. All selected assets are downloaded into a temporary directory before any of them is installed, and a
  transfer that `curl` reports as failed or incomplete fails the run, so a failing run replaces nothing. Checked by
  review of `install.sh` and by the hand checks below.
- Exact asset names. The asset name is built from the fixed binary name and the mapped architecture, and only that name
  is requested, so `hf-mount-fuse-sidecar-*` can never be installed as `hf-mount-fuse-*`. Checked by review.
- The requested URLs are fixed by the feature. Every download URL is built from the template in the spec. The only value
  taken from a response is the tag in the latest-release redirect: that redirect is read, not followed, its `Location`
  must be exactly `https://github.com/huggingface/hf-mount/releases/tag/v<MAJOR.MINOR.PATCH>`, and anything else fails
  the run. Checked by review and by the latest-release hand check.
- No credential. No request carries a token or any other credential, and the feature reads none from its environment.
  Checked by review.
- One request resolves `latest`, and each selected binary takes one download; a pinned `version` makes no other request.
  Checked by review.
- Nothing changes before the platform checks pass. No package is installed and nothing is downloaded until the
  architecture, C library (glibc 2.34 or later), distribution, and `version` checks pass; no mount-dependency package is
  installed until every download has completed; and no binary is installed until those packages are in place, so a
  package failure leaves `/usr/local/bin` unchanged. The entry point is POSIX `sh` so an image without bash, such as
  Alpine, still gets the clear message. Checked by review, by `shellcheck` in `just check` (which takes the `sh` dialect
  from the shebang), and by the platform hand checks.
- Idempotent and additive, as the spec's Installing twice requirement states: every selected binary is downloaded and
  replaced by `install` with mode `0755` on each install, and none is skipped, since the feature compares no checksum
  and so cannot tell whether an installed file is the requested release; nothing is removed. Checked by `duplicate.sh`
  and the install-twice hand checks.
- Minimal package footprint: packages are installed with `--no-install-recommends` (apt) or
  `--setopt=install_weak_deps=False` (dnf), `curl` and `ca-certificates` only when missing, and package caches are
  cleaned. The temporary directory is removed on every exit. Checked by review and the `installMountDependencies`
  scenario.

**Non-Goals:**

- Verifying a checksum, a signature, or provenance: upstream publishes none (see Decisions and Risks).
- Mounting at build or start time, or any credential handling (issue #18, Out of scope).
- Supporting musl, glibc older than 2.34, other architectures, or distributions other than Debian, Ubuntu, and Fedora.
- Configuring `/etc/fuse.conf`, sudo rules, or container privileges; `NOTES.md` documents them instead.
- Removing binaries or packages a previous install added.

## Options

All three options are new. Where this table and the delta spec's Option requirements differ, the delta spec wins.

| Option                     | Type      | Default    | Enum or proposals                                      | Meaning                                                                       |
| -------------------------- | --------- | ---------- | ------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `version`                  | `string`  | `"latest"` | proposals: `latest` and the current release (`0.13.1`) | The upstream release to install; accepts `latest` or `MAJOR.MINOR.PATCH` only |
| `backend`                  | `string`  | `"both"`   | enum, in this order: `nfs`, `fuse`, `both`             | The backends installed next to the daemon, which is always installed          |
| `installMountDependencies` | `boolean` | `true`     | none                                                   | Whether the mount helpers of the selected backends are installed              |

- `version` defaults to `latest`: upstream releases several times a month, and following it needs no feature release per
  upstream release (Decisions, Source); users who need stability pin it (Risks).
- `backend` defaults to `both`, so either backend can be chosen at run time without a rebuild, at a cost of about 27 MB
  per backend.
- `installMountDependencies` defaults to `true`, since neither backend can mount without its helper.
- The enum order and the release in `proposals` decide the duplicate test's first install (Context): the test depends on
  that release staying downloadable, and refreshing a stale proposal is a PATCH bump.
- Rejected: a token option (issue #18: options appear in build logs); a separate option per backend (two booleans allow
  selecting none, which installs a daemon that cannot mount); accepting a leading `v` in `version` (two spellings of one
  value; the message names the accepted forms).

## Decisions

- **Source: raw release assets from `github.com/huggingface/hf-mount`, relying on TLS alone.** Decided by the maintainer
  in the pull request's conversation on 2026-10-01. Anchored in the download rules of
  `.agents/knowledge/feature-authoring.md`: upstream publishes no checksum or signature for any release, so the feature
  installs relying on TLS alone, stated as a spec Requirement; a digest computed by the hosting platform (GitHub's asset
  digest) "may be used, never required", and it is not used. Rejected: verifying against the Releases API `digest`, the
  choice of the earlier package (it is served from the same origin as the binary, so beyond TLS it only detects a
  corrupted download, and it costs one API request per install, the anonymous limit of 60 API requests per hour per
  address with the CI flakiness that follows, and `GITHUB_TOKEN` handling at build time); Homebrew on Linux (brings a
  whole package manager into the image); `cargo build` (Rust 1.89 or later and minutes per build); the upstream image
  `ghcr.io/huggingface/hf-mount-fuse` (holds only the FUSE backend and the sidecar); checksums pinned in the feature for
  an allow-list of versions (stronger against a compromised release, but the download rules forbid per-version hashes
  without a change to the rule, and it would mean no `latest` and a feature release for every upstream release, which
  comes several times a month).
- **`latest` is resolved from the release redirect.** `https://github.com/huggingface/hf-mount/releases/latest` answers
  with a redirect to the latest release's tag page (Context), and the tag is read from it under the bound in Goals.
  Rejected: the Releases API, which brings back the rate limit and the token handling that the Source decision drops.
- **A 404 on a download names the version, the asset, the URL, and the status.** A release that does not exist and an
  asset missing from an existing release answer alike (Context), so one message serves the spec's "Release does not
  exist" and "Asset missing from the release". Rejected: a request to the release's tag page to tell them apart (one
  more URL, only for a more specific message).
- **Install location: `/usr/local/bin`, all binaries side by side.** The daemon finds its backend next to itself first,
  and `/usr/local/bin` is on `PATH` in every supported image, so no environment change is needed. Rejected: a versioned
  directory with symlinks (no second version needs to coexist).
- **Mount dependencies per distribution:** `nfs-common` (apt) or `nfs-utils` (dnf) for NFS, `fuse3` for FUSE. The
  distribution is taken from `ID` in `/etc/os-release` (`debian`, `ubuntu`, `fedora`) and checked on every install, also
  when no package is needed. Rejected: accepting any `ID_LIKE` match (derivatives such as RHEL clones or Mint would ship
  untested); checking the distribution only when a package must be installed (whether an image is supported would then
  depend on which packages it happens to ship and on `installMountDependencies`, and none of those images is tested).
- **`NOTES.md` content bounds.** It names the container settings a mount needs (`--cap-add SYS_ADMIN`,
  `--device /dev/fuse` for FUSE, `--security-opt apparmor=unconfined` where AppArmor applies, or `--privileged` as the
  broad alternative), the non-root prerequisites (passwordless `sudo` for NFS; `user_allow_other` in `/etc/fuse.conf` or
  `--fuse-owner-only` for FUSE), and that the downloads are checked against no checksum or signature, since upstream
  publishes none, and rest on TLS alone.
- **Tests.** Container tests assert only what needs no privileges and no network: `hf-mount --version` (the
  `hf-mount <MAJOR.MINOR.PATCH>` form only; `test.sh` makes no network request, since `latest` can move between build
  and test), `hf-mount status`, the backend files, `mount.nfs` or `fusermount3` presence, no `hf-mount` process (read
  from `/proc/*/comm`, so no `procps` is needed), and no uncommented `user_allow_other` in `/etc/fuse.conf`.
  `duplicate.sh` asserts the spec's "Non-default options, then the defaults". Scenarios, on `debian:12` amd64, cover
  `backend` `nfs` and `fuse`, `installMountDependencies` disabled, and a pinned `version`. Everything else is a hand
  check (below).

## Hand checks

How each spec scenario outside the container tests is provoked; results go to the PR's Validation section.

- Version: `version` set to `v0.13.1`, `0.13`, and `9.9.9`.
- Downloads: copies of `install.sh` with a binary name altered ("Asset missing from the release", whose 404 also shows
  "HTTP error") and with the latest-release URL naming a repository that has no release ("Latest release cannot be
  resolved"). Each run must leave `/usr/local/bin` as it was. The non-HTTPS redirect of "HTTP error" is checked by
  review of the `curl` flags.
- Platforms: `alpine` (musl), `debian:11` (glibc 2.31), a glibc 2.34 or later image of another distribution such as
  `rockylinux:9` (RHEL 9, glibc 2.34), and a third architecture under emulation where available, otherwise a copy of
  `install.sh` with the detected architecture altered.
- Installing twice: an image built with the first options, then built on again with the second: same options twice;
  `backend` `nfs` then `fuse`; `version` `0.13.1` then `0.13.0`, with each binary's SHA-256 compared by hand to the
  digest the Releases API reports for the older release's asset.
- Mounts: one mount of a small public repository per backend with the `runArgs` `NOTES.md` names, as root and as
  `vscode` on `mcr.microsoft.com/devcontainers/base:ubuntu24.04`.

## Security review surface

- Downloads and verification: the URL inventory below, bounded as the Goals state (TLS alone and never weakened, exact
  asset names, requested URLs fixed by the feature, HTTPS only, all downloaded before any is installed).
- Keys: none. Upstream signs nothing and publishes no checksum, so nothing is pinned or verified; the trade-off is under
  Risks.
- Credentials: none. No request carries a credential and the feature reads none; no option carries one, and Hugging Face
  tokens stay with `hf-mount` at run time.
- User-scoped setup: none. The feature writes no per-user state, does not use `_REMOTE_USER` or `_CONTAINER_USER`, and
  leaves `/etc/fuse.conf` and the sudo configuration untouched.
- Idempotency: additive, as the spec's Installing twice requirement states and the Goals bound it.
- Supported images: the planned list below.
- Failure behavior: every failure the spec names ends the build with a message naming its cause and, within the bounds
  in Goals, leaves `/usr/local/bin` unchanged; a failure after the platform checks may leave `curl` or `ca-certificates`
  installed.
- Metadata (each property the feature could set, and why it stays unset):

| Property                                      | Value | Justification                                                                                                                                                                                                          |
| --------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `privileged`, `capAdd`, `securityOpt`, `init` | none  | Mounting is out of scope at build and start; a mount needs `CAP_SYS_ADMIN` and, for FUSE, `/dev/fuse`, which only `privileged` could grant from a feature, far too broad as a default. `NOTES.md` names the `runArgs`. |
| `mounts`                                      | none  | The feature needs no host path or volume.                                                                                                                                                                              |
| `entrypoint`, lifecycle commands              | none  | Nothing runs after the build.                                                                                                                                                                                          |
| `containerEnv`                                | none  | Binaries are on the default `PATH`; credentials are the user's (`HF_TOKEN`).                                                                                                                                           |
| `dependsOn`, `installsAfter`                  | none  | The feature installs its own download tools; `hf-mount` reads `HF_TOKEN` itself, so `hf-cli` is not needed.                                                                                                            |

## Supported images (planned `test/hf-mount/compatibility.json`)

| Image                                              | Arch         | remoteUser | Why                                            |
| -------------------------------------------------- | ------------ | ---------- | ---------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu24.04` | amd64, arm64 | `vscode`   | The common dev container base; non-root checks |
| `debian:12`                                        | amd64, arm64 | —          | Debian, glibc 2.36, minimal image; scenarios   |
| `ubuntu:22.04`                                     | amd64, arm64 | —          | Oldest supported glibc family (2.35)           |
| `fedora:44`                                        | amd64, arm64 | —          | The dnf path (`nfs-utils`)                     |

Excluded: `alpine` (musl), `debian:11` and `ubuntu:20.04` (glibc 2.31). `fedora:44` is included by the maintainer's
decision (2026-10-01). The first entry names the maintained tag `ubuntu24.04`, not the `ubuntu-24.04` that
`scripts/new_feature.ts` writes into a new `compatibility.json` (Context).

## URL inventory

Every URL the feature's scripts access. The feature configures no package repository: `nfs-common`, `nfs-utils`,
`fuse3`, `curl`, and `ca-certificates` come from the repositories preconfigured in the image. It fetches nothing at
start or run time (a mount started later by the user talks to Hugging Face, which is `hf-mount`'s own traffic), and it
has no `dependsOn` or `installsAfter`.

| URL / template                                                                   | Purpose                                                        | When  | Integrity / authenticity                                                                                              | Official source evidence                                                                                                                                         | Verified                                                                                                                                                       |
| -------------------------------------------------------------------------------- | -------------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://github.com/huggingface/hf-mount/releases/latest`                        | Resolve `version=latest`: the tag in the redirect's `Location` | build | TLS alone; the `Location` must be exactly `https://github.com/huggingface/hf-mount/releases/tag/v<MAJOR.MINOR.PATCH>` | The `/releases/latest` link form in https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases                                     | 2026-10-01: 302 to `https://github.com/huggingface/hf-mount/releases/tag/v0.13.1`                                                                              |
| `https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`   | Download `hf-mount`, `hf-mount-nfs`, `hf-mount-fuse`           | build | TLS alone: no upstream checksum or signature exists, and none is verified                                             | Upstream README "Manual download" (https://github.com/huggingface/hf-mount) links GitHub Releases and lists the asset names; upstream `release.yml` uploads them | 2026-09-30: 302 then 200 for all six `v0.13.1` Linux assets of the three binaries on both architectures; 2026-10-01: 404 for `v9.9.9` and for an unknown asset |
| `https://release-assets.githubusercontent.com/github-production-release-asset/…` | Redirect target of the download (not requested directly)       | build | Same as the download                                                                                                  | Listed among GitHub's hosts in https://docs.github.com/en/actions/reference/runners/self-hosted-runners, which also lists `objects.githubusercontent.com`        | 2026-09-30: the only redirect host of all six downloads; `objects.githubusercontent.com` was not observed but is allowed, since redirects are not host-pinned  |

## Risks / Trade-offs

- [No download is verified beyond TLS: whoever can upload to the upstream release can supply the binary the feature
  installs] → Accepted by the maintainer and stated in the spec and `NOTES.md`; upstream publishes nothing to verify
  against; a pinned `version` limits exposure to the chosen release; pinned checksums would be stronger but need a
  change to the download rules (Decisions).
- [A file corrupted on GitHub's side is not detected, since no digest is compared] → TLS protects the transfer and a
  transfer `curl` reports as incomplete fails the run (Goals); the container tests run the installed daemon, while a
  corrupted backend would surface only when a mount is started.
- [`github.com` answers the latest-release request or a download with an HTTP error] → The install fails with the
  message of the spec's "HTTP error" and the job is re-run; no API request is made, so the API's anonymous rate limit no
  longer applies.
- [Upstream renames or transfers the repository] → A latest-release redirect other than the one named in Goals fails the
  run; the fix is a feature change.
- [`latest` moves several times a month, so a rebuild can bring a new upstream version or a new glibc floor] → The glibc
  check fails clearly; users who need stability pin `version`.
- [A backend left from an earlier install at an older version sits next to a newer daemon] → Stated in the spec as the
  additive behavior; reinstalling with that backend selected updates it.
- [Upstream renames assets or drops `aarch64`] → The download answers 404 and the install fails with the missing asset
  named; the fix is a feature change.
- [Upstream deletes the release in `proposals`] → The duplicate test's first install fails; refreshing the proposal is a
  PATCH bump (Options).
- [`nfs-common` pulls `rpcbind`, whose maintainer scripts were not yet run inside a container build] → The default
  install on every compatibility image exercises it; a failure there is resolved before the PR is marked ready.
- [Each backend is about 27 MB, so `both` adds about 55 MB] → `backend` narrows it.
