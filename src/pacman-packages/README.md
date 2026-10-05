
# Pacman packages (pacman-packages)

Installs a list of system packages with pacman from the repositories the Arch Linux image already configures, as part of a full system upgrade.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/pacman-packages:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| packages | Comma-separated packages to install: a name, a provided name, or a group, optionally with a version constraint (name>=version). Whitespace around entries and empty entries are ignored; an empty list installs nothing, and a non-empty list also upgrades the whole system. | string | - |
| cleanup | Remove all managed caches, package files only, or skip feature cleanup. Native retention remains independent. | string | all |

## Usage

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/pacman-packages:1": {
      "packages": "bc, tree, rsync>=3.2"
    }
  }
}
```

The feature installs the listed packages with `pacman` from the repositories the image already configures. It adds no
repository, mirror, key, or pacman configuration of its own, and leaves out packages that a listed package only names as
optional dependencies; list them explicitly when you need them.

## Entries

`packages` is a comma-separated list; whitespace around an entry and empty entries are ignored, so an empty list, or one
of only commas, installs nothing and succeeds on any image. `pacman` resolves each entry as it resolves any target:

- the exact name of a package (`python-pip`, `libsigc++`, `gtk4`);
- otherwise a name that packages provide (`cron`): when several packages provide it, the first one `pacman` offers is
  installed, so name the package itself when you need a specific provider;
- otherwise a package group (`xorg-fonts`): every package of the group is installed.

An entry may end in a version constraint: `name=version`, `name<version`, `name<=version`, `name>version`, or
`name>=version`. A constraint only checks the version the repositories offer; it cannot install an older one, and the
installation fails when the offered version does not satisfy it.

The feature refuses, before it changes anything, any entry holding `/` (paths, URLs, `repository/name`), an entry
starting with `-` or `.`, whitespace inside an entry, and any character outside ASCII letters, digits, and
`@ . _ + - : < > =`, such as a shell metacharacter or a glob. An entry is never matched as a regular expression or a
glob: a name that is no package, provided name, or group fails, and so does a package that conflicts with an installed
one.

## Full system upgrade

Arch Linux supports only full system upgrades, so a non-empty list also upgrades the whole system: the feature runs one
`pacman -Syu`, which upgrades every installed package the repositories offer in a newer version, replaces an installed
package with the one the repositories declare as its replacement, and installs the list. Nothing is ever downgraded. A
configuration file you changed is kept when its package is upgraded; a differing new version is written beside it as
`<file>.pacnew`.

The same list therefore gives different images over time, and pinning the base image's digest does not change that. If
you need a fixed, reviewed package set, prebuild the dev container image and pin the digest of the built image.

With the default `cleanup=all`, the feature removes downloaded packages and sync databases from their default
directories. `packages` keeps sync databases and `none` skips feature cleanup. To install more packages later, run
`pacman -Syu <package>`.

## Security

- `pacman` verifies each package's signature against the image's keyring, as the image's `SigLevel` requires; the
  feature never weakens that check. The Arch Linux repositories publish their databases unsigned, so the list of
  packages, versions, and checksums is protected only by TLS to the mirror the image configures.
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

A second installation does the same as the first with its own list, including the full system upgrade: the packages
either list named stay installed, unless the upgrade replaces one, and any installed package may be upgraded. A
constraint below the installed version (`name<version`, or `name=version` with an older version) fails, because the
feature never downgrades.

## OS support

Arch Linux images that provide `pacman`; the tested images are listed in
[test/pacman-packages/compatibility.json](../../test/pacman-packages/compatibility.json). Arch Linux publishes no
official arm64 image, so only amd64 is tested. On an image without `pacman`, a non-empty list fails with a message
naming the detected distribution.

## Installation controls

`cleanup` (all): Remove all managed caches, package files only, or skip feature cleanup. Native retention remains
independent.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged.

Cleanup affects only `/var/cache/pacman/pkg` and `/var/lib/pacman/sync`; custom `CacheDir` and `DBPath` locations stay
untouched. Every non-empty invocation still performs a full system synchronization and upgrade.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/pacman-packages/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
