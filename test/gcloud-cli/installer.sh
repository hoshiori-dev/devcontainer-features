# shellcheck shell=bash
# Shared helpers for gcloud-cli scenario scripts that invoke install.sh directly.

INSTALLER="$(dirname "$0")/_feature/install.sh"
readonly INSTALLER

install_status=0
install_output=""

as_root() {
  if (($(id -u) == 0)); then
    "$@"
  else
    sudo "$@"
  fi
}

run_install() {
  install_status=0
  install_output="$(
    as_root env _REMOTE_USER="$(id -un)" _REMOTE_USER_HOME="${HOME}" "$@" bash "${INSTALLER}" 2>&1
  )" || install_status=$?
}

failed_with() {
  if [[ "${install_status}" -eq 0 || "${install_output}" != *"gcloud-cli: error: $1"* ]]; then
    printf 'install.sh exited with %s:\n%s\n' "${install_status}" "${install_output}" >&2
    return 1
  fi
}

succeeded() {
  if [[ "${install_status}" -ne 0 || "${install_output}" != *"${1-}"* ]]; then
    printf 'install.sh exited with %s:\n%s\n' "${install_status}" "${install_output}" >&2
    return 1
  fi
}

output_contains() {
  if [[ "${install_output}" != *"$1"* ]]; then
    printf 'expected output to contain %s:\n%s\n' "$1" "${install_output}" >&2
    return 1
  fi
}
