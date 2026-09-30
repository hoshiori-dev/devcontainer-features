# Spec Delta

## Purpose

The `pacman-packages` feature installs a list of system packages with `pacman` on Arch Linux images, as part of a full
system upgrade, taking them only from the package repositories the image already configures, and configures nothing
else.

Upstream sources:

- pacman manual: https://man.archlinux.org/man/pacman.8
- pacman source repository: https://gitlab.archlinux.org/pacman/pacman
- Arch Wiki, pacman: https://wiki.archlinux.org/title/Pacman

## ADDED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `pacman`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories configured in the image. It SHALL NOT install packages that a
listed package only names as optional dependencies, and SHALL NOT reinstall a listed package that is already installed
at the version the repositories offer. Whitespace around an entry and empty entries SHALL be ignored.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Optional dependencies are left out

- **WHEN** `packages` names a package with an optional dependency that nothing installed depends on
- **THEN** the listed package is installed and the optional dependency is not

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

#### Scenario: Listed package already up to date

- **WHEN** `packages` names, without a version constraint, a package that is already installed at the version the
  configured repositories offer
- **THEN** the feature succeeds and the package is neither reinstalled nor changed

### Requirement: Full system upgrade

Arch Linux supports only full system upgrades (https://wiki.archlinux.org/title/System_maintenance). When `packages`
names at least one package, the feature SHALL, together with installing the list, upgrade every installed package for
which the configured repositories offer a newer version, and SHALL replace an installed package with a package of the
configured repositories that declares it replaces that package (`replaces`, https://man.archlinux.org/man/PKGBUILD.5),
removing the replaced package. The feature SHALL NOT downgrade any installed package.

#### Scenario: Outdated installed packages are upgraded

- **WHEN** the image has installed packages older than the versions the configured repositories offer and `packages`
  names at least one package
- **THEN** after the feature succeeds, no installed package is older than the version the repositories offer

### Requirement: Empty package list

The feature SHALL succeed without changing the image when `packages` names no package.

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs, upgrades, and removes nothing, and does not synchronize the
  package databases, also on an image without `pacman`

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

The feature SHALL accept an entry only when it starts with a letter or a digit and consists only of letters, digits, the
characters `@`, `.`, `_`, `+`, `-`, and `:`, and the comparison characters `<`, `>`, and `=`. When any entry is refused,
the feature SHALL exit with status 1 and a message naming that entry before it checks for `pacman`, synchronizes the
package databases, or installs anything. The feature SHALL hand every accepted entry to `pacman` as one argument and
SHALL NOT evaluate it as shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL, a path to a package file, or a `repository/name`
  prefix
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** `packages` holds an entry with whitespace inside it or with a character outside the accepted set, such as
  `;`, `$`, `` ` ``, `*`, `?`, or `|`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries name packages exactly

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
hash of the local part; otherwise by its fingerprint on the default keyserver of the image's GnuPG, which is
`https://keyserver.ubuntu.com/pks/lookup` from GnuPG 2.2.29 until 2.5.3, which has no default keyserver. A fetched key
SHALL gain no trust of its own: a package it signs installs only when the keys the image's keyring already trusts
certify the key.

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

After installing, the feature SHALL leave neither downloaded package files, their signature files, nor sync database
files in the image.

#### Scenario: Caches are removed

- **WHEN** the feature has installed packages
- **THEN** the image holds no downloaded package or signature files and no sync database files

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that the first installation installed for its
entries, except a package the second installation's upgrade replaces (requirement "Full system upgrade"), and SHALL
treat the second list as a first installation would, including the full system upgrade, so the second installation MAY
upgrade packages that the first installed.

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
