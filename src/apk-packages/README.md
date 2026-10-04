
# APK packages (apk-packages)

Installs a list of system packages with apk from the repositories the Alpine Linux image already configures.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/apk-packages:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| packages | Comma-separated packages to install: name, name=version, name~version, a range such as name>=version, name@tag, or a provided name such as cmd:jq. Whitespace around entries and empty entries are ignored; an empty list installs nothing. | string | - |
| refreshPolicy | Select native default refresh, check every repository, or require cached metadata without refreshing. | string | default |
| cleanup | Remove all managed caches, package files only, or skip feature cleanup. Native retention remains independent. | string | all |
| networkTimeout | Native network timeout in seconds (1–3600), or empty to inherit image settings; applies only to this invocation. | string | - |
| upgradePackages | Request upgrades of listed packages and their dependencies with apk add, preserving world constraints. | boolean | false |

## Usage

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/apk-packages:1": {
      "packages": "file, tree, g++"
    }
  }
}
```

The feature installs the listed packages with `apk` from the repositories the image already configures. It adds no
repository, tag, key, or apk configuration of its own, and it does not upgrade the system.

## Entries

`packages` is a comma-separated list; whitespace around an entry and empty entries are ignored, so an empty list, or one
of only commas, installs nothing and succeeds on any image. Each entry is passed to `apk add` unchanged and is one of:

- `name`: the exact name of a package (`file`, `g++`, `libstdc++`), or a name a package provides, such as `cmd:jq`,
  `so:libcrypto.so.3`, or `pc:zlib`. For a provided name apk picks one of the providers; name the package itself when
  you need a specific one.
- `name=version`: exactly that version. An Alpine branch keeps only the current build of each package, so a pin stops
  resolving when the branch updates the package; prefer `name~prefix` (for example `jq~1.8`) for a version family.
- `name~prefix`, or a range such as `name>=version`, `name>version`, `name<=version`, `name<version`: a version that
  starts with the prefix or lies in the range.
- `name@tag`: the package from the repository the image configures with that tag in `/etc/apk/repositories`. The feature
  adds no repository and no tag; a tag the image does not configure fails.

The feature refuses, before it changes anything, an entry that does not start with an ASCII letter or digit (such as an
option starting with `-`, or apk's conflict marker `!`) and an entry holding any character other than ASCII letters,
digits, and `.`, `_`, `+`, `-`, `:`, `~`, `=`, `@`, `<`, `>`: a `/` (paths and URLs), whitespace inside an entry, globs,
and other shell characters. An entry is never read as a local package file. A name that no package has or provides, a
version the repositories do not offer, and a constraint apk cannot read all fail the build without installing anything.

## What apk does with the list

- Every entry is recorded in apk's world (`/etc/apk/world`), constraint included. A constraint stays in effect for later
  apk operations: an `apk upgrade` in your Dockerfile keeps a package pinned with `name=version` where it is.
- An installed package keeps its version unless an entry's constraint or a newly installed package requires another one.
  When the installed version does not satisfy an entry's constraint, apk replaces it with one that does, which can be a
  lower version.
- apk also installs packages whose install-if conditions are all met. For example, listing `docs` together with `jq`
  installs `jq-doc`, and the `-doc` packages of the other installed packages. apk has no option to turn this off.

## Package index

With `refreshPolicy=default` or `always`, every configured repository is refreshed and verified before installation.
`never` requires cached indexes for every repository, reads existing image caches without modifying them, and permits
package downloads without refreshing indexes. Missing or invalid indexes fail before installation.

`cleanup=all` removes the temporary feature cache. `packages` retains indexes under `/var/cache/apk-packages` and
removes package files; `none` skips explicit cache deletion. Native apk retention remains independent. Existing image
caches are preserved. Retained feature indexes can be reused by a later `refreshPolicy=never` invocation. Temporary work
directories are removed even on failure.

## Security

- apk verifies each repository index against the keys the image trusts in `/etc/apk/keys` and each package against the
  hash its index records; the feature never weakens that check. Options the image's own apk configuration sets stay the
  image's decision.
- The devcontainer CLI evaluates option values in a shell before the feature runs, so a double quote, dollar sign, or
  backtick in `packages` is expanded as root at that point. Never put untrusted text into the option.
- A package you list, or one it needs, may itself add a repository, key, or apk configuration file. The feature does not
  undo that.
- On `alpine:3.22` the `community` repository no longer receives fixes, so packages installed from it may lack security
  fixes.

## Installing twice

A second installation installs its own list the same way, and every package either list named stays installed. For a
name both lists hold, the later entry replaces the earlier one in apk's world, with its constraint or without one. A
constraint that the repositories cannot satisfy fails and changes nothing.

## OS support

Alpine Linux images, which provide `apk`; the tested images are listed in
[test/apk-packages/compatibility.json](../../test/apk-packages/compatibility.json). On an image without `apk`, a
non-empty list fails with a message naming the detected distribution.

## Installation controls

`refreshPolicy` (default): Select native default refresh, check every repository, or require cached metadata without
refreshing. `cleanup` (all): Remove all managed caches, package files only, or skip feature cleanup. Native retention
remains independent. `networkTimeout` (): Native network timeout in seconds (1–3600), or empty to inherit image
settings; applies only to this invocation. `upgradePackages` (false): Request upgrades of listed packages and their
dependencies with apk add, preserving world constraints.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged. Previously installed packages remain installed.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/apk-packages/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
