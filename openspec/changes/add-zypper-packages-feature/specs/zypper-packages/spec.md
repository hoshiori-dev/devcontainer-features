# Spec Delta

## Purpose

The `zypper-packages` feature installs a list of system packages with `zypper` on openSUSE images, taking them only from
the package repositories the image already configures and enables, and configures nothing else.

Upstream sources:

- zypper source repository: https://github.com/openSUSE/zypper
- zypper(8) manual page, zypper 1.14.101: https://github.com/openSUSE/zypper/blob/1.14.101/doc/zypper.8.txt
- zypper manual: https://en.opensuse.org/SDB:Zypper_manual

## ADDED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `zypper`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories enabled in the image. It SHALL NOT install packages that a
listed package only recommends, and SHALL NOT upgrade installed packages other than the listed packages and what they
need. Whitespace around an entry and empty entries SHALL be ignored.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Recommended packages are left out

- **WHEN** `packages` names a package that recommends another package which nothing installed requires
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

#### Scenario: Listed package already installed at its newest version

- **WHEN** `packages` names, without a version, a package that is already installed at the newest version the enabled
  repositories offer
- **THEN** the feature succeeds and the package stays at that version

### Requirement: Empty package list

The feature SHALL succeed without changing the image when `packages` names no package.

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs and removes nothing, and does not refresh repository metadata, also
  on an image without `zypper`

### Requirement: Version and architecture qualifiers

The feature SHALL pass an entry of the form `name=edition`, `name.architecture`, or `name.architecture=edition` to
`zypper` unchanged, so that `zypper` selects that edition (a version, optionally with an epoch and a release) or that
architecture of the package. The feature SHALL NOT downgrade a package: when an entry pins an edition that the enabled
repositories offer and that is older than the installed version of that package, the installed version stays and the
entry does not fail the feature.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name=edition` for an edition the image's repositories offer, and the package is not
  installed
- **THEN** exactly that edition of the package is installed

#### Scenario: Unavailable pinned version fails

- **WHEN** `packages` holds `name=edition` for an edition the image's repositories do not offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Native architecture qualifier is installed

- **WHEN** `packages` holds `name.architecture` with the image's native architecture
- **THEN** the package is installed for that architecture

#### Scenario: Architecture the repositories do not offer fails

- **WHEN** `packages` holds `name.architecture` with an architecture for which the image's repositories offer no build
  of that package
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it starts with a letter or a digit, its name part consists only of letters,
digits, and the characters `.`, `_`, `+`, and `-`, it holds at most one `=`, the part after that `=` is not empty and
consists only of letters, digits, and the characters `.`, `_`, `+`, `~`, `:`, and `-`, and the entry does not end in
`.rpm`. When any entry is refused, the feature SHALL exit with status 1 and a message naming that entry before it checks
for `zypper`, refreshes repository metadata, or installs anything. The feature SHALL hand every accepted entry to
`zypper` as one argument and SHALL NOT evaluate it as shell code.

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

- **WHEN** `packages` holds an entry with `:` before any `=`, such as `pattern:name` or `repository:name`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** `packages` holds an entry with whitespace inside it or with a character outside the accepted set, such as
  `;`, `$`, `` ` ``, `*`, `?`, `|`, `<`, or `>`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries name packages exactly

The feature SHALL install a package for an entry only when the entry's name part, without its architecture and edition,
is the exact, case-sensitive name of a package that the enabled repositories offer, or is such a name followed by
`-version` or `-version-release`, which `zypper` reads as an edition of that package. An entry SHALL NOT be matched as a
capability that a package provides, a glob, a pattern, a patch, or a product.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name-version form selects that edition

- **WHEN** `packages` holds a package name followed by `-` and an edition of that package that the image's repositories
  offer, and the package is not installed
- **THEN** exactly that edition of the package is installed

#### Scenario: Capability is not matched

- **WHEN** `packages` names a capability that a package of the image's repositories provides but that is not itself the
  name of a package the repositories offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name in another case fails

- **WHEN** `packages` names a package that the repositories offer, written with different letter case
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Image without zypper

The feature SHALL exit with status 1, with a message naming `zypper` and the distributions the feature supports, when
`packages` names at least one package, every entry is accepted, and `zypper` is not available in the image.

#### Scenario: Image without zypper fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `zypper`
- **THEN** it exits with status 1, prints a message naming `zypper` and openSUSE, and changes nothing in the image

### Requirement: Repository metadata refresh

Before installing, the feature SHALL check the index of every repository enabled in the image and download a
repository's metadata only when none is cached or its index changed, and SHALL install from that metadata. The feature
SHALL fail, installing none of the listed packages, when refreshing any enabled repository fails, including a transient
download failure; it SHALL NOT skip a failing repository and install from the others.

#### Scenario: Missing metadata is refreshed

- **WHEN** the image holds no cached repository metadata
- **THEN** the feature downloads the metadata of every enabled repository before installing

#### Scenario: Current metadata is kept

- **WHEN** the image already holds cached metadata of every enabled repository and no repository's index has changed
- **THEN** the feature installs from the cached metadata, downloading only each repository's index file

#### Scenario: Failed refresh fails the feature

- **WHEN** refreshing the metadata of any enabled repository fails, while the other enabled repositories refresh and
  offer the listed packages
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Repository authentication stays in effect

The feature SHALL leave libzypp's signature checking (`gpgcheck` in zypp.conf(5), libzypp 17.38.16,
https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt) in effect: it SHALL NOT pass any option or
configuration that ignores signature failures, imports or trusts a new signing key, or accepts unsigned repositories or
packages, and SHALL NOT itself add, remove, or change any repository, service, trusted key, or zypp configuration file
in the image. Files that the packages it installs ship, and repository definitions that a repository index service the
image defines rewrites from its own index when `zypper` refreshes it, are not the feature's changes.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** an enabled repository's metadata is signed by a key the image does not trust
- **THEN** the feature exits with a non-zero status, trusts no new key, and installs none of the listed packages

#### Scenario: Zypp configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/zypp` or
  a signing key
- **THEN** the repository and service definitions, the files under `/etc/zypp`, and the keys the RPM database trusts are
  the same as before it ran

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input. It SHALL NOT agree to a license on the user's behalf: an
installation that needs a license confirmed fails, installing none of the listed packages.

#### Scenario: Installation runs unattended

- **WHEN** the feature runs with a non-empty `packages` and no terminal or input attached
- **THEN** it completes without waiting for input, and the listed packages are installed

### Requirement: Clean package caches

After installing, the feature SHALL leave neither downloaded package files nor cached repository metadata in the image.

#### Scenario: Caches are removed

- **WHEN** the feature has installed packages
- **THEN** the image holds no downloaded package files, no raw repository metadata, and no parsed metadata cache

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without an edition, or that a package of its list needs.

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
