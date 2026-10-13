
# ZYPPER packages (zypper-packages)

Installs listed system packages from the repositories the image already enables.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/zypper-packages:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| packages | Comma-separated native package entries. Whitespace around entries and empty entries are ignored. | string | - |
| installRecommends | Include optional dependencies during native package resolution. | boolean | false |
| refreshPolicy | Select native default refresh, check every repository, or require cached metadata without refreshing. | string | default |
| cleanup | Remove all managed caches, package files only, or skip feature cleanup. Native retention remains independent. | string | all |
| exactNames | Match entries by package name only, without falling back to a package that provides the name; applies only to this invocation. | boolean | false |
| repositories | Comma-separated aliases of repositories the image enables, to refresh and install from these only, or empty to use every enabled repository; applies only to this invocation. | string | - |
| lockTimeout | Seconds from 1 to 3600 that each zypper call waits for the libzypp lock, or empty to inherit image settings; applies only to this invocation. | string | - |
| connectTimeout | Seconds from 1 to 3600 allowed for the connection phase of each download, or empty to inherit image settings; applies only to this invocation. | string | - |
| transferTimeout | Seconds from 1 to 3600 without received data before a download is aborted, or empty to inherit image settings; applies only to this invocation. | string | - |
| downloadRetries | Retries from 0 to 10 of a failed repository metadata request, or empty to inherit image settings; applies only to this invocation. | string | - |

## Usage

Use `packages` for a comma-separated list of native package names, version pins, or architecture qualifiers. Empty lists
install nothing. Entries are validated before any package-manager command; paths, RPM files, options, patterns, and
shell characters are refused. The feature uses the image's existing repositories, trusted keys, and verification
settings.

Examples: `bc,file`, `tree=2.2.1` (a version pin), `tree>=2.0` (a version constraint), `bc.x86_64` (an architecture
qualifier), or `awk` (a native capability). Versions and architectures must be offered by the enabled repositories.
Repository prefixes and `pattern:` targets are refused.

## Installation controls

`installRecommends` (default `false`): Include optional dependencies during native package resolution.

`refreshPolicy` (default `default`): Select native default refresh, check every repository, or require cached metadata
without refreshing.

`cleanup` (default `all`): Remove all managed caches, package files only, or skip feature cleanup. Image hooks and
native retention settings may remove downloaded packages even when feature cleanup is disabled.

Controls apply separately on each invocation; disabling optional dependencies does not remove installed packages.
Invalid controls fail even with an empty list. Native hooks can remove downloaded packages independently of cleanup.

## Native behavior

Zypper resolves capabilities natively and may upgrade unpinned packages and needed dependencies. A pin below an
installed version leaves that newer version installed; the feature does not enable Zypper's downgrade override.

Both `refreshPolicy=default` and `always` require a successful refresh of every enabled repository before installation.
With `never`, every enabled repository must have usable cached metadata; package downloads remain permitted.
Noninteractive mode rejects license acceptance and new signing-key prompts, so an installation requiring either fails.
SUSE Linux Enterprise images are outside this release.

## Configuration

The facts below were checked with zypper 1.14.101 and libzypp 17.38.16, the versions in both tested images, on amd64.

### What the feature sets explicitly

Each of these options is inert at its default and applies to one invocation only: nothing the feature sets is left in
the image.

`exactNames` (default `false`): `true` matches each entry by package name only (`zypper install --name`). An entry that
is only a capability, such as `awk`, then fails instead of installing a package that provides it; write the package
name, `gawk`. Version, range, and architecture forms work as before.

`repositories` (default empty): a comma-separated list of repository aliases, for example `repo-oss,repo-update`. The
refresh, the cached-metadata check of `refreshPolicy=never`, and the whole installation then work with these
repositories only (`zypper --repo`), so a repository outside the list is neither contacted nor needed.

- Write each alias exactly as `zypper lr` shows it in the Alias column. Aliases differ between images:
  `opensuse/tumbleweed` has `repo-oss`, and `opensuse/leap:16.0` has `openSUSE:repo-oss`. A repository's name, number,
  or URI is refused.
- The repository must be enabled in the image. The feature enables, adds, and edits no repository.
- An alias must start with a letter or digit and consist of letters, digits, `.`, `_`, `:`, `+`, and `-`. A repository
  whose alias holds another character, such as a space, cannot be selected. Neither can one whose alias is also the name
  of another repository, because zypper could take that other repository for it.
- Every dependency must come from the selected repositories too. A package whose dependency is offered only outside the
  selection fails to install.
- zypper's manual discourages working with a selection, because the resolver decides without the other repositories. The
  feature passes zypper nothing that permits removing a package, but for an installed package that came from an
  unselected repository it cannot promise more than zypper does.
- `cleanup=all` still removes the caches of every repository, selected or not.

`lockTimeout` (default empty): seconds from 1 to 3600 that each `zypper` call of the feature waits for libzypp's system
lock (`ZYPP_LOCK_TIMEOUT`, set for those calls only).

`connectTimeout` (default empty): seconds from 1 to 3600 for the connection phase of each download
(`download.connect_timeout`).

`transferTimeout` (default empty): seconds from 1 to 3600 without received data after which a download is aborted
(`download.transfer_timeout`). It is an inactivity limit, so a slow transfer that keeps receiving data is not aborted.
Apart from it, libzypp ends every single transfer after 3600 seconds; that limit was read from libzypp's source and was
not measured.

`downloadRetries` (default empty): retries from 0 to 10 of a failed repository metadata request after its first attempt
(`download.max_silent_tries`, set to the value plus one). `0` turns retries off. It does not repeat package downloads:
on the tested libzypp a package file is tried once on each mirror, whatever the value (observed on Tumbleweed).

The three download options travel in one temporary libzypp configuration file under `/run/zypp/zypp.conf.d`, which holds
only the keys of the options that are set and is removed when the feature exits, after a failure too. They need a
libzypp that reads such files, which provides the RPM capability `libzypp(econf)`; on an older libzypp a non-empty value
fails the build instead of being ignored.

### What is inherited

Everything no option declares stays as the image and the build environment configure it: signature checking, trusted
keys, repositories, the solver, caches, and mirrors.

- libzypp reads `zypp.conf`; `zypper.conf` configures the command-line tool and holds no network, lock, or repository
  setting.
- libzypp looks for `zypp.conf` in `/etc/zypp` and then in the vendor directory `/usr/etc/zypp`, and reads the `*.conf`
  files of their `zypp.conf.d` directories afterwards, in the order of their file names; a later setting overrides an
  earlier one. The feature's file sorts after ordinary names, but a file of the image that sorts even later and sets the
  same key overrides the option. The feature does not detect this.
- `ZYPP_CONF` in the build environment, even when it is empty, makes libzypp read only the file it names and ignore
  every other configuration file. The feature passes the variable on unchanged. Since its own file would be ignored too,
  a non-empty `connectTimeout`, `transferTimeout`, or `downloadRetries` then fails the build; set those values in the
  file `ZYPP_CONF` names instead.
- With an empty option the matching setting of the image applies. libzypp's own defaults are 60 seconds to connect, 180
  seconds without data, one attempt, and no waiting for the lock.

### Proxy

The feature has no proxy option and sets no proxy variable; zypper uses what the image or the build environment
configures.

- For an `http` repository zypper uses the lower-case `http_proxy` and `all_proxy` and the upper-case `ALL_PROXY`. It
  ignores the upper-case `HTTP_PROXY`.
- For an `https` repository it uses `https_proxy` and `HTTPS_PROXY`, which do not apply to an `http` repository
  (observed on Leap only; Tumbleweed enables no `https` repository).
- `/etc/sysconfig/proxy` with `PROXY_ENABLED="yes"` is used when no variable is set.
- `no_proxy="*"` bypasses the proxy. `no_proxy=opensuse.org` and `no_proxy=.opensuse.org` did not bypass it for every
  request of a refresh.
- Not verified: any other form of `no_proxy`, and which of the environment and `/etc/sysconfig/proxy` wins when both are
  set.

### Locks and retries

- Without `lockTimeout` and without a setting of the image (`lock_timeout`, or `ZYPP_LOCK_TIMEOUT` in the build
  environment), zypper does not wait: it fails at once when another process holds the lock.
- The wait is counted for each `zypper` call, not for the feature as a whole, and it is coarse: libzypp checks the lock
  again after growing pauses, so a call can wait a few seconds longer than the value.
- The feature makes each `zypper` call once. It does not repeat a failed refresh or installation, with or without
  `downloadRetries`.
- zypper's own fixed retries ("Retrying in 30 seconds...") belong to commands the feature does not run, such as
  `zypper download`, and are not affected by any option.

## Security and repeated installation

The devcontainer CLI evaluates option values in a shell before the feature runs. Never put untrusted text in options.
The feature keeps the image's signature and TLS configuration; repositories the image explicitly leaves unchecked stay
unchecked. Installed packages may themselves ship configuration or keys. A second invocation uses its own list and
controls, retaining earlier packages except where native resolution replaces them.

## OS support

Tested images and architectures: [compatibility.json](../../test/zypper-packages/compatibility.json).


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/zypper-packages/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
