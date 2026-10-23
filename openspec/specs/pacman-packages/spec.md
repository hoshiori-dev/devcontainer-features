# pacman-packages Specification

## Purpose

The `pacman-packages` feature installs a list of system packages with `pacman` on Arch Linux images, as part of a full
system upgrade, taking them only from the package repositories the image already configures, and configures nothing
else.

Upstream sources:

- pacman manual: https://man.archlinux.org/man/pacman.8
- pacman source repository: https://gitlab.archlinux.org/pacman/pacman
- Arch Wiki, pacman: https://wiki.archlinux.org/title/Pacman

## Requirements

### Requirement: Option packages

The feature SHALL accept the option `packages` as declared here, read it as a comma-separated list of entries in which
whitespace around an entry and empty entries are ignored, and succeed without changing the image when the list names no
package.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted packages

- **WHEN** the feature is installed without `packages`
- **THEN** the feature exits with status 0, installs, upgrades, and removes nothing, and does not synchronize the
  package databases, also on an image without `pacman`

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs, upgrades, and removes nothing, and does not synchronize the
  package databases, also on an image without `pacman`

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

### Requirement: Install the listed packages

The feature SHALL install, with `pacman`, every package named in the `packages` option, taking each package and its
dependencies only from the repositories configured in the image. It SHALL NOT install packages that a listed package
only names as optional dependencies, and SHALL NOT reinstall a listed package that is already installed at the version
the repositories offer.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Optional dependencies are left out

- **WHEN** `packages` names a package with an optional dependency that nothing installed depends on
- **THEN** the listed package is installed and the optional dependency is not

#### Scenario: Listed package already up to date

- **WHEN** `packages` names, without a version constraint, a package that is already installed at the version the
  configured repositories offer
- **THEN** the feature succeeds and the package is neither reinstalled nor changed

### Requirement: Full system upgrade

Arch Linux supports only full system upgrades (https://wiki.archlinux.org/title/System_maintenance). When `packages`
names at least one package, the feature SHALL, together with installing the list, upgrade every installed package for
which the configured repositories offer a newer version and which the image's pacman configuration does not hold back.
See also requirements "Upgrade replacements" and "System upgrade never downgrades".

#### Scenario: Outdated installed packages are upgraded

- **WHEN** the image has installed packages older than the versions the configured repositories offer and `packages`
  names at least one package
- **THEN** after the feature succeeds, no installed package that the image's pacman configuration does not hold back is
  older than the version the repositories offer, other than a package this installation installed for a listed entry
  whose repository qualifier or version constraint selected that version

### Requirement: Version constraints

The feature SHALL pass an entry of the form `name=version`, `name<version`, `name<=version`, `name>version`, or
`name>=version` to `pacman` unchanged, so that `pacman` installs the package only at a version the configured
repositories offer that satisfies the constraint. A constraint that no offered version satisfies fails; the feature
SHALL NOT install a version the configured repositories do not offer.

#### Scenario: Satisfied constraint is installed

- **WHEN** `packages` holds `name=version` or `name>=version` that the version offered by the image's repositories
  satisfies
- **THEN** the package is installed at the offered version

#### Scenario: Unsatisfied constraint fails

- **WHEN** `packages` holds a constraint that the version offered by the image's repositories does not satisfy
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it is a target or a repository-qualified target (requirements "Accepted
target syntax" and "Accepted repository qualifier syntax"). When any entry is refused, the feature SHALL exit with
status 1 and a message naming that entry before it checks for `pacman`, synchronizes the package databases, or installs
anything. The feature SHALL hand every accepted entry to `pacman` as one argument and SHALL NOT evaluate it as shell
code.

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

### Requirement: Image without pacman

The feature SHALL exit with status 1, with a message naming `pacman` and the distribution the feature supports, when
`packages` names at least one package, every entry is accepted, and `pacman` is not available in the image.

#### Scenario: Image without pacman fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `pacman`
- **THEN** it exits with status 1, prints a message naming `pacman` and Arch Linux, and changes nothing in the image

### Requirement: Package index refresh

The feature SHALL synchronize the package database of every configured repository before installing, and SHALL fail when
synchronizing any configured repository fails. Unsigned databases: requirement "Unsigned database trust".

#### Scenario: Missing database is downloaded

- **WHEN** the image holds no package database
- **THEN** the feature downloads the database of every configured repository before installing

#### Scenario: Failed refresh fails the feature

- **WHEN** synchronizing the database of any configured repository fails
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

### Requirement: Repository authentication stays in effect

The feature SHALL leave `pacman`'s signature checking as the image configures it (`SigLevel`,
https://man.archlinux.org/man/pacman.conf.5) in effect: it SHALL NOT pass any option or configuration that lowers the
required signature level, trusts keys the image's keyring does not trust, skips dependency or file-conflict checks, or
allows a downgrade. See also requirements "Image repository configuration is preserved" and "Temporary configuration
preserves trust".

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

### Requirement: Packager key import

When a package to install or upgrade is signed by a packager key that the image's keyring lacks or holds only as
expired, the feature MAY let `pacman` fetch that key into the image's keyring under `/etc/pacman.d/gnupg`, also when the
installation then fails. A fetched key SHALL gain no trust of its own: a package it signs installs only when the keys
the image's keyring already trusts certify the key. Key lookup: requirement "Packager key address".

#### Scenario: Missing certified key is fetched

- **WHEN** a package to install is signed by a packager key that the image's keyring lacks and that the keys it trusts
  certify
- **THEN** the feature succeeds, the package is installed, and the key is in the image's keyring

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input: every question `pacman` asks SHALL take `pacman`'s default answer.
A package that conflicts with an installed package SHALL fail the installation instead of removing the installed
package. When an upgrade ships a new version of a configuration file that was changed in the image, the changed file
SHALL be kept, and a new version that differs from both is written beside it as `<file>.pacnew`.

#### Scenario: Installation runs without a terminal

- **WHEN** the feature runs with a non-empty `packages`, no terminal, and no input
- **THEN** it completes without waiting for input

#### Scenario: Conflict with an installed package fails

- **WHEN** `packages` names a package that conflicts with an installed package
- **THEN** the feature exits with a non-zero status, the installed package stays installed, and none of the listed
  packages is installed

#### Scenario: Changed configuration file is kept on upgrade

- **WHEN** the image has an outdated installed package whose configuration file was changed in the image, and `packages`
  names at least one package
- **THEN** after the feature succeeds, the configuration file keeps its changed content

### Requirement: Clean package caches

After a successful installation, `cleanup=all` SHALL remove downloaded packages, their detached signatures, and sync
database files from the default directories /var/cache/pacman/pkg and /var/lib/pacman/sync. `packages` SHALL remove
package and signature files from the default package directory but keep sync databases; `none` SHALL perform no explicit
feature cache deletion. Cleanup SHALL NOT remove the installed-package database or unrelated paths.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the default package and sync directories hold no downloaded package, signature, or sync database files

#### Scenario: Only package files are cleaned

- **WHEN** cleanup=packages with usable metadata and package files present in the managed cache after installation
- **THEN** package files are removed from the managed cache and usable metadata remains

#### Scenario: Feature cleanup is disabled

- **WHEN** cleanup=none and the native package manager and image hooks retain downloads
- **THEN** the feature leaves cached package files and metadata in place

#### Scenario: Custom cache paths are outside the cleanup bound

- **WHEN** pacman.conf directs CacheDir or DBPath to a non-default location
- **THEN** feature cleanup affects only the documented default directories and leaves files in the configured
  non-default locations alone

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that the first installation installed for its
entries, except a package the second installation's upgrade replaces (requirements "Full system upgrade" and "Upgrade
replacements"), and SHALL treat the second list as a first installation would, including the full system upgrade, so the
second installation MAY upgrade packages that the first installed. See also requirement "Later installations use their
own controls".

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

### Requirement: Option cleanup

The feature SHALL accept the option `cleanup` as declared here.

| Field   | Value                       |
| ------- | --------------------------- |
| Type    | `string`                    |
| Default | `"all"`                     |
| Enum    | `["all","packages","none"]` |

#### Scenario: Omitted cleanup

- **WHEN** `cleanup` is omitted
- **THEN** the feature uses `"all"` as specified by the requirements below

### Requirement: Installation controls are validated before changes

The feature SHALL validate `cleanup`, `parallelDownloads`, and all package entries before invoking any package-manager
command or creating any cache or temporary file. The cleanup option SHALL accept only its declared values. Invalid
options SHALL fail with status 1 and a message naming the option. With valid options and an empty package list, the
feature SHALL succeed without refreshing, upgrading, cleaning, or changing any configuration, also without the package
manager.

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
timeouts, or for a proxy, because `pacman` has no bounded native control the feature could set for one call. The image's
configuration and `pacman`'s own behavior apply to each of them, and the feature SHALL document that it controls none.
What the feature leaves untouched: requirement "Download behavior stays native".

#### Scenario: Held database lock fails the installation

- **WHEN** `packages` names at least one package and the lock file of the image's package database already exists
- **THEN** the feature exits with a non-zero status after its one `pacman` call, installs and upgrades nothing, and the
  lock file is still there

#### Scenario: Build environment proxy reaches pacman unchanged

- **WHEN** the environment the feature runs in sets proxy variables
- **THEN** the environment `pacman` receives holds those variables with the same values, and the feature has neither
  added, changed, nor removed a proxy setting

### Requirement: Upgrade replacements

When `packages` names at least one package, the feature SHALL, together with installing the list, replace an installed
package with a package of the configured repositories that declares it replaces that package (`replaces`,
https://man.archlinux.org/man/PKGBUILD.5), removing the replaced package (requirement "Full system upgrade").

#### Scenario: Declared replacement during upgrade

- **WHEN** `packages` names at least one package and a package of the configured repositories declares that it replaces
  an installed package
- **THEN** after the feature succeeds, the replacing package is installed and the replaced package is not

### Requirement: System upgrade never downgrades

The system upgrade SHALL NOT downgrade any installed package, and the feature SHALL NOT pass an argument that allows a
downgrade. A package that `pacman` installs for a listed entry of the same installation is not part of that
installation's system upgrade: it is installed at the version the entry selects (requirements "Version constraints" and
"Entries select packages as pacman matches them").

#### Scenario: Newer installed package is kept

- **WHEN** `packages` names at least one package, an installed package that no entry names is newer than every version
  the configured repositories offer, and no package of them declares that it replaces it
- **THEN** after the feature succeeds, that package is still installed at its version

### Requirement: Listed entries may select older versions

When an entry's repository qualifier or version constraint leaves only a version older than the installed one, `pacman`
therefore replaces the installed package with that older version (requirement "System upgrade never downgrades"), and
the feature SHALL pass no argument that forces or prevents the replacement. This needs configured repositories that
offer one package name at different versions.

#### Scenario: Constraint selects an older offered version

- **WHEN** `packages` holds an unqualified entry whose version constraint only an offered version older than the
  installed one satisfies
- **THEN** the feature succeeds, the installed version is that older one, and the feature passed no argument that forces
  or prevents the replacement

### Requirement: Older version selection is an accepted risk

The feature SHALL NOT pass an argument that allows a downgrade (requirement "System upgrade never downgrades"). For the
replacement by an older version of the requirement "Listed entries may select older versions", the feature knowingly
leaves it in place and adds no guard: the developer's configuration names the entry, refusing it would need a resolution
of the feature's own beside `pacman`'s before the one transaction, and the feature has no option that governs
downgrades.

#### Scenario: Older version selection needs no downgrade argument

- **WHEN** `packages` holds an entry whose repository qualifier or version constraint leaves only a version older than
  the installed one
- **THEN** the feature succeeds with the older version installed and has passed `pacman` no argument that allows a
  downgrade

### Requirement: Accepted target syntax

The feature SHALL accept an entry without `/` only when it is a target. A target starts with an ASCII letter or a digit
and consists only of ASCII letters, digits, the characters `@`, `.`, `_`, `+`, `-`, and `:`, and the comparison
characters `<`, `>`, and `=`.

#### Scenario: Target starting with another character is refused

- **WHEN** `packages` holds an entry without `/` that starts with a character other than an ASCII letter or a digit,
  such as `_` or `.`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

### Requirement: Accepted repository qualifier syntax

The feature SHALL accept an entry holding `/` only when it is a repository-qualified target: a repository name, exactly
one `/`, and a target, where the repository name starts with an ASCII letter or a digit and consists only of ASCII
letters, digits, and the characters `.`, `_`, `+`, and `-`. Whether a repository of the given name exists is not part of
this validation (requirement "Entries select packages as pacman matches them").

#### Scenario: Empty qualified target

- **WHEN** `packages` holds an entry made of a repository name followed by `/` and no target
- **THEN** the feature exits with status 1, names the entry, names the `repository/target` form, and installs nothing

### Requirement: Slash validation diagnostics

Every entry holding `/` that is not a repository-qualified target SHALL be refused, and the message SHALL tell two cases
apart: an entry that starts with `/` or `.`, holds `://`, or holds more than one `/` is refused as a path or URL, which
the feature never installs from; any other refused entry holding `/` is refused as a malformed repository qualifier,
with the accepted form named.

#### Scenario: Malformed qualifier diagnostic

- **WHEN** `packages` holds an entry with exactly one `/` that neither starts with `/` or `.` nor holds `://`, and whose
  repository part holds a character outside its accepted set
- **THEN** the feature exits with status 1, names the entry, names the `repository/target` form, and installs nothing

### Requirement: Relative paths resembling qualified targets

The feature knowingly leaves one case to `pacman`: a relative path with a single `/` and no leading `.` has the shape of
a repository-qualified target and is not told apart from one, so the feature SHALL hand it to `pacman` as one argument
like any accepted entry. It reaches `pacman` as a sync target, which `pacman` never reads as a file or URL, and fails
there as an unknown repository unless the image configures a repository of that name.

#### Scenario: Relative path shaped as a qualifier

- **WHEN** `packages` holds an entry `directory/package` whose `directory` is no repository the image's configuration
  defines
- **THEN** the feature exits with a non-zero status, `pacman`'s message names the repository, and none of the listed
  packages is installed

### Requirement: Qualified target resolution

An entry without a repository name is resolved across the repositories the image's configuration enables for
installation (`Usage`, pacman.conf(5)), in their configured order. A repository-qualified entry SHALL reach `pacman`
unchanged, so that `pacman` resolves its target, by the same steps and with the same version constraints, only in the
configured repository of that name. The feature SHALL NOT look up, enable, add, or reorder a repository itself.

#### Scenario: Target absent from the named repository

- **WHEN** `packages` holds a repository-qualified entry whose target only another configured repository offers
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Unknown repositories fail after synchronization

A repository name that the image's configuration does not define, compared exactly and with case, SHALL fail as `pacman`
fails it: after the package databases were synchronized, before any package is installed or upgraded, with a non-zero
status and `pacman`'s message naming the repository. A qualified entry's package signature is checked as for any other
entry (requirement "Repository authentication stays in effect").

#### Scenario: Case mismatch in repository name

- **WHEN** `packages` holds a repository-qualified entry whose repository name differs from a configured repository only
  in the case of its letters
- **THEN** the feature exits with a non-zero status after synchronizing the package databases, `pacman`'s message names
  the repository, and no package is installed or upgraded

### Requirement: Qualified entries keep native properties

The feature SHALL hand a repository-qualified entry to `pacman` unchanged (requirement "Qualified target resolution"). A
qualified entry has `pacman`'s native properties, and the feature adds no check of its own to any of them: those of the
requirements "Qualified targets are not pins", "Satisfied qualified entries follow the system upgrade", "Explicit
repository reach", and "Qualified entries may select older versions".

#### Scenario: Qualified entry passes unchanged

- **WHEN** `packages` holds a repository-qualified entry with a version constraint
- **THEN** the feature hands `pacman` the entry unchanged as one argument

### Requirement: Qualified targets are not pins

A qualified entry, which SHALL reach `pacman` unchanged, is not a pin. The version the named repository offers stands
for the installation that installs it: `pacman` leaves a package it installs for a listed entry out of that
transaction's system upgrade, also when another configured repository offers a newer version.

#### Scenario: Named repository version stands for the installing installation

- **WHEN** `packages` holds a repository-qualified entry for a package that is not installed, the named repository
  offers it, and a repository earlier in the configured order offers a newer version of it
- **THEN** the feature succeeds and the package is installed at the version the named repository offers

### Requirement: Satisfied qualified entries follow the system upgrade

The feature SHALL hand a repository-qualified entry to `pacman` unchanged (requirement "Qualified target resolution").
An installation that finds the entry already satisfied skips it, and its full system upgrade then follows the configured
order of the repositories, so the package is upgraded when a repository earlier in that order offers a newer version.

#### Scenario: Satisfied qualified entry can be upgraded

- **WHEN** `packages` holds a repository-qualified entry for a package already installed at the version the named
  repository offers, and a repository earlier in the configured order offers a newer version of it
- **THEN** the feature succeeds and the package is installed at the newer version from the earlier repository

### Requirement: Explicit repository reach

A qualified entry, which SHALL reach `pacman` unchanged, reaches a repository that the image's configuration
synchronizes but does not enable for installation (a `Usage` setting with `Sync` and without `Install` or `All`,
pacman.conf(5)), because `pacman` treats a named repository as valid for the named target, and for nothing else
(requirement "Explicit repository reach stops at the target").

#### Scenario: Qualified entry installs from a repository only synchronized

- **WHEN** `packages` holds a repository-qualified entry whose repository the image configures with a `Usage` that holds
  `Sync` and leaves out `Install`, and whose target needs no dependency that only this repository offers
- **THEN** the feature succeeds and the package is installed from that repository

### Requirement: Explicit repository reach stops at the target

The feature SHALL hand every accepted entry to `pacman` as one argument (requirement "Entries are validated before
anything changes"). Under the requirement "Explicit repository reach", the target's dependencies and every unqualified
entry are still resolved only in the repositories enabled for installation, so a qualified entry whose dependency only
that repository offers fails.

#### Scenario: Dependency outside installation-enabled repositories

- **WHEN** `packages` holds a repository-qualified entry whose repository is not enabled for installation and whose
  target depends on a package that only this repository offers and no entry names with the repository
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Explicit repository reach is an accepted risk

The feature SHALL NOT refuse a qualified entry for the repository it names (requirement "Explicit repository reach").
The feature knowingly leaves the reach of the named target in place: the repository is one the image configures and
whose signatures it checks, the qualifier names it visibly in the developer's configuration, and refusing it would need
a second resolution beside `pacman`'s own.

#### Scenario: Named repository not enabled for installation is reached

- **WHEN** `packages` holds a repository-qualified entry whose repository the image configures with a `Usage` that holds
  `Sync` and leaves out `Install`, and whose target needs no dependency that only this repository offers
- **THEN** the feature succeeds and the package is installed from that repository

### Requirement: Qualified entries may select older versions

A qualified entry can select a version older than the installed one. When the named repository offers the target only at
an older version than the one installed, `pacman` replaces the installed package with that older version, as it does for
an unqualified entry whose version constraint only an older offered version satisfies, and the feature SHALL pass no
argument that forces or prevents the replacement (requirement "Older version selection is an accepted risk" states this
risk and its reason).

#### Scenario: Qualified entry selects an older version

- **WHEN** `packages` holds a repository-qualified entry whose named repository offers the target only at a version
  older than the installed one
- **THEN** the feature succeeds and the installed version is the older one the named repository offers

### Requirement: Older qualified versions need several offered versions

The older-version selection of the requirement "Qualified entries may select older versions" cannot occur while every
configured repository offers one version of a package name, as on the images of
`test/pacman-packages/compatibility.json`. A qualified entry SHALL still reach `pacman` unchanged. What repeated
installations with such an entry do is stated in the requirements "Qualified entries on later installations" and
"Repeated target selection can alternate versions".

#### Scenario: Repositories offer one version per package

- **WHEN** every configured repository offers one version of a package name and `packages` holds a repository-qualified
  entry that the named repository offers
- **THEN** the feature succeeds and the package is installed at the version the named repository offers

### Requirement: Unsigned database trust

When the image's `SigLevel` accepts an unsigned database (`DatabaseOptional`), as it does for the Arch Linux
repositories, which publish their databases unsigned, the feature SHALL rely on TLS alone for the databases it
downloads: their content, including the versions and checksums of the packages they list, is authenticated only by TLS
to the mirror the image's mirror list names, while every package stays verified by its signature (requirement
"Repository authentication stays in effect").

#### Scenario: Unsigned database under DatabaseOptional

- **WHEN** the image's `SigLevel` accepts an unsigned database, a configured repository publishes its database unsigned,
  and a package to install is signed by a key the image's keyring does not trust
- **THEN** the feature synchronizes that database, exits with a non-zero status, and installs and upgrades none of the
  packages

### Requirement: Image repository configuration is preserved

The feature SHALL NOT itself add, remove, or change any repository, mirror, signing key, or pacman configuration file in
the image, except the packager keys that the requirement "Packager key import" allows. Files that the packages it
installs or upgrades ship or change are not the feature's changes.

#### Scenario: No package changes configuration

- **WHEN** the feature has installed and upgraded packages none of which ships or changes a file under `/etc/pacman.d`
  or `/etc/pacman.conf`, and every one of them is signed by an unexpired key already in the image's keyring
- **THEN** the repositories, the mirror list, and the keyring of the image are the same as before it ran

### Requirement: Temporary configuration preserves trust

The temporary configuration file of the requirement "Temporary download configuration" is not a configuration file in
the image: it lies outside `/etc/pacman.conf` and `/etc/pacman.d`, exists only while the feature runs, and SHALL give
`pacman` the image's whole configuration with the one `ParallelDownloads` value replaced. Under it the repositories and
their order, their servers, every `SigLevel`, the keyring, the download user, and the sandbox settings SHALL be the ones
the image configures.

#### Scenario: Untrusted package with explicit downloads

- **WHEN** the feature runs with a non-empty `parallelDownloads` and a non-empty list, and a package to install is
  signed by a key the image's keyring does not trust
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

### Requirement: Qualified packages keep their repository signature level

The feature SHALL hand a repository-qualified entry to `pacman` unchanged (requirement "Qualified target resolution"),
and the entry changes none of the settings of the requirement "Temporary configuration preserves trust" either: its
package is verified under the signature level of the repository it names.

#### Scenario: Qualified package under its repository's signature level

- **WHEN** `packages` holds a repository-qualified entry whose named repository's `SigLevel` requires package signatures
  and whose package is signed by a key the image's keyring does not trust
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

### Requirement: Packager key address

A key that the requirement "Packager key import" lets `pacman` fetch SHALL gain no trust of its own. The key is looked
up by an e-mail address: for a missing key, the package's packager address; for an expired key, the address of the key's
first user ID in the image's keyring.

#### Scenario: Fetched uncertified key gains no trust

- **WHEN** a package to install is signed by a packager key that the image's keyring lacks and that no key it trusts
  certifies
- **THEN** the feature exits with a non-zero status and the package is not installed

### Requirement: Packager Web Key Directory lookup

Such a key SHALL gain no trust of its own (requirement "Packager key import"). With `<domain>` and `<local part>` taken
from the address of "Packager key address", the key is looked up first in the Web Key Directory of `<domain>`, at
`https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local part>` or, when that host does not
exist, at `https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local part>`, where `<hash>` is the Web Key Directory
hash of the local part.

#### Scenario: Key from a Web Key Directory gains no trust

- **WHEN** a package to install is signed by a packager key that the image's keyring lacks, the packager's Web Key
  Directory serves it, and no key the image's keyring trusts certifies it
- **THEN** the feature exits with a non-zero status and the package is not installed

### Requirement: Packager keyserver fallback

A key that the requirement "Packager key import" lets `pacman` fetch SHALL gain no trust of its own. Otherwise than by
the Web Key Directory (requirement "Packager Web Key Directory lookup"), the key is looked up by its fingerprint, and
then by the last eight hexadecimal digits of the fingerprint, on the default keyserver of the image's GnuPG, which is
`https://keyserver.ubuntu.com/pks/lookup` from GnuPG 2.2.29 until 2.5.3, which has no default keyserver.

#### Scenario: Key from a keyserver gains no trust

- **WHEN** a package to install is signed by a packager key that the image's keyring lacks, a keyserver serves it, and
  no key the image's keyring trusts certifies it
- **THEN** the feature exits with a non-zero status and the package is not installed

### Requirement: Custom cache paths remain unmanaged

Custom CacheDir or DBPath locations SHALL NOT be deleted by this feature; that limitation SHALL be documented.
Package-manager or image hooks MAY independently delete downloaded files.

#### Scenario: Custom database path

- **WHEN** pacman.conf directs DBPath to a non-default location and `cleanup=all`
- **THEN** feature cleanup leaves the files in that location alone

### Requirement: Later installations use their own controls

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later cleanup policy. Every non-empty invocation SHALL still perform the full system
upgrade. A `parallelDownloads` value SHALL apply to the installation that sets it and to no other: a later installation
without it uses the image's setting, and finds no file an earlier one created for it.

#### Scenario: Later invocation omits downloads override

- **WHEN** an installation sets `parallelDownloads` and a later installation with a non-empty list sets none
- **THEN** the later `pacman` call uses the image's setting and no file the earlier installation created for it exists

### Requirement: Qualified entries on later installations

A later installation SHALL keep a package installed for a repository-qualified entry like any other (requirement
"Installing the feature twice"), and a later installation that does not name it upgrades it like any other. A second
installation with the same qualified entry finds the entry satisfied and changes nothing for it while no repository
earlier in the configured order offers a newer version of that package name.

#### Scenario: Same qualified entry without a newer version

- **WHEN** the feature is installed twice with the same repository-qualified entry and no repository earlier in the
  configured order offers a newer version of that package name
- **THEN** both installations succeed and the second leaves the package as the first installed it

### Requirement: Repeated target selection can alternate versions

Each installation SHALL treat its list as a first would (requirement "Installing the feature twice"). When a repository
earlier in the configured order offers a newer version of a qualified entry's package name, the installed version
alternates between installations with the same options, by the steps of the requirement "Alternation steps of a
qualified entry". Every one of these installations succeeds.

#### Scenario: Three installations alternate selected versions

- **WHEN** the feature is installed three times with the same repository-qualified entry, the package is not installed
  before the first, and a repository earlier in the configured order offers a newer version of that package name
- **THEN** all three installations succeed and the installed version is the named repository's, the newer one, and the
  named repository's again, in turn

### Requirement: Alternation steps of a qualified entry

Each installation SHALL treat its list as a first would. In the alternation of the requirement "Repeated target
selection can alternate versions", the installation that finds the named repository's version installed skips the entry
and its system upgrade moves the package to the newer version, and the next one replaces that with the named
repository's version again (requirements "Entries select packages as pacman matches them" and "Full system upgrade").

#### Scenario: Installed named repository version moves to the newer one

- **WHEN** `packages` holds a repository-qualified entry for a package already installed at the version the named
  repository offers, and a repository earlier in the configured order offers a newer version of it
- **THEN** the feature's full system upgrade selects the newer version from the earlier repository

### Requirement: Alternating versions are an accepted risk

A later installation SHALL treat its list as a first installation would (requirement "Installing the feature twice").
What the requirement "Repeated target selection can alternate versions" states holds the same for an unqualified entry
whose version constraint only the older of several offered versions satisfies. The feature knowingly leaves this in
place: it keeps no state between installations, and each installation is the one `pacman` transaction its options
describe.

#### Scenario: Repeated older constraint passes no downgrade argument

- **WHEN** the feature is installed repeatedly with the same unqualified entry whose version constraint only the older
  of two offered versions satisfies
- **THEN** no installation passes `pacman` an argument that allows a downgrade

### Requirement: Accepted parallel download values

A non-empty `parallelDownloads` SHALL be a canonical ASCII decimal integer string from `1` through `20`, with no sign,
whitespace, leading zero, or other character. That check is also what keeps a value from adding lines or settings of its
own to the temporary configuration file (requirement "Temporary download configuration"): the feature SHALL write no
value to that file that has not passed it.

#### Scenario: Newline in parallel download value

- **WHEN** `parallelDownloads` holds digits followed by a line break and a configuration setting
- **THEN** the feature exits with status 1 naming the option before a package-manager command runs and before a
  temporary file is created

### Requirement: Temporary download configuration

`pacman` takes `ParallelDownloads` from its configuration alone, so for a non-empty `parallelDownloads` and a non-empty
package list the feature SHALL create a temporary configuration file outside `/etc` that holds no setting other than an
inclusion of `/etc/pacman.conf`, the configuration `pacman` reads by default on Arch Linux, and the one
`ParallelDownloads` setting, and SHALL hand that file to `pacman` for the call (requirement "Parallel downloads are
bounded").

#### Scenario: Explicit value uses a temporary configuration

- **WHEN** `parallelDownloads` holds an accepted value and `packages` names at least one package
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads` and the
  repositories of the image

### Requirement: Download setting placement

The `ParallelDownloads` setting of the requirement "Temporary download configuration" SHALL be placed so that `pacman`
reads it in the options section and after everything the inclusion brings, whichever section the image's configuration
ends in.

#### Scenario: Included configuration ends in a repository

- **WHEN** `parallelDownloads` holds an accepted value, `packages` names at least one package, and the last section of
  the image's `/etc/pacman.conf` is a repository section
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads` and the
  repositories of the image

### Requirement: Download configuration lifecycle

The feature SHALL remove the file of the requirement "Temporary download configuration", and any directory it created
for it, when it exits, whether the installation succeeded or failed. It SHALL create no such file for an empty value or
an empty list.

#### Scenario: Failed installation cleans temporary files

- **WHEN** the feature has run with a non-empty `parallelDownloads` and a non-empty list, and the installation failed in
  `pacman`
- **THEN** the temporary configuration file and any directory the feature created for it no longer exist

### Requirement: Effective parallel download value is confirmed

Before the package databases are synchronized, the feature SHALL confirm with `pacman-conf`
(https://man.archlinux.org/man/pacman-conf.8), the tool that reports the configuration `pacman` resolves, that the
configuration resolved from the temporary file carries the requested value. It SHALL NOT continue with the image's
value, and SHALL NOT run `pacman` with a configuration that lacks the image's repositories.

#### Scenario: Resolved value differs

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `pacman-conf` reports for the
  temporary configuration a `ParallelDownloads` value other than the requested one
- **THEN** the feature exits with status 1, names `parallelDownloads`, and synchronizes, installs, and upgrades nothing

### Requirement: Unconfirmed parallel download value fails

When `pacman-conf` reports another value or none, fails, or cannot be run, whatever the cause, a missing or unreadable
`/etc/pacman.conf` included, the feature SHALL exit with status 1 and a message naming `parallelDownloads`, without
synchronizing, installing, or upgrading anything (requirement "Effective parallel download value is confirmed").

#### Scenario: Missing pacman-conf fails closed

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `pacman-conf` cannot be run
- **THEN** the feature exits with status 1, names `parallelDownloads`, and synchronizes, installs, and upgrades nothing

### Requirement: Parallel download accepted risks

The feature knowingly leaves three things in place. `pacman` writes its command line to `/var/log/pacman.log`, so the
log keeps the path of the removed temporary file; the feature does not edit the log, and SHALL still remove the file
(requirement "Download configuration lifecycle"). An image whose `pacman` reads its default configuration from another
path than `/etc/pacman.conf` is not supported with a non-empty value. The third is in the requirement "Parallel download
range is kept small".

#### Scenario: Temporary file is removed although logged

- **WHEN** the feature has run with a non-empty `parallelDownloads` and a non-empty list
- **THEN** the temporary configuration file no longer exists after the feature exits

### Requirement: Parallel download range is kept small

`pacman` has no retry that would absorb a mirror limiting many simultaneous connections, and the feature SHALL NOT
repeat a `pacman` call that failed (requirement "Download behavior stays native"), so a high value can fail an
installation that a lower one completes; the accepted range (requirement "Accepted parallel download values") is kept
small for that reason.

#### Scenario: Failed call with explicit parallel downloads is not repeated

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and the feature's `pacman` call
  fails
- **THEN** the feature exits with a non-zero status without calling `pacman` again

### Requirement: Download behavior stays native

The feature SHALL NOT set, change, or unset a proxy or any other environment variable for `pacman`, SHALL NOT pass an
argument or setting that changes retries, lock handling, or timeouts, SHALL NOT replace `pacman`'s downloader, SHALL NOT
repeat a `pacman` call that failed, and SHALL neither wait for nor remove a package database lock that is already held.

#### Scenario: Failed call is not repeated

- **WHEN** `packages` names at least one package and the feature's one `pacman` call fails
- **THEN** the feature exits with a non-zero status without calling `pacman` again
