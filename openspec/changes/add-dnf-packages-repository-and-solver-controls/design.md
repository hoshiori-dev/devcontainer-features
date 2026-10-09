# Design

## Context

See proposal.md - Why. The feature at `1.0.1` builds one `dnf install` call whose every setting is a command-line
argument, validates all options before any package-manager call, and treats an empty list as a no-op without `dnf`
(phase 1 design, `openspec/changes/archive/2026-10-05-add-dnf-packages-feature/design.md`, "Phase 1 installation
controls"). That design deferred repository selection, best-version policy, retries, and download concurrency to #57 and
left `--setopt=best=False` unverified on dnf 4 (its Open question 6).

Facts this change relies on, checked on 2026-10-09 against the upstream documents and source, and by running `dnf` as
root in throwaway amd64 containers of the three compatibility images: `fedora:44` (built 2026-08-26, dnf5 5.4.3.0,
librepo 1.20.0), `almalinux:9` (9.8, built 2026-10-02, dnf 4.14.0, libdnf 0.69.0, librepo 1.19.0), and
`rockylinux/rockylinux:9` (9.8, built 2026-05-25, same dnf, libdnf, and librepo versions). The arm64 variants were not
run. Experiments used `--repofrompath`, `--nogpgcheck`, a temporary repository file, and a local HTTP server as
scaffolding only; none of these appears in the feature.

**Image configuration**

- `fedora:44`: `best` False (`/usr/share/dnf5/libdnf.conf.d/20-fedora-defaults.conf`), `max_parallel_downloads` 3,
  `max_downloads_per_mirror` 3, `skip_if_unavailable` True in `[main]`. Enabled: `fedora`, `updates`,
  `fedora-cisco-openh264`; nine configured and disabled identifiers (`updates-testing` and the `-debuginfo` and
  `-source` repositories).
- `almalinux:9`: `/etc/dnf/dnf.conf` sets `best=True` and `skip_if_unavailable=False`. Enabled: `appstream`, `baseos`,
  `extras`; 30 disabled identifiers, among them `crb`, `plus`, and `highavailability`.
- `rockylinux/rockylinux:9`: `best=True`, `skip_if_unavailable=False`. Enabled: `appstream`, `baseos`, `extras`; 33
  disabled identifiers, among them `crb`, `devel`, and `security`.
- No identifier on the three images starts with a character other than a letter or digit. None of the images configures
  a proxy.

**`best`**

- dnf `conf_ref`: boolean; "True instructs the solver to either use a package with the highest available version or
  fail. On False, do not fail if the latest version cannot be installed and go with the lower version", and the
  distribution may set it. `dnf5.conf(5)` documents the same key with the compiled default True; dnf 4's is False.
- `dnf install --assumeno <option> <package>` for an installed package with a newer candidate (`gnutls` on
  `almalinux:9`, `attr` on `rockylinux/rockylinux:9`, `ca-certificates` on `fedora:44`): `--setopt=best=True` plans the
  upgrade on all three; `--setopt=best=False` answers "already installed. Nothing to do." on all three; without the
  option the EL9 images upgrade and Fedora does not. This settles the phase 1 open question: the setting is effective on
  dnf 4.14.0.
- `--best` and `--nobest` exist in both generations; dnf5's primary spelling `--no-best` is a usage error (status 2) on
  dnf 4.14. For `--setopt=*.best=True` dnf5 prints "Option \"best\" not found" once per repository, and dnf 4.14 prints
  nothing: `best` is a main-level setting only.
- Both generations refuse a non-boolean value themselves (`--setopt=best=maybe`: status 1 on dnf 4.14, status 2 on
  dnf5), also an empty one.
- Pins under either value: phase 1 observed a pinned downgrade on Fedora (image `best` False) and on AlmaLinux (image
  `best` True).

**Repository selection**

- dnf `command_ref`: `--enablerepo` and `--disablerepo` "temporarily" enable or disable repositories "for the purpose of
  the current dnf command", accept an identifier, a comma-separated list, or a glob, may be repeated, and
  `--disablerepo` is mutually exclusive with `--repo`. dnf5 names them `--enable-repo` and `--disable-repo` and
  documents `--enablerepo` and `--disablerepo` as aliases; dnf 4.14 rejects the dnf5 spellings (status 2).
- Effect: `ninja-build` is unresolvable on `almalinux:9` and installs from `crb` with `--enablerepo=crb`; `epel-release`
  installs from `extras` and is unresolvable with `--disablerepo=extras`; `updates-testing` and `fedora-cisco-openh264`
  behave the same way on `fedora:44`. After real installs the image's enabled set and the checksums of
  `/etc/yum.repos.d`, `/etc/dnf`, `/etc/pki/rpm-gpg`, and `rpm -q gpg-pubkey` were unchanged.
- Order: for one identifier the last argument wins on both generations (`--enablerepo=X --disablerepo=X` leaves X
  disabled, the reverse enables it; `--disablerepo=* --enablerepo=crb` leaves only `crb`).
- Globs expand silently: `--enablerepo=crb*` enabled `crb`, `crb-debuginfo`, and `crb-source`.
- Unknown identifier: dnf5 fails for both arguments ("No matching repositories for …", status 2), also for a known
  identifier in another letter case (`FEDORA`). dnf 4.14 fails for `--enablerepo` ("Unknown repo", status 1) but for
  `--disablerepo` only prints "No repository match" and continues with status 0. An empty list item fails on dnf 4.14
  (`--enablerepo=crb,`: "Unknown repo: ''") and is ignored by dnf5.
- `--setopt=<id>.enabled=1` with an unknown identifier is silently ignored by dnf 4.14 and fails on dnf5.
- Identifier characters: `libdnf` `Repo::verifyId` and `libdnf5` `Repo::verify_id` accept only ASCII letters, digits,
  and `-`, `_`, `.`, `:`; `a/b`, `a b`, `a+b`, and `a@b` are refused by both, `A-b_c.d:e` is accepted by both.
- Listing the configured repositories: `dnf -q repolist --all` prints one header line and one row per configured
  repository with the identifier as the first field, on both generations. It exits 0 in a container without network on
  all three images, and with network it downloads no `repomd.xml`. dnf5 creates nothing under `/var/cache/libdnf5`; dnf
  4.14 creates the bookkeeping file `/var/cache/dnf/expired_repos.json` and writes its logs, and no metadata. The
  identifier column is not truncated: a 107-character identifier is printed in full with standard output not a terminal
  and `COLUMNS=20`. A repository whose identifier is `repo` appears as its own row below the header `repo id`.
- The same command with an identifier as argument is not an exact match: on dnf 4.14 `repolist --all CRB` prints the
  `crb` row, `base*` prints three rows, and a repository's name (`Rocky Linux 9 - BaseOS`) selects its row; on dnf5
  `Fedora` prints the `fedora` row. Output that is merely non-empty therefore does not prove that an identifier is
  configured.
- With the phase 1 arguments: `--refresh '--setopt=*.skip_if_unavailable=False' '--setopt=*.timeout=7' --enablerepo=X`
  refreshed X too on both generations. With `--cacheonly '--setopt=*.skip_if_unavailable=False'` after a `makecache`
  that left one enabled repository out: the install fails naming that repository ("Cache-only enabled but no cache for
  …"), succeeds in planning when `--disablerepo` names it, and fails naming a repository `--enablerepo` adds without
  cache (`almalinux:9` with `extras` and `crb`, `fedora:44` with `fedora-cisco-openh264` and `updates-testing`).
- Plain `dnf clean all` removed the metadata, and `dnf clean packages` the package files, of a repository enabled only
  for the preceding install (`almalinux:9`, `fedora:44`).
- All phase 2 arguments together with the phase 1 timeout pair (`--setopt=best=False`, the two parallel-download
  arguments, `--disablerepo`, `--enablerepo`) plan a transaction on `almalinux:9` and `fedora:44`.

**Parallel downloads**

- dnf `conf_ref`: `max_parallel_downloads`, integer, "Maximum number of simultaneous package downloads. Defaults to 3.
  Maximum of 20."; `dnf5.conf(5)` the same, valid in `[main]` and in a repository section. Both libraries hand the value
  to librepo (`libdnf` `Repo.cpp`, `libdnf5` `repo_downloader.cpp`: `LRO_MAXPARALLELDOWNLOADS`).
- Against a local repository of seven packages whose responses are delayed one second, counting the peak of concurrent
  package requests, identical on `almalinux:9` and `fedora:44`: no override 3; `=1` 1; `=2` 2; `=10` 3, held by
  `max_downloads_per_mirror=3`; `=10` with `max_downloads_per_mirror=10` 7.
- A repository-level value wins over the main-level one (main 1 with repository 2: peak 2; main 2 with repository 1:
  peak 1).
- Native parsing does not enforce the range: `=21` and `=-1` pass option parsing on both generations and abort when the
  download starts ("Bad value of LRO_MAXPARALLELDOWNLOADS", status 1); `=05` is accepted; `=0` is refused with different
  messages and statuses.

**Retries and locks**

- dnf `conf_ref` documents `retries` (default 10, 0 "makes dnf try forever"); `dnf5.conf(5)` has no such entry. dnf5
  5.4.3 accepts the key, but its source reads it nowhere outside the configuration classes and lists it in
  `doc/dnf5.conf-todo.5.rst`. dnf 4.14 uses it only in a loop over errors that `dnf/repo.py` fills from delta-RPM
  rebuild failures. Against a local repository answering HTTP 503, every run made exactly four requests for the file,
  with no override and with `retries` 1, 3, and 25, main-level or per repository, on both generations. Only HTTP 503
  from a single URL was run.
- Locks: dnf 4.14 waits without limit, polling every second, or fails at once with `exit_on_lock=True` (status 200).
  dnf5 5.4.3 accepts `exit_on_lock` without effect, takes no download lock, and waits without limit for the system
  repository lock; its only switch, `--skip-file-locks`, bypasses the protection.

**Environment** (for NOTES.md; the feature sets none of it)

- Repository variables: `DNF_VAR_<name>` reaches `$<name>` in a repository file on both generations, names are
  case-sensitive. With the variable in the environment and in a vars file, dnf 4.14 used the file and dnf5 5.4.3 the
  environment; both EL9 images ship vars files. `DNF_VAR_releasever` overrode `$releasever` on both. `DNF_VAR_basearch`
  was ignored by dnf 4.14 and honored by dnf5 5.4.3, against `dnf5.conf(5)`.
- Proxy: a configured `proxy` wins over the environment; otherwise curl's variables apply, of which lower-case
  `http_proxy` and `all_proxy` are honored for HTTP URLs, upper-case `HTTP_PROXY` is not, and both `https_proxy` and
  `HTTPS_PROXY` are honored for HTTPS URLs; `no_proxy` bypasses both kinds; an empty `proxy=` in a repository cancels a
  main-level proxy but not one from the environment. Proxy credentials and `proxy_sslverify` were not tested.
- Not verified: that variables a `devcontainer.json` sets (`containerEnv`, `remoteEnv`) do not reach `install.sh` while
  the base image's `ENV` does.

Family conventions shared by the five package installers in this phase (`apt`, `dnf`, `apk`, `zypper`, `pacman`),
applied here: a numeric control is a string that is empty to inherit; an override of a native boolean the feature does
not pass in phase 1 is the enum `inherit`, `true`, `false`; an identifier list is a string parsed like `packages`; one
option name per shared concept (`parallelDownloads`, also on `pacman-packages`; `lockTimeout` and `downloadRetries` on
the installers whose manager supports them); and an option is declared only when every compatibility image honors it.

## Goals / Non-Goals

**Goals:**

- With the four options omitted, the arguments of every `dnf` call are those of `1.0.1`. Checked by review of
  `install.sh` and by the existing scenarios, which run unchanged.
- Every new setting is an argument of the one `dnf install` call; the feature writes no configuration file and sets no
  environment variable for `dnf`. Checked by review and by the scenarios "Dnf configuration is unchanged" and
  "Repository selection leaves the configuration unchanged", which hash `/etc/yum.repos.d`, `/etc/dnf`,
  `/etc/pki/rpm-gpg`, and `rpm -q gpg-pubkey` before and after.
- All four options are validated in the same place as the phase 1 controls, before the empty-list exit and before
  `require_dnf`. Checked by the validation scenarios run with an empty list on an image state that would reveal a `dnf`
  call (no repository metadata in the cache, `rpm -qa` unchanged).
- Identifier and numeric checks match ASCII only: character sets are enumerated in the script and evaluated under
  `LC_ALL=C`, and the numeric length is tested before any arithmetic comparison, as for `networkTimeout`. Checked by
  "Repository identifiers are validated" with a non-ASCII letter and "Parallel download boundaries are validated" with a
  value of many digits.
- An identifier reaches `dnf` only inside one quoted argument of the form `--enablerepo=<id>` or `--disablerepo=<id>`,
  one argument per identifier; the script has no `eval` and no unquoted expansion of an identifier. Checked by review
  and by "Repository identifiers are validated" with an identifier such as `x;touch /tmp/pwned`.
- All disable arguments precede all enable arguments, and an identifier in both lists never reaches `dnf`, so the result
  does not depend on how the options were written. Checked by "Identifier in both repository lists is refused" and by
  review of the argument order.
- The existence check reads one listing of configured repositories and counts an identifier as configured only when it
  equals, byte for byte, the first field of a row other than the header line. Checked by "Unknown repository fails
  before installation" on both generations, by "Identifier in another letter case is unknown", and by a check with a
  repository whose identifier is `repo`.
- The existence check and the listing run only when the package list is not empty and at least one repository list is
  not empty. Checked by "Empty list ignores installation controls" on an image without `dnf` and by review.
- The feature never passes `--repo`, `--repoid`, `--repofrompath`, `--nogpgcheck`, `--skip-file-locks`, a `<id>.enabled`
  setting, `retries`, `exit_on_lock`, `max_downloads_per_mirror`, or a proxy setting. Checked by review and by "No retry
  or lock setting is passed", which inspects the arguments the installer hands to `dnf`.
- `dnf clean` keeps its phase 1 arguments. Checked by "Cleanup covers a temporarily enabled repository".

**Non-Goals:**

- A retries option and a lock-wait option (decision "No option where `dnf` has no bound").
- An exclusive repository set, patterns, per-package repository choice, and creating or editing repositories or keys.
- Raising the per-mirror download limit, throttling, minimum rate, and mirror selection.
- A proxy option, a repository-variable option, and any pass-through of arguments, settings, or environment.
- Downgrade and conflict-replacement policy (phase 3, #62), and everything in #57's Out of scope.
- A change to the compatibility list, to `dnf clean`, or to the phase 1 options.

## Decisions

- **Command-line arguments on the install call, nothing else.** The family prefers a per-invocation argument over an
  environment variable over a temporary file; `dnf` offers an argument for all three controls, so no file is written and
  nothing needs removing. Rejected: a drop-in under `/etc/dnf`, which edits the image and must be undone on every exit
  path; `DNF_VAR_*` or other environment, which no control here needs.
- **`best` through `--setopt=best=True|False`.** One spelling works on both generations and follows the phase 1
  `install_weak_deps` argument. `best` is a main-level setting, so it gets no `*.` companion; dnf5 rejects one.
  Rejected: `--best` / `--nobest`, where dnf5's primary spelling `--no-best` fails on dnf 4.14, so the common spelling
  would rest on an alias; a boolean option, which cannot express "leave the image's setting", so its default would
  override either Fedora or EL9.
- **Repository selection through `--disablerepo=<id>` then `--enablerepo=<id>`, one argument per identifier.** These are
  the only spellings common to both generations. One identifier per argument keeps `dnf`'s own comma and glob handling
  out of the path. Rejected: `--setopt=<id>.enabled=`, which dnf 4.14 silently ignores for an unknown identifier;
  passing the option value as one native comma list, which lets an empty item fail on dnf 4.14 and pass on dnf5;
  `--repo`, an exclusive set that is mutually exclusive with `--disablerepo` and breaks dependency resolution
  (`--disablerepo=* --enablerepo=crb ninja-build`: "nothing provides emacs-filesystem").
- **A strict identifier set, first character a letter or digit.** The set is upstream's own (`-`, `_`, `.`, `:`,
  letters, digits); requiring a letter or digit first removes any option-like value. Globs are refused although `dnf`
  accepts them, because their expansion hides what gets enabled and `*` disables everything. Rejected: the full upstream
  set for the first character, which admits `-x`; accepting globs with a warning.
- **An identifier in both lists is an error.** Otherwise the fixed argument order would silently make enable win.
  Rejected: enable wins; last-written wins, which the two separate options cannot express.
- **The feature checks that each identifier is configured.** dnf 4.14 warns and continues for an unknown
  `--disablerepo`, so a misspelled identifier would install from the repository the developer meant to leave out, on EL9
  only. One listing call after `require_dnf` gives the same failure, status 1 naming the identifier, on both generations
  and for both lists, before `dnf` loads metadata. It reads the full listing and compares the first field exactly,
  because the same command with an identifier as argument also matches other letter cases, globs, and repository names
  (Context). Rejected: accepting the native difference and specifying the dnf 4 warning as allowed, a control that is
  silently ignored on one generation; `repolist --all <id>` judged by non-empty output, which accepts `CRB` and then
  lets dnf 4.14 ignore it; reading `.repo` files in the script, a second parser that must agree with `dnf`'s variable
  substitution and `reposdir`.
- **An identifier already in the requested state is accepted.** The same `devcontainer.json` may run on images with
  different defaults, and `dnf` itself treats it as nothing to do. Rejected: failing, which would make a list written
  for one image an error on another that already enables the repository.
- **`parallelDownloads` through the main-level and the `*.` setting together.** A repository-level value wins over the
  main-level one, so both are passed, the phase 1 timeout pattern. The feature enforces 1 through 20 itself because
  `dnf` accepts 21, -1, and 05 at parsing. Rejected: also raising `max_downloads_per_mirror`, a politeness limit toward
  mirrors that the issue does not name; the cap is documented instead.
- **No option where `dnf` has no bound.** `retries` changes no request count on either generation and its value 0 means
  forever; lock waiting is unbounded or absent. A declared option would be accepted and ignored, which the family rule
  forbids, so neither `downloadRetries` nor `lockTimeout` exists here and the spec says so ("Undeclared settings are
  inherited"). #57's "bounded retries where supported" resolves to "not supported" on dnf 4.14 and dnf5 5.4.3. Rejected:
  `downloadRetries` mapped to `retries`, a documented no-op; `exit_on_lock` as a boolean, fail-fast only on dnf 4 and
  without effect on dnf5; `--skip-file-locks`.
- **Proxy and repository variables are documentation.** Both are inherited from the image and the build environment; an
  option would carry URLs or credentials into `devcontainer.json`, and a `DNF_VAR_releasever` option would reintroduce
  the release-version override the issue excludes.

### Options

The Option requirements in the delta spec are the source of truth; the phase 1 options are unchanged and not listed.

| Name                  | Type     | Default     | Enum or proposals            | Meaning                                                                                                                                |
| --------------------- | -------- | ----------- | ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `best`                | `string` | `"inherit"` | `["inherit","true","false"]` | Best-version policy for this invocation; `inherit` passes nothing and the image decides.                                               |
| `enableRepositories`  | `string` | `""`        | no proposals                 | Comma-separated identifiers of repositories the image configures and leaves disabled, enabled for this invocation; empty enables none. |
| `disableRepositories` | `string` | `""`        | no proposals                 | Comma-separated identifiers of repositories the image enables, left out for this invocation; empty leaves none out.                    |
| `parallelDownloads`   | `string` | `""`        | no proposals                 | Upper bound of simultaneous downloads, a canonical decimal from 1 through 20; empty inherits the image's setting.                      |

Reasons for the defaults: each default passes no argument, so an unset option is exactly `1.0.1`. `inherit` rather than
`false` because the images disagree (Fedora False, EL9 True) and either fixed default would change one of them. Empty
repository lists keep the image's set. An empty bound keeps the image's `max_parallel_downloads`.

No proposals: repository identifiers differ per image, so any proposal would be wrong on some compatibility image, and
the CLI's install-twice test takes its first-run value from `proposals`; a numeric proposal would suggest a recommended
concurrency the feature does not have.

Rejected option shapes: a boolean `best`; `bestPolicy` or `bestVersion` as the name, where the issue and `dnf` both say
`best`; `maxParallelDownloads`, replaced by the family name `parallelDownloads`; one `repositories` option with `+id`
and `-id` items, a private syntax; an exclusive `repositories` list (`--repo`); `enableRepos` / `disableRepos`,
abbreviations the other options do not use; `0` or `inherit` as the word for an unset numeric bound, where the family
uses the empty string as `networkTimeout` does; an upper bound other than `dnf`'s own 20.

Descriptions in `devcontainer-feature.json` follow the phase 1 sentence pattern ("…, or empty to inherit image settings;
applies only to this invocation."). The feature's `description` there ("…the repositories the image already enables") is
revisited with the implementation, since a configured repository can now be enabled.

### Verification bounds

- Each new option has scenarios on all three compatibility images, since the two generations and the two inherited
  `best` values differ. Expected failures and second runs use the installer directly, as `testing.md` (Running the
  installer) describes.
- `best` scenarios do not rely on a named package having an update on the day of the test: they find an installed
  package with a newer candidate at run time, or assert the arguments the installer passes when none exists.
- Repository scenarios use identifiers the images ship (`crb` and `extras` on EL9, `updates-testing` and
  `fedora-cisco-openh264` on Fedora) and assert the image's enabled set and the configuration hashes afterwards.
- The unknown-identifier scenarios assert the feature's own message and status 1 on both generations and that the cache
  holds no repository metadata; on dnf 4.14 the bookkeeping file `expired_repos.json` may exist and is not metadata.
- Parallel-download scenarios assert the arguments and, where concurrency is asserted, use a local endpoint on a
  loopback address; a public mirror proves nothing.
- "No retry or lock setting is passed" and the "inherited" scenarios assert arguments through a stand-in `dnf` on
  `PATH`, the way the phase 1 timeout scenario does.
- `duplicate.sh` covers what the CLI's install-twice test supplies; the second-install scenarios of the delta run the
  installer directly with non-default repository lists, `best`, and `parallelDownloads`, since those values must name
  repositories of the image under test.

### NOTES.md

NOTES.md documents each new option and gains one section on inherited configuration with the four headings the five
installers share: "What the feature sets explicitly", "What is inherited", "Proxy", and "Locks and retries". Bounds on
its content:

- It states only facts listed under Context, tied to the tested versions where the generations differ (the `DNF_VAR_`
  precedence, the dnf5 `basearch` behavior), and labels the unverified item as such or omits it.
- It says that `best=true` can upgrade an installed package named without a version and `best=false` can leave it; that
  `parallelDownloads` above the image's per-mirror limit has no visible effect against one mirror; that a repository
  option never changes a repository file; that an enabled repository's own signature settings apply; and that leaving
  out a repository can leave out its updates.
- It says that the feature has no retries and no lock option and why.

### Security review surface

- **Downloads:** unchanged. The feature still fetches nothing itself; `dnf` reaches only repositories the image
  configures. `enableRepositories` widens that from "enabled" to "configured": URLs come from the image's repository
  files, none from an option.
- **Verification and keys:** no argument relaxes a check. A temporarily enabled repository brings its own `gpgcheck` and
  `gpgkey`; under `--assumeyes` `dnf` may import the key it names, the risk phase 1 accepted for enabled repositories
  and the signature requirement now states for configured ones. On the tested images `crb` and `updates-testing` use the
  distribution key already in the keyring.
- **Option injection:** identifiers are validated against an enumerated ASCII set and passed inside one argument each;
  numeric values are digits only; `best` is one of three words. No value is written to a file.
- **Failure behavior:** invalid options exit 1 before any `dnf` call; an unconfigured identifier exits 1 after
  `require_dnf` and before the install; a package that only a left-out repository offers fails with `dnf`'s own status.
- **Idempotency:** nothing persists, so a second run starts from the image's configuration; no `idempotencyExemption`.

## Risks / Trade-offs

- [A `devcontainer.json` can install from a repository the image's author left disabled, including one with `gpgcheck=0`
  or a remote key] → Stated and accepted in "Package signature checking stays in effect"; the identifier is explicit in
  the configuration, and the repository and its settings are the image's.
- [`disableRepositories` can leave out the repository that carries updates or a dependency] → Stated in "Repository
  selection is scoped to installation"; failures are `dnf`'s resolver errors.
- [The existence check depends on the layout of `repolist` output: a header line and the identifier as the first field]
  → Verified on dnf 4.14.0 and dnf5 5.4.3.0, including long identifiers; the scenarios for unknown identifiers run on
  both generations, so a layout change fails a test rather than passing silently. An identifier is never matched
  loosely, so a misread can only refuse a configured repository, never accept an unconfigured one.
- [The first-character rule is stricter than upstream: a repository whose identifier starts with `_`, `.`, `:`, or `-`
  cannot be named] → None of the 81 identifiers on the tested images does; the rule is an open question below.
- [Values of `parallelDownloads` above 3 usually show no effect because of the per-mirror limit, which reads as an
  ignored option] → Stated in "Parallel downloads are bounded" and in NOTES.md.
- [`best` scenarios depend on repository state at test time] → Verification bounds: candidates are found at run time.
- [Facts are tied to dnf 4.14.0, dnf5 5.4.3.0, librepo 1.19 and 1.20 on amd64; dnf5 accepts `retries` and `exit_on_lock`
  without effect and may implement them later] → No option depends on them; a later change can add one when a bound
  exists. arm64 was not run and ships the same package versions.
- [Retry behavior was measured for HTTP 503 from one URL only] → The source reading covers the other failure classes;
  NOTES.md states the measured case as measured.
- [dnf 4.14 leaves `expired_repos.json` and log lines after a failed existence check] → Neither is repository metadata
  or a package change; the spec's wording is limited to those two.

## Open Questions

For the maintainer at the package gate; each has the recommendation the package currently carries.

1. **No retries and no lock option.** The issue asks for "bounded retries where supported" and the epic names lock
   waiting; the finding is that neither is supported by `dnf`. Carried: no option, a statement in the spec and NOTES.md.
2. **Unknown repository identifier.** Carried: the feature checks both lists itself with one listing call. Alternative:
   accept dnf 4.14's warn-and-continue for `disableRepositories`.
3. **Names.** Carried: `best`, `enableRepositories`, `disableRepositories`, `parallelDownloads`. Names are a contract; a
   rename after release is MAJOR.
4. **An identifier in both lists.** Carried: validation error. Alternative: enable wins.
5. **Identifiers already in the requested state.** Carried: accepted silently.
6. **First character of an identifier.** Carried: letter or digit. Alternative: the full upstream set.
7. **`max_downloads_per_mirror`.** Carried: not touched, the cap documented.
8. **Trust consequence of `enableRepositories`.** Carried: stated and accepted in the signature requirement. Whether
   `SECURITY.md`'s overview needs a sentence is the maintainer's call: `AGENTS.md` (Keep In Sync) ties it to the threat
   model in `review-guidance.md` and the trust rules in `feature-authoring.md`, neither of which this change edits.
9. **NOTES.md and observed differences.** May NOTES.md state the `DNF_VAR_` precedence difference and the dnf5
   `basearch` behavior as observations tied to the tested versions? Carried: yes, so labeled.
10. **Log line.** Whether the install log line also names `best` and the repository lists. Not a contract item; it
    affects tests that match output. Carried: decided with the implementation.

## Follow-up work

Phase 3 (downgrade and conflict-replacement policy) is tracked in
[#62](https://github.com/hoshiori-dev/devcontainer-features/issues/62) and is outside this approval package.
