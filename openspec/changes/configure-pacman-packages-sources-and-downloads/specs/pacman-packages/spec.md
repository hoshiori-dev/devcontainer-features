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
feature SHALL create a temporary configuration file outside `/etc` that holds nothing but an inclusion of
`/etc/pacman.conf`, the configuration `pacman` reads by default on Arch Linux, followed by the one `ParallelDownloads`
setting, and SHALL hand that file to `pacman` for the call. The feature SHALL remove the file, and any directory it
created for it, when it exits, whether the installation succeeded or failed. It SHALL create no such file for an empty
value or an empty list.

Before the package databases are synchronized, the feature SHALL confirm that the configuration `pacman` resolves from
the temporary file carries the requested value. When it does not, because `/etc/pacman.conf` is missing or unreadable,
because the `pacman` found does not know the setting, or because the value cannot be confirmed, the feature SHALL exit
with status 1 and a message naming `parallelDownloads`, without synchronizing, installing, or upgrading anything. It
SHALL NOT continue with the image's value, and SHALL NOT run `pacman` with a configuration that lacks the image's
repositories.

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
that changes retries, lock handling, or timeouts, and SHALL NOT replace `pacman`'s downloader. What applies is the
image's configuration and `pacman`'s own behavior: a download that fails is tried again only on the next server the
image lists for that repository; a package database lock that is already held fails the installation at once, and the
feature SHALL neither wait for the lock nor remove it; proxy variables of the build environment reach `pacman` as they
are. These limits SHALL be documented.

#### Scenario: Held database lock fails the installation

- **WHEN** `packages` names at least one package and the lock file of the image's package database already exists
- **THEN** the feature exits with a non-zero status without waiting, installs and upgrades nothing, and the lock file is
  still there

#### Scenario: Build environment proxy reaches pacman unchanged

- **WHEN** the environment the feature runs in sets a proxy variable that `pacman`'s downloader honors
- **THEN** `pacman` downloads through that proxy, and the feature has neither added, changed, nor removed a proxy
  setting

#### Scenario: Failing server falls back to the next one

- **WHEN** the first server the image lists for a repository refuses the connection and a later one answers
- **THEN** the feature succeeds with the downloads taken from the later server

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

An entry without a repository name is resolved across all repositories the image configures, in their configured order.
A repository-qualified entry SHALL reach `pacman` unchanged, so that `pacman` resolves its target, by the same steps and
with the same version constraints, only in the configured repository of that name. The feature SHALL NOT look up,
enable, add, or reorder a repository itself. A repository name that the image's configuration does not define, compared
exactly and with case, SHALL fail as `pacman` fails it: after the package databases were synchronized, before any
package is installed or upgraded, with a non-zero status and `pacman`'s message naming the repository. A package's
signature is checked as for any other entry (requirement "Repository authentication stays in effect").

A qualified entry has `pacman`'s native properties, and the feature adds no check of its own to any of them:

- It is not a pin. The full system upgrade of the same and of every later installation follows the configured order of
  the repositories, so a package installed from a named repository is upgraded when another configured repository offers
  a newer version.
- It reaches a repository that the image's configuration does not enable for installation (a `Usage` setting without
  `Install` or `All`, pacman.conf(5)), because `pacman` treats a named repository as valid for that target. The feature
  knowingly leaves this in place: the repository is one the image configures and whose signatures it checks, the
  qualifier names it visibly in the developer's configuration, and refusing it would need a second resolution beside
  `pacman`'s own.
- It can select a version older than the installed one. When the named repository offers the target only at an older
  version than the one installed, `pacman` selects that older version to replace the installed package, as it does for
  an unqualified entry whose version constraint only an older offered version satisfies. The feature knowingly leaves
  this in place for an explicit entry and adds no guard; it cannot occur while every configured repository offers one
  version of a package name, as on the images of `test/pacman-packages/compatibility.json`.

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
  a version constraint the offered version satisfies, each offered by the named repository
- **THEN** the feature succeeds and each is installed from the named repository, also when a repository earlier in the
  configured order offers a package of the same name

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

- **WHEN** `packages` holds a repository-qualified entry whose repository the image configures with a `Usage` that
  leaves out installation
- **THEN** `pacman` resolves the target in that repository, under that repository's signature level

#### Scenario: Qualified entry offering an older version

- **WHEN** `packages` holds a repository-qualified entry whose named repository offers the target only at a version
  older than the installed one
- **THEN** the entry reaches `pacman` unchanged, `pacman` selects the older version to replace the installed one, and
  the feature neither refuses the entry nor passes an argument that forces or prevents the replacement

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
it uses the image's setting, and finds no file an earlier one created for it. A package installed for a
repository-qualified entry is kept like any other, and a later installation's upgrade treats it like any other
(requirement "Entries select packages as pacman matches them").

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time, and the
  configured repositories replace none of the packages the first installation installed
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Constraint below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name<version` or `name=version` with a version older than the one
  installed
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
