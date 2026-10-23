# Spec Delta

## MODIFIED Requirements

### Requirement: Full system upgrade

With non-empty `packages`, the feature SHALL install the list and upgrade installed packages when configured
repositories offer newer versions, except packages held by image configuration and packages installed for this run's
listed entries. It SHALL NOT downgrade during the system upgrade or pass downgrade-enabling arguments. Arch supports
full upgrades only (https://wiki.archlinux.org/title/System_maintenance). See "Upgrade replacements" and "Listed entries
may select older versions".

#### Scenario: Outdated installed packages are upgraded

- **WHEN** the image has installed packages older than the versions the configured repositories offer and `packages`
  names at least one package
- **THEN** after the feature succeeds, no installed package that the image's pacman configuration does not hold back is
  older than the version the repositories offer, other than a package this installation installed for a listed entry
  whose repository qualifier or version constraint selected that version

### Requirement: Entries are validated before anything changes

Entries SHALL follow "Accepted target syntax" and "Accepted repository qualifier syntax". Rejected entries SHALL fail
with status 1 and a message naming the entry before checking for `pacman`, synchronizing databases, or installing.
Accepted entries SHALL reach `pacman` as single arguments without shell evaluation. Repository existence SHALL be left
to `pacman`. Slash errors follow "Slash validation diagnostics"; ambiguous relative paths follow "Relative paths
resembling qualified targets".

#### Scenario: URL or path is refused

- **WHEN** `packages` holds an entry containing `/` that is a URL or a path to a package file, such as one starting with
  `/` or `.`, one holding `://`, or one holding more than one `/`
- **THEN** the feature exits with status 1, names the entry, says that paths and URLs are not accepted, and installs
  nothing

#### Scenario: Option-like entry is refused

- **WHEN** `packages` holds an entry starting with `-`
- **THEN** the feature exits with status 1, names the entry, and installs nothing

#### Scenario: Shell metacharacters and inner whitespace are refused

- **WHEN** the `packages` value the feature receives holds an entry with whitespace inside it or with a character
  outside the accepted set, such as `;`, `$`, `` ` ``, `*`, `?`, `|`, or a non-ASCII letter
- **THEN** the feature exits with status 1, names the entry, installs nothing, and runs no command contained in the
  entry

#### Scenario: Repository-qualified entry is accepted

- **WHEN** `packages` holds an entry made of a repository name, one `/`, and a target, with or without a version
  constraint, each part within its accepted characters
- **THEN** the entry passes validation and reaches `pacman` unchanged as one argument

#### Scenario: Malformed repository qualifier is refused

- **WHEN** `packages` holds an entry with exactly one `/` that is no path or URL and whose repository part holds a
  character outside its accepted set or starts with one, or whose target part is empty or is not an accepted target
- **THEN** the feature exits with status 1, names the entry, names the `repository/target` form, and installs nothing

### Requirement: Entries select packages as pacman matches them

The feature SHALL resolve a sync target without its version constraint as an exact package name, otherwise a provided
name, otherwise a group, without regex or glob matching. For multiple providers it SHALL select the first `pacman`
offers; groups SHALL install all members. Unqualified entries SHALL use installation-enabled repositories in configured
order (`Usage`, pacman.conf(5)). Qualified entries follow "Qualified target resolution" and "Qualified targets are not
pins".

#### Scenario: Unknown package fails

- **WHEN** `packages` names a package that the image's repositories do not offer, alongside packages they do offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Entry is not matched as a regular expression

- **WHEN** `packages` holds an entry containing `.` that names no package, provided name, or group, although read as a
  regular expression it would match the names of packages the repositories offer
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Name with several providers installs the first

- **WHEN** `packages` names a name that no package has but several packages provide
- **THEN** the feature succeeds and installs the provider `pacman` offers first, and no other provider

#### Scenario: Group name installs the whole group

- **WHEN** `packages` names a package group
- **THEN** the feature succeeds and every package of the group is installed

#### Scenario: Qualified entry resolves in the named repository

- **WHEN** `packages` holds repository-qualified entries naming a package, a provided name, a group, and a package with
  a version constraint the offered version satisfies, each offered by the named repository and none of them installed
- **THEN** the feature succeeds and each named package, provider, or group member is installed from the named repository
  at the version it offers, also when a repository earlier in the configured order offers a newer version of the same
  name; their dependencies are resolved as for any other entry

#### Scenario: Qualified entry outside the named repository fails

- **WHEN** `packages` holds a repository-qualified entry whose target another configured repository offers and the named
  repository does not, alongside entries that can be installed
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Unknown repository fails

- **WHEN** `packages` holds a repository-qualified entry whose repository name the image's configuration does not
  define, alongside entries that can be installed
- **THEN** the feature exits with a non-zero status, `pacman`'s message names the repository, and none of the listed
  packages is installed

#### Scenario: Repository name is matched exactly

- **WHEN** `packages` holds a repository-qualified entry whose repository name differs from a configured repository only
  in the case of its letters
- **THEN** the feature exits with a non-zero status as for an unknown repository and installs none of the listed
  packages

#### Scenario: Qualified entry is not a pin

- **WHEN** `packages` holds a repository-qualified entry for a package already installed at the version the named
  repository offers, and a repository earlier in the configured order offers a newer version of it
- **THEN** the feature's full system upgrade selects the newer version from the earlier repository

#### Scenario: Qualified entry reaches a repository not enabled for installation

- **WHEN** `packages` holds a repository-qualified entry whose repository the image configures with a `Usage` that holds
  `Sync` and leaves out `Install`, and whose target needs no dependency that only this repository offers
- **THEN** the feature succeeds and the package is installed from that repository, under that repository's signature
  level

#### Scenario: Dependency only in a repository not enabled for installation fails

- **WHEN** `packages` holds a repository-qualified entry whose repository is not enabled for installation and whose
  target depends on a package that only this repository offers and no entry names with the repository
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Unqualified entry does not reach a repository not enabled for installation

- **WHEN** `packages` holds an unqualified entry for a package that only a repository not enabled for installation
  offers, alongside a qualified entry naming that repository
- **THEN** the feature exits with a non-zero status and installs none of the listed packages

#### Scenario: Qualified entry offering an older version

- **WHEN** `packages` holds a repository-qualified entry whose named repository offers the target only at a version
  older than the installed one
- **THEN** the feature succeeds, the installed version is the older one the named repository offers, and the feature
  passed no argument that forces or prevents the replacement

### Requirement: Package index refresh

The feature SHALL synchronize every configured repository's package database before installing and fail if any
synchronization fails. Unsigned databases follow "Unsigned database trust"; package signatures remain governed by
"Repository authentication stays in effect".

#### Scenario: Missing database is downloaded

- **WHEN** the image holds no package database
- **THEN** the feature downloads the database of every configured repository before installing

#### Scenario: Failed refresh fails the feature

- **WHEN** synchronizing the database of any configured repository fails
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

### Requirement: Repository authentication stays in effect

The feature SHALL preserve image `SigLevel` (https://man.archlinux.org/man/pacman.conf.5). It SHALL NOT lower signature
requirements, trust keys outside the image keyring's trust except as "Packager key import" allows, skip dependency or
file-conflict checks, or pass downgrade-enabling arguments. Qualified packages SHALL use the named repository's
signature level. See "Image repository configuration is preserved" and "Temporary configuration preserves trust".

#### Scenario: Untrusted signature fails the install

- **WHEN** a package to install or upgrade is signed by a key that the image's keyring does not trust
- **THEN** the feature exits with a non-zero status and installs and upgrades none of the packages

#### Scenario: Pacman configuration is unchanged

- **WHEN** the feature has installed and upgraded packages none of which ships or changes a file under `/etc/pacman.d`
  or `/etc/pacman.conf`, and every one of them is signed by an unexpired key already in the image's keyring
- **THEN** `/etc/pacman.conf` and the files under `/etc/pacman.d`, including the mirror list and the keyring, are the
  same as before it ran

#### Scenario: Explicit parallel downloads keep the image configuration

- **WHEN** the feature runs with a non-empty `parallelDownloads` and a non-empty list
- **THEN** the configuration `pacman` resolves for the feature's call equals the one it resolves from the image's
  configuration in everything but `ParallelDownloads`, a package signed by a key the image's keyring does not trust
  still fails the installation, and `/etc/pacman.conf` and the files under `/etc/pacman.d` are the same as before the
  feature ran, under the conditions of the scenario "Pacman configuration is unchanged"

### Requirement: Packager key import

For a missing or expired signing key of a package being installed or upgraded, the feature MAY let `pacman` import it
into `/etc/pacman.d/gnupg`, even if installation later fails. A fetched key SHALL gain no trust: its packages install
only if keys already trusted by the image certify it. Lookup follows "Packager key lookup identity", "Packager Web Key
Directory lookup", and "Packager keyserver fallback".

#### Scenario: Missing certified key is fetched

- **WHEN** a package to install is signed by a packager key that the image's keyring lacks and that the keys it trusts
  certify
- **THEN** the feature succeeds, the package is installed, and the key is in the image's keyring

### Requirement: Clean package caches

After successful installation, `cleanup=all` SHALL delete package files, detached signatures, and sync databases from
`/var/cache/pacman/pkg` and `/var/lib/pacman/sync`; `packages` SHALL delete only package and signature files from the
former; `none` SHALL perform no explicit feature cache deletion. Installed-package databases and unrelated paths SHALL
remain. See "Custom cache paths remain unmanaged" for custom paths and independent hooks.

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

A second installation SHALL process its list as a first would, including a full system upgrade for every non-empty
invocation. It SHALL retain packages installed for earlier entries except packages the upgrade replaces, and MAY upgrade
them. Each run SHALL use its own controls, with no permanent image override; earlier cleanup choices SHALL NOT override
later ones. See "Download controls do not persist" and "Repeated target selection can alternate versions".

#### Scenario: Same list on the second install

- **WHEN** the feature is installed twice with the same `packages`
- **THEN** both installations succeed and every listed package is installed

#### Scenario: Different list on the second install

- **WHEN** the feature is installed a second time with `packages` naming different packages than the first time, and the
  configured repositories replace none of the packages the first installation installed
- **THEN** the second installation succeeds and the packages of both lists are installed

#### Scenario: Constraint below the installed version on the second install

- **WHEN** the second installation's `packages` holds `name<version` or `name=version` with a version older than the one
  installed, and no configured repository offers a version that satisfies it
- **THEN** the second installation exits with a non-zero status and the installed version stays as it was

#### Scenario: Later controls apply to the second installation

- **WHEN** the first invocation preserves metadata and the second uses different cleanup values with a non-empty
  compatible package list
- **THEN** the second invocation follows its own values, retains the packages guaranteed by this requirement, and does
  not persist control settings

#### Scenario: Download controls do not persist to the second install

- **WHEN** the first installation sets `parallelDownloads` and holds a repository-qualified entry, and the second, with
  a non-empty list, sets no `parallelDownloads` or another value
- **THEN** the second installation's `pacman` call uses the image's setting or its own value, no temporary configuration
  of the first exists, and the package the first installed for the qualified entry is still installed

#### Scenario: Same qualified entry with a newer version in an earlier repository

- **WHEN** the feature is installed three times with the same repository-qualified entry, the package is not installed
  before the first, and a repository earlier in the configured order offers a newer version of that package name
- **THEN** all three installations succeed; after the first the installed version is the named repository's, after the
  second the newer one, and after the third the named repository's again

### Requirement: Installation controls are validated before changes

The feature SHALL validate `cleanup`, `parallelDownloads`, and package entries before any package-manager command or
cache or temporary-file creation. `cleanup` SHALL accept only its declared values; `parallelDownloads` SHALL follow
"Accepted parallel download values". Invalid options SHALL fail with status 1 naming the option. Valid options with an
empty list SHALL succeed without the package manager, refresh, upgrade, cleanup, or configuration changes.

#### Scenario: Invalid control fails before any change

- **WHEN** a control value is invalid, also when packages is empty
- **THEN** the feature exits with status 1, names the option, and changes nothing

#### Scenario: Empty list ignores installation controls

- **WHEN** packages is empty and valid non-default controls are provided
- **THEN** the feature succeeds without invoking the package manager or touching any cache

#### Scenario: Parallel download boundaries are validated

- **WHEN** parallelDownloads is empty, 1, or 20, or an invalid value such as 0, 21, 01, +3, a value with whitespace
  around it, 1.5, shell text, or digits followed by a line break and a configuration setting
- **THEN** empty and the two boundaries are accepted; every invalid value fails with status 1 naming the option before a
  package-manager command runs and before a temporary file is created

### Requirement: Parallel downloads are bounded

Empty `parallelDownloads` SHALL add no argument, environment variable, or file to the `pacman` call: image
configuration, or `pacman`'s default, applies. A non-empty value SHALL bound simultaneous downloads through
`ParallelDownloads` for the one call, overriding only that setting. See "Temporary download configuration", "Download
configuration lifecycle", "Effective parallel download value is confirmed", and "Parallel download accepted risks".

#### Scenario: Native parallel downloads are inherited

- **WHEN** `parallelDownloads` is omitted or empty and `packages` names at least one package
- **THEN** the feature's `pacman` call names no configuration file, the feature creates no file of its own, and the
  number of simultaneous downloads is the one the image's pacman configuration gives

#### Scenario: Explicit parallel downloads reach pacman

- **WHEN** `parallelDownloads` holds an accepted value different from the image's and `packages` names at least one
  package
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads`, and the
  listed packages are installed

#### Scenario: Temporary configuration is removed

- **WHEN** the feature has run with a non-empty `parallelDownloads` and a non-empty list, and the installation either
  succeeded or failed in `pacman`
- **THEN** the temporary configuration file and any directory the feature created for it no longer exist

#### Scenario: Image configuration that cannot be included fails closed

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `/etc/pacman.conf` is missing or
  unreadable
- **THEN** the feature exits with status 1, names `parallelDownloads`, synchronizes no database, installs and upgrades
  nothing, and leaves no temporary file behind

#### Scenario: Unconfirmed value fails closed

- **WHEN** `parallelDownloads` is non-empty, `packages` names at least one package, and `pacman-conf` is missing, fails,
  or reports for the temporary configuration a `ParallelDownloads` value other than the requested one
- **THEN** the feature exits with status 1, names `parallelDownloads`, synchronizes no database, installs and upgrades
  nothing, and leaves no temporary file behind

#### Scenario: Image configuration ending in a repository section

- **WHEN** `parallelDownloads` holds an accepted value, `packages` names at least one package, and the last section of
  the image's `/etc/pacman.conf` is a repository section
- **THEN** the configuration `pacman` resolves for the feature's call has that value as `ParallelDownloads` and the
  repositories of the image, and the listed packages are installed

#### Scenario: Parallel downloads apply under every cleanup value

- **WHEN** `parallelDownloads` is non-empty and `cleanup` is `all`, `packages`, or `none`
- **THEN** the installation uses the requested value, the caches are treated as the requirement "Clean package caches"
  says for that `cleanup` value, and the temporary configuration file is removed under each of them

#### Scenario: Parallel downloads apply to repository-qualified entries

- **WHEN** `parallelDownloads` is non-empty and `packages` holds a repository-qualified entry beside an unqualified one
- **THEN** both are installed in the one `pacman` call, each from the repository the requirement "Entries select
  packages as pacman matches them" gives it

### Requirement: Unsupported download controls stay native

The feature SHALL expose no retry, lock-wait, timeout, or proxy option: `pacman` lacks bounded native controls for one
call. It SHALL document this and inherit image and native behavior. It SHALL NOT change `pacman`'s environment, retries,
locks, timeouts, or downloader; retry failed calls; or wait for or remove an existing database lock.

#### Scenario: Held database lock fails the installation

- **WHEN** `packages` names at least one package and the lock file of the image's package database already exists
- **THEN** the feature exits with a non-zero status after its one `pacman` call, installs and upgrades nothing, and the
  lock file is still there

#### Scenario: Build environment proxy reaches pacman unchanged

- **WHEN** the environment the feature runs in sets proxy variables
- **THEN** the environment `pacman` receives holds those variables with the same values, and the feature has neither
  added, changed, nor removed a proxy setting

## ADDED Requirements

### Requirement: Upgrade replacements

The system upgrade SHALL replace an installed package when a configured repository package declares it in `replaces`
(https://man.archlinux.org/man/PKGBUILD.5), removing the replaced package.

#### Scenario: Declared replacement during upgrade

- **WHEN** a non-empty installation upgrades an installed package through a configured repository's replacement
  declaration
- **THEN** the replacement is installed and the replaced package is removed.

### Requirement: Listed entries may select older versions

Packages installed for listed entries SHALL use their selected versions outside that transaction's upgrade. A qualifier
or constraint selecting only an older offered version SHALL replace a newer installed one. Accepted risk: this needs
repositories offering different versions of the same package; no downgrade option or guard is added because entries are
developer configuration and a guard would require a second resolver alongside `pacman`.

#### Scenario: Constraint selects an older offered version

- **WHEN** an entry's constraint is satisfied only by an offered version older than the installed one
- **THEN** the older version is installed without an argument forcing or preventing its replacement.

#### Scenario: Repositories offer one version per package

- **WHEN** the configured repositories offer only one version of each package name, as on the images listed in
  `test/pacman-packages/compatibility.json`
- **THEN** the older-version selection requiring multiple offered versions cannot occur

### Requirement: Accepted target syntax

A target SHALL start with an ASCII letter or digit and contain only ASCII letters, digits, `@`, `.`, `_`, `+`, `-`, `:`,
`<`, `>`, and `=`. An unqualified entry SHALL be a target; a qualified entry SHALL have the form defined by "Accepted
repository qualifier syntax".

#### Scenario: Invalid target character

- **WHEN** a target contains whitespace, a non-ASCII letter, or a character outside the accepted set
- **THEN** validation rejects the entry before any package-manager command.

### Requirement: Accepted repository qualifier syntax

A qualified entry SHALL consist of a repository name, exactly one `/`, and an accepted target. The repository name SHALL
start with an ASCII letter or digit and contain only ASCII letters, digits, `.`, `_`, `+`, and `-`. All other entries
containing `/` SHALL be refused as described by "Slash validation diagnostics".

#### Scenario: Empty qualified target

- **WHEN** an entry names a repository followed by `/` and no target
- **THEN** validation rejects it as a malformed repository qualifier.

### Requirement: Slash validation diagnostics

A refused entry starting with `/` or `.`, containing `://`, or containing multiple `/` characters SHALL be reported as a
path or URL, which the feature never installs from. Any other refused slash-containing entry SHALL be reported as a
malformed repository qualifier with the accepted form named.

#### Scenario: Malformed qualifier diagnostic

- **WHEN** a slash-containing entry is invalid but has no path or URL marker
- **THEN** the message names the entry and the accepted `repository/target` form.

### Requirement: Relative paths resembling qualified targets

A relative path with one `/` and no leading `.` that matches qualified-target syntax SHALL reach `pacman` as a sync
target, never as a file or URL. Accepted risk: syntax cannot distinguish it from a qualifier; it fails as an unknown
repository unless the image configures that repository name.

#### Scenario: Relative path shaped as a qualifier

- **WHEN** an entry resembles `directory/package` and `directory` is not configured as a repository
- **THEN** `pacman` rejects the unknown repository and does not read a package file.

### Requirement: Qualified target resolution

A qualified entry SHALL reach `pacman` unchanged and resolve its package, provided name, or group and version constraint
only within the named configured repository. The feature SHALL NOT look up, enable, add, or reorder repositories itself.
Signatures follow "Repository authentication stays in effect"; repositories excluded from normal installation follow
"Explicit repository reach".

#### Scenario: Target absent from the named repository

- **WHEN** a qualified target is offered only by another repository
- **THEN** installation fails without installing any listed package.

### Requirement: Unknown repositories fail after synchronization

Repository names SHALL match configured names exactly, including case. For unknown names the feature SHALL preserve
`pacman`'s failure behavior: non-zero status and a message naming the repository, after database synchronization and
before any package installation or upgrade.

#### Scenario: Case mismatch in repository name

- **WHEN** a qualifier differs from a configured repository name only in letter case
- **THEN** synchronization precedes failure; the message names the unknown repository and nothing is installed or
  upgraded.

### Requirement: Qualified targets are not pins

A newly installed qualified target SHALL use the named repository's version outside that transaction's upgrade, even if
another offers newer. A satisfied entry SHALL be skipped; the upgrade then follows repository order and upgrades it if
an earlier repository offers newer. No guard SHALL be added. Older versions follow "Listed entries may select older
versions"; repeats follow "Repeated target selection can alternate versions".

#### Scenario: Satisfied qualified entry can be upgraded

- **WHEN** a qualified entry is satisfied and an earlier repository offers a newer version
- **THEN** the system upgrade selects the newer version from the earlier repository.

### Requirement: Explicit repository reach

A qualified target SHALL reach a configured repository with `Usage` containing `Sync` but neither `Install` nor `All`
(pacman.conf(5)). Accepted risk: the qualifier visibly selects an image-configured, signature-checked source; refusing
it needs a second resolver. This exception SHALL apply only to that target. Dependencies and unqualified entries SHALL
use installation-enabled repositories; a dependency offered only by the excluded repository SHALL fail.

#### Scenario: Dependency outside installation-enabled repositories

- **WHEN** a qualified target depends on a package offered only by its repository, which is excluded from normal
  installation
- **THEN** the installation fails and installs none of the listed packages.

### Requirement: Unsigned database trust

When image `SigLevel` permits unsigned databases (`DatabaseOptional`), authentication of database content, including
listed versions and checksums, SHALL rely on TLS alone to the mirror in the image's mirror list. Arch Linux repositories
publish unsigned databases and use this policy. Package signatures SHALL still be verified under "Repository
authentication stays in effect".

#### Scenario: Unsigned database under DatabaseOptional

- **WHEN** a configured mirror serves an unsigned database permitted by image policy
- **THEN** database authentication relies on TLS to that mirror and package signature checks remain enabled.

### Requirement: Image repository configuration is preserved

The feature SHALL NOT add, remove, or change image repositories, mirrors, signing keys, or pacman configuration, except
keys allowed by "Packager key import". Files shipped or changed by installed or upgraded packages are excluded.
Temporary configuration SHALL remain outside `/etc/pacman.conf` and `/etc/pacman.d` and follow "Temporary configuration
preserves trust".

#### Scenario: No package changes configuration

- **WHEN** installed and upgraded packages change no pacman configuration and need no missing or expired packager key
- **THEN** image repository configuration, mirrors, and keyring remain unchanged.

### Requirement: Temporary configuration preserves trust

Temporary configuration SHALL preserve the image's complete resolved configuration except `ParallelDownloads`:
repositories, order, servers, every `SigLevel`, keyring, download user, and sandbox settings SHALL remain unchanged. The
file SHALL exist only while the feature runs and outside the image's pacman configuration paths.

#### Scenario: Untrusted package with explicit downloads

- **WHEN** a non-empty `parallelDownloads` is used for a package signed by an untrusted key
- **THEN** the install fails under the image's signature policy; the override grants no trust.

### Requirement: Packager key lookup identity

Packager key lookup SHALL use the package's packager email for a missing key, or the first user ID's email in the image
keyring for an expired key. That email's domain and local part SHALL determine the lookup described in "Packager Web Key
Directory lookup".

#### Scenario: Expired packager key

- **WHEN** the image holds an expired signing key
- **THEN** lookup uses the email of that key's first user ID.

### Requirement: Packager Web Key Directory lookup

Packager key lookup SHALL first use
`https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local part>`. If that host does not exist, it
SHALL use `https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local part>`. The domain and local part come from
"Packager key lookup identity"; `<hash>` SHALL be the Web Key Directory hash of the local part.

#### Scenario: Advanced Web Key Directory host absent

- **WHEN** the `openpgpkey` host for the lookup email's domain does not exist
- **THEN** lookup uses the direct Web Key Directory URL with the local part and its Web Key Directory hash.

### Requirement: Packager keyserver fallback

If Web Key Directory lookup obtains no key, packager key lookup SHALL query the image's GnuPG default keyserver by
fingerprint, then its last eight hexadecimal digits. The server is `https://keyserver.ubuntu.com/pks/lookup` from GnuPG
2.2.29 up to, but excluding, 2.5.3; GnuPG 2.5.3 has no default keyserver. Fetched keys SHALL remain subject to "Packager
key import" trust restrictions.

#### Scenario: Web Key Directory lookup needs fallback

- **WHEN** Web Key Directory lookup does not obtain the key and GnuPG has a default keyserver
- **THEN** lookup queries it first by fingerprint and then by the fingerprint's last eight hexadecimal digits.

### Requirement: Custom cache paths remain unmanaged

Feature cleanup SHALL NOT delete custom `CacheDir` or `DBPath` locations and SHALL document that limitation.
Package-manager or image hooks MAY independently delete downloaded files even when feature cleanup is disabled.

#### Scenario: Custom database path

- **WHEN** the image configures a non-default `DBPath`
- **THEN** feature cleanup leaves that location alone.

### Requirement: Download controls do not persist

A `parallelDownloads` value SHALL apply only to the invocation that sets it. A later invocation with an empty value
SHALL use image configuration and find no temporary configuration from earlier runs. A later non-empty value SHALL
replace the earlier invocation's value only for its own call.

#### Scenario: Later invocation omits downloads override

- **WHEN** an installation sets `parallelDownloads` and a later non-empty installation leaves it empty
- **THEN** the later call uses the image setting and no configuration from the earlier invocation remains.

### Requirement: Repeated target selection can alternate versions

Qualified packages SHALL be retained and upgraded like others when later lists omit them. Repeating a satisfied
qualified entry SHALL leave it unchanged unless an earlier repository offers newer; then runs SHALL alternate between
that upgrade and the named older version, all succeeding. The same applies to constraints only the older version
satisfies. Accepted risk: the feature retains no state and each run is one native transaction; selection is not a
persistent pin.

#### Scenario: Three installations alternate selected versions

- **WHEN** the same qualified entry is installed three times from an initially absent state and an earlier repository
  offers newer
- **THEN** all succeed, selecting the named version, the earlier repository's newer version, and the named version in
  turn.

### Requirement: Accepted parallel download values

A non-empty `parallelDownloads` SHALL be an ASCII decimal integer from `1` to `20`, without a sign, whitespace, leading
zeros, or other characters. Only validated values SHALL be written to temporary configuration, preventing injected lines
or settings.

#### Scenario: Newline in parallel download value

- **WHEN** `parallelDownloads` contains digits followed by a newline and configuration text
- **THEN** validation fails with status 1 naming the option before any package-manager command or temporary-file
  creation.

### Requirement: Temporary download configuration

With non-empty `parallelDownloads` and `packages`, the feature SHALL pass `pacman` a temporary file outside `/etc`,
containing only an inclusion of `/etc/pacman.conf` and a `ParallelDownloads` setting. The setting SHALL be read in the
options section after all included content regardless of the image's final section. The image's default configuration
path on Arch Linux is `/etc/pacman.conf`.

#### Scenario: Included configuration ends in a repository

- **WHEN** the image configuration ends in a repository section and a valid override is set
- **THEN** the resolved override is an option and the image repositories remain available.

### Requirement: Download configuration lifecycle

The feature SHALL create no temporary configuration for an empty `parallelDownloads` or empty package list. When a
temporary configuration is used, it SHALL remove the file and any directory it created for it on exit, whether
installation succeeds or fails.

#### Scenario: Failed installation cleans temporary files

- **WHEN** `pacman` fails during an installation using explicit parallel downloads
- **THEN** the temporary file and any directory created for it are removed.

### Requirement: Effective parallel download value is confirmed

Before synchronization, the feature SHALL use `pacman-conf` (https://man.archlinux.org/man/pacman-conf.8) to confirm the
temporary configuration resolves to the requested `ParallelDownloads`. A different or absent value, tool failure or
unavailability, or missing or unreadable `/etc/pacman.conf` SHALL make the feature exit with status 1 naming
`parallelDownloads`, without synchronization, install, or upgrade. It SHALL NOT fall back to image values or run without
image repositories.

#### Scenario: Resolved value differs

- **WHEN** `pacman-conf` reports a different value for the temporary configuration
- **THEN** the feature exits with status 1 naming `parallelDownloads` and synchronizes, installs, and upgrades nothing.

### Requirement: Parallel download accepted risks

The feature SHALL NOT edit `/var/log/pacman.log`; `pacman` logs the removed temporary file's path there. Non-empty
`parallelDownloads` SHALL be unsupported when the default configuration path differs from `/etc/pacman.conf`. Accepted
risk: `pacman` does not retry mirror connection-limit failures, so higher concurrency can fail where lower succeeds; the
small accepted range bounds this risk.

#### Scenario: Temporary path remains in log

- **WHEN** an installation uses a temporary configuration and `pacman` logs its command line
- **THEN** the log keeps that path after the temporary file is removed.
