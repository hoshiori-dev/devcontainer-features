# Spec Delta

## Purpose

The `apk-packages` feature installs a list of system packages with `apk` on Alpine Linux images, taking them only from
the package repositories the image already configures, and configures nothing else.

Upstream sources:

- Alpine Package Keeper wiki page: https://wiki.alpinelinux.org/wiki/Alpine_Package_Keeper
- apk-tools source repository: https://gitlab.alpinelinux.org/alpine/apk-tools

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
- **THEN** the feature exits with status 0, installs and removes nothing, and fetches no package index, also on an image
  without `apk`

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs and removes nothing, and fetches no package index, also on an image
  without `apk`

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

### Requirement: Install the listed packages

The feature SHALL install, with `apk`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories configured in the image, and SHALL leave each entry recorded in apk's
world (`/etc/apk/world`). Besides the listed packages and their dependencies, it SHALL install only the packages that
apk selects automatically because all of their install-if conditions are met. It SHALL NOT change the version of an
installed package unless an entry's constraint or a package it installs requires another version of it.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0, both packages, with their dependencies, are installed, and each entry is a
  line of apk's world

#### Scenario: Install-if packages follow their conditions

- **WHEN** `packages` names a package whose documentation subpackage the repositories offer, together with the `docs`
  meta package
- **THEN** the documentation subpackage is installed as well

#### Scenario: Listed package already installed stays at its version

- **WHEN** `packages` names, without a constraint, a package that is installed at a version older than the one the
  repositories offer, and no other listed package requires a newer version of it
- **THEN** the feature succeeds and the package stays at its installed version

### Requirement: Version constraints and repository tags

The feature SHALL pass an entry of the form `name=version`, `name~version`, or `name@tag` to `apk` unchanged, so that
`apk` selects a version that equals the version, starts with it, or comes from the repository the image configures with
that tag, and keeps the entry as a constraint in its world for later apk operations. A tag selects only a repository the
image already configures with that tag; the feature SHALL NOT add a repository or a tag. When the installed version of a
package does not satisfy its constraint, apk replaces it with a version that does, which can be a lower one; when the
repositories offer none, the feature fails.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name=version` for a version the image's repositories offer
- **THEN** exactly that version of the package is installed and apk's world holds the entry `name=version`

#### Scenario: Prefix constraint is installed

- **WHEN** `packages` holds `name~prefix` with a prefix of a version the image's repositories offer
- **THEN** a version of the package that starts with that prefix is installed

#### Scenario: Configured tag selects its repository

- **WHEN** the image configures a repository with a tag, and `packages` holds `name@tag` for a package that only this
  repository offers
- **THEN** the package is installed from that repository and apk's world holds the entry `name@tag`

#### Scenario: Unavailable pinned version fails

- **WHEN** `packages` holds `name=version` for a version the image's repositories do not offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Tag the image does not configure fails

- **WHEN** `packages` holds `name@tag` with a tag that no repository configured in the image carries
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and leaves the repository
  configuration unchanged

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it starts with a letter or a digit and consists only of letters, digits, and
the characters `.`, `_`, `+`, `-`, `:`, `~`, `=`, and `@`. When any entry is refused, the feature SHALL exit with status
1 and a message naming that entry before it checks for `apk`, fetches any package index, or installs anything. The
feature SHALL hand every accepted entry to `apk` as one argument and SHALL NOT evaluate it as shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL or a path to an `.apk` file
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Conflict marker is refused

- **WHEN** `packages` holds an entry starting with `!`
- **THEN** the feature exits with status 1, names the entry, and neither removes nor installs any package

#### Scenario: Range operators are refused

- **WHEN** `packages` holds an entry containing `<` or `>`, such as `name>=version`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** `packages` holds an entry with whitespace inside it or with a character outside the accepted set, such as
  `;`, `$`, `` ` ``, `*`, `?`, or `|`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries name packages exactly

The feature SHALL install a package for an entry only when the entry's name, without its constraint or tag, is the exact
name of a package the image's repositories offer or a name that such a package provides, such as `cmd:jq`; for a
provided name, apk selects one of the packages that provide it. An entry SHALL NOT be read as a local package file, even
when a file of that name exists in the directory the feature was started from.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Provided name installs a provider

- **WHEN** `packages` holds `cmd:` followed by the name of a command that a package in the image's repositories provides
- **THEN** a package that provides that command is installed

#### Scenario: Entry is not read as a package file

- **WHEN** `packages` holds the file name of a signed Alpine package file that exists in the directory the feature was
  started from, and no package in the repositories has that name
- **THEN** the feature exits with a non-zero status and installs nothing

### Requirement: Image without apk

The feature SHALL exit with status 1, with a message naming `apk` and the distribution the feature supports, when
`packages` names at least one package, every entry is accepted, and `apk` is not available in the image.

#### Scenario: Image without apk fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `apk`
- **THEN** it exits with status 1, prints a message naming `apk` and Alpine Linux, and changes nothing in the image

### Requirement: Package index refresh

Before installing, the feature SHALL fetch the index of every repository configured in the image, on every installation
that names at least one package, and SHALL NOT install from a package index already present in the image. It SHALL fail
when fetching or verifying the index of any configured repository fails, including a transient download failure.

#### Scenario: Unavailable repository fails the feature

- **WHEN** the index of one configured repository cannot be fetched while the others can
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Index present in the image is not used

- **WHEN** the image already holds, in apk's cache, a fresh package index together with the package files of the listed
  packages and their dependencies, and no configured repository can be reached
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Repository authentication stays in effect

The feature SHALL leave apk's signature verification against the keys the image trusts
(https://gitlab.alpinelinux.org/alpine/apk-tools/-/blob/master/doc/apk-keys.5.scd) in effect: it SHALL NOT pass any
option or configuration that allows untrusted or unsigned packages or indexes, skips server certificate verification,
continues without an unavailable repository, or replaces the image's repositories or trusted keys, and SHALL NOT itself
add, remove, or change any repository, signing key, or apk configuration file in the image. Files that the packages it
installs ship are not the feature's changes.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** a configured repository's index cannot be verified with the keys the image trusts
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Apk configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/apk`
- **THEN** the repository files, the trusted keys, and every file under `/etc/apk` other than the world are the same as
  before it ran

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input, also when the image makes apk interactive by default with
`/etc/apk/interactive` and a terminal is attached.

#### Scenario: Interactive default is overridden

- **WHEN** the image holds `/etc/apk/interactive` and the feature runs with a terminal attached and no input
- **THEN** the feature completes and installs the listed packages without asking a question

### Requirement: Clean package caches

After installing, the feature SHALL leave neither the package indexes it fetched nor the package files it downloaded in
the image, and SHALL leave `/var/cache/apk`, and any cache directory the image configures through `/etc/apk/cache`, as
the image had them.

#### Scenario: Caches are removed

- **WHEN** the feature has installed packages
- **THEN** no package index or package file that the feature fetched remains in the image, and `/var/cache/apk` holds
  the same files as before it ran

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. For a name that both lists hold, the second entry, with its
constraint or without one, SHALL replace the first in apk's world. The second installation SHALL NOT change the version
of an installed package unless an entry's constraint or a package it installs requires another version of it.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Later entry replaces the earlier constraint

- **WHEN** the first installation's `packages` holds `name=version` and the second's holds `name` without a constraint
- **THEN** the second installation succeeds, apk's world holds `name` without a constraint, and the installed version
  stays as it was

#### Scenario: Unsatisfiable constraint on the second install

- **WHEN** the second installation's `packages` holds, for an installed package, a constraint that no version the
  repositories offer satisfies
- **THEN** the second installation exits with a non-zero status, and the installed version and apk's world stay as they
  were
