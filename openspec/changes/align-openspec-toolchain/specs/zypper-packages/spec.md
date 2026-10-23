# Spec Delta

## MODIFIED Requirements

### Requirement: Installation controls are validated before changes

The feature SHALL validate `installRecommends`, `exactNames`, `refreshPolicy`, `cleanup`, `repositories`, `lockTimeout`,
`connectTimeout`, `transferTimeout`, `downloadRetries` and all package entries before invoking any package-manager
command, creating any cache, or writing any file. Invalid options SHALL fail with status 1 and a message naming the
option, for `repositories` also the refused alias.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Empty list ignores selection and network controls

- **WHEN** packages is empty, `repositories` holds a well-formed alias no repository has, the timeout and retry options
  are valid and non-empty, and the build environment sets `ZYPP_CONF`
- **THEN** the feature succeeds without invoking the package manager and without writing any file, also on an image
  without `zypper`

#### Scenario: Lock timeout boundaries are validated

- **WHEN** `lockTimeout` is empty or one of its two bounds, or an invalid value such as zero, a negative number, a
  number above the upper bound, a number with a leading zero, a number followed by a letter, or shell text
- **THEN** empty and the two bounds are accepted; every invalid value fails with status 1 naming `lockTimeout` before a
  package-manager command

#### Scenario: Connect timeout boundaries are validated

- **WHEN** `connectTimeout` is empty or one of its two bounds, or an invalid value such as zero, a number above the
  upper bound, a number with a leading zero, or text holding a line break and a configuration key
- **THEN** empty and the two bounds are accepted; every invalid value fails with status 1 naming `connectTimeout` before
  a package-manager command and before any file is written

#### Scenario: Transfer timeout boundaries are validated

- **WHEN** `transferTimeout` is empty or one of its two bounds, or an invalid value such as zero, a number above the
  upper bound, a number with a leading zero, or text holding a line break and a configuration key
- **THEN** empty and the two bounds are accepted; every invalid value fails with status 1 naming `transferTimeout`
  before a package-manager command and before any file is written

#### Scenario: Retry boundaries are validated

- **WHEN** `downloadRetries` is empty or one of its two bounds, or an invalid value such as a negative number, a number
  above the upper bound, a number with a leading zero, or text holding a line break and a configuration key
- **THEN** empty and the two bounds are accepted; every invalid value fails with status 1 naming `downloadRetries`
  before a package-manager command and before any file is written

#### Scenario: Malformed repository alias is refused

- **WHEN** `repositories` holds an item that is a number, a URI or path, a glob, starts with `-`, or holds whitespace
  inside it or a character outside the accepted set, also when packages is empty
- **THEN** the feature exits with status 1, names `repositories` and the item, and invokes no package-manager command

### Requirement: Install the listed packages

The feature SHALL install, with `zypper`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories in use: the repositories enabled in the image, or, with a
non-empty `repositories`, the selected ones among them. Apart from that dependency selection, it SHALL NOT upgrade
installed packages other than the listed packages and what they need.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Recommended packages are left out

- **WHEN** `installRecommends=false` and `packages` names a package that recommends another package which nothing
  installed requires
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Listed package already installed at its newest version

- **WHEN** `packages` names, without a version, a package that is already installed at the newest version the enabled
  repositories offer
- **THEN** the feature succeeds and the package stays at that version

#### Scenario: Optional dependency selection is enabled

- **WHEN** `installRecommends=true` and a listed package has an applicable recommendation that is available and
  unconstrained
- **THEN** the package manager includes that recommendation in its resolution; required dependencies and conflict
  protection remain in effect

### Requirement: Version and architecture qualifiers

The feature SHALL pass an entry of the form `name=edition`, `name.architecture`, or `name.architecture=edition`, or one
that puts a range operator in the place of `=` (`name<edition`, `name<=edition`, `name>edition`, `name>=edition`), to
`zypper` unchanged, so that `zypper` selects that edition (a version, optionally with an epoch and a release), an
edition in that range, or that architecture of the package.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name=edition` for an edition the image's repositories offer, and the package is not
  installed
- **THEN** exactly that edition of the package is installed

#### Scenario: Unavailable pinned version fails

- **WHEN** `packages` holds `name=edition` for an edition the image's repositories do not offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Range constraint is installed

- **WHEN** `packages` holds `name>=edition` that an edition the image's repositories offer satisfies, and the package is
  not installed
- **THEN** an edition of the package that satisfies the constraint is installed

#### Scenario: Unsatisfied range constraint fails

- **WHEN** `packages` holds `name<edition` that no edition the image's repositories offer satisfies
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Native architecture qualifier is installed

- **WHEN** `packages` holds `name.architecture` with the image's native architecture
- **THEN** the package is installed for that architecture

#### Scenario: Architecture the repositories do not offer fails

- **WHEN** `packages` holds `name.architecture` with an architecture for which the image's repositories offer no build
  of that package
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it starts with an ASCII letter or a digit, its name part consists only of
ASCII letters, digits, and the characters `.`, `_`, `+`, and `-`, it holds at most one operator (`=`, `<`, `<=`, `>`, or
`>=`), the part after that operator is not empty and consists only of ASCII letters, digits, and the characters `.`,
`_`, `+`, `~`, `^`, `:`, and `-`, and the entry does not end in `.rpm`.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL or a path to an `.rpm` file
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Package file name is refused

- **WHEN** `packages` holds an entry ending in `.rpm`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like or modifier entry is refused

- **WHEN** `packages` holds an entry starting with `-`, `!`, `+`, or `~`
- **THEN** the feature exits with status 1, names the entry, and neither removes nor installs any package

#### Scenario: Kind or repository prefix is refused

- **WHEN** `packages` holds an entry with `:` before any operator, such as `pattern:name` or `repository:name`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, `|`, `(`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries select packages as zypper matches them

The feature SHALL install for each entry the package that `zypper` selects for it from the repositories in use: a
package whose name equals the entry's name part, without its architecture and edition, in the same letter case, or
equals it once a trailing `-version` or `-version-release` is read as an edition of that package; and, with
`exactNames=false`, when no package has that name, a package that provides the name part as a capability, which `zypper`
chooses when several provide it.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name-version form selects that edition

- **WHEN** `packages` holds a package name followed by `-` and an edition of that package that the image's repositories
  offer, and the package is not installed
- **THEN** exactly that edition of the package is installed

#### Scenario: Capability selects a providing package

- **WHEN** `exactNames=false` and `packages` names a capability that a package of the image's repositories provides,
  that no installed package provides, and that is not itself the name of a package the repositories offer
- **THEN** the feature succeeds and a package that provides the capability is installed

#### Scenario: Name in another case fails

- **WHEN** `packages` names a package that the repositories offer, written with different letter case, and no package or
  capability has that spelling
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Exact names refuse a capability

- **WHEN** `exactNames=true` and `packages` names, alongside a package the repositories offer, a capability that a
  package of the repositories provides and that is not itself the name of a package they offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages, the providing package
  included

#### Scenario: Exact names keep the qualified forms

- **WHEN** `exactNames=true` and `packages` holds package names in the forms `name`, `name=edition`, `name>=edition`,
  `name.architecture`, and name followed by `-` and an edition, each of which the repositories satisfy
- **THEN** the feature succeeds and each entry installs what it installs with `exactNames=false`

#### Scenario: Exact names combine with a repository selection

- **WHEN** `exactNames=true`, `repositories` names an enabled repository, and `packages` names a package of that
  repository and a capability only a package of that repository provides
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Repository metadata refresh

With `refreshPolicy=default` or `always`, the feature SHALL check the index of every repository in use before
installation and download metadata only when missing or changed; the repositories in use are every enabled repository,
or, with a non-empty `repositories`, the selected ones. If any repository in use cannot be refreshed or verified, the
feature SHALL fail before installing and SHALL NOT skip it.

#### Scenario: Missing metadata is refreshed

- **WHEN** `refreshPolicy=default` and the image holds no cached repository metadata
- **THEN** the feature downloads the metadata of every repository in use before installing

#### Scenario: Current metadata is kept

- **WHEN** `refreshPolicy=default` and the image already holds cached metadata of every repository in use and no
  repository's index has changed
- **THEN** the feature installs from the cached metadata, downloading only each repository's index file

#### Scenario: Failed refresh fails the feature

- **WHEN** `refreshPolicy=default` and refreshing the metadata of any repository in use fails, while the other
  repositories in use refresh and offer the listed packages
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Refresh is explicitly requested

- **WHEN** refreshPolicy=always with a non-empty package list and existing metadata
- **THEN** every repository in use is checked before installing; failure of any of them fails before packages change

#### Scenario: Cached metadata is explicitly selected

- **WHEN** refreshPolicy=never and every required index or metadata cache is usable
- **THEN** no metadata is fetched and installation uses the existing metadata under the package manager's normal
  verification policy

#### Scenario: Missing cached metadata fails without refresh

- **WHEN** refreshPolicy=never and a repository in use has no usable cached metadata
- **THEN** the feature fails before installing without attempting a metadata download

### Requirement: Repository authentication stays in effect

The feature SHALL leave libzypp's signature checking (`gpgcheck` in zypp.conf(5), libzypp 17.38.16,
https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt) in effect: it SHALL NOT pass any option or
configuration that ignores signature failures, imports or trusts a new signing key, or accepts unsigned repositories or
packages, and SHALL NOT itself add, remove, or change any repository, service, or trusted key in the image.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** a repository in use has metadata signed by a key the image does not trust
- **THEN** the feature exits with a non-zero status, trusts no new key, and installs none of the listed packages

#### Scenario: Unsigned repository fails the refresh

- **WHEN** a repository in use has metadata that carries no signature, and the image's configuration does not turn the
  signature check off for it
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Zypp configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/zypp` or
  a signing key, with any valid values of its options
- **THEN** the repository and service definitions, the files under `/etc/zypp` and under every other directory libzypp
  reads configuration from, and the keys the RPM database trusts are the same as before it ran

#### Scenario: Signature checking holds beside an override

- **WHEN** a timeout or retry option is non-empty and a repository in use has metadata signed by a key the image does
  not trust
- **THEN** the feature exits with a non-zero status, trusts no new key, and installs none of the listed packages

### Requirement: Clean package caches

After successful installation, `cleanup=all` SHALL explicitly remove downloaded package files and repository metadata
from the effective libzypp package, raw metadata, and parsed metadata caches. With `packages`, it SHALL explicitly
remove downloaded package files while leaving usable metadata; with `none`, it SHALL perform no explicit cache deletion.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the image holds no downloaded package files, no raw repository metadata, and no parsed metadata cache

#### Scenario: Only package files are cleaned

- **WHEN** cleanup=packages with usable metadata and package files present in the managed cache after installation
- **THEN** package files are removed from the managed cache and usable metadata remains

#### Scenario: Feature cleanup is disabled

- **WHEN** cleanup=none and the native package manager and image hooks retain downloads
- **THEN** the feature leaves cached package files and metadata in place

#### Scenario: Native package retention is independent

- **WHEN** cleanup=none but a native setting or image hook deletes package files
- **THEN** the feature does not override the native deletion and does not promise retained packages

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without an edition or with a range, or that a package of its list needs.

The second invocation SHALL use its own control values, with no permanent override of image configuration.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Pin below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name=edition` with an edition that the enabled repositories offer
  and that is older than the one installed
- **THEN** the second installation succeeds and the installed version stays as it was

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different refresh or cleanup values with a
  non-empty compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

#### Scenario: Selection and network controls do not carry over

- **WHEN** the first invocation runs with a repository selection, exact names, a lock wait, timeouts, and retries, and
  the second leaves those options at their defaults and lists a capability that only an enabled repository outside the
  first selection provides
- **THEN** the second invocation refreshes every enabled repository, installs the providing package, runs with the
  image's own lock, timeout, and retry settings, and finds no file the first invocation wrote

#### Scenario: Selection of the second install keeps earlier packages

- **WHEN** the first invocation installed a package from one enabled repository and the second selects another enabled
  repository and lists a package that it offers with all its dependencies and that conflicts with no installed package
- **THEN** the second installation succeeds and the packages of both lists are installed

### Requirement: Repository selection restricts the installation

An empty `repositories` SHALL leave the feature working with every repository the image enables. A non-empty
`repositories` SHALL restrict this invocation's metadata refresh, its cached-metadata check, and the whole installation,
the listed packages and every dependency, to the named repositories; these are then the repositories in use. Each alias
SHALL equal, in the same letter case, the alias of a repository the image enables.

#### Scenario: Empty repositories uses every enabled repository

- **WHEN** `repositories` is empty and `packages` names a package
- **THEN** metadata refresh and installation work with every repository the image enables

#### Scenario: Selected repository provides the packages

- **WHEN** `repositories` names an enabled repository that offers a listed package and all its dependencies
- **THEN** the feature exits with status 0 and the package is installed

#### Scenario: Package outside the selection fails

- **WHEN** `repositories` names an enabled repository, and `packages` names a package that only another enabled
  repository offers
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Dependency outside the selection fails

- **WHEN** `repositories` names an enabled repository that offers a listed package, and a dependency of that package is
  offered only by an enabled repository outside the selection
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Unknown alias fails before installation

- **WHEN** `repositories` holds a well-formed alias that no enabled repository has in that spelling, such as an alias in
  another letter case, an alias without its service prefix, or a repository's name where that name is well-formed, and
  `packages` names a package
- **THEN** the feature exits with status 1, names the alias, downloads no metadata, and changes no package

#### Scenario: Disabled repository is not enabled

- **WHEN** `repositories` holds the alias of a repository the image defines but disables, and `packages` names a package
- **THEN** the feature exits with status 1, names the alias, and the repository stays disabled

#### Scenario: Alias that is another repository's name fails

- **WHEN** `repositories` holds the alias of an enabled repository, another repository the image defines, enabled or
  disabled, has that same text as its name, and `packages` names a package
- **THEN** the feature exits with status 1, names the alias, downloads no metadata, and changes no package

#### Scenario: Unselected repository is not refreshed

- **WHEN** `refreshPolicy` is `default` or `always`, `repositories` names enabled repositories that refresh and offer
  the listed packages, and another enabled repository cannot be refreshed
- **THEN** the feature succeeds and requests no metadata of the unselected repository

#### Scenario: Selected repository that cannot be refreshed fails

- **WHEN** `refreshPolicy` is `default` or `always` and one of several selected repositories cannot be refreshed
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Cached metadata is required only for the selection

- **WHEN** `refreshPolicy=never`, the selected repositories have usable cached metadata, and an unselected enabled
  repository has none
- **THEN** the feature installs from the cached metadata of the selection without downloading any metadata

#### Scenario: Conflict with a package of an unselected repository fails

- **WHEN** `repositories` selects a repository offering a listed package that conflicts with an installed package which
  came from an unselected repository
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and the installed package
  stays

#### Scenario: Cleanup covers every repository

- **WHEN** `repositories` is non-empty, `cleanup=all`, and the image holds cached metadata of an unselected repository
- **THEN** after a successful installation the caches of the unselected repository are removed as well

### Requirement: Lock wait is scoped to installation

An empty `lockTimeout` SHALL leave libzypp's waiting for its system lock as the image and the build environment
configure it: the feature sets and unsets nothing, so an inherited setting applies, and without one libzypp fails at
once when another process holds the lock. A non-empty value SHALL be the number of seconds that each `zypper` call the
feature makes waits for the lock before failing, overriding the inherited setting for those calls only.

#### Scenario: Native lock wait is inherited

- **WHEN** `lockTimeout` is omitted or empty
- **THEN** no lock-wait override is passed, and a lock wait the image or the build environment configures stays in
  effect

#### Scenario: Explicit lock wait reaches zypper calls

- **WHEN** `lockTimeout` is a valid non-empty value and `packages` names a package
- **THEN** every refresh, installation, and cleanup call of the feature runs with that lock wait, and nothing outside
  those calls receives it

#### Scenario: Lock released within the wait

- **WHEN** another process holds libzypp's system lock when the feature starts and releases it before the `lockTimeout`
  elapses
- **THEN** the feature waits, then installs the listed packages and exits with status 0

#### Scenario: Lock held past the wait fails

- **WHEN** another process holds libzypp's system lock for longer than the `lockTimeout`
- **THEN** the feature exits with a non-zero status after waiting at least that long and installs none of the listed
  packages

#### Scenario: Explicit lock wait overrides an inherited one

- **WHEN** the build environment already sets a lock wait for libzypp and `lockTimeout` holds another value
- **THEN** the feature's `zypper` calls wait as `lockTimeout` says, and the environment's own setting is as before for
  anything that runs after the feature

### Requirement: Download timeouts are scoped to installation

An empty `connectTimeout` or `transferTimeout` SHALL leave the matching libzypp setting as the image configures it. A
non-empty `connectTimeout` SHALL be the number of seconds libzypp allows for the connection phase of each download
(`download.connect_timeout` in zypp.conf(5)). Each option SHALL apply to the repository metadata and package downloads
of every `zypper` call the feature makes, and to nothing after the feature exits.

#### Scenario: Native timeouts are inherited

- **WHEN** `connectTimeout` and `transferTimeout` are omitted or empty
- **THEN** no timeout override is applied, and timeouts the image configures stay in effect

#### Scenario: Explicit connect timeout reaches downloads

- **WHEN** `connectTimeout` is a valid value below the connect timeout the image configures and a repository in use does
  not answer connection attempts
- **THEN** the feature exits with a non-zero status without installing any listed package, no sooner than that many
  seconds after it started and sooner than the same run does with `connectTimeout` empty

#### Scenario: Explicit transfer timeout reaches downloads

- **WHEN** `transferTimeout` is a valid value below the transfer timeout the image configures and a server accepts a
  metadata or package request and then sends no data
- **THEN** the feature exits with a non-zero status no sooner than that many seconds after the server accepted the
  request and sooner than the same run does with `transferTimeout` empty

#### Scenario: Active transfer outlasts the transfer timeout

- **WHEN** `transferTimeout` is a valid non-empty value and the download of a listed package's file keeps receiving
  data, with every pause shorter than that value, for longer than that value in total
- **THEN** the download completes and the package is installed

#### Scenario: One timeout leaves the other inherited

- **WHEN** only one of `connectTimeout` and `transferTimeout` is non-empty
- **THEN** the other timeout is the one the image configures

### Requirement: Download retries are bounded

An empty `downloadRetries` SHALL leave libzypp's number of download attempts (`download.max_silent_tries` in
zypp.conf(5)) as the image configures it. A non-empty value N SHALL make libzypp try each repository metadata request at
most N + 1 times before it reports the error, so that `0` means no retry. A request is one HTTP method on one URL:
libzypp may ask for the same file with more than one method, and each counts on its own. No value SHALL request
unbounded retries.

#### Scenario: Native retries are inherited

- **WHEN** `downloadRetries` is omitted or empty
- **THEN** no retry override is applied, and the number of attempts the image configures stays in effect

#### Scenario: Explicit retries reach metadata requests

- **WHEN** `downloadRetries` is a valid value N greater than `0` and a repository in use fails every metadata request
- **THEN** the repository receives no request, counted per HTTP method and URL, more than N + 1 times and its first
  failing request exactly N + 1 times, and the feature exits with a non-zero status, installing no listed package

#### Scenario: Retries turned off

- **WHEN** `downloadRetries` is `0` and a repository in use fails every metadata request
- **THEN** the repository receives no request, counted per HTTP method and URL, more than once, also when the image
  configures more attempts

#### Scenario: Feature does not repeat a failed call

- **WHEN** `downloadRetries` is greater than `0` and the refresh or the installation fails
- **THEN** the feature exits with a non-zero status having made that `zypper` call once

### Requirement: Timeout and retry overrides are temporary

When at least one of `connectTimeout`, `transferTimeout`, and `downloadRetries` is non-empty and `packages` names a
package, the feature SHALL apply the non-empty ones through one temporary libzypp configuration file that holds only the
overridden settings and that libzypp reads in addition to the image's configuration, so that every setting the feature
does not override, the signature, repository, solver, and cache settings among them, stays the image's.

#### Scenario: No override writes no file

- **WHEN** `connectTimeout`, `transferTimeout`, and `downloadRetries` are empty
- **THEN** the feature creates no configuration file or directory at any time during its run

#### Scenario: Override file holds only the overridden settings

- **WHEN** one or more of the three options are non-empty and `packages` names a package
- **THEN** while `zypper` runs, the feature's file sets exactly the keys of the non-empty options and nothing else

#### Scenario: Image settings stay in effect beside an override

- **WHEN** a timeout or retry option is non-empty and the image's libzypp configuration sets other keys, such as
  excluding documentation files or requiring signatures
- **THEN** the installation follows those image settings exactly as it does with the option empty

#### Scenario: Override file is removed after success

- **WHEN** the feature has installed packages with a non-empty timeout or retry option
- **THEN** neither the file nor any directory the feature created for it exists afterwards

#### Scenario: Override file is removed after failure

- **WHEN** the feature fails after it wrote the file, for example because a listed package does not exist
- **THEN** neither the file nor any directory the feature created for it exists afterwards

#### Scenario: Inherited ZYPP_CONF fails an explicit override

- **WHEN** `ZYPP_CONF` is set in the build environment, to the path of a file, to a path that does not exist, or to an
  empty value, a timeout or retry option is non-empty, and `packages` names a package
- **THEN** the feature exits with status 1, names the option and `ZYPP_CONF`, and neither refreshes metadata nor changes
  any package

#### Scenario: Inherited ZYPP_CONF is kept without an override

- **WHEN** `ZYPP_CONF` is set in the build environment, to a path or to an empty value, and the three options are empty
- **THEN** the feature runs `zypper` with that variable unchanged and does not fail because of it

#### Scenario: Libzypp without additional configuration files fails an explicit override

- **WHEN** a timeout or retry option is non-empty, `packages` names a package, and the image's libzypp does not provide
  the RPM capability `libzypp(econf)`
- **THEN** the feature exits with status 1, names the option, and neither refreshes metadata nor changes any package

## ADDED Requirements

### Requirement: Boolean and enum options accept only their values

Boolean options SHALL accept only `true` or `false`; enum options SHALL accept only their declared values.

#### Scenario: Undeclared boolean or enum value is refused

- **WHEN** `installRecommends` is `yes`, or `cleanup` is a value outside `all`, `packages`, and `none`
- **THEN** the feature exits with status 1, names that option, and invokes no package-manager command

### Requirement: Timeout and retry values are bounded integers

A non-empty `lockTimeout`, `connectTimeout`, or `transferTimeout` SHALL be a canonical ASCII decimal integer string from
`1` through `3600`, and a non-empty `downloadRetries` one from `0` through `10`, with no sign, whitespace, leading zero,
or other character. This refuses every value libzypp reads as waiting or retrying without bound, and every value it
would reinterpret; as these values are written into a libzypp configuration file, the same rule keeps an option value
from adding a directive.

#### Scenario: Out-of-range or non-canonical value is refused

- **WHEN** `lockTimeout` is `0`, `connectTimeout` is `3601`, `transferTimeout` is `030`, or `downloadRetries` is `11`
- **THEN** the feature exits with status 1, names that option, and invokes no package-manager command

### Requirement: Repository aliases are well-formed

Each alias in `repositories` SHALL start with an ASCII letter or digit, consist only of ASCII letters, digits, and the
characters `.`, `_`, `:`, `+`, and `-`, and not consist of digits alone, so that a repository number, a URI, a path, a
glob, and an option-like value are refused. An enabled repository whose alias lies outside this set, one holding a space
for example, cannot be selected: its alias is refused as an invalid item.

#### Scenario: Alias holding a space is refused

- **WHEN** `repositories` holds the alias of an enabled repository whose alias holds a space
- **THEN** the feature exits with status 1, names `repositories` and the item, and invokes no package-manager command

### Requirement: An empty package list leaves the controls unchecked

With valid options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or
changing any configuration, also without the package manager; whether an alias names an enabled repository, and whether
a timeout or retry option can take effect, SHALL be checked only when `packages` names a package.

#### Scenario: Empty list skips the alias and override checks

- **WHEN** packages is empty, `repositories` holds a well-formed alias no repository has, a timeout or retry option is
  valid and non-empty, and the image has no `zypper`
- **THEN** the feature succeeds without invoking the package manager and without writing any file

### Requirement: Recommended packages follow installRecommends

Recommended packages SHALL be excluded when `installRecommends=false` and considered by Zypper when
`installRecommends=true`.

#### Scenario: Recommendation is excluded by default

- **WHEN** `installRecommends` is omitted and `packages` names a package that recommends another package which nothing
  installed requires
- **THEN** the listed package is installed and the recommended package is not

### Requirement: Pinned editions are not downgraded

The feature SHALL NOT downgrade a package: when an entry pins with `=` an edition that the enabled repositories offer
and that is older than the installed version of that package, the installed version stays and the entry does not fail
the feature.

#### Scenario: Pin below the installed version

- **WHEN** `packages` holds `name=edition` with an edition that the enabled repositories offer and that is older than
  the one installed
- **THEN** the feature succeeds and the installed version stays as it was

### Requirement: Refused entries fail before any change

When any entry is refused, the feature SHALL exit with status 1 and a message naming that entry before it checks for
`zypper`, refreshes repository metadata, or installs anything. The feature SHALL hand every accepted entry to `zypper`
as one argument and SHALL NOT evaluate it as shell code.

#### Scenario: Refused entry fails before the zypper check

- **WHEN** `packages` holds an entry ending in `.rpm` on an image that has no `zypper`
- **THEN** the feature exits with status 1 with a message naming the entry, and installs nothing

### Requirement: Exact names and unmatched entries

With `exactNames=true` an entry SHALL select a package by its name only: the feature SHALL NOT install a package merely
because it provides the name part as a capability, while the edition, range, architecture, and name-version forms select
as they do with `false`. An entry SHALL NOT be matched as a glob, a pattern, a patch, or a product. When one entry
selects nothing, the feature SHALL fail and install none of the listed packages.

#### Scenario: Exact names install no capability provider

- **WHEN** `exactNames=true` and `packages` names only a capability that a package of the repositories provides and that
  is not itself the name of a package they offer
- **THEN** the feature exits with a non-zero status and installs no package that provides the capability

### Requirement: Cached metadata and metadata use

With `refreshPolicy=never`, the feature SHALL use existing metadata without contacting repositories for refresh and
SHALL fail before installation if any repository in use has no usable cached metadata; package files MAY still be
downloaded. A repository that is not in use SHALL neither be refreshed nor need cached metadata. Installation SHALL use
the selected metadata without another automatic refresh. Signature and TLS checks SHALL remain in effect.

#### Scenario: Cached metadata is used without refresh

- **WHEN** `refreshPolicy=never` and every repository in use has usable cached metadata
- **THEN** no metadata is fetched and installation uses the existing metadata

### Requirement: Zypp configuration files stay the image's

The feature SHALL edit no existing zypp configuration file and SHALL leave no configuration file of its own behind: the
one file it MAY write is the temporary file of the requirement "Timeout and retry overrides are temporary", which holds
no signature, key, or repository setting and is gone when the feature exits.

#### Scenario: No configuration file is left behind

- **WHEN** the feature has installed packages with a non-empty timeout or retry option
- **THEN** no existing zypp configuration file has changed and no configuration file of the feature exists afterwards

### Requirement: Keys and signature settings are the image's

The feature SHALL NOT itself add, remove, or change any trusted key in the image. The keys and the signature settings
are the image's: the feature trusts what the image's RPM database trusts, and a repository for which the image's
configuration turns the check off stays unchecked. Files that the packages it installs ship, and repository definitions
that a repository index service the image defines rewrites from its own index when `zypper` refreshes it, are not the
feature's changes.

#### Scenario: Check turned off by the image stays off

- **WHEN** the image's configuration turns the signature check off for a repository in use
- **THEN** the feature leaves that setting as it is and the repository stays unchecked

### Requirement: Cache cleanup leaves other data alone

No `cleanup` mode SHALL remove installed-package databases, signing keys, or unrelated paths. Package-manager
configuration or image hooks MAY independently delete downloads; none does not guarantee that package files are
retained, and packages does not guarantee that missing metadata is created.

#### Scenario: Cleanup keeps databases and keys

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the installed-package database, the signing keys, and paths unrelated to the package caches remain

### Requirement: Later invocations keep packages and drop earlier controls

Earlier cache choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later
invocation SHALL NOT uninstall previously installed packages. A repository selection, exact-name matching, a lock wait,
timeouts, and retries of one invocation SHALL NOT carry over to the next: an invocation that leaves those options at
their defaults behaves as on an image where the feature never ran with them.

#### Scenario: Recommendations disabled later keep earlier packages

- **WHEN** the first installation ran with `installRecommends=true` and installed a recommended package, and the second
  runs with `installRecommends=false`
- **THEN** the recommended package stays installed

### Requirement: Unknown or disabled alias fails before refresh

When an alias in `repositories` does not equal, in the same letter case, the alias of a repository the image enables,
because no repository has it or because the repository is defined but disabled, the feature SHALL exit with status 1 and
a message naming that alias, after the `zypper` check and before it refreshes metadata or changes any package.

#### Scenario: Alias in another letter case fails

- **WHEN** `repositories` holds the alias of an enabled repository in another letter case and `packages` names a package
- **THEN** the feature exits with status 1, names the alias, downloads no metadata, and changes no package

### Requirement: Alias that is also a repository name fails

The feature SHALL fail in the same way, with status 1 and a message naming that alias, after the `zypper` check and
before it refreshes metadata or changes any package, when a selected alias is also the name of another repository the
image defines, enabled or disabled, because zypper reads a selection as an alias or a name and could take that other
repository for it.

#### Scenario: Alias that is a disabled repository's name fails

- **WHEN** `repositories` holds the alias of an enabled repository that a disabled repository the image defines has as
  its name, and `packages` names a package
- **THEN** the feature exits with status 1, names the alias, downloads no metadata, and changes no package

### Requirement: Repository selection changes no repository

The feature SHALL NOT enable, add, remove, or edit a repository to honor the `repositories` option, and SHALL NOT accept
a repository's name, number, or URI in place of its alias. The selection SHALL NOT narrow cleanup: the requirement
"Clean package caches" applies to the caches of every repository.

#### Scenario: Repository number is not accepted as an alias

- **WHEN** `repositories` holds the number of an enabled repository and `packages` names a package
- **THEN** the feature exits with status 1, names `repositories` and the item, and no repository changes

### Requirement: Repository selection risk is accepted

A non-empty `repositories` SHALL restrict the installation, and the feature knowingly leaves one risk in place.
zypper(8) discourages working with a selection of repositories, because the unselected ones are hidden from the
resolver, which then decides without them, and it announces that the selection will later restrict only the listed
packages. The feature accepts this because hiding the unselected repositories is what lets a build depend on, and
refresh, only the repositories it names.

#### Scenario: Unselected repositories stay hidden from the resolver

- **WHEN** `repositories` names an enabled repository, and a dependency of a listed package is offered only by an
  enabled repository outside the selection
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Removal protection under a selection is zypper's

With a non-empty `repositories`, the requirement "Installed packages are not removed" SHALL hold, but, because the
selection hides the unselected repositories from the resolver, only as far as zypper's own behavior: the feature passes
no option that permits a removal and fails when zypper, running without input, declines a solution that removes a
package, but it adds no check of its own and cannot promise more than zypper does for an installed package that came
from an unselected repository.

#### Scenario: Conflict under a selection fails

- **WHEN** `repositories` selects a repository offering a listed package that conflicts with an installed package which
  came from an unselected repository
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and the installed package
  stays

### Requirement: Lock wait stays per call

The feature SHALL NOT pass a non-empty `lockTimeout` to any other process or persist it. The wait is counted per call
and is not a deadline for the feature, and it MAY run past the value until libzypp's next check of the lock. When a call
does not obtain the lock, the feature SHALL exit with a non-zero status, and a refresh or an installation that did not
obtain it changes no package.

#### Scenario: Lock not obtained fails without package change

- **WHEN** another process holds libzypp's system lock for longer than the `lockTimeout`
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Transfer timeout is an inactivity limit

A non-empty `transferTimeout` SHALL be the number of seconds without any received data after which libzypp aborts a
transfer (`download.transfer_timeout`): an inactivity limit, not a deadline for the feature, so the option does not
abort a transfer that keeps receiving data. zypp.conf(5) words the setting as the maximum time of a transfer operation;
this requirement follows what libzypp does.

#### Scenario: Receiving transfer is not aborted

- **WHEN** `transferTimeout` is a valid non-empty value and a download keeps receiving data, with every pause shorter
  than that value, for longer than that value in total
- **THEN** the download completes

### Requirement: Timeouts change nothing else

libzypp separately ends every single transfer after 3600 seconds, with or without `transferTimeout`, and the feature
does not change that. Neither `connectTimeout` nor `transferTimeout` SHALL change retries, mirror selection, proxy
settings, TLS, or signature checking.

#### Scenario: Timeout leaves the proxy configuration

- **WHEN** `connectTimeout` is non-empty and the image configures a proxy for libzypp
- **THEN** the feature's `zypper` calls use that proxy configuration unchanged

### Requirement: Download retries are knowingly partial

`downloadRetries` is knowingly a partial control. It promises nothing for package files: when the option was specified,
libzypp applied the setting to repository metadata requests only and tried a package file once on each mirror it knew
for it, and the fixed retries zypper itself performs on other commands are not affected. The feature accepts this
because it is the bounded retry libzypp offers per invocation, and it SHALL NOT repeat a refresh or an installation
itself to make up for it.

#### Scenario: Failed installation is not repeated

- **WHEN** `downloadRetries` is greater than `0` and the installation fails
- **THEN** the feature exits with a non-zero status having made the installation call once

### Requirement: The override file is written only when needed and removed

When `connectTimeout`, `transferTimeout`, and `downloadRetries` are all empty, the feature SHALL write no configuration.
Otherwise the temporary file of the requirement "Timeout and retry overrides are temporary" SHALL be a new file: the
feature SHALL NOT edit, replace, or mask an existing file, and SHALL remove the file and every directory it created for
it when it exits, after a success and after a failure alike.

#### Scenario: Override file is gone after a failed run

- **WHEN** the feature fails after it wrote the override file
- **THEN** neither the file nor any directory the feature created for it exists afterwards

### Requirement: An override that cannot take effect fails

A non-empty timeout or retry option that cannot take effect SHALL fail instead of being ignored: the feature SHALL exit
with status 1 and a message naming the option and the cause, before it refreshes metadata or changes any package, when
`ZYPP_CONF` is set in the feature's environment, also to an empty value, or when the image's libzypp does not provide
the RPM capability `libzypp(econf)`, which zypp.conf(5) names as the mark of every libzypp that reads such additional
configuration files.

#### Scenario: Empty ZYPP_CONF fails an override

- **WHEN** `ZYPP_CONF` is set to an empty value, a timeout or retry option is non-empty, and `packages` names a package
- **THEN** the feature exits with status 1, names the option and `ZYPP_CONF`, and changes no package

### Requirement: ZYPP_CONF is untouched

The feature SHALL NOT set, change, or unset `ZYPP_CONF`; when that variable is set, also to an empty value, libzypp
reads solely the file it names, or only its builtin defaults when it names none. With `connectTimeout`,
`transferTimeout`, and `downloadRetries` all empty, neither that condition nor the absence of `libzypp(econf)` is
examined and neither fails the feature.

#### Scenario: ZYPP_CONF without an override is passed unchanged

- **WHEN** `ZYPP_CONF` is set to a path and `connectTimeout`, `transferTimeout`, and `downloadRetries` are empty
- **THEN** the feature runs `zypper` with that variable unchanged and does not fail because of it

### Requirement: Later image configuration can override an option

Overrides SHALL use a file libzypp reads besides the image's configuration, and the feature knowingly leaves two risks
in place, the second in "Econf is the only support test". An image configuration file that libzypp reads after the
feature's file and that sets the same key overrides the option, undetected: detecting it would mean re-implementing
libzypp's merging of configuration files, where a mistake would silently change settings, the signature settings
included.

#### Scenario: Later image configuration overrides an option

- **WHEN** a timeout or retry option is non-empty and a configuration file of the image that libzypp reads after the
  feature's file sets the same key
- **THEN** the image's value takes effect and the feature does not fail because of it

### Requirement: Econf is the only support test

An override SHALL fail when the image's libzypp does not provide the RPM capability `libzypp(econf)`, as the requirement
"An override that cannot take effect fails" states, and this is the second risk the feature knowingly leaves in place:
the capability is the feature's only test of support, and it does not verify afterwards that libzypp read its file.

#### Scenario: Libzypp without econf fails an override

- **WHEN** a timeout or retry option is non-empty, `packages` names a package, and the image's libzypp does not provide
  the RPM capability `libzypp(econf)`
- **THEN** the feature exits with status 1, names the option, and neither refreshes metadata nor changes any package
