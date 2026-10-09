# Design

## Context

See proposal.md - Why. Facts this change relies on, checked on 2026-10-09 against upstream documents and source and by
running `zypper` in the two images of `test/zypper-packages/compatibility.json`, amd64 only. Both images ran zypper
1.14.101 with libzypp 17.38.16 (`opensuse/leap:16.0`; `opensuse/tumbleweed`, VERSION_ID 20261007), so the compatibility
list holds one tool generation and no behavior below differs between its images. Where a fact was read from source and
not run, or run on one image only, the entry says so.

Documents: zypper(8) of zypper 1.14.101 (https://github.com/openSUSE/zypper/blob/1.14.101/doc/zypper.8.txt) and
zypp.conf(5) of libzypp 17.38.16 (the URL in the requirement "Repository authentication stays in effect").

- **The images.** Both provide the RPM capability `libzypp(econf)` and have an empty `/etc/zypp/zypp.conf.d`;
  `/run/zypp` exists on neither. Leap ships `/etc/zypp/zypp.conf` (active lines `solver.onlyRequires = true`, a
  `multiversion` line, `rpm.install.excludedocs = yes`), which masks `/usr/etc/zypp/zypp.conf`. Tumbleweed ships no
  `/etc/zypp/zypp.conf`; its settings are `/usr/etc/zypp/zypp.conf` and
  `/usr/etc/zypp/zypp.conf.d/{excludedocs,no-recommends}.conf`. Neither sets a `ZYPP_*` or proxy variable. Enabled
  aliases: Leap `openSUSE:repo-oss`, `openSUSE:repo-openh264`; Tumbleweed `repo-oss`, `repo-non-oss`, `repo-update`,
  `repo-openh264`. Defined but disabled: Leap `openSUSE:repo-non-oss`, `openSUSE:repo-non-oss-debug`,
  `openSUSE:repo-oss-debug`, `openSUSE:repo-oss-source`; Tumbleweed `repo-debug`, `repo-source`.
  `zypper --xmlout --non-interactive --no-refresh repos` prints one `<repo alias="…" … enabled="0|1">` element per
  repository on both.
- **Exact names.** zypper(8), install: "-n, --name: Select packages by their name, don't try to select by capabilities."
  Observed with `zypper -n --no-refresh install --dry-run --no-recommends [--name] -- X`: without `--name`, `awk` prints
  "'awk' not found in package names. Trying capabilities." and selects `gawk`; with `--name`, `awk` exits 104 ("Package
  'awk' not found."), `gawk` exits 0, the forms `tree=<edition>`, `tree.x86_64`, `tree>=1`, and `tree-<version>` exit 0,
  `tree<1` and `Tree` exit 104, and `bc nosuchpkg-xyz` exits 104 selecting nothing. `--name` with `--capability` exits
  2. `--name` together with `--repo` behaves the same (`awk` 104, `gawk` 0).
- **Repository selection.** zypper(8), install: "-r, --repo alias|name|#|URI: Work only with the repository specified …
  can be used multiple times", and: "Using --repo is discouraged as it currently hides unmentioned repositories from the
  resolver … packages originally installed from the hidden repos will now be treated as orphaned or dropped. They can be
  silently removed if involved in a dependency conflict. In the future --repo will become an alias for --from."
  Observed:
  - `install --repo <oss> -- bc` exits 0; `--repo repo-non-oss -- bc` exits 104 ("No provider of 'bc' found.");
    `--repo nosuchrepo` exits 3; `--repo repo-debug` (disabled) exits 3 ("is disabled"); on Leap `--repo repo-oss` exits
    3, only the alias `openSUSE:repo-oss` matches.
  - Dependencies are restricted (Tumbleweed): `--repo repo-non-oss -- 7kaa-music` exits 4 ("nothing provides '7kaa'");
    without `--repo` it resolves.
  - In a fresh container `refresh --repo <oss>` leaves raw metadata of that repository only, and a following
    `--no-refresh install --repo <oss>` fetches no other repository's metadata, whereas an unrestricted
    `--no-refresh install` downloads the missing ones.
  - With an added enabled repository at an unreachable address: `refresh --repo <oss>` exits 0, a refresh that also
    selects the unreachable one exits 4, and a plain `refresh` exits 4.
  - `--no-refresh refresh --build-only --repo A --repo B` rebuilds the parsed cache of exactly those.
  - `refresh <disabled alias>` exits 0 with only a warning, and zypper matches a selection also by name, number, and
    URI, so zypper's own answer to a bad selection is uneven.
  - One conflict case (Tumbleweed, a local fixture repository whose package conflicts with `bc`, with `bc` installed
    from the then hidden `repo-oss`): the install exits 4 at the solver's question and `bc` stays.
  - One install case (Tumbleweed): with `bc` installed from `repo-oss`, `install --repo repo-non-oss` of a package whose
    dependencies are installed adds that package and removes nothing.
- **Lock.** zypp.conf(5): "lock_timeout (0 sec) … A negative value will wait forever. The environment variable
  ZYPP_LOCK_TIMEOUT can be used to override this setting." Observed with the lock held by another zypper: without a
  setting, `refresh` and `clean` exit 7 at once ("System management is locked by the application with pid …"); with
  `ZYPP_LOCK_TIMEOUT=4`, exit 7 after 6 s; with `60` and the holder leaving after 8 s, exit 0 after 10 s; the variable
  beats a `lock_timeout` from configuration. `zypper repos` takes no lock, and a stale pid file does not block. libzypp
  checks the lock again after 1, 2, 3, … seconds, the step capped at 60 (source, `ZYppFactory.cc`), which is why the
  wait runs past the value. It parses the variable leniently: `4x` waited as 4, and `abc` behaved as 0.
- **Timeouts and attempts.** zypp.conf(5): `download.connect_timeout` (60 sec), `download.transfer_timeout` (180 sec),
  `download.max_silent_tries` (1, "Setting this to 0 will silently retry forever!"). They are configuration only:
  neither zypper nor libzypp reads an option or environment variable for them, and `zypper.conf` has no network key
  (zypper(8), FILES: "zypp.conf and zypper.conf have different content and serve different purpose").
  - Connect: with a repository at an unroutable address and a value of 2, a refresh fails after 4 s (two probes).
  - Transfer: the value starts an activity timer, while libzypp caps the whole transfer at a fixed 3600 s and clamps the
    key to 0..3600 (source, `zypp-curl/ng/network/request.cc`, `mediaconfig.cc`). Observed on Tumbleweed only: a server
    that accepts and never answers, value 5, times the metadata request out after 5 s; a server that sends headers for a
    package file and stalls, value 4, ends the install with exit 4 after about 5 s. That a transfer which keeps
    receiving data outlasts the value is read from source and was not run.
  - Attempts (Tumbleweed only): a refresh against the unreachable repository takes 6 s at the default and 18 s with
    `download.max_silent_tries = 3`, three tries on each of two probes. During `install`, with 2 and 3 tries, the server
    saw exactly one request for the stalled package file: the commit's package preloader tries each mirror once.
    zypper's own "Retrying in 30 seconds..." appeared only with `zypper download`, a command the feature does not run.
  - The values 0 of the three keys were not run. libzypp's number parser accepts trailing text.
- **Configuration lookup.** zypp.conf(5) names `/etc/zypp/zypp.conf`, the vendor directory `/usr/etc/zypp`, and
  `zypp.conf.d/*.conf` drop-ins of both, parsed after `zypp.conf` "in lexicographic order of their filenames. Later
  settings override earlier settings", and refers to the UAPI configuration files specification. The source
  (`zypp-core/parser/econfdict.cc`) searches `/etc`, `/run`, and `/usr/etc`, in that order of precedence per file name;
  the manual page does not name `/run`. Observed: a drop-in `/run/zypp/zypp.conf.d/<name>.conf` is read (zypper's log
  shows the file and the key) and removing it leaves the image's files byte-identical; the last assignment of a key
  wins; an image drop-in in `/etc/zypp/zypp.conf.d` whose name sorts later beats it; a file of the same name in `/etc`
  masks it.
- **ZYPP_CONF.** zypp.conf(5): "If the environment variable is set the default way of parsing system and vendor
  configuration files is disabled … solely this file is parsed as configuration file. Otherwise the builtin defaults
  apply." Observed: with `ZYPP_CONF` naming a file that holds only two timeouts, the image's `rpm.install.excludedocs`
  and `solver.onlyRequires` are lost (packages install with their documentation, and a dry run of `less` grows from 1 to
  8 packages); with a path that does not exist, zypper runs on builtin defaults without an error.
- **A libzypp without drop-ins.** Informational, outside the compatibility list: `opensuse/leap:15.6` (zypper 1.14.94,
  libzypp 17.37.18) provides no `libzypp(econf)` and ignores drop-ins in `/run` and `/etc`; `ZYPP_LOCK_TIMEOUT` works
  there as above.
- **Proxy**, for NOTES.md only. Observed on both images: lower-case `http_proxy`, `https_proxy` (for https
  repositories), and `all_proxy` are used; upper-case `HTTP_PROXY` is ignored; `/etc/sysconfig/proxy` with
  `PROXY_ENABLED="yes"` is used without any variable. Not verified, and to be labeled so wherever written: that
  `no_proxy` is honored (one run was consistent with it), and the precedence between the environment and
  `/etc/sysconfig/proxy`.
- Not run at all: arm64 (Leap arm64 is in the compatibility list).
- The current installer makes five kinds of `zypper` call (`refresh`; `repos`; `refresh --build-only`; `install`;
  `clean`), each spelling out its flags, and reads `cachedir` for the cached-metadata check from one configuration file.
  Scenario scripts can run the installer themselves and assert failures (`.agents/knowledge/testing.md`, Running the
  installer), which the phase 1 design could not yet rely on.

## Goals / Non-Goals

**Goals:**

- An invocation with every new option at its default makes byte-for-byte the phase 1 `zypper` calls and writes nothing.
  Checked by review of `install.sh` (every new argument, variable, and file sits behind a test of its option) and by the
  existing scenarios and `duplicate.sh`, which run unchanged.
- All syntax is validated before the empty-list exit; everything that needs `zypper`, the RPM database, or the build
  environment's `ZYPP_CONF` is examined only after `require_zypper`, and before the first refresh. Checked by the
  scenarios "Invalid control fails before any change", "Empty list ignores selection and network controls", "Unknown
  alias fails before installation", and "Inherited ZYPP_CONF fails an explicit override", each asserting an empty
  `/var/cache/zypp` and an unchanged package list.
- One numeric rule, identical in shape to the sibling features' `networkTimeout`: digits only, no leading zero, a length
  check before any arithmetic comparison, evaluated under `LC_ALL=C`. Because three of the values are written into a
  configuration file, this check is the boundary against injecting a directive; nothing but validated digits and the
  feature's own fixed key names reaches the file. Checked by the four boundary scenarios, which include a value holding
  a line break and a key, and by review.
- An alias reaches `zypper` only as one quoted argument after `--repo`, never through `eval` or an unquoted expansion,
  and only after it matched the allowlist under `LC_ALL=C` and equaled an enabled alias from zypper's own listing.
  Checked by "Malformed repository alias is refused", "Unknown alias fails before installation", "Disabled repository is
  not enabled", and review.
- Mechanism order of preference: a per-call argument (`exactNames`, `repositories`), then an environment variable set on
  the feature's own `zypper` calls only (`lockTimeout`), then a temporary configuration file (`connectTimeout`,
  `transferTimeout`, `downloadRetries`), used only because no argument or variable exists for those keys. Checked by
  review; "Explicit lock wait overrides an inherited one" checks that the variable is not exported.
- The temporary file is created only when one of its three options is non-empty, never overwrites an existing file,
  holds a `[main]` section with only the overridden keys, has a name that sorts after ordinary drop-in names and is
  unique to the run, and is removed by an EXIT trap together with each directory the feature created, in reverse order
  and only when empty. Checked by the scenarios of "Timeout and retry overrides are temporary" and by "Zypp
  configuration is unchanged", which lists and hashes `/etc/zypp`, `/usr/etc/zypp`, and `/run/zypp` before and after.
- No `zypper` call gains an argument beyond `--name` and `--repo <alias>`: the phase 1 ban list stays in force for
  `--from`, `--plus-content`, `--plus-repo`, `--capability`, `--oldpackage`, `--force`, `--force-resolution`,
  `--no-gpg-checks`, `--gpg-auto-import-keys`, `--allow-unsigned-rpm`, `--auto-agree-with-licenses`, and `--config`.
  Checked by review of `install.sh` against this list.
- The feature sets none of `ZYPP_CONF`, a proxy variable, or `ZYPP_PCK_PRELOAD`. Checked by review and by "Inherited
  ZYPP_CONF is kept without an override".
- `devcontainer-feature.json` gains only the six options and the version; no `dependsOn`, `installsAfter`, or
  capability-widening property. Checked by review and `just spec-check`.

**Non-Goals:**

- Enabling a repository the image disables, adding repositories or services, per-entry repository prefixes, downgrades,
  vendor changes, license agreement, forced resolution, verification overrides, and offline installation (issue #59, Out
  of scope; phase 3 is #63).
- A parallel-download, download-speed, or proxy option; a pass-through of arguments, settings, or environment; an option
  naming a configuration file.
- Making `downloadRetries` cover package downloads, or repeating a failed `zypper` call in the feature.
- Changing the compatibility list, the phase 1 options, or the cached-metadata lookup of `refreshPolicy=never` beyond
  restricting it to the selection.

## Decisions

- **`repositories` restricts the whole invocation with `--repo`.** Refresh, the cached-metadata check, the parsed-cache
  build, and the install all take the selected aliases, so an unselected repository is neither contacted nor needed;
  this is the only shape in which a build stops depending on a repository it does not use. Rejected: `--from`, which
  restricts only the listed packages and is soft in practice (observed: `--from repo-non-oss -- bc` falls back to
  capabilities and installs `bc` from `repo-oss`; a disabled alias is only warned about; `--from 1` is read as a
  repository number), so it would need a forced `--name` and still a full refresh; a per-entry `REPOSITORY:NAME` prefix,
  equally soft and ambiguous with Leap's aliases that contain `:`; restricting the install but refreshing everything,
  which keeps the build hostage to repositories it excluded. The cost, upstream's "discouraged" note, is stated as an
  accepted risk in the requirement (Open question 1).
- **The feature checks the aliases itself, against enabled repositories only.** zypper's own answers differ by command
  (exit 3 on install, a warning and exit 0 on `refresh <disabled alias>`) and it also matches names, numbers, and URIs.
  One exact comparison with the enabled aliases of `zypper --xmlout --non-interactive --no-refresh repos`, the listing
  the installer already parses for `refreshPolicy=never`, gives one failure, status 1 naming the alias, before anything
  is downloaded. Rejected: relying on zypper's errors; accepting names or numbers.
- **Alias syntax `[A-Za-z0-9][A-Za-z0-9._:+-]*`, not all digits.** It admits the aliases of both images, Leap's service
  prefix with its `:` included, and refuses `/` (URIs, paths), whitespace, globs, `=`, a leading `-`, and repository
  numbers. Rejected: accepting whatever zypper accepts, which makes a number or a URL a valid selection.
- **`cleanup` is not narrowed by the selection.** `clean` keeps its phase 1 arguments: the cache state after the feature
  does not depend on which repositories were in use. Rejected: `clean --repo`, a second meaning for `cleanup=all`.
- **`exactNames` is a plain boolean adding `--name` to the install call.** `false` adds no argument and is exactly phase
  1; zypper has no third, inherited state for this. Phase 1 rejected a hard-wired `--name` to keep zypper's provider
  matching as the default; an opt-in keeps that decision. Rejected: a tri-state; making it the default (a MAJOR change);
  checking names with `zypper search` first.
- **`lockTimeout` is `ZYPP_LOCK_TIMEOUT` on the feature's own calls, bounded 1..3600.** The variable is documented,
  needs no file, and beats the image's `lock_timeout`. It is set per call, not exported, so nothing after the feature
  sees it. `0` is refused although libzypp reads it as "do not wait": it equals libzypp's default, and an empty option
  already says "do not override" (Open question 6). Negative values, which wait forever, and values libzypp would
  truncate (`4x`) are refused. Rejected: writing `lock_timeout` into the temporary file, a weaker mechanism than the
  variable that would also lose against an inherited `ZYPP_LOCK_TIMEOUT`; a wait-forever value, an unbounded build hang.
- **Two timeouts, no `networkTimeout`.** libzypp has two keys with different meanings and the issue's outcome names
  both; a third option aliasing one or both would have no native counterpart. `transferTimeout` is specified as what
  libzypp implements, an inactivity limit, and not as the manual's wording ("maximum time … a transfer operation"),
  because the source and the stalled-server runs agree on inactivity. Both are bounded 1..3600: `0` reaches libcurl as
  "library default" or disarms the activity timer (source, not run), and libzypp silently clamps above 3600.
- **`downloadRetries` counts retries, mapped to `download.max_silent_tries = N + 1`, bounded 0..10.** The name and
  counting are the family's (the `apt-packages` change of the same epic proposes the same option). The mapping makes
  libzypp's retry-forever value `0` unreachable by construction. The option ships although it governs metadata requests
  only on this libzypp, because the issue's outcome names bounded attempts and the requirement states the scope as an
  accepted limitation (Open question 3). Rejected: `downloadAttempts` counting tries, a second vocabulary inside one
  family; `ZYPP_PCK_PRELOAD=0` to route package downloads through the retrying path, a switch that exists in source only
  and changes how packages are downloaded; a retry loop around `zypper` in the feature.
- **Timeouts and retries travel in one temporary drop-in under `/run/zypp/zypp.conf.d`.** libzypp merges it natively
  after the image's files, so the image's signature, solver, and `rpm.install.excludedocs` settings stay in force and no
  existing file is touched. `/run` is where the source and the specification the manual page refers to put ephemeral
  overrides, and it lies outside the image's configuration directories; the manual page itself does not name it (Open
  question 4). The directories do not exist on the supported images, so the feature creates and removes them. Rejected:
  - `ZYPP_CONF` pointing at a file with only the overrides: libzypp then reads solely that file, and the image's
    settings, trust settings among them, are dropped (observed).
  - Emulating libzypp's merge in shell to build a complete `ZYPP_CONF` file: three directories, masking by name, and
    bytewise ordering would have to be reproduced exactly, and an error silently changes trust settings.
  - Editing `/etc/zypp/zypp.conf` and restoring it: edits an image file, and Tumbleweed has none to edit.
  - `zypper --config` or `zypper.conf`: they hold no network, lock, or repository key.
- **A non-empty option that cannot be honored fails.** With an inherited `ZYPP_CONF`, libzypp ignores every drop-in; on
  a libzypp without `libzypp(econf)` likewise. A control that silently does nothing is a false control, so both cases
  exit 1 naming the option, and only when one of the three options is non-empty, which keeps "unset is phase 1" intact.
  Support is probed through the RPM capability `libzypp(econf)`, the one marker verified on both supported images and
  absent on the libzypp that ignores drop-ins. Rejected: building a single file from the inherited `ZYPP_CONF` file plus
  appended overrides, exact for that case but a second configuration path that no supported image exercises (Open
  question 5); comparing libzypp version numbers, since the version that introduced drop-ins was not verified; ignoring
  the option with a warning.
- **No check that the override took effect.** A later-sorting image drop-in that sets the same key wins (observed). The
  feature's file name sorts late and is unique, which covers ordinary names and rules out masking by a same-named file,
  and the remaining case is an accepted risk in the requirement. Rejected: parsing the image's drop-ins to detect it,
  the merge emulation rejected above.
- **Pre-existing defects stay out.** The cached-metadata check reads `cachedir` from one file, ignoring drop-ins,
  `/usr/etc`, and section headers; fixing it changes behavior with no new option set, which the epic's bar excludes from
  this phase (Follow-up work).

### Phase 2 options

The delta spec's Option requirements are the source of truth; where this table differs, the delta spec wins. None of the
six gets `proposals`: aliases differ per image (Leap's carry the service prefix), and the devcontainer CLI's
install-twice test installs a string option's proposal on every image, so a proposed alias or number would silently
become part of the autogenerated test.

| Name              | Type      | Default | Enum or proposals | Meaning                                                                                                              |
| ----------------- | --------- | ------- | ----------------- | -------------------------------------------------------------------------------------------------------------------- |
| `exactNames`      | `boolean` | `false` | none              | `true` matches entries by package name only, without the fallback to a package providing the name as a capability.   |
| `repositories`    | `string`  | `""`    | none              | Comma-separated aliases of enabled repositories; non-empty restricts refresh, cache check, and installation to them. |
| `lockTimeout`     | `string`  | `""`    | none              | Empty inherits; otherwise 1..3600 seconds each `zypper` call waits for libzypp's lock.                               |
| `connectTimeout`  | `string`  | `""`    | none              | Empty inherits; otherwise 1..3600 seconds for the connection phase of each download.                                 |
| `transferTimeout` | `string`  | `""`    | none              | Empty inherits; otherwise 1..3600 seconds without received data before a transfer is aborted.                        |
| `downloadRetries` | `string`  | `""`    | none              | Empty inherits; otherwise 0..10 retries of a repository metadata request after its first attempt.                    |

Reasons for the defaults: `false` adds no argument, and each empty string passes nothing, so every default is the phase
1 behavior and inherits what the image configures. An empty string, not a number, is the default of the numeric options
because the image's value is unknown to the feature and may differ from libzypp's builtin one.

Rejected option shapes: numbers as a non-string type (features have only `boolean` and `string`); an `enum` of preset
timeouts; a tri-state `exactNames`; one `networkTimeout` for both keys; `downloadAttempts`; `repositories` as a single
alias or with glob support; a per-entry repository syntax inside `packages`; `enableRepositories` through
`--plus-content` (the name stays reserved, Open question 2); `parallelDownloads` through
`download.max_concurrent_connections`, a verified key that issue #59's outcome does not list (Open question 8);
`extraArgs`, `setopt`, an environment dictionary, a proxy option, and an option naming a configuration file, as in phase
1.

Descriptions in `devcontainer-feature.json` follow the phase 1 sentence pattern of the sibling features ("…, or empty to
inherit image settings; applies only to this invocation.").

### Documentation bounds

NOTES.md gains one section on configuration with the four headings the five package features share: "What the feature
sets explicitly", "What is inherited", "Proxy", and "Locks and retries". It carries the upstream facts the spec leaves
out: `zypp.conf` versus `zypper.conf`; that an inherited `ZYPP_CONF` replaces libzypp's whole configuration and makes
the timeout and retry options fail; the lookup and drop-in order, and that a later-sorting image drop-in wins; the
no-wait default of the lock and the coarse wait; zypper's fixed retries on commands the feature does not run; that
`transferTimeout` is an inactivity limit; the proxy spellings from Context, with the two unverified points labeled as
not verified; that aliases are image-specific and are written as `zypper lr` shows them; that dependencies must be
inside the selection; that `cleanup=all` still cleans every repository; and that `exactNames=true` refuses capability
names such as `awk`.

### Verification bounds

Every scenario the delta adds is checked on both amd64 images of the compatibility list, since scenario jobs run on
amd64; arm64 keeps the autogenerated and install-twice tests. Checks that must observe a failure, a second run, or a
prepared container run the installer from the scenario script.

| Scenarios                                                                    | Checked by                                                                                                                                                                          |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| The six "Omitted …" scenarios; "Undeclared settings are inherited"           | The existing scenarios, `test.sh`, and `duplicate.sh`, unchanged, plus a `zypper` stub on `PATH` that records arguments and environment for a default run                           |
| Validation scenarios, the boundary scenarios, "Malformed repository alias …" | Installer runs with an empty and a non-empty list, asserting status 1, the named option, an empty cache, and no file under `/run/zypp`                                              |
| Selection scenarios                                                          | Installer runs with the image's own aliases read at run time; an added enabled repository at an unreachable address stands for the one that cannot be refreshed                     |
| "Dependency outside the selection fails"                                     | Tumbleweed, with a package of one enabled repository whose dependency is only in another; on Leap, a local fixture repository when no such pair exists                              |
| "Conflict with a package of an unselected repository fails"                  | A local fixture repository with a package that conflicts with one installed from the image's repository                                                                             |
| Exact-name scenarios                                                         | Installer runs with `awk` and `gawk`, and with editions read at run time                                                                                                            |
| Lock scenarios                                                               | A background process in the script holds libzypp's lock for a fixed time; elapsed time is asserted with a lower bound only                                                          |
| Connect and transfer timeout scenarios, retry scenarios                      | Fixtures inside the container: an unroutable address or a listener that accepts and stalls, and a local server counting requests; never a public mirror being slow                  |
| "Active transfer outlasts the transfer timeout"                              | A local server that sends a file slowly for longer than the value                                                                                                                   |
| Override file scenarios; "Zypp configuration is unchanged"                   | A `zypper` stub that copies the feature's file while it exists; listings and hashes of the configuration directories before and after a succeeding and a failing run                |
| "Inherited ZYPP_CONF …" scenarios                                            | Installer runs with `ZYPP_CONF` set in the script                                                                                                                                   |
| "Libzypp without additional configuration files fails an explicit override"  | A `build` scenario on a pinned image outside the compatibility list whose libzypp lacks `libzypp(econf)`, or, if none can be pinned, an `rpm` stub on `PATH` that hides the provide |
| "Proxy configuration is inherited"                                           | A run with `http_proxy` pointing at a closed loopback port fails at the refresh, with and without the new options                                                                   |
| Install-twice scenarios                                                      | Two installer runs in one container with different option values                                                                                                                    |

An unroutable address gave clean connect timeouts in the environment these facts were gathered in; another network may
answer differently, so a timing assertion uses generous bounds and the fixture that is local wherever one exists.

## Risks / Trade-offs

- [`--repo` hides unselected repositories from the resolver; upstream says packages installed from them can be removed
  when a dependency conflict involves them, and one fixture run showed a refusal instead] → Stated as an accepted risk
  in "Repository selection restricts the installation"; the conflict scenario pins the observed behavior, and the
  feature still passes no option that lets zypper pick a removing solution.
- [Upstream announces that `--repo` will become an alias of `--from`, which would let dependencies come from unselected
  repositories] → "Dependency outside the selection fails" turns red when that lands, instead of the contract changing
  silently.
- [`downloadRetries` does not repeat package downloads on this libzypp] → Scoped in the requirement and in NOTES.md;
  "Package download is not repeated" records the present behavior, so a libzypp that starts honoring the key there shows
  up as a failing check to re-specify, not as a silent change.
- [An image drop-in sorting after the feature's file overrides an option] → Accepted risk in "Timeout and retry
  overrides are temporary"; NOTES.md names it.
- [A build killed without running the EXIT trap leaves the file in `/run/zypp/zypp.conf.d`] → A failed build step
  discards its layer; the file holds only timeouts and attempts, never a trust setting.
- [A later-added image whose libzypp lacks drop-in support makes three options fail there] → That is the specified
  behavior; adding such an image is a change of its own that decides between failing and a second mechanism.
- [Aliases are image-specific, so one `repositories` value does not port between Leap and Tumbleweed] → Inherent to
  selecting among what an image provides; NOTES.md says to copy the alias from `zypper lr`.
- [The alias check runs `zypper repos`, which on Leap refreshes the local repository index service] → The same call
  phase 1 makes under `refreshPolicy=never`, and the spec already excludes that rewrite from the feature's changes.
- [Lock and timeout checks depend on timing] → Lower bounds only, with values of a few seconds.
- [arm64 was not run for any new path] → CI covers Leap arm64 with the autogenerated and install-twice tests only, as in
  phase 1; no new path is architecture-specific.

## Open Questions

For the maintainer at the package gate. Each has a recommended answer, which the package already follows.

1. **Meaning of `repositories`.** The whole invocation restricted with `--repo`, dependencies inside the selection
   (written), or "listed packages from the selection, dependencies from anywhere" (`--from` with a forced `--name`)?
   Upstream discourages `--repo` and announces it will become an alias of `--from`.
2. **Disabled repositories.** Is temporarily enabling a repository the image defines but disables (`--plus-content`)
   inside the epic's "sources the image already provides"? It works on both images, but an unknown tag exits 0 after
   downloading the metadata of every disabled repository, and it changes the Purpose. Written: not in this change; the
   name `enableRepositories` stays reserved.
3. **Ship `downloadRetries`?** It governs metadata requests only. Written: shipped with the scope in the requirement,
   named and counted as in the family (retries, `N + 1` tries), not `downloadAttempts`.
4. **Drop-in location.** `/run/zypp/zypp.conf.d` (ephemeral by source and the specification the manual refers to, not
   named in the manual page; written) or `/etc/zypp/zypp.conf.d` (documented, inside the image's configuration directory
   for the duration of the call)? The spec does not name the directory, so either satisfies it.
5. **Inherited `ZYPP_CONF` with a non-empty timeout or retry option.** Fail (written), or build a temporary single file
   from that file plus the overrides?
6. **`lockTimeout` range.** 1..3600 only (written), or also `0` as an explicit "do not wait" that overrides an image
   setting, or a wait-forever value?
7. **Bounds.** 1..3600 for `connectTimeout` and `transferTimeout`, and 0..10 for `downloadRetries`.
8. **`parallelDownloads`.** The key `download.max_concurrent_connections` is verified (a drop-in value of 2 gives
   "Downloading packages via 2 connections."), but issue #59 does not list it. Written: not declared.
9. **Accepted risk of the selection.** Is the statement in "Repository selection restricts the installation" enough,
   given that upstream documents possible removal of packages from hidden repositories and only one conflict case and
   one plain install were run? The alternative is to hold `repositories` back until more cases are run.
10. **Pre-existing items.** The cached-metadata lookup defect as a separate issue (written), and whether restoring
    Tumbleweed arm64 (`TODO(#43)` in `test/zypper-packages/test.sh`; the phase 1 design asks to re-verify it on the next
    feature change) belongs to this change. Written: neither; the compatibility list is unchanged.

## Follow-up work

- A fix issue for the cached-metadata check of `refreshPolicy=never`, which reads `cachedir` and `metadatadir` only from
  `${ZYPP_CONF-/etc/zypp/zypp.conf}` and so misses drop-ins, `/usr/etc/zypp`, and section headers. Suggested, not
  opened: this change makes no GitHub write.
- Phase 3, downgrade and conflict-replacement policy, is tracked in
  [#63](https://github.com/hoshiori-dev/devcontainer-features/issues/63).
