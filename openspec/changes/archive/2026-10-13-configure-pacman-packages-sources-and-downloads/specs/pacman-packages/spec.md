## ADDED Requirements

### Requirement: Option parallelDownloads

The feature SHALL accept the option `parallelDownloads` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted parallelDownloads

- **WHEN** `parallelDownloads` is omitted
- **THEN** the feature uses `""` as specified by the requirements below

### Requirement: Parallel downloads are bounded

An empty `parallelDownloads` SHALL add no argument, environment variable, or file to the feature's `pacman` call, so the
number of simultaneous downloads is the one the image's pacman configuration sets, or `pacman`'s own when the image sets
none. A non-empty value SHALL be the upper bound of simultaneous downloads (`ParallelDownloads` in pacman.conf(5)) for
the feature's one `pacman` call, overriding only that setting and only for that call.

`pacman` takes this setting from its configuration alone, so for a non-empty value and a non-empty package list the
feature SHALL create a temporary configuration file outside `/etc` that holds no setting other than an inclusion of
`/etc/pacman.conf`, the configuration `pacman` reads by default on Arch Linux, and the one `ParallelDownloads` setting,
and SHALL hand that file to `pacman` for the call. The setting SHALL be placed so that `pacman` reads it in the options
section and after everything the inclusion brings, whichever section the image's configuration ends in. The feature
SHALL remove the file, and any directory it created for it, when it exits, whether the installation succeeded or failed.
It SHALL create no such file for an empty value or an empty list.

Before the package databases are synchronized, the feature SHALL confirm with `pacman-conf`
(https://man.archlinux.org/man/pacman-conf.8), the tool that reports the configuration `pacman` resolves, that the
configuration resolved from the temporary file carries the requested value. When `pacman-conf` reports another value or
none, fails, or cannot be run, whatever the cause, a missing or unreadable `/etc/pacman.conf` included, the feature
SHALL exit with status 1 and a message naming `parallelDownloads`, without synchronizing, installing, or upgrading
anything. It SHALL NOT continue with the image's value, and SHALL NOT run `pacman` with a configuration that lacks the
image's repositories.

The feature knowingly leaves three things in place. `pacman` writes its command line to `/var/log/pacman.log`, so the
log keeps the path of the removed temporary file; the feature does not edit the log. An image whose `pacman` reads its
default configuration from another path than `/etc/pacman.conf` is not supported with a non-empty value. And `pacman`
has no retry that would absorb a mirror limiting many simultaneous connections, so a high value can fail an installation
that a lower one completes; the accepted range (requirement "Installation controls are validated before changes") is
kept small for that reason.

#### Scenario: Native parallel downloads are inherited

- **WHEN** `parallelDownloads` is omitted or empty and `packages` names at least one package
- **THEN** the feature's `pacman` call names no configuration file, the feature creates no file of its own, and the
  number of simultaneous downloads is the one the image's pacman configuration gives

#### Scenario: Explicit parallel downloads reach pacman

- **WHEN** `parallelDownloads` holds an accepted value different from the image's and `packages` names at least one
  package
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads`, and the
  listed packages are installed

#### Scenario: Temporary configuration is removed

- **WHEN** the feature has run with a non-empty `parallelDownloads` and a non-empty list, and the installation either
  succeeded or failed in `pacman`
- **THEN** the temporary configuration file and any directory the feature created for it no longer exist

#### Scenario: Image configuration that cannot be included fails closed

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `/etc/pacman.conf` is missing or
  unreadable
- **THEN** the feature exits with status 1, names `parallelDownloads`, synchronizes no database, installs and upgrades
  nothing, and leaves no temporary file behind

#### Scenario: Unconfirmed value fails closed

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `pacman-conf` is missing, fails,
  or reports for the temporary configuration a `ParallelDownloads` value other than the requested one
- **THEN** the feature exits with status 1, names `parallelDownloads`, synchronizes no database, installs and upgrades
  nothing, and leaves no temporary file behind

#### Scenario: Image configuration ending in a repository section

- **WHEN** `parallelDownloads` holds an accepted value, `packages` names at least one package, and the last section of
  the image's `/etc/pacman.conf` is a repository section
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads` and the
  repositories of the image, and the listed packages are installed

#### Scenario: Parallel downloads apply under every cleanup value

- **WHEN** `parallelDownloads` is non-empty and `cleanup` is `all`, `packages`, or `none`
- **THEN** the installation uses the requested value, the caches are treated as the requirement "Clean package caches"
  says for that `cleanup` value, and the temporary configuration file is removed under each of them

#### Scenario: Parallel downloads apply to repository-qualified entries

- **WHEN** `parallelDownloads` is non-empty and `packages` holds a repository-qualified entry beside an unqualified one
- **THEN** both are installed in the one `pacman` call, each from the repository the requirement "Entries select
  packages as pacman matches them" gives it

### Requirement: Unsupported download controls stay native

The feature SHALL declare no option for download retries, for waiting on the package database lock, for download
timeouts, or for a proxy, because `pacman` has no bounded native control the feature could set for one call. It SHALL
NOT set, change, or unset a proxy or any other environment variable for `pacman`, SHALL NOT pass an argument or setting
that changes retries, lock handling, or timeouts, SHALL NOT replace `pacman`'s downloader, SHALL NOT repeat a `pacman`
call that failed, and SHALL neither wait for nor remove a package database lock that is already held. The image's
configuration and `pacman`'s own behavior apply to each of them, and the feature SHALL document that it controls none.

#### Scenario: Held database lock fails the installation

- **WHEN** `packages` names at least one package and the lock file of the image's package database already exists
- **THEN** the feature exits with a non-zero status after its one `pacman` call, installs and upgrades nothing, and the
  lock file is still there

#### Scenario: Build environment proxy reaches pacman unchanged

- **WHEN** the environment the feature runs in sets proxy variables
- **THEN** the environment `pacman` receives holds those variables with the same values, and the feature has neither
  added, changed, nor removed a proxy setting

## MODIFIED Requirements

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it is a target or a repository-qualified target. A target starts with an
ASCII letter or a digit and consists only of ASCII letters, digits, the characters `@`, `.`, `_`, `+`, `-`, and `:`, and
the comparison characters `<`, `>`, and `=`. A repository-qualified target is a repository name, exactly one `/`, and a
target, where the repository name starts with an ASCII letter or a digit and consists only of ASCII letters, digits, and
the characters `.`, `_`, `+`, and `-`. Every other entry holding `/` SHALL be refused, and the message SHALL tell two
cases apart: an entry that starts with `/` or `.`, holds `://`, or holds more than one `/` is refused as a path or URL,
which the feature never installs from; any other refused entry holding `/` is refused as a malformed repository
qualifier, with the accepted form named.

When any entry is refused, the feature SHALL exit with status 1 and a message naming that entry before it checks for
`pacman`, synchronizes the package databases, or installs anything. The feature SHALL hand every accepted entry to
`pacman` as one argument and SHALL NOT evaluate it as shell code. Whether a repository of the given name exists is not
part of this validation (requirement "Entries select packages as pacman matches them").

The feature knowingly leaves one case to `pacman`: a relative path with a single `/` and no leading `.` has the shape of
a repository-qualified target and is not told apart from one. It reaches `pacman` as a sync target, which `pacman` never
reads as a file or URL, and fails there as an unknown repository unless the image configures a repository of that name.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/` that is a URL or a path to a package file, such as one starting with
  `/` or `.`, one holding `://`, or one holding more than one `/`
- **THEN** the feature exits with status 1, names the entry, says that paths and URLs are not accepted, and installs
  nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, `|`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

#### Scenario: Repository-qualified entry is accepted

- **WHEN** `packages` holds an entry made of a repository name, one `/`, and a target, with or without a version
  constraint, each part within its accepted characters
- **THEN** the entry passes validation and reaches `pacman` unchanged as one argument

#### Scenario: Malformed repository qualifier is refused

- **WHEN** `packages` holds an entry with exactly one `/` that is no path or URL and whose repository part holds a
  character outside its accepted set or starts with one, or whose target part is empty or is not an accepted target
- **THEN** the feature exits with status 1, names the entry, names the `repository/target` form, and installs nothing

### Requirement: Entries select packages as pacman matches them

The feature SHALL resolve an entry, without its version constraint, only as `pacman` resolves a sync target: the exact
name of a package in the configured repositories, otherwise a name that packages there provide, otherwise the name of a
package group. An entry SHALL NOT be matched as a regular expression or a glob. A name that several packages provide
installs the provider `pacman` offers first, and a group name installs every package of the group.

An entry without a repository name is resolved across the repositories the image's configuration enables for
installation (`Usage`, pacman.conf(5)), in their configured order. A repository-qualified entry SHALL reach `pacman`
unchanged, so that `pacman` resolves its target, by the same steps and with the same version constraints, only in the
configured repository of that name. The feature SHALL NOT look up, enable, add, or reorder a repository itself. A
repository name that the image's configuration does not define, compared exactly and with case, SHALL fail as `pacman`
fails it: after the package databases were synchronized, before any package is installed or upgraded, with a non-zero
status and `pacman`'s message naming the repository. A package's signature is checked as for any other entry
(requirement "Repository authentication stays in effect").

A qualified entry has `pacman`'s native properties, and the feature adds no check of its own to any of them:

- It is not a pin. The version the named repository offers stands for the installation that installs it: `pacman` leaves
  a package it installs for a listed entry out of that transaction's system upgrade, also when another configured
  repository offers a newer version. An installation that finds the entry already satisfied skips it, and its full
  system upgrade then follows the configured order of the repositories, so the package is upgraded when a repository
  earlier in that order offers a newer version.
- It reaches a repository that the image's configuration synchronizes but does not enable for installation (a `Usage`
  setting with `Sync` and without `Install` or `All`, pacman.conf(5)), because `pacman` treats a named repository as
  valid for the named target, and for nothing else: the target's dependencies and every unqualified entry are still
  resolved only in the repositories enabled for installation, so a qualified entry whose dependency only that repository
  offers fails. The feature knowingly leaves the reach of the named target in place: the repository is one the image
  configures and whose signatures it checks, the qualifier names it visibly in the developer's configuration, and
  refusing it would need a second resolution beside `pacman`'s own.
- It can select a version older than the installed one. When the named repository offers the target only at an older
  version than the one installed, `pacman` replaces the installed package with that older version, as it does for an
  unqualified entry whose version constraint only an older offered version satisfies (requirement "Full system upgrade",
  which states this risk and its reason). It cannot occur while every configured repository offers one version of a
  package name, as on the images of `test/pacman-packages/compatibility.json`. What repeated installations with such an
  entry do is stated in the requirement "Installing the feature twice".

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Entry is not matched as a regular expression

- **WHEN** `packages` holds an entry containing `.` that names no package, provided name, or group, although read as a
  regular expression it would match the names of packages the repositories offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name with several providers installs the first

- **WHEN** `packages` names a name that no package has but several packages provide
- **THEN** the feature succeeds and installs the provider `pacman` offers first, and no other provider

#### Scenario: Group name installs the whole group

- **WHEN** `packages` names a package group
- **THEN** the feature succeeds and every package of the group is installed

#### Scenario: Qualified entry resolves in the named repository

- **WHEN** `packages` holds repository-qualified entries naming a package, a provided name, a group, and a package with
  a version constraint the offered version satisfies, each offered by the named repository and none of them installed
- **THEN** the feature succeeds and each named package, provider, or group member is installed from the named repository
  at the version it offers, also when a repository earlier in the configured order offers a newer version of the same
  name; their dependencies are resolved as for any other entry

#### Scenario: Qualified entry outside the named repository fails

- **WHEN** `packages` holds a repository-qualified entry whose target another configured repository offers and the named
  repository does not, alongside entries that can be installed
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Unknown repository fails

- **WHEN** `packages` holds a repository-qualified entry whose repository name the image's configuration does not
  define, alongside entries that can be installed
- **THEN** the feature exits with a non-zero status, `pacman`'s message names the repository, and none of the listed
  packages is installed

#### Scenario: Repository name is matched exactly

- **WHEN** `packages` holds a repository-qualified entry whose repository name differs from a configured repository only
  in the case of its letters
- **THEN** the feature exits with a non-zero status as for an unknown repository and installs none of the listed
  packages

#### Scenario: Qualified entry is not a pin

- **WHEN** `packages` holds a repository-qualified entry for a package already installed at the version the named
  repository offers, and a repository earlier in the configured order offers a newer version of it
- **THEN** the feature's full system upgrade selects the newer version from the earlier repository

#### Scenario: Qualified entry reaches a repository not enabled for installation

- **WHEN** `packages` holds a repository-qualified entry whose repository the image configures with a `Usage` that holds
  `Sync` and leaves out `Install`, and whose target needs no dependency that only this repository offers
- **THEN** the feature succeeds and the package is installed from that repository, under that repository's signature
  level

#### Scenario: Dependency only in a repository not enabled for installation fails

- **WHEN** `packages` holds a repository-qualified entry whose repository is not enabled for installation and whose
  target depends on a package that only this repository offers and no entry names with the repository
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Unqualified entry does not reach a repository not enabled for installation

- **WHEN** `packages` holds an unqualified entry for a package that only a repository not enabled for installation
  offers, alongside a qualified entry naming that repository
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Qualified entry offering an older version

- **WHEN** `packages` holds a repository-qualified entry whose named repository offers the target only at a version
  older than the installed one
- **THEN** the feature succeeds, the installed version is the older one the named repository offers, and the feature
  passed no argument that forces or prevents the replacement

### Requirement: Full system upgrade

Arch Linux supports only full system upgrades (https://wiki.archlinux.org/title/System_maintenance). When `packages`
names at least one package, the feature SHALL, together with installing the list, upgrade every installed package for
which the configured repositories offer a newer version and which the image's pacman configuration does not hold back,
and SHALL replace an installed package with a package of the configured repositories that declares it replaces that
package (`replaces`, https://man.archlinux.org/man/PKGBUILD.5), removing the replaced package. The system upgrade SHALL
NOT downgrade any installed package, and the feature SHALL NOT pass an argument that allows a downgrade.

A package that `pacman` installs for a listed entry of the same installation is not part of that installation's system
upgrade: it is installed at the version the entry selects (requirements "Version constraints" and "Entries select
packages as pacman matches them"). When an entry's repository qualifier or version constraint leaves only a version
older than the installed one, `pacman` therefore replaces the installed package with that older version. This needs
configured repositories that offer one package name at different versions. The feature knowingly leaves it in place and
adds no guard: the developer's configuration names the entry, refusing it would need a resolution of the feature's own
beside `pacman`'s before the one transaction, and the feature has no option that governs downgrades.

#### Scenario: Outdated installed packages are upgraded

- **WHEN** the image has installed packages older than the versions the configured repositories offer and `packages`
  names at least one package
- **THEN** after the feature succeeds, no installed package that the image's pacman configuration does not hold back is
  older than the version the repositories offer, other than a package this installation installed for a listed entry
  whose repository qualifier or version constraint selected that version

### Requirement: Repository authentication stays in effect

The feature SHALL leave `pacman`'s signature checking as the image configures it (`SigLevel`,
https://man.archlinux.org/man/pacman.conf.5) in effect: it SHALL NOT pass any option or configuration that lowers the
required signature level, trusts keys the image's keyring does not trust, skips dependency or file-conflict checks, or
allows a downgrade, and SHALL NOT itself add, remove, or change any repository, mirror, signing key, or pacman
configuration file in the image, except the packager keys that the requirement "Packager key import" allows. Files that
the packages it installs or upgrades ship or change are not the feature's changes.

The temporary configuration file of the requirement "Parallel downloads are bounded" is not a configuration file in the
image: it lies outside `/etc/pacman.conf` and `/etc/pacman.d`, exists only while the feature runs, and SHALL give
`pacman` the image's whole configuration with the one `ParallelDownloads` value replaced. Under it the repositories and
their order, their servers, every `SigLevel`, the keyring, the download user, and the sandbox settings SHALL be the ones
the image configures. A repository-qualified entry changes none of these either: its package is verified under the
signature level of the repository it names.

#### Scenario: Untrusted signature fails the install

- **WHEN** a package to install or upgrade is signed by a key that the image's keyring does not trust
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

#### Scenario: Pacman configuration is unchanged

- **WHEN** the feature has installed and upgraded packages none of which ships or changes a file under `/etc/pacman.d`
  or `/etc/pacman.conf`, and every one of them is signed by an unexpired key already in the image's keyring
- **THEN** `/etc/pacman.conf` and the files under `/etc/pacman.d`, including the mirror list and the keyring, are the
  same as before it ran

#### Scenario: Explicit parallel downloads keep the image configuration

- **WHEN** the feature runs with a non-empty `parallelDownloads` and a non-empty list
- **THEN** the configuration `pacman` resolves for the feature's call equals the one it resolves from the image's
  configuration in everything but `ParallelDownloads`, a package signed by a key the image's keyring does not trust
  still fails the installation, and `/etc/pacman.conf` and the files under `/etc/pacman.d` are the same as before the
  feature ran, under the conditions of the scenario "Pacman configuration is unchanged"

### Requirement: Installation controls are validated before changes

The feature SHALL validate `cleanup`, `parallelDownloads`, and all package entries before invoking any package-manager
command or creating any cache or temporary file. The cleanup option SHALL accept only its declared values. A non-empty
`parallelDownloads` SHALL be a canonical ASCII decimal integer string from `1` through `20`, with no sign, whitespace,
leading zero, or other character. That check is also what keeps a value from adding lines or settings of its own to the
temporary configuration file (requirement "Parallel downloads are bounded"): the feature SHALL write no value to that
file that has not passed it. Invalid options SHALL fail with status 1 and a message naming the option. With valid
options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or changing any
configuration, also without the package manager.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Parallel download boundaries are validated

- **WHEN** parallelDownloads is empty, 1, or 20, or an invalid value such as 0, 21, 01, +3, a value with whitespace
  around it, 1.5, shell text, or digits followed by a line break and a configuration setting
- **THEN** empty and the two boundaries are accepted; every invalid value fails with status 1 naming the option before a
  package-manager command runs and before a temporary file is created

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that the first installation installed for its
entries, except a package the second installation's upgrade replaces (requirement "Full system upgrade"), and SHALL
treat the second list as a first installation would, including the full system upgrade, so the second installation MAY
upgrade packages that the first installed.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later cleanup policy. Every non-empty invocation SHALL still perform the full system
upgrade.

A `parallelDownloads` value SHALL apply to the installation that sets it and to no other: a later installation without
it uses the image's setting, and finds no file an earlier one created for it.

A package installed for a repository-qualified entry is kept like any other, and a later installation that does not name
it upgrades it like any other. A second installation with the same qualified entry finds the entry satisfied and changes
nothing for it while no repository earlier in the configured order offers a newer version of that package name. When one
does, the installed version alternates between installations with the same options: the installation that finds the
named repository's version installed skips the entry and its system upgrade moves the package to the newer version, and
the next one replaces that with the named repository's version again (requirements "Entries select packages as pacman
matches them" and "Full system upgrade"). Every one of these installations succeeds. The same holds for an unqualified
entry whose version constraint only the older of several offered versions satisfies. The feature knowingly leaves this
in place: it keeps no state between installations, and each installation is the one `pacman` transaction its options
describe.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time, and the
  configured repositories replace none of the packages the first installation installed
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Constraint below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name<version` or `name=version` with a version older than the one
  installed, and no configured repository offers a version that satisfies it
- **THEN** the second installation exits with a non-zero status and the installed version stays as it was

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different cleanup values with a non-empty
  compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

#### Scenario: Download controls do not persist to the second install

- **WHEN** the first installation sets `parallelDownloads` and holds a repository-qualified entry, and the second, with
  a non-empty list, sets no `parallelDownloads` or another value
- **THEN** the second installation's `pacman` call uses the image's setting or its own value, no temporary configuration
  of the first exists, and the package the first installed for the qualified entry is still installed

#### Scenario: Same qualified entry with a newer version in an earlier repository

- **WHEN** the feature is installed three times with the same repository-qualified entry, the package is not installed
  before the first, and a repository earlier in the configured order offers a newer version of that package name
- **THEN** all three installations succeed; after the first the installed version is the named repository's, after the
  second the newer one, and after the third the named repository's again
