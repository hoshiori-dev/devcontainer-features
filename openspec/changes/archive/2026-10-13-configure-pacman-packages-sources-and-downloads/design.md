# Design

## Context

Version 1.0.1 validates `cleanup` and every entry, exits 0 on an empty list before it looks for `pacman`, makes one call
`pacman --sync --refresh --sysupgrade --needed --noconfirm -- <entries>`, and then cleans the two default cache
directories. It creates no file, sets no trap, and refuses every entry holding `/`. The baseline design
(`../archive/2026-10-05-add-pacman-packages-feature/design.md`) bound that call to carry no `--config`, `--cachedir`, or
`--dbpath`, and the phase 1 design (`../archive/2026-10-05-configure-pacman-packages-cleanup/design.md`) left download
configuration and path resolution to phase 2.

Epic #127 asks five package-manager features for phase 2 controls, and nothing on `main` records conventions they share.
The conventions this design applies are therefore its own decisions, each stated with its reason under Decisions and
Options: options are strings or booleans; an empty string passes nothing, so the image's setting applies; a numeric
value is a canonical decimal integer checked before any package-manager call; a control the manager cannot honor is not
declared; an explicit value that cannot be honored at run time fails instead of being ignored; a per-invocation argument
is preferred over an environment variable, and that over a temporary configuration file; nothing persists. The name
`parallelDownloads` and the range 1 to 20 are also what the sibling change for `dnf-packages` proposes on its own
branch; that is a reason for the maintainer to weigh, not a rule this design can cite.

### Upstream facts

From pacman(8) (https://man.archlinux.org/man/pacman.8), pacman.conf(5) (https://man.archlinux.org/man/pacman.conf.5),
and the pacman source at tag v7.1.0 (https://gitlab.archlinux.org/pacman/pacman):

- pacman(8), `-S`: "the repository can be explicitly specified to clarify the package to install: `-S testing/qt`", and
  version requirements may be given. `src/pacman/sync.c` (`process_target`) splits a sync target at its first `/`, looks
  the left part up among the configured databases, and fails with "database not found" when there is none; its comment
  says a named repository is marked valid for installs because the name was given with the target, and after resolving
  that one target it restores the repository's usage "so we don't possibly disturb later targets". `Usage` therefore
  does not restrict the named target, and still restricts its dependencies and every other target.
- `lib/libalpm/sync.c` (`alpm_sync_sysupgrade`) skips an installed package that is "already in the target list", and for
  every other one consults the first repository in the configured order that holds the name and is enabled for upgrades.
  A package the transaction installs for a listed entry is thus exempt from that transaction's upgrade, and a listed
  entry that `--needed` skipped is not. pacman(8), `-u`: only passing the option twice enables downgrades in the system
  upgrade.
- pacman(8): `--config <file>` names an alternate configuration file. pacman.conf(5): `Include` reads another
  configuration file, which "can include repositories or general configuration options"; `ParallelDownloads` "specifies
  number of concurrent download streams", "needs to be a positive integer", and without it "only one download stream is
  used". `pacman -S --help` lists no argument for it.
- `src/pacman/conf.c` (`_parse_options`) assigns `ParallelDownloads` on every occurrence, so the last one read wins. It
  parses the number with `strtol`, refuses a value below 1 and one above `INT_MAX`, and accepts `03`, `+3`, and a 3 with
  a leading space as 3 (each confirmed with `pacman-conf`).
- `lib/libalpm/handle.c` takes the database lock with one exclusive create and no wait. `lib/libalpm/dload.c` has no
  retry count; on a failed transfer it moves to the repository's next `Server`. It sets a connect timeout of 10 seconds
  and aborts a transfer below 1 byte per second for 10 seconds; `--disable-download-timeout` lifts only the second, and
  no numeric timeout setting exists. pacman's own code reads no proxy variable; its downloader is libcurl, which reads
  the proxy variables (https://curl.se/libcurl/c/libcurl-env.html).
- `ParallelDownloads` exists since pacman 6.0.0 (NEWS of v7.1.0); the download user and the sandbox since 7.0.0.

### Experiments

Run on 2026-10-09 in `archlinux:latest` (digest
`sha256:4e77cf2ea5f410e6f8be5abf93ccf17ce2436e87a138c167208356711a405dbd`, `VERSION_ID=20261004.0.606936`, pacman 7.1.0,
libalpm 16.0.1, curl 8.22.0), the only image and the only pacman generation of the compatibility list. Its
`/etc/pacman.conf` sets `ParallelDownloads = 5`, `DownloadUser = alpm`, `DisableSandboxFilesystem`,
`SigLevel = Required DatabaseOptional`, and `[core]` and `[extra]` through the mirror list; `CacheDir` and `DBPath` are
defaults.

- Qualified targets, resolved with `pacman -S -p --print-format "%r/%n %v" --needed --noconfirm -- <entry>` after a
  refresh: `extra/bc` gives `extra/bc 1.08.2-1`; `core/bc` gives "target not found: bc"; `nosuchrepo/bc`, `local/bc`,
  and `EXTRA/bc` give "database not found"; `extra/bc>=1.0` resolves and `extra/bc<1.0` does not; `extra/cron` (a
  provided name) gives `cronie`; `extra/archlinux-tools` gives the group's members; `extra/bc/x` gives "target not
  found: bc/x"; `https://example.com/x.pkg.tar.zst` gives "database not found: https:" and `./bc` gives "database not
  found: .", so `-S` reads neither as a file or URL.
- Real runs of the feature's call: with `tree nosuchrepo/bc` and with `tree core/bc` the status is 1 and `tree` is not
  installed, after the databases were refreshed, as for an unknown name in phase 1.
- A fixture configuration with `file://` repositories holding real package files and `SigLevel = Never`: `newer` (fx-c
  9.0-1) before `older` (fx-c 1.0-1), and `nouse` with `Usage = Sync Search` (fx-b; fx-a, which depends on fx-dep;
  fx-dep). The feature's call `--sync --refresh --sysupgrade --needed --noconfirm -- older/fx-c`, run four times, all
  with status 0: the first installs 1.0-1 although `newer` offers 9.0-1; the second reports "up to date -- skipping" and
  upgrades to 9.0-1; the third prints "downgrading package fx-c (9.0-1 => 1.0-1)" and installs 1.0-1; the fourth
  upgrades again. The unqualified `fx-c<5` alternates the same way, which version 1.0.1 already does. `newer/fx-c` with
  9.0-1 installed changes nothing.
- `Usage` in the same fixture: the unqualified `fx-b` gives "target not found" and `nouse/fx-b` installs it, status 0.
  `nouse/fx-a` fails with "unable to satisfy dependency 'fx-dep' required by fx-a"; `nouse/fx-b fx-dep` and
  `fx-dep nouse/fx-b` both fail with "target not found: fx-dep"; `nouse/fx-a nouse/fx-dep` resolves both. A repository
  with `Usage = Search` gets no database on refresh, so a target qualified with it gives "target not found".
- Dependencies of a qualified target: `extra/archlinux-tools` on the plain image resolves 13 packages from `extra` and 2
  from `core`.
- Wrapper configuration (`[options]`, `Include = /etc/pacman.conf`, `[options]`, `ParallelDownloads = 3`):
  `pacman-conf --config <file> ParallelDownloads` prints 3; with the override before the `Include` it prints 5. The
  whole `pacman-conf --config <file>` dump equals the plain `pacman-conf` dump except the `ParallelDownloads` line, and
  `--repo-list` prints `core` and `extra`. The image's `/etc/pacman.conf` ends in an `[options]` section (its
  `NoExtract` lines follow `[extra]`), so on this image the value is also 3 without the second `[options]` header.
  Including the fixture configuration, which ends in a repository section, shows the need: without the second header
  `pacman-conf` warns "directive 'ParallelDownloads' in section 'nouse' not recognized" and prints 5, status 0; with it
  the value is 3 and `--repo-list` prints the fixture's repositories.
- With `--debug`, the run under the wrapper shows the `alpm` download user and the syscall filter in effect, completions
  in queue order with 1 and interleaved with 4. A full run with a wrapper from `mktemp` (mode 0600, root) exits 0 and
  leaves `/etc/pacman.conf` and every file under `/etc/pacman.d` with unchanged hashes. An `Include` of a missing file
  fails both `pacman-conf` and `pacman` with "config file ... could not be read", status 1, nothing installed.
  `/var/log/pacman.log` records the call with `--config <path>`.
- Outside the supported images, `archlinux:base-20210131.0.14634` (pacman 5.2.2, before `ParallelDownloads` existed)
  with the same wrapper: `pacman-conf --config <file> ParallelDownloads` warns "unknown directive" and exits 1, while
  `pacman --config <file>` only prints the warning and goes on with the override ignored. On such a `pacman` the
  confirmation is the only thing that fails closed.
- `--config /dev/stdin` with a here-document also works and ties `pacman`'s standard input to the configuration text.
- Lock: with an existing `/var/lib/pacman/db.lck` the call fails within milliseconds with "unable to lock database",
  status 1; a killed `pacman` leaves the lock file behind.
- Servers: with a first `Server` that refuses the connection, `pacman` reports it and completes from the next, status 0.
- Proxy: `https_proxy`, `HTTPS_PROXY`, and `ALL_PROXY` pointing at a closed port each made the download fail through the
  proxy, and `no_proxy` for the mirror's domain bypassed it. Precedence among these variables is libcurl's and was not
  tested.

Not verified: any pacman other than 7.1.0 and the 5.2.2 observation above; a character set for repository section names,
which pacman.conf(5) does not define; a configuration path other than `/etc/pacman.conf` on a derivative.

## Goals / Non-Goals

**Goals:**

- With `parallelDownloads` empty and no qualified entry, the script reaches the phase 1 call with the same argument
  vector and creates nothing. Checked by a direct check that records the arguments `pacman` receives and lists the
  temporary directory before and after, and by the unchanged phase 1 scenarios and `duplicate.sh`.
- An accepted entry still reaches `pacman` as one quoted argument after `--`, qualified or not. Checked by review of
  `install.sh` and the existing injection check, extended with a qualified entry.
- The repository part and `parallelDownloads` are matched under `LC_ALL=C` against character sets spelled out in the
  script, with a length test before any arithmetic comparison of the number. Checked by shellcheck, review, and the
  refusal checks, including a non-ASCII letter, a line break, and an over-long digit string.
- The temporary configuration has exactly the shape tested above: an `[options]` header, the `Include` of
  `/etc/pacman.conf`, a second `[options]` header, and the `ParallelDownloads` line, in that order and nothing else. The
  second header is needed whenever the included configuration ends in a repository section, as the stock upstream layout
  does; the supported image's happens to end in `[options]`, so it cannot show the need. The override comes last because
  the last assignment wins. Checked by comparing the `pacman-conf --config <file>` dump with the plain dump, where only
  the `ParallelDownloads` line may differ, on the plain image and on a container whose `/etc/pacman.conf` was made to
  end in a repository section.
- The file is created with `mktemp` under the default temporary directory, never under `/etc`, readable by root only,
  and removed by a trap on exit and on the signals the shell lets the script catch. Checked by listing the temporary
  directory after a successful run, after a run failing in `pacman`, and after a run failing the confirmation below.
- An explicit value is confirmed before the transaction: `pacman-conf --config <file> ParallelDownloads` must print the
  requested value, and anything else, a failing or missing `pacman-conf` included, ends the run with status 1 naming the
  option. Checked by the direct checks for "Image configuration that cannot be included fails closed", "Unconfirmed
  value fails closed" (with `pacman-conf` hidden or replaced by one that prints another value), and "Explicit parallel
  downloads reach pacman", which use the same command to observe the value.
- No temporary file exists and neither `pacman` nor `pacman-conf` has run before every option and entry is validated and
  the list is known to be non-empty; the confirmation precedes the one `pacman` call. A valid `parallelDownloads` with
  an empty list therefore creates nothing and needs no `pacman`. Checked by the refusal and empty-list checks on an
  image without `pacman`.
- The feature still runs `pacman` once per installation, adds no option to that call besides `--config`, exports no
  variable, runs no `pacman-key`, and writes nothing under `/etc`. Checked by review against this bound and by the hash
  comparison of "Pacman configuration is unchanged".
- POSIX `sh` with `set -eu` and the shared skeleton stay. Checked by shellcheck and by the busybox `sh` runs of the
  validation and empty-list paths.

**Non-Goals:**

- Retries, lock waiting, numeric timeouts, a proxy option, `XferCommand`, or any pass-through of arguments, settings, or
  environment variables.
- Custom `CacheDir` or `DBPath` handling; cleanup keeps the two default directories.
- Enabling, adding, or reordering repositories; historical versions; pinning; any downgrade or conflict policy (phase
  3).
- A change to the compatibility list, the test infrastructure, or the dev container configuration.

## Decisions

- **The repository qualifier is entry grammar, not an option.** `pacman` selects a repository per target, and has no
  global switch like the other managers' repository arguments. Passing `repository/target` through keeps the baseline
  decision "Native behavior first": one call, no second resolution. Rejected: a `repositories` option applied to every
  entry, which `pacman` cannot express in one call; rewriting unqualified entries; resolving entries with `pacman -Sp`
  before the call to guard against `Usage` or an older version, which is a second code path that must agree with
  `pacman`'s own.
- **Validate the qualifier in the script, leave existence to `pacman`.** The repository part matches
  `[A-Za-z0-9][A-Za-z0-9._+-]*`, an identifier rule that covers the characters all official repository names use
  (`core`, `extra`, `multilib`, the `-testing` and `-unstable` ones). It leaves out `:`, `@`, `<`, `>`, and `=`, so a
  URL scheme or a constraint cannot sit left of the slash. An unknown repository fails in `pacman` with "database not
  found" before any package changes, which the native tool guarantees uniformly, so the feature adds no lookup of its
  own. Rejected: asking `pacman-conf --repo-list` first, a second path for an outcome `pacman` already gives; accepting
  any section name pacman.conf would take, which upstream does not define.
- **Two refusal messages for entries holding `/`.** An entry that starts with `/` or `.`, holds `://`, or holds more
  than one `/` is reported as a path or URL; any other refused entry with a `/` as a malformed qualifier. The phase 1
  guarantee that paths and URLs are refused before `pacman` runs stays for every form a developer would plausibly write,
  and the message tells a developer who mistyped a qualifier what form is accepted. A single-slash relative path without
  a leading `.` is indistinguishable from a qualified target and is left to `pacman`, which never opens a sync target as
  a file (Experiments); the spec states this. Rejected: refusing targets that end in a package file suffix, which
  guesses at intent and would refuse nothing `pacman` could install from.
- **`parallelDownloads` through a temporary wrapper configuration.** `pacman` has no argument and no environment
  variable for the setting, so the last of the three mechanisms in Context applies. This deliberately lifts the baseline
  bound "no `--config`" for this one key and for a non-empty value only; `--cachedir`, `--dbpath`, and every other
  excluded argument stay excluded. The wrapper includes the image's configuration instead of copying it, so
  repositories, `SigLevel`, `DownloadUser`, the sandbox settings, and the image's own `Include` lines are whatever the
  image has at that moment. Rejected: `--config /dev/stdin`, which writes no file but consumes the standard input of the
  one command that must run without input, and whose behavior with a here-document under every POSIX shell is one more
  thing to verify; editing `/etc/pacman.conf` and restoring it, which changes an image file and can leave it changed
  when the build is killed; copying the configuration with the line rewritten, which duplicates repository and trust
  settings into a file the feature would then own; not offering the option, which leaves the issue's download control
  out although the manager supports it.
- **Confirm the value with `pacman-conf` before the transaction.** A developer who sets a value must not get the image's
  instead without being told. One read-only command covers a missing or unreadable `/etc/pacman.conf`, a `pacman` that
  does not know the key (it only warns and continues, Experiments), and any future reason the override would not win,
  and it is the same command the tests use to observe the value. `pacman-conf` ships in the `pacman` package. The spec
  names the causes by their effect on the confirmation; the unknown-key cause cannot be prepared on an image of the
  compatibility list and is covered by review of the comparison, not by a scenario. Rejected: relying on `pacman`'s own
  failure for the missing file alone, which covers one of the cases; parsing `/etc/pacman.conf` in the script.
- **Range 1 to 20.** `pacman` accepts any positive integer up to `INT_MAX`. The bound is kept small because `pacman` has
  no retry to absorb a mirror that limits simultaneous connections; 20 is four times the image's 5 and equals the range
  the sibling `dnf-packages` change proposes for the same option name (Open question 4). The digits-only rule matters
  more than the range: the value is written into a configuration file, so a line break or `[` in it would add
  directives. `0` is refused because `pacman` refuses it, and the forms `pacman` would quietly accept (`03`, `+3`, a
  value with leading whitespace) are refused so that one value has one spelling.
- **Unsupported controls are stated, not emulated.** A wait loop around the lock, deleting a stale lock, or a retry loop
  around the whole transaction would be behavior outside `pacman`, and a retried `-Syu` is not the same transaction. The
  spec's requirement "Unsupported download controls stay native" states what the feature does not do; what `pacman` does
  instead (Upstream facts) goes to NOTES.md. Rejected: a boolean for `--disable-download-timeout`, which issue #60 does
  not name, works one way only (it cannot restore the timeout an image disabled), and is not a bounded control.
- **Cleanup stays bound to the default directories.** Following `pacman-conf CacheDir` and `DBPath` would change what
  `cleanup=all` deletes on an image with custom paths while no new option is set, which the epic forbids in this phase,
  and no custom-path option is proposed that would need it (Open question 1).
- **The downgrade wording is corrected in this change.** The main spec's "The feature SHALL NOT downgrade any installed
  package" was already untrue in version 1.0.1 for an unqualified entry whose constraint only an older offered version
  satisfies (Experiments), but only the qualifier makes that case easy to reach, and a delta that admits the qualifier
  while the merged requirement denies its effect contradicts itself. The requirement "Full system upgrade" is therefore
  MODIFIED: the bound is on the system upgrade and on the arguments the feature passes, and a package installed for a
  listed entry is the stated exception, with the risk and its reason. No behavior of version 1.0.1 changes by this
  wording. Rejected: leaving the wording for a separate fix, which would approve a contradiction; a guard that refuses a
  qualified entry whose repository offers an older version than the installed one, which needs the databases refreshed
  and the target resolved before the transaction, so a second `pacman` call and a resolution that must agree with
  `pacman`'s own, and which would leave the unqualified constraint case behaving differently (Open question 2).
- **Alternating versions on repeated installation are stated, not prevented.** With the same qualified entry and a newer
  version in an earlier repository, the installed version alternates from one installation to the next (Experiments).
  Preventing it needs either the guard above or state kept between installations; the requirement "Installing the
  feature twice" states it instead. It cannot occur on the images of the compatibility list.

### Options

| Name                | Type     | Default | Enum or proposals                            | Meaning                                                                                                                                                                          |
| ------------------- | -------- | ------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `packages`          | `string` | `""`    | proposals `"bc"` and `"bc,tree"` (unchanged) | Unchanged in name, type, default, and proposals. An entry may now also be `repository/target`, which `pacman` resolves only in that configured repository.                       |
| `parallelDownloads` | `string` | `""`    | proposals `"1"`, `"3"`, `"10"`               | Upper bound of simultaneous downloads for this installation's `pacman` call, 1 to 20; empty inherits the image's setting. Applies to this invocation only and is stored nowhere. |

- **Default `""` for `parallelDownloads`.** The image sets 5 and another image may set anything or nothing; any fixed
  number would change what version 1.0.1 does. Empty adds nothing to the call, which is exactly phase 1.
- **Proposals `"1"`, `"3"`, `"10"`.** The devcontainer CLI's install-twice test takes the second proposal of a string
  option whose default is not among them, so `duplicate.sh` runs the wrapper path with a value that differs from the
  image's 5 and can be told apart from it.
- **`packages` proposals stay.** A qualified proposal would tie the generated test input to a repository name.
- **Description** follows the phase 1 sentence pattern: the meaning and range, "or empty to inherit image settings;
  applies only to this invocation."
- **Rejected shapes:** a number or an array (options are only `string` or `boolean`); a default of `"5"`, which hard
  codes one image's value; an enum of a few counts, which cannot hold "inherit" without a word that is not a number; an
  upper bound of 999 as the research first suggested, against the range decision above; a separate `repository` option
  (first decision); `downloadRetries`, `lockTimeout`, `networkTimeout`, `connectTimeout`, and `transferTimeout`, which
  sibling features declare and `pacman` cannot honor; options for `CacheDir`, `DBPath`, a proxy, or extra arguments.

### Documentation bounds

NOTES.md gains one section with the four headings the five features share: "What the feature sets explicitly" (the one
`--config` wrapper and its one override, only for a non-empty `parallelDownloads`), "What is inherited" (the whole
`pacman.conf`, including its repositories and their order), "Proxy" (the libcurl variables observed to take effect, with
their precedence labeled as not verified), and "Locks and retries" (no waiting, a stale `db.lck` fails at once; no
retries beyond the next server; the fixed 10-second timeouts; these upstream facts live in NOTES.md and in this design,
not in the spec, which states only what the feature does not do). It also explains the qualifier with its three native
properties, including the alternation on repeated installation and that `Usage` is lifted for the named target only,
replaces "Nothing is ever downgraded" and "the feature never downgrades" with the bound of the requirement "Full system
upgrade", says that an unqualified constraint already selects among repositories, mentions the path left in
`pacman.log`, and replaces the two sentences that say every entry holding `/` is refused and that the feature adds no
pacman configuration of its own. No fact from the "Not verified" list above is written as a fact.

### Verification bounds

The plain image has two repositories that share no package name, so scenarios can show `extra/<package>`,
`core/<package>` for a package only `extra` holds, an unknown repository, and every `parallelDownloads` value.
Everything that needs several versions of one name or a `Usage` setting (a qualifier choosing a later repository,
"Qualified entry is not a pin", the three `Usage` scenarios, the older-version case, "Same qualified entry with a newer
version in an earlier repository") needs a container prepared with fixture repositories holding real package files, run
through the installer-in-scenario path of `.agents/knowledge/testing.md` or the feature's direct checks. "Image
configuration ending in a repository section" needs a container whose `/etc/pacman.conf` was rearranged, since the
supported image's ends in `[options]`. "Unconfirmed value fails closed" is prepared by hiding or replacing
`pacman-conf`; the cause "the `pacman` found does not know the setting" cannot be prepared on a supported image and is
covered by review. Concurrency itself is timing dependent and is not asserted; the resolved configuration is. The held
lock and the proxy variables are prepared by the check's own script inside its container, with a stand-in that records
the environment and the number of `pacman` calls; server fallback and timeouts are upstream behavior and are not
asserted.

## Risks / Trade-offs

- [`--config` widens the reviewed surface the baseline had closed] → The file has a fixed shape with one validated
  number, includes the image's configuration instead of restating it, and is compared against the image's resolved
  configuration in tests; every other excluded argument stays excluded.
- [The wrapper names `/etc/pacman.conf`, `pacman`'s default on Arch Linux; a derivative with another default path would
  get the wrong base] → Only images of the compatibility list are supported; a missing file fails closed, and the spec
  states the limit.
- [A build killed by a signal the shell cannot catch leaves the temporary file in the layer] → It holds two lines and no
  secret; the trap covers every exit the script can observe.
- [`pacman.log` keeps the temporary path] → Stated in the spec and NOTES.md; the feature does not edit the log.
- [A qualifier reads like a pin and is not one; it lifts `Usage` for the named target and can select an older version,
  and repeated installations can then alternate between two versions] → Each is stated in the requirement that carries
  it and in NOTES.md; none can occur on the plain compatibility image, whose two repositories share no package name and
  set no `Usage`.
- [A high `parallelDownloads` meets mirror rate limits and nothing retries] → Range capped at 20; NOTES.md says so.
- [Entries with one `/` that failed validation before can now reach `pacman`] → They fail there as an unknown repository
  unless the image configures one; no entry accepted before changes meaning.
- [All evidence but one observation is from pacman 7.1.0 on one rolling image] → The confirmation step fails an explicit
  value on a `pacman` that does not honor it, as observed with 5.2.2; the default path does not depend on any of it.

## Open Questions

1. **Cleanup limitation.** Issue #60 asks to resolve the default `CacheDir`/`DBPath` limitation "before exposing custom
   paths". No custom-path option is proposed, so this package leaves cleanup bound to the two default directories.
   Confirm that, or ask for cleanup to follow `pacman-conf`, which changes default behavior on images with custom paths.
2. **Downgrade through an explicit target.** This package rewords "Full system upgrade" so that the no-downgrade bound
   covers the system upgrade and the feature's arguments, and states as a knowingly left risk that a listed entry can
   replace an installed package with an older version and that repeated installations can alternate. The epic keeps the
   downgrade policy for phase 3, so the maintainer decides whether phase 2 may state this native behavior. The
   alternative is a guard that fails such an entry, at the cost of a second `pacman` call before the transaction.
3. **Lifting "no `--config`".** Without it `parallelDownloads` cannot be offered. Confirm the temporary file with a
   trap, or prefer `--config /dev/stdin`.
4. **Name, default, and range.** Confirm `parallelDownloads`, empty as "inherit", and the upper bound 20 instead of a
   higher pacman-specific one.
5. **Repository name characters.** Confirm `[A-Za-z0-9][A-Za-z0-9._+-]*`; upstream documents no set.
6. **`Usage` override.** Accepted as native behavior in the requirement, for the named target only; its dependencies and
   unqualified entries stay bound by `Usage`. The alternative is refusing a qualified entry whose repository lacks
   install usage, through a `pacman-conf --repo=<name> Usage` lookup.
7. **Unsupported controls.** Confirm that the epic accepts "not supported by this manager" for retries, lock waiting,
   and numeric timeouts, and that no boolean for `--disable-download-timeout` is wanted.
8. **Version.** Confirm 1.1.0 as MINOR although entries with one `/` that failed validation before can now succeed.
9. **Confirmation step.** The `pacman-conf` confirmation is this design's way to never ignore an explicit value; it adds
   one read-only command before the transaction and names `pacman-conf` in the requirement. Confirm it, or accept
   `pacman`'s own failure on a missing configuration as sufficient.
10. **Single-slash relative paths.** `dir/file.pkg.tar.zst` passes validation as a qualified target and fails in
    `pacman` as an unknown repository. Confirm this as stated in the requirement, or ask for a stricter rule.
