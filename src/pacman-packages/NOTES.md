## Usage

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/pacman-packages:1": {
      "packages": "bc, tree, rsync>=3.2, extra/jq",
      "parallelDownloads": "3"
    }
  }
}
```

The feature installs the listed packages with `pacman` from the repositories the image already configures. It adds no
repository, mirror, or key, and changes no pacman configuration file of the image; the one setting it can override for
its own `pacman` call is described under [Download controls](#download-controls). It leaves out packages that a listed
package only names as optional dependencies; list them explicitly when you need them.

## Entries

`packages` is a comma-separated list; whitespace around an entry and empty entries are ignored, so an empty list, or one
of only commas, installs nothing and succeeds on any image. `pacman` resolves each entry as it resolves any target:

- the exact name of a package (`python-pip`, `libsigc++`, `gtk4`);
- otherwise a name that packages provide (`cron`): when several packages provide it, the first one `pacman` offers is
  installed, so name the package itself when you need a specific provider;
- otherwise a package group (`xorg-fonts`): every package of the group is installed.

An entry may end in a version constraint: `name=version`, `name<version`, `name<=version`, `name>version`, or
`name>=version`. A constraint only selects among the versions the configured repositories offer, and the installation
fails when none of them satisfies it. Arch Linux's own repositories offer one version of a package, so there a
constraint cannot install an older one.

The feature refuses, before it changes anything, paths and URLs (an entry holding `/` that starts with `/` or `.`, holds
`://`, or holds a second `/`), a malformed repository qualifier, an entry starting with `-` or `.`, whitespace inside an
entry, and any character outside ASCII letters, digits, and `@ . _ + - : < > =`, such as a shell metacharacter or a
glob. An entry is never matched as a regular expression or a glob: a name that is no package, provided name, or group
fails, and so does a package that conflicts with an installed one.

### Repository-qualified entries

An entry may name one of the image's configured repositories in `pacman`'s own form, `repository/target` (`extra/jq`,
`extra/rsync>=3.2`). `pacman` then resolves that target (a package, a provided name, or a group, with or without a
constraint) only in that repository. The repository name starts with an ASCII letter or digit and uses only ASCII
letters, digits, and `. _ + -`; it is compared exactly, with case. `pacman` documents no character set for repository
names, so whether an image can configure a name outside this set was not verified; such a repository could not be named
in an entry. A name the image does not configure fails in `pacman` with "database not found", after the databases were
synchronized and before anything is installed. The feature never adds or enables a repository.

A relative path with a single `/` and no leading `.` (`dir/file.pkg.tar.zst`) has the same shape and is not refused by
the feature. `pacman` never reads such a target as a file; it fails there as an unknown repository.

A qualifier has `pacman`'s native properties, and the feature adds no check of its own:

- It is not a pin. The version the named repository offers is installed, also when a repository earlier in the
  configured order offers a newer one. A later installation that finds the entry satisfied skips it, and its system
  upgrade then moves the package to the newer version.
- It reaches a repository that the image synchronizes but does not enable for installation (a `Usage` setting without
  `Install` or `All`), for the named target only. The target's dependencies and every unqualified entry are still
  resolved only in the repositories enabled for installation.
- It can select a version older than the installed one: when the named repository offers the target only at an older
  version, `pacman` replaces the installed package with it. An unqualified entry whose constraint only an older offered
  version satisfies behaves the same way.

None of the three can happen while every configured repository offers one version of a package name and sets no `Usage`,
as on the official Arch Linux image.

## Full system upgrade

Arch Linux supports only full system upgrades, so a non-empty list also upgrades the whole system: the feature runs one
`pacman -Syu`, which upgrades every installed package the repositories offer in a newer version, replaces an installed
package with the one the repositories declare as its replacement, and installs the list. The system upgrade downgrades
nothing, and the feature passes no argument that allows a downgrade. A package installed for a listed entry is the one
exception: it gets the version the entry selects, which can be older than the installed one when a repository qualifier
or a version constraint leaves only an older version (see
[Repository-qualified entries](#repository-qualified-entries)). A configuration file you changed is kept when its
package is upgraded; a differing new version is written beside it as `<file>.pacnew`.

The same list therefore gives different images over time, and pinning the base image's digest does not change that. If
you need a fixed, reviewed package set, prebuild the dev container image and pin the digest of the built image.

With the default `cleanup=all`, the feature removes downloaded packages and sync databases from their default
directories. `packages` keeps sync databases and `none` skips feature cleanup. To install more packages later, run
`pacman -Syu <package>`.

## Security

- `pacman` verifies each package's signature against the image's keyring, as the image's `SigLevel` requires; the
  feature never weakens that check, also not for a repository-qualified entry or with `parallelDownloads`. The Arch
  Linux repositories publish their databases unsigned, so the list of packages, versions, and checksums is protected
  only by TLS to the mirror the image configures.
- When a package is signed by a packager key that the image's keyring lacks, or holds only as expired, `pacman` fetches
  that key into the keyring under `/etc/pacman.d/gnupg`. It looks the key up in the Web Key Directory of the domain of
  the key's e-mail address, which need not be a host Arch Linux runs, and then on `keyserver.ubuntu.com`. A fetched key
  gains no trust of its own: a package it signs installs only when the Arch Linux master keys already in the keyring
  certify the key. A fetched key stays in the keyring, also when the installation fails.
- The devcontainer CLI evaluates option values in a shell before the feature runs, so a double quote, dollar sign, or
  backtick in `packages` is expanded as root at that point. Never put untrusted text into the option.
- A package you list, or one the upgrade installs, may itself change the keyring or files under `/etc/pacman.d`
  (`archlinux-keyring` does). The feature does not undo that.

## Installing twice

A second installation does the same as the first with its own list and its own controls, including the full system
upgrade: the packages either list named stay installed, unless the upgrade replaces one, and any installed package may
be upgraded. A constraint below the installed version (`name<version`, or `name=version` with an older version) fails
when no configured repository offers a version that satisfies it.

When a repository earlier in the configured order offers a newer version than the one a qualified entry names, repeated
installations with the same options alternate: one installs the named repository's version, the next finds the entry
satisfied and upgrades the package to the newer version, the one after that replaces it with the named repository's
version again. Every one of them succeeds. The feature keeps no state between installations and does not prevent this.

## OS support

Arch Linux images that provide `pacman`; the tested images are listed in
[test/pacman-packages/compatibility.json](../../test/pacman-packages/compatibility.json). Arch Linux publishes no
official arm64 image, so only amd64 is tested. On an image without `pacman`, a non-empty list fails with a message
naming the detected distribution.

Repository-qualified entries and `parallelDownloads` were verified with pacman 7.1.0, the version of the tested image.
Their behavior with any other pacman version is not verified.

## Installation controls

`cleanup` (all): Remove all managed caches, package files only, or skip feature cleanup. Native retention remains
independent.

`parallelDownloads` (empty): Upper bound of simultaneous package downloads, a whole number from 1 to 20, or empty to
inherit image settings; applies only to this invocation.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged and create nothing.

Cleanup affects only `/var/cache/pacman/pkg` and `/var/lib/pacman/sync`; custom `CacheDir` and `DBPath` locations stay
untouched. Every non-empty invocation still performs a full system synchronization and upgrade.

## Download controls

### What the feature sets explicitly

Nothing, unless `parallelDownloads` is set. `pacman` takes its number of simultaneous downloads (`ParallelDownloads`)
from its configuration alone, so for a non-empty value and a non-empty list the feature writes a temporary file under
`/tmp`, readable by root only, that includes `/etc/pacman.conf` and then sets that one value, and hands it to its one
`pacman` call with `--config`. Before the call it asks `pacman-conf` whether the configuration resolves to the requested
value. If it does not (`/etc/pacman.conf` is missing, `pacman-conf` is missing, or this `pacman` does not know the
setting), the installation fails and names `parallelDownloads` instead of going on with the image's value. The file is
removed when the feature exits, whether the installation succeeded or failed.

- Accepted values are `1` to `20`, written without a sign, a leading zero, or whitespace. `pacman` does not retry a
  failed download, so a high value can fail on a mirror that limits simultaneous connections where a lower one succeeds.
- `pacman` writes its command line to `/var/log/pacman.log`, so the log keeps the path of the removed file.
- The file includes `/etc/pacman.conf`. An image whose `pacman` reads its default configuration from another path is not
  supported with a non-empty value; whether such images exist was not verified.

### What is inherited

Everything else: the whole `pacman.conf` of the image, including its repositories and their order, their servers and
`Usage`, every `SigLevel`, the keyring, the download user and sandbox settings, and, with `parallelDownloads` empty, the
image's `ParallelDownloads` (or `pacman`'s single download stream when the image sets none). The feature sets no
environment variable for `pacman` and passes no other argument than the ones named here.

### Proxy

The feature has no proxy option and neither sets, changes, nor removes a proxy variable: `pacman` receives the build
environment as it is. `pacman` downloads with libcurl, and `https_proxy`, `HTTPS_PROXY`, `ALL_PROXY`, and `no_proxy`
were observed to take effect. Which of them wins when several are set is libcurl's rule and was not verified.

### Locks and retries

The feature has no option for retries, for waiting on the database lock, or for timeouts, because `pacman` offers no
bounded control for them, and it does not emulate one: it never repeats a failed `pacman` call and never waits for or
removes a lock. What `pacman` does instead, as of pacman 7.1.0:

- `pacman` does not wait for its database lock. When `/var/lib/pacman/db.lck` exists, also as a leftover of a killed
  `pacman`, the installation fails at once and the file stays.
- `pacman` has no retry count. When a download from one server of a repository fails, it goes on to the repository's
  next server, and the installation fails when none is left.
- `pacman` gives up connecting to a server after 10 seconds and aborts a transfer that stays below 1 byte per second for
  10 seconds. Neither number can be configured.
