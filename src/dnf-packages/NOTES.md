## Usage

Use `packages` for a comma-separated list of native package names, version pins, or architecture qualifiers. Empty lists
install nothing. Entries are validated before any package-manager command; paths, RPM files, options, patterns, and
shell characters are refused. The feature uses the image's existing repositories, trusted keys, and verification
settings.

Examples: `bc,file`, `file-5.46-6.fc44` (an offered version-release), `bc.x86_64` (an architecture qualifier), or
`libz.so.1` (a native capability). Pins must name an edition offered by the enabled repositories.

## Installation controls

`installWeakDeps` (default `false`): Include optional dependencies during native package resolution.

`refreshPolicy` (default `default`): Select native default refresh, check every repository, or require cached metadata
without refreshing.

`cleanup` (default `all`): Remove all managed caches, package files only, or skip feature cleanup. Image hooks and
native retention settings may remove downloaded packages even when feature cleanup is disabled.

`networkTimeout` (default ``): Native network timeout in seconds (1–3600), or empty to inherit image settings; applies
only to this invocation.

Controls apply separately on each invocation; disabling optional dependencies does not remove installed packages.
Invalid controls fail even with an empty list. Native hooks can remove downloaded packages independently of cleanup.

## Native behavior

DNF decides version resolution using the image's configuration; a pin can downgrade a package and its dependencies. DNF5
may resolve a program name where DNF4 does not. `refreshPolicy=default` follows the image's native refresh and
`skip_if_unavailable` settings. With `always`, every enabled repository must refresh successfully. With `never`, DNF
uses cache-only mode: both metadata and package files must already be cached.

DNF may import the signing key named by an enabled repository on first use. The feature does not pin that key; a remote
HTTPS key relies on TLS, and an HTTP key has no transport protection. Import third-party keys in your Dockerfile only
after checking their fingerprints. Images with only microdnf are not supported.

## Security and repeated installation

The devcontainer CLI evaluates option values in a shell before the feature runs. Never put untrusted text in options.
The feature keeps the image's signature and TLS configuration; repositories the image explicitly leaves unchecked stay
unchecked. Installed packages may themselves ship configuration or keys. A second invocation uses its own list and
controls, retaining earlier packages except where native resolution replaces them.

## OS support

Tested images and architectures: [compatibility.json](../../test/dnf-packages/compatibility.json).
