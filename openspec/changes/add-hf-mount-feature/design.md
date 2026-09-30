# Design

## Context

Research for this change, re-checked against upstream on 2026-09-30:

- Latest upstream release: `v0.13.1` (2026-09-29). 32 releases since `v0.0.1` (2026-03-23), six in September 2026 alone
  (Releases API listing). Every release carries raw ELF assets named `<binary>-<arch>-linux` (`hf-mount`,
  `hf-mount-nfs`, `hf-mount-fuse`; `x86_64`, `aarch64`); since `v0.3.0` there is also
  `hf-mount-fuse-sidecar-<arch>-linux`, which serves only the Kubernetes CSI driver and shares the `hf-mount-fuse`
  prefix. The upstream README's "Manual download" table lists the same six Linux names.
- Upstream publishes no checksum file, no signature, and no build attestation (the attestations API returns 404); its
  `release.yml` ends with `gh release create "$TAG" artifacts/*`. The GitHub Releases API reports a `digest`
  (`sha256:<hex>`) for every asset, which GitHub computes on upload; every Linux asset of all 32 releases has one of the
  form `sha256:` plus 64 hex characters. Four `v0.13.1` assets were streamed and hashed and matched their digests.
- The binaries target `*-unknown-linux-gnu`, are built on `ubuntu-22.04` runners, and need glibc 2.34 or later (highest
  symbol version on both architectures). The daemon links `libc.so.6` and `libgcc_s.so.1`; the backends also link
  `libm.so.6`. OpenSSL is vendored and nothing links libfuse: the FUSE backend uses its fuser fork's pure-Rust mount
  path. No musl build exists.
- The daemon starts `hf-mount-nfs` (default) or `hf-mount-fuse` (`--fuse`) from its own directory first, then from
  `PATH`.
- `hf-mount --version` prints `hf-mount 0.13.1`; `hf-mount status` with no daemon prints `No running daemons` to stderr,
  exits 0, and creates nothing. Both were run with no network in `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`, as
  root and as `vscode`, with the `v0.13.1` x86_64 daemon after its SHA-256 matched the API digest.
- Runtime needs, from upstream source: the NFS backend calls `mount.nfs` (`nfs-common` on Debian and Ubuntu, `nfs-utils`
  on Fedora; the README's "no system dependencies" is wrong on Linux) and, as non-root, runs it and `umount` through
  `sudo -n`. The FUSE backend tries `mount(2)` on `/dev/fuse` for every user and falls back to `fusermount3` from
  `fuse3`; it mounts with `allow_other` unless `--fuse-owner-only` is given, which for non-root needs `user_allow_other`
  in `/etc/fuse.conf`. Any mount needs `CAP_SYS_ADMIN` and seccomp/AppArmor profiles that allow `mount`; FUSE also needs
  `/dev/fuse`. The feature metadata schema has no `devices` property, so only `privileged` could expose `/dev/fuse` from
  the feature itself.
- Anonymous GitHub API requests are limited to 60 per hour per address (`x-ratelimit-limit: 60` observed); authenticated
  requests get 5,000 per hour (https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api).
- A feature's `install.sh` runs inside the image build and sees only the build's environment: the image's `ENV` and the
  `containerEnv` of features installed before it. The dev container CLI passes no host variable to it; its
  `--secrets-file` applies to lifecycle commands, not to the build. `devcontainer features test` sets no `GITHUB_TOKEN`.
- The duplicate test of devcontainer CLI 0.89.0 installs the feature twice in one build: first with the first value of
  each `enum` and `proposals` list that is not the default and with every boolean negated, then with no options (the
  defaults). With the options below that is `backend=nfs`, `installMountDependencies=false`, `version=0.13.1`, then
  `both`, `true`, `latest`. A scenario cannot install one feature twice.
- Images: `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` (glibc 2.39, ships `curl` and `jq`), `debian:12` (2.36),
  `ubuntu:22.04` (2.35), `fedora:44` (2.43) have amd64 and arm64 manifests; `debian:11` and `ubuntu:20.04` have 2.31.
  `nfs-common` and `fuse3` (Debian, Ubuntu) and `nfs-utils` and `fuse3` (Fedora) exist for both architectures.
- `hf-mount` reads `HF_TOKEN` or `--token-file` itself, so the feature needs no credential and no `hf-cli` dependency.

## Goals / Non-Goals

**Goals:**

- Fail closed on verification. A binary reaches `/usr/local/bin` only after its SHA-256 equals a digest read for exactly
  its asset name, of the form `sha256:` plus 64 hex characters; a parse that yields no digest, more than one, or a
  malformed one fails the run. All selected assets are downloaded and verified in a temporary directory before any of
  them is installed, so a failing run replaces nothing. Checked by review of `install.sh` and by the hand checks below.
- Exact asset matching. The asset name is built from the fixed binary name and the mapped architecture and compared as a
  whole string, never as a prefix or pattern, so `hf-mount-fuse-sidecar-*` can never satisfy `hf-mount-fuse-*`. Checked
  by review.
- The download host is fixed by the feature. The download URL is built from the template in the spec, not taken from the
  API response, so API content cannot redirect the download to another repository; only the digest and the tag come from
  the API, and the tag must match `v<MAJOR.MINOR.PATCH>`. Checked by review.
- HTTPS only, including redirects. Every request fails on an HTTP error status and on a non-HTTPS URL or redirect
  (`--proto =https` and `--proto-redir =https`). Redirects are followed without pinning their host, since GitHub has
  served release downloads from both `release-assets.githubusercontent.com` and `objects.githubusercontent.com`; the
  content is verified after it arrives. Checked by review of the `curl` flags.
- The token stays secret. `GITHUB_TOKEN`, when set, reaches `curl` as a header through standard input, only on
  `api.github.com` requests, never through an argument, a file in the image, or shell tracing (no `set -x`); no request
  uses `--location-trusted`, so a redirect to another host never carries it. Checked by review and by the token hand
  checks below.
- One API request per install: the release object (`releases/latest` or `releases/tags/v<X>`) holds both the tag and
  every asset's digest. Checked by review.
- Nothing changes before the platform checks pass. No package is installed and nothing is downloaded until the
  architecture, C library (glibc 2.34 or later), distribution, and `version` checks pass; no mount-dependency package is
  installed until every download is verified; and no binary is installed until those packages are in place, so a package
  failure leaves `/usr/local/bin` unchanged. The entry point is POSIX `sh` so an image without bash, such as Alpine,
  still gets the clear message. Checked by review, by `shellcheck` in `just check` (which takes the `sh` dialect from
  the shebang), and by the platform hand checks.
- Idempotent and additive, as the spec's Installing twice requirement states: binaries are replaced by `install` with
  mode `0755`; an installed binary whose SHA-256 already equals the verified digest is left as is; nothing is removed.
  Checked by `duplicate.sh` and the install-twice hand checks.
- Minimal package footprint: packages are installed with `--no-install-recommends` (apt) or
  `--setopt=install_weak_deps=False` (dnf), `curl` and `ca-certificates` only when missing, and package caches are
  cleaned. The temporary directory is removed on every exit. Checked by review and the `installMountDependencies`
  scenario.

**Non-Goals:**

- Provenance beyond GitHub's digest (see Decisions and Risks).
- Mounting at build or start time, or any credential handling (issue #18, Out of scope).
- Supporting musl, glibc older than 2.34, other architectures, or distributions other than Debian, Ubuntu, and Fedora.
- Configuring `/etc/fuse.conf`, sudo rules, or container privileges; `NOTES.md` documents them instead.
- Removing binaries or packages a previous install added.

## Decisions

- **Source: raw release assets from `github.com/huggingface/hf-mount`, verified against the Releases API `digest`.**
  Approved by the maintainer. Anchored in the download rules of `.agents/knowledge/feature-authoring.md`: upstream
  publishes no checksum or signature for any release, so the feature may install relying on TLS alone, stated as a spec
  Requirement, and a digest computed by the hosting platform (GitHub's asset digest) "may be used, never required". The
  maintainer chose to use it. The spec states the trade-off: the digest is computed by GitHub and served from the same
  origin as the binary, so beyond TLS it proves integrity (the file is the one uploaded to the release), not who built
  it. Whether to keep it now that the rule no longer requires it is Open Question 2. Rejected: Homebrew on Linux (brings
  a whole package manager into the image); `cargo build` (Rust 1.89 or later and minutes per build); the upstream image
  `ghcr.io/huggingface/hf-mount-fuse` (holds only the FUSE backend and the sidecar); checksums pinned in the feature for
  an allow-list of versions (stronger against a compromised release, but the download rules forbid per-version hashes
  without a change to the rule, and it would mean no `latest` and a feature release for every upstream release, which
  comes several times a month).
- **Options.** `version` (string, default `latest`, proposals `latest` and the current release; accepts `latest` or
  `MAJOR.MINOR.PATCH` only), `backend` (enum in the order `nfs`, `fuse`, `both`, default `both`, so either backend can
  be chosen at run time without a rebuild at a cost of about 27 MB per backend), `installMountDependencies` (boolean,
  default `true`, since neither backend can mount without its helper). The daemon is always installed. The enum order
  and the release in `proposals` decide the duplicate test's first install (Context): the test depends on that release
  staying downloadable, and refreshing a stale proposal is a PATCH bump. Rejected: a token option (issue #18: options
  appear in build logs); a separate option per backend (two booleans allow selecting none, which installs a daemon that
  cannot mount); accepting a leading `v` in `version` (two spellings of one value; the message names the accepted
  forms).
- **Install location: `/usr/local/bin`, all binaries side by side.** The daemon finds its backend next to itself first,
  and `/usr/local/bin` is on `PATH` in every supported image, so no environment change is needed. Rejected: a versioned
  directory with symlinks (no second version needs to coexist).
- **Mount dependencies per distribution:** `nfs-common` (apt) or `nfs-utils` (dnf) for NFS, `fuse3` for FUSE. The
  distribution is taken from `ID` in `/etc/os-release` (`debian`, `ubuntu`, `fedora`) and checked on every install, also
  when no package is needed. Rejected: accepting any `ID_LIKE` match (derivatives such as RHEL clones or Mint would ship
  untested); checking the distribution only when a package must be installed (whether an image is supported would then
  depend on which packages it happens to ship and on `installMountDependencies`, and none of those images is tested).
- **JSON parsing without `jq`.** Base images such as `debian:12` lack `jq`, and installing it only to read two fields
  adds a package; the release object is read with `sed`/`grep` under the fail-closed rules in Goals. Rejected:
  installing `jq` when missing (a heavier footprint for the same result, and it would stay in the image).
- **A rejected `GITHUB_TOKEN` fails the install** (spec: Token rejected). Rejected: retrying anonymously (hides a
  misconfigured token and doubles the requests counted against the address).
- **A rate-limited response fails at once** (spec: Rate limit reached). Rejected: waiting for the reset and retrying
  (the primary limit resets hourly, so a build could hang for up to an hour).
- **`NOTES.md` content bounds.** It names the container settings a mount needs (`--cap-add SYS_ADMIN`,
  `--device /dev/fuse` for FUSE, `--security-opt apparmor=unconfined` where AppArmor applies, or `--privileged` as the
  broad alternative), the non-root prerequisites (passwordless `sudo` for NFS; `user_allow_other` in `/etc/fuse.conf` or
  `--fuse-owner-only` for FUSE), how `GITHUB_TOKEN` reaches the install and that it then already sits in the image's
  `ENV`, and what the digest verification proves.
- **Tests.** Container tests assert only what needs no privileges and no network: `hf-mount --version` (the
  `hf-mount <MAJOR.MINOR.PATCH>` form only; `test.sh` makes no API request, since `latest` can move between build and
  test and every request counts against the anonymous limit), `hf-mount status`, the backend files, `mount.nfs` or
  `fusermount3` presence, no `hf-mount` process (read from `/proc/*/comm`, so no `procps` is needed), and no uncommented
  `user_allow_other` in `/etc/fuse.conf`. `duplicate.sh` asserts the spec's "Non-default options, then the defaults".
  Scenarios, on `debian:12` amd64, cover `backend` `nfs` and `fuse`, `installMountDependencies` disabled, and a pinned
  `version`. Everything else is a hand check (below).

## Hand checks

How each spec scenario outside the container tests is provoked; results go to the PR's Validation section.

- Version: `version` set to `v0.13.1`, `0.13`, and `9.9.9`.
- Verification: copies of `install.sh` with the expected digest altered ("Digest does not match"); reading a saved
  release object with the asset's `digest` removed, and with it shortened ("Digest missing or malformed"); with the
  asset name altered ("Asset missing from the release"); and with the download path naming a file that does not exist
  ("HTTP error"). Each run must leave `/usr/local/bin` as it was.
- Token: an image built with `ENV GITHUB_TOKEN=<dummy>`, never a real token. The 401 shows the token reached the API
  ("Token rejected", and "Token present" for the request); the build output and the files the feature's layer adds must
  not contain the dummy string. That downloads carry no token is checked by review.
- Rate limit: install after exhausting the address's anonymous limit with repeated API requests.
- Platforms: `alpine` (musl), `debian:11` (glibc 2.31), a glibc 2.34 or later image of another distribution such as
  `rockylinux:9` (RHEL 9, glibc 2.34), and a third architecture under emulation where available, otherwise a copy of
  `install.sh` with the detected architecture altered.
- Installing twice: an image built with the first options, then built on again with the second: same options twice;
  `backend` `nfs` then `fuse`; `version` `0.13.1` then `0.13.0`, with each binary's SHA-256 compared to the older
  release's digests.
- Mounts: one mount of a small public repository per backend with the `runArgs` `NOTES.md` names, as root and as
  `vscode` on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04`.

## Security review surface

- Downloads and verification: the URL inventory below, verified as the Goals bound it (fail closed, exact asset names,
  fixed download host, HTTPS only, all verified before any is installed).
- Keys: none. Upstream signs nothing, so no key or fingerprint is pinned; the trade-off is under Risks.
- Credentials: `GITHUB_TOKEN` only when the build environment already has it, handled as the Goals bound it; no option
  carries a credential, and Hugging Face tokens stay with `hf-mount` at run time.
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

| Image                                               | Arch         | remoteUser | Why                                            |
| --------------------------------------------------- | ------------ | ---------- | ---------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | amd64, arm64 | `vscode`   | The common dev container base; non-root checks |
| `debian:12`                                         | amd64, arm64 | —          | Debian, glibc 2.36, minimal image; scenarios   |
| `ubuntu:22.04`                                      | amd64, arm64 | —          | Oldest supported glibc family (2.35)           |
| `fedora:44`                                         | amd64, arm64 | —          | The dnf path (`nfs-utils`); see Open Questions |

Excluded: `alpine` (musl), `debian:11` and `ubuntu:20.04` (glibc 2.31).

## URL inventory

Every URL the feature's scripts access. The feature configures no package repository: `nfs-common`, `nfs-utils`,
`fuse3`, `curl`, and `ca-certificates` come from the repositories preconfigured in the image. It fetches nothing at
start or run time (a mount started later by the user talks to Hugging Face, which is `hf-mount`'s own traffic), and it
has no `dependsOn` or `installsAfter`. A renamed or transferred upstream repository would answer the API requests with a
301 to `api.github.com/repositories/<id>/…`, on the same host.

| URL / template                                                                   | Purpose                                                  | When  | Integrity / authenticity                                                                                                                                       | Official source evidence                                                                                                                                         | Verified                                                                                                                                                      |
| -------------------------------------------------------------------------------- | -------------------------------------------------------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://api.github.com/repos/huggingface/hf-mount/releases/latest`              | Resolve `version=latest`: tag and every asset's `digest` | build | HTTPS to GitHub; its `digest` is an integrity check beyond TLS; tag checked against `v<MAJOR.MINOR.PATCH>`                                                     | "Get the latest release" in https://docs.github.com/en/rest/releases/releases; `digest` in the asset object in https://docs.github.com/en/rest/releases/assets   | 2026-09-30: 200, final host `api.github.com`, `tag_name` `v0.13.1`, all Linux assets with `sha256:` digests                                                   |
| `https://api.github.com/repos/huggingface/hf-mount/releases/tags/v<version>`     | Pinned `version`: every asset's `digest`                 | build | As above                                                                                                                                                       | "Get a release by tag name" in https://docs.github.com/en/rest/releases/releases                                                                                 | 2026-09-30: 200 for `v0.13.1`, final host `api.github.com`; 404 for `v9.9.9`                                                                                  |
| `https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`   | Download `hf-mount`, `hf-mount-nfs`, `hf-mount-fuse`     | build | SHA-256 compared with the API `digest` for the exact asset name (integrity only; no upstream checksum or signature exists, so authenticity rests on TLS alone) | Upstream README "Manual download" (https://github.com/huggingface/hf-mount) links GitHub Releases and lists the asset names; upstream `release.yml` uploads them | 2026-09-30: 302 then 200 for all six `v0.13.1` Linux assets of the three binaries on both architectures                                                       |
| `https://release-assets.githubusercontent.com/github-production-release-asset/…` | Redirect target of the download (not requested directly) | build | Same as the download: the content is verified after it arrives                                                                                                 | Listed among GitHub's hosts in https://docs.github.com/en/actions/reference/runners/self-hosted-runners, which also lists `objects.githubusercontent.com`        | 2026-09-30: the only redirect host of all six downloads; `objects.githubusercontent.com` was not observed but is allowed, since redirects are not host-pinned |

## Risks / Trade-offs

- [The digest proves integrity, not provenance: whoever can upload to the upstream release can replace a binary and its
  digest changes with it] → Accepted by the maintainer and stated in the spec and `NOTES.md`; a pinned `version` limits
  exposure to the chosen release; pinned checksums would be stronger but need a change to the download rules
  (Decisions).
- [Anonymous rate limit of 60 API requests per hour per address; `GITHUB_TOKEN` rarely reaches a feature's build
  environment, and CI never has one] → One request per install and none from test scripts: a container job makes three
  (the default install and the duplicate test's two) and the scenario job four. GitHub-hosted runners share and reuse
  addresses, so a job can still meet an exhausted limit; it then fails with the message of the spec's "Rate limit
  reached", and a required check that failed this way is re-run after the reset. This design accepts that flakiness in
  exchange for the digest check; Open Question 2 weighs dropping it. A full local `just test hf-mount` plus
  `just test-scenarios hf-mount` makes 13 to 16 requests, so four runs in an hour can exhaust the limit.
- [`latest` moves several times a month, so a rebuild can bring a new upstream version or a new glibc floor] → The glibc
  check fails clearly; users who need stability pin `version`.
- [A backend left from an earlier install at an older version sits next to a newer daemon] → Stated in the spec as the
  additive behavior; reinstalling with that backend selected updates it.
- [Upstream renames assets or drops `aarch64`] → The exact-name match fails the install with the missing asset named;
  the fix is a feature change.
- [Upstream deletes the release in `proposals`] → The duplicate test's first install fails; refreshing the proposal is a
  PATCH bump (Decisions, Options).
- [Parsing pretty-printed JSON with `sed`/`grep` depends on GitHub's formatting] → Any ambiguity fails closed (Goals);
  the container tests show when GitHub's format changes.
- [`nfs-common` pulls `rpcbind`, whose maintainer scripts were not yet run inside a container build] → The default
  install on every compatibility image exercises it; a failure there is resolved before the PR is marked ready.
- [Each backend is about 27 MB, so `both` adds about 55 MB] → `backend` narrows it.

## Open Questions

1. **Include `fedora:44` in the compatibility list?** Recommendation: yes, amd64 and arm64, so the dnf path and the
   `nfs-utils` name are tested; it adds two test jobs. The answer is needed before the spec is approved: if declined,
   the spec drops Fedora from the supported distributions and the mount-dependency requirement first, and Fedora fails
   as unsupported.
2. **Keep the API digest, or drop it and rely on TLS alone?** The download rules now allow either (Decisions, Source).
   Keeping it adds an integrity check against a corrupted or truncated download, at the cost of one API request per
   install, the anonymous limit of 60 per hour with its CI flakiness (Risks), and the `GITHUB_TOKEN` handling. Dropping
   it removes all three: `latest` would be resolved from the redirect of
   `https://github.com/huggingface/hf-mount/releases/latest` (302 to `…/releases/tag/v0.13.1` on 2026-09-30), not an API
   request; the spec's digest requirement would become a TLS-alone download requirement, and its token requirement and
   the digest and rate-limit scenarios would go. Recommendation: drop it: the digest comes from the same origin as the
   binary, so beyond TLS it protects only against corruption, and it adds a failure mode. The answer is needed before
   the spec is approved; until then the package keeps the approved digest.
