# shellcheck shell=sh
# A POSIX stand-in for dev-container-features-test-lib, which is bash: the same check and reportResults interface,
# plus the assertions the rclone tests share.

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

readonly RCLONE_COMPLETIONS="/usr/local/share/bash-completion/completions/rclone
/usr/local/share/zsh/site-functions/_rclone
/usr/share/fish/vendor_completions.d/rclone.fish"

# Runs a command as root: directly when already root, else through passwordless sudo.
as_root() {
  if [ "$(id -u)" = "0" ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

# Prints the release the version file names when called, read as install.sh reads it, without the leading "v"; a
# release between build and test fails the comparison once.
latest_release() {
  latest_release_text="$(curl --proto '=https' --fail --silent --show-error --retry 3 \
    https://downloads.rclone.org/version.txt)" || return 1
  case "${latest_release_text}" in
    "rclone v"*) printf '%s\n' "${latest_release_text#rclone v}" ;;
    *)
      printf 'unexpected version file: %s\n' "${latest_release_text}" >&2
      return 1
      ;;
  esac
}

# Runs rclone with every home and configuration path in a new temporary directory, so a check leaves nothing behind.
isolated_rclone() {
  isolated_rclone_dir="$(mktemp -d)" || return 1
  isolated_rclone_status=0
  env HOME="${isolated_rclone_dir}" XDG_CONFIG_HOME="${isolated_rclone_dir}/.config" \
    XDG_CACHE_HOME="${isolated_rclone_dir}/.cache" RCLONE_CONFIG="${isolated_rclone_dir}/rclone.conf" \
    rclone "$@" || isolated_rclone_status=$?
  rm -rf "${isolated_rclone_dir}"
  return "${isolated_rclone_status}"
}

# The first line of `rclone version` is exactly "rclone v$1".
rclone_reports_version() {
  rclone_reports_version_output="$(isolated_rclone version)" || return 1
  rclone_reports_version_first="$(printf '%s\n' "${rclone_reports_version_output}" | sed -n 1p)"
  printf "  got '%s', expected 'rclone v%s'\n" "${rclone_reports_version_first}" "$1"
  [ "${rclone_reports_version_first}" = "rclone v$1" ]
}

# `command -v rclone` names /usr/local/bin/rclone, or the same file through a directory symlink: on fedora:44,
# /usr/local/sbin links to bin and comes first on PATH.
rclone_resolves_to_usr_local_bin() {
  rclone_resolves_found="$(command -v rclone)" || return 1
  printf '  command -v rclone: %s\n' "${rclone_resolves_found}"
  rclone_resolves_dir="$(cd -P "${rclone_resolves_found%/*}" && pwd)" || return 1
  [ "${rclone_resolves_dir}/${rclone_resolves_found##*/}" = "/usr/local/bin/rclone" ]
}

# Neither the remote user's nor root's home holds rclone's configuration or cache locations, or a .gnupg directory;
# none of the compatibility images has one before the install. Other names holding "rclone" are not rclone's: the
# Ubuntu base image ships oh-my-zsh's rclone plugin.
no_rclone_files_in_homes() {
  for no_rclone_files_home in "${HOME}" /root; do
    for no_rclone_files_path in .config/rclone .cache/rclone .rclone.conf .gnupg; do
      if as_root test -e "${no_rclone_files_home}/${no_rclone_files_path}"; then
        printf '  found: %s/%s\n' "${no_rclone_files_home}" "${no_rclone_files_path}"
        return 1
      fi
    done
  done
}

# No environment variable whose name starts with RCLONE_ is set.
no_rclone_variables() {
  no_rclone_variables_set="$(env | grep '^RCLONE_' || true)"
  if [ -n "${no_rclone_variables_set}" ]; then
    printf '  set: %s\n' "${no_rclone_variables_set}"
    return 1
  fi
}

# Files $1 and $2 have the same content. Compared by digest: cmp and diff are missing from some images.
same_content() {
  same_content_a="$(sha256sum <"$1")" || return 1
  same_content_b="$(sha256sum <"$2")" || return 1
  [ "${same_content_a}" = "${same_content_b}" ]
}

# Each completion file is a regular file owned by root, readable by every user, and equal to what the installed
# rclone prints for its shell.
completions_match() {
  for completions_match_path in ${RCLONE_COMPLETIONS}; do
    case "${completions_match_path}" in
      */bash-completion/*) completions_match_shell=bash ;;
      */zsh/*) completions_match_shell=zsh ;;
      *) completions_match_shell=fish ;;
    esac
    if [ ! -f "${completions_match_path}" ] || [ -L "${completions_match_path}" ]; then
      printf '  not a regular file: %s\n' "${completions_match_path}"
      return 1
    fi
    completions_match_mode="$(stat -c '%a %U' "${completions_match_path}")" || return 1
    if [ "${completions_match_mode}" != "644 root" ]; then
      printf '  %s has mode and owner %s, expected 644 root\n' "${completions_match_path}" "${completions_match_mode}"
      return 1
    fi
    completions_match_expected="$(mktemp)" || return 1
    isolated_rclone completion "${completions_match_shell}" - >"${completions_match_expected}" || return 1
    if ! same_content "${completions_match_expected}" "${completions_match_path}"; then
      printf '  %s differs from rclone completion %s -\n' "${completions_match_path}" "${completions_match_shell}"
      rm -f "${completions_match_expected}"
      return 1
    fi
    rm -f "${completions_match_expected}"
  done
}

# `fusermount3` resolves on PATH, owned by root with the set-user-ID bit.
fusermount3_setuid_on_path() {
  fusermount3_found="$(command -v fusermount3)" || {
    echo '  fusermount3 is not on PATH'
    return 1
  }
  fusermount3_mode="$(stat -L -c '%A %U' "${fusermount3_found}")" || return 1
  printf '  %s: %s\n' "${fusermount3_found}" "${fusermount3_mode}"
  case "${fusermount3_mode}" in
    ???s*' root') ;;
    *) return 1 ;;
  esac
}

# No file under apt's package lists, dnf's cache, or apk's cache, whichever of them the image has.
package_caches_empty() {
  for package_caches_empty_dir in /var/lib/apt/lists /var/cache/libdnf5 /var/cache/apk; do
    if [ ! -d "${package_caches_empty_dir}" ]; then continue; fi
    package_caches_empty_files="$(as_root find "${package_caches_empty_dir}" -type f)" || return 1
    if [ -n "${package_caches_empty_files}" ]; then
      printf '  files remain under %s:\n%s\n' "${package_caches_empty_dir}" "${package_caches_empty_files}"
      return 1
    fi
  done
}

# No temporary directory or staged file of install.sh remains, in the temporary directory or beside a target.
no_install_leftovers() {
  for no_install_leftovers_path in \
    /tmp/rclone-feature.* "${TMPDIR:-/tmp}"/rclone-feature.* /usr/local/bin/.rclone-feature.* \
    /usr/local/share/bash-completion/completions/.rclone-feature.* \
    /usr/local/share/zsh/site-functions/.rclone-feature.* /usr/share/fish/vendor_completions.d/.rclone-feature.*; do
    if as_root test -e "${no_install_leftovers_path}"; then
      printf '  leftover: %s\n' "${no_install_leftovers_path}"
      return 1
    fi
  done
}
