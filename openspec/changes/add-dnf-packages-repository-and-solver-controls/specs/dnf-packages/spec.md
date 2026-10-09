# Spec Delta

## ADDED Requirements

### Requirement: Option best

The feature SHALL accept the option `best` as declared here.

| Field   | Value                        |
| ------- | ---------------------------- |
| Type    | `string`                     |
| Default | `"inherit"`                  |
| Enum    | `["inherit","true","false"]` |

#### Scenario: Omitted best

- **WHEN** `best` is omitted
- **THEN** the feature uses `"inherit"` as specified by the requirements below

### Requirement: Option enableRepositories

The feature SHALL accept the option `enableRepositories` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted enableRepositories

- **WHEN** `enableRepositories` is omitted
- **THEN** the feature uses `""` as specified by the requirements below

### Requirement: Option disableRepositories

The feature SHALL accept the option `disableRepositories` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted disableRepositories

- **WHEN** `disableRepositories` is omitted
- **THEN** the feature uses `""` as specified by the requirements below

### Requirement: Option parallelDownloads

The feature SHALL accept the option `parallelDownloads` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted parallelDownloads

- **WHEN** `parallelDownloads` is omitted
- **THEN** the feature uses `""` as specified by the requirements below

### Requirement: Best-version policy is scoped to installation

With `best=inherit`, the feature SHALL pass no best-version setting, so the image's `dnf` configuration decides, as
before this option existed. With `best=true` or `best=false`, the feature SHALL set DNF's `best` setting to that value
for its install call only, whatever the image configures, in the same way on every supported `dnf` generation. Under
`true`, `dnf` uses the highest version the enabled repositories offer of each listed package or fails, so a listed
package that is installed and named without a version is upgraded when a higher version is offered. Under `false`, `dnf`
MAY fall back to a lower version of a listed package, and a listed package that is installed and named without a version
stays as installed. The policy SHALL NOT change how a pinned version is installed, permit erasing an installed package,
skip an unresolvable entry, or persist a setting in the image.

#### Scenario: Native best policy is inherited

- **WHEN** `best` is omitted or `inherit`
- **THEN** no best-version override is passed, and an installed package the list names without a version is upgraded or
  left as the image's `dnf` configuration decides

#### Scenario: Explicit best policy reaches the solver

- **WHEN** `best=true` and `packages` names, without a version, an installed package of which the enabled repositories
  offer a higher version
- **THEN** the feature succeeds and the package is upgraded to that version, also on an image whose configuration turns
  the best-version policy off

#### Scenario: Best policy is turned off for the invocation

- **WHEN** `best=false` and `packages` names, without a version, an installed package of which the enabled repositories
  offer a higher version
- **THEN** the feature succeeds and the package stays at its installed version, also on an image whose configuration
  turns the best-version policy on

#### Scenario: Pinned version is installed under either policy

- **WHEN** `best` is `true` or `false` and `packages` holds `name-version-release` for a version the enabled
  repositories offer
- **THEN** exactly that version of the package is installed, as the requirement "Version and architecture qualifiers"
  states

### Requirement: Repository selection is scoped to installation

The repositories enabled for an invocation SHALL be the repositories the image enables, without those named in
`disableRepositories`, together with those named in `enableRepositories`. Wherever this specification speaks of the
enabled repositories, it means that set: the refresh policy, the network timeout, the parallel-download bound, and the
signature requirement apply to a temporarily enabled repository as to any other, and a repository left out is neither
loaded nor required to hold cached metadata. With both options empty the feature SHALL pass no repository selection, so
the image's set applies, as before these options existed.

Both options name only repositories the image already configures. A listed identifier that equals, in the same letter
case, no identifier of a repository the image configures SHALL fail the feature with status 1 and a message naming the
identifier, before `dnf` loads repository metadata or changes a package, alike on every supported `dnf` generation. The
feature SHALL make this check itself, from `dnf`'s list of configured repositories and without network access, and only
when the package list is not empty; when that list cannot be read, the feature SHALL fail with status 1 before
installing. An identifier whose repository is already in the requested state SHALL be accepted and change nothing.

The selection SHALL apply to the feature's install call only: the feature SHALL NOT create, edit, or remove a repository
file, SHALL NOT select an exclusive repository set, expand a pattern, or pass a repository location, and the image's
enabled set SHALL be the same after the feature as before it. The cleanup the `cleanup` option selects SHALL cover the
cache of a temporarily enabled repository like that of any other.

Leaving a repository out is the developer's choice and is not checked: when it carries a listed package or a dependency
the installation fails as unresolvable, and when it carries the image's updates `dnf` selects the older versions the
remaining repositories offer. The feature accepts this because the value is explicit in the configuration.

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
- **THEN** on every supported `dnf` generation the feature exits with status 1, names the identifier, loads no
  repository metadata, and installs none of the listed packages

#### Scenario: Identifier in another letter case is unknown

- **WHEN** either list names a configured repository's identifier spelled in a different letter case
- **THEN** the feature exits with status 1, names the identifier, and installs none of the listed packages

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

### Requirement: Parallel downloads are bounded

An empty `parallelDownloads` SHALL leave the native download concurrency unchanged. A non-empty value SHALL be the upper
bound of simultaneous downloads on the feature's install call, set for `dnf` as a whole and for every enabled
repository, so that a repository's own setting cannot replace it. It is an upper bound only: the feature SHALL NOT
change the image's limit of downloads per mirror, which MAY keep the number of simultaneous downloads from one mirror
below the value. It SHALL NOT change the timeout, retry, speed, or mirror-selection settings, disable a check, or
persist a setting in the image.

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

The feature SHALL pass `dnf` no setting other than those its options declare. It SHALL NOT set a proxy, SHALL NOT set,
change, or unset a repository variable or any environment variable that selects `dnf` configuration, and SHALL NOT pass
a retry count, a lock setting, or a switch that skips a lock: `dnf` offers no bounded retry and no bounded lock wait on
the supported generations, so the feature declares no option for either and `dnf`'s own behavior applies. Proxy
settings, repository variables, retry behavior, and lock waiting therefore come from the image's configuration and the
build environment, unchanged by the feature.

#### Scenario: Proxy and repository variables are inherited

- **WHEN** the image's configuration or the build environment sets a proxy or a repository variable
- **THEN** `dnf` receives it as it would outside the feature, and the feature adds, changes, and removes none

#### Scenario: No retry or lock setting is passed

- **WHEN** the feature installs packages with any combination of its options
- **THEN** its `dnf` calls carry no retry setting, no lock setting, and no switch that skips a lock

## MODIFIED Requirements

### Requirement: Installation controls are validated before changes

The feature SHALL validate `installWeakDeps`, `refreshPolicy`, `cleanup`, `networkTimeout`, `best`,
`enableRepositories`, `disableRepositories`, `parallelDownloads` and all package entries before invoking any
package-manager command or creating any cache. Boolean options SHALL accept only `true` or `false`; enum options SHALL
accept only their declared values, in the letter case declared, and never an empty value. A non-empty `networkTimeout`
SHALL be a canonical ASCII decimal integer string from `1` through `3600`, with no sign, whitespace, leading zero, or
other character. A non-empty `parallelDownloads` SHALL be such a string from `1` through `20`; the feature refuses every
other value itself, because `dnf` accepts some of them and fails only when a download starts.

`enableRepositories` and `disableRepositories` SHALL each be a comma-separated list of repository identifiers in which
whitespace around an identifier and empty items are ignored and a repeated identifier counts once. An identifier SHALL
start with an ASCII letter or a digit and consist only of ASCII letters, digits, and the characters `_`, `.`, `:`, and
`-`, whatever the locale, so that a pattern, an option-like value, and an identifier holding `/`, `=`, or whitespace are
refused. An identifier present in both lists SHALL be refused. The feature SHALL hand every accepted identifier to `dnf`
as part of one argument and SHALL NOT evaluate it as shell code.

Invalid options SHALL fail with status 1 and a message naming the option, and for a refused identifier also that
identifier. With valid options and an empty package list, the feature SHALL succeed without refreshing, upgrading,
cleaning, or changing any configuration, also without the package manager, and without checking whether a listed
repository exists.

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

The feature SHALL install, with `dnf`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories enabled for this invocation: those the image enables, as
`enableRepositories` and `disableRepositories` adjust them. Weak Recommends and Supplements SHALL be excluded when
`installWeakDeps=false` and considered by DNF when `installWeakDeps=true`. Apart from that dependency selection, it
SHALL NOT upgrade installed packages other than the listed packages and what they need. A listed package that the image
already has MAY be upgraded when the list names it without a version, as the `best` option decides and, with
`best=inherit`, the image's `dnf` configuration.

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

### Requirement: Package signature checking stays in effect

The feature SHALL leave the signature checks that the image's `dnf` configuration sets in effect
(https://dnf.readthedocs.io/en/latest/conf_ref.html, `gpgcheck`; https://dnf5.readthedocs.io/en/latest/dnf5.conf.5.html,
`pkg_gpgcheck`): it SHALL NOT pass any option or configuration that disables or relaxes a signature or TLS check, and
SHALL NOT itself add or remove a repository, or change any repository file, signing key, or `dnf` configuration file in
the image. Enabling or disabling a repository through `enableRepositories` and `disableRepositories` applies to the
invocation only and changes none of those files. A repository for which the image's configuration turns the package
signature check off stays unchecked: the feature neither turns the check on nor refuses the repository. When a package's
signature needs a key that is not yet in the RPM keyring, `dnf` MAY import, without confirmation, the key that the
package's repository configuration names for it, from a local file or a remote location, and that key stays in the
keyring even when the signature check then fails. The feature checks such a key against no pinned fingerprint or
checksum: a key from a remote location relies on that location's transport alone, which is TLS for an HTTPS URL and no
protection for a plain HTTP URL. The feature names no key and passes no key location; every key `dnf` imports is one the
image's repository configuration names. Files that the packages it installs ship are not the feature's changes.

A repository named in `enableRepositories` is used with the settings its own configuration in the image gives it, its
signature check and key location included, and all of the above holds for it. The option therefore lets a
`devcontainer.json` install from a repository the image's author configured and left disabled, such as a testing
repository, one whose signature check is turned off, or one that names a remote key. The feature accepts this: the
repository and its settings come from the image, the feature adds no repository and relaxes no check, and the identifier
is explicit in the configuration, where a reviewer can see it.

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

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. The second installation MAY upgrade an installed package that its
list names without a version, or that a package of its list needs, and SHALL install a version its list pins, also below
the installed one.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages. A repository the first invocation enabled or left out, its
best-version policy, and its parallel-download bound SHALL NOT apply to the second, which starts from the image's
configuration; a package the first invocation installed from a temporarily enabled repository SHALL stay installed when
the second does not enable that repository.

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
