# zypper-packages Specification

## Purpose

The `zypper-packages` feature installs a list of system packages with `zypper` on openSUSE images, taking them only from
the package repositories the image already configures and enables, and configures nothing else.

Upstream sources:

- zypper source repository: https://github.com/openSUSE/zypper
- zypper(8) manual page, zypper 1.14.101: https://github.com/openSUSE/zypper/blob/1.14.101/doc/zypper.8.txt
- zypper manual: https://en.opensuse.org/SDB:Zypper_manual
- libzypp source repository: https://github.com/openSUSE/libzypp
- Configuration files specification that zypp.conf(5) refers to:
  https://github.com/uapi-group/specifications/blob/main/specs/configuration_files_specification.md

## Requirements

### Requirement: Option installRecommends

The feature SHALL accept the option `installRecommends` as declared here.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted installRecommends

- **WHEN** `installRecommends` is omitted
- **THEN** the feature uses `false` as specified by the requirements below

### Requirement: Option refreshPolicy

The feature SHALL accept the option `refreshPolicy` as declared here.

| Field   | Value                          |
| ------- | ------------------------------ |
| Type    | `string`                       |
| Default | `"default"`                    |
| Enum    | `["default","always","never"]` |

#### Scenario: Omitted refreshPolicy

- **WHEN** `refreshPolicy` is omitted
- **THEN** the feature uses `"default"` as specified by the requirements below

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

The feature SHALL validate `installRecommends`, `refreshPolicy`, `cleanup` and all package entries before invoking any
package-manager command or creating any cache. Boolean options SHALL accept only `true` or `false`; enum options SHALL
accept only their declared values. Invalid options SHALL fail with status 1 and a message naming the option. With valid
options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or changing any
configuration, also without the package manager.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

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
- **THEN** the feature exits with status 0, installs and removes nothing, and does not refresh repository metadata, also
  on an image without `zypper`

#### Scenario: Empty list is a no-op

- **WHEN** `packages` is empty or holds only commas and whitespace
- **THEN** the feature exits with status 0, installs and removes nothing, and does not refresh repository metadata, also
  on an image without `zypper`

#### Scenario: Spaces and empty entries are ignored

- **WHEN** `packages` has spaces and tabs around its entries and an empty entry between two commas
- **THEN** the named packages are installed exactly as if the whitespace and the empty entry were absent

### Requirement: Install the listed packages

The feature SHALL install, with `zypper`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories enabled in the image. Recommended packages SHALL be excluded
when `installRecommends=false` and considered by Zypper when `installRecommends=true`. Apart from that dependency
selection, it SHALL NOT upgrade installed packages other than the listed packages and what they need.

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

The feature SHALL pass an entry of the form `name=edition`, `name.architecture`, or `name.architecture=edition`, or one
that puts a range operator in the place of `=` (`name<edition`, `name<=edition`, `name>edition`, `name>=edition`), to
`zypper` unchanged, so that `zypper` selects that edition (a version, optionally with an epoch and a release), an
edition in that range, or that architecture of the package. The feature SHALL NOT downgrade a package: when an entry
pins with `=` an edition that the enabled repositories offer and that is older than the installed version of that
package, the installed version stays and the entry does not fail the feature.

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

The feature SHALL accept an entry only when it starts with an ASCII letter or a digit, its name part consists only of
ASCII letters, digits, and the characters `.`, `_`, `+`, and `-`, it holds at most one operator (`=`, `<`, `<=`, `>`, or
`>=`), the part after that operator is not empty and consists only of ASCII letters, digits, and the characters `.`,
`_`, `+`, `~`, `^`, `:`, and `-`, and the entry does not end in `.rpm`. When any entry is refused, the feature SHALL
exit with status 1 and a message naming that entry before it checks for `zypper`, refreshes repository metadata, or
installs anything. The feature SHALL hand every accepted entry to `zypper` as one argument and SHALL NOT evaluate it as
shell code.

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

The feature SHALL install for each entry the package that `zypper` selects for it from the enabled repositories: a
package whose name equals the entry's name part, without its architecture and edition, in the same letter case, or
equals it once a trailing `-version` or `-version-release` is read as an edition of that package; and, when no package
has that name, a package that provides the name part as a capability, which `zypper` chooses when several provide it. An
entry SHALL NOT be matched as a glob, a pattern, a patch, or a product. When one entry selects nothing, the feature
SHALL fail and install none of the listed packages.

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name-version form selects that edition

- **WHEN** `packages` holds a package name followed by `-` and an edition of that package that the image's repositories
  offer, and the package is not installed
- **THEN** exactly that edition of the package is installed

#### Scenario: Capability selects a providing package

- **WHEN** `packages` names a capability that a package of the image's repositories provides, that no installed package
  provides, and that is not itself the name of a package the repositories offer
- **THEN** the feature succeeds and a package that provides the capability is installed

#### Scenario: Name in another case fails

- **WHEN** `packages` names a package that the repositories offer, written with different letter case, and no package or
  capability has that spelling
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

### Requirement: Installed packages are not removed

The feature SHALL NOT remove an installed package to resolve a conflict with a listed package or its dependencies; such
a conflict SHALL fail the feature. An installed package that a newly installed package obsoletes MAY be replaced by it.

#### Scenario: Conflict with an installed package fails

- **WHEN** `packages` names a package that conflicts with an installed package
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and the installed package
  stays

### Requirement: Image without zypper

The feature SHALL exit with status 1, with a message naming `zypper` and the distributions the feature supports, when
`packages` names at least one package, every entry is accepted, and `zypper` is not available in the image.

#### Scenario: Image without zypper fails clearly

- **WHEN** the feature runs with a non-empty `packages` on an image that has no `zypper`
- **THEN** it exits with status 1, prints a message naming `zypper` and openSUSE, and changes nothing in the image

### Requirement: Repository metadata refresh

With `refreshPolicy=default` or `always`, the feature SHALL check every enabled repository index before installation and
download metadata only when missing or changed. If any enabled repository cannot be refreshed or verified, the feature
SHALL fail before installing and SHALL NOT skip it. With `never`, it SHALL use existing metadata without contacting
repositories for refresh and SHALL fail before installation if any enabled repository has no usable cached metadata;
package files MAY still be downloaded. Installation SHALL use the selected metadata without another automatic refresh.
Signature and TLS checks SHALL remain in effect.

#### Scenario: Missing metadata is refreshed

- **WHEN** `refreshPolicy=default` and the image holds no cached repository metadata
- **THEN** the feature downloads the metadata of every enabled repository before installing

#### Scenario: Current metadata is kept

- **WHEN** `refreshPolicy=default` and the image already holds cached metadata of every enabled repository and no
  repository's index has changed
- **THEN** the feature installs from the cached metadata, downloading only each repository's index file

#### Scenario: Failed refresh fails the feature

- **WHEN** `refreshPolicy=default` and refreshing the metadata of any enabled repository fails, while the other enabled
  repositories refresh and offer the listed packages
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Refresh is explicitly requested

- **WHEN** refreshPolicy=always with a non-empty package list and existing metadata
- **THEN** every configured or enabled repository is checked before installing; failure of any repository fails before
  packages change

#### Scenario: Cached metadata is explicitly selected

- **WHEN** refreshPolicy=never and every required index or metadata cache is usable
- **THEN** no metadata is fetched and installation uses the existing metadata under the package manager's normal
  verification policy

#### Scenario: Missing cached metadata fails without refresh

- **WHEN** refreshPolicy=never and a required repository has no usable cached metadata
- **THEN** the feature fails before installing without attempting a metadata download

### Requirement: Repository authentication stays in effect

The feature SHALL leave libzypp's signature checking (`gpgcheck` in zypp.conf(5), libzypp 17.38.16,
https://github.com/openSUSE/libzypp/blob/17.38.16/zypp/doc/zypp.conf.5.txt) in effect: it SHALL NOT pass any option or
configuration that ignores signature failures, imports or trusts a new signing key, or accepts unsigned repositories or
packages, and SHALL NOT itself add, remove, or change any repository, service, trusted key, or zypp configuration file
in the image. The keys and the signature settings are the image's: the feature trusts what the image's RPM database
trusts, and a repository for which the image's configuration turns the check off stays unchecked. Files that the
packages it installs ship, and repository definitions that a repository index service the image defines rewrites from
its own index when `zypper` refreshes it, are not the feature's changes.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** an enabled repository's metadata is signed by a key the image does not trust
- **THEN** the feature exits with a non-zero status, trusts no new key, and installs none of the listed packages

#### Scenario: Unsigned repository fails the refresh

- **WHEN** an enabled repository's metadata carries no signature, and the image's configuration does not turn the
  signature check off for it
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

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

After successful installation, `cleanup=all` SHALL explicitly remove downloaded package files and repository metadata
from the effective libzypp package, raw metadata, and parsed metadata caches. With `packages`, it SHALL explicitly
remove downloaded package files while leaving usable metadata; with `none`, it SHALL perform no explicit cache deletion.
No mode SHALL remove installed-package databases, signing keys, or unrelated paths. Package-manager configuration or
image hooks MAY independently delete downloads; none does not guarantee that package files are retained, and packages
does not guarantee that missing metadata is created.

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

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without an edition or with a range, or that a package of its list needs.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages.

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
