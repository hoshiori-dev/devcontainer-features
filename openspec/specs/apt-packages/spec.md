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
package and its dependencies only from the repositories configured in the image.

Accepted risk: with `installSuggests=true`, APT follows the suggestions of every package it newly installs, so the
installed set can grow by orders of magnitude; the developer who enables it chooses that, and the feature sets no limit.

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

#### Scenario: Suggested packages are left out

- **WHEN** `installSuggests=false` and `packages` names a package that suggests another package which nothing installed
  depends on
- **THEN** the listed package is installed and the suggested package is not, also on an image whose APT configuration
  enables suggestions

#### Scenario: Suggested packages are installed

- **WHEN** `installSuggests=true` and a listed package has a suggestion that is available and unconstrained
- **THEN** the suggested package is installed with it; required dependencies and conflict protection remain in effect

#### Scenario: Suggestions and recommendations are selected independently

- **WHEN** `installSuggests=true` and `installRecommends=false`, and a listed package has both a suggestion and a
  recommendation
- **THEN** the suggested package is installed and the recommended package is not

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
the entry does not end in `-`.

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
refreshed or verified. The `refreshPolicy` option SHALL NOT disable package downloads or relax repository
authentication.

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
and when an upgrade ships a new version of a conffile dpkg tracks that was changed in the image, the changed file SHALL
be kept with `conffilePolicy=keep` and replaced by the packaged file with `conffilePolicy=replace`.

#### Scenario: Package that asks a question installs unattended

- **WHEN** `packages` names a package whose installation asks a configuration question
- **THEN** the feature completes without a terminal or input, and the package is configured with the default answer

#### Scenario: Changed configuration file is kept

- **WHEN** `conffilePolicy=keep` and a listed package is upgraded to a version that ships a new version of a conffile
  changed in the image
- **THEN** the feature completes without input and the file keeps the image's content

#### Scenario: Changed configuration file is replaced

- **WHEN** `conffilePolicy=replace` and a listed package is upgraded to a version that ships a new version of a conffile
  changed in the image
- **THEN** the feature completes without input and the file holds the packaged content

#### Scenario: Image setting does not defeat keeping

- **WHEN** `conffilePolicy=keep` and the image's APT or dpkg configuration selects the packaged version of changed
  conffiles
- **THEN** the changed conffile is kept

#### Scenario: Image setting does not defeat replacing

- **WHEN** `conffilePolicy=replace` and the image's APT or dpkg configuration selects the default action or the
  installed version for changed conffiles
- **THEN** the changed conffile is replaced by the packaged file

#### Scenario: File managed by maintainer scripts is outside the policy

- **WHEN** a listed package manages a configuration file through its maintainer scripts and not as a conffile
- **THEN** the feature completes without input and passes no setting for that file with either policy

### Requirement: Clean package caches

After successful installation, `cleanup=all` SHALL explicitly remove downloaded package files and repository metadata
from APT's effective package archive and index locations. With `packages`, it SHALL explicitly remove downloaded package
files while leaving usable metadata; with `none`, it SHALL perform no explicit cache deletion.

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

#### Scenario: Earlier source and download controls do not persist

- **WHEN** the first invocation sets `targetRelease`, `installSuggests=true`, `conffilePolicy=replace`,
  `downloadRetries`, and `lockTimeout`, the second sets none of them with a non-empty compatible package list, and no
  package either invocation installs ships a file under /etc/apt or /etc/dpkg
- **THEN** the second invocation gives APT no release preference, retry count, or lock wait, excludes suggestions, and
  keeps changed configuration files; the image's APT and dpkg configuration files are the same as before the first
  invocation

#### Scenario: Later invocation keeps what the earlier one installed

- **WHEN** the first invocation installed a package from a target release, together with suggested packages, and the
  second lists the same package with `targetRelease` empty and `installSuggests=false`
- **THEN** the second invocation succeeds, removes no package, and downgrades none

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

The feature SHALL validate `installRecommends`, `installSuggests`, `refreshPolicy`, `cleanup`, `conffilePolicy`,
`networkTimeout`, `downloadRetries`, `lockTimeout`, `targetRelease` and all package entries before invoking any
package-manager command or creating any cache. Invalid options SHALL fail with status 1 and a message naming the option.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Timeout boundaries are validated

- **WHEN** networkTimeout is empty, 1, or 3600, or an invalid value such as 0, 3601, 01, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails before a package-manager command

#### Scenario: Retry boundaries are validated

- **WHEN** downloadRetries is empty, 0, or 10, or an invalid value such as 11, 00, 01, -1, 1.5, a number of twenty
  digits, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails with status 1 naming `downloadRetries`
  before a package-manager command

#### Scenario: Lock timeout boundaries are validated

- **WHEN** lockTimeout is empty, 1, or 3600, or an invalid value such as 0, 3601, 01, -1, a number of twenty digits, or
  shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails with status 1 naming `lockTimeout`
  before a package-manager command

#### Scenario: Target release syntax is validated

- **WHEN** targetRelease is empty, a plain suite name, a codename, or a dotted version, or an invalid value that holds
  `=`, `/`, `*`, `?`, `[`, a comma, whitespace, or shell text, that starts with `-`, that is longer than 64 characters,
  or that is `now`, `NOW`, or `Now`
- **THEN** empty and the plain names are accepted; every invalid value fails with status 1 naming `targetRelease` before
  a package-manager command

#### Scenario: Undeclared policy or boolean value is refused

- **WHEN** conffilePolicy is empty or a value other than its declared ones, such as `inherit` or a dpkg option, or
  installSuggests is neither `true` nor `false`
- **THEN** the feature exits with status 1, names the option, and changes nothing, also when packages is empty

### Requirement: Network timeout is scoped to installation

An empty `networkTimeout` SHALL leave native timeout settings unchanged. A non-empty value SHALL apply to APT HTTP and
HTTPS acquisition timeout settings on every refresh and install call made by the feature. It SHALL NOT set an overall
build deadline, change retry policy, disable certificate checks, or persist a setting in the image. The retry policy is
selected by `downloadRetries` alone.

#### Scenario: Native timeout is inherited

- **WHEN** networkTimeout is omitted or empty
- **THEN** no timeout override is passed

#### Scenario: Explicit timeout reaches network operations

- **WHEN** networkTimeout is a valid non-empty value and installation needs network access
- **THEN** every feature refresh and install call receives the corresponding native timeout override, while retry and
  verification settings remain unchanged

### Requirement: Option targetRelease

The feature SHALL accept the option `targetRelease` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted targetRelease

- **WHEN** `targetRelease` is omitted
- **THEN** the feature passes no release preference to APT and installs the candidates APT selects from the image's
  configuration alone

### Requirement: Option installSuggests

The feature SHALL accept the option `installSuggests` as declared here.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted installSuggests

- **WHEN** `installSuggests` is omitted
- **THEN** the feature excludes suggested packages, also on an image whose APT configuration enables them

### Requirement: Option conffilePolicy

The feature SHALL accept the option `conffilePolicy` as declared here.

| Field   | Value                |
| ------- | -------------------- |
| Type    | `string`             |
| Default | `"keep"`             |
| Enum    | `["keep","replace"]` |

#### Scenario: Omitted conffilePolicy

- **WHEN** `conffilePolicy` is omitted
- **THEN** a conffile that was changed in the image is kept when an upgrade ships a new version of it

### Requirement: Option downloadRetries

The feature SHALL accept the option `downloadRetries` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted downloadRetries

- **WHEN** `downloadRetries` is omitted
- **THEN** the feature passes no retry setting, and APT retries downloads as its own default or the image's
  configuration says

### Requirement: Option lockTimeout

The feature SHALL accept the option `lockTimeout` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted lockTimeout

- **WHEN** `lockTimeout` is omitted
- **THEN** the feature passes no lock setting, and a held dpkg lock is handled as `apt-get` or the image's configuration
  says

### Requirement: Target release prefers a configured release

An empty `targetRelease` SHALL pass no release preference. A non-empty value SHALL make APT prefer that release on the
install call only. It is a preference, not a filter: other releases stay usable, and a `name=version` entry keeps its
version. APT compares the whole value, without regard to letter case, with one kind of release field only: a value that
starts with a digit with release versions, and any other value with suite names and codenames.

#### Scenario: Native release preference is inherited

- **WHEN** `targetRelease` is omitted or empty and the image's APT configuration sets a default release
- **THEN** no release preference is passed and the image's default release stays in effect

#### Scenario: Explicit release reaches the install call

- **WHEN** `targetRelease` names a release of the package index, and a listed package without a version is offered by
  that release and, at a newer version, by another configured release of default priority
- **THEN** the version of the named release is installed

#### Scenario: Dependencies follow the target release

- **WHEN** `targetRelease` names a release and a listed package needs a dependency that several configured releases
  offer
- **THEN** APT selects the dependency with the same preference, and still takes a dependency the named release does not
  offer from another configured release

#### Scenario: Pinned version wins over the target release

- **WHEN** `targetRelease` names a release and `packages` holds `name=version` for a version only another configured
  release offers
- **THEN** exactly that version is installed

#### Scenario: Image default release is overridden for the invocation

- **WHEN** `targetRelease` is non-empty and the image's APT configuration sets a different default release
- **THEN** the install call prefers the release the option names, and the image's configuration is unchanged afterwards

#### Scenario: Release name shared by several suites prefers all of them

- **WHEN** the configured sources hold several suites that carry the same codename or version, one of which the image
  ranks below the default priority, and `targetRelease` holds that codename or version
- **THEN** every such suite is preferred, so a listed package can be installed from the lower-ranked suite

#### Scenario: Release name carried by one suite prefers that suite alone

- **WHEN** the configured sources hold several suites with distinct suite names, codenames, and versions, and
  `targetRelease` holds the name of one of them
- **THEN** only that suite is preferred: a listed package that is not installed comes from it, also when another suite
  offers a newer version

#### Scenario: Letter case of the release name is not significant

- **WHEN** `targetRelease` differs only in letter case from a field it is compared with, a suite name, a codename, or a
  release version that contains a letter, that one release of the package index carries
- **THEN** that release is preferred as it is with the name in the release's own spelling

### Requirement: Target release selects only among configured sources

A `targetRelease` SHALL select only among the releases present in the package index the feature uses. It SHALL add no
source, component, or key, SHALL NOT be passed to the index refresh, and SHALL NOT be matched as a pattern, a regular
expression, or a `key=value` selector.

#### Scenario: Unknown release fails before any change

- **WHEN** `targetRelease` is a well-formed name that no release of the package index carries
- **THEN** the feature exits with status 1, the output names `targetRelease` and the given value, the install call is
  not made, and no package is installed or changed

#### Scenario: Name starting with a digit is not compared with suite names or codenames

- **WHEN** `targetRelease` starts with a digit and equals a suite name or a codename of the package index, but the
  version of no release
- **THEN** the feature exits with status 1, the output names `targetRelease` and the given value, the install call is
  not made, and no package is installed or changed

#### Scenario: Name starting with a letter is not compared with release versions

- **WHEN** `targetRelease` starts with a letter and equals the version of a release of the package index, but no suite
  name or codename
- **THEN** the feature exits with status 1, the output names `targetRelease` and the given value, the install call is
  not made, and no package is installed or changed

#### Scenario: Release the image does not configure is not added

- **WHEN** `targetRelease` names a suite that exists upstream but that no source of the image configures
- **THEN** the feature fails as for an unknown release and the image's sources are unchanged

#### Scenario: Refresh ignores the target release

- **WHEN** `targetRelease` is non-empty and the feature refreshes the package index
- **THEN** the refresh covers every configured repository exactly as it does without the option

### Requirement: Target release ranks with holds and pins as APT does

A `targetRelease` SHALL NOT change a held package or downgrade an installed one. APT gives each suite the name selects
priority 990, in place of a pin the image set on that suite for all packages. A pin on another suite and a pin naming a
package keep their priority: above 990 they win, negative they exclude, below 990 they lose; at 990 the newest version
wins. Accepted risk: an image's pin of a whole suite, such as -1 on backports, is cancelled when the name selects it.

#### Scenario: Held package is not changed

- **WHEN** `targetRelease` names a release that offers a newer version of a listed package the image holds
- **THEN** the feature exits with a non-zero status and the held package keeps its version

#### Scenario: Installed newer version is not downgraded

- **WHEN** `targetRelease` names a release whose version of a listed package is older than the installed one
- **THEN** the feature succeeds and the installed version stays

#### Scenario: Higher-priority pin wins

- **WHEN** the image pins, with a priority above 990, a suite that `targetRelease` does not select
- **THEN** the version the pin selects is installed

#### Scenario: Negative pin still excludes

- **WHEN** the image pins every version of a listed package, by the package's name, with a negative priority and
  `targetRelease` names a release that offers it
- **THEN** the feature exits with a non-zero status and the package is not installed

#### Scenario: Lower-priority pin on another version is outranked

- **WHEN** `targetRelease` names a release that offers a listed package, and the image pins a version of that package
  outside the target release with a positive priority below 990
- **THEN** the version of the target release is installed

#### Scenario: Pin of exactly 990 yields to the newer version

- **WHEN** `targetRelease` names a release that offers a listed package, and the image pins another version of that
  package with priority 990
- **THEN** the newer of the two versions is installed

#### Scenario: Pin on the whole named suite is replaced

- **WHEN** the image gives a suite a negative priority for all packages, `targetRelease` selects that suite, and a
  listed package is offered by that suite alone
- **THEN** the package is installed from that suite, and the image's pin is unchanged afterwards

### Requirement: Configuration file policy covers dpkg conffiles

`conffilePolicy` SHALL apply only to dpkg conffiles, wherever a conffile's path holds other content than dpkg expects:
on an upgrade, on a first installation over an existing file, and after a removal without purge. `keep` leaves the
image's file and writes the packaged one as `.dpkg-dist`. `replace` installs the packaged file, saves the image's as
`.dpkg-old`, and restores a deleted conffile. Accepted risk: `replace` overwrites deliberate image configuration,
dependencies included.

#### Scenario: Kept file has the packaged version beside it

- **WHEN** `conffilePolicy=keep` and an upgrade ships a new version of a conffile that was changed in the image
- **THEN** the changed file is unchanged and the packaged version is present with the suffix `.dpkg-dist`

#### Scenario: Replaced file is saved beside the packaged one

- **WHEN** `conffilePolicy=replace` and an upgrade ships a new version of a conffile that was changed in the image
- **THEN** the file holds the packaged content and the image's version is present with the suffix `.dpkg-old`

#### Scenario: Deleted conffile is installed again when replacing

- **WHEN** `conffilePolicy=replace` and an upgrade ships a new version of a conffile that was deleted in the image
- **THEN** the packaged file is present after the installation

#### Scenario: Unchanged conffile is upgraded under either policy

- **WHEN** an upgrade ships a new version of a conffile that the image did not change
- **THEN** the packaged file is installed with either policy and no file with a `.dpkg-dist` or `.dpkg-old` suffix
  appears

#### Scenario: Package without existing configuration files is unaffected

- **WHEN** a listed package is not installed before the feature runs and none of its conffile paths exists in the image
- **THEN** its conffiles are installed as packaged with either policy and no file with a `.dpkg-dist` or `.dpkg-old`
  suffix appears

#### Scenario: Existing file at a new package's conffile path follows the policy

- **WHEN** a listed package is not installed, or was removed without being purged, and the image holds a file with other
  content at one of its conffile paths
- **THEN** with `conffilePolicy=keep` the image's file stays and the packaged one is present with the suffix
  `.dpkg-dist`; with `conffilePolicy=replace` the file holds the packaged content and the image's is present with the
  suffix `.dpkg-old`

### Requirement: Download retries are bounded

An empty `downloadRetries` SHALL leave APT's retry setting unchanged. A non-empty value SHALL be the number of times APT
retries a failed download after its first attempt, on every refresh and install call the feature makes; `0` disables
retries. It SHALL NOT change the delay between attempts, which failures APT retries, or any timeout. Accepted risk: APT
lengthens the delay with each retry, so a high value can add minutes per file; the range of the option is the bound.

#### Scenario: Native retries are inherited

- **WHEN** `downloadRetries` is omitted or empty
- **THEN** no retry override is passed, and a retry count the image configures stays in effect

#### Scenario: Explicit retries reach refresh and install

- **WHEN** `downloadRetries` is a valid non-empty value and the feature refreshes the index and installs packages
- **THEN** every refresh and install call receives that retry count, and a download whose connection keeps being closed
  without an answer is retried that many times, with APT's growing delay, before the feature fails

#### Scenario: Retries are disabled

- **WHEN** `downloadRetries` is zero and the connection of a download is closed without an answer
- **THEN** the download is not retried, no retry delay passes, and the feature exits with a non-zero status

#### Scenario: Missing file is not retried

- **WHEN** `downloadRetries` is greater than zero and a repository answers that a requested file does not exist
- **THEN** the file is requested once and the feature exits with a non-zero status

#### Scenario: Retry count and timeout are independent

- **WHEN** `downloadRetries` and `networkTimeout` are both non-empty
- **THEN** each call receives both settings and neither changes the other's value

### Requirement: Lock wait is scoped to installation

An empty `lockTimeout` SHALL leave APT's lock behavior unchanged. A non-empty value SHALL be the number of seconds the
install call waits for dpkg's locks while another process holds them; when the wait ends first, the feature SHALL fail
without changing a package. It SHALL NOT make the index refresh, the download of package files, or the cleanup wait: APT
offers no wait for the index and archive locks, so one of them held by another process fails at once.

#### Scenario: Native lock behavior is inherited

- **WHEN** `lockTimeout` is omitted or empty
- **THEN** no lock setting is passed, and a held dpkg lock is handled as `apt-get` or the image's configuration says

#### Scenario: Explicit lock wait reaches the install call

- **WHEN** `lockTimeout` is a valid non-empty value
- **THEN** the install call, and no other call of the feature, receives that wait

#### Scenario: Lock released within the wait

- **WHEN** another process holds a dpkg lock and releases it before `lockTimeout` seconds have passed
- **THEN** the feature waits, then installs the listed packages and exits with status 0

#### Scenario: Lock held beyond the wait

- **WHEN** another process holds a dpkg lock for longer than `lockTimeout` seconds
- **THEN** the feature exits with a non-zero status no earlier than `lockTimeout` seconds after the install call
  started, and no package is changed

#### Scenario: Index and archive locks do not wait

- **WHEN** `lockTimeout` is non-empty and another process holds the lock of the package index or of the package archive
- **THEN** the call that needs that lock fails at once and the feature exits with a non-zero status

### Requirement: Image configuration is inherited

The feature SHALL set no proxy and no environment variable that selects an APT or dpkg configuration file, and SHALL
write no configuration file. An option left empty SHALL inherit what the image's configuration and the build environment
provide. An explicit option, and every option that always carries a value, SHALL override only its matching native
setting, on the feature's own calls only.

#### Scenario: Empty options inherit the image configuration

- **WHEN** `targetRelease`, `downloadRetries`, `lockTimeout`, and `networkTimeout` are empty and the image's APT
  configuration sets a default release, a retry count, a lock wait, and a timeout
- **THEN** the feature's calls run with the image's four settings

#### Scenario: Explicit option overrides its image setting

- **WHEN** `targetRelease`, `downloadRetries`, `lockTimeout`, or `networkTimeout` is non-empty and the image's APT
  configuration sets a different value for the same setting
- **THEN** the feature's calls use the option's value, the other image settings stay in effect, and the feature changes
  no configuration file of the image

#### Scenario: Proxy settings are inherited

- **WHEN** the build environment or the image's APT configuration provides a proxy
- **THEN** the feature passes no proxy setting of its own and changes no proxy variable, so APT applies a proxy exactly
  as it would without the feature

#### Scenario: Configuration selected by the environment is honored

- **WHEN** the environment the feature runs in names an additional APT configuration file
- **THEN** the feature's calls read it as APT does, and an explicit option still overrides the matching setting in it

### Requirement: Optional package choices are independent

Suggested packages SHALL be excluded when `installSuggests=false` and considered by APT when `installSuggests=true`,
independently of `installRecommends`. Recommended packages SHALL be excluded when `installRecommends=false` and
considered by APT when `installRecommends=true`. Apart from that dependency selection, the feature SHALL NOT upgrade
installed packages other than the listed packages and what they need.

#### Scenario: Suggestions are enabled independently

- **WHEN** `installSuggests=true` and `installRecommends=false`, and a listed package has both a suggestion and a
  recommendation
- **THEN** the suggested package is installed and the recommended package is not

### Requirement: Installation never removes packages

The feature SHALL NOT remove any installed package to satisfy a listed package or its dependencies. When the requested
installation requires removal, it SHALL fail before changing any installed package.

#### Scenario: Required removal fails before any change

- **WHEN** a listed package conflicts with a package already installed in the image
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and leaves the installed
  packages unchanged

### Requirement: Refused entries stop the run before package work

When any entry is refused by "Entries are validated before anything changes", the feature SHALL exit with status 1 and a
message naming that entry before it checks for `apt-get`, refreshes the package index, or installs anything. The feature
SHALL hand every accepted entry to `apt-get` as one argument and SHALL NOT evaluate it as shell code.

#### Scenario: Refused entry is named and runs nothing

- **WHEN** the `packages` value the feature receives holds an entry with a character outside the accepted set, such as
  `;` or `$`
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entry names are checked before installation

The feature SHALL check every accepted entry's exact package name against APT's known actual and virtual names after the
index is ready and before installation. A pinned version SHALL match an available version exactly; a trailing `+` SHALL
NOT be interpreted as an install marker in a name or version.

#### Scenario: Pinned version ending in plus must match exactly

- **WHEN** `packages` pins a package to an available version followed by `+`, and that resulting version is unavailable
- **THEN** the feature exits with a non-zero status and leaves installed packages unchanged

### Requirement: Refresh policy never uses only existing indexes

With `refreshPolicy=never`, the feature SHALL use existing indexes without refreshing and SHALL fail before installation
when no usable index exists; missing or unavailable requested packages SHALL fail without a refresh fallback.

#### Scenario: Never refresh fails on missing metadata

- **WHEN** refreshPolicy=never and a required repository has no usable cached metadata
- **THEN** the feature fails before installing without attempting a metadata download

### Requirement: Conffile outcomes do not depend on image settings

Either outcome of `conffilePolicy` SHALL be reached without a question and SHALL NOT depend on the conffile handling
that the image's APT or dpkg configuration selects. A configuration file that a package's own maintainer scripts manage,
for example through ucf or debconf, is not a conffile: the feature passes no setting for it, and it is handled as that
package decides under either policy.

#### Scenario: Image setting does not defeat the policy

- **WHEN** `conffilePolicy=keep` and the image's APT or dpkg configuration selects the packaged version of changed
  conffiles
- **THEN** the changed conffile is kept

### Requirement: Cache cleanup leaves other data and native deletion alone

No `cleanup` mode SHALL remove installed-package databases, signing keys, or unrelated paths. Package-manager
configuration or image hooks MAY independently delete downloads; `cleanup=none` does not guarantee that package files
are retained, and `cleanup=packages` does not guarantee that missing metadata is created.

#### Scenario: Native deletion is not overridden

- **WHEN** cleanup=none but a native setting or image hook deletes package files
- **THEN** the feature does not override the native deletion and does not promise retained packages

### Requirement: A later invocation uses its own control values

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages.

#### Scenario: Second invocation follows its own controls

- **WHEN** the first invocation preserves metadata and the second uses different refresh or cleanup values with a
  non-empty compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by "Installing the feature
  twice", and does not persist control settings

### Requirement: Earlier source and download choices do not carry over

An earlier invocation's target release, suggestion choice, configuration-file policy, retry count, and lock wait SHALL
NOT apply to a later one. A later invocation SHALL NOT undo what an earlier one did under its own values: it SHALL NOT
downgrade a package installed from another release, and SHALL NOT restore a configuration file that was replaced.

#### Scenario: Later invocation does not downgrade

- **WHEN** the first invocation installed a package from a target release, and the second lists the same package with
  `targetRelease` empty
- **THEN** the second invocation succeeds, removes no package, and downgrades none

### Requirement: Empty list does no package work

With valid options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or
changing any configuration, also without the package manager.

#### Scenario: Valid controls with an empty list change nothing

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

### Requirement: Boolean and enum options accept only declared values

Boolean options SHALL accept only `true` or `false`; enum options SHALL accept only their declared values.

#### Scenario: Undeclared enum or boolean value is refused

- **WHEN** conffilePolicy is a value other than `keep` or `replace`, or installSuggests is neither `true` nor `false`
- **THEN** the feature exits with status 1, names the option, and changes nothing, also when packages is empty

### Requirement: Control values are canonical

A non-empty `networkTimeout` SHALL be a canonical ASCII decimal integer string from `1` through `3600`, with no sign,
whitespace, leading zero, or other character. A non-empty `lockTimeout` SHALL follow the same rule with the same range.
A non-empty `downloadRetries` SHALL follow the same rule from `0` through `10`, where the single digit `0` is the only
accepted value that starts with a zero.

#### Scenario: Non-canonical number is refused

- **WHEN** `lockTimeout` is `01` or `-1`, or `downloadRetries` is `00`
- **THEN** the feature exits with status 1, names the option, and changes nothing, also when packages is empty

### Requirement: Target-release syntax is validated

A non-empty `targetRelease` SHALL be one name of at most 64 characters that starts with an ASCII letter or digit and
consists only of ASCII letters, digits, and the characters `.`, `+`, `_`, `~`, and `-`, and SHALL NOT be `now` in any
letter case.

#### Scenario: Target-release syntax restrictions apply

- **WHEN** `targetRelease` holds `=`, `/`, or whitespace, starts with `-`, is longer than 64 characters, or is `now` in
  any letter case
- **THEN** the feature exits with status 1 naming `targetRelease` before a package-manager command

### Requirement: Apt control values are rejected before native misinterpretation

The feature SHALL refuse invalid control values itself because APT does not: APT reads a negative or oversized retry
count and a negative lock wait as unbounded, replaces any other malformed number with a value of its own, does not check
a release given as a `key=value` selector, so a mistyped one is ignored without an error, and accepts `now`, which names
the installed packages and no source.

#### Scenario: Native-invalid retry value is rejected

- **WHEN** `downloadRetries` is `-1` or a number of twenty digits
- **THEN** the feature exits with status 1 naming `downloadRetries` before a package-manager command

### Requirement: Shared release names are an accepted risk

A non-empty `targetRelease` SHALL make APT prefer every suite that carries the name in a release field of the kind it is
compared with. Accepted risk: the name selects every such suite, so it holds back security updates where suites differ
in them (Debian) and raises backports where they share them (Ubuntu), without a warning.

#### Scenario: Shared release name prefers every suite carrying it

- **WHEN** the configured sources hold several suites that carry the same codename or version, one of which the image
  ranks below the default priority, and `targetRelease` holds that codename or version
- **THEN** every such suite is preferred, so a listed package can be installed from the lower-ranked suite

### Requirement: Unmatched target release fails before install

When a non-empty package list is given and a non-empty `targetRelease` would make APT prefer no release of that index,
by the comparison that "Target release prefers a configured release" states, the feature SHALL fail with status 1 and a
message naming `targetRelease` and the given value, without installing or upgrading anything.

#### Scenario: Unmatched release names option and value

- **WHEN** `targetRelease` is a well-formed name that no release of the package index carries
- **THEN** the feature exits with status 1, the output names `targetRelease` and the given value, the install call is
  not made, and no package is installed or changed

### Requirement: Target-release validation follows index and entry checks

The feature SHALL make the check of "Unmatched target release fails before install" after the index refresh when one
runs, after the name and version check of "Entry names are checked before installation", and before the install call;
when an entry fails that check as well, the entry's failure ends the run. This check is not part of the validation of
"Installation controls are validated before changes": it needs the index and a non-empty package list.

#### Scenario: Unmatched release is reported before installation

- **WHEN** a non-empty package list of accepted, known entries is given and `targetRelease` is a well-formed name that
  no release of the package index carries
- **THEN** the feature exits with status 1 naming `targetRelease`, and the install call is not made

### Requirement: Target-release check covers APT's narrower refusal

The feature SHALL make the check of "Unmatched target release fails before install" itself because APT's own refusal is
narrower: APT accepts a value that equals a release field of the other kind, a suite name or codename that starts with a
digit or a version that starts with a letter, and then prefers no release, without an error.

#### Scenario: Release field of the other kind fails

- **WHEN** `targetRelease` starts with a digit and equals a suite name or a codename of the package index, but the
  version of no release
- **THEN** the feature exits with status 1, the output names `targetRelease` and the given value, the install call is
  not made, and no package is installed or changed
