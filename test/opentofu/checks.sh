# shellcheck shell=sh
# A POSIX stand-in for dev-container-features-test-lib, which is bash: the same check and reportResults interface,
# plus the assertions the opentofu tests share.

failed=""

# Runs a command and records the label when it fails: check <label> <command> [args...].
check() {
  check_label=$1
  shift
  printf "Testing '%s'\n" "${check_label}"
  if "$@"; then
    printf "Passed '%s'\n" "${check_label}"
  else
    printf "FAILED '%s'\n" "${check_label}" >&2
    failed="${failed}
  - ${check_label}"
  fi
}

# Lists the failed labels and exits 1, or exits 0 when every check passed. The camelCase name is the library's.
reportResults() {
  if [ -n "${failed}" ]; then
    printf 'Failed tests:%s\n' "${failed}" >&2
    exit 1
  fi
  echo "Test Passed!"
  exit 0
}

# Runs a command as root: directly when already root, else through passwordless sudo.
as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# Prints the release the latest-release link redirects to when called, parsed as install.sh parses it, without the
# leading "v"; a release between build and test fails the comparison once.
latest_release() {
  latest_release_location="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 \
    --head --output /dev/null --write-out '%{redirect_url}' https://github.com/opentofu/opentofu/releases/latest)" \
    || return 1
  case "${latest_release_location}" in
    https://github.com/opentofu/opentofu/releases/tag/v*) ;;
    *)
      printf 'unexpected latest-release redirect: %s\n' "${latest_release_location}" >&2
      return 1
      ;;
  esac
  latest_release_tag="${latest_release_location#https://github.com/opentofu/opentofu/releases/tag/v}"
  latest_release_tag="${latest_release_tag%%[?#]*}"
  printf '%s\n' "${latest_release_tag%/}"
}

# Runs tofu with HOME in a new temporary directory, so a check leaves no ~/.terraform.d behind.
isolated_tofu() {
  isolated_tofu_dir="$(mktemp -d)" || return 1
  isolated_tofu_status=0
  env HOME="${isolated_tofu_dir}" tofu "$@" || isolated_tofu_status=$?
  rm -rf "${isolated_tofu_dir}"
  return "${isolated_tofu_status}"
}

# The first line of `tofu version` is exactly "OpenTofu v$1".
tofu_reports_version() {
  tofu_reports_version_output="$(isolated_tofu version)" || return 1
  tofu_reports_version_first="$(printf '%s\n' "${tofu_reports_version_output}" | sed -n 1p)"
  printf "  got '%s', expected 'OpenTofu v%s'\n" "${tofu_reports_version_first}" "$1"
  [ "${tofu_reports_version_first}" = "OpenTofu v$1" ]
}

# `command -v tofu` names /usr/local/bin/tofu, or the same file through a directory symlink: on fedora:44 and
# archlinux:latest, /usr/local/sbin links to bin and comes first on PATH.
tofu_resolves_to_usr_local_bin() {
  tofu_resolves_found="$(command -v tofu)" || return 1
  printf '  command -v tofu: %s\n' "${tofu_resolves_found}"
  tofu_resolves_dir="$(cd -P "${tofu_resolves_found%/*}" && pwd)" || return 1
  [ "${tofu_resolves_dir}/${tofu_resolves_found##*/}" = "/usr/local/bin/tofu" ]
}

# A script that prints every file (not directory) under directory $1, one per line, run through as_root: apt's
# lists/partial is readable by root only, and opensuse/leap:16.0 has no find.
# shellcheck disable=SC2016 # Expanded by the shell that runs the script.
readonly FILES_UNDER='files_under() {
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    if [ -d "${entry}" ] && [ ! -L "${entry}" ]; then
      files_under "${entry}"
    elif [ -e "${entry}" ] || [ -L "${entry}" ]; then
      printf "%s\n" "${entry}"
    fi
  done
}
files_under "$1"'

# No package index or downloaded package remains in the package-manager caches of any family, whichever of them the
# image has. apt's lists, pacman's sync databases and package cache, and apk's cache hold nothing else, so any file
# counts there. dnf and zypper keep bookkeeping files after a clean (AlmaLinux 9's dnf keeps packages.db), so only
# repository metadata and packages count there. None of the compatibility images holds one before the install.
package_caches_clean() {
  for package_caches_dir in /var/lib/apt/lists /var/lib/pacman/sync /var/cache/pacman/pkg /var/cache/apk \
    /var/cache/dnf /var/cache/libdnf5 /var/cache/zypp; do
    if [ ! -d "${package_caches_dir}" ]; then continue; fi
    package_caches_files="$(as_root sh -c "${FILES_UNDER}" sh "${package_caches_dir}")" || return 1
    case "${package_caches_dir}" in
      */dnf | */libdnf5 | */zypp)
        package_caches_files="$(printf '%s\n' "${package_caches_files}" \
          | grep -E '/repodata/|/raw/|/solv/|repomd\.xml$|\.rpm$|\.solvx?$|/solv$' || true)"
        ;;
    esac
    if [ -n "${package_caches_files}" ]; then
      printf '  remaining under %s:\n%s\n' "${package_caches_dir}" "${package_caches_files}"
      return 1
    fi
  done
}

# No temporary directory or staged file of install.sh remains, in the temporary directory or beside the target.
no_install_leftovers() {
  for no_install_leftovers_path in \
    /tmp/opentofu-feature.* "${TMPDIR:-/tmp}"/opentofu-feature.* /usr/local/bin/.opentofu-feature.*; do
    if as_root test -e "${no_install_leftovers_path}"; then
      printf '  leftover: %s\n' "${no_install_leftovers_path}"
      return 1
    fi
  done
}
