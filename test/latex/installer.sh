# shellcheck shell=bash
# Runs the staged feature as root while preserving its intended target user.
run_installer() {
  local target_user
  local target_home
  target_user="$(id -un)"
  target_home="${HOME}"
  if [[ "${target_user}" == root ]]; then
    env _REMOTE_USER="${target_user}" _REMOTE_USER_HOME="${target_home}" "$@" bash ./_feature/install.sh
  else
    sudo env _REMOTE_USER="${target_user}" _REMOTE_USER_HOME="${target_home}" "$@" bash ./_feature/install.sh
  fi
}
