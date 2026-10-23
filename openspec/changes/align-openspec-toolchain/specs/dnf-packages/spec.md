# Spec Delta

## MODIFIED Requirements

### Requirement: Installation controls are validated before changes

Before package-manager calls or cache creation, the feature SHALL validate booleans, enums, timeouts, retry/concurrency
values, repository identifiers, and package entries. Network timeout is 1–3600 and parallel downloads 1–20, both
canonical ASCII decimals. Invalid values fail status 1 naming the option; valid empty lists do no package work or
repository-existence checks.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided, including a repository identifier the image
  does not configure
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Timeout boundaries are validated

- **WHEN** networkTimeout is empty, 1, or 3600, or an invalid value such as 0, 3601, 01, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails before a package-manager command

#### Scenario: Parallel download boundaries are validated

- **WHEN** parallelDownloads is empty, 1, or 20, or an invalid value such as 0, 21, 05, -1, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails before a package-manager command

#### Scenario: Best policy values are validated

- **WHEN** best is a value other than its declared ones, such as an empty value or a declared word in another letter
  case
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Repository identifiers are validated

- **WHEN** a repository list holds an identifier with a pattern character, a leading `-`, a `/`, a `=`, inner
  whitespace, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the option and the identifier, runs no command contained in it, and
  changes nothing, also when packages is empty

#### Scenario: Spaces and empty items in a repository list are ignored

- **WHEN** a repository list has spaces around its identifiers, an empty item between two commas, and one identifier
  twice
- **THEN** the feature behaves exactly as if the list held each identifier once and nothing else

#### Scenario: Identifier in both repository lists is refused

- **WHEN** the same identifier appears in `enableRepositories` and `disableRepositories`
- **THEN** the feature exits with status 1, names the identifier, and changes nothing, also when packages is empty

### Requirement: Install the listed packages

The feature SHALL install listed packages and dependencies only from repositories enabled for this invocation. Weak
Recommends and Supplements follow installWeakDeps. Other installed packages do not upgrade except listed packages and
their needs; best controls whether a listed unversioned package may upgrade, with inherit following image DNF
configuration.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0 and both packages, with their dependencies, are installed

#### Scenario: Weak dependencies are left out

- **WHEN** `installWeakDeps=false` and `packages` names a package that recommends another package which nothing
  installed requires
- **THEN** the listed package is installed and the recommended package is not

#### Scenario: Listed package already installed at its newest version

- **WHEN** `packages` names, without a version, a package that is already installed at the newest version the enabled
  repositories offer
- **THEN** the feature succeeds and the package stays at that version

#### Scenario: Optional dependency selection is enabled

- **WHEN** `installWeakDeps=true` and a listed package has an applicable recommendation that is available and
  unconstrained
- **THEN** the package manager includes that recommendation in its resolution; required dependencies and conflict
  protection remain in effect

### Requirement: Version and architecture qualifiers

The feature SHALL pass version forms `name-version` or `name-version-release` (optionally prefixed by `epoch:`) and
architecture forms `name.architecture` unchanged. Architecture must be offered for the image. A pinned version is
installed even when that upgrades or downgrades the package and any installed package that must change with it.

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

Entries SHALL start with an ASCII letter or digit, use only ASCII letters, digits, `.`, `_`, `+`, `-`, `:`, `~`, `^`,
and not end in `.rpm` in any case. Invalid entries fail status 1 naming the entry before checking dnf, loading metadata,
or installing. Accepted entries are single arguments, never shell code.

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

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, `[`, `|`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

### Requirement: Entries select packages as dnf matches them

For each entry the feature SHALL install DNF’s same-case match by package name and qualifiers, then capability provider,
then (where native DNF supports it) program in `/usr/bin` or `/usr/sbin`. An entry selecting nothing fails the
transaction before any listed package is installed.

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

### Requirement: Repository metadata refresh

default SHALL let DNF use image settings, including skippable repositories. always SHALL refresh every enabled
repository and fail before installation on any refresh or verification error, even skippable ones. never SHALL use
cache-only mode, fetch neither metadata nor packages, and fail before installation if usable metadata or a required
package file is absent/invalid. Cached metadata may be expired; no mode relaxes signature or TLS checks.

#### Scenario: Missing metadata is downloaded

- **WHEN** `refreshPolicy=default` and the image holds no metadata for the enabled repositories
- **THEN** the feature downloads it from the image's enabled repositories before installing

#### Scenario: Unexpired metadata is used as is

- **WHEN** `refreshPolicy=default` and the image already holds metadata of every enabled repository that its `dnf`
  configuration does not consider expired
- **THEN** the feature installs from that metadata without downloading it again

#### Scenario: Failed metadata download fails the feature

- **WHEN** `refreshPolicy=default` and the metadata of an enabled repository that the image does not mark as skippable
  cannot be downloaded
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Skippable repository is skipped

- **WHEN** `refreshPolicy=default` and the metadata of an enabled repository that the image marks as skippable cannot be
  downloaded, and the listed packages come from other repositories
- **THEN** the feature installs the listed packages from the other repositories and exits with status 0

#### Scenario: Refresh is explicitly requested

- **WHEN** refreshPolicy=always with a non-empty package list and existing metadata
- **THEN** every repository enabled for the invocation is checked before installing; failure of any of them fails before
  packages change

#### Scenario: Cached metadata is explicitly selected

- **WHEN** refreshPolicy=never and every required index or metadata cache is usable and all required package files are
  cached
- **THEN** no metadata is fetched and installation uses the existing metadata under the package manager's normal
  verification policy

#### Scenario: Missing cached metadata fails without refresh

- **WHEN** refreshPolicy=never and a required repository has no usable cached metadata
- **THEN** the feature fails before installing without attempting a metadata download

#### Scenario: Cache-only package miss fails

- **WHEN** refreshPolicy=never with cached metadata but a missing or invalid required package file
- **THEN** the feature fails without downloading or installing a package

### Requirement: Package signature checking stays in effect

The feature SHALL preserve image-configured signature (`gpgcheck`: https://dnf.readthedocs.io/en/latest/conf_ref.html;
`pkg_gpgcheck`: https://dnf5.readthedocs.io/en/latest/dnf5.conf.5.html) and TLS checks, without weakening them or
altering image repositories, keys, or DNF configuration. Image-disabled signature checking stays disabled.
Package-shipped files and image index-service rewrites are outside feature changes.

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

#### Scenario: Temporarily enabled repository keeps its own checks

- **WHEN** `enableRepositories` names a repository whose configuration turns the package signature check on, and a
  package to install from it carries a signature its configured keys cannot verify
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Repository selection leaves the configuration unchanged

- **WHEN** the feature has installed, with non-empty `enableRepositories` and `disableRepositories`, packages none of
  which, with their dependencies, ships a file under `/etc/yum.repos.d`, `/etc/dnf`, or `/etc/pki/rpm-gpg`, and every
  key their signatures need was already in the RPM keyring
- **THEN** the repository files, the `dnf` configuration, the key files, and the keys in the RPM keyring are the same as
  before it ran

### Requirement: Clean package caches

After success, all SHALL explicitly remove downloaded packages and repository metadata from effective DNF cache;
packages removes downloaded packages but leaves usable metadata; none performs no explicit deletion. No mode removes
installed databases, keys, or unrelated paths. Native config/hooks may delete files independently; none cannot guarantee
retention and packages cannot create missing metadata.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the image holds no downloaded package files and no repository metadata in `dnf`'s cache

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

A second install SHALL retain packages from both successful lists and resolve its list as a first install would. It may
upgrade unversioned listed packages/dependencies and SHALL install pinned versions, including downgrades. Each
invocation uses its own controls: refresh/cleanup, weak-dependency, repository, best-version and parallel-download
settings do not persist; prior optional packages and packages from temporarily enabled repositories remain installed.

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

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different refresh or cleanup values with a
  non-empty compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

#### Scenario: Repository selection does not carry over

- **WHEN** the first invocation installs a package from a repository named in `enableRepositories`, and the second runs
  with default controls and a list naming a package the image's enabled repositories offer
- **THEN** the second installation succeeds using only the image's enabled repositories, and the package from the
  temporarily enabled repository stays installed

#### Scenario: Same repository and solver controls on the second install

- **WHEN** the feature is installed twice with the same `packages`, `best`, `enableRepositories`, `disableRepositories`,
  and `parallelDownloads`
- **THEN** both installations succeed, every listed package is installed, and the image's repository files and `dnf`
  configuration are unchanged

### Requirement: Best-version policy is scoped to installation

best=inherit SHALL pass no setting; true/false override image policy for install only. true selects each listed
package’s highest enabled version or fails; false may fall back and leaves an installed unversioned package unless
transaction needs a higher version. This does not affect pins, allow erasure, skip unresolved entries, or persist.

#### Scenario: Native best policy is inherited

- **WHEN** `best` is omitted or `inherit`
- **THEN** no best-version override is passed, and an installed package the list names without a version is upgraded or
  left as the image's `dnf` configuration decides

#### Scenario: Explicit best policy reaches the solver

- **WHEN** `best=true` and `packages` names, without a version, an installed package of which the enabled repositories
  offer a higher version that can be installed
- **THEN** the feature succeeds and the package is upgraded to that version, also on an image whose configuration turns
  the best-version policy off

#### Scenario: Best policy is turned off for the invocation

- **WHEN** `best=false` and `packages` names, without a version, an installed package of which the enabled repositories
  offer a higher version, and nothing else to install requires that higher version
- **THEN** the feature succeeds and the package stays at its installed version, also on an image whose configuration
  turns the best-version policy on

#### Scenario: Pinned version is installed under either policy

- **WHEN** `best` is `true` or `false` and `packages` holds `name-version-release` for a version the enabled
  repositories offer
- **THEN** exactly that version of the package is installed, as the requirement "Version and architecture qualifiers"
  states

### Requirement: Repository selection is scoped to installation

Enabled repositories SHALL be image-enabled minus disabled plus explicitly enabled. Empty options pass no selection.
Selection applies to refresh, cache checks, install, timeout, concurrency and signature rules; omitted repositories are
not loaded. IDs match configured IDs exactly; unknown IDs fail status 1 before metadata/package changes, checked locally
only for nonempty lists. Selection changes no image files, is not exclusive/pattern/location based, and cleanup covers
all cache.

#### Scenario: Image repository set is inherited

- **WHEN** `enableRepositories` and `disableRepositories` are omitted or empty
- **THEN** no repository selection is passed and packages come from the repositories the image enables

#### Scenario: Disabled repository is enabled for the invocation

- **WHEN** `enableRepositories` names a repository the image configures and leaves disabled, and `packages` names a
  package only that repository offers
- **THEN** the feature exits with status 0, the package is installed, and afterwards the repository is still disabled in
  the image and its repository file is unchanged

#### Scenario: Enabled repository is left out for the invocation

- **WHEN** `disableRepositories` names a repository the image enables, and `packages` names a package only that
  repository offers
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and afterwards the repository
  is still enabled in the image

#### Scenario: Both lists apply together

- **WHEN** `enableRepositories` and `disableRepositories` each name a different configured repository, and `packages`
  names a package the resulting set offers
- **THEN** the package is installed from the image's enabled repositories without the one left out and with the one
  added

#### Scenario: Repository already in the requested state

- **WHEN** `enableRepositories` names a repository the image already enables, or `disableRepositories` names one the
  image already leaves disabled
- **THEN** the feature installs the listed packages exactly as without that identifier

#### Scenario: Unknown repository fails before installation

- **WHEN** either list names an identifier of no repository the image configures, with a non-empty package list
- **THEN** on every supported `dnf` generation the feature exits with status 1, names the option and the identifier,
  loads no repository metadata, and installs none of the listed packages

#### Scenario: Identifier in another letter case is unknown

- **WHEN** either list names a configured repository's identifier spelled in a different letter case, with a non-empty
  package list
- **THEN** the feature exits with status 1, names the option and the identifier, and installs none of the listed
  packages

#### Scenario: Repository list cannot be read

- **WHEN** a repository list is not empty, the package list is not empty, and `dnf` fails to list the configured
  repositories
- **THEN** the feature exits with status 1 and installs none of the listed packages

#### Scenario: Refresh policy and timeout cover a temporarily enabled repository

- **WHEN** `refreshPolicy=always` or a non-empty `networkTimeout` is combined with `enableRepositories`
- **THEN** the temporarily enabled repository is checked and receives the timeout override like every other enabled
  repository

#### Scenario: Cache-only installation needs the metadata of a temporarily enabled repository

- **WHEN** `refreshPolicy=never` and `enableRepositories` names a repository without usable cached metadata
- **THEN** the feature fails before installing without attempting a metadata download

#### Scenario: Cache-only installation does not need a repository that is left out

- **WHEN** `refreshPolicy=never`, an enabled repository has no usable cached metadata, `disableRepositories` names it,
  and every other requirement of the cache-only policy is met
- **THEN** the feature installs the listed packages from the remaining repositories

#### Scenario: Cleanup covers a temporarily enabled repository

- **WHEN** `cleanup=all` and the feature has installed a package from a temporarily enabled repository
- **THEN** the image holds no downloaded package file and no repository metadata of that repository in `dnf`'s cache

#### Scenario: Package-file cleanup covers a temporarily enabled repository

- **WHEN** `cleanup=packages` and the feature has installed a package from a temporarily enabled repository
- **THEN** the image holds no downloaded package file of that repository in `dnf`'s cache

### Requirement: Parallel downloads are bounded

Empty parallelDownloads SHALL preserve native concurrency. A nonempty value bounds simultaneous downloads globally and
per enabled repository, overriding per-repository settings; mirror limits may lower actual concurrency. It changes no
timeout, retry, speed, mirror, checks, or persistent image setting.

#### Scenario: Native parallel downloads are inherited

- **WHEN** `parallelDownloads` is omitted or empty
- **THEN** no download-concurrency override is passed

#### Scenario: Explicit parallel downloads reach package downloads

- **WHEN** `parallelDownloads` is a valid non-empty value and installation downloads several packages
- **THEN** the install call receives the bound for `dnf` as a whole and for every enabled repository, and never more
  packages than the value are downloaded at the same time

#### Scenario: Repository setting does not replace the bound

- **WHEN** `parallelDownloads` is a valid non-empty value and an enabled repository's own configuration sets a different
  download concurrency
- **THEN** the option's value applies to that repository for this invocation

#### Scenario: Per-mirror limit still applies

- **WHEN** `parallelDownloads` is higher than the image's limit of downloads per mirror and every package comes from one
  mirror
- **THEN** the feature succeeds, and the number of simultaneous downloads stays within the image's per-mirror limit

### Requirement: Undeclared settings are inherited

The feature SHALL set no proxy, repository variable, DNF-config-selection environment, retry, or lock setting. DNF has
no bounded retry or lock wait on supported generations, so image configuration and build environment continue to govern
these behaviors unchanged.

#### Scenario: Proxy and repository variables are inherited

- **WHEN** the image's configuration or the build environment sets a proxy or a repository variable
- **THEN** `dnf` receives it as it would outside the feature, and the feature adds, changes, and removes none

#### Scenario: No retry or lock setting is passed

- **WHEN** the feature installs packages with any combination of its options
- **THEN** its `dnf` calls carry no retry setting, no lock setting, and no switch that skips a lock

## ADDED Requirements

### Requirement: Repository list syntax is constrained

Each enableRepositories and disableRepositories identifier SHALL start with an ASCII letter or digit and contain only
ASCII letters, digits, `_`, `.`, `:`, or `-`, independent of locale. The comma-separated lists ignore surrounding
whitespace, empty items, and duplicates. An identifier in both lists is refused. Accepted IDs are passed in one
argument, never shell code.

#### Scenario: Invalid repository identifier is rejected

- **WHEN** an identifier contains a pattern character, starts with `-`, contains `/`, `=`, inner whitespace or a
  non-ASCII letter, or appears in both lists
- **THEN** validation fails with status 1 naming the option and identifier before any change

### Requirement: Omitted repositories have explicit resolution risks

When an omitted repository carries a listed package or dependency, DNF SHALL fail as unresolvable; when it carries image
updates, DNF selects older versions available elsewhere. The feature accepts this because repository choice is explicit
in configuration. Explicitly enabling an image-configured testing repository is likewise an explicit devcontainer.json
choice visible to reviewers, including that repository's own signature and key settings.

#### Scenario: Omitted repository contains an update

- **WHEN** an omitted repository carries a newer version of a listed package than remaining enabled repositories
- **THEN** DNF selects only among the remaining enabled repositories

### Requirement: Repository-configured signing keys retain native trust

DNF MAY import a repository-configured signing key from a local or remote location; it remains in the RPM keyring after
verification failure. The feature SHALL name or supply no key and check no fingerprint or checksum. Remote transport
alone protects the key (TLS on HTTPS, none on HTTP). An explicitly enabled repository retains image key and signature
settings; this is accepted because those settings are visible in image configuration.

#### Scenario: Repository key is imported under image configuration

- **WHEN** a package signature requires a key named by the enabled repository configuration and not yet in the RPM
  keyring
- **THEN** DNF may import that configured key without confirmation, and the feature adds no key source or fingerprint
  check
