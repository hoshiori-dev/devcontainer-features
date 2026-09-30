# shellcheck shell=sh
# Sourced by the glab test scripts. A POSIX stand-in for dev-container-features-test-lib with the
# same check / reportResults interface: that library uses bash arrays, which BusyBox ash cannot
# parse, and alpine:3.24 ships no bash.

FAILED=""

# check <label> <command> [args...]: runs the command and records the label when it fails.
check() {
  label=$1
  shift
  echo "Testing '$label'"
  if "$@"; then
    echo "Passed '$label'"
  else
    echo "FAILED '$label'" >&2
    FAILED="$FAILED
  - $label"
  fi
}

reportResults() {
  if [ -n "$FAILED" ]; then
    echo "Failed tests:$FAILED" >&2
    exit 1
  fi
  echo "Test Passed!"
  exit 0
}

# Runs a command as root: directly when already root, else through passwordless sudo.
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@"; else sudo -n "$@"; fi
}

# Runs glab without an update check or telemetry, so tests contact no host through glab.
glab_quiet() {
  GLAB_CHECK_UPDATE=false CHECK_UPDATE=false GLAB_SEND_TELEMETRY=false glab "$@"
}

# Prints the version `glab --version` reports, in either output format glab has used since 1.47.0.
installed_version() {
  glab_quiet --version 2>/dev/null \
    | sed -n -e 's/^glab \([0-9][0-9.]*\) (.*/\1/p' \
      -e 's/^Current glab version: \([0-9][0-9.]*\).*/\1/p' \
    | head -n 1
}

# Prints the version the latest-release permanent link names now, without following it.
latest_version() {
  location=$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --head \
    --output /dev/null --write-out '%{redirect_url}' \
    https://gitlab.com/gitlab-org/cli/-/releases/permalink/latest) \
    || return 1
  tag=${location##*/}
  printf '%s\n' "${tag#v}"
}

equals() {
  echo "  got '$1', expected '$2'"
  [ -n "$2" ] && [ "$1" = "$2" ]
}

# `command -v glab` names /usr/local/bin/glab, or the same file through a directory symlink: on
# fedora:44, /usr/local/sbin links to bin and comes first on PATH, so it prints /usr/local/sbin/glab.
glab_resolves_to_usr_local_bin() {
  found=$(command -v glab) || return 1
  echo "  command -v glab: $found"
  [ "$(cd -P "${found%/*}" && pwd)/${found##*/}" = /usr/local/bin/glab ]
}

# No glab configuration directory in the remote user's or root's home.
no_glab_config() {
  [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/glab-cli" ] && [ ! -e "$HOME/.config/glab-cli" ] \
    && as_root test ! -e /root/.config/glab-cli
}

no_token_variables() {
  [ -z "${GITLAB_TOKEN+set}" ] && [ -z "${GITLAB_ACCESS_TOKEN+set}" ] && [ -z "${OAUTH_TOKEN+set}" ]
}

# No file under the package-manager caches the feature cleans, whichever exist.
package_caches_empty() {
  for dir in /var/lib/apt/lists /var/cache/libdnf5 /var/cache/apk; do
    if [ -d "$dir" ] && [ -n "$(as_root find "$dir" -type f | head -n 1)" ]; then
      echo "  files remain under $dir"
      return 1
    fi
  done
}

# No temporary directory or staged binary of install.sh remains.
no_install_leftovers() {
  for path in /tmp/glab-feature.* /usr/local/bin/.glab-feature.*; do
    if [ -e "$path" ]; then
      echo "  leftover: $path"
      return 1
    fi
  done
}

# /usr/local/bin holds no file other than glab whose name contains "glab".
only_one_glab() {
  for path in /usr/local/bin/*glab* /usr/local/bin/.*glab*; do
    if [ -e "$path" ] && [ "$path" != /usr/local/bin/glab ]; then
      echo "  other file: $path"
      return 1
    fi
  done
  [ -f /usr/local/bin/glab ]
}
