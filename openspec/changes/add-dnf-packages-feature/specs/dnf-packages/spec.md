# Spec Delta

## Purpose

The `dnf-packages` feature installs a list of system packages with `dnf` on Fedora and RHEL-compatible images, taking
them only from the package repositories the image already configures and enables, and configures nothing else.

Upstream sources:

- DNF documentation: https://dnf.readthedocs.io/
- DNF5 documentation: https://dnf5.readthedocs.io/
- DNF source repository: https://github.com/rpm-software-management/dnf
- DNF5 source repository: https://github.com/rpm-software-management/dnf5

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
- **THEN** the feature exits with status 0, installs and removes nothing, and loads no repository metadata, also on an
  image without `dnf`

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs and removes nothing, and loads no repository metadata, also on an
  image without `dnf`

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

### Requirement: Install the listed packages

The feature SHALL install, with `dnf`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories enabled in the image. It SHALL NOT install packages that a listed
package only recommends or supplements (weak dependencies), and SHALL NOT upgrade installed packages other than the
listed packages and what they need. A listed package that the image already has MAY be upgraded when the list names it
without a version, as the image's `dnf` configuration decides.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Weak dependencies are left out

- **WHEN** `packages` names a package that recommends another package which nothing installed requires
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Listed package already installed at its newest version

- **WHEN** `packages` names, without a version, a package that is already installed at the newest version the enabled
  repositories offer
- **THEN** the feature succeeds and the package stays at that version

### Requirement: Version and architecture qualifiers

The feature SHALL pass an entry that adds a version to a package name (`name-version` or `name-version-release`, the
version optionally preceded by `epoch:`) or an architecture (`name.architecture`, also after a version) to `dnf`
unchanged, so that `dnf` selects that version or that architecture of the package. An architecture qualifier selects
only an architecture that the enabled repositories offer for the image. A pinned version SHALL be installed whatever
version of the package is installed, so that `dnf` upgrades or downgrades the package, and any installed package that
must change with it, to match the pin.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name-version-release` for a version the image's repositories offer
- **THEN** exactly that version of the package is installed

#### Scenario: Unavailable pinned version fails

- **WHEN** `packages` holds `name-version` for a version the image's repositories do not offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Native architecture qualifier is installed

- **WHEN** `packages` holds `name.architecture` with the image's native architecture
- **THEN** the package is installed for that architecture

#### Scenario: Architecture the repositories do not offer fails

- **WHEN** `packages` holds `name.architecture` with an architecture for which the image's repositories offer no package
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Entries are validated before anything changes

The feature SHALL accept an entry only when it starts with an ASCII letter or a digit, consists only of ASCII letters,
digits, and the characters `.`, `_`, `+`, `-`, `:`, `~`, and `^`, and does not end in `.rpm` in any letter case. When
any entry is refused, the feature SHALL exit with status 1 and a message naming that entry before it checks for `dnf`,
loads repository metadata, or installs anything. The feature SHALL hand every accepted entry to `dnf` as one argument
and SHALL NOT evaluate it as shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL, a path to an `.rpm` file, or a file path a package
  provides
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Package file name is refused

- **WHEN** `packages` holds an entry ending in `.rpm`, such as the file name of a package in the working directory
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Group, module, and dependency expressions are refused

- **WHEN** `packages` holds an entry starting with `@`, or an entry containing `(`, `)`, `<`, `>`, or `=`
- **THEN** the feature exits with status 1, names the entry, and installs no group, module, or package

#### Scenario: Shell metacharacters, globs, and inner whitespace are refused

- **WHEN** `packages` holds an entry with whitespace inside it or with a character outside the accepted set, such as
  `;`, `$`, `` ` ``, `*`, `?`, `[`, `|`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries select packages as dnf matches them

The feature SHALL install for each entry the package that `dnf` selects for it from the enabled repositories: a package
whose name, or name with the entry's qualifiers, equals the entry in the same letter case; when no package matches that
way, a package that provides the entry as a capability; and, on an image whose `dnf` also matches program names, a
package that ships the entry as a program in `/usr/bin` or `/usr/sbin`. When one entry selects nothing, the feature
SHALL fail and install none of the listed packages.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Names are matched in their letter case

- **WHEN** `packages` names a package the repositories offer, spelled with a different letter case, and no package or
  capability has that spelling
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Capability selects a providing package

- **WHEN** `packages` holds a capability that no package is named after and that packages in the repositories provide
- **THEN** the feature succeeds, and exactly one package providing the capability is installed, or none when an
  installed package already provides it

#### Scenario: Program name selects a package where dnf matches program names

- **WHEN** `packages` holds the name of a program that no package is named after and no package provides as a
  capability, and a package in the repositories ships it in `/usr/bin` or `/usr/sbin`
- **THEN** on an image whose `dnf` matches program names, the feature succeeds and installs that package; on any other
  image it exits with a non-zero status and installs none of the listed packages

### Requirement: Installed packages are not erased

The feature SHALL NOT remove an installed package to resolve a conflict with a listed package or its dependencies; such
a conflict SHALL fail the feature. An installed package that a newly installed package obsoletes MAY be replaced by it.

#### Scenario: Conflict with an installed package fails

- **WHEN** `packages` names a package that conflicts with an installed package
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and the installed package
  stays

### Requirement: Image without dnf

The feature SHALL exit with status 1, with a message naming `dnf` and the distributions the feature supports, when
`packages` names at least one package, every entry is accepted, and `dnf` is not available in the image.

#### Scenario: Image without dnf fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `dnf`
- **THEN** it exits with status 1, prints a message naming `dnf` and Fedora and RHEL-compatible distributions, and
  changes nothing in the image

#### Scenario: Image with only microdnf fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has `microdnf` but no `dnf`
- **THEN** it exits with status 1, prints a message saying that the feature needs `dnf` and does not support images that
  have only `microdnf`, does not run `microdnf`, and changes nothing in the image

### Requirement: Repository metadata refresh

The feature SHALL NOT force a refresh of repository metadata: the metadata of an enabled repository is downloaded only
when the image's `dnf` configuration considers the metadata the image holds for it missing or expired. The feature SHALL
fail when the metadata of an enabled repository cannot be loaded, including after a transient download failure, unless
the image's configuration marks that repository as skippable (`skip_if_unavailable`); the installation then continues
without that repository.

#### Scenario: Missing metadata is downloaded

- **WHEN** the image holds no metadata for the enabled repositories
- **THEN** the feature downloads it from the image's enabled repositories before installing

#### Scenario: Unexpired metadata is used as is

- **WHEN** the image already holds metadata of every enabled repository that its `dnf` configuration does not consider
  expired
- **THEN** the feature installs from that metadata without downloading it again

#### Scenario: Failed metadata download fails the feature

- **WHEN** the metadata of an enabled repository that the image does not mark as skippable cannot be downloaded
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Skippable repository is skipped

- **WHEN** the metadata of an enabled repository that the image marks as skippable cannot be downloaded, and the listed
  packages come from other repositories
- **THEN** the feature installs the listed packages from the other repositories and exits with status 0

### Requirement: Package signature checking stays in effect

The feature SHALL leave the signature checks that the image's `dnf` configuration sets in effect
(https://dnf.readthedocs.io/en/latest/conf_ref.html, `gpgcheck`; https://dnf5.readthedocs.io/en/latest/dnf5.conf.5.html,
`pkg_gpgcheck`): it SHALL NOT pass any option or configuration that disables or relaxes a signature or TLS check, and
SHALL NOT itself add, remove, enable, disable, or change any repository, signing key, or `dnf` configuration file in the
image. When a package's signature needs a key that is not yet in the RPM keyring, `dnf` MAY import, without
confirmation, the key that the package's repository configuration names for it, from a local file or a remote location,
and that key stays in the keyring even when the signature check then fails. The feature checks such a key against no
pinned fingerprint or checksum: a key from a remote location relies on that location's transport alone, TLS for an HTTPS
URL. The feature names no key and passes no key location; every key `dnf` imports is one the image's repository
configuration names. Files that the packages it installs ship are not the feature's changes.

#### Scenario: Unverifiable package fails

- **WHEN** a package to install carries a signature that the keys the image's configuration names for its repository
  cannot verify
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Dnf configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under
  `/etc/yum.repos.d`, `/etc/dnf`, or `/etc/pki/rpm-gpg`, and every key their signatures need was already in the RPM
  keyring
- **THEN** the repository files, the `dnf` configuration, the key files, and the keys in the RPM keyring are the same as
  before it ran

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input.

#### Scenario: Installation completes without input

- **WHEN** the feature runs without a terminal and with its standard input closed
- **THEN** it installs the listed packages and exits with status 0 without waiting for input

### Requirement: Clean package caches

After installing, the feature SHALL leave neither downloaded package files nor repository metadata in `dnf`'s cache.

#### Scenario: Caches are removed

- **WHEN** the feature has installed packages
- **THEN** the image holds no downloaded package files and no repository metadata in `dnf`'s cache

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without a version, or that a package of its list needs, and SHALL install a version its list pins, also below
the installed one.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Pin below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name-version-release` with a version older than the one
  installed, which the repositories offer
- **THEN** the second installation succeeds and exactly the pinned version of the package is installed
