# Design

## Context

Version 1.0.1 validates `cleanup` and every entry, exits 0 on an empty list before it looks for `pacman`, makes one call
`pacman --sync --refresh --sysupgrade --needed --noconfirm -- <entries>`, and then cleans the two default cache
directories. It creates no file, sets no trap, and refuses every entry holding `/`. The baseline design
(`../archive/2026-10-05-add-pacman-packages-feature/design.md`) bound that call to carry no `--config`, `--cachedir`, or
`--dbpath`, and the phase 1 design (`../archive/2026-10-05-configure-pacman-packages-cleanup/design.md`) left download
configuration and path resolution to phase 2.

The five package-manager features of epic #127 share conventions for phase 2, which this design follows and refers to as
"the family rule": options are strings or booleans; an empty string means "pass nothing, the image's setting applies"; a
numeric value is a canonical decimal integer checked before any package-manager call; one name per shared concept
(`parallelDownloads` here and in `dnf-packages`, range 1 to 20); a control the manager cannot honor is not declared; an
explicit value that cannot be honored at run time fails instead of being ignored; a per-invocation argument is preferred
over an environment variable, and that over a temporary configuration file; nothing persists.

### Upstream facts

From pacman(8) (https://man.archlinux.org/man/pacman.8), pacman.conf(5) (https://man.archlinux.org/man/pacman.conf.5),
and the pacman source at tag v7.1.0 (https://gitlab.archlinux.org/pacman/pacman):

- pacman(8), `-S`: "the repository can be explicitly specified to clarify the package to install: `-S testing/qt`", and
  version requirements may be given. `src/pacman/sync.c` (`process_target`) splits a sync target at its first `/`, looks
  the left part up among the configured databases, and fails with "database not found" when there is none; its comment
  says a named repository is marked valid for installs because the name was given with the target, which is why `Usage`
  does not restrict a qualified target.
- pacman(8): `--config <file>` names an alternate configuration file. pacman.conf(5): `Include` reads another
  configuration file, which "can include repositories or general configuration options"; `ParallelDownloads` "specifies
  number of concurrent download streams", "needs to be a positive integer", and without it "only one download stream is
  used". `pacman -S --help` lists no argument for it.
- `src/pacman/conf.c` (`_parse_options`) assigns `ParallelDownloads` on every occurrence, so the last one read wins. It
  parses the number with `strtol`, refuses a value below 1 and one above `INT_MAX`, and accepts `3`, `3`, `03`, and `+3`
  as 3.
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
- A fixture with hand-built `file://` databases (`newer`, bc 9.0-1, before `[core]`; `older`, bc 1.00-1, and `nouse`, bc
  9.5-1 with `Usage = Sync Search`, after `[extra]`): `bc` resolves to `newer/bc`, `extra/bc` to `extra/bc` at 1.08.2-1,
  `older/bc` to `older/bc 1.00-1`, `nouse/bc` to `nouse/bc 9.5-1`, and the unqualified `bc<9` to `extra/bc`. With
  extra's bc installed, `-Syu --needed -- extra/bc` reports it up to date and then upgrades it to `newer/bc`. With bc
  1.08.2-1 installed, `older/bc` and the unqualified `bc<1.05` both print "downgrading package bc (1.08.2-1 => 1.00-1)"
  and go on to the download; the fixture holds no package file, so the transaction was not observed to its end.
- Wrapper configuration (`[options]`, `Include = /etc/pacman.conf`, `[options]`, `ParallelDownloads = 3`):
  `pacman-conf --config <file> ParallelDownloads` prints 3; with the override before the `Include` it prints 5. The
  whole `pacman-conf --config <file>` dump equals the plain `pacman-conf` dump except the `ParallelDownloads` line, and
  `--repo-list` prints `core` and `extra`. With `--debug`, the run under the wrapper shows the `alpm` download user and
  the syscall filter in effect, completions in queue order with 1 and interleaved with 4. A full run with a wrapper from
  `mktemp` (mode 0600, root) exits 0 and leaves `/etc/pacman.conf` and every file under `/etc/pacman.d` with unchanged
  hashes. An `Include` of a missing file fails both `pacman-conf` and `pacman` with "config file ... could not be read",
  status 1, nothing installed. `/var/log/pacman.log` records the call with `--config <path>`.
- `--config /dev/stdin` with a here-document also works and ties `pacman`'s standard input to the configuration text.
- Lock: with an existing `/var/lib/pacman/db.lck` the call fails within milliseconds with "unable to lock database",
  status 1; a killed `pacman` leaves the lock file behind.
- Servers: with a first `Server` that refuses the connection, `pacman` reports it and completes from the next, status 0.
- Proxy: `https_proxy`, `HTTPS_PROXY`, and `ALL_PROXY` pointing at a closed port each made the download fail through the
  proxy, and `no_proxy` for the mirror's domain bypassed it. Precedence among these variables is libcurl's and was not
  tested.

Not verified: any pacman other than 7.1.0 (an older one is expected to warn about an unknown directive); a character set
for repository section names, which pacman.conf(5) does not define; a configuration path other than `/etc/pacman.conf`
on a derivative.

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
  `/etc/pacman.conf`, a second `[options]` header, and the `ParallelDownloads` line, in that order. The second header is
  needed because the included file ends inside a repository section, and the override comes last because the last
  assignment wins. Checked by comparing the `pacman-conf --config <file>` dump with the plain dump: only the
  `ParallelDownloads` line may differ.
- The file is created with `mktemp` under the default temporary directory, never under `/etc`, readable by root only,
  and removed by a trap on exit and on the signals the shell lets the script catch. Checked by listing the temporary
  directory after a successful run, after a run failing in `pacman`, and after a run failing the confirmation below.
- An explicit value is confirmed before the transaction: `pacman-conf --config <file> ParallelDownloads` must print the
  requested value, and anything else, a failing or missing `pacman-conf` included, ends the run with status 1 naming the
  option. Checked by the direct checks for "Image configuration that cannot be included fails closed" and "Explicit
  parallel downloads reach pacman", which use the same command to observe the value.
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
  `[A-Za-z0-9][A-Za-z0-9._+-]*`, the family's identifier rule with the characters all official repository names use
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
  variable for the setting, so the family's third mechanism applies. This deliberately lifts the baseline bound "no
  `--config`" for this one key and for a non-empty value only; `--cachedir`, `--dbpath`, and every other excluded
  argument stay excluded. The wrapper includes the image's configuration instead of copying it, so repositories,
  `SigLevel`, `DownloadUser`, the sandbox settings, and the image's own `Include` lines are whatever the image has at
  that moment. Rejected: `--config /dev/stdin`, which writes no file but consumes the standard input of the one command
  that must run without input, and whose behavior with a here-document under every POSIX shell is one more thing to
  verify; editing `/etc/pacman.conf` and restoring it, which changes an image file and can leave it changed when the
  build is killed; copying the configuration with the line rewritten, which duplicates repository and trust settings
  into a file the feature would then own; not offering the option, which leaves the issue's download control out
  although the manager supports it.
- **Confirm the value with `pacman-conf` before the transaction.** The family rule forbids a silently ignored control.
  One read-only command covers a missing or unreadable `/etc/pacman.conf`, a `pacman` that does not know the key, and
  any future reason the override would not win, and it is the same command the tests use to observe the value.
  `pacman-conf` ships in the `pacman` package. Rejected: relying on `pacman`'s own failure for the missing file alone,
  which covers one of the three cases; parsing `/etc/pacman.conf` in the script.
- **Range 1 to 20.** `pacman` accepts any positive integer up to `INT_MAX`. The family bound is applied because `pacman`
  has no retry to absorb a mirror that limits simultaneous connections, and one range for one option name keeps the two
  features that share it alike. The digits-only rule matters more than the range: the value is written into a
  configuration file, so a line break or `[` in it would add directives. `0` is refused because `pacman` refuses it, and
  the forms `pacman` would quietly accept (`3`, `03`, `+3`) are refused so that one value has one spelling.
- **Validation order is the phase 1 order.** `cleanup`, `parallelDownloads`, and every entry are checked first; then the
  empty-list exit; then `require_pacman`; then, for a non-empty value, the temporary file and its confirmation; then the
  call; then cleanup. A valid `parallelDownloads` with an empty list therefore creates nothing and needs no `pacman`.
- **Unsupported controls are stated, not emulated.** A wait loop around the lock, deleting a stale lock, or a retry loop
  around the whole transaction would be behavior outside `pacman`, and a retried `-Syu` is not the same transaction. The
  spec's requirement "Unsupported download controls stay native" states what applies instead. Rejected: a boolean for
  `--disable-download-timeout`, which issue #60 does not name, works one way only (it cannot restore the timeout an
  image disabled), and is not a bounded control.
- **Cleanup stays bound to the default directories.** Following `pacman-conf CacheDir` and `DBPath` would change what
  `cleanup=all` deletes on an image with custom paths while no new option is set, which the epic forbids in this phase,
  and no custom-path option is proposed that would need it (Open question 1).
- **Pre-existing wording is not corrected here.** The main spec's "The feature SHALL NOT downgrade any installed
  package" is not true for an explicit target in an image whose repositories offer an older version, with or without a
  qualifier. Correcting it changes a requirement that describes behavior with no new option set, so it is recommended as
  a separate fix; this change states `pacman`'s behavior for qualified entries in the requirement that admits them (Open
  question 2).

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
  upper bound of 999 as the research first suggested, against the family bound; a separate `repository` option (first
  decision); `downloadRetries`, `lockTimeout`, `networkTimeout`, `connectTimeout`, and `transferTimeout`, which sibling
  features declare and `pacman` cannot honor; options for `CacheDir`, `DBPath`, a proxy, or extra arguments.

### Documentation bounds

NOTES.md gains one section with the four headings the five features share: "What the feature sets explicitly" (the one
`--config` wrapper and its two lines, only for a non-empty `parallelDownloads`), "What is inherited" (the whole
`pacman.conf`, including its repositories and their order), "Proxy" (the libcurl variables observed to take effect, with
their precedence labeled as not verified), and "Locks and retries" (no waiting, a stale `db.lck` fails at once; no
retries beyond the next server; the fixed 10-second timeouts). It also explains the qualifier with its three native
properties, says that an unqualified constraint already selects among repositories, mentions the path left in
`pacman.log`, and replaces the two sentences that say every entry holding `/` is refused and that the feature adds no
pacman configuration of its own. No fact from the "Not verified" list above is written as a fact.

### Verification bounds

The plain image has two repositories that share no package name, so scenarios can show `extra/<package>`,
`core/<package>` for a package only `extra` holds, an unknown repository, and every `parallelDownloads` value.
Everything that needs several versions of one name (a qualifier choosing a later repository, "Qualified entry is not a
pin", the `Usage` case, the older-version case) needs a container prepared with fixture repositories, run through the
installer-in-scenario path of `.agents/knowledge/testing.md` or the feature's direct checks; the fixture needs real
package files for the older-version scenario to be observed to its end. Concurrency itself is timing dependent and is
not asserted; the resolved configuration is. The held lock, the refusing first server, and the proxy variable are
prepared by the check's own script inside its container.

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
- [A qualifier reads like a pin and is not one; it also overrides `Usage` and can select an older version] → Each is
  stated in the requirement and in NOTES.md; none can occur on the plain compatibility image, whose two repositories
  share no package name.
- [A high `parallelDownloads` meets mirror rate limits and nothing retries] → Range capped at 20; NOTES.md says so.
- [Entries with one `/` that failed validation before can now reach `pacman`] → They fail there as an unknown repository
  unless the image configures one; no entry accepted before changes meaning.
- [All evidence is from pacman 7.1.0 on one rolling image] → The confirmation step fails an explicit value on a `pacman`
  that does not honor it; the default path does not depend on any of it.

## Open Questions

1. **Cleanup limitation.** Issue #60 asks to resolve the default `CacheDir`/`DBPath` limitation "before exposing custom
   paths". No custom-path option is proposed, so this package leaves cleanup bound to the two default directories.
   Confirm that, or ask for cleanup to follow `pacman-conf`, which changes default behavior on images with custom paths.
2. **Downgrade through an explicit target.** The existing "SHALL NOT downgrade any installed package" and the scenario
   "Constraint below the installed version on the second install" hold only while each name has one offered version.
   This package states `pacman`'s behavior for qualified entries and recommends correcting the existing wording in a
   separate fix or in phase 3. Alternatives: correct it inside this change, or add a guard in the feature.
3. **Lifting "no `--config`".** Without it `parallelDownloads` cannot be offered. Confirm the temporary file with a
   trap, or prefer `--config /dev/stdin`.
4. **Name, default, and range.** Confirm `parallelDownloads`, empty as "inherit", and the upper bound 20 instead of a
   higher pacman-specific one.
5. **Repository name characters.** Confirm `[A-Za-z0-9][A-Za-z0-9._+-]*`; upstream documents no set.
6. **`Usage` override.** Accepted as native behavior in the requirement. The alternative is refusing a qualified entry
   whose repository lacks install usage, through a `pacman-conf --repo=<name> Usage` lookup.
7. **Unsupported controls.** Confirm that the epic accepts "not supported by this manager" for retries, lock waiting,
   and numeric timeouts, and that no boolean for `--disable-download-timeout` is wanted.
8. **Version.** Confirm 1.1.0 as MINOR although entries with one `/` that failed validation before can now succeed.
9. **Confirmation step.** The `pacman-conf` confirmation is this design's reading of the family rule "fail, never
   ignore"; it adds one read-only command before the transaction. Confirm it, or accept `pacman`'s own failure on a
   missing configuration as sufficient.
10. **Single-slash relative paths.** `dir/file.pkg.tar.zst` passes validation as a qualified target and fails in
    `pacman` as an unknown repository. Confirm this as stated in the requirement, or ask for a stricter rule.
