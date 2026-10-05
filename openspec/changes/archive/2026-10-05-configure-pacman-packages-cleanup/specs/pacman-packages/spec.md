# Spec Delta

## ADDED Requirements

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

The feature SHALL validate `cleanup` and all package entries before invoking any package-manager command or creating any
cache. The cleanup option SHALL accept only its declared values. Invalid options SHALL fail with status 1 and a message
naming the option. With valid options and an empty package list, the feature SHALL succeed without refreshing,
upgrading, cleaning, or changing any configuration, also without the package manager.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

## MODIFIED Requirements

### Requirement: Clean package caches

After a successful installation, `cleanup=all` SHALL remove downloaded packages, their detached signatures, and sync
database files from the default directories /var/cache/pacman/pkg and /var/lib/pacman/sync. `packages` SHALL remove
package and signature files from the default package directory but keep sync databases; `none` SHALL perform no explicit
feature cache deletion. Cleanup SHALL NOT remove the installed-package database or unrelated paths. Custom CacheDir or
DBPath locations SHALL NOT be deleted by this feature; that limitation SHALL be documented. Package-manager or image
hooks MAY independently delete downloaded files.

#### Scenario: Caches are removed

- **WHEN** `cleanup=all` and the feature has installed packages
- **THEN** the default package and sync directories hold no downloaded package, signature, or sync database files

#### Scenario: Only package files are cleaned

- **WHEN** cleanup=packages with usable metadata and package files present in the managed cache after installation
- **THEN** package files are removed from the managed cache and usable metadata remains

#### Scenario: Feature cleanup is disabled

- **WHEN** cleanup=none and the native package manager and image hooks retain downloads
- **THEN** the feature leaves cached package files and metadata in place

#### Scenario: Custom cache paths are outside the cleanup bound

- **WHEN** pacman.conf directs CacheDir or DBPath to a non-default location
- **THEN** feature cleanup affects only the documented default directories and leaves files in the configured
  non-default locations alone

### Requirement: Installing the feature twice

Installing the feature a second time SHALL leave installed every package that the first installation installed for its
entries, except a package the second installation's upgrade replaces (requirement "Full system upgrade"), and SHALL
treat the second list as a first installation would, including the full system upgrade, so the second installation MAY
upgrade packages that the first installed.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later cleanup policy. Every non-empty invocation SHALL still perform the full system
upgrade.

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time, and the
  configured repositories replace none of the packages the first installation installed
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Constraint below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name<version` or `name=version` with a version older than the one
  installed
- **THEN** the second installation exits with a non-zero status and the installed version stays as it was

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different cleanup values with a non-empty
  compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings
