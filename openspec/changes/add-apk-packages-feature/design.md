# Design

## Context

See proposal.md - Why. Facts this change relies on, checked on 2026-09-30 against upstream documents and source, and by
running `apk` in `alpine:3.24` (Alpine 3.24.2, apk-tools 3.0.8) and `alpine:3.22` (Alpine 3.22.6, apk-tools 2.14.12) on
amd64; the arm64 variants were pulled and inspected without running them:

- Both images list `https://dl-cdn.alpinelinux.org/alpine/v<release>/main` and `.../community` in
  `/etc/apk/repositories`, on amd64 and arm64 alike, and trust the keys of the `alpine-keys` package in `/etc/apk/keys`
  (URL inventory). `/var/cache/apk` exists and is empty; there is no `/etc/apk/cache`, no `/etc/apk/interactive`, and no
  bash; `/bin/sh` is busybox. Neither image has `file`, `tree`, or `jq` installed. On 3.24, `libcrypto3` and `libssl3`
  are installed at 3.5.8 while the repositories offer 3.5.9; on 3.22, every installed package is at the offered version.
- The first releases of both branches, `alpine:3.24.0` (apk-tools 3.0.6,
  `alpine@sha256:a2d49ea686c2adfe3c992e47dc3b5e7fa6e6b5055609400dc2acaeb241c829f4`) and `alpine:3.22.0` (apk-tools
  2.14.9, `alpine@sha256:8a1f59ffb675680d47db6337b49d22281a139e9d709335b492be023728e11715`), hold installed packages the
  repositories offer in newer versions (`apk version -l '<'` lists 6 and 12, among them `alpine-release` and
  `apk-tools`), since every point release of a branch updates at least `alpine-release`.
- apk-tools documents (`doc/` at tags `v3.0.8` and `v2.14.12`, https://gitlab.alpinelinux.org/alpine/apk-tools): apk is
  non-interactive by default, and `/etc/apk/interactive` turns on asking when a terminal is attached; `--no-interactive`
  exists in both versions. `apk add` "adds or updates given constraints to world" and "will avoid changing installed
  package unless it is required by the newly added packages or their dependencies"; `-u` changes that preference to
  upgrading. World constraints have the form `[!]name{@tag}{[<>~=]version}`, with `><` for an identity hash; a leading
  `!` is a conflict that keeps a package from being installed; "the installed version is preferred unless an upgrade is
  requested or a world constraint or package dependency requires an alternate version" (apk-world(5)). A package with
  `install_if` is installed automatically once all its conditions are installed (apk-package(5)); apk(8) and apk-add(8)
  name no option that turns this off. `apk update` returns the number of unavailable plus stale repositories
  (`src/app_update.c` in both versions). `--cache-dir` "temporarily override[s] the cache directory". Index signatures
  are checked against `/etc/apk/keys` (apk-keys(5)); a package is authenticated against the hash its index records
  (apk-package(5), field `C`); `--allow-untrusted` would accept unsigned packages.
- Observed with `apk add --no-cache`: when one configured repository fails (an unresolvable host or HTTP 404), apk
  prints a warning, installs from the others, and exits 0 on both versions. With the trusted keys removed, both
  repositories are skipped as "UNTRUSTED signature" and only the empty result fails the install. `apk update` with one
  repository returning 404 exits 1 (3.0.8) or 2 (2.14.12), and with the keys removed 2 or 4.
- Observed on both versions: `apk update --cache-dir D` followed by `apk add --cache-dir D` resolves from the indexes in
  `D` without the network (an offline `apk add --simulate --cache-dir D` succeeds), downloads the packages into `D`, and
  leaves `/var/cache/apk` untouched.
- Observed on both versions: with `/etc/apk/cache` linked to `/var/cache/apk`, `apk update` and
  `apk cache download jq file` leave the indexes and the package files in `/var/cache/apk`; with the network cut, a
  plain `apk add jq file` then installs from them and exits 0, while `apk update --cache-dir D` into an empty directory
  exits 2 (3.0.8) or 4 (2.14.12) and `apk add --no-cache jq` exits 1.
- Observed on both versions: with `@t` put before the image's `community` line, `apk add ripgrep` (a package only
  `community` offers) fails with exit 1, while `apk add ripgrep@t` installs it and records `ripgrep@t` in the world.
- `apk add` reads an argument as a local package file when it contains `.` and a file of that name exists (3.0.8,
  `src/app_add.c`) or when it contains `.apk` (2.14.12). Observed: with a signed `jq-1.8.2-r0.apk` in the working
  directory, both versions install jq from that file for the argument `jq-1.8.2-r0.apk`; run from an empty directory,
  3.0.8 fails with "no such package" (exit 1) and 2.14.12 with "No such file or directory" (exit 99).
- Observed on both versions: an unknown name or an unavailable pinned version fails with "unable to select packages",
  exit 1, and installs nothing, also when other entries are valid; a tag no repository carries fails with exit 99 ("Not
  committing changes due to missing repository tags"); a malformed constraint such as `jq=` fails with exit 99; `cmd:jq`
  installs jq, and `cmd:awk`, which several packages provide, installs `gawk`; `g++` and `libstdc++` install; `jq,docs`
  also installs `jq-doc` and the other `-doc` packages of installed packages through install-if. On 3.24, listing
  `libcrypto3` leaves it at 3.5.8, while listing `openssl` upgrades it to 3.5.9. A failed `apk add` leaves the world
  file as it was. A later `apk add jq` replaces a world entry `jq=1.8.2-r0` with `jq`. `--` ends the options on both
  versions. With `/etc/apk/interactive` and a terminal, 3.0.8 asks "Do you want to continue [Y/n]?"; with
  `--no-interactive` it does not.
- Alpine release support (https://alpinelinux.org/releases/): 3.24 until 2028-06-01; 3.22 until 2027-05-01 for `main`
  only, so its `community` repository no longer receives fixes.
- The devcontainer CLI's install-twice test (CLI 0.89.0) installs the feature first with a non-default value taken from
  a string option's `proposals` (the second entry when the default is not among them), then with the defaults.
- Test harness limits (`.agents/knowledge/testing.md`, `scripts/test_feature.ts`): a scenario runs through
  `devcontainer features test`, so a failing `install.sh` fails the image build and no check script runs; nothing
  asserts an expected failure. A `build` scenario's context is `test/<id>/<name>/`, which cannot reach `src/`. Two
  scenario keys for the same feature resolve to one staged ref, and the CLI installs a feature once. Scenario jobs run
  on amd64 only.
- Prior art: none. `devcontainers-extra` has no apk installer (its `apko` feature is unrelated), and the apt installers
  of `devcontainers-extra` and `rocker-org` are not reused (see the `apt-packages` change).

## Goals / Non-Goals

**Goals:**

- One POSIX `sh` script with `set -eu`, whose structure the other four installers share: parse, validate, detect the
  manager, refresh when needed (for apk, on every run; Open question 2), install, clean. Checked by shellcheck in
  `just check` (dialect from the `#!/bin/sh` shebang) and by the tests on both images, whose `/bin/sh` is busybox.
- Entries reach `apk` only as separate, quoted arguments after `--`; the script has no `eval`, no `sh -c`, and no
  unquoted expansion of an entry. Checked by review of `install.sh` and by the direct check for "Shell metacharacters
  and inner whitespace are refused" with an entry such as `x;touch /tmp/pwned` that asserts the file does not exist.
- Every entry is validated before the `apk` check and any `apk` call, so a refused list leaves the image untouched.
  Checked by the direct refusal checks, which also assert that apk's world and installed database are unchanged and that
  no temporary directory of the feature remains.
- No `apk` call carries an option that weakens verification or widens the package source: never `--allow-untrusted`,
  `--no-check-certificate`, any `--force-*` option (including `--force-missing-repositories`, `--force-broken-world`,
  and `--force-non-repository`), `--keys-dir`, `--repositories-file`, `--repository`/`-X`, `--root`, or `--arch`, and
  never `-u`/`--upgrade`, `--latest`, or `--available`. Every `apk` call carries `--no-interactive` and `--cache-dir`
  naming a directory the feature created, and `apk add` runs in an empty working directory the feature created. Checked
  by review of `install.sh` against this list, and by the checks for "Entry is not read as a package file", "Listed
  package already installed stays at its version", and "Interactive default is overridden".
- The only strict index fetch is `apk update` into the feature's cache directory; `apk add` runs only after it exits 0
  and reads the indexes from that directory. Checked by the direct checks for "Unavailable repository fails the feature"
  and "Index present in the image is not used".
- The feature writes nothing itself except its temporary directories, which it removes; apk writes the installed
  packages, its database, and its world. Checked by the direct check for "Apk configuration is unchanged", which
  compares `/etc/apk` except the world before and after, and by "Caches are removed".
- The `packages` option's `proposals` are lists installable on every image in the compatibility list and installed on
  none of them, with at least two entries, so the CLI's install-twice test installs real packages. Checked by
  `just test apk-packages`.
- `devcontainer-feature.json` declares no `dependsOn` and no `installsAfter` (decision "No feature dependencies").
  Checked by review of the file.

**Non-Goals:**

- Adding repositories, tags, or keys, upgrading the whole system, or choosing a package manager across distributions
  (issue #22, Out of scope).
- An option to upgrade listed packages (`-u`), to group them under a virtual package (`--virtual`), or to suppress
  install-if; users list what they need.
- Checking the architecture: the feature downloads nothing architecture-specific, and `apk` resolves packages for the
  image's architecture; the compatibility list names the architectures that are tested.
- An image that configures its own apk cache through `/etc/apk/cache`: the feature neither uses nor cleans it, since
  every call names the feature's cache directory.

## Decisions

- **POSIX `sh`, shared skeleton.** One skeleton keeps the five installers auditable side by side; the Alpine images ship
  no bash, so `feature-authoring.md` calls for POSIX `sh` here anyway. Rejected: installing bash first, which would add
  a package the user did not list.
- **Validate, then the empty check, then the `apk` check.** A refused entry fails first on every image, so the same bad
  list gives the same message everywhere; the empty check runs before the `apk` check, so the default options succeed on
  any image, including one without `apk`. Rejected: failing on an image without `apk` even for an empty list, which
  would make adding the feature with defaults to a non-Alpine image an error although it has nothing to do.
- **A strict allowlist per manager.** An entry matches `^[A-Za-z0-9][A-Za-z0-9._+:~=@-]*$`: Alpine package name and
  version characters (`_` appears in versions such as `1.0_rc1` and `_p1`), `:` for provided names such as `cmd:jq`,
  `so:libcrypto.so.3`, or `pc:zlib`, `=` and `~` for constraints, `@` for a tag. It has no rule for a trailing `+` or
  `-`, which mean nothing special to apk and end real names such as `g++` and `libstdc++`. It refuses option injection
  (leading `-`), apk's conflict marker (leading `!`, which would remove packages), URLs and paths (`/`), the range
  operators `<` and `>` (the binding rule on shell metacharacters; Open question 1), globs, whitespace, and every other
  shell metacharacter. Rejected: the shared cross-manager expression `^[A-Za-z0-9][A-Za-z0-9._+:~=<>@/-]*$` from the
  research brief, whose `/` admits URLs and paths; validating by asking apk, which would run apk on unvalidated input.
- **An empty working directory for `apk`.** Because apk reads an argument as a local package file when a file of that
  name exists (3.0.8) or when it contains `.apk` (2.14.12), `apk add` runs in a directory the feature just created and
  left empty, so no entry can name a local file. Rejected: refusing entries that contain `.apk`, which covers 2.14.12
  only, since 3.0.8 reads any dotted name that exists; refusing `.`, which would refuse versions and provided names.
- **Fetch the indexes strictly on every run, into the feature's own cache directory.** `apk update --cache-dir <dir>`
  runs once and must exit 0, which it does only when every configured repository's index was fetched and verified; then
  `apk add --cache-dir <dir>` installs from those indexes, downloads into the same directory, and the directory is
  removed. The images keep no index, and neither does the feature, so every run needs one; an index already in the
  image's cache is never read. Rejected: `apk add --no-cache` alone, which skips a failing repository and installs from
  the rest (Context); refreshing only when no index exists, as `apt-packages` does, which here would trust an index the
  image cached, which apk refreshes by itself after its cache age expires without failing on an unavailable repository;
  `apk --no-cache update` followed by `apk add --no-cache`, whose second fetch is again not strict and doubles the
  download; parsing apk's warnings, which are not a stable interface.
- **Clean by removing the feature's directories only.** The index files and downloaded packages live only in the
  feature's cache directory, which is removed after installing; `/var/cache/apk` and any `/etc/apk/cache` stay as the
  image had them. Rejected: `apk cache clean`, which needs a configured package cache; emptying `/var/cache/apk`, which
  would delete what the image or the user placed there.
- **Always `--no-interactive`.** The default is non-interactive, but an image can change it with `/etc/apk/interactive`.
  Rejected: relying on the default.
- **Install-if stays apk's behavior.** apk has no recommends or weak dependencies to turn off; its only automatic
  installation is install-if, which fires only when all of its conditions are installed and which no apk option
  disables. The spec states it (requirement "Install the listed packages"); Open question 3 asks the maintainer to
  accept it. Rejected: removing auto-installed packages afterwards, which fights apk's solver and would remove packages
  that were installed before.
- **No upgrade preference.** `apk add` runs without `-u` or `--latest`, so apk keeps installed versions unless an
  entry's constraint or a newly installed package requires another version. Rejected: `-u`, which upgrades listed
  packages and their dependencies (out of scope).
- **Detect by binary, describe by `/etc/os-release`.** Support means `apk` is on the `PATH`; `/etc/os-release` is read
  only to name the detected distribution in the failure message. This deviates from `feature-authoring.md` (Deviations).
  Rejected: an `ID` allowlist, which would refuse Alpine derivatives with a working apk while adding no safety.
- **No feature dependencies.** Nothing this feature does depends on another feature's result. Rejected: an
  `installsAfter` on a common-utils feature; a user who needs an order sets `overrideFeatureInstallOrder`.
- **Direct checks for what a scenario cannot assert.** A host-side runner under `test/apk-packages/`, following the
  repository's script convention (Deno first), runs `src/apk-packages/install.sh` from the checkout, mounted read-only,
  as root in throwaway containers of the compatibility images, and asserts the exit status, the message, and the image
  state after each run. It covers expected failures, installing twice in one container, and checks that need a prepared
  or offline container (Test plan). It changes no test infrastructure, and CI does not run it. Rejected: a `build`
  scenario that carries a first install, which cannot reach `src/` from its context; two scenario keys for the feature,
  which the CLI installs once; extending `scripts/test_feature.ts` with expected-failure scenarios, a test
  infrastructure change outside this change (Open question 5). `just check` formats the runner (`deno fmt --check`) but
  type-checks and lints only `scripts/`, so the runner's shebang runs it with `deno run --check`, which type-checks it
  on every run, and `deno lint test/apk-packages/` runs before its output is recorded in the Validation section.

### Options

The feature's only option; the delta spec's Option requirement states its contract.

| Name       | Type     | Default | Enum or proposals                  | Meaning                                                                                                                                                                                                                         |
| ---------- | -------- | ------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages` | `string` | `""`    | proposals: `"file"`, `"file,tree"` | Comma-separated entries (`name`, `name=version`, `name~version`, `name@tag`, or a provided name such as `cmd:jq`) that `apk` installs; whitespace around entries and empty entries are dropped, so a trailing comma is harmless |

- **Default `""`.** An empty list installs nothing and, because the empty check runs before the `apk` check, succeeds on
  any image, including one without `apk` (decision "Validate, then the empty check, then the `apk` check"). The
  proposals are two lists installed on neither image, so the install-twice test installs real packages (Goals).
- **Rejected shapes:** an array (feature options are only `string` or `boolean`); options for upgrading, virtual
  packages, or extra repositories (out of scope); an option to suppress install-if (Non-Goals).

### Deviations from `feature-authoring.md`

Each follows from a binding decision for the five installers and needs the maintainer's acceptance at the package gate.

- **Distribution detection.** The convention says to detect the distribution from `/etc/os-release`. The feature detects
  `apk` on the `PATH` and reads `/etc/os-release` only for its message (decision "Detect by binary").
- **Skipping installed versions.** The convention says to skip an install when the requested version is already present.
  The feature always fetches the indexes and runs `apk add` for the whole list; apk leaves an installed package that
  satisfies its entry as it is.

### Security review surface

- **Downloads:** the feature downloads nothing itself; `install.sh` holds no URL and calls no download tool. `apk`
  fetches index files and packages only from the repositories in the image's `/etc/apk/repositories`, over HTTPS in both
  images (URL inventory). Under the download rules of `feature-authoring.md` these are repositories the image itself
  configures, so the package-manager rule governs them: apk verifies each index's signature and each package's hash, and
  the feature adds no second check. The feature adds no repository, so the key-pinning rule for added repositories does
  not apply; it makes no direct download and runs no installer script, so no download relies on TLS alone and the spec
  needs no Requirement stating one. The spec lists no source URL because the feature requests none itself. The
  no-weakening rule is kept by the option list in Goals and by the requirement "Repository authentication stays in
  effect". An entry can name neither a URL nor a local package file (decisions "A strict allowlist" and "An empty
  working directory").
- **Verification and keys:** apk verifies each repository's `APKINDEX.tar.gz` signature against the keys in
  `/etc/apk/keys` and each package against the hash its verified index records (requirement "Repository authentication
  stays in effect"); `apk update` fails when any index fails verification. The feature pins, adds, and changes no key;
  the keys are the images' own, shipped by their `alpine-keys` package. The URL inventory records the key each index is
  signed with and where the key files are published; none of those sources is load-bearing, because the feature pins no
  key.
- **Metadata:** none of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, lifecycle
  commands, `dependsOn`, or `installsAfter`: the feature runs once at build time as root, installs system-wide, and
  needs nothing at container start. No user-scoped setup; `_REMOTE_USER` is not used.
- **Idempotency:** a second run validates, fetches the indexes again, and installs its list; installed packages stay; an
  installed package changes version only when an entry's constraint or a newly installed package requires it; an entry
  replaces the world constraint of the same name, and a constraint the repositories cannot satisfy fails without
  changing anything. No `idempotencyExemption`.
- **Failure behavior:** a refused entry and a missing `apk` exit 1 before anything changes; an unavailable or
  unverifiable repository fails `apk update` before any install; an unknown package, an unavailable version, or a
  constraint that cannot be satisfied exits with `apk add`'s status 1, and an unknown tag or a malformed constraint with
  99, all before apk changes the world or installs anything.

### Test plan

Where each scenario of `specs/apk-packages/spec.md` is checked. "Scenario" means `scenarios.json`, run in CI on amd64 on
the image each entry names; "test.sh" and "duplicate.sh" run in CI on every image and architecture of the compatibility
list; "Direct" means the host-side runner (decision "Direct checks"), run locally on every amd64 image of the
compatibility list, or on the pinned images outside it that a row names, with its output recorded in the PR's Validation
section. On arm64, CI runs only test.sh and duplicate.sh.

| Scenario                                                                                    | Checked by                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Listed packages are installed                                                               | Scenario on each image; duplicate.sh with the `proposals` list                                                                                                                                                                                                                                                                                                       |
| Install-if packages follow their conditions; Spaces and empty entries are ignored           | Scenario                                                                                                                                                                                                                                                                                                                                                             |
| Listed package already installed stays at its version                                       | Direct: the runner picks at run time an installed package the repositories offer in a newer version (`apk version -l '<'`), lists it, and compares the version. Runs on `alpine:3.24.0` and `alpine:3.22.0`, pinned by digest (Context) and outside the compatibility list, whose installed packages lag their branches; the check fails if it finds no such package |
| Omitted packages; Empty list is a no-op                                                     | test.sh; Direct on an image without `apk`                                                                                                                                                                                                                                                                                                                            |
| Pinned version is installed; Prefix constraint is installed                                 | Direct: the runner reads the offered version at run time and pins it, so no fixed version goes stale                                                                                                                                                                                                                                                                 |
| Configured tag selects its repository                                                       | Direct: the runner puts `@t` before the image's `community` line in the test container and lists a package only `community` offers, such as `ripgrep`, as `name@t`; since the untagged name no longer resolves (Context), success proves the tag selected the repository; asserts the package is installed and the world holds `name@t`                              |
| Unavailable pinned version fails; Tag the image does not configure fails                    | Direct                                                                                                                                                                                                                                                                                                                                                               |
| The five refusal scenarios                                                                  | Direct, each also asserting an unchanged world and installed database                                                                                                                                                                                                                                                                                                |
| Unknown package fails; Provided name installs a provider                                    | Direct                                                                                                                                                                                                                                                                                                                                                               |
| Entry is not read as a package file                                                         | Direct: the runner fetches a package file with `apk fetch` into the directory it starts the feature from and lists that file name                                                                                                                                                                                                                                    |
| Image without apk fails clearly                                                             | Direct on `debian:12@sha256:f37a335e82bca302e955fa39f9dfe28f1be618f016f8a2b56318e5a5111afc26`, outside the compatibility list, which has no `apk`                                                                                                                                                                                                                    |
| Unavailable repository fails the feature                                                    | Direct, with a line for `https://dl-cdn.alpinelinux.org/alpine/v<release>/nonexistent` added, whose index returns HTTP 404 (URL inventory, test-only URLs)                                                                                                                                                                                                           |
| Index present in the image is not used                                                      | Direct: the runner links `/etc/apk/cache` to `/var/cache/apk` and runs `apk update` and `apk cache download` for the list, so the cache holds a fresh index and the package files; the container then loses its network and runs the feature. A plain `apk add` would install from that cache (Context), so only the strict refresh makes the feature fail           |
| Unverifiable repository fails the refresh                                                   | Direct, with the trusted keys moved out of `/etc/apk/keys`                                                                                                                                                                                                                                                                                                           |
| Apk configuration is unchanged                                                              | Direct, hashing `/etc/apk` except the world before and after                                                                                                                                                                                                                                                                                                         |
| Interactive default is overridden                                                           | Direct, with `/etc/apk/interactive` created, a terminal attached, and no input; the output must hold no question                                                                                                                                                                                                                                                     |
| Caches are removed                                                                          | Scenario; duplicate.sh. Both assert that `/var/cache/apk` is empty and no feature directory remains, which equals "as the image had it" only because the compatibility images ship it empty (Context)                                                                                                                                                                |
| Same list on the second install; Different list on the second install                       | Direct, running the feature twice in one container                                                                                                                                                                                                                                                                                                                   |
| Later entry replaces the earlier constraint; Unsatisfiable constraint on the second install | Direct, running the feature twice in one container with versions read at run time                                                                                                                                                                                                                                                                                    |

### Supported images

The planned `test/apk-packages/compatibility.json`, both images on `amd64` and `arm64` (arm64 variants pulled and
inspected on 2026-09-30):

| Image         | Architectures | Why                                                                                   |
| ------------- | ------------- | ------------------------------------------------------------------------------------- |
| `alpine:3.24` | amd64, arm64  | Current Alpine release; apk-tools 3.0.8                                               |
| `alpine:3.22` | amd64, arm64  | Older supported release with apk-tools 2.14.12, so both apk major versions are tested |

## URL inventory

The feature itself fetches no URL at build or start time: it has no download, checksum, signature, or key URL, no
latest-version endpoint, configures no repository, fetches nothing at start, and names no `dependsOn` or `installsAfter`
feature. The only network access is `apk` reaching the repositories that the supported images configure, listed here so
the review sees the whole build-time surface. The images themselves are pulled by the consumer or the test harness, not
by the feature. Both images use HTTPS; integrity rests on the signed `APKINDEX.tar.gz` of each repository and the
package hashes it records. Verified by `curl -sSIL` of each index on 2026-09-30, and by listing each index's members,
which include a `.SIGN.RSA.<key>` signature. The Alpine wiki and GitLab web pages cited below answer a plain `curl` with
a bot challenge (HTTP 307, then 403 or 418); their content was confirmed on 2026-09-30 through the MediaWiki and GitLab
APIs, so an automated link check may report them as failing although they exist.

`dl-cdn.alpinelinux.org` resolved on 2026-09-30 to `dualstack.j.sni.global.fastly.net` and answered through Varnish
caches, so apk connects to Fastly's CDN rather than to a host Alpine runs; https://mirrors.alpinelinux.org/ lists it as
an Alpine mirror. The CDN changes nothing about integrity, which rests on the signed index.

| URL / template                                                                                                                      | Purpose                                                     | When  | Integrity / authenticity                                                                                                                                                                                                                                                                                                                                                     | Official source evidence                                                                                                                                                                                                                                                                                                                                                                       | Verified                                                                                                                                                              |
| ----------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://dl-cdn.alpinelinux.org/alpine/v3.24/{main,community}/x86_64/APKINDEX.tar.gz` and the `<name>-<version>.apk` files it lists | `alpine:3.24` repositories, configured by the image (amd64) | build | Index signed with `alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub`, verified against `/etc/apk/keys` (the image's `4a6a0840`, `5261cecb`, and `6165ee59` keys); packages checked against the index hashes. The key files and their architectures are listed in `alpine-keys`: https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.24-stable/main/alpine-keys/APKBUILD | Alpine's image build script writes these lines into `/etc/apk/repositories`: https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.24-stable/scripts/genrootfs.sh (`https://dl-cdn.alpinelinux.org/alpine/$branch/{main,community}`); https://wiki.alpinelinux.org/wiki/Repositories (shows these repository lines for v3.24); https://mirrors.alpinelinux.org/ (lists dl-cdn.alpinelinux.org) | 2026-09-30: HTTP 200 for both repositories, no redirect, final host `dl-cdn.alpinelinux.org` (Fastly, above); a package file (`main/x86_64/jq-1.8.2-r0.apk`) HTTP 200 |
| `https://dl-cdn.alpinelinux.org/alpine/v3.24/{main,community}/aarch64/APKINDEX.tar.gz` and the package files it lists               | `alpine:3.24` repositories, configured by the image (arm64) | build | Index signed with `alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub`, verified against the image's `58199dcc` and `616ae350` keys; packages checked against the index hashes                                                                                                                                                                                              | as above                                                                                                                                                                                                                                                                                                                                                                                       | 2026-09-30: HTTP 200 for both repositories, no redirect, final host `dl-cdn.alpinelinux.org`                                                                          |
| `https://dl-cdn.alpinelinux.org/alpine/v3.22/{main,community}/x86_64/APKINDEX.tar.gz` and the package files it lists                | `alpine:3.22` repositories, configured by the image (amd64) | build | Index signed with `alpine-devel@lists.alpinelinux.org-6165ee59.rsa.pub`, verified against the image's `4a6a0840`, `5243ef4b`, `5261cecb`, `6165ee59`, and `61666e3f` keys; packages checked against the index hashes                                                                                                                                                         | Alpine's image build script writes these lines into `/etc/apk/repositories`: https://gitlab.alpinelinux.org/alpine/aports/-/blob/3.22-stable/scripts/genrootfs.sh (`https://dl-cdn.alpinelinux.org/alpine/$branch/{main,community}`); https://mirrors.alpinelinux.org/ (lists dl-cdn.alpinelinux.org, whose `/alpine/` tree holds every release branch)                                        | 2026-09-30: HTTP 200 for both repositories, no redirect, final host `dl-cdn.alpinelinux.org`                                                                          |
| `https://dl-cdn.alpinelinux.org/alpine/v3.22/{main,community}/aarch64/APKINDEX.tar.gz` and the package files it lists               | `alpine:3.22` repositories, configured by the image (arm64) | build | Index signed with `alpine-devel@lists.alpinelinux.org-616ae350.rsa.pub`, verified against the image's `524d27bb`, `58199dcc`, `616a9724`, `616adfeb`, and `616ae350` keys; packages checked against the index hashes                                                                                                                                                         | as above                                                                                                                                                                                                                                                                                                                                                                                       | 2026-09-30: HTTP 200 for both repositories, no redirect, final host `dl-cdn.alpinelinux.org`; a package file (`main/aarch64/jq-1.8.2-r0.apk`) HTTP 200                |

Test-only URLs, which the direct checks add to a throwaway container and the feature never uses: a repository line for
`https://dl-cdn.alpinelinux.org/alpine/v<release>/nonexistent`, whose `x86_64/APKINDEX.tar.gz` returned HTTP 404 on
2026-09-30 (check "Unavailable repository fails the feature"). The unresolvable host in Context was an observation, not
a planned check.

## Risks / Trade-offs

- [Every run with a non-empty list downloads the indexes of all configured repositories, about 3 MB on 3.24] → Accepted
  for strictness; the build caches the resulting layer.
- [A mirror or CDN outage for one repository fails the build, although the listed packages may all come from another
  repository] → Intended: installing from a subset of the repositories could select other versions; the message names
  apk's failing repository, and a rebuild retries.
- [Alpine branches keep only the current build of each package, so a `name=version` pin stops resolving when the branch
  updates the package] → NOTES.md recommends `name~prefix` for a version family; no test fixes a version: the direct
  checks read the offered version at run time.
- [A constraint stays in apk's world, so a later `apk upgrade` in the user's Dockerfile keeps the pinned package where
  it is] → Stated in the spec (requirement "Version constraints and repository tags") and in NOTES.md.
- [Install-if can add packages the user did not list, such as `-doc` packages once `docs` is installed] → Stated in the
  spec; they appear only when the user or the image installed all of their conditions.
- [A provided name such as `cmd:awk` installs whichever provider apk ranks first] → Stated in the spec; users who need a
  specific package name it.
- [`alpine:3.22`'s `community` repository no longer receives fixes] → The image stays for apk-tools 2 coverage; Open
  question 4 covers its replacement.
- [Whether an image holds a package the repositories offer in a newer version depends on when both were built (on
  2026-09-30 only `alpine:3.24` did), so the compatibility images cannot be relied on to exercise "Listed package
  already installed stays at its version"] → The direct check runs on the first release of each branch, pinned by
  digest, whose `alpine-release` lags the branch after any point release; it runs apk-tools 3.0.6 and 2.14.9 instead of
  3.0.8 and 2.14.12, the same major versions.
- [A constraint can make apk replace an installed version with a lower one, while `apt-packages` refuses every
  downgrade] → Stated in the spec (requirement "Version constraints and repository tags"). An Alpine branch keeps one
  build of each package, so `name=<older version>` does not resolve and fails; a lower version comes only from a
  repository the image tags or from another configured repository offering the same name, both of which the image, not
  the feature, sets up.
- [CI does not run the direct checks, so a later change could break a failure path unnoticed until someone runs them] →
  The PR's Validation section records their output; Open question 5 offers running them in CI.
- [An Alpine derivative whose `apk` behaves differently] → Only images in the compatibility list are supported; others
  work or fail with `apk`'s own error.

## Open Questions

Decisions for the maintainer at the package gate; each notes whether it changes the spec.

1. **Range operators.** The binding rule refuses shell metacharacters, which include `<` and `>`, so apk's native
   `name<version`, `name>version`, `name>=version`, `name<~version`, and `name>~version` are refused, while `=` and `~`
   pass. Entries never reach a shell (quoted arguments, no `eval`), and apk's own parser rejects a malformed constraint
   with exit 99 before changing anything. Recommendation: accept `<` and `>`, since `name>=version` is a common Alpine
   pin and the pin syntax is meant to pass through verbatim. The spec follows the binding rule; accepting the
   recommendation changes the requirement "Entries are validated before anything changes" and replaces the scenario
   "Range operators are refused" before approval.
2. **Fetching the indexes on every run.** The binding rule and issue #22 say to refresh the package index only when
   needed; `apt-packages` refreshes only when no index exists. The spec departs from that wording: it fetches on every
   run that names a package. The argument is that for apk a fetch is needed on every run: the feature keeps no index
   after it runs, the images ship none, apk's own `--no-cache` mode also fetches on every run, and a strict fetch is
   possible only through `apk update`, while an index the image cached would be refreshed by apk itself without failing
   on an unavailable repository. Recommendation: accept the departure as specified. The alternative, using an index the
   image holds, changes the requirement "Package index refresh" and its scenario "Index present in the image is not
   used".
3. **Install-if.** The shared design turns off recommends and weak dependencies; apk has neither, and its install-if
   cannot be turned off. Recommendation: accept it as specified and document it in NOTES.md. Does not change the spec.
4. **The older image.** `alpine:3.22` covers apk-tools 2 until 2027-05-01, but its `community` repository no longer
   receives fixes; `alpine:3.23` (apk-tools 3) is supported until 2027-11-01. Recommendation: keep `alpine:3.24` and
   `alpine:3.22` as decided and replace 3.22 in a later change when it reaches end of life, which is a MAJOR bump. Does
   not change the spec.
5. **Direct checks in CI.** The direct checks run by hand, because the scenario harness cannot assert an expected
   failure. Recommendation: accept that for this change and propose a separate test-infrastructure change that lets a
   feature's tests assert expected failures in CI, which all five installers would use. That change could also replace
   the five near-identical per-feature runners with one shared runner under `scripts/`, which `just check` type-checks
   and lints. Does not change the spec.
