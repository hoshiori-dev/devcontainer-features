#!/bin/sh
# Scenario: act installed with defaultImage "medium" on mcr.microsoft.com/devcontainers/base:ubuntu24.04, as the
# non-root remote user vscode. POSIX sh, as every act test: alpine:3.24 ships no bash.
set -eu

# The path is computed from $0 at run time, so shellcheck cannot follow it.
# shellcheck source=/dev/null
. "$(dirname "$0")/checks.sh"

config="${HOME}/.config/act/actrc"

# The file and every directory the install created on its path belong to the remote user. The image has no
# ~/.config, so the install created both directories.
config_owned_by_remote_user() {
  for config_owned_path in "${HOME}/.config" "${HOME}/.config/act" "${config}"; do
    config_owned_owner="$(stat -c '%U' "${config_owned_path}")" || return 1
    if [ "${config_owned_owner}" != "$(id -un)" ]; then
      printf '  %s belongs to %s\n' "${config_owned_path}" "${config_owned_owner}"
      return 1
    fi
  done
  config_owned_mode="$(stat -c '%a' "${config}")" || return 1
  printf '  mode of %s: %s\n' "${config}" "${config_owned_mode}"
  [ "${config_owned_mode}" = "644" ]
}
check "the configuration file and its new directories belong to the remote user, the file with mode 0644" \
  config_owned_by_remote_user
check "the configuration file holds exactly the medium lines" config_holds_lines "${config}" act

# Stdin from /dev/null stands for a run without a terminal. Without a Docker Engine the dry run still fails when it
# sets up the job, after the point where act would have prompted, so the exit status is not asserted.
dry_run_does_not_prompt() {
  dry_run_dir="$(make_workflow_dir)" || return 1
  cd "${dry_run_dir}" || return 1
  dry_run_output="$(act --dryrun </dev/null 2>&1 || true)"
  cd - >/dev/null || return 1
  printf '%s\n' "${dry_run_output}" | tail -n 3
  if printf '%s\n' "${dry_run_output}" | grep -q -e 'Please choose the default image' -e 'level=fatal msg=EOF'; then
    return 1
  fi
}
check "act --dryrun without a terminal does not show the default-image prompt" dry_run_does_not_prompt

reportResults
