# Shell Style

Read this before writing or editing a shell script under `src/` or `test/`, or the script templates in
`scripts/new_feature.ts`. It is the one source of shell style here and applies on its own; it adapts the Google Shell
Style Guide (https://google.github.io/styleguide/shellguide.html) to Dev Container Features. "Shipped" means a script
under `src/`, executable or library; "test" means a script under `test/`. Download, checksum, signature, and installer
rules live in `feature-authoring.md` (`install.sh` section, Downloads) and are not repeated here.

Why the rules look the way they do: a shipped script exists so that developers who configure a dev container, and
developers who use one someone else configured, can audit what it does and trust the feature author. It is not a general
tool that copes with every input. Clear logic, clear logs, and early failure help those developers fix their
configuration, and an option must never become a way to run something it does not state. A test script describes the
behavior contract to feature developers and auditors, so it is written for reading rather than for defense.

## Applying the guide

- New files follow this guide. An edit to a file that does not follow this guide yet keeps that file's existing style
  until the whole file is restyled, so no file mixes two styles.
- A restyle of a shipped script bumps the feature's version like any change under `src/<id>/` (`feature-authoring.md`,
  Versions); whether it needs an OpenSpec change follows `spec-workflow.md`.
- Mark every deliberate deviation, including each `# shellcheck disable=SCxxxx`, with a comment on the line above that
  gives the reason. Disable checks per line, never per file. Two directives need no reason:
  `# shellcheck source=/dev/null` before sourcing `/etc/os-release` or `dev-container-features-test-lib`, and
  `# shellcheck shell=bash` or `# shellcheck shell=sh` at the top of a sourced file.
- `just check` runs shellcheck on every tracked `*.sh`. `.shellcheckrc` enables the two optional checks this guide
  relies on, `require-variable-braces` and `require-double-brackets`, wherever shellcheck runs.

## Choosing bash or POSIX sh

- POSIX `sh` (`#!/bin/sh`, `set -eu`) is required when an image in the feature's compatibility list ships no bash, and
  allowed when the feature's purpose calls for broad image compatibility (the package-list installers).
- Bash (`#!/usr/bin/env bash`, `set -euo pipefail`) is recommended for every other feature: it is easier to read.
- Tests use the same pair: bash tests `set -euo pipefail`, POSIX tests `set -eu`. A POSIX test cannot source
  `dev-container-features-test-lib` (it is bash); it uses a POSIX stand-in with the same `check` / `reportResults`
  interface, as `test/glab/checks.sh` does; `just new-feature <id> --posix` generates one.
- Never install bash into a user's image to satisfy this guide.

## Layout

- Indent with two spaces. Keep lines within 120 characters; a line that holds only a long URL or path may exceed it.
- Put `; then` and `; do` on the line of `if`, `for`, `while`, and `until`; `else`, `fi`, and `done` go on their own
  lines, aligned with the opening keyword.
- When a pipeline or a `&&` / `||` list does not fit on one line, end the line with `\` and start each continuation line
  with the operator, indented two spaces.
- `case`: indent alternatives two spaces. A one-line alternative is `pattern) command ;;`; a longer one puts the
  pattern, the commands, and `;;` on separate lines. Patterns are unquoted and have no opening `(`. Use `;;` only.
- Use `cmd || fail "…"`, `cmd || return`, and `[[ … ]] || fail "…"` (`[ … ]` in POSIX) as guards; branch with `if`
  everywhere else. A one-line `if …; then …; fi` holds exactly one simple command.
- Put `|| fail` or `|| return` after one command or a function that runs one command: on a function that runs several,
  it switches `set -e` off inside that function, and a failing step in the middle goes unnoticed.
- Separate parts of a file with functions and the comment above each one, without decorative divider lines.
- Write long text with a here-document; quote its delimiter (`<<'EOF'`) unless it needs expansion.

## Names

- Functions and variables: lower snake_case. Name a loop variable after what it holds (`for package in …`).
- Upper case only for readonly constants, exported variables, and the variables that options and the Dev Container
  tooling set (`VERSION`, `_REMOTE_USER`). A mutable global is lower case.
- Shell script file names: snake_case (`test_repair_volume.sh`), test scripts included, so scenario keys in
  `scenarios.json` are snake_case too. `install.sh` and paths installed into an image keep the names the Dev Container
  spec or the feature's spec gives them.
- `TODO(#<issue>)` for a known gap, naming the issue that tracks it.

## Variables and quoting

- Brace every named variable: `${name}`. Special parameters stay unbraced: `$1`, `$@`, `$#`, `$?`, `$$`, `$!`.
- Quote every string that holds an expansion, a command substitution, a space, or a shell metacharacter. Pass arguments
  on with `"$@"`; use `$*` only to join them into one string. Assignments and `case` subjects may stay unquoted, and
  literal integers are not quoted.
- A pattern stays unquoted: a `case` pattern, and the right side of `==` or `=~` in `[[ ]]` when it is meant as a glob
  or regular expression. Quoting it makes it match literally.
- Every constant is `readonly` and defined at the top of the file. An option variable gets its default at the top and
  becomes `readonly` as soon as it is validated; one that `/etc/os-release` also assigns (in practice `VERSION`) only
  after that file has been read. When a script validates its options before it reads that file, make such a variable
  readonly in `main` after the platform step instead of inside `validate_options`.
- Give an option its default with `${NAME-default}`: an unset variable takes the default, and an explicitly empty value
  stays empty and reaches validation. Use `${NAME:-default}` only when the spec says an empty value means the default.
- Rewrite an option's value only where its spec defines an accepted alternative form (glab's leading `v`); every other
  value is either valid as given or fails.

## Functions and structure

- Define functions as `name() {` on one line, without the `function` keyword. Put all functions after the constants and
  globals; no executable code between them.
- An executable shipped script that defines a function ends with a `main` function and the line `main "$@"`. `main`
  reads as the list of steps. Every other function is a named step, a helper used in several places, or a handler that
  `trap` calls, so calls go at most `main` → step → helper, and a single-use wrapper around one command is inlined.
- When a function's name does not say everything, comment it with one sentence: what it does, what `$1`, `$2` mean, what
  it prints, and what its status means. Comment a block or command where the reason or method is not obvious; leave
  plain commands uncommented.
- A shipped script sources only two kinds of file:
  - `/etc/os-release`, always inside a subshell, because it defines variables such as `VERSION` that would overwrite
    options. Put `# shellcheck source=/dev/null` on the line above
    `os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"`. Read it before an option variable it also assigns (in
    practice `VERSION`) becomes readonly: the subshell inherits the attribute, and the file's own `VERSION=` then fails.
    For the same reason, no readonly constant takes the name of a key that file defines (`NAME`, `ID`, `VERSION_ID`).
  - Library files of its own feature under `src/<id>/`. Most features stay one file; split only when it makes a large
    feature easier to audit. A library is named `*.sh`, has no shebang, is not executable, starts with
    `# shellcheck shell=…`, defines only functions and constants, and uses the `log` and `fail` of the script that
    sources it.
- The header of `install.sh`, right after the shebang, says what is installed, from where, and to which path; that it
  runs as root at image build time and which environment variable each option arrives in; and for POSIX `sh`, why.
  Second-install behavior belongs to the spec, not the header.

### Bash

- Declare every variable used only inside a function with `local`, on its own line before any assignment from a command
  substitution, so the substitution's status is not lost: `local version` then `version="$(…)"`. A variable that a trap
  or a later step reads stays global.
- Test with `[[ … ]]`: `==` for string equality, `-z` / `-n` for empty and non-empty, `=~` for regular expressions
  (anchor them with `^` and `$`). Compare numbers with `(( … ))` or `-lt` / `-gt`, never `<` / `>` inside `[[ ]]`.
- Keep lists in arrays and expand them as `"${packages[@]}"`; append with `+=( … )`.
- Read command output line by line with process substitution (`while read -r …; do …; done < <(command)`) or
  `readarray`, so variables set in the loop survive it.

### POSIX sh

- POSIX has no `local`: prefix every variable used only inside a function with the function's full name and `_`
  (`version_at_least_a`), and those of `main` with `main_`. Globals declared at the top keep their names.
- Test with `[ … ]` and `=`; always quote both operands.
- POSIX has no `pipefail`: never let a pipeline's status decide anything. Save output to a variable or file and check
  each command.
- BusyBox tools on Alpine lack many long options; check every option against the images in the compatibility list.

## Commands

- Use `$(…)`, never backticks. Do arithmetic with `$(( … ))` and, in bash, `(( … ))`; never with `let`, `expr`, or
  `$[ … ]`. A bare `(( … ))` that evaluates to 0 fails under `set -e`, so use it only as an `if` condition.
- Prefer builtins and parameter expansion to spawning `sed`, `awk`, or `expr` for simple string work.
- Expand globs as `./*`, so a file name starting with `-` is not read as an option.
- Shipped scripts use long options (`curl --fail --silent`) wherever every target image's implementation has them.
- Give a set of arguments used more than once a function, in both dialects, for example
  `fetch() { curl --proto '=https' … "$@"; }`. Arrays hold only lists that vary, such as package names.
- Print text that contains an expansion with `printf '%s\n' "…"`; fixed text may use `echo`.
- Assign the output of a command whose failure matters to a variable before using it: in
  `log "installed $(tool --version)"` the status is `log`'s, so a failing `tool` goes unnoticed. Write
  `version="$(tool --version)"` first; a bare assignment keeps the command's status, so `set -e` stops there, while
  `local`, `readonly`, and `export` with an assignment report their own status instead.
- Shipped scripts contain no `eval`, aliases, indirect expansion (`${!name}`), command names built from variables,
  encoded blobs, or `set -x`.

## Options are data

- `main` validates every option value, and checks the platform preconditions the run relies on, before anything changes
  in the image. The spec decides the order of the checks; where it fixes none, keep the order the script has. A
  precondition the run does not need (a package manager when the package list is empty) is not checked; option values
  are always validated.
- Validate with patterns that must match the whole value: `case` in POSIX, an anchored `[[ … =~ ^…$ ]]` in bash. Avoid
  `grep` for this: it matches per line, so it lets a value with a newline through.
- An option value reaches a command only as a quoted argument; it never reaches `eval`, `sh -c`, `source`, or a script
  the feature generates. The one exception is an option that its name, its spec, and its description all present as a
  hook or configuration script; the feature logs the command before running it.
- Name the trust surface as readonly constants at the top of a shipped script: every external URL, every signing-key
  fingerprint, and every path the feature creates or modifies outside a temporary directory.

## Logging and failure

- Every executable shipped script defines `log`, writing to stdout, and `fail`, writing to stderr and exiting 1, with
  the prefix `<id>:` followed by a space; `fail` adds `error:` after it (`deno: error: …`). Start messages in lower
  case, without a trailing period or a timestamp.
- Log one line for every step that changes the image or uses the network: what it does, from where, and to where.
- Let state-changing commands print their output; send only probes such as `command -v` to `/dev/null`.
- End every step that can fail for a reason the developer can fix (a download, a verification, the package manager, an
  unsuitable option or image) with `|| fail "<reason>; <how to fix it>"`. Leave other failures to `set -e`.
- Handle known failure modes explicitly (a network interruption, a temporarily unavailable source, a known difference
  between distributions), with a comment naming the failure mode, and only within the sources and behavior the spec
  allows.
- Let unknown errors fail the build with their own message; no catch-all turns them into a half-working install.
- Fail on input outside the forms the spec accepts; never guess what the developer meant.

## Tests

- A check's label states one behavior in the words of the spec, and its command verifies exactly that behavior.
- Write expected values as literals. When one must be computed at run time (the current latest release), say why in a
  comment.
- Name a helper after the behavior it asserts; it may be defined right before the first check that uses it. A pipeline
  that fits on one line may be inlined as `check "…" bash -c '…'`; anything longer becomes a helper.
- Repeat a few lines rather than abstract across files. A shared helper file holds only assertions that several scripts
  of the same feature use.
- Tests need no `main` and may use short options. Every other rule applies, except the ones written for shipped scripts.

```bash
# The version the release pointer names when the test runs; a release between build and test fails once.
latest="$(curl --fail --silent --location https://example.com/release-latest.txt)"

check "example-tool reports the latest version" bash -c "example-tool --version | grep -qx 'example-tool ${latest}'"
check "example-tool is installed at /usr/local/bin/example-tool" test -x /usr/local/bin/example-tool
```

## Skeletons

Start an executable shipped script from the skeleton for its dialect and keep its layout: shebang, header, `set`,
constants, option defaults, mutable globals, `log` and `fail`, other functions, `main`, `main "$@"`.

### Bash

```bash
#!/usr/bin/env bash
# Installs the example-tool CLI from its upstream release archive, verified against the release's checksum file, to
# /usr/local/bin/example-tool. Runs as root at image build time; the option `version` arrives as VERSION.
set -euo pipefail

readonly RELEASES_URL="https://example.com/example-tool/releases/download"
readonly INSTALL_PATH="/usr/local/bin/example-tool"

VERSION="${VERSION-latest}"

work_dir=""

log() {
  printf 'example-tool: %s\n' "$*"
}

fail() {
  printf 'example-tool: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory on every exit, success or failure.
cleanup() {
  if [[ -n "${work_dir}" ]]; then rm --recursive --force "${work_dir}"; fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Fails unless the image is Debian or Ubuntu. Runs before VERSION becomes readonly: /etc/os-release assigns it too.
detect_platform() {
  local os_id
  [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release; use a Debian or Ubuntu image"
  # shellcheck source=/dev/null
  os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${os_id}" in
    debian | ubuntu) ;;
    *) fail "unsupported distribution \"${os_id}\"; use a Debian or Ubuntu image" ;;
  esac
}

validate_options() {
  if [[ "${VERSION}" != latest && ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "option version is \"${VERSION}\"; use \"latest\" or an exact release such as 1.2.3"
  fi
  readonly VERSION
}

install_release() {
  local base_url="${RELEASES_URL}/v${VERSION}"
  work_dir="$(mktemp --directory)"
  log "downloading ${base_url}/example-tool.tar.gz and its checksum file"
  fetch --output "${work_dir}/example-tool.tar.gz" "${base_url}/example-tool.tar.gz" \
    || fail "cannot download ${base_url}/example-tool.tar.gz; check that release ${VERSION} exists"
  fetch --output "${work_dir}/checksums.txt" "${base_url}/checksums.txt" \
    || fail "cannot download ${base_url}/checksums.txt; release ${VERSION} must publish one"
  grep ' example-tool.tar.gz$' "${work_dir}/checksums.txt" >"${work_dir}/example-tool.sha256" \
    || fail "checksums.txt of release ${VERSION} lists no example-tool.tar.gz"
  (cd "${work_dir}" && sha256sum --check --quiet example-tool.sha256) \
    || fail "example-tool.tar.gz does not match checksums.txt of release ${VERSION}"
  tar --extract --gzip --file "${work_dir}/example-tool.tar.gz" --directory "${work_dir}"
  log "installing example-tool ${VERSION} to ${INSTALL_PATH}"
  install --mode 0755 "${work_dir}/example-tool" "${INSTALL_PATH}"
}

main() {
  detect_platform
  validate_options
  trap cleanup EXIT
  install_release
}

main "$@"
```

### POSIX sh

```sh
#!/bin/sh
# Installs the example-tool CLI from its upstream release archive, verified against the release's checksum file, to
# /usr/local/bin/example-tool. Runs as root at image build time; the option `version` arrives as VERSION.
# POSIX sh, because Alpine images ship no bash.
set -eu

readonly RELEASES_URL="https://example.com/example-tool/releases/download"
readonly INSTALL_PATH="/usr/local/bin/example-tool"

VERSION="${VERSION-latest}"

work_dir=""

log() {
  printf 'example-tool: %s\n' "$*"
}

fail() {
  printf 'example-tool: error: %s\n' "$*" >&2
  exit 1
}

# Removes the download directory on every exit, success or failure.
cleanup() {
  if [ -n "${work_dir}" ]; then rm -rf "${work_dir}"; fi
}

# Runs curl with the transport rules every download in this feature needs (feature-authoring.md, install.sh).
fetch() {
  curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --location --retry 3 "$@"
}

# Fails unless the image is Alpine. Runs before VERSION becomes readonly: /etc/os-release assigns it too.
detect_platform() {
  [ -r /etc/os-release ] || fail "cannot read /etc/os-release; use an Alpine image"
  # shellcheck source=/dev/null
  detect_platform_os_id="$(. /etc/os-release && printf '%s\n' "${ID:-}")"
  case "${detect_platform_os_id}" in
    alpine) ;;
    *) fail "unsupported distribution \"${detect_platform_os_id}\"; use an Alpine image" ;;
  esac
}

validate_options() {
  validate_options_hint="use \"latest\" or an exact release such as 1.2.3"
  case "${VERSION}" in
    latest) ;;
    *[!0-9.]* | .* | *. | *..* | *.*.*.*) fail "option version is \"${VERSION}\"; ${validate_options_hint}" ;;
    *.*.*) ;;
    *) fail "option version is \"${VERSION}\"; ${validate_options_hint}" ;;
  esac
  readonly VERSION
}

install_release() {
  install_release_base_url="${RELEASES_URL}/v${VERSION}"
  work_dir="$(mktemp -d)"
  log "downloading ${install_release_base_url}/example-tool.tar.gz and its checksum file"
  fetch --output "${work_dir}/example-tool.tar.gz" "${install_release_base_url}/example-tool.tar.gz" \
    || fail "cannot download ${install_release_base_url}/example-tool.tar.gz; check that release ${VERSION} exists"
  fetch --output "${work_dir}/checksums.txt" "${install_release_base_url}/checksums.txt" \
    || fail "cannot download ${install_release_base_url}/checksums.txt; release ${VERSION} must publish one"
  grep ' example-tool.tar.gz$' "${work_dir}/checksums.txt" >"${work_dir}/example-tool.sha256" \
    || fail "checksums.txt of release ${VERSION} lists no example-tool.tar.gz"
  (cd "${work_dir}" && sha256sum -c example-tool.sha256) \
    || fail "example-tool.tar.gz does not match checksums.txt of release ${VERSION}"
  tar -xzf "${work_dir}/example-tool.tar.gz" -C "${work_dir}"
  log "installing example-tool ${VERSION} to ${INSTALL_PATH}"
  install -m 0755 "${work_dir}/example-tool" "${INSTALL_PATH}"
}

main() {
  detect_platform
  validate_options
  trap cleanup EXIT
  install_release
}

main "$@"
```
