# shellcheck shell=bash
# Sourced by the godot test scripts: the minimal project of the spec's "Headless use" requirement, and the assertions
# more than one test script uses. The scripts run as the remote user and source dev-container-features-test-lib first.

# Writes a minimal project into the new directory $1: a project.godot whose application/run/main_scene names main.tscn,
# a scene holding one node.
make_project() {
  mkdir "$1"
  cat >"$1/project.godot" <<'PROJECT'
config_version=5

[application]

config/name="Minimal"
run/main_scene="res://main.tscn"
PROJECT
  cat >"$1/main.tscn" <<'SCENE'
[gd_scene format=3]

[node name="Main" type="Node"]
SCENE
}

# `godot --version` exits 0 and prints exactly $1, ".stable.official.", and a hexadecimal commit hash.
godot_reports_version() {
  local output
  output="$(godot --version)" || return 1
  printf "  got '%s', expected '%s.stable.official.<hash>'\n" "${output}" "$1"
  [[ "${output}" == "$1.stable.official."* && "${output#"$1.stable.official."}" =~ ^[0-9a-f]+$ ]]
}

# `command -v godot` names /usr/local/bin/godot once symbolic links are followed: on fedora:44, /usr/local/sbin links
# to bin and comes first on PATH, so it prints /usr/local/sbin/godot.
godot_resolves_to_usr_local_bin() {
  local found
  local resolved
  found="$(command -v godot)" || return 1
  resolved="$(readlink -f "${found}")" || return 1
  printf '  command -v godot: %s, resolved: %s\n' "${found}" "${resolved}"
  [[ "${resolved}" == /usr/local/bin/godot ]]
}

# Prints the tag the latest-release link names when called, read as install.sh reads it, without following the
# redirect.
latest_release_tag() {
  local location
  local tag
  location="$(curl --proto '=https' --proto-redir '=https' --fail --silent --show-error --retry 3 \
    --head --output /dev/null --write-out '%{redirect_url}' \
    https://github.com/godotengine/godot/releases/latest)" || return 1
  if [[ -z "${location}" ]]; then
    echo 'the latest-release link did not redirect to a release' >&2
    return 1
  fi
  tag="${location%%[?#]*}"
  tag="${tag%/}"
  printf '%s\n' "${tag##*/}"
}

# No temporary directory, archive, or staged executable of install.sh remains in the temporary directory or in
# /usr/local/bin. Both directories are listable by every user, so the globs expand for the remote user too.
no_install_residue() {
  local path
  for path in /tmp/godot-feature.* "${TMPDIR:-/tmp}"/godot-feature.* /usr/local/bin/.godot-feature.*; do
    if [[ -e "${path}" ]]; then
      printf '  residue: %s\n' "${path}"
      return 1
    fi
  done
}
