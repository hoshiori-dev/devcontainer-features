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
repository, tag, key, or apk configuration of its own, and it does not perform a full system upgrade.

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
- With `upgradePackages=false` and `latest=false`, an installed package keeps its version unless an entry's constraint
  or a newly installed package requires another one. When the installed version does not satisfy an entry's constraint,
  apk replaces it with one that does, which can be a lower version.
- apk also installs packages whose install-if conditions are all met. For example, listing `docs` together with `jq`
  installs `jq-doc`, and the `-doc` packages of the other installed packages. apk has no option to turn this off.

## Requiring the highest version

`latest=true` passes `--latest` to `apk add`. It is a requirement, not a preference: every package listed without a
repository tag, and every dependency apk resolves for it, must end at the highest version the image's untagged
repositories offer, and the build fails, changing nothing, when apk cannot select that version.

- This is the difference from `upgradePackages=true`, which succeeds and keeps a version that is held back. A constraint
  already in apk's world on a dependency, or an entry such as `name=version` or `name<version` that excludes the highest
  version, fails with `latest=true`; `name>=version`, `name~prefix`, and `name=version` naming the highest version work.
- It changes packages you did not list: the dependencies of the listed packages, and installed packages that depend on a
  raised package at an exact version.
- It does not reach `name@tag` entries. Such an entry resolves exactly as without the option, so it can stay at an older
  version without a failure; use `upgradePackages=true` to raise it. With both options set, entries without a tag behave
  as with `latest=true` and tagged entries as with `upgradePackages=true`.
- It never lowers an installed version by itself, and it does not persist: nothing is pinned in apk's world, so a later
  `apk add` without it may keep an older version.

## Package index

With `refreshPolicy=default` or `always`, every configured repository is refreshed and verified before installation.
`never` requires cached indexes for every repository, reads existing image caches without modifying them, and permits
package downloads without refreshing indexes. Missing or invalid indexes fail before installation.

`cleanup` alone decides what the feature's own cache keeps after a successful installation; no other option controls
retention. `all` uses a temporary cache and removes it, so neither an index nor a package file remains. `packages` keeps
the indexes under `/var/cache/apk-packages` and removes the package files. `none` keeps both the indexes and the package
files apk downloaded for that invocation. Existing image caches are preserved. Retained feature indexes can be reused by
a later `refreshPolicy=never` invocation. Temporary work directories are removed even on failure.

One image setting defeats `packages` and `none`: when the image's apk configuration holds `no-cache`, which only
apk-tools 3 reads, apk stores nothing, so with `refreshPolicy=default` or `always` the installation succeeds and the
feature's cache stays empty. The feature neither overrides nor checks that setting.

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

`latest` and `lockTimeout` of one installation do not carry over to the next: each passes only what its own options
select. A later `latest=true` raises a package an earlier installation left at an older version; a later `latest=false`
does not by itself lower a version an earlier `latest=true` selected; and a package an earlier `name@tag` entry
installed at a higher version than the untagged repositories offer stays at that version when it is later listed without
the tag and with `latest=true`.

## OS support

Alpine Linux images, which provide `apk`; the tested images are listed in
[test/apk-packages/compatibility.json](../../test/apk-packages/compatibility.json). On an image without `apk`, a
non-empty list fails with a message naming the detected distribution.

## Installation controls

`refreshPolicy` (default): Select native default refresh, check every repository, or require cached metadata without
refreshing. `cleanup` (all): What the feature's own package cache keeps after installation: `all` removes it, `packages`
keeps the package indexes without package files, `none` keeps the indexes and the downloaded package files.
`networkTimeout` (default: empty): Native network timeout in seconds (1–3600), or empty to inherit image settings;
applies only to this invocation. `upgradePackages` (false): Request upgrades of listed packages and their dependencies
with apk add, preserving world constraints. `latest` (false): Require the highest version the image's untagged
repositories offer for packages listed without a tag and their dependencies; the build fails when apk cannot select it.
`lockTimeout` (default: empty): Seconds (1–3600) each apk call of the feature waits for apk's database lock, or empty to
inherit image settings; applies only to this invocation.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged. Previously installed packages remain installed.

## What the feature sets and what it inherits

The statements below were observed with apk-tools 3.0.8 and 2.14.12 on amd64; arm64 is not verified.

### What the feature sets explicitly

Only command-line arguments of its own apk calls, an index refresh (`apk update`) followed by `apk add`:

- always: `--no-interactive`, `--cache-dir` with the feature's own cache, and on `apk add` a cache age under which no
  index counts as stale, so `apk add` checks no remote index after the refresh step;
- only when the option is not at its default: `--timeout` (`networkTimeout`), `--wait` (`lockTimeout`), `--upgrade`
  (`upgradePackages=true`), `--latest` (`latest=true`), and `--no-network` on the index check of `refreshPolicy=never`.

It sets no environment variable for apk and writes no apk configuration file.

### What is inherited

- The image's repositories, tags, and trusted keys.
- The image's apk configuration. apk-tools 3 reads the first existing file of `/etc/apk/config` and `/lib/apk/config`,
  or the file `APK_CONFIG` names instead of `/etc/apk/config`; apk-tools 2 reads none of them. A `timeout`, `wait`,
  `latest`, or `upgrade` setting there applies whenever the matching option is at its default, and a non-default option
  overrides only its own setting, for the feature's apk calls.
- `latest=false` and `upgradePackages=false` add no argument and cannot turn off a `latest` or `upgrade` setting of the
  image: apk has no argument that does.
- A `no-cache` setting of the image (see Package index).

### Proxy

The feature has no proxy option and sets, changes, and unsets no proxy variable: apk runs with the environment the build
gives the feature. apk honors `HTTPS_PROXY` and `https_proxy` (the upper-case one wins when both are set) and bypasses
the proxy for host name suffixes in `NO_PROXY` or `no_proxy`; `HTTP_PROXY` alone does not affect https repositories, and
`ALL_PROXY` is ignored. apk has no command-line or configuration-file proxy setting. Not verified: how proxy variables
of the host or of `devcontainer.json` reach a feature's installation through the devcontainer CLI at build time.

### Locks and retries

apk allows one write transaction at a time and guards it with a lock on `/lib/apk/db/lock`. With `lockTimeout` empty, an
apk call fails at once when another process holds the lock, unless the image's apk configuration sets a wait.
`lockTimeout` is the number of seconds each apk call of the feature waits for the lock before it fails; it overrides an
image setting for those calls only. It is not an overall deadline: the two apk calls wait separately, so a lock held
without interruption fails the build after one wait, while a lock released during the first call's wait and taken again
before the second can delay a failing build by up to twice the value. The feature refuses `0`, text, a sign, and a
number followed by text, which apk itself would read as no wait, another number, or an unbounded wait.

apk has no retry and no parallel-download setting, and the feature retries nothing: a call that fails ends the build.
