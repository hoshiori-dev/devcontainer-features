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
repository, key, or apt configuration of its own. Recommended and suggested packages are excluded by default;
`installRecommends` and `installSuggests` include them.

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
feature never downgrades. The feature never overrides a package hold. Without `targetRelease` every APT pin the image
set stays in effect; with it, pins rank as [Target release](#target-release) describes.

No control outlives its installation: a later installation uses its own values and the image's configuration. It does
not undo what an earlier one did either: a package installed from another release is not downgraded, a suggested package
stays installed, and a replaced configuration file is not restored.

## Target release

`targetRelease` makes APT prefer one release among the sources the image already configures, on the install call only
(`apt-get --target-release`). The value is one plain name: a suite name (`bookworm-security`, `noble-updates`), a
codename (`bookworm`, `noble`), or a version (`12.15`, `24.04`). A pattern, a regular expression, a `key=value`
selector, and `now` are refused. A name that no release of the package index carries fails before any package changes;
the feature never adds a source to make a release available.

It is a preference, not a filter: a dependency the release does not offer still comes from another release, and
`name=version` keeps its version. The name selects every suite whose suite name, codename, or version equals it, which
has two effects that are easy to miss:

- Debian's suites have distinct codenames, so `bookworm` prefers the main suite alone. A package that is not installed
  yet then comes from it even when `bookworm-security` offers a newer version: the option holds back security updates.
- Ubuntu's pockets share one codename and one version, so `noble` or `24.04` prefers all of them, backports included,
  also on an image that pinned backports down. A pocket's own suite name, such as `noble-updates`, prefers that pocket
  alone.

A held package is never changed, and an installed package is never downgraded. APT gives each suite the name selects
priority 990, in place of a pin the image set on that whole suite, so a pin of -1 on a suite no longer excludes it when
`targetRelease` selects it. A pin on another suite, and a pin that names a package, keep their priority: above 990 they
win, a negative one still excludes, below 990 they lose to the target release, and at exactly 990 the newer version
wins.

## Suggested packages

`installSuggests=true` makes APT install suggested packages as well, with or without `installRecommends`. APT follows
the suggestions of every package it newly installs, not only of the listed ones, so the installed set can grow from tens
of packages to thousands. The feature sets no limit; it still removes no package.

## Configuration files

`conffilePolicy` decides, without a question, what dpkg does where the path of a conffile holds other content than the
package expects: on an upgrade, on a first installation over a file the image already holds, and after a package was
removed but not purged.

- `keep` (the default) leaves the image's file and writes the packaged one beside it as `<file>.dpkg-dist`.
- `replace` installs the packaged file, saves the image's beside it as `<file>.dpkg-old`, and installs a conffile again
  that the image deleted.

Either policy applies to every package the installation installs or upgrades, dependencies included, and holds whatever
the image's APT or dpkg configuration says about conffiles. Only dpkg conffiles are covered: a configuration file that a
package manages through its maintainer scripts, for example with ucf or debconf, is handled as that package decides.

## Downloads and locks

`downloadRetries` is how often APT retries a failed download after its first attempt, on the index refresh and on the
installation; `0` disables retries, and an empty value leaves APT's default of 3 or the image's setting. APT decides
which failures it retries: a connection that is refused, closed without an answer, or stalled is retried, while a file
the repository reports as missing is requested once. APT waits longer before each retry (1 s, 2 s, 4 s, and so on), so a
high value can add minutes for each file that keeps failing. Neither `downloadRetries` nor `networkTimeout` is a
deadline for the whole installation.

`lockTimeout` is how many seconds the installation waits for dpkg's locks while another process holds them; when the
wait ends first, the feature fails without changing a package. With an empty value `apt-get` fails at once, unless the
image's configuration sets a wait. The index refresh and the download of package files never wait: APT offers no wait
for their locks.

## Image configuration and proxy

The feature writes no configuration file and sets no environment variable. Each option reaches APT as an argument of the
feature's own `apt-get` calls, and APT reads its configuration in this order, a later source overriding an earlier one:

1. the file the environment variable `APT_CONFIG` names, if the build environment sets it;
2. the image's configuration under `/etc/apt`;
3. the arguments of the feature.

So an option you set overrides the matching setting of the image for that call only, and an option left empty
(`targetRelease`, `networkTimeout`, `downloadRetries`, `lockTimeout`) inherits it. `installRecommends`,
`installSuggests`, and `conffilePolicy` always carry a value and always override.

The feature has no proxy option and passes no proxy setting. For the `http://` sources of the supported images, APT
honors at build time:

- `Acquire::http::Proxy` in the image's APT configuration, which wins over the environment;
- the lower-case environment variable `http_proxy`, and `no_proxy` for hosts to reach directly.

Upper-case `HTTP_PROXY` alone is ignored. Whether a proxy variable of your build reaches the step that installs the
feature depends on the tool that builds the image.

## OS support

Debian and Ubuntu images that provide `apt-get`; the tested images are listed in
[test/apt-packages/compatibility.json](../../test/apt-packages/compatibility.json). On an image without `apt-get`, a
non-empty list fails with a message naming the detected distribution.

## Installation controls

`installRecommends` (false): Include recommended dependencies; installSuggests selects suggested ones. `installSuggests`
(false): Include suggested packages, independently of installRecommends. `refreshPolicy` (default): Select native
default refresh, check every repository, or require cached metadata without refreshing. `cleanup` (all): Remove all
managed caches, package files only, or skip feature cleanup. Native retention remains independent. `conffilePolicy`
(keep): Keep the image's file, or replace it with the packaged one, where a conffile's path holds other content than the
package expects. `networkTimeout` (default: empty): Native network timeout in seconds (1–3600), or empty to inherit
image settings. `downloadRetries` (default: empty): How often APT retries a failed download after its first attempt
(0–10), or empty to inherit image settings. `lockTimeout` (default: empty): Seconds the installation waits for dpkg's
locks (1–3600), or empty to inherit image settings. `targetRelease` (default: empty): Suite name, codename, or version
of a release among the image's sources that APT prefers when installing, or empty to inherit image settings.

Controls apply separately on each invocation and never persist image configuration. Invalid values fail even for an
empty package list; valid empty lists leave caches unchanged. Disabling optional dependencies does not remove installed
packages.
