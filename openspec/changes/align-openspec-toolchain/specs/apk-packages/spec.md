# Spec Delta

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install listed packages and dependencies only from image repositories, recording entries in apk world
(`/etc/apk/world`), plus packages selected by satisfied install-if conditions. With both version controls false it SHALL
preserve installed versions except when constraints, dependencies, or image policy require change; upgradePackages
requests targeted upgrades, latest follows its requirement, and neither requests a whole-system upgrade.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0, both packages, with their dependencies, are installed, and each entry is a
  line of apk's world

#### Scenario: Install-if packages follow their conditions

- **WHEN** `packages` names a package whose documentation subpackage the repositories offer, together with the `docs`
  meta package
- **THEN** the documentation subpackage is installed as well

#### Scenario: Listed package already installed stays at its version

- **WHEN** `upgradePackages=false`, `latest=false`, the image's apk configuration sets no version policy, and `packages`
  names, without a constraint, a package that is installed at a version older than the one the repositories offer, and
  no other listed package requires a newer version of it
- **THEN** the feature succeeds and the package stays at its installed version

#### Scenario: Listed packages are upgraded on request

- **WHEN** upgradePackages=true and a listed installed package has a newer installable version
- **THEN** the listed package and dependencies selected by apk add are upgraded, existing world constraints remain
  effective, and no whole-system upgrade is requested

#### Scenario: Highest version is required without the upgrade option

- **WHEN** `latest=true`, `upgradePackages=false`, and an installed package listed without a tag has a newer installable
  version in the untagged repositories
- **THEN** the listed package and the dependencies apk resolves for it are at their highest offered versions, install-if
  packages follow their conditions as before, and no whole-system upgrade is requested

### Requirement: Version constraints and repository tags

The feature SHALL pass `name=version`, `name~version`, `name@tag`, and apk range entries (`name<version`,
`name<=version`, `name>version`, or `name>=version`) unchanged and retain them in apk world. Apk enforces exact, prefix,
range, or configured-tag selection; malformed or unsatisfied constraints fail. The feature adds no repository or tag; a
constraint may replace an installed package with a lower version.

#### Scenario: Pinned version is installed

- **WHEN** `packages` holds `name=version` for a version the image's repositories offer
- **THEN** exactly that version of the package is installed and apk's world holds the entry `name=version`

#### Scenario: Prefix constraint is installed

- **WHEN** `packages` holds `name~prefix` with a prefix of a version the image's repositories offer
- **THEN** a version of the package that starts with that prefix is installed

#### Scenario: Range constraint is installed

- **WHEN** `packages` holds `name>=version` that a version the image's repositories offer satisfies
- **THEN** a version of the package that satisfies the constraint is installed and apk's world holds the entry
  `name>=version`

#### Scenario: Unsatisfied range constraint fails

- **WHEN** `packages` holds `name<version` that no version the image's repositories offer satisfies
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Malformed constraint fails

- **WHEN** `packages` holds an entry that ends in a range operator, such as `name>`
- **THEN** the feature exits with a non-zero status, installs none of the listed packages, and leaves apk's world as it
  was

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

### Requirement: Package index refresh

For default and always, the feature SHALL fetch and verify every configured repository index before installing, even if
indexes exist, and fail before install if any fails. never uses usable cached indexes only, fails before install if one
is missing, and never falls back to refresh; package files may still download. Existing image caches are read-only;
retained feature indexes may be reused and authentication remains in effect.

#### Scenario: Unavailable repository fails the feature

- **WHEN** `refreshPolicy=default` and the index of one configured repository cannot be fetched while the others can
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Index present in the image is not used

- **WHEN** `refreshPolicy=default` and the image already holds, in apk's cache, a fresh package index together with the
  package files of the listed packages and their dependencies, and no configured repository can be reached
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

The feature SHALL preserve apk signature verification against image-trusted keys
(https://gitlab.alpinelinux.org/alpine/apk-tools/-/blob/v3.0.8/doc/apk-keys.5.scd). It SHALL NOT weaken package/index or
TLS checks, continue past unavailable repositories, or change repositories, keys, or apk configuration. Image-set apk
options stay the image’s decision and are neither overridden nor checked; package-shipped files are excluded.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** a configured repository's index cannot be verified with the keys the image trusts
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Apk configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/apk`
- **THEN** the repository files, the trusted keys, and every file under `/etc/apk` other than the world are the same as
  before it ran

### Requirement: Clean package caches

After success, cleanup SHALL remove fetched indexes and package files from feature-owned caches for all; package files
but not usable indexes for packages; and no files explicitly for none. Image caches remain unchanged except reads;
unrelated caches are never deleted, retained caches are reusable, and temporary work directories are removed even on
failure.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** no package index or package file fetched into a feature-owned cache remains in the image, and
  `/var/cache/apk` holds the same files as before it ran

#### Scenario: Only package files are cleaned

- **WHEN** cleanup=packages with usable metadata and package files present in the managed cache after installation
- **THEN** package files are removed from the managed cache and usable metadata remains

#### Scenario: Feature cleanup is disabled

- **WHEN** `cleanup=none`, the image's apk configuration does not disable apk's cache, and the feature has installed a
  package that apk had to download, on any image of the compatibility list
- **THEN** the feature's cache holds the package index of every configured repository and the package file of that
  package

#### Scenario: Existing image caches are preserved

- **WHEN** any cleanup mode is selected and pre-existing image caches contain sentinel files
- **THEN** those files remain unchanged; cleanup affects feature-owned caches only

#### Scenario: Image configuration that disables caching keeps nothing

- **WHEN** `refreshPolicy=default` or `always`, `cleanup=none` or `cleanup=packages`, and the image's apk configuration
  disables apk's cache on an apk generation that reads such configuration
- **THEN** the feature succeeds, the listed packages are installed, the feature's cache holds neither an index nor a
  package file, and the image's configuration file is unchanged

### Requirement: Installing the feature twice

A second installation SHALL keep packages from either list and replace a shared entry in apk world with the later
constraint. The second list follows normal upgradePackages and latest behavior, including raising earlier versions
without lowering tagged versions. Its refresh, cleanup, version, and lock controls apply only to that invocation;
disabling optional dependencies never uninstalls earlier packages.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Later entry replaces the earlier constraint

- **WHEN** `upgradePackages=false` and `latest=false` on the second invocation, the image's apk configuration sets no
  version policy, and the first installation's `packages` holds `name=version` and the second's holds `name` without a
  constraint
- **THEN** the second installation succeeds, apk's world holds `name` without a constraint, and the installed version
  stays as it was

#### Scenario: Unsatisfiable constraint on the second install

- **WHEN** the second installation's `packages` holds, for an installed package, a constraint that no version the
  repositories offer satisfies
- **THEN** the second installation exits with a non-zero status, and the installed version and apk's world stay as they
  were

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different refresh or cleanup values with a
  non-empty compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

#### Scenario: Later version policy applies to the second installation

- **WHEN** the first invocation lists a package with `latest=false` and leaves it at a version older than the highest
  one the repositories offer, and the second lists the same package with `latest=true`
- **THEN** the second installation succeeds, the package is at the highest offered version, and apk's world holds the
  entry once

#### Scenario: Later untagged entry keeps a higher tagged version

- **WHEN** the first invocation lists `name@tag` and installs from the tagged repository a version higher than the
  untagged repositories offer, and the second lists `name` without a tag with `latest=true`
- **THEN** the second installation succeeds, the package stays at its installed version, and apk's world holds `name`
  without the tag

#### Scenario: Earlier version policy and lock wait do not carry over

- **WHEN** the first invocation sets `latest=true` and a `lockTimeout`, and the second omits both with the same
  `packages`
- **THEN** the second installation succeeds, passes neither a version policy nor a lock wait to apk, lowers no installed
  version, and finds no setting of the first in the image's apk configuration

### Requirement: Installation controls are validated before changes

Before any package-manager command or cache creation, the feature SHALL validate all controls and entries: booleans are
exactly true/false, enums use declared values, and non-empty network and lock timeouts are canonical ASCII decimals
1–3600. Lock values apk would read as zero, another number, or unbounded are refused. Invalid values fail status 1
naming the option; valid empty lists succeed without refresh, upgrade, cleanup, configuration changes, or apk.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Timeout boundaries are validated

- **WHEN** networkTimeout is empty, 1, or 3600, or an invalid value such as 0, 3601, 01, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails before a package-manager command

#### Scenario: Lock wait boundaries are validated

- **WHEN** lockTimeout is empty, the lowest or the highest accepted number of seconds, or an invalid value such as a
  number below or above the range, a number with a leading zero, a sign, or a trailing letter, whitespace, or shell text
- **THEN** empty and the two boundaries are accepted; every invalid value fails with status 1 naming `lockTimeout`
  before a package-manager command, also when packages is empty

#### Scenario: Version policy value is validated

- **WHEN** `latest` holds anything other than `true` or `false`, such as an empty value or a word in another case, also
  when packages is empty
- **THEN** the feature exits with status 1, names `latest`, and runs no package-manager command

### Requirement: Highest version is required on request

With latest=true, apk add --latest SHALL select the highest version from untagged repositories for untagged entries and
their dependencies. If a constraint or apk-world pin excludes it, the feature fails without package/world changes and
does not fall back; unlike upgradePackages, it does not keep held-back versions. Tagged entries and their dependencies
ignore this policy; existing higher versions are not lowered.

#### Scenario: Listed package is raised to the highest version

- **WHEN** `latest=true`, `upgradePackages=false`, and `packages` names, without a constraint or a tag, a package that
  is installed at a version older than the highest one the image's untagged repositories offer
- **THEN** the feature succeeds, the package is at that highest version, and apk's world holds the entry as written

#### Scenario: Dependencies are raised with the listed package

- **WHEN** `latest=true` and a dependency of a package listed without a tag is installed at a version older than the
  highest one the untagged repositories offer
- **THEN** the feature succeeds and both the listed package and that dependency are at their highest offered versions

#### Scenario: Held-back dependency fails instead of being kept

- **WHEN** `latest=true` and apk's world already pins a dependency of a package listed without a tag to a version older
  than the highest one the untagged repositories offer
- **THEN** the feature exits with a non-zero status, and the installed versions and apk's world are as they were before
  it ran

#### Scenario: Held-back dependency is kept by the upgrade option alone

- **WHEN** `latest=false`, `upgradePackages=true`, and apk's world already pins a dependency of a listed package to a
  version older than the highest one the repositories offer
- **THEN** the feature succeeds and the pinned dependency stays at its version

#### Scenario: Entry constraint that excludes the highest version fails

- **WHEN** `latest=true` and `packages` holds `name=version` or `name<version` that the untagged repositories can
  satisfy only with a version lower than the highest one they offer
- **THEN** the feature exits with a non-zero status, and the installed versions and apk's world are as they were before
  it ran

#### Scenario: Entry constraint that admits the highest version succeeds

- **WHEN** `latest=true` and `packages` holds `name=version`, `name>=version`, or `name~prefix` that the highest version
  the untagged repositories offer satisfies
- **THEN** the feature succeeds, the package is at that highest version, and apk's world holds the entry with its
  constraint

#### Scenario: Untagged entry does not take a tagged repository's version

- **WHEN** `latest=true`, the image configures a repository with a tag that offers a higher version of a package than
  its untagged repositories do, the package is not installed, and `packages` names it without a tag
- **THEN** the feature succeeds and the package is at the highest version of the untagged repositories

#### Scenario: Tagged entry resolves as without the policy

- **WHEN** `latest=true` and `packages` holds `name@tag` for a tag the image configures
- **THEN** the installed versions and apk's world are the same as the same invocation with `latest=false` leaves them,
  also when that leaves the package or one of its dependencies at a version older than the highest one offered

#### Scenario: Both version options are requested

- **WHEN** `latest=true` and `upgradePackages=true`
- **THEN** apk receives both policies; for entries without a tag the installed versions and apk's world are the same as
  with `latest=true` alone, and for entries `name@tag` the same as with `upgradePackages=true` alone

#### Scenario: Policy behaves the same on every apk generation

- **WHEN** `latest=true` on any image of the feature's compatibility list
- **THEN** the same policy reaches `apk add`, and a version apk cannot select fails with a non-zero status whose value
  the feature does not specify

### Requirement: Lock wait is scoped to installation

An empty lockTimeout SHALL pass no wait and leave apk/image behavior in force. A non-empty value is passed in seconds to
every apk call, including the never offline index check, overriding image wait only for that call. Each call waits
separately; it is no deadline, retry, or other wait, does not persist, and a lock held beyond it fails before package
installation.

#### Scenario: Native lock behavior is inherited

- **WHEN** `lockTimeout` is omitted or empty
- **THEN** no lock wait is passed to any apk call, and a lock held by another process is handled as the image's apk
  would handle it without the feature

#### Scenario: Explicit lock wait reaches every apk call

- **WHEN** `lockTimeout` is a valid non-empty value, with any `refreshPolicy`
- **THEN** every apk call the feature makes, the install call and before it the refresh call or, with
  `refreshPolicy=never`, the offline index check, receives that value as apk's lock wait, and no other apk setting
  changes

#### Scenario: Lock released within the wait

- **WHEN** `lockTimeout` is set and another process holds apk's database lock for less than that many seconds
- **THEN** the feature waits, then succeeds and installs the listed packages

#### Scenario: Lock held beyond the wait

- **WHEN** `lockTimeout` is set and another process holds apk's database lock for longer than that many seconds
- **THEN** the feature exits with a non-zero status, not before that many seconds have passed, installs none of the
  listed packages, and leaves apk's world as it was

#### Scenario: Image wait setting is overridden for the invocation

- **WHEN** the image's apk configuration sets a lock wait, the image's apk reads that configuration, and `lockTimeout`
  holds another value
- **THEN** the feature's apk calls wait for the value of `lockTimeout`, and the image's configuration file is unchanged

#### Scenario: Lock wait works with a network timeout

- **WHEN** `lockTimeout` and `networkTimeout` are both valid non-empty values
- **THEN** every apk call the feature makes receives both, each as its own apk setting

### Requirement: Image configuration and environment are inherited

The feature SHALL leave proxy and apk configuration-selection environment unchanged and create no apk config. Default
networkTimeout, lockTimeout, latest, and upgradePackages add no arguments; non-defaults override only their matching
setting for this invocation. Non-interactive mode, the feature cache, and associated index age are always
feature-controlled.

#### Scenario: Default controls add no argument

- **WHEN** `networkTimeout`, `lockTimeout`, `latest`, and `upgradePackages` are omitted with a non-empty package list
- **THEN** no apk call receives a timeout, a lock wait, or a version policy from the feature

#### Scenario: Proxy environment is left as the build provides it

- **WHEN** the environment the feature runs in holds proxy variables
- **THEN** every apk call the feature makes runs with those variables unchanged, and the feature adds none

#### Scenario: Configuration selection is left to the image

- **WHEN** the image holds an apk configuration file or the environment names one
- **THEN** the feature neither writes, replaces, nor redirects it, and of the network timeout, the lock wait, and the
  version policy only those whose option has a non-default value are overridden, for the feature's own apk calls

## ADDED Requirements

### Requirement: Install-if packages follow apk conditions

Besides listed packages and their dependencies, the feature SHALL install only packages apk automatically selects when
all their install-if conditions are met.

#### Scenario: Install-if condition is met

- **WHEN** a listed package has an install-if package whose conditions are all satisfied
- **THEN** apk installs that package

### Requirement: Version controls remain targeted

With upgradePackages=true, the feature SHALL request apk add --upgrade for listed packages and their dependencies. With
latest=true, it SHALL use the highest-version behavior of Highest version is required on request. Neither setting
requests a whole-system upgrade.

#### Scenario: Upgrade option applies only to listed targets

- **WHEN** upgradePackages=true and a listed package or dependency has a newer installable version
- **THEN** apk requests the targeted upgrade without a whole-system upgrade

### Requirement: Apk index retention follows cleanup mode

The feature SHALL leave cleanup as the sole control of cache retention. On every supported apk generation, the feature
cache holds fetched indexes and downloaded package files: none retains both, packages retains indexes without package
files, and all retains neither. Apk adjunct files beside indexes and package files may remain for packages and none.

#### Scenario: Packages cleanup preserves feature indexes

- **WHEN** cleanup=packages after successful installation
- **THEN** feature-owned package files are removed while usable indexes remain

### Requirement: Image-disabled apk cache remains disabled

The feature SHALL knowingly leave this exception: if image apk configuration disables caching on a generation that reads
it, apk stores nothing. With refreshPolicy=default or always and cleanup packages or none, installation still succeeds
but retains no feature index or package file. The feature neither overrides nor checks this image decision because not
every supported apk generation has an argument restoring cache. Outcome under refreshPolicy=never is governed by
index-refresh behavior.

#### Scenario: Image cache setting prevents feature retention

- **WHEN** image apk configuration disables caching and refreshPolicy is default or always
- **THEN** installation succeeds without a feature-owned index or package file, and image configuration is unchanged

### Requirement: Later apk invocation uses only its own controls

Earlier refresh, cleanup, latest, lockTimeout, and upgrade settings SHALL NOT persist. A later latest=false alone does
not lower an earlier version; disabling optional dependencies does not uninstall prior packages.

#### Scenario: First invocation controls do not persist

- **WHEN** the first install sets latest or lockTimeout and the second omits them
- **THEN** the second call uses only its own values and does not lower installed versions

### Requirement: Highest-version failures and option interaction

With latest=true, untagged entries and their dependencies SHALL require highest untagged-repository versions. A
disqualifying entry or apk-world constraint fails without changing installed packages or world and never falls back;
upgradePackages=true alone instead keeps a held-back version. With both options true, latest governs untagged entries
and upgrade governs tagged entries.

#### Scenario: Latest fails on a held-back dependency

- **WHEN** an apk-world constraint pins a dependency below the highest offered version with latest=true
- **THEN** installation fails and installed packages and apk world remain unchanged

### Requirement: Latest-version policy leaves its accepted risks explicit

The feature SHALL knowingly leave three risks: latest is mandatory and can turn a formerly successful pinned/held-back
build into failure (otherwise it duplicates upgradePackages); it raises unlisted dependencies and exact-version
dependents because apk offers no narrower policy; and it does not reach tagged entries, which require
upgradePackages=true to raise.

#### Scenario: Tagged entry stays outside latest policy

- **WHEN** latest=true for an entry tagged with a configured repository
- **THEN** it resolves as with latest=false, including when its version is below the untagged maximum

### Requirement: Latest=false inherits version policy

When latest is false, the feature SHALL add no version policy, so apk resolves without this option; any version policy
the image configuration sets remains the image’s decision. Latest SHALL NOT alter apk world entries, affect install-if
selection, request a system upgrade, or persist to later apk operations.

#### Scenario: Latest omitted preserves native version selection

- **WHEN** latest is omitted for a non-empty package list
- **THEN** the feature passes no version policy and apk world keeps the entry as written

### Requirement: Lock timeout preserves image defaults and invocation scope

An empty lockTimeout SHALL pass no wait; apk fails immediately on a held lock unless an apk generation reads an
image-configured wait. A non-empty value overrides image wait only for each feature call and does not persist.

#### Scenario: Image lock setting applies when feature option is empty

- **WHEN** lockTimeout is empty and the image configures a wait on an apk generation that reads it
- **THEN** the feature passes no override and apk uses its image configuration

### Requirement: Lock timeout is per apk call

Each apk call SHALL wait separately up to lockTimeout; an interrupted and reacquired lock can delay a failing build up
to twice the value. A single deadline would require timing apk itself, which apk's lock wait does not provide.

#### Scenario: Lock reacquisition can consume two waits

- **WHEN** another process releases the database lock during the first call’s wait and reacquires it before the second
  call
- **THEN** each call waits independently up to the configured value
