# apt-packages Specification

## Purpose

The `apt-packages` feature installs a list of system packages with `apt-get` on Debian and Ubuntu images, taking them
only from the package repositories the image already configures, and configures nothing else.

Upstream sources:

- apt-get manual: https://manpages.debian.org/apt-get
- apt.conf manual: https://manpages.debian.org/apt.conf
- apt_preferences manual: https://manpages.debian.org/apt_preferences
- apt-transport-http manual: https://manpages.debian.org/apt-transport-http
- dpkg manual: https://manpages.debian.org/dpkg
- APT source repository: https://salsa.debian.org/apt-team/apt

## Requirements

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
listed package only suggests. Recommended packages SHALL be excluded when `installRecommends=false` and considered by
APT when `installRecommends=true`. Apart from that dependency selection, it SHALL NOT upgrade installed packages other
than the listed packages and what they need.

The feature SHALL NOT remove any installed package to satisfy a listed package or its dependencies. When the requested
installation requires removal, it SHALL fail before changing any installed package.

#### Scenario: Conflicting package fails without removal

- **WHEN** a listed package conflicts with a package already installed in the image
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and leaves the installed
  packages unchanged

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Recommended packages are left out

- **WHEN** `installRecommends=false` and `packages` names a package that recommends another package which nothing
  installed depends on
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Listed package already installed at its candidate version

- **WHEN** `packages` names, without a version, a package that is already installed at the candidate version apt selects
  from the configured repositories and their pin priorities
- **THEN** the feature succeeds and the package stays at that version

#### Scenario: Optional dependency selection is enabled

- **WHEN** `installRecommends=true` and a listed package has an applicable recommendation that is available and
  unconstrained
- **THEN** the package manager includes that recommendation in its resolution; required dependencies and conflict
  protection remain in effect

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

The feature SHALL accept an entry only when its package name, the part before the first `:` or `=`, starts with a
lower-case letter or a digit and consists only of lower-case letters, digits, and the characters `.`, `+`, and `-`; when
the rest of the entry consists only of letters, digits, and the characters `.`, `+`, `-`, `:`, `~`, and `=`; and when
the entry does not end in `-`. When any entry is refused, the feature SHALL exit with status 1 and a message naming that
entry before it checks for `apt-get`, refreshes the package index, or installs anything. The feature SHALL hand every
accepted entry to `apt-get` as one argument and SHALL NOT evaluate it as shell code.

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/`, such as a URL or a path to a `.deb` file
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Removal marker is refused

- **WHEN** `packages` holds an entry ending in `-`
- **THEN** the feature exits with status 1, names the entry, and neither removes nor installs any package

#### Scenario: Package name ending in plus is installed

- **WHEN** `packages` names a package whose name ends in `+` and that the image's repositories offer
- **THEN** that package is installed

#### Scenario: Upper-case package name is refused

- **WHEN** `packages` holds an entry whose package name contains an upper-case letter
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, or `|`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries name packages exactly

The feature SHALL install a package for an entry only when the entry's package name, without its qualifier, is the exact
name of a package known to the image's repositories. An entry SHALL NOT be matched as a regular expression, a glob, a
task, or an APT search pattern. An entry that names a virtual package installs the package that provides it when exactly
one package does, and fails when several do.

The feature SHALL check every accepted entry's exact package name against APT's known actual and virtual names after the
index is ready and before installation. A pinned version SHALL match an available version exactly; a trailing `+` SHALL
NOT be interpreted as an install marker in a name or version.

#### Scenario: Unknown name ending in plus fails

- **WHEN** `packages` contains `bc+`, which is not a known package name, alongside an available package
- **THEN** the feature exits with a non-zero status and installs none of the listed packages, including `bc`

#### Scenario: Unknown version ending in plus fails

- **WHEN** `packages` pins a package to an available version followed by `+`, and that resulting version is unavailable
- **THEN** the feature exits with a non-zero status and leaves installed packages unchanged

#### Scenario: Virtual package with one provider installs

- **WHEN** `packages` names a virtual package with exactly one available provider
- **THEN** the feature succeeds and installs that provider

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

With `refreshPolicy=default`, the feature SHALL refresh only when the image holds no package index, otherwise using the
existing index without checking its age or repository coverage. With `always`, it SHALL refresh every configured
repository even when an index exists. Any attempted refresh SHALL fail before installing if any repository cannot be
refreshed or verified. With `never`, the feature SHALL use existing indexes without refreshing and SHALL fail before
installation when no usable index exists; missing or unavailable requested packages SHALL fail without a refresh
fallback. This option SHALL NOT disable package downloads or relax repository authentication.

#### Scenario: Missing index is refreshed

- **WHEN** `refreshPolicy=default` and the image holds no package index
- **THEN** the feature refreshes the index from the image's configured repositories before installing

#### Scenario: Present index is used as is

- **WHEN** `refreshPolicy=default` and the image already holds a package index
- **THEN** the feature installs from that index without refreshing it

#### Scenario: Failed refresh fails the feature

- **WHEN** refreshing the index of any configured repository fails
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

After successful installation, `cleanup=all` SHALL explicitly remove downloaded package files and repository metadata
from APT's effective package archive and index locations. With `packages`, it SHALL explicitly remove downloaded package
files while leaving usable metadata; with `none`, it SHALL perform no explicit cache deletion. No mode SHALL remove
installed-package databases, signing keys, or unrelated paths. Package-manager configuration or image hooks MAY
independently delete downloads; none does not guarantee that package files are retained, and packages does not guarantee
that missing metadata is created.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the image holds no downloaded package files and no package index files

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

Installing the feature a second time SHALL treat the second list as a first installation would. When successful, it
SHALL leave installed every package that either installation listed. If the second list requires removal of an installed
package, it SHALL fail without changing installed packages. The second installation MAY upgrade an installed package
that its list names without a version, or that a package of its list needs.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time, and the
  packages can coexist without removing an installed package
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Conflicting list on the second install

- **WHEN** the feature first installs `chrony` and a second installation lists the conflicting package `openntpd`
- **THEN** the second installation fails, `chrony` stays installed, `openntpd` is not installed, and installed packages
  are unchanged

#### Scenario: Pin below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name=version` with a version older than the one installed
- **THEN** the second installation exits with a non-zero status and the installed version stays as it was

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different refresh or cleanup values with a
  non-empty compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

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

### Requirement: Option networkTimeout

The feature SHALL accept the option `networkTimeout` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted networkTimeout

- **WHEN** `networkTimeout` is omitted
- **THEN** the feature uses `""` as specified by the requirements below

### Requirement: Installation controls are validated before changes

The feature SHALL validate `installRecommends`, `refreshPolicy`, `cleanup`, `networkTimeout` and all package entries
before invoking any package-manager command or creating any cache. Boolean options SHALL accept only `true` or `false`;
enum options SHALL accept only their declared values. A non-empty `networkTimeout` SHALL be a canonical ASCII decimal
integer string from `1` through `3600`, with no sign, whitespace, leading zero, or other character. Invalid options
SHALL fail with status 1 and a message naming the option. With valid options and an empty package list, the feature
SHALL succeed without refreshing, upgrading, cleaning, or changing any configuration, also without the package manager.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Timeout boundaries are validated

- **WHEN** networkTimeout is empty, 1, or 3600, or an invalid value such as 0, 3601, 01, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails before a package-manager command

### Requirement: Network timeout is scoped to installation

An empty `networkTimeout` SHALL leave native timeout settings unchanged. A non-empty value SHALL apply to APT HTTP and
HTTPS acquisition timeout settings on every refresh and install call made by the feature. It SHALL NOT set an overall
build deadline, change retry policy, disable certificate checks, or persist a setting in the image.

#### Scenario: Native timeout is inherited

- **WHEN** networkTimeout is omitted or empty
- **THEN** no timeout override is passed

#### Scenario: Explicit timeout reaches network operations

- **WHEN** networkTimeout is a valid non-empty value and installation needs network access
- **THEN** every feature refresh and install call receives the corresponding native timeout override, while retry and
  verification settings remain unchanged
