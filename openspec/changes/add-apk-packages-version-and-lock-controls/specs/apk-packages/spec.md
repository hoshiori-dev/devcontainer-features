# Spec Delta

## ADDED Requirements

### Requirement: Option latest

The feature SHALL accept the option `latest` as declared here.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted latest

- **WHEN** `latest` is omitted
- **THEN** the feature uses `false`: it passes no version policy to apk, and versions are selected as Install the listed
  packages states

#### Scenario: Latest is requested

- **WHEN** `latest=true` with a non-empty package list
- **THEN** versions are selected as Highest version is required on request states

### Requirement: Option lockTimeout

The feature SHALL accept the option `lockTimeout` as declared here.

| Field   | Value    |
| ------- | -------- |
| Type    | `string` |
| Default | `""`     |

#### Scenario: Omitted lockTimeout

- **WHEN** `lockTimeout` is omitted
- **THEN** the feature uses `""`: it passes no lock wait to apk, as Lock wait is scoped to installation states

#### Scenario: Lock wait is requested

- **WHEN** `lockTimeout` is a whole number of seconds from 1 through 3600 with a non-empty package list
- **THEN** every apk call the feature makes waits for apk's database lock as Lock wait is scoped to installation states

### Requirement: Highest version is required on request

When `latest=true`, the feature SHALL request, as `apk add --latest` resolves it, that every package listed without a
repository tag, and every dependency apk resolves for it, ends at the highest version the image's untagged repositories
offer. When apk cannot select that version, because the entry's constraint or a constraint already in apk's world
excludes it, the feature SHALL exit with a non-zero status and SHALL leave the installed packages and apk's world as
they were; it SHALL NOT fall back to an older version. This is the difference from `upgradePackages=true`, which
succeeds and keeps a held-back version.

apk applies the policy neither to an entry `name@tag` nor to the dependencies it resolves for that entry, so with
`latest=true` such an entry SHALL resolve exactly as it does with `latest=false`. The policy SHALL NOT lower an
installed version: a package installed at a higher version than the untagged repositories offer, as an earlier
`name@tag` entry can leave it, stays at that version when it is listed without a tag. With both `latest` and
`upgradePackages` true the feature SHALL request both; an entry without a tag then has the outcome of `latest=true`, and
an entry `name@tag` that of `upgradePackages=true`.

When `latest=false`, the feature SHALL add no version policy, so apk resolves as it does without the option; a version
policy that the image's own apk configuration sets stays the image's decision, as Repository authentication stays in
effect states. `latest` SHALL NOT change how an entry is recorded in apk's world, SHALL NOT affect install-if selection,
SHALL NOT request a whole-system upgrade, and SHALL NOT persist: a later apk operation without it may keep an older
version.

The feature knowingly leaves three risks in place. The policy is a requirement, not a preference, so a build that used
to succeed with a pinned or held-back package fails once `latest=true`; relaxing it would make the option a silent
duplicate of `upgradePackages`. The policy also changes packages the developer did not list: the dependencies of the
listed packages move to their highest versions, and so do installed packages that depend on a raised package at an exact
version; apk offers no narrower form of the policy. And the policy does not reach `name@tag` entries, so `latest=true`
alone can leave such a package at an older version without failing; apk offers no form of the policy that covers them,
and `upgradePackages=true` is the control that raises them.

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
generation that reads such configuration can do. A non-empty value SHALL be passed as apk's wait, in seconds, for its
exclusive database lock on every apk call the feature makes, including the offline index check of `refreshPolicy=never`,
and SHALL override a wait the image configures for that call only. Each call waits separately up to the value: it SHALL
NOT be an overall build deadline, a retry of a call that failed, or a wait for anything other than the lock, and it
SHALL NOT persist a setting in the image. When the lock is not released within the wait, the feature SHALL exit with a
non-zero status without installing any listed package.

The feature knowingly leaves one risk in place: each of the two apk calls of an installation waits separately. A lock
held without interruption fails the build after one wait, but a lock that is released during the first call's wait and
taken again before the second call can delay a failing build by up to twice the value. A single deadline would need the
feature to time apk itself, which apk's own wait does not offer.

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
and reads the configuration the image holds. Of the apk settings that `networkTimeout`, `lockTimeout`, `latest`, and
`upgradePackages` govern (network timeout, lock wait, and version policy), each option at its default SHALL add no
argument, so the matching setting of the image, where its apk reads one, or apk's own default applies. A non-default
value SHALL override only its matching apk setting, as a command-line argument of the feature's own apk calls, for that
invocation. What the feature sets on every apk call whatever these options hold stays its own and is not inherited:
non-interactive mode, the feature's cache directory, and the index age that goes with it, as Non-interactive
installation, Package index refresh, and Clean package caches define them.

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

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `apk`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories configured in the image, and SHALL leave each entry recorded in apk's
world (`/etc/apk/world`). Besides the listed packages and their dependencies, it SHALL install only the packages that
apk selects automatically because all of their install-if conditions are met. When `upgradePackages=false` and
`latest=false`, it SHALL NOT change the version of an installed package unless an entry's constraint or a package it
installs requires another version, or the image's own apk configuration sets a version policy, which only an apk
generation that reads such configuration honors and which stays the image's decision (Repository authentication stays in
effect). When `upgradePackages=true`, it SHALL request upgrades of the listed packages and their dependencies as
`apk add --upgrade` resolves them. When `latest=true`, it SHALL select versions as Highest version is required on
request states. Under every combination of the two options it SHALL NOT request a whole-system upgrade.

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

### Requirement: Clean package caches

After a successful installation, `cleanup=all` SHALL remove indexes and package files fetched into feature-owned caches;
`packages` SHALL remove feature-owned package files while leaving usable feature indexes; `none` SHALL perform no
explicit feature cache deletion. All modes SHALL leave /var/cache/apk and any cache configured through /etc/apk/cache as
they were, except that existing caches MAY be read. The feature SHALL NOT delete an unrelated cache. Retained feature
caches SHALL be reusable on a later invocation, and every temporary work directory SHALL be removed even on failure.

`cleanup` alone decides what the feature's cache keeps; no other option controls retention. apk stores in the feature's
cache the indexes it fetches and the package files it downloads, on every apk generation of the compatibility list, so
after a successful installation `none` SHALL leave both the indexes and the package files downloaded by that invocation
in the feature cache, `packages` SHALL leave the indexes without any package file, and `all` SHALL leave neither. Files
that apk itself keeps in its cache directory beside indexes and package files are not package files and MAY remain with
`packages` and `none`.

The feature knowingly leaves one exception in place: when the image's own apk configuration disables apk's cache, which
only an apk generation that reads such configuration honors, apk stores nothing, so with `refreshPolicy=default` or
`always` the values `packages` and `none` keep nothing although the installation succeeds. The feature neither overrides
nor checks that setting, because options the image's apk configuration sets stay the image's decision (Repository
authentication stays in effect) and no argument that restores caching exists on every supported apk generation. This
requirement states no outcome for `refreshPolicy=never` under such a configuration; Package index refresh governs it.

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
constraint or without one, SHALL replace the first in apk's world. When its upgradePackages and its latest are both
false, the second installation SHALL NOT change an installed version unless a constraint or dependency requires it or
the image's own apk configuration sets a version policy, as Install the listed packages states; when upgradePackages is
true, it SHALL request the target upgrades described by Install the listed packages; when latest is true, it SHALL
select versions as Highest version is required on request states, also for a package the first installation left at an
older version, and SHALL NOT lower a version the first installation selected through a `name@tag` entry.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. A version policy or lock wait of the first invocation
SHALL NOT apply to the second: the second passes only what its own `latest` and `lockTimeout` select. Disabling optional
dependencies on a later invocation SHALL NOT uninstall previously installed packages, and a later `latest=false` SHALL
NOT by itself lower a version an earlier `latest=true` selected.

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
`true` or `false`; enum options SHALL accept only their declared values. A non-empty `networkTimeout` SHALL be a
canonical ASCII decimal integer string from `1` through `3600`, with no sign, whitespace, leading zero, or other
character, and a non-empty `lockTimeout` SHALL follow the same rule with the same bounds. The feature SHALL refuse every
`lockTimeout` value that apk itself would accept and read as no wait, as a different number, or as an unbounded wait,
such as `0`, text, a number followed by text, or a negative number. Invalid options SHALL fail with status 1 and a
message naming the option. With valid options and an empty package list, the feature SHALL succeed without refreshing,
upgrading, cleaning, or changing any configuration, also without the package manager.

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
