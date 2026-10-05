# Spec Delta

## ADDED Requirements

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

### Requirement: Option upgradePackages

The feature SHALL accept the option `upgradePackages` as declared here.

| Field   | Value     |
| ------- | --------- |
| Type    | `boolean` |
| Default | `false`   |

#### Scenario: Omitted upgradePackages

- **WHEN** `upgradePackages` is omitted
- **THEN** the feature uses `false` as specified by the requirements below

### Requirement: Installation controls are validated before changes

The feature SHALL validate `refreshPolicy`, `cleanup`, `networkTimeout`, `upgradePackages` and all package entries
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

An empty `networkTimeout` SHALL leave native timeout settings unchanged. A non-empty value SHALL apply to apk's timeout
for a network connection making no progress on every refresh and install call made by the feature. It SHALL NOT set an
overall build deadline, change retry policy, disable certificate checks, or persist a setting in the image.

#### Scenario: Native timeout is inherited

- **WHEN** networkTimeout is omitted or empty
- **THEN** no timeout override is passed

#### Scenario: Explicit timeout reaches network operations

- **WHEN** networkTimeout is a valid non-empty value and installation needs network access
- **THEN** every feature refresh and install call receives the corresponding native timeout override, while retry and
  verification settings remain unchanged

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `apk`, every package named in the comma-separated `packages` option, taking each package
and its dependencies only from the repositories configured in the image, and SHALL leave each entry recorded in apk's
world (`/etc/apk/world`). Besides the listed packages and their dependencies, it SHALL install only the packages that
apk selects automatically because all of their install-if conditions are met. When `upgradePackages=false`, it SHALL NOT
change the version of an installed package unless an entry's constraint or a package it installs requires another
version. When `upgradePackages=true`, it SHALL request upgrades of the listed packages and their dependencies as
`apk add --upgrade` resolves them; it SHALL NOT request a whole-system upgrade.

#### Scenario: Listed packages are installed

- **WHEN** `packages` names two packages that the image's repositories offer and that are not installed
- **THEN** the feature exits with status 0, both packages, with their dependencies, are installed, and each entry is a
  line of apk's world

#### Scenario: Install-if packages follow their conditions

- **WHEN** `packages` names a package whose documentation subpackage the repositories offer, together with the `docs`
  meta package
- **THEN** the documentation subpackage is installed as well

#### Scenario: Listed package already installed stays at its version

- **WHEN** `upgradePackages=false` and `packages` names, without a constraint, a package that is installed at a version
  older than the one the repositories offer, and no other listed package requires a newer version of it
- **THEN** the feature succeeds and the package stays at its installed version

#### Scenario: Listed packages are upgraded on request

- **WHEN** upgradePackages=true and a listed installed package has a newer installable version
- **THEN** the listed package and dependencies selected by apk add are upgraded, existing world constraints remain
  effective, and no whole-system upgrade is requested

### Requirement: Package index refresh

With `refreshPolicy=default` or `always`, the feature SHALL fetch and verify the index of every configured repository
before installation, even if existing indexes are available, and SHALL fail before installing when any repository fails.
With `never`, it SHALL use existing cached indexes without checking remote indexes, SHALL fail before installing when a
configured repository has no usable cached index, and SHALL NOT fall back to fetching an index. Package files MAY still
be downloaded under never. Existing image caches SHALL be read without modifying them; retained feature indexes MAY be
reused. Authentication SHALL remain in effect.

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

### Requirement: Clean package caches

After a successful installation, `cleanup=all` SHALL remove indexes and package files fetched into feature-owned caches;
`packages` SHALL remove feature-owned package files while leaving usable feature indexes; `none` SHALL perform no
explicit feature cache deletion. All modes SHALL leave /var/cache/apk and any cache configured through /etc/apk/cache as
they were, except that existing caches MAY be read. The feature SHALL NOT delete an unrelated cache. Retained feature
caches SHALL be reusable on a later invocation, and every temporary work directory SHALL be removed even on failure.
Package-file retention by apk is independent from cleanup and is not guaranteed by none.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** no package index or package file fetched into a feature-owned cache remains in the image, and
  `/var/cache/apk` holds the same files as before it ran

#### Scenario: Only package files are cleaned

- **WHEN** cleanup=packages with usable metadata and package files present in the managed cache after installation
- **THEN** package files are removed from the managed cache and usable metadata remains

#### Scenario: Feature cleanup is disabled

- **WHEN** cleanup=none and the native package manager and image hooks retain downloads
- **THEN** the feature leaves cached package files and metadata in place

#### Scenario: Existing image caches are preserved

- **WHEN** any cleanup mode is selected and pre-existing image caches contain sentinel files
- **THEN** those files remain unchanged; cleanup affects feature-owned caches only

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that either installation listed, and SHALL
treat the second list as a first installation would. For a name that both lists hold, the second entry, with its
constraint or without one, SHALL replace the first in apk's world. When its upgradePackages is false, the second
installation SHALL NOT change an installed version unless a constraint or dependency requires it; when true, it SHALL
request the target upgrades described by Install the listed packages.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Later entry replaces the earlier constraint

- **WHEN** `upgradePackages=false` on the second invocation and the first installation's `packages` holds `name=version`
  and the second's holds `name` without a constraint
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
