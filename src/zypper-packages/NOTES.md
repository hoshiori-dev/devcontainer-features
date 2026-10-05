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

## Security and repeated installation

The devcontainer CLI evaluates option values in a shell before the feature runs. Never put untrusted text in options.
The feature keeps the image's signature and TLS configuration; repositories the image explicitly leaves unchecked stay
unchecked. Installed packages may themselves ship configuration or keys. A second invocation uses its own list and
controls, retaining earlier packages except where native resolution replaces them.

## OS support

Tested images and architectures: [compatibility.json](../../test/zypper-packages/compatibility.json).
