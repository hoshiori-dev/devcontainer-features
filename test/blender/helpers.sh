# shellcheck shell=bash
# Assertions and the installer run shared by the blender tests. Sourced after dev-container-features-test-lib; each
# function returns non-zero on failure and says why on stderr, so `check "<label>" <function> ...` reports it.

readonly RELEASE_URL="https://download.blender.org/release/"
readonly TREE="/opt/blender"
readonly LINK="/usr/local/bin/blender"
# Every Blender run is bounded: Blender 4.5 hangs in background mode on an unknown engine id.
readonly LIMIT=600

test_dir="${test_dir-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SCRATCH="$(mktemp -d)"
readonly SCRATCH

# Prints the newest release that the listings name with both its Linux x64 archive and its checksum file, in series $1
# or, without $1, in any series of 4.2 or later. Computed when the test runs: the newest release changes upstream.
newest_release() {
  local series="${1-}"
  local listing
  local candidate
  local release
  if [[ -z "${series}" ]]; then
    while IFS= read -r candidate; do
      if release="$(newest_release "${candidate}")"; then
        printf '%s\n' "${release}"
        return
      fi
    done < <(curl -fsS "${RELEASE_URL}" | grep -oE 'href="Blender[0-9]+\.[0-9]+/"' | grep -oE '[0-9]+\.[0-9]+' \
      | sort -V -r | awk -F. '$1 > 4 || ($1 == 4 && $2 >= 2)')
    return 1
  fi
  listing="$(curl -fsS "${RELEASE_URL}Blender${series}/")"
  while IFS= read -r release; do
    if grep -qF "href=\"blender-${release}.sha256\"" <<<"${listing}"; then
      printf '%s\n' "${release}"
      return
    fi
  done < <(grep -oE "href=\"blender-${series//./\\.}\.[0-9]+-linux-x64\.tar\.xz\"" <<<"${listing}" \
    | grep -oE "${series//./\\.}\.[0-9]+" | sort -V -r)
  return 1
}

# Succeeds when blender, run through the command prefix in the remaining arguments (such as `sudo -n`), reports
# release $1 on the first line of its version output.
reports_release() {
  local release="$1"
  local output
  local first_line
  shift
  output="$("$@" timeout "${LIMIT}" blender --version)" || return
  first_line="${output%%$'\n'*}"
  [[ "${first_line}" =~ ^Blender\ ${release//./\\.}(\ |$) ]] || {
    printf 'blender reports "%s", expected %s\n' "${first_line}" "${release}" >&2
    return 1
  }
}

# Renders frame 1 of the factory startup scene with engine $1 in background mode at 64x48 and checks the image; the
# remaining arguments are a command prefix such as `sudo -n`.
renders_frame() {
  local engine="$1"
  local out="${SCRATCH}/render_${engine}_$#"
  shift
  mkdir -p "${out}"
  cat >"${out}/small.py" <<'PY'
import bpy

scene = bpy.context.scene
scene.render.resolution_x = 64
scene.render.resolution_y = 48
scene.render.resolution_percentage = 100
scene.cycles.samples = 4
scene.eevee.taa_render_samples = 1
PY
  "$@" timeout "${LIMIT}" blender -b --factory-startup -E "${engine}" --python-exit-code 1 --python "${out}/small.py" \
    -o "${out}/frame_####" -F PNG -f 1 >"${out}/log" 2>&1 || {
    cat "${out}/log" >&2
    return 1
  }
  [[ -s "${out}/frame_0001.png" ]] || {
    printf 'no image at %s\n' "${out}/frame_0001.png" >&2
    cat "${out}/log" >&2
    return 1
  }
}

# Runs script $1 in background mode with factory settings and prints Blender's exit status.
script_status() {
  local status=0
  timeout "${LIMIT}" blender -b --factory-startup --python-exit-code 1 --python "$1" >"${SCRATCH}/script.log" 2>&1 \
    || status=$?
  printf '%s\n' "${status}"
}

# Succeeds when a succeeding script makes Blender exit 0 and a raising one makes it exit 1.
script_status_follows_script() {
  printf 'print("ok")\n' >"${SCRATCH}/ok.py"
  printf 'raise RuntimeError("expected failure")\n' >"${SCRATCH}/raise.py"
  [[ "$(script_status "${SCRATCH}/ok.py")" == 0 && "$(script_status "${SCRATCH}/raise.py")" == 1 ]]
}

# Prints the type, mode, owner, size, mtime, and path of every entry of the tree, sorted.
tree_manifest() {
  find "${TREE}" -printf '%y %m %u %s %T@ %p\n' | sort
}

# Succeeds when /usr/local/bin/blender is a link to the executable in the tree.
link_targets_executable() {
  [[ -L "${LINK}" && "$(readlink "${LINK}")" == "${TREE}/blender" ]]
}

# Succeeds when root owns every entry of the tree and no entry but a link is writable by group or others.
tree_is_root_only() {
  ! find "${TREE}" \( ! -user 0 -o \( ! -type l -perm /022 \) \) -print -quit | grep -q .
}

# Writes a minimal extension source named $2 into directory $1.
make_extension() {
  mkdir -p "$1"
  cat >"$1/blender_manifest.toml" <<TOML
schema_version = "1.0.0"
id = "$2"
version = "1.0.0"
name = "Probe Extension"
tagline = "Extension used by the blender feature tests"
maintainer = "Blender feature tests"
type = "add-on"
blender_version_min = "4.2.0"
license = ["SPDX:GPL-3.0-or-later"]
TOML
  cat >"$1/__init__.py" <<'PY'
def register():
    pass


def unregister():
    pass
PY
}

# Succeeds when Blender validates the extension source in $1.
validates_extension() {
  timeout "${LIMIT}" blender -b --factory-startup -c extension validate "$1" >"${SCRATCH}/validate.log" 2>&1 || {
    cat "${SCRATCH}/validate.log" >&2
    return 1
  }
}

# Runs the copied installer as root with VERSION $1 and, when given, _REMOTE_USER $2, taking curl and other commands
# from the fixture's bin directory; keeps the output in ${FIXTURE_DIR}/output and shows it.
run_installer() {
  local status=0
  env PATH="${FIXTURE_DIR}/bin:${PATH}" FIXTURE_DIR="${FIXTURE_DIR}" VERSION="$1" _REMOTE_USER="${2-}" \
    bash "${test_dir}/_feature/install.sh" >"${FIXTURE_DIR}/output" 2>&1 || status=$?
  cat "${FIXTURE_DIR}/output"
  return "${status}"
}
