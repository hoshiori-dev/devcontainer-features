## Usage

Use `packages` for a comma-separated list of native package names, version pins, or architecture qualifiers. Empty lists
install nothing. Entries are validated before any package-manager command; paths, RPM files, options, patterns, and
shell characters are refused. The feature uses the image's existing repositories, trusted keys, and verification
settings.

Examples: `bc,file`, `file-5.46-6.fc44` (an offered version-release), `bc.x86_64` (an architecture qualifier), or
`libz.so.1` (a native capability). Pins must specify a version offered by the enabled repositories.

## Installation controls

`installWeakDeps` (default `false`): Include optional dependencies during native package resolution.

`refreshPolicy` (default `default`): Select native default refresh, check every repository, or require cached metadata
without refreshing.

`cleanup` (default `all`): Remove all managed caches, package files only, or skip feature cleanup. Image hooks and
native retention settings may remove downloaded packages even when feature cleanup is disabled.

`networkTimeout` (default: empty): Native network timeout in seconds (1–3600), or empty to inherit image settings;
applies only to this invocation.

`best` (default `inherit`): Set DNF's `best` setting for this invocation. With `true`, DNF installs the highest version
the enabled repositories offer of each listed package or fails, so an installed package that the list names without a
version is upgraded when a higher version is offered. With `false`, DNF may fall back to a lower version, and such a
package stays as installed unless another package of the same transaction needs the higher version. With `inherit`, the
image decides: the tested Fedora image turns `best` off, the tested AlmaLinux and Rocky Linux images turn it on. A
pinned version is installed in the same way under every value.

`enableRepositories` (default: empty): Comma-separated identifiers of repositories the image configures but leaves
disabled, such as `crb` on AlmaLinux and Rocky Linux; they are enabled for this invocation. The repository is used with
the settings its own configuration gives it, including its signature check and its key location.

`disableRepositories` (default: empty): Comma-separated identifiers of repositories the image enables; they are left out
for this invocation. A repository that is left out contributes no package, dependency, or update: a listed package that
only it offers fails as unresolvable, and DNF selects the older versions the remaining repositories offer.

`parallelDownloads` (default: empty): Upper bound of simultaneous downloads (1–20), or empty to inherit image settings;
applies only to this invocation. The feature leaves the image's limit of downloads per mirror alone (3 on the tested
images), so a higher value has no visible effect when every package comes from one mirror.

Repository identifiers are those `dnf repolist --all` prints, in the same letter case. Whitespace around an identifier
and empty items are ignored. An identifier starts with an ASCII letter or digit and holds only ASCII letters, digits,
and `_`, `.`, `:`, `-`; patterns such as `crb*` are refused. An identifier in both lists is refused, and so is one the
image does not configure, before anything is installed. An identifier whose repository is already in the requested state
is accepted. Neither option creates, edits, or removes a repository file, and the image enables the same repositories
after the feature as before it.

Controls apply separately on each invocation; disabling optional dependencies does not remove installed packages.
Invalid controls fail even with an empty list. Native hooks can remove downloaded packages independently of cleanup.

## Native behavior

DNF decides version resolution using the image's configuration and `best`; a pin can downgrade a package and its
dependencies. DNF5 may resolve a program name where DNF4 does not. `refreshPolicy=default` follows the image's native
refresh and `skip_if_unavailable` settings. With `always`, every enabled repository must refresh successfully. With
`never`, DNF uses cache-only mode: both metadata and package files must already be cached.

DNF may import the signing key named by an enabled repository on first use. The feature does not pin that key; a remote
HTTPS key relies on TLS, and an HTTP key has no transport protection. Import third-party keys in your Dockerfile only
after checking their fingerprints. Images with only microdnf are not supported.

## Inherited configuration

The behavior described here was observed with DNF 4.14.0 on AlmaLinux 9 and Rocky Linux 9 and with DNF5 5.4.3 on
Fedora 44.

### What the feature sets explicitly

Every setting is an argument of the feature's one `dnf install` call: the weak-dependency selection, and, only when the
option is set, the refresh policy, the network timeout, `best`, the repositories to enable or leave out, and the bound
of simultaneous downloads. The feature writes no DNF configuration file and sets no environment variable for DNF.

### What is inherited

Everything else comes from the image's DNF configuration and from the environment of the image build: the repositories
and their URLs, signature and TLS settings, mirror selection, the limit of downloads per mirror, download speed limits,
and repository variables. A variable `DNF_VAR_<name>` in the environment reaches `$<name>` in a repository file; names
are case-sensitive. Where a variable is set both in the environment and in a file under the image's `vars` directory,
DNF 4.14 used the file and DNF5 5.4.3 the environment, and the tested AlmaLinux and Rocky Linux images ship such files.
`DNF_VAR_releasever` replaced `$releasever` on both. `DNF_VAR_basearch` was ignored by DNF 4.14 and honored by DNF5
5.4.3. The feature sets, changes, and unsets none of these variables.

### Proxy

The feature has no proxy option and passes no proxy setting. A `proxy` in the image's DNF configuration wins over the
environment. Without one, DNF follows curl's variables: for HTTP URLs lower-case `http_proxy` and `all_proxy` (not
upper-case `HTTP_PROXY`), for HTTPS URLs `https_proxy` or `HTTPS_PROXY`, and `no_proxy` exempts hosts from both. An
empty `proxy=` in a repository's configuration cancels a proxy of the main configuration, but not one from the
environment. Proxy credentials and `proxy_sslverify` were not tested.

### Locks and retries

The feature has no option for retries and none for lock waiting, because DNF offers no bounded form of either on the
tested versions. Its `retries` setting changed nothing in the measured case, a repository answering HTTP 503 from a
single URL: DNF requested the file four times under every value, and the value 0 is documented as "forever". When
another process holds DNF's lock, DNF 4.14 waits without limit, and DNF5 5.4.3 waits without limit for the system
repository lock; the switches that exist either fail at once or skip the lock's protection. DNF's own behavior therefore
applies unchanged.

## Security and repeated installation

The devcontainer CLI evaluates option values in a shell before the feature runs. Never put untrusted text in options.
The feature keeps the image's signature and TLS configuration; repositories the image explicitly leaves unchecked stay
unchecked. `enableRepositories` lets a `devcontainer.json` install from a repository the image's author configured and
left disabled, for example a testing repository, one whose signature check is turned off, or one that names a remote
key; review the identifiers it lists as you would review a repository file. DNF's own messages go to the build log
unfiltered: on both tested versions a failed download printed the repository's URL in full, credentials included, and a
proxy URL deserves the same care. Keep credentials in DNF's `username` and `password` settings or in build secrets, not
in a URL; a repository enabled for an invocation is covered by this too. Installed packages may themselves ship
configuration or keys. A second invocation uses its own list and controls, retaining earlier packages except where
native resolution replaces them: a repository the first invocation enabled or left out, its `best` value, and its
download bound do not carry over, and a package installed from a temporarily enabled repository stays installed.

## OS support

Tested images and architectures: [compatibility.json](../../test/dnf-packages/compatibility.json).
