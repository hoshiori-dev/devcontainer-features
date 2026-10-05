# Spec Delta

## ADDED Requirements

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

## MODIFIED Requirements

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
