# Spec Delta

## MODIFIED Requirements

### Requirement: Installation controls are validated before changes

Before package-manager calls, cache creation, or file writes, the feature SHALL validate booleans, enums, package
entries, repository aliases, timeouts and retries. Lock/connect/transfer values are canonical ASCII decimals 1–3600;
retries 0–10. Alias syntax is separately specified. Invalid options fail status 1 naming the option/alias. Valid empty
lists perform no package work or configuration change; alias existence and whether controls take effect are checked only
for nonempty lists.

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

The feature SHALL install listed packages and dependencies only from image-enabled repositories, or the selected enabled
repositories when `repositories` is nonempty. Recommendations follow installRecommends. Other installed packages do not
upgrade except listed packages and their needs.

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

The feature SHALL pass `name=edition`, `name.architecture`, combined forms, and `<`, `<=`, `>`, `>=` edition ranges
unchanged. An edition may include version, epoch and release. Architecture must be offered for the image. Pinned
editions do not downgrade: if older than installed, the installed package stays and the entry does not fail.

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

Entries SHALL start with an ASCII letter/digit; name characters are ASCII letters, digits, `.`, `_`, `+`, `-`; at most
one `=`, `<`, `<=`, `>`, or `>=` operator is allowed. The nonempty suffix uses ASCII letters, digits, `.`, `_`, `+`,
`~`, `^`, `:`, `-`; `.rpm` endings are refused. Invalid entries fail status 1 before zypper, refresh or install;
accepted entries are one argument, never shell code.

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

The feature SHALL select same-case package-name matches, including name-architecture/edition and trailing
version/release forms. Unless exactNames=true, if no name matches, Zypper may select a capability provider. It never
matches globs, patterns, patches or products. Unmatched entries fail with no listed package installed.

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

With default or always, SHALL check every repository in use before install and fetch metadata only if missing/changed;
any unavailable/unverifiable repository fails before install. never uses cached metadata only and fails if any in-use
repository lacks usable metadata; package files may still download. Unused repositories are neither refreshed nor
checked. Install does not refresh again; signature/TLS checks remain.

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

The feature SHALL preserve image libzypp signature checks and SHALL NOT ignore failures, trust keys, accept unsigned
content, or change repositories/services/keys/configuration. Image-disabled checks remain disabled. No own config
persists; only the temporary timeout/retry file may be written. Package-shipped files and image index-service rewrites
are excluded.

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

After success, all SHALL remove downloaded packages and raw/parsed repository metadata from effective libzypp caches;
packages removes package files but retains usable metadata; none performs no explicit deletion. No mode removes
installed databases, keys, or unrelated paths. Native hooks may delete independently; none cannot guarantee retention
and packages cannot create metadata.

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

A second installation SHALL retain packages from both lists and resolve as a first run; it may upgrade
unpinned/range-listed packages and dependencies. Each run uses its own controls, with no image-config override: cache,
recommendations, repositories, exactNames, lock wait, timeouts and retries do not persist. Prior optional packages
remain.

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

With empty `repositories`, the feature SHALL use all image-enabled repositories. Otherwise refresh, cache checks and the
entire transaction (listed packages and dependencies) SHALL use only selected enabled aliases. An exact case-sensitive
enabled alias is required; a missing, disabled, or ambiguous alias SHALL fail status 1 after zypper check and before
refresh/change. The feature SHALL NOT enable/edit repositories, accept names/numbers/URIs, or narrow cleanup.

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

An empty lockTimeout SHALL leave image/build libzypp wait settings unchanged (without one, immediate failure). A
nonempty value SHALL apply per zypper call, override inherited wait for that call only, and SHALL NOT persist or pass
elsewhere. Each call waits separately, may exceed the value until lock check; failure is nonzero and a failed
refresh/install changes no package.

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

Empty connect/transfer timeout SHALL leave image settings. Nonempty connectTimeout SHALL limit each connection phase;
transferTimeout SHALL limit inactivity between received data, not a transfer that continues receiving. Both SHALL apply
to metadata and package downloads for all feature zypper calls only. libzypp still ends each transfer at 3600 seconds;
options change no retries, mirrors, proxy, TLS or signatures.

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

Empty downloadRetries inherits image `download.max_silent_tries`. N makes each metadata request try at most N+1 times; 0
means no retry. Each HTTP method on each URL counts as a separate request. This is partial: package files are not
covered and zypper’s fixed retries on other commands are unaffected. The feature SHALL NOT repeat refresh/install to
compensate.

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

When all three options are empty, the feature SHALL write no config. Otherwise with packages it uses one new temporary
libzypp config containing only nonempty overrides; it never edits/masks existing files and removes its file/directories
after success or failure. If ZYPP_CONF is set (even empty) or libzypp lacks RPM capability `libzypp(econf)`, fail status
1 naming cause before refresh/change. Never alter ZYPP_CONF. With empty options these conditions are not checked.

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

### Requirement: Repository aliases use literal image identifiers

Each `repositories` alias SHALL start with an ASCII letter or digit, contain only ASCII letters, digits, `.`, `_`, `:`,
`+`, `-`, and not be digits alone. This rejects repository numbers, URIs, paths, globs and option-like values. An
enabled repository with an alias outside this grammar cannot be selected. Repository lists SHALL validate before
package-manager commands, cache/file changes; errors name the option and alias.

#### Scenario: Invalid repository alias is refused

- **WHEN** a repository alias is numeric-only or contains a disallowed character
- **THEN** the feature exits status 1 naming `repositories` and the alias before package work

### Requirement: Edition and architecture qualifiers retain native forms

The feature SHALL pass `name=edition`, `name.architecture`, `name.architecture=edition`, `name<edition`,
`name<=edition`, `name>edition`, and `name>=edition` unchanged. A trailing `-version` or `-version-release` SHALL be
parsed as the package edition, including an optional epoch; architecture-qualified resolution only selects builds
available for the image.

#### Scenario: Qualified name selects the available edition

- **WHEN** `exactNames=true` and a valid entry uses `name.architecture=edition` or a trailing `-version-release` form
- **THEN** zypper selects the same package form as when exactNames is false

### Requirement: libzypp signature settings remain image-owned

The feature SHALL preserve libzypp `gpgcheck` settings from zypp.conf(5), libzypp 17.38.16
(https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt). It SHALL trust only keys already trusted
by the image RPM database, except that it trusts no new key; repositories whose image setting disables checking remain
unchecked. Repository index services may rewrite their own definitions during refresh, which is outside feature changes.

#### Scenario: Signature setting disabled by image remains disabled

- **WHEN** the image disables signature checking for a repository in use
- **THEN** the feature does not enable checking or alter the repository configuration

### Requirement: Timeout settings retain native scopes

`connectTimeout` SHALL set `download.connect_timeout` for each connection phase. `transferTimeout` SHALL set
`download.transfer_timeout` as an inactivity limit; zypp.conf(5) describes maximum transfer time, but libzypp behavior
governs. Each transfer still has libzypp’s 3600-second limit with or without the option. Neither option changes retries,
mirror selection, proxy, TLS, or signature checking.

#### Scenario: Active transfer is governed by inactivity only

- **WHEN** a transfer continues receiving data with pauses shorter than transferTimeout for longer than that value total
- **THEN** the transfer completes rather than timing out

### Requirement: Download retry scope stays partial

`downloadRetries` SHALL set `download.max_silent_tries` only for repository metadata requests. N means at most N+1
attempts per HTTP-method/URL request; package files are attempted once per known mirror, and fixed zypper retries on
other commands are unaffected. This partial control is accepted because it is libzypp’s bounded per-invocation behavior;
the feature SHALL NOT repeat refresh or install to compensate.

#### Scenario: Retry count is independent per method and URL

- **WHEN** one metadata file is requested through multiple HTTP methods or URLs with downloadRetries=N
- **THEN** each method/URL request gets at most N+1 attempts

### Requirement: Temporary libzypp configuration preserves image settings

When a timeout or retry override is active, the new temporary file SHALL contain only nonempty settings and be read in
addition to image config. Later image config may override it; the feature does not detect precedence because
reimplementing libzypp merge risks silently changing signature settings. `libzypp(econf)` is the only support test and
the feature does not verify that libzypp read the file.

#### Scenario: Later image configuration can override an option

- **WHEN** image libzypp configuration read after the temporary file sets the same key
- **THEN** that later image value takes effect without feature detection

### Requirement: Repository selection risks remain explicit

The feature SHALL accept zypper’s documented risk: selection hides unselected repositories from resolution, and zypper
says it later restricts only listed packages. This allows builds to depend on and refresh only named repositories. No
option permits removals; the feature runs non-interactively and fails when zypper declines a solution requiring removal,
but it adds no removal check and cannot promise retention for an installed package from an unselected repository.

#### Scenario: Package from an unselected repository is not protected by a feature check

- **WHEN** a selected-repository transaction would require removing an installed package from an unselected repository
- **THEN** the feature passes no removal option and relies on zypper’s non-interactive solution behavior
