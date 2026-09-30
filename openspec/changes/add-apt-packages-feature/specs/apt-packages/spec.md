# Spec Delta

## Purpose

The `apt-packages` feature installs a list of system packages with `apt-get` on Debian and Ubuntu images, taking them
only from the package repositories the image already configures, and configures nothing else.

Upstream sources:

- apt-get manual: https://manpages.debian.org/apt-get
- APT source repository: https://salsa.debian.org/apt-team/apt

## ADDED Requirements

### Requirement: Option packages

The feature SHALL accept the option `packages` as declared here, a comma-separated list of package entries in which
whitespace around an entry and empty entries are ignored, and SHALL succeed without changing the image when the list
names no package.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted packages

- **WHEN** the feature is installed without `packages`
- **THEN** the feature exits with status 0, installs and removes nothing, and does not refresh the package index, also
  on an image without `apt-get`

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs and removes nothing, and does not refresh the package index, also
  on an image without `apt-get`

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

### Requirement: Install the listed packages

The feature SHALL install, with `apt-get`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories configured in the image. It SHALL NOT install packages that a
listed package only recommends or suggests, and SHALL NOT upgrade installed packages other than the listed packages and
what they need.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Recommended packages are left out

- **WHEN** `packages` names a package that recommends another package which nothing installed depends on
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Listed package already installed at its candidate version

- **WHEN** `packages` names, without a version, a package that is already installed at the candidate version apt selects
  from the configured repositories and their pin priorities
- **THEN** the feature succeeds and the package stays at that version

### Requirement: Version and architecture qualifiers

The feature SHALL pass an entry of the form `name=version` or `name:architecture` to `apt-get` unchanged, so that
`apt-get` selects that version or that architecture of the package. An architecture qualifier selects only the image's
native architecture or a foreign architecture the image has already enabled in dpkg; the feature SHALL NOT enable an
architecture. The feature SHALL NOT allow a downgrade: a version below the installed one fails.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name=version` for a version the image's repositories offer
- **THEN** exactly that version of the package is installed

#### Scenario: Unavailable pinned version fails

- **WHEN** `packages` holds `name=version` for a version the image's repositories do not offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Native architecture qualifier is installed

- **WHEN** `packages` holds `name:architecture` with the image's native architecture
- **THEN** the package is installed for that architecture

#### Scenario: Architecture the image has not enabled fails

- **WHEN** `packages` holds `name:architecture` with a foreign architecture the image has not enabled
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and enables no architecture

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it starts with a letter or a digit, consists only of letters, digits, and
the characters `.`, `+`, `-`, `:`, `~`, and `=`, and ends in neither `-` nor `+`. When any entry is refused, the feature
SHALL exit with status 1 and a message naming that entry before it checks for `apt-get`, refreshes the package index, or
installs anything. The feature SHALL hand every accepted entry to `apt-get` as one argument and SHALL NOT evaluate it as
shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL or a path to a `.deb` file
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Removal or install marker is refused

- **WHEN** `packages` holds an entry ending in `-` or `+`
- **THEN** the feature exits with status 1, names the entry, and neither removes nor installs any package

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** `packages` holds an entry with whitespace inside it or with a character outside the accepted set, such as
  `;`, `$`, `` ` ``, `*`, `?`, or `|`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries name packages exactly

The feature SHALL install a package for an entry only when the entry's package name, without its qualifier, is the exact
name of a package known to the image's repositories. An entry SHALL NOT be matched as a regular expression, a glob, a
task, or an APT search pattern. An entry that names a virtual package installs the package that provides it when exactly
one package does, and fails when several do.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Entry is not matched as a regular expression

- **WHEN** `packages` holds an entry containing `.` that names no package, although read as a regular expression it
  would match the names of packages the repositories offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Virtual package with several providers fails

- **WHEN** `packages` names a virtual package that several packages provide
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: No version for the image's architecture

- **WHEN** `packages` names a package that the image's repositories offer for no architecture the image supports
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Image without apt-get

The feature SHALL exit with status 1, with a message naming `apt-get` and the distributions the feature supports, when
`packages` names at least one package, every entry is accepted, and `apt-get` is not available in the image.

#### Scenario: Image without apt-get fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `apt-get`
- **THEN** it exits with status 1, prints a message naming `apt-get` and Debian and Ubuntu, and changes nothing in the
  image

### Requirement: Package index refresh

The feature SHALL refresh the package index before installing only when the image holds no package index, and SHALL fail
when refreshing the index of any configured repository fails, including a transient download failure.

#### Scenario: Missing index is refreshed

- **WHEN** the image holds no package index
- **THEN** the feature refreshes the index from the image's configured repositories before installing

#### Scenario: Present index is used as is

- **WHEN** the image already holds a package index
- **THEN** the feature installs from that index without refreshing it

#### Scenario: Failed refresh fails the feature

- **WHEN** refreshing the index of any configured repository fails
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Repository authentication stays in effect

The feature SHALL leave APT's repository authentication (https://manpages.debian.org/apt-secure) in effect: it SHALL NOT
pass any option or configuration that allows unauthenticated packages, insecure, unsigned, weakly signed, or expired
repositories, or a repository whose release information changed, and SHALL NOT itself add, remove, or change any
repository, signing key, or apt configuration file in the image. Files that the packages it installs ship are not the
feature's changes.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** the feature refreshes the index and a configured repository's index cannot be verified with the keys the
  image trusts for it
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Apt configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/apt` or
  `/usr/share/keyrings`
- **THEN** the repository lists, the trusted keys, and the files under `/etc/apt` are the same as before it ran

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input: package configuration questions SHALL take their default answers,
and when an upgrade ships a new version of a configuration file that was changed in the image, the changed file SHALL be
kept.

#### Scenario: Package that asks a question installs unattended

- **WHEN** `packages` names a package whose installation asks a configuration question
- **THEN** the feature completes without a terminal or input, and the package is configured with the default answer

### Requirement: Clean package caches

After installing, the feature SHALL leave neither downloaded package files nor package index files in the image.

#### Scenario: Caches are removed

- **WHEN** the feature has installed packages
- **THEN** the image holds no downloaded package files and no package index files

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without a version, or that a package of its list needs.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Pin below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name=version` with a version older than the one installed
- **THEN** the second installation exits with a non-zero status and the installed version stays as it was
