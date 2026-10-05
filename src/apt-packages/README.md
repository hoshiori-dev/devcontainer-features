
# APT packages (apt-packages)

Installs a list of system packages with apt-get from the repositories the Debian or Ubuntu image already configures.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/apt-packages:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| packages | Comma-separated packages to install: name, name=version, or name:architecture. Whitespace around entries and empty entries are ignored; an empty list installs nothing. | string | - |
| installRecommends | Include recommended dependencies; suggested dependencies remain excluded. | boolean | false |
| refreshPolicy | Select native default refresh, check every repository, or require cached metadata without refreshing. | string | default |
| cleanup | Remove all managed caches, package files only, or skip feature cleanup. Native retention remains independent. | string | all |
| networkTimeout | Native network timeout in seconds (1–3600), or empty to inherit image settings; applies only to this invocation. | string | - |

## Usage

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/apt-packages:1": {
      "packages": "bc, file, g++"
    }
  }
}
```

The feature installs the listed packages with `apt-get` from the repositories the image already configures. It adds no
repository, key, or apt configuration of its own. Suggested packages are excluded; recommended packages are excluded by
default and can be enabled with `installRecommends`.

## Entries

`packages` is a comma-separated list; whitespace around an entry and empty entries are ignored, so an empty list, or one
of only commas, installs nothing and succeeds on any image. Each entry is one of:

- `name`: the exact package name, in lower case (`python3.11`, `libstdc++6`, `g++`);
- `name=version`: that version, which the image's repositories must offer;
- `name:architecture`: the image's native architecture, or a foreign one already enabled with `dpkg --add-architecture`;
  the feature enables none.

The feature refuses, before it changes anything, any entry holding `/` (paths, URLs, `name/release`), an entry starting
with `-` or ending in `-`, upper case in the package name, whitespace inside an entry, and any character outside those
above, such as a shell metacharacter, a glob, or an APT search pattern. An entry is never matched as a regular
expression, glob, or task: a name that is not an exact actual or virtual package name fails. A trailing `+` is accepted
only as part of an exact name or version, so `g++` works but `bc+` does not mean `bc`. Every name and pinned version is
checked after the index is ready and before any package is installed.

## Package index

With `refreshPolicy=default`, when the image holds no package index, the feature runs `apt-get update` first and fails
if any configured repository cannot be refreshed. When the image already holds an index, the feature uses it as it is,
even if it is stale or covers only some repositories; a version the mirrors no longer serve then fails. Clear
`/var/lib/apt/lists` or run `apt-get update` in your Dockerfile before this feature if the image ships an old index.
With `always`, every configured repository is refreshed before installing. With `never`, the feature requires an
existing index and does not refresh, while package downloads remain possible. `cleanup=all` removes downloaded packages
and indexes at APT's effective directories; `packages` keeps indexes; `none` skips explicit cleanup. Native image hooks
can still delete downloaded files.

## Security

- APT verifies each repository's signature with the keys the image trusts for it; the feature never weakens that check.
  The supported images fetch over plain HTTP, where signatures protect integrity but not freshness: an attacker on the
  network path during the build can replay an older, validly signed index and hold back security updates. If you need
  freshness, switch the image's sources to `https://`, which the Debian and Ubuntu archives serve.
- The devcontainer CLI evaluates option values in a shell before the feature runs, so a double quote, dollar sign, or
  backtick in `packages` is expanded as root at that point. Never put untrusted text into the option.
- A package you list, or one it needs, may itself add a repository, key, or apt configuration file. The feature does not
  undo that.

## Installing twice

A second installation installs its own list the same way, and every package either list named stays installed on
success. The feature never removes installed packages: if an installation requires removal to resolve a conflict, it
fails before changing installed packages. For example, installing `openntpd` after `chrony` fails and leaves `chrony`
installed. A package listed without a version, or one a listed package needs, may be upgraded to the version the
repositories now offer; pin `name=version` for a stable result. A version below the installed one fails, because the
feature never downgrades. The feature never overrides a package hold or an APT pin the image set.

## OS support

Debian and Ubuntu images that provide `apt-get`; the tested images are listed in
[test/apt-packages/compatibility.json](../../test/apt-packages/compatibility.json). On an image without `apt-get`, a
non-empty list fails with a message naming the detected distribution.

## Installation controls

`installRecommends` (false): Include recommended dependencies; suggested dependencies remain excluded. `refreshPolicy`
(default): Select native default refresh, check every repository, or require cached metadata without refreshing.
`cleanup` (all): Remove all managed caches, package files only, or skip feature cleanup. Native retention remains
independent. `networkTimeout` (default: empty): Native network timeout in seconds (1–3600), or empty to inherit image
settings; applies only to this invocation.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged. Disabling optional dependencies does not remove installed
packages.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/apt-packages/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
