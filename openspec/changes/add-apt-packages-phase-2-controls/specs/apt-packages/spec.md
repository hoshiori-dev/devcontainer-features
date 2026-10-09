# Spec Delta

## ADDED Requirements

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
- **THEN** a configuration file that was changed in the image is kept when an upgrade ships a new version of it

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

An empty `targetRelease` SHALL pass no release preference. A non-empty value SHALL make APT prefer that release, as its
default release, on the install call only. It is a preference, not a filter: other releases stay usable, and a
`name=version` entry keeps its version. Accepted risk: it can hold back a security update published under another
release name and raises every suite sharing the name, backports included; the developer chooses that, and the feature
does not warn.

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

- **WHEN** `targetRelease` holds a codename or version that several configured suites carry, one of which the image
  ranks below the default priority
- **THEN** every such suite is preferred, so a listed package can be installed from the lower-ranked suite

### Requirement: Target release selects only among configured sources

A `targetRelease` SHALL select only among the releases present in the package index the feature uses. It SHALL add no
source, component, or key, SHALL NOT be passed to the index refresh, and SHALL NOT be matched as a pattern, a regular
expression, or a `key=value` selector. When the index holds no release of that name, APT's refusal SHALL end the feature
with a non-zero status before any package changes.

#### Scenario: Unknown release fails before any change

- **WHEN** `targetRelease` is a well-formed name that no release of the package index carries
- **THEN** the feature exits with a non-zero status, the output names the release, and no package is installed or
  changed

#### Scenario: Release the image does not configure is not added

- **WHEN** `targetRelease` names a suite that exists upstream but that no source of the image configures
- **THEN** the feature fails as for an unknown release and the image's sources are unchanged

#### Scenario: Refresh ignores the target release

- **WHEN** `targetRelease` is non-empty and the feature refreshes the package index
- **THEN** the refresh covers every configured repository exactly as it does without the option

### Requirement: Target release leaves holds and pins in force

A `targetRelease` SHALL NOT change a held package: an installation that would change one fails and leaves it as it was.
It SHALL NOT downgrade an installed package. A pin with a priority above 990 and a negative pin SHALL keep their effect.
A positive pin below 990 on a version outside the target release is outranked, because APT gives the target release
priority 990; a developer who relies on such a pin leaves `targetRelease` empty or raises the pin.

#### Scenario: Held package is not changed

- **WHEN** `targetRelease` names a release that offers a newer version of a listed package the image holds
- **THEN** the feature exits with a non-zero status and the held package keeps its version

#### Scenario: Installed newer version is not downgraded

- **WHEN** `targetRelease` names a release whose version of a listed package is older than the installed one
- **THEN** the feature succeeds and the installed version stays

#### Scenario: Higher-priority pin wins

- **WHEN** the image pins another release with a priority above 990 and `targetRelease` names a different release
- **THEN** the version the pin selects is installed

#### Scenario: Negative pin still excludes

- **WHEN** the image pins a listed package with a negative priority and `targetRelease` names a release that offers it
- **THEN** the feature exits with a non-zero status and the package is not installed

#### Scenario: Lower-priority pin on another version is outranked

- **WHEN** the image pins a version of a listed package outside the target release with a positive priority below 990
- **THEN** the version of the target release is installed

### Requirement: Configuration file policy covers dpkg conffiles

`conffilePolicy` SHALL apply only to files dpkg tracks as conffiles, when an installed package is upgraded. `keep`
leaves the image's file and writes the packaged one beside it as `.dpkg-dist`. `replace` installs the packaged file,
saves the image's file beside it as `.dpkg-old`, and installs again a conffile the image deleted. Accepted risk:
`replace` overwrites configuration the image changed on purpose, for listed packages and every upgraded dependency.

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

#### Scenario: Newly installed package is unaffected

- **WHEN** a listed package is not installed before the feature runs
- **THEN** its configuration files are installed as packaged with either policy

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
- **THEN** every refresh and install call receives that retry count, and a download that keeps failing is attempted once
  more than the value before the feature fails

#### Scenario: Retries are disabled

- **WHEN** `downloadRetries` is zero and a download fails
- **THEN** the download is attempted once and the feature exits with a non-zero status

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
- **THEN** the feature exits with a non-zero status after about that many seconds and no package is changed

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

- **WHEN** one of those options is non-empty and the image's APT configuration sets a different value for the same
  setting
- **THEN** the feature's calls use the option's value, the other image settings stay in effect, and the image's
  configuration files are the same as before the feature ran

#### Scenario: Proxy settings are inherited

- **WHEN** the build environment or the image's APT configuration provides a proxy
- **THEN** the feature passes no proxy setting of its own and APT applies the one provided

#### Scenario: Configuration selected by the environment is honored

- **WHEN** the environment the feature runs in names an additional APT configuration file
- **THEN** the feature's calls read it as APT does, and an explicit option still overrides the matching setting in it

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install, with `apt-get`, every package named in the comma-separated `packages` option, taking each
package and its dependencies only from the repositories configured in the image. Suggested packages SHALL be excluded
when `installSuggests=false` and considered by APT when `installSuggests=true`, independently of `installRecommends`.
Recommended packages SHALL be excluded when `installRecommends=false` and considered by APT when
`installRecommends=true`. Apart from that dependency selection, it SHALL NOT upgrade installed packages other than the
listed packages and what they need.

The feature SHALL NOT remove any installed package to satisfy a listed package or its dependencies. When the requested
installation requires removal, it SHALL fail before changing any installed package.

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

### Requirement: Non-interactive installation

The feature SHALL complete without reading any input: package configuration questions SHALL take their default answers,
and when an upgrade ships a new version of a configuration file that was changed in the image, the changed file SHALL be
kept with `conffilePolicy=keep` and replaced by the packaged file with `conffilePolicy=replace`. Either outcome SHALL be
reached without a question and SHALL NOT depend on the configuration-file handling that the image's APT or dpkg
configuration selects.

#### Scenario: Package that asks a question installs unattended

- **WHEN** `packages` names a package whose installation asks a configuration question
- **THEN** the feature completes without a terminal or input, and the package is configured with the default answer

#### Scenario: Changed configuration file is kept

- **WHEN** `conffilePolicy=keep` and a listed package is upgraded to a version that ships a new version of a
  configuration file changed in the image
- **THEN** the feature completes without input and the file keeps the image's content

#### Scenario: Changed configuration file is replaced

- **WHEN** `conffilePolicy=replace` and a listed package is upgraded to a version that ships a new version of a
  configuration file changed in the image
- **THEN** the feature completes without input and the file holds the packaged content

#### Scenario: Image setting does not defeat keeping

- **WHEN** `conffilePolicy=keep` and the image's APT or dpkg configuration selects the packaged version of changed
  configuration files
- **THEN** the changed file is kept

#### Scenario: Image setting does not defeat replacing

- **WHEN** `conffilePolicy=replace` and the image's APT or dpkg configuration selects the default action or the
  installed version for changed configuration files
- **THEN** the changed file is replaced by the packaged file

### Requirement: Installation controls are validated before changes

The feature SHALL validate `installRecommends`, `installSuggests`, `refreshPolicy`, `cleanup`, `conffilePolicy`,
`networkTimeout`, `downloadRetries`, `lockTimeout`, `targetRelease` and all package entries before invoking any
package-manager command or creating any cache. Boolean options SHALL accept only `true` or `false`; enum options SHALL
accept only their declared values. A non-empty `networkTimeout` SHALL be a canonical ASCII decimal integer string from
`1` through `3600`, with no sign, whitespace, leading zero, or other character. A non-empty `lockTimeout` SHALL follow
the same rule with the same range. A non-empty `downloadRetries` SHALL follow the same rule from `0` through `10`, where
the single digit `0` is the only accepted value that starts with a zero. A non-empty `targetRelease` SHALL be one name
of at most 64 characters that starts with an ASCII letter or digit and consists only of ASCII letters, digits, and the
characters `.`, `+`, `_`, `~`, and `-`. Invalid options SHALL fail with status 1 and a message naming the option. With
valid options and an empty package list, the feature SHALL succeed without refreshing, upgrading, cleaning, or changing
any configuration, also without the package manager.

The feature SHALL refuse these values itself because APT does not: APT reads a negative or oversized retry count and a
negative lock wait as unbounded, replaces any other malformed number with a value of its own, and ignores a release that
holds `=` without an error.

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
  `=`, `/`, `*`, `?`, `[`, a comma, whitespace, or shell text, that starts with `-`, or that is longer than 64
  characters
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

### Requirement: Installing the feature twice

Installing the feature a second time SHALL treat the second list as a first installation would. When successful, it
SHALL leave installed every package that either installation listed. If the second list requires removal of an installed
package, it SHALL fail without changing installed packages. The second installation MAY upgrade an installed package
that its list names without a version, or that a package of its list needs.

The second invocation SHALL use its own control values, with no permanent override of image configuration. Earlier cache
choices SHALL NOT override the later refresh or cleanup policy. Disabling optional dependencies on a later invocation
SHALL NOT uninstall previously installed packages.

An earlier invocation's target release, suggestion choice, configuration-file policy, retry count, and lock wait SHALL
NOT apply to a later one. A later invocation SHALL NOT undo what an earlier one did under its own values: it SHALL NOT
downgrade a package installed from another release, and SHALL NOT restore a configuration file that was replaced.

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
  `downloadRetries`, and `lockTimeout`, and the second sets none of them with a non-empty compatible package list
- **THEN** the second invocation gives APT no release preference, retry count, or lock wait, excludes suggestions, and
  keeps changed configuration files; the image's APT and dpkg configuration files are the same as before the first
  invocation

#### Scenario: Later invocation keeps what the earlier one installed

- **WHEN** the first invocation installed a package from a target release, together with suggested packages, and the
  second lists the same package with `targetRelease` empty and `installSuggests=false`
- **THEN** the second invocation succeeds, removes no package, and downgrades none
