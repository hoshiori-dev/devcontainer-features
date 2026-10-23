# Spec Delta

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `apk`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories configured in the image, and SHALL leave each entry recorded in apk's
world (`/etc/apk/world`). It SHALL install other packages only as Install-if selection is automatic states, and SHALL
select versions as Installed versions stay without version options and Version controls remain targeted state.

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

The feature SHALL pass an entry of the form `name=version`, `name~version`, `name@tag`, or a name followed by one of
apk's range operators and a version (such as `name<version`, `name<=version`, `name>version`, or `name>=version`) to
`apk` unchanged, so that `apk` selects a version that equals the version, starts with it, lies in that range, or comes
from the repository the image configures with that tag, and keeps the entry as a constraint in its world for later apk
operations.

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

With `refreshPolicy=default` or `always`, the feature SHALL fetch and verify the index of every configured repository
before installation, even if existing indexes are available, and SHALL fail before installing when any repository fails.
With `never`, it SHALL use existing cached indexes without checking remote indexes, SHALL fail before installing when a
configured repository has no usable cached index, and SHALL NOT fall back to fetching an index.

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

The feature SHALL leave apk's signature verification against the keys the image trusts
(https://gitlab.alpinelinux.org/alpine/apk-tools/-/blob/v3.0.8/doc/apk-keys.5.scd) in effect, as Apk verification and
configuration are not weakened states. Options that the image's own apk configuration sets stay the image's decision:
the feature neither overrides nor checks them.

#### Scenario: Unverifiable repository fails the refresh

- **WHEN** a configured repository's index cannot be verified with the keys the image trusts
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Apk configuration is unchanged

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/apk`
- **THEN** the repository files, the trusted keys, and every file under `/etc/apk` other than the world are the same as
  before it ran

### Requirement: Clean package caches

After a successful installation, `cleanup=all` SHALL remove indexes and package files fetched into feature-owned caches;
`packages` SHALL remove feature-owned package files while leaving usable feature indexes; `none` SHALL perform no
explicit feature cache deletion. All modes SHALL leave /var/cache/apk and any cache configured through /etc/apk/cache as
they were, except that existing caches MAY be read. The feature SHALL NOT delete an unrelated cache.

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

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. For a name that both lists hold, the second entry, with its
constraint or without one, SHALL replace the first in apk's world. The second invocation SHALL use its own control
values, with no permanent override of image configuration.

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

The feature SHALL validate `refreshPolicy`, `cleanup`, `networkTimeout`, `upgradePackages`, `latest`, `lockTimeout` and
all package entries before invoking any package-manager command or creating any cache. Boolean options SHALL accept only
`true` or `false`; enum options SHALL accept only their declared values. Invalid options SHALL fail with status 1 and a
message naming the option.

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

When `latest=true`, the feature SHALL request, as `apk add --latest` resolves it, that every package listed without a
repository tag, and every dependency apk resolves for it, ends at the highest version the image's untagged repositories
offer. apk applies the policy neither to an entry `name@tag` nor to the dependencies it resolves for that entry, so with
`latest=true` such an entry SHALL resolve exactly as it does with `latest=false`.

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

An empty `lockTimeout` SHALL leave apk's lock behavior unchanged: the feature passes no lock wait, so apk fails at once
when another process holds its database lock, unless the image's own apk configuration sets a wait, which only an apk
generation that reads such configuration can do. A non-empty value SHALL be passed and enforced as Non-empty lock wait
applies to every apk call states.

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

The feature SHALL set, change, and unset no proxy variable and no environment variable that selects apk's configuration
on its apk calls, and SHALL create no apk configuration file: apk runs with the environment the build gives the feature
and reads the configuration the image holds.

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

### Requirement: Install-if selection is automatic

Besides the listed packages and their dependencies, the feature SHALL install only the packages that apk selects
automatically because all of their install-if conditions are met.

#### Scenario: Install-if package follows its conditions

- **WHEN** `packages` names a package whose documentation subpackage the repositories offer, together with the `docs`
  meta package
- **THEN** the documentation subpackage is installed as well

### Requirement: Installed versions stay without version options

When `upgradePackages=false` and `latest=false`, the feature SHALL NOT change the version of an installed package unless
an entry's constraint or a package it installs requires another version, or the image's own apk configuration sets a
version policy, which only an apk generation that reads such configuration honors and which stays the image's decision
(Repository authentication stays in effect).

#### Scenario: Installed version is kept without version options

- **WHEN** `upgradePackages=false`, `latest=false`, the image's apk configuration sets no version policy, and `packages`
  names, without a constraint, a package that is installed at a version older than the one the repositories offer, and
  no other listed package requires a newer version of it
- **THEN** the feature succeeds and the package stays at its installed version

### Requirement: Version controls remain targeted

When `upgradePackages=true`, the feature SHALL request upgrades of the listed packages and their dependencies as
`apk add --upgrade` resolves them. When `latest=true`, it SHALL select versions as Highest version is required on
request states. Under every combination of the two options it SHALL NOT request a whole-system upgrade.

#### Scenario: Upgrade option applies only to listed targets

- **WHEN** `upgradePackages=true` and a listed installed package has a newer installable version
- **THEN** the listed package and the dependencies `apk add --upgrade` resolves for it are upgraded, existing world
  constraints remain effective, and no whole-system upgrade is requested

### Requirement: Constraint failures and configured tags

An entry whose constraint `apk` cannot read, such as an operator without a version, fails the feature. A tag selects
only a repository the image already configures with that tag; the feature SHALL NOT add a repository or a tag. When the
installed version of a package does not satisfy its constraint, apk replaces it with a version that does, which can be a
lower one; when the repositories offer none, the feature fails.

#### Scenario: Unsatisfied installed version is replaced

- **WHEN** `packages` holds, for an installed package, a constraint that its installed version does not satisfy and that
  only a lower version the image's repositories offer satisfies
- **THEN** the package is replaced with that lower version, and the feature adds no repository or tag

### Requirement: Refresh reads image caches without changing them

Package files MAY still be downloaded under never. Existing image caches SHALL be read without modifying them; retained
feature indexes MAY be reused. Authentication SHALL remain in effect.

#### Scenario: Image caches are read but not modified

- **WHEN** the image already holds package indexes or package files in its own apk cache, with any `refreshPolicy`
- **THEN** those files are the same after the feature ran as before, and repository signatures are verified as without
  the feature

### Requirement: Apk verification and configuration are not weakened

The feature SHALL NOT pass any option or configuration that allows untrusted or unsigned packages or indexes, skips
server certificate verification, continues without an unavailable repository, or replaces the image's repositories or
trusted keys, and SHALL NOT itself add, remove, or change any repository, signing key, or apk configuration file in the
image. Files that the packages it installs ship are not the feature's changes.

#### Scenario: No verification-weakening option is passed

- **WHEN** the feature has installed packages none of which, with their dependencies, ships a file under `/etc/apk`
- **THEN** no apk call received an option that allows untrusted or unsigned packages or indexes, skips certificate
  verification, or continues without an unavailable repository, and the repository files, the trusted keys, and every
  file under `/etc/apk` other than the world are the same as before it ran

### Requirement: Retained feature caches are reusable

Retained feature caches SHALL be reusable on a later invocation, and every temporary work directory SHALL be removed
even on failure. Files that apk itself keeps in its cache directory beside indexes and package files are not package
files and MAY remain with `packages` and `none`.

#### Scenario: Later invocation reuses retained caches

- **WHEN** an earlier invocation with `cleanup=packages` or `cleanup=none` left feature caches, and a later invocation
  runs, also when either invocation fails
- **THEN** the later invocation can reuse the retained caches, and no temporary work directory of either invocation
  remains

### Requirement: Apk index retention follows cleanup mode

`cleanup` alone decides what the feature's cache keeps; no other option controls retention. apk stores in the feature's
cache the indexes it fetches and the package files it downloads, on every apk generation of the compatibility list, so
after a successful installation `none` SHALL leave both the indexes and the package files downloaded by that invocation
in the feature cache, `packages` SHALL leave the indexes without any package file, and `all` SHALL leave neither.

#### Scenario: Packages cleanup preserves feature indexes

- **WHEN** `cleanup=packages`, the image's apk configuration does not disable apk's cache, and the feature has installed
  a package that apk had to download, on any image of the compatibility list
- **THEN** the feature's cache holds the package index of every configured repository and no package file

### Requirement: Image-disabled apk cache remains disabled

The feature knowingly leaves one exception in place to what `packages` and `none` SHALL keep: when the image's own apk
configuration disables apk's cache, which only an apk generation that reads such configuration honors, apk stores
nothing, so with `refreshPolicy=default` or `always` the values `packages` and `none` keep nothing although the
installation succeeds.

#### Scenario: Image cache setting prevents feature retention

- **WHEN** `refreshPolicy=default` or `always`, `cleanup=none` or `cleanup=packages`, and the image's apk configuration
  disables apk's cache on an apk generation that reads such configuration
- **THEN** the feature succeeds, the listed packages are installed, and the feature's cache holds neither an index nor a
  package file

### Requirement: Image cache setting is neither overridden nor checked

The feature neither overrides nor checks an image apk configuration that disables what `packages` and `none` SHALL keep,
because options the image's apk configuration sets stay the image's decision (Repository authentication stays in effect)
and no argument that restores caching exists on every supported apk generation.

#### Scenario: Cache-disabling configuration stays in force

- **WHEN** `refreshPolicy=default` or `always` and the image's apk configuration disables apk's cache on an apk
  generation that reads such configuration
- **THEN** the feature succeeds, passes no argument that restores caching, and the image's configuration file is
  unchanged

### Requirement: Disabled cache under never is governed by refresh

With `refreshPolicy=never` and an image apk configuration that disables apk's cache, the outcome SHALL be the one
Package index refresh states: Clean package caches, Apk index retention follows cleanup mode, Retained feature caches
are reusable, Image-disabled apk cache remains disabled, and Image cache setting is neither overridden nor checked state
no outcome for that case.

#### Scenario: Missing cached index fails under a disabled cache

- **WHEN** `refreshPolicy=never`, the image's apk configuration disables apk's cache on an apk generation that reads
  such configuration, and a configured repository has no usable cached index
- **THEN** the feature fails before installing without attempting an index download

### Requirement: Second installation keeps or upgrades versions by its own options

When the second installation's upgradePackages and latest are both false, it SHALL NOT change an installed version
unless a constraint or dependency requires it or the image's own apk configuration sets a version policy, as Installed
versions stay without version options states; when its upgradePackages is true, it SHALL request the target upgrades
described by Version controls remain targeted.

#### Scenario: Second installation keeps an installed version

- **WHEN** `upgradePackages=false` and `latest=false` on the second invocation, the image's apk configuration sets no
  version policy, and the second's `packages` names, without a constraint, a package installed at a version older than
  the one the repositories offer that no other listed package requires to change
- **THEN** the second installation succeeds and the package stays at its installed version

### Requirement: Second installation with latest raises versions

When the second installation's latest is true, it SHALL select versions as Highest version is required on request
states, also for a package the first installation left at an older version, and SHALL NOT lower a version the first
installation selected through a `name@tag` entry.

#### Scenario: Second installation raises an older version

- **WHEN** the first invocation lists a package with `latest=false` and leaves it at a version older than the highest
  one the repositories offer, and the second lists the same package with `latest=true`
- **THEN** the second installation succeeds and the package is at the highest offered version

### Requirement: Later apk invocation uses only its own controls

Earlier cache choices SHALL NOT override the later refresh or cleanup policy. A version policy or lock wait of the first
invocation SHALL NOT apply to the second: the second passes only what its own `latest` and `lockTimeout` select.
Disabling optional dependencies on a later invocation SHALL NOT uninstall previously installed packages, and a later
`latest=false` SHALL NOT by itself lower a version an earlier `latest=true` selected.

#### Scenario: First invocation controls do not persist

- **WHEN** the first invocation sets `latest=true` and a `lockTimeout`, and the second omits both with the same
  `packages`
- **THEN** the second invocation passes neither a version policy nor a lock wait to apk and lowers no installed version

### Requirement: Timeout values are canonical and bounded

A non-empty `networkTimeout` SHALL be a canonical ASCII decimal integer string from `1` through `3600`, with no sign,
whitespace, leading zero, or other character, and a non-empty `lockTimeout` SHALL follow the same rule with the same
bounds. The feature SHALL refuse every `lockTimeout` value that apk itself would accept and read as no wait, as a
different number, or as an unbounded wait, such as `0`, text, a number followed by text, or a negative number.

#### Scenario: Lock values apk would misread are refused

- **WHEN** `lockTimeout` is `0`, text, a number followed by text, or a negative number
- **THEN** the feature exits with status 1, names `lockTimeout`, and runs no package-manager command

### Requirement: Empty package list skips the package manager

With valid options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or
changing any configuration, also without the package manager.

#### Scenario: Valid controls with an empty list succeed without apk

- **WHEN** `packages` is empty, valid non-default controls are provided, and the image has no `apk`
- **THEN** the feature succeeds without invoking the package manager, touching any cache, or changing any configuration

### Requirement: Highest-version failures do not fall back

When `latest=true` and apk cannot select the version Highest version is required on request requires, because the
entry's constraint or a constraint already in apk's world excludes it, the feature SHALL exit with a non-zero status and
SHALL leave the installed packages and apk's world as they were; it SHALL NOT fall back to an older version. This is the
difference from `upgradePackages=true`, which succeeds and keeps a held-back version.

#### Scenario: Latest fails on a held-back dependency

- **WHEN** `latest=true` and apk's world already pins a dependency of a package listed without a tag to a version older
  than the highest one the untagged repositories offer
- **THEN** the feature exits with a non-zero status, and the installed versions and apk's world are as they were before
  it ran

### Requirement: Latest lowers no version and combines with upgrade

The policy of `latest=true` SHALL NOT lower an installed version: a package installed at a higher version than the
untagged repositories offer, as an earlier `name@tag` entry can leave it, stays at that version when it is listed
without a tag. With both `latest` and `upgradePackages` true the feature SHALL request both; an entry without a tag then
has the outcome of `latest=true`, and an entry `name@tag` that of `upgradePackages=true`.

#### Scenario: Higher installed version is kept under latest

- **WHEN** `latest=true` and a package installed at a higher version than the untagged repositories offer is listed
  without a tag
- **THEN** the feature succeeds and the package stays at its installed version

#### Scenario: Both version options reach apk

- **WHEN** `latest=true` and `upgradePackages=true`
- **THEN** apk receives both policies; entries without a tag have the outcome of `latest=true` alone, and entries
  `name@tag` that of `upgradePackages=true` alone

### Requirement: Latest=false inherits version policy

When `latest=false`, the feature SHALL add no version policy, so apk resolves as it does without the option; a version
policy that the image's own apk configuration sets stays the image's decision, as Repository authentication stays in
effect states. `latest` SHALL NOT change how an entry is recorded in apk's world, SHALL NOT affect install-if selection,
SHALL NOT request a whole-system upgrade, and SHALL NOT persist: a later apk operation without it may keep an older
version.

#### Scenario: Latest omitted preserves native version selection

- **WHEN** `latest` is omitted for a non-empty package list
- **THEN** the feature passes no version policy and apk's world holds each entry as written

### Requirement: Latest-version policy leaves its accepted risks explicit

The feature knowingly leaves three risks in place in the policy that `latest=true` SHALL request; this is the first, and
Latest policy raises unlisted packages and Latest policy leaves tagged entries unraised state the others. The policy is
a requirement, not a preference, so a build that used to succeed with a pinned or held-back package fails once
`latest=true`; relaxing it would make the option a silent duplicate of `upgradePackages`.

#### Scenario: Pinned build fails once latest is requested

- **WHEN** `latest=true` and `packages` holds `name=version` that the untagged repositories can satisfy only with a
  version lower than the highest one they offer
- **THEN** the feature exits with a non-zero status

### Requirement: Latest policy raises unlisted packages

The second risk the feature knowingly leaves in place in the policy that `latest=true` SHALL request: the policy also
changes packages the developer did not list: the dependencies of the listed packages move to their highest versions, and
so do installed packages that depend on a raised package at an exact version; apk offers no narrower form of the policy.

#### Scenario: Unlisted dependency is raised

- **WHEN** `latest=true` and a dependency of a package listed without a tag is installed at a version older than the
  highest one the untagged repositories offer
- **THEN** the feature succeeds and that dependency is at its highest offered version

### Requirement: Latest policy leaves tagged entries unraised

The third risk the feature knowingly leaves in place in the policy that `latest=true` SHALL request: the policy does not
reach `name@tag` entries, so `latest=true` alone can leave such a package at an older version without failing; apk
offers no form of the policy that covers them, and `upgradePackages=true` is the control that raises them.

#### Scenario: Tagged entry stays outside latest policy

- **WHEN** `latest=true`, `upgradePackages=false`, and `packages` holds `name@tag` for a tag the image configures, and
  resolving it as with `latest=false` leaves the package at a version older than the highest one offered
- **THEN** the feature succeeds, and the installed versions and apk's world are the same as with `latest=false`

### Requirement: Non-empty lock wait applies to every apk call

A non-empty `lockTimeout` SHALL be passed as apk's wait, in seconds, for its exclusive database lock on every apk call
the feature makes, including the offline index check of `refreshPolicy=never`, and SHALL override a wait the image
configures for that call only. When the lock is not released within the wait, the feature SHALL exit with a non-zero
status without installing any listed package.

#### Scenario: Non-empty lock wait reaches every apk call

- **WHEN** `lockTimeout` is a valid non-empty value, with any `refreshPolicy`
- **THEN** every apk call the feature makes, the install call and before it the refresh call or, with
  `refreshPolicy=never`, the offline index check, receives that value as apk's lock wait

### Requirement: Lock timeout is per apk call

Each apk call waits separately up to the `lockTimeout` value: it SHALL NOT be an overall build deadline, a retry of a
call that failed, or a wait for anything other than the lock, and it SHALL NOT persist a setting in the image.

#### Scenario: Each call waits on its own

- **WHEN** `lockTimeout` is set and another process holds apk's database lock during the feature's apk calls
- **THEN** each apk call waits up to that value for the lock only, failed calls are not retried, and no lock setting is
  left in the image

### Requirement: Per-call lock wait risk is accepted

The feature knowingly leaves one risk in place in the wait that `lockTimeout` SHALL pass to every apk call: each of the
two apk calls of an installation waits separately. A lock held without interruption fails the build after one wait, but
a lock that is released during the first call's wait and taken again before the second call can delay a failing build by
up to twice the value. A single deadline would need the feature to time apk itself, which apk's own wait does not offer.

#### Scenario: Lock held without interruption fails after one wait

- **WHEN** `lockTimeout` is set and another process holds apk's database lock without interruption for longer than that
  many seconds
- **THEN** the feature fails after one wait

#### Scenario: Lock reacquisition can consume two waits

- **WHEN** another process releases the database lock during the first call's wait and takes it again before the second
  call
- **THEN** each call waits independently up to the configured value, so a failing build can be delayed by up to twice
  the value

### Requirement: Version, lock and timeout defaults add no argument

Of the apk settings that `networkTimeout`, `lockTimeout`, `latest`, and `upgradePackages` govern (network timeout, lock
wait, and version policy), each option at its default SHALL add no argument, so the matching setting of the image, where
its apk reads one, or apk's own default applies.

#### Scenario: Image or apk default applies

- **WHEN** `networkTimeout`, `lockTimeout`, `latest`, and `upgradePackages` are at their defaults with a non-empty
  package list
- **THEN** no apk call receives a timeout, a lock wait, or a version policy from the feature, and the image's setting,
  where its apk reads one, or apk's own default applies

### Requirement: Non-default controls override per invocation

A non-default value of `networkTimeout`, `lockTimeout`, `latest`, or `upgradePackages` SHALL override only its matching
apk setting, as a command-line argument of the feature's own apk calls, for that invocation. What the feature sets on
every apk call whatever these options hold stays its own and is not inherited: non-interactive mode, the feature's cache
directory, and the index age that goes with it, as Non-interactive installation, Package index refresh, and Clean
package caches define them.

#### Scenario: Override is a command-line argument of the feature's apk calls

- **WHEN** `networkTimeout` has a valid non-default value and the image's apk configuration sets a network timeout
- **THEN** the feature's own apk calls receive the value as a command-line argument, the image's configuration file is
  unchanged, and non-interactive mode and the feature's cache directory apply as with default controls
