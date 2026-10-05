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
which the configured repositories offer a newer version and which the image's pacman configuration does not hold back,
and SHALL replace an installed package with a package of the configured repositories that declares it replaces that
package (`replaces`, https://man.archlinux.org/man/PKGBUILD.5), removing the replaced package. The feature SHALL NOT
downgrade any installed package.

#### Scenario: Outdated installed packages are upgraded

- **WHEN** the image has installed packages older than the versions the configured repositories offer and `packages`
  names at least one package
- **THEN** after the feature succeeds, no installed package that the image's pacman configuration does not hold back is
  older than the version the repositories offer

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

The feature SHALL accept an entry only when it starts with an ASCII letter or a digit and consists only of ASCII
letters, digits, the characters `@`, `.`, `_`, `+`, `-`, and `:`, and the comparison characters `<`, `>`, and `=`. When
any entry is refused, the feature SHALL exit with status 1 and a message naming that entry before it checks for
`pacman`, synchronizes the package databases, or installs anything. The feature SHALL hand every accepted entry to
`pacman` as one argument and SHALL NOT evaluate it as shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL, a path to a package file, or a `repository/name`
  prefix
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, `|`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

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

### Requirement: Image without pacman

The feature SHALL exit with status 1, with a message naming `pacman` and the distribution the feature supports, when
`packages` names at least one package, every entry is accepted, and `pacman` is not available in the image.

#### Scenario: Image without pacman fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `pacman`
- **THEN** it exits with status 1, prints a message naming `pacman` and Arch Linux, and changes nothing in the image

### Requirement: Package index refresh

The feature SHALL synchronize the package database of every configured repository before installing, and SHALL fail when
synchronizing any configured repository fails. When the image's `SigLevel` accepts an unsigned database
(`DatabaseOptional`), as it does for the Arch Linux repositories, which publish their databases unsigned, the feature
SHALL rely on TLS alone for the databases it downloads: their content, including the versions and checksums of the
packages they list, is authenticated only by TLS to the mirror the image's mirror list names, while every package stays
verified by its signature (requirement "Repository authentication stays in effect").

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
allows a downgrade, and SHALL NOT itself add, remove, or change any repository, mirror, signing key, or pacman
configuration file in the image, except the packager keys that the requirement "Packager key import" allows. Files that
the packages it installs or upgrades ship or change are not the feature's changes.

#### Scenario: Untrusted signature fails the install

- **WHEN** a package to install or upgrade is signed by a key that the image's keyring does not trust
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

#### Scenario: Pacman configuration is unchanged

- **WHEN** the feature has installed and upgraded packages none of which ships or changes a file under `/etc/pacman.d`
  or `/etc/pacman.conf`, and every one of them is signed by an unexpired key already in the image's keyring
- **THEN** `/etc/pacman.conf` and the files under `/etc/pacman.d`, including the mirror list and the keyring, are the
  same as before it ran

### Requirement: Packager key import

When a package to install or upgrade is signed by a packager key that the image's keyring lacks or holds only as
expired, the feature MAY let `pacman` fetch that key into the image's keyring under `/etc/pacman.d/gnupg`, also when the
installation then fails. The key is looked up by an e-mail address: for a missing key, the package's packager address;
for an expired key, the address of the key's first user ID in the image's keyring. With `<domain>` and `<local part>`
taken from that address, the key is looked up first in the Web Key Directory of `<domain>`, at
`https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local part>` or, when that host does not
exist, at `https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local part>`, where `<hash>` is the Web Key Directory
hash of the local part; otherwise by its fingerprint, and then by the last eight hexadecimal digits of the fingerprint,
on the default keyserver of the image's GnuPG, which is `https://keyserver.ubuntu.com/pks/lookup` from GnuPG 2.2.29
until 2.5.3, which has no default keyserver. A fetched key SHALL gain no trust of its own: a package it signs installs
only when the keys the image's keyring already trusts certify the key.

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
feature cache deletion. Cleanup SHALL NOT remove the installed-package database or unrelated paths. Custom CacheDir or
DBPath locations SHALL NOT be deleted by this feature; that limitation SHALL be documented. Package-manager or image
hooks MAY independently delete downloaded files.

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
entries, except a package the second installation's upgrade replaces (requirement "Full system upgrade"), and SHALL
treat the second list as a first installation would, including the full system upgrade, so the second installation MAY
upgrade packages that the first installed.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later cleanup policy. Every non-empty invocation SHALL still perform the full system
upgrade.

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

The feature SHALL validate `cleanup` and all package entries before invoking any package-manager command or creating any
cache. The cleanup option SHALL accept only its declared values. Invalid options SHALL fail with status 1 and a message
naming the option. With valid options and an empty package list, the feature SHALL succeed without refreshing,
upgrading, cleaning, or changing any configuration, also without the package manager.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache
