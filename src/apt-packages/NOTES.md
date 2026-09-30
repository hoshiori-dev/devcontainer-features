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
repository, key, or apt configuration of its own, and leaves out packages that a listed package only recommends or
suggests; list them explicitly when you need them.

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
expression, glob, or task: a name that is not an exact package name fails.

## Package index

When the image holds no package index, the feature runs `apt-get update` first and fails if any configured repository
cannot be refreshed. When the image already holds an index, the feature uses it as it is, even if it is stale or covers
only some repositories; a version the mirrors no longer serve then fails. Clear `/var/lib/apt/lists` or run
`apt-get update` in your Dockerfile before this feature if the image ships an old index. After installing, the feature
removes the downloaded packages and every index list.

## Security

- APT verifies each repository's signature with the keys the image trusts for it; the feature never weakens that check.
  The supported images fetch over plain HTTP, where signatures protect integrity but not freshness: an attacker on the
  network path during the build can replay an older, validly signed index and hold back security updates. If you need
  freshness, switch the image's sources to `https://`, which the Debian and Ubuntu archives serve.
- The devcontainer CLI evaluates option values in a shell before the feature runs, so a `"`, `$`, or backtick in
  `packages` is expanded as root at that point. Never put untrusted text into the option.
- A package you list, or one it needs, may itself add a repository, key, or apt configuration file. The feature does not
  undo that.

## Installing twice

A second installation installs its own list the same way, and every package either list named stays installed. A package
listed without a version, or one a listed package needs, may be upgraded to the version the repositories now offer; pin
`name=version` for a stable result. A version below the installed one fails, because the feature never downgrades. The
feature never overrides a package hold or an APT pin the image set.

## OS support

Debian and Ubuntu images that provide `apt-get`; the tested images are listed in
[test/apt-packages/compatibility.json](../../test/apt-packages/compatibility.json). On an image without `apt-get`, a
non-empty list fails with a message naming the detected distribution.
