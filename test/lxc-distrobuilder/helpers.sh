# shellcheck shell=bash
# Assertions shared by the lxc-distrobuilder tests. Sourced by test.sh, duplicate.sh, and the scenario scripts after
# dev-container-features-test-lib; each function returns non-zero on failure.

readonly DB_TARGET="/usr/local/bin/distrobuilder"
readonly DB_VERSION_FILE="/usr/local/share/lxc-distrobuilder/version"
readonly DB_LATEST_URL="https://github.com/lxc/distrobuilder/releases/latest"

# Runs a command as root: the tests run as the image's remote user, which may be a sudoer.
as_root() {
  local uid
  uid="$(id -u)"
  if ((uid == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

# Runs the installer of this checkout as root with only the given NAME=value options in its environment; prints its
# output and returns its status.
run_installer() {
  as_root env -i PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" HOME=/root "$@" \
    bash "$(dirname "$0")/_feature/install.sh" 2>&1
}

# Prints the release the latest-release link redirects to, without its leading "v".
latest_release() {
  local location
  location="$(curl --fail --silent --head --output /dev/null --write-out '%{redirect_url}' "${DB_LATEST_URL}")" \
    || return
  location="${location##*/tag/}"
  printf '%s\n' "${location#v}"
}

# The version distrobuilder prints as root equals $1 and the recorded release.
reports_version() {
  local printed recorded
  printed="$(as_root "${DB_TARGET}" --version)" || return
  recorded="$(cat "${DB_VERSION_FILE}")" || return
  printf '  printed: %s; recorded: %s; expected: %s\n' "${printed}" "${recorded}" "$1"
  [[ "${printed}" == "$1" && "${recorded}" == "$1" ]]
}

# Every command named is on root's PATH.
on_root_path() {
  local name
  for name in "$@"; do
    as_root sh -c "command -v ${name}" >/dev/null || {
      printf '  missing: %s\n' "${name}"
      return 1
    }
  done
}

# None of the commands named is on root's PATH.
not_on_root_path() {
  local name
  for name in "$@"; do
    if as_root sh -c "command -v ${name}" >/dev/null; then
      printf '  present: %s\n' "${name}"
      return 1
    fi
  done
}

# The container holds CAP_SYS_ADMIN (bit 21 of PID 1's effective capabilities) and is not privileged: it lacks
# CAP_SYS_MODULE (bit 16), which Docker grants only to a privileged container.
holds_sys_admin_only() {
  local caps
  caps="$(sed -n 's/^CapEff:[[:space:]]*//p' /proc/1/status)"
  (((16#${caps} >> 21) & 1)) && ! (((16#${caps} >> 16) & 1))
}

# PID 1 runs without an AppArmor profile. Under AppArmor a confined process has a label such as
# "docker-default (enforce)" and an unconfined one "unconfined"; a kernel without AppArmor reports another module's
# label or none.
runs_without_apparmor() {
  local label
  label="$(as_root cat /proc/1/attr/current 2>/dev/null | tr -d '\0')" || return 0
  printf '  security label of PID 1: %s\n' "${label}"
  [[ "${label}" != *"(enforce)"* && "${label}" != *"(complain)"* ]]
}

# Root builds a container image from the definition beside this file: `distrobuilder build-incus` exits 0 and writes
# the image's metadata archive and its root file system.
builds_container_image() {
  local out
  out="$(mktemp -d)"
  as_root "${DB_TARGET}" build-incus "$(dirname "$0")/alpine.yaml" "${out}" || return
  ls -l "${out}"
  [[ -s "${out}/incus.tar.xz" && -s "${out}/rootfs.squashfs" ]] || return
  as_root rm -rf "${out}"
}

# Neither the remote user's home nor root's holds a GnuPG directory or a Go directory: the install keeps both in a
# temporary directory.
no_build_leftovers_in_homes() {
  [[ ! -e "${HOME}/.gnupg" && ! -e "${HOME}/go" ]] && ! as_root test -e /root/.gnupg && ! as_root test -e /root/go
}

# The install left no Go toolchain, source, or build cache: no go on PATH, none in /usr/local/go, and no temporary
# directory of the install, which held all three, in /tmp.
no_toolchain_left() {
  not_on_root_path go || return
  [[ ! -e /usr/local/go ]] || return
  ! as_root sh -c 'ls -d /tmp/tmp.*/go /tmp/tmp.*/gocache /tmp/tmp.*/source 2>/dev/null | grep .'
}
