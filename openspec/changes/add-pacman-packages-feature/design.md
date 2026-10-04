# Design

This file describes the baseline implementation. The same PR also carries ../configure-pacman-packages-cleanup/, a
separate phase 1 extension awaiting approval and implementation. Its delta supersedes the relevant baseline requirements
only when applied; the baseline task completion and test results do not validate its new paths.

## Context

See proposal.md - Why. The five installers share one option shape and one script skeleton; this design follows the
structure of the `apt-packages` design (issue #20, pull request #33). Facts this change relies on, checked on 2026-09-30
against upstream documents and source, and by running `pacman` in `archlinux:latest` (digest
`sha256:b21322c663be387c0ed9cbc7bbbfe18e41633ad4e7b7c77cfad45f128be20040`, built 2026-09-28,
`VERSION_ID=20260927.0.600689`, pacman 7.1.0, libalpm 16.0.1, GnuPG 2.4.9):

- The image ships no sync databases (`/var/lib/pacman/sync/` is empty) and an empty package cache; the image project's
  `exclude` file drops both (https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/master/exclude). So
  `pacman -S` without `-y` has nothing to resolve against.
- `/etc/pacman.conf` sets `SigLevel = Required DatabaseOptional` (`TrustedOnly` is the compiled-in default, Arch Wiki,
  https://wiki.archlinux.org/title/Pacman/Package_signing), `LocalFileSigLevel = Optional`, repositories `[core]` and
  `[extra]` through `/etc/pacman.d/mirrorlist`, the default `CacheDir` and `DBPath`, no `IgnorePkg`, and `NoExtract` for
  `etc/pacman.conf` and `etc/pacman.d/mirrorlist` besides documentation and locales, so upgrading `pacman` or
  `pacman-mirrorlist` never replaces either file. The mirror list names `https://fastly.mirror.pkgbuild.com` and then
  `https://geo.mirror.pkgbuild.com`, as the image project's source does (URL inventory). `/etc/pacman.conf` also sets
  `DisableSandboxFilesystem` (observed on 2026-10-01), which the image project's `scripts/make-rootfs.sh` writes because
  containerd offers no Landlock: pacman's download process runs without Landlock write confinement, while its syscall
  filter and the drop to the `alpm` download user stay in effect.
- The keyring `/etc/pacman.d/gnupg/` ships populated (`pubring.gpg`, `trustdb.gpg`) with the local signing key stripped;
  the image README says pacman must work out of the box, and only the `repro` image needs `pacman-key --init`
  (https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/master/README.md). The same README says the official
  Docker Hub library image is rebuilt weekly (the project's own registries daily). Its `gpg.conf` names no keyserver, so
  dirmngr's compiled-in default applies: `gpgconf --list-options dirmngr` reports `hkps://keyserver.ubuntu.com`, the
  default since GnuPG 2.2.29 and 2.3.2 (URL inventory); GnuPG 2.5.3 and later have no default keyserver
  (https://www.gnupg.org/documentation/manuals/gnupg/Dirmngr-Options.html), so once Arch ships one, the keyserver
  fallback reaches no host.
- The Arch Wiki: "never run `pacman -Sy`"; `pacman -Sy package` is an unsupported partial upgrade; only full upgrades
  are supported (https://wiki.archlinux.org/title/System_maintenance, https://wiki.archlinux.org/title/Pacman). The wiki
  also endorses `pacman -Sy --needed archlinux-keyring && pacman -Su` for a stale keyring, as "not considered a partial
  upgrade" (Package signing).
- pacman(8) (https://man.archlinux.org/man/pacman.8): `-S "bash>=3.2"` takes version requirements; a group name prompts
  for members; a name no package has falls back to providers, with a prompt when several provide it; `--needed` does
  "not reinstall the targets that are already up-to-date"; `-u` given twice enables downgrades.
- pacman source, v7.1.0: a target is resolved by `alpm_find_dbs_satisfier` (exact name, then providers) and otherwise as
  a group (`process_targname` in `src/pacman/sync.c`); a target with `/` is split as `repository/name`; with
  `--noconfirm`, `question()` returns the preset answer (`src/pacman/util.c`), which is yes for "Proceed", "Replace",
  and "Import PGP key" (`yesno`), no for removing a conflicting package (`noyes`), 1 for a provider, all for a group,
  and no to skipping packages that cannot be upgraded (`src/pacman/callback.c`). `_alpm_key_import` asks that question,
  then looks the key up through WKD by the e-mail address of the user ID it is given and falls back to the keyserver by
  fingerprint (`lib/libalpm/signing.c`). For a key missing from the keyring, that user ID is the package's `PACKAGER`
  (`keyinfo->uid = strdup(pkg->packager)`, `lib/libalpm/sync.c`; the field is read from `%PACKAGER%` in
  `lib/libalpm/be_sync.c`), so the WKD host is the packager's domain. For a key present but expired
  (`ALPM_SIGSTATUS_KEY_EXPIRED`; Arch Wiki, Package signing: "Since version 7.1, pacman will automatically refresh known
  keys"), pacman 7.1 passes instead the key's first user ID in the local keyring (`result->key.uid = key->uids->uid`,
  `signing.c`), so the WKD host is that user ID's domain, which need not be the packager's: the sample key of the URL
  inventory has a first user ID on a domain other than `archlinux.org` and its `archlinux.org` address later, so an
  expired copy of it would be looked up under that other domain. On 2026-09-30, three packages in `[core]` and `[extra]`
  had a packager address outside `archlinux.org`.
- Observed in the image (pacman 7.1.0):
  - `pacman -Syu --needed --noconfirm -- bc` installs `bc` and upgrades the outdated `glibc`, `coreutils`, and `pcre2`
    in one transaction; run again, it reports `bc` "up to date -- skipping" and "there is nothing to do", exit 0.
  - An unknown name (`nosuchpkg-xyz`), `b.`, `bc-`, `-foo` after `--`, `bc=0.1-1`, `bc<1`, and `bc<1.08.2-1` with
    1.08.2-1 installed each fail with "target not found" and exit 1 before anything is installed; the databases were
    already downloaded by then. `bc=1.08.2` (pkgver without pkgrel) matches `1.08.2-1`.
  - `cron` (provided by `cronie` and `fcron`) installs `cronie`, the first provider; group `archlinux-tools` installs
    all four members; `rsync` installs without its optional dependency `python`; `gvim` with `vim` installed fails with
    "unresolvable package conflicts detected", exit 1, `vim` kept.
  - A second `-Sy` with current databases gets HTTP 304 and leaves the files untouched. `core.db.sig` is requested and
    answers 404 (the databases are unsigned, which `DatabaseOptional` allows); each package's `.sig` is downloaded next
    to it into the cache.
  - With no network, or with one extra repository whose database answers 404, `-Syu` fails with "failed to synchronize
    all databases", exit 1, nothing installed.
  - With the keyring replaced by a freshly initialized one, pacman imports the four packager keys from
    `openpgpkey.archlinux.org` (WKD) under `--noconfirm`, then fails with "signature is unknown trust", exit 1, nothing
    installed or upgraded; the imported keys stay in that keyring.
  - A successful install of `bc` leaves `/etc/pacman.conf` and every file under `/etc/pacman.d` byte-identical.
  - All 15,304 `name=version` strings of `[core]` and `[extra]` match the allowlist below; no name contains an uppercase
    letter or `@`.
- PKGBUILD(5) (https://man.archlinux.org/man/PKGBUILD.5): names use alphanumerics and `@ . _ + -` and do not start with
  `-` or `.`; `pkgver` contains no colon, slash, hyphen, or whitespace; `epoch` is a positive integer before a `:`.
- `/bin/sh` in the image is bash; `curl` and `gpg` are installed. The image manifest list has only `linux/amd64` (plus
  an attestation entry); Arch Linux publishes no official arm64 image.
- The devcontainer CLI's install-twice test (CLI 0.89.0) installs the feature first with a non-default value taken from
  a string option's `proposals` (the second entry when the default is not among them), then with the defaults.
- Test harness limits (`.agents/knowledge/testing.md`, `scripts/test_feature.ts`): a scenario runs through
  `devcontainer features test`, so a failing `install.sh` fails the image build and no check script runs; nothing
  asserts an expected failure. A `build` scenario's context is `test/<id>/<name>/`, which cannot reach `src/`. Two
  scenario keys for the same feature resolve to one staged ref, and the CLI installs a feature once. Scenario jobs run
  on amd64 only.
- The devcontainer CLI (0.89.0) writes each option to `devcontainer-features.env` as `NAME="<value>"` without escaping,
  and its wrapper runs `set -a; . ./devcontainer-features.env` as root before `./install.sh` (observed in the 0.89.0
  bundle, as recorded in the `apt-packages` design, pull request #33). A `"`, `$`, or backtick in an option value is
  therefore evaluated by that shell before the feature runs, and `install.sh` receives the result. A `<` or `>` inside
  the double quotes is not special to that shell.
- Neither `bc` nor `tree` is installed in the image; `file` is.
- Prior art: none. `devcontainers-extra` has no pacman feature (its `apko` feature is unrelated).

## Goals / Non-Goals

**Goals:**

- One POSIX `sh` script with `set -eu`, the skeleton the five installers share: parse, validate, detect the manager,
  install (refreshing through `-Syu`), clean. Checked by shellcheck in `just check` (dialect from the `#!/bin/sh`
  shebang) and, because the image's `/bin/sh` is bash, by running the validation and empty-list paths under busybox `sh`
  in the direct checks on the image without `pacman` (Test plan).
- Entries reach `pacman` only as separate, quoted arguments after `--`; the script has no `eval`, no `sh -c`, and no
  unquoted expansion of an entry. Checked by review of `install.sh` and by the direct check for "Shell metacharacters
  and inner whitespace are refused" with an entry such as `x;touch /tmp/pwned` that asserts the file does not exist. The
  guarantee covers the value `install.sh` receives; what the CLI's shell does to the value before that is outside the
  feature (Context, Risks).
- The allowlist matches ASCII only: the check runs with `LC_ALL=C`, so a bracket range cannot admit a non-ASCII letter.
  Checked by the direct check for "Shell metacharacters and inner whitespace are refused" with an entry that holds a
  non-ASCII letter.
- Every entry is validated before the `pacman` check and any `pacman` call, so a refused list leaves the image
  untouched. Checked by the direct refusal checks, which also assert that `/var/lib/pacman/sync` stays empty and that
  the local package database (`pacman -Q`) is unchanged.
- `pacman` runs once per installation, as `pacman -Syu --needed --noconfirm -- <entries>`, and the call carries no other
  option; in particular none of `-yy`, `-uu`, `-d`/`--nodeps`, `--overwrite`, `--ask`, `--ignore`, `--ignoregroup`,
  `--disable-sandbox`, `--disable-sandbox-filesystem`, `--disable-sandbox-syscalls`, `--dbonly`, `--noscriptlet`,
  `--assume-installed`, `--config`, `--gpgdir`, `--dbpath`, `--root`, `--sysroot`, `--cachedir`, or `--asdeps`. The
  script runs no `pacman-key` and writes no pacman configuration, so no `IgnorePkg`, `IgnoreGroup`, or `DisableSandbox*`
  setting (pacman.conf(5)) comes from the feature. Checked by review of `install.sh` against this bound, and by the
  checks for "Entry is not matched as a regular expression", "Constraint below the installed version on the second
  install", and "Conflict with an installed package fails".
- The feature writes nothing itself except what `pacman` installs, and removes only the files inside
  `/var/cache/pacman/pkg/` and `/var/lib/pacman/sync/`, deleting them directly rather than through `pacman -Scc`, whose
  "remove ALL files" question defaults to no under `--noconfirm`. Checked by the direct check for "Pacman configuration
  is unchanged" and by "Caches are removed".
- The `packages` option's `proposals` are lists installable on every image in the compatibility list and installed on
  none of them, with at least two entries, so the CLI's install-twice test installs real packages. Checked by
  `just test pacman-packages`.
- `devcontainer-feature.json` declares no `dependsOn` and no `installsAfter` (decision "No feature dependencies").
  Checked by review of the file.

**Non-Goals:**

- Adding repositories, mirrors, or keys, or choosing a package manager across distributions (issue #23, Out of scope).
  Upgrading the whole system is out of scope in the issue too; decision "Full upgrade through `-Syu`" records the
  approved exception.
- Installing an older version: the Arch Linux Archive and `pacman -U` are out of scope; a constraint only checks the
  version the configured repositories offer.
- An option to skip the system upgrade, to install optional dependencies, or to keep the sync databases.
- Checking the architecture: the feature downloads nothing architecture-specific, and `pacman` resolves packages for the
  image's `Architecture`; the compatibility list names the architecture that is tested.
- Refusing groups or names with several providers: `pacman`'s own resolution applies (Open question 2).

## Decisions

- **Native behavior first.** The five installers share the option shape and the script skeleton, not identical behavior.
  Where package managers differ (a constraint below the installed version, provided names and groups, range operators,
  upgrades of installed packages), the feature keeps `pacman`'s own behavior and the spec states it. An entry passes
  through in `pacman`'s own syntax for a package and its version constraint; the allowlist admits the characters that
  syntax needs, `<` and `>` included, and refuses every other character. The maintainer decided this for all five
  installers on 2026-10-01. Rejected: one identical guarantee across managers, which needs a second code path per
  manager that must agree with the manager's own resolution.
- **POSIX `sh`, shared skeleton.** Installing packages has to work on as many images as possible, one skeleton keeps the
  five installers auditable side by side, and `alpine`, an image of the `apk-packages` sibling, ships no bash. This
  deviates from `feature-authoring.md` (Deviations). Rejected: bash with `set -euo pipefail`, which the convention calls
  for here because the image ships bash.
- **Validate, then the empty check, then the `pacman` check.** A refused entry fails first on every image, so the same
  bad list gives the same message everywhere; the empty check runs before the `pacman` check, so the default options
  succeed on any image, including one without `pacman`. Rejected: failing on an image without `pacman` even for an empty
  list, which would make adding the feature with defaults to a non-Arch image an error although it has nothing to do.
- **A strict allowlist per manager.** An entry matches `^[A-Za-z0-9][A-Za-z0-9@._+:<>=-]*$` under `LC_ALL=C`: the
  PKGBUILD name and version characters, `:` for an epoch, and `<`, `>`, `=` for pacman's version constraints. This
  refuses option injection and pacman's `-` read-from-stdin target (leading `-`), local files, URLs, and
  `repository/name` (`/`, and a leading `.`), globs, regular-expression metacharacters other than `.` and `+`,
  whitespace, and every shell metacharacter except `<` and `>`. Those two stay because pacman's constraints need them
  (`name>=version`), as `apk-packages` and `zypper-packages` keep them for their managers (decision "Native behavior
  first"); they are harmless because they reach `pacman` only inside one quoted argument and are never seen by a shell.
  No trailing character is refused: `pacman` has no removal or install marker, and `bc-` is only an unknown name.
  Rejected: an earlier cross-manager expression `^[A-Za-z0-9][A-Za-z0-9._+:~=<>@/-]*$` drafted for all five installers,
  whose `/` admits URLs, package files, and repository prefixes; validating by asking `pacman`, which would run it on
  unvalidated input.
- **Full upgrade through `-Syu`, with `--needed`.** One `pacman -Syu --needed --noconfirm` transaction synchronizes
  every database with `-y` (a database is downloaded only when missing or older than the repository's), upgrades the
  system, including the replacements the repositories declare, and installs the list, which is Arch's only supported
  path and the maintainer's approved choice; `--needed` keeps an up-to-date listed package from being reinstalled.
  Rejected: `pacman -Sy <packages>` or `-S` without `-y`, an unsupported partial upgrade or, on this image, no database
  at all; `-Syyu`, which forces downloads of current databases; a separate `pacman -Sy --needed archlinux-keyring`
  before the upgrade, which the wiki endorses for stale keyrings but which adds a second transaction (Open question 1).
- **Pacman's default answers.** `--noconfirm` answers every question with its preset: proceed, replace, import a missing
  or expired packager key, first provider, all group members, and no to removing a conflicting package, which fails the
  transaction. The key import writes to the image's keyring; the maintainer accepted it as `pacman`'s own behavior (Open
  question 1), and the spec states it (requirement "Packager key import"). Rejected: `--ask`, an option pacman(8) does
  not document that presets individual answers, for example to remove conflicting packages or to refuse the key import.
- **Clean by deleting the cache and database files.** After installing, the files inside `/var/cache/pacman/pkg/` and
  `/var/lib/pacman/sync/` are removed, which returns the image to the state it shipped in. Rejected:
  `pacman -Scc --noconfirm`, which keeps every file because its question defaults to no; keeping the databases, which a
  later `pacman -S` without `-u` would use for a partial upgrade.
- **Detect by binary, describe by `/etc/os-release`.** Support means `pacman` is on the `PATH`; `/etc/os-release` is
  read only to name the detected distribution in the failure message. This deviates from `feature-authoring.md`
  (Deviations). Rejected: an `ID` allowlist, which would refuse Arch derivatives with a working `pacman` while adding no
  safety.
- **No feature dependencies.** Nothing this feature does depends on another feature's result. Rejected: an
  `installsAfter` on `ghcr.io/devcontainers/features/common-utils`; a user who needs an order sets
  `overrideFeatureInstallOrder`.
- **Direct checks for what a scenario cannot assert.** A host-side runner under `test/pacman-packages/`, following the
  repository's script convention (Deno first), runs `src/pacman-packages/install.sh` from the checkout, mounted
  read-only, as root in throwaway containers, and asserts the exit status, the message, and the image state after each
  run. It covers expected failures, installing twice in one container, and checks that need a prepared or offline
  container (Test plan). It changes no test infrastructure, and CI does not run it. Rejected: a `build` scenario that
  carries a first install, which cannot reach `src/` from its context; two scenario keys for the feature, which the CLI
  installs once; extending `scripts/test_feature.ts` with expected-failure scenarios, a test infrastructure change
  outside this change (Open question 3).

### Options

The feature is new, so its one option is added:

| Name       | Type     | Default | Enum or proposals                | Meaning                                                                                                                                                                                                                                       |
| ---------- | -------- | ------- | -------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages` | `string` | `""`    | proposals `"bc"` and `"bc,tree"` | Comma-separated packages to install with `pacman` from the image's configured repositories, each a name, a provided name, or a group, optionally with a version constraint (`name>=version`); a non-empty list also upgrades the whole system |

- **Default `""`.** No package list suits every image, so the feature installs nothing unless told to; with the default,
  it succeeds on any image, including one without `pacman` (decision "Validate, then the empty check").
- **Comma-separated.** Whitespace around entries and empty entries are dropped, so a trailing comma is harmless.
- **Proposals.** Two lists not installed in the image, so the CLI's install-twice test installs real packages (Goals).
- **Rejected shapes:** an array (feature options are only `string` or `boolean`); an option to skip the upgrade (Arch
  supports no partial upgrade); options to install optional dependencies or to keep the sync databases (Non-Goals).

### Deviations from `feature-authoring.md`

The maintainer accepted each for the five installers on 2026-10-01.

- **Shell.** The convention calls for bash with `set -euo pipefail` when every image in the compatibility list ships
  bash, which `archlinux:latest` does. The feature uses POSIX `sh` with `set -eu` so that all five installers share one
  skeleton (decision "POSIX `sh`, shared skeleton"). Issue #49 proposes relaxing the convention for features that need
  broad image compatibility.
- **Distribution detection.** The convention says to detect the distribution from `/etc/os-release`. The feature detects
  `pacman` on the `PATH` and reads `/etc/os-release` only for its message (decision "Detect by binary").
- **Skipping installed versions.** The convention says to skip an install when the requested version is already present.
  `--needed` skips an up-to-date listed package, but every run with a non-empty list upgrades the whole system, as the
  spec states.

### Security review surface

- **Downloads:** the feature downloads nothing itself; `install.sh` holds no URL and calls no download tool. `pacman`
  fetches the sync databases, packages, and their detached signatures only from the servers in the image's mirror list,
  and, only for a packager key missing from the image's keyring or expired there, that key from the Web Key Directory of
  the domain of the key's address (the packager's for a missing key, the key's first user ID for an expired one) or from
  GnuPG's default keyserver (URL inventory). Under `feature-authoring.md`'s download rules, the repositories are ones
  the image configures, so they fall under the package-manager rule: `pacman` verifies what it fetches, the feature adds
  no second check, and the spec names no package source because the feature requests none itself; the key lookup
  locations `pacman` and GnuPG use are named in the requirement "Packager key import". The databases are the one
  download verified by TLS alone (unsigned, `DatabaseOptional`); the spec states this in the requirement "Package index
  refresh", following the direct-download rule for TLS-only downloads. The feature weakens no check (requirement
  "Repository authentication stays in effect") and pins no key fingerprint because it neither adds nor chooses a key.
  The image's `DisableSandboxFilesystem` (Context) is inherited: the feature neither sets nor lifts a sandbox setting,
  and key fetches run through GnuPG, outside pacman's sandbox either way.
- **Verification and keys:** `SigLevel = Required` with the default `TrustedOnly` makes `pacman` verify every package's
  OpenPGP signature against `/etc/pacman.d/gnupg` and accept only keys trusted through the Arch Linux master keys in
  that keyring (requirement "Repository authentication stays in effect"). The databases are unsigned
  (`DatabaseOptional`), so the package list and its checksums are protected by HTTPS only; authenticity of what is
  installed rests on the package signatures. A key `pacman` imports under `--noconfirm` is used only when the master
  keys certify it; the observed foreign-keyring run failed with "unknown trust" after importing. The feature pins, adds,
  and changes no key itself; the keys are the image's `archlinux-keyring`, whose master key fingerprints Arch publishes
  at https://archlinux.org/master-keys/. A full upgrade may upgrade `archlinux-keyring`, whose install script then
  updates the keyring; that is a package's change, not the feature's.
- **Metadata:** none of `privileged`, `capAdd`, `securityOpt`, `mounts`, `entrypoint`, `init`, `containerEnv`, lifecycle
  commands, `dependsOn`, or `installsAfter`: the feature runs once at build time as root, installs system-wide, and
  needs nothing at container start. The feature sets no environment variable. It has no user-scoped setup, so
  `_REMOTE_USER` is unused.
- **Idempotency:** a second run validates, synchronizes (the first run removed the databases), upgrades the system, and
  installs its list; already installed packages stay unless the upgrade replaces them, and `--needed` skips up-to-date
  listed ones; any package may be upgraded to the version the repositories offer; a constraint below the installed
  version fails because the image's repositories offer only the current version and downgrades are never allowed. No
  `idempotencyExemption`.
- **Failure behavior:** a refused entry and a missing `pacman` exit 1 before anything changes; an unknown name, an
  unsatisfied constraint, a failed database synchronization, an untrusted signature, or a conflict with an installed
  package exit with `pacman`'s status 1, before the transaction changes any package. On an architecture without official
  Arch Linux images, the feature is unsupported and `pacman` resolves or fails as that image's repositories allow.

### Test plan

Where each scenario of `specs/pacman-packages/spec.md` is checked. "Scenario" means `scenarios.json`, run in CI on amd64
on the image each entry names; "test.sh" and "duplicate.sh" run in CI on every image and architecture of the
compatibility list; "Direct" means the host-side runner (decision "Direct checks"), run locally on every image of the
compatibility list, or on the pinned image outside it that a row names, with its output recorded in the PR's Validation
section. The runner reads package names and versions from the repositories at run time, so no fixed version goes stale.
Where it needs an outdated package, it installs the previous version from the Arch Linux Archive
(`https://archive.archlinux.org/packages/`, https://wiki.archlinux.org/title/Arch_Linux_Archive), a test-only host that
the feature never reaches and the URL inventory therefore leaves out; it installs with `pacman -U <package URL>`, which
verifies the package's detached signature under the image's `SigLevel`, because the image leaves `RemoteFileSigLevel`
unset (pacman.conf(5)).

| Scenario                                                                                      | Checked by                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| --------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Listed packages are installed                                                                 | Scenario; duplicate.sh with the `proposals` list                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Optional dependencies are left out                                                            | Scenario with `rsync`, asserting `python` is absent                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Spaces and empty entries are ignored                                                          | Scenario                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Listed package already up to date                                                             | Direct: installs a package, lists it again, and compares its version and install date                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Outdated installed packages are upgraded                                                      | Direct: after the run, a fresh `pacman -Sy` and `pacman -Qu` list nothing; when `-Qu` lists a package, the runner repeats the check once in a fresh container, because a mirror update between the feature's synchronization and its own can list a package that was current when the feature ran; when the image had nothing outdated, the runner first installs the previous version of a small package from the Arch Linux Archive                                                                         |
| Omitted packages; Empty list is a no-op                                                       | test.sh; Direct on the image without `pacman`                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Satisfied constraint is installed; Unsatisfied constraint fails                               | Direct, with `name=<offered pkgver>`, `name>=<offered version>`, and `name<<offered version>`                                                                                                                                                                                                                                                                                                                                                                                                                 |
| The three refusal scenarios                                                                   | Direct, each also asserting an empty `/var/lib/pacman/sync` and an unchanged `pacman -Q`; also on the image without `pacman`, where `/bin/sh` is busybox and only the exit status and the message are asserted; "Shell metacharacters and inner whitespace are refused" also with an entry holding a non-ASCII letter                                                                                                                                                                                         |
| Unknown package fails; Entry is not matched as a regular expression                           | Direct                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Name with several providers installs the first; Group name installs the whole group           | Direct, choosing at run time a provided name with several providers and a small group from `pacman -Sg`, and comparing with `pacman`'s own `-Sp` choice                                                                                                                                                                                                                                                                                                                                                       |
| Image without pacman fails clearly                                                            | Direct on `alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6` (the digest of its multi-architecture index, read on 2026-10-01), outside the compatibility list, which has no `pacman`                                                                                                                                                                                                                                                                                       |
| Missing database is downloaded                                                                | Every scenario and duplicate.sh run with a non-empty list on the plain image, which ships no database                                                                                                                                                                                                                                                                                                                                                                                                         |
| Failed refresh fails the feature                                                              | Direct, with no network                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Untrusted signature fails the install                                                         | Direct, with `/etc/pacman.d/gnupg` replaced by a freshly initialized keyring                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Pacman configuration is unchanged                                                             | Direct: the runner first brings its container current (`pacman -Syu --noconfirm`, then deletes the sync databases and the package cache), so the feature's transaction holds only the listed package and its dependencies; it hashes `/etc/pacman.conf` and every file under `/etc/pacman.d`, keyring included, before and after, and asserts that the transaction changed no package owning a file there and printed no "Import PGP key" line, so the scenario's precondition is checked rather than assumed |
| Missing certified key is fetched                                                              | Direct: the runner deletes from the keyring (`pacman-key --delete`) the packager key that signs a package not yet installed, lists that package, and asserts success and that the key is back in the keyring                                                                                                                                                                                                                                                                                                  |
| Installation runs without a terminal                                                          | Every scenario (the CLI builds without a terminal); Direct with stdin from `/dev/null`                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Conflict with an installed package fails                                                      | Direct: installs `vim`, then lists `gvim`                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Changed configuration file is kept on upgrade                                                 | Direct: installs from the Arch Linux Archive the previous version of a package with a `backup` file, changes that file, runs the feature, and asserts that the file keeps its changed content and, when the package's copy of the file differs between the two versions, that a `.pacnew` file is written beside it                                                                                                                                                                                           |
| Caches are removed                                                                            | Scenario; duplicate.sh                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Same list on the second install; Constraint below the installed version on the second install | Direct, running the feature twice in one container                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Different list on the second install                                                          | Direct, running the feature twice in one container; duplicate.sh, whose second, default install has an empty list                                                                                                                                                                                                                                                                                                                                                                                             |

### Supported images

The planned `test/pacman-packages/compatibility.json`:

| Image              | Architectures | Why                                                                                          |
| ------------------ | ------------- | -------------------------------------------------------------------------------------------- |
| `archlinux:latest` | amd64         | The official Arch Linux image, rebuilt weekly; pacman 7.1.0 on 2026-09-30; no official arm64 |

Excluded: `archlinux/archlinux` and `quay.io/archlinux/archlinux` (the same build, daily; one entry keeps CI to one
job); third-party arm64 images such as `menci/archlinuxarm`, whose repositories and keys Arch Linux does not publish.

## URL inventory

The feature itself fetches no URL at build or start time: it has no download, checksum, signature, or key URL of its
own, no latest-version endpoint, configures no repository, fetches nothing at start, and names no `dependsOn` or
`installsAfter` feature. The only network access is `pacman` (and the GnuPG it drives) reaching what the supported image
configures, listed here so the review sees the whole build-time surface. The image itself is pulled by the consumer or
the test harness, not by the feature. `$repo` is `core` or `extra`, `$arch` is `x86_64`; Arch publishes no `aarch64`
databases on these hosts (HTTP 404). Verified on 2026-09-30 by `curl -sSIL`, and by a GET for the WKD and keyserver rows
(the keyserver answers HEAD with 405), using `bc-1.08.2-1-x86_64` as the sample package and the packager key
`05C7775A9E8B977407FE08E69D4C5AA15426DA0A` (listed at https://archlinux.org/master-keys/ only as the revoker's signing
key of a master key, not as a master key) as the sample key, whose holder has an `archlinux.org` address among its user
IDs.

| URL / template                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  | Purpose                                                                                                                                  | When  | Integrity / authenticity                                                                                                                                                                                          | Official source evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          | Verified                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://fastly.mirror.pkgbuild.com/$repo/os/$arch/$repo.db` (and `$repo.db.sig`), and `…/$repo/os/$arch/<package>.pkg.tar.zst` with its `.sig`                                                                                                                                                                                                                                                                                                                                                                 | First server of the image's mirror list: sync databases, packages, detached package signatures                                           | build | HTTPS; each package's OpenPGP signature verified against `/etc/pacman.d/gnupg` (`SigLevel = Required`, `TrustedOnly`) and its checksum against the database; the database itself is unsigned (`DatabaseOptional`) | The image project's mirror list, https://gitlab.archlinux.org/archlinux/archlinux-docker/-/blob/master/rootfs/etc/pacman.d/mirrorlist; Arch's mirror status list, https://archlinux.org/mirrors/ (names the host, Tier 2); Arch's infrastructure repository holds the `pkgbuild.com` zone, with this host a CNAME to Fastly, https://gitlab.archlinux.org/archlinux/infrastructure/-/blob/main/tf-stage1/archlinux.tf                                                                                                                                                                                                                                                                                             | 2026-09-30: HTTP 200 for both databases, the package, and its `.sig`; 404 for `core.db.sig` and `extra.db.sig` (expected, unsigned databases); no redirect, final host `fastly.mirror.pkgbuild.com`                                                                                                                                                                                                                                                                                                                                                                     |
| `https://geo.mirror.pkgbuild.com/$repo/os/$arch/$repo.db` (and `$repo.db.sig`), and `…/<package>.pkg.tar.zst` with its `.sig`                                                                                                                                                                                                                                                                                                                                                                                   | Second server of the mirror list, used when the first fails                                                                              | build | as above                                                                                                                                                                                                          | as above (Tier 1; a `geo_domains` entry in `archlinux.tf`, a GeoDNS zone delegated to Arch's own `*.mirror.pkgbuild.com` name servers)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | 2026-09-30: HTTP 200 for both databases, the package, and its `.sig`; 404 for both `.db.sig`; no redirect, final host `geo.mirror.pkgbuild.com`                                                                                                                                                                                                                                                                                                                                                                                                                         |
| `https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<zbase32 hash of local part>?l=<local part>` (WKD advanced method) and, when that host does not resolve, `https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local part>` (direct method); `<domain>` and `<local part>` come from the package's `PACKAGER` address for a missing key (`archlinux.org` for almost every package) and from the key's first user ID in the image's keyring for an expired key (any domain the key holder chose) | WKD lookup of a packager key missing from the image's keyring or expired there, after `pacman`'s "Import PGP key" question (default yes) | build | The fetched key is used only when the Arch Linux master keys in the image's keyring certify it (`TrustedOnly`); otherwise the install fails with "unknown trust"                                                  | pacman v7.1.0 `_alpm_key_import` (WKD first, then keyserver; also on `ALPM_SIGSTATUS_KEY_EXPIRED`), https://gitlab.archlinux.org/pacman/pacman/-/blob/v7.1.0/lib/libalpm/signing.c; the address is the package's packager for a missing key, https://gitlab.archlinux.org/pacman/pacman/-/blob/v7.1.0/lib/libalpm/sync.c (`%PACKAGER%` read in `lib/libalpm/be_sync.c`), and the key's first user ID for an expired key (`result->key.uid`, signing.c); the keyring project's "distribution's Web Key Directory" refresh script, https://gitlab.archlinux.org/archlinux/archlinux-keyring/-/blob/master/wkd_sync/archlinux-keyring-wkd-sync; the `openpgpkey` record in Arch's `archlinux.tf` (above)             | 2026-09-30, for `archlinux.org`: HTTP 200 (`application/octet-stream`), no redirect, final host `openpgpkey.archlinux.org`, returned key's fingerprint matches; the direct URL on `archlinux.org` answers 404 and is not used while the subdomain resolves. Three packages in `[core]` and `[extra]` had a packager address on another domain, and an expired key's first user ID may name any domain (the sample key's is a domain outside `archlinux.org`); those hosts neither Arch nor this inventory controls; trust still requires the master keys' certification |
| `https://keyserver.ubuntu.com/pks/lookup?op=index&options=mr&search=0x<fingerprint>` (search), retried with `search=0x<last 8 hex digits of the fingerprint>` when the full fingerprint finds nothing, and `…/pks/lookup?op=get&options=mr&search=0x<fingerprint>` (import); dirmngr's `hkps://keyserver.ubuntu.com`                                                                                                                                                                                            | Keyserver fallback when the WKD lookup of a missing or expired packager key fails                                                        | build | as for WKD; the keyserver is not operated by Arch Linux, and a key from it gains no trust without the master keys' certification                                                                                  | pacman `_alpm_key_import` falls back to `key_search_keyserver`, which searches (`GPGME_KEYLIST_MODE_EXTERN`), by full fingerprint and then by its last 8 hex digits, and then imports (signing.c above); GnuPG made this host the default in 2.2.29 and 2.3.2, https://lists.gnupg.org/pipermail/gnupg-announce/2021q3/000461.html and https://lists.gnupg.org/pipermail/gnupg-announce/2021q3/000462.html ("Change the default keyserver to keyserver.ubuntu.com"); GnuPG 2.5.3 and later have none, https://www.gnupg.org/documentation/manuals/gnupg/Dirmngr-Options.html; `pacman-key --init` writes no `keyserver` line, and the image's GnuPG 2.4.9 reports this host from `gpgconf --list-options dirmngr` | 2026-09-30: GET HTTP 200 for `op=index` (`text/plain`) and `op=get` (`application/pgp-keys`, fingerprint matches), no redirect, final host `keyserver.ubuntu.com`; depends on the image's GnuPG version                                                                                                                                                                                                                                                                                                                                                                 |

## Risks / Trade-offs

- [Every non-empty install upgrades the whole system, so the same list produces different images over time, and a second
  feature run can change or replace packages the first installed] → Stated in the spec ("Full system upgrade",
  "Installing the feature twice") and in NOTES.md; it is Arch's only supported path. Pinning the base image's digest
  does not fix the result, because every build with a non-empty list synchronizes from the mirror; NOTES.md tells users
  who need a fixed, reviewed package set to prebuild the dev container image and pin the built image's digest.
- [The weekly official image's `archlinux-keyring` lacks a key that signs a current package] → `pacman` imports the key
  through WKD and trusts it when the master keys certify it; a key that needs a newer master-key certification fails
  with "unknown trust" until the next image. Upgrading `archlinux-keyring` first was rejected (Open question 1).
- [The sync databases are unsigned, so a compromised mirror or TLS path could offer an older, validly signed package
  version] → HTTPS to Arch-run hosts limits it; `-u` never downgrades an installed package; signing still stops any
  package Arch developers did not sign. The feature cannot change this without configuring repositories.
- [A key import writes to the image's keyring, also when the install fails, and contacts the domain of the key's address
  or a keyserver Arch does not run. For a missing key that domain comes from the package's `PACKAGER`, which is read
  from the unsigned sync database, and pacman 7.1.0 imports the key it finds through WKD before it compares the
  fingerprint, so a compromised mirror or TLS path could make the build contact a domain of its choosing and leave keys
  in the keyring] → Such keys gain no trust: only keys certified by the master keys are used (`TrustedOnly`), so the
  result is keyring clutter and a build-time request, not an installed package. The spec states the import (requirement
  "Packager key import"), NOTES.md names the hosts and says that fetched keys stay in the keyring untrusted, and the
  maintainer accepted it (Open question 1). The "Pacman configuration is unchanged" check brings its container current
  first, so it covers the keyring.
- [The keyserver fallback retries with the last eight hexadecimal digits of the fingerprint, and anyone can upload a key
  to `keyserver.ubuntu.com` that collides on those 32 bits] → The retry runs only after the WKD lookup and the
  full-fingerprint lookup found nothing, and a colliding key gains no trust under `TrustedOnly`; it adds nothing to the
  risk above.
- [The image disables pacman's Landlock filesystem sandbox (Context), so pacman's download process is not confined to
  its download directory] → Inherited from the image; pacman's syscall filter and its unprivileged download user stay in
  effect, and the feature changes no sandbox setting.
- [The devcontainer CLI shell-sources option values before `install.sh` runs (Context), so a `$(…)`, backtick, `$VAR`,
  or `"` in `packages` is evaluated, as root, before validation] → Whoever sets the option already controls the build,
  so no privilege boundary is crossed. The spec's refusal scenarios cover the value `install.sh` receives; NOTES.md says
  option values must not carry untrusted `"`, `$`, or backticks.
- [Arch moves to GnuPG 2.5.3 or later, which has no default keyserver] → The keyserver fallback then reaches no host; a
  key missing from WKD fails the install with `pacman`'s error, which the spec allows.
- [A name with several providers installs `pacman`'s first provider, which a repository change could alter] → Stated in
  the spec; users who need a specific provider name it. Open question 2.
- [A listed name that is both unknown as a package and a large group installs the whole group] → Stated in the spec; the
  list names what the user wants installed.
- [CI does not run the direct checks, so a later change could break a failure path unnoticed until someone runs them] →
  The PR's Validation section records their output; issue #50 tracks running them in CI (Open question 3).
- [An Arch derivative (for example Arch Linux ARM or Manjaro) with its own repositories and keys] → Only images in the
  compatibility list are supported; others work or fail with `pacman`'s own error.

## Open Questions

None open. The maintainer decided these on 2026-10-01, ahead of the package gate, following the decision "Native
behavior first":

1. **Packager key import.** Under `--noconfirm`, `pacman` fetches a missing or expired packager key into the image's
   keyring from the Web Key Directory of the key's address domain (the packager's for a missing key, the key's first
   user ID for an expired one) or, failing that, from `keyserver.ubuntu.com`, and keeps it even when the install fails;
   issue #23 lists "adding third-party repositories or keys" as out of scope, and the key gains no trust without the
   master keys' certification. Resolved: accepted as `pacman`'s own behavior, as the requirement "Packager key import"
   states; NOTES.md says that the build may contact Web Key Directory hosts outside Arch Linux and
   `keyserver.ubuntu.com`, and that fetched keys stay in the keyring without trust. Rejected: refusing the import
   through `--ask`, which pacman(8) does not document; first running `pacman -Sy --needed --noconfirm archlinux-keyring`
   and then `pacman -Su --needed --noconfirm -- <entries>`, which the Arch Wiki endorses for a stale keyring and which
   makes an import rarer but not impossible, at the price of a second transaction.
2. **Several providers and groups.** `apt-packages` fails on a virtual package with several providers; `pacman`'s
   default installs the first provider, and a group name installs the whole group. Resolved: `pacman`'s native
   resolution stays, as specified. Rejected: refusing both by resolving each entry with `pacman -Sp` first, a second
   code path.
3. **Direct checks in CI.** The direct checks run by hand, because the scenario harness cannot assert an expected
   failure. Resolved: accepted for this change; issue #50 tracks the test-infrastructure change that lets a feature's
   tests assert expected failures in CI, which all five installers would use. Does not change the spec.
4. **Issue text.** Issue #23 lists "upgrading the whole system" as out of scope, which the `-Syu` decision overrides,
   and "adding third-party repositories or keys", which Open question 1 touches. Resolved: the pull request description
   says so, and the issue stays the raw requirement. Does not change the spec.
