# Spec Delta

## MODIFIED Requirements

### Requirement: Install the listed packages

The feature SHALL install listed packages and dependencies only from image repositories. installSuggests and
installRecommends independently control whether APT considers each class; otherwise only listed packages and their needs
may upgrade. It SHALL never remove installed packages: if removal is required, fail before changing installed packages.
Enabling suggestions knowingly can grow the installed set by orders of magnitude; the developer chooses this and the
feature sets no limit.

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

### Requirement: Entries are validated before anything changes

The feature SHALL accept only a package name whose prefix before the first colon or equals starts lowercase or a digit
and contains lowercase letters, digits, dot, plus, hyphen; the rest permits letters, digits, dot, plus, hyphen, colon,
tilde, equals. Entries cannot end in hyphen. Invalid entries fail status 1 before checking apt-get, refreshing, or
installing; accepted values are single arguments, never shell code.

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

After index readiness and before install, the feature SHALL check each exact actual or virtual package name, excluding
its qualifier. It SHALL NOT accept regex, glob, task, or search-pattern matches. Virtual names need exactly one
provider; version pins match an available version exactly, and trailing plus is not an install marker.

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

### Requirement: Package index refresh

default SHALL refresh when no index exists and otherwise use the existing index regardless of age or coverage; always
refreshes every configured repository. Any attempted refresh fails before install if a repository cannot refresh or
verify. never uses existing indexes only and fails without fallback when unusable; it does not disable package downloads
or relax authentication.

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

### Requirement: Non-interactive installation

The feature SHALL take package configuration questions’ defaults without input. For changed dpkg-tracked conffiles, keep
retains the changed file and replace installs the packaged file, regardless of image APT/dpkg settings. It passes no
policy for files managed by maintainer scripts such as ucf or debconf; those remain package-defined under either policy.

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

After success, all SHALL explicitly remove package files and repository metadata from APT’s effective archive/index
paths; packages removes package files but retains usable metadata; none makes no explicit deletion. No mode removes
installed-package databases, signing keys, or unrelated paths. Native configuration/hooks may delete files
independently; none cannot guarantee retention and packages cannot create missing metadata.

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

A second installation SHALL treat its list as a first would and retain packages from both successful lists. It fails
without package changes if the second list requires removal. It may upgrade listed packages and dependencies, but uses
its own target release, suggestion, conffile, retry, and lock settings; earlier optional packages remain, and later runs
do not undo prior downgrades or conffile replacements.

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

### Requirement: Installation controls are validated before changes

Before package-manager calls or cache creation, the feature SHALL validate all booleans, enums, entries, timeouts,
retries, lock wait, and target release. Network/lock values are canonical decimals 1–3600; retries are 0–10, with only
literal zero allowed to start with zero. Invalid values fail status 1 naming the option; valid empty lists do no package
work.

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

### Requirement: Target release prefers a configured release

An empty targetRelease SHALL add no preference; a value is an install-call preference, not a filter, and pins still win.
APT compares the whole case-insensitive value with version fields only when it starts with a digit, otherwise
suite/codename fields. The feature SHALL knowingly leave the risk that shared names hold back Debian security updates or
raise Ubuntu backports, without warning.

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

A targetRelease SHALL select only a release in the index used; the feature adds no source, component, or key, passes no
target during refresh, and treats it as no pattern or key=value selector. If none matches, fail status 1 naming
targetRelease and value after refresh and exact entry validation but before install. This check is needed because APT
silently accepts other-kind release values and prefers nothing.

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

## ADDED Requirements

### Requirement: Optional package choices are independent

installSuggests SHALL control suggested packages and installRecommends SHALL control recommended packages independently.
With suggestions enabled, APT follows suggestions of every newly installed package; the feature knowingly places no
limit on resulting growth because the developer explicitly enables it.

#### Scenario: Suggestions are enabled independently

- **WHEN** installSuggests=true and installRecommends=false
- **THEN** APT considers suggestions but excludes recommendations

### Requirement: Target-release validation follows index and entry checks

The feature SHALL validate whether a target release exists only after refresh, exact package-name/version checks, and
before install. It cannot validate source availability earlier because it needs the index and a non-empty package list;
if an entry also fails, the entry failure ends the run first.

#### Scenario: Invalid target fails after index checks

- **WHEN** a non-empty package list names a well-formed target release absent from the refreshed index
- **THEN** the feature fails naming targetRelease before installation

### Requirement: Apt control values are rejected before native misinterpretation

The feature SHALL reject malformed retry and lock values because APT may interpret negative or oversized values as
unbounded and other malformed numbers as its own default. It SHALL reject mistyped release key=value selectors that APT
ignores and now, which names installed packages rather than a source.

#### Scenario: Native-invalid retry value is rejected

- **WHEN** downloadRetries is negative or malformed
- **THEN** validation fails before any APT command rather than allowing APT’s unbounded/default behavior

### Requirement: Target-release matching has no implicit pattern behavior

The target release SHALL be compared as a whole value and according to its first character: digit-leading values against
release versions, others against suite/codename fields, without case sensitivity. A shared field name selects every
matching suite; the accepted risk is that this can hold back security updates on Debian or raise backports on Ubuntu
without warning.

#### Scenario: Shared release field selects all matching suites

- **WHEN** several configured suites carry the requested release name in the compared field kind
- **THEN** APT prefers every matching suite

### Requirement: Target-release syntax is validated

A non-empty `targetRelease` SHALL be 1–64 ASCII characters, start with a letter or digit, contain only letters, digits,
`.`, `+`, `_`, `~`, or `-`, and not equal `now` in any letter case.

#### Scenario: Target-release syntax restrictions apply

- **WHEN** `targetRelease` is empty, a valid suite, codename or dotted version, or an invalid value with disallowed
  characters, an invalid first character, excess length, or the value `now` in any case
- **THEN** empty and valid names pass syntax validation, and each invalid value fails with status 1 naming
  `targetRelease`
