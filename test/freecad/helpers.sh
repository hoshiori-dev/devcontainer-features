# shellcheck shell=bash
# Assertions and the installer run shared by the freecad tests. Sourced after dev-container-features-test-lib; each
# function returns non-zero on failure and says why on stderr, so `check "<label>" <function> ...` reports it.

readonly RELEASES_API="https://api.github.com/repos/FreeCAD/FreeCAD/releases"
readonly LATEST_URL="https://github.com/FreeCAD/FreeCAD/releases/latest"
readonly TREE="/opt/freecad"
readonly MARKER="${TREE}/.devcontainer-feature-freecad"
readonly DISPLAY_NUMBER=":99"
# Every FreeCAD run is bounded: a GUI that meets no exit stays open.
readonly LIMIT=600

test_dir="${test_dir-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
SCRATCH="$(mktemp -d)"
# Root and the remote user both write here.
chmod 0777 "${SCRATCH}"
readonly SCRATCH

# Prints the newest stable release, of series $1 when given. Computed when the test runs: the newest release changes
# upstream. Without a series it follows the redirect of the latest-release page, which needs no API request.
newest_release() {
  local series="${1-}"
  local location
  if [[ -z "${series}" ]]; then
    location="$(curl -fsS -o /dev/null -w '%{redirect_url}' "${LATEST_URL}")"
    printf '%s\n' "${location##*/}"
    return
  fi
  curl -fsS "${RELEASES_API}?per_page=100" "${RELEASES_API}?per_page=100&page=2" \
    | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
    | grep -E "^${series//./\\.}\.[0-9]+$" | sort -V -r | head -n 1
}

# Succeeds when freecadcmd, run through the command prefix in the remaining arguments (such as `sudo -n`), reports
# release $1.
reports_release() {
  local release="$1"
  local output
  shift
  output="$("$@" timeout "${LIMIT}" freecadcmd --version)" || return
  grep -qE "^FreeCAD ${release//./\\.}( |\$)" <<<"${output}" || {
    printf 'freecadcmd reports "%s", expected %s\n' "${output}" "${release}" >&2
    return 1
  }
}

# Succeeds when the marker in the tree records release $1.
marker_records() {
  [[ "$(cat "${MARKER}")" == "$1" ]]
}

# Succeeds when /usr/local/bin holds exactly two entries with freecad in their name.
adds_two_commands() {
  local entries=(/usr/local/bin/*freecad*)
  [[ "${#entries[@]}" == 2 ]]
}

# Succeeds when the home of the user the command prefix in the arguments selects (the caller's without one) holds
# none of FreeCAD's per-user directories.
home_has_no_freecad_state() {
  local home
  home="$("$@" sh -c 'cd && pwd')"
  ! "$@" test -e "${home}/.config/FreeCAD" && ! "$@" test -e "${home}/.local/share/FreeCAD" \
    && ! "$@" test -e "${home}/.cache/FreeCAD"
}

# Succeeds when the image holds a fontconfig configuration and a DejaVu Sans font file.
fonts_are_configured() {
  local font
  font="$(find /usr/share/fonts -name 'DejaVuSans*.ttf' -print -quit)"
  [[ -r /etc/fonts/fonts.conf && -n "${font}" ]]
}

# Prints the type, mode, owner, size, mtime, and path of every entry of the tree, sorted.
tree_manifest() {
  find "${TREE}" -printf '%y %m %u %s %T@ %p\n' | sort
}

# Succeeds when /usr/local/bin/freecad and /usr/local/bin/freecadcmd are links to the launchers in the tree.
links_target_launchers() {
  local name
  for name in freecad freecadcmd; do
    [[ -L "/usr/local/bin/${name}" && "$(readlink "/usr/local/bin/${name}")" == "${TREE}/bin/${name}" ]] || return
  done
}

# Succeeds when root owns every entry of the tree and no entry but a link is writable by group or others.
tree_is_root_only() {
  ! find "${TREE}" \( ! -user 0 -o \( ! -type l -perm /022 \) \) -print -quit | grep -q .
}

# Runs a freecadcmd script that creates a solid, saves the document, exports STEP and STL, and imports the STEP file
# again; succeeds when the command exits 0, each file is non-empty, and the imported shape has the solid's volume.
# The arguments are a command prefix such as `sudo -n`.
models_and_exports() {
  local out="${SCRATCH}/model_$#"
  rm -rf "${out}"
  mkdir -p "${out}"
  chmod 0777 "${out}"
  cat >"${out}/model.py" <<'PY'
import sys

import FreeCAD
import Mesh
import Part

out = sys.argv[sys.argv.index("--pass") + 1]
doc = FreeCAD.newDocument("model")
box = doc.addObject("Part::Box", "Box")
box.Length, box.Width, box.Height = 10, 20, 30
doc.recompute()
doc.saveAs(out + "/model.FCStd")
Part.export([box], out + "/model.step")
Mesh.export([box], out + "/model.stl")
volume = Part.read(out + "/model.step").Volume
with open(out + "/volume", "w") as result:
    result.write("%.3f\n" % volume)
PY
  "$@" timeout "${LIMIT}" freecadcmd "${out}/model.py" --pass "${out}" >"${out}/log" 2>&1 || {
    cat "${out}/log" >&2
    return 1
  }
  [[ -s "${out}/model.FCStd" && -s "${out}/model.step" && -s "${out}/model.stl" ]] || {
    printf 'a model file is missing or empty in %s\n' "${out}" >&2
    cat "${out}/log" >&2
    return 1
  }
  [[ "$(cat "${out}/volume")" == 6000.000 ]] || {
    printf 'the imported STEP shape has volume "%s", expected 6000.000\n' "$(cat "${out}/volume")" >&2
    return 1
  }
}

# Succeeds when a freecadcmd script ending in sys.exit(3) makes the command exit 3.
exit_status_reaches_caller() {
  local status=0
  printf 'import sys\nsys.exit(3)\n' >"${SCRATCH}/exit3.py"
  timeout "${LIMIT}" freecadcmd "${SCRATCH}/exit3.py" >"${SCRATCH}/exit3.log" 2>&1 || status=$?
  [[ "${status}" == 3 ]] || {
    printf 'freecadcmd exited %s, expected 3\n' "${status}" >&2
    return 1
  }
}

# Writes the command-line example of NOTES.md to ${SCRATCH}/make_plate.py, exactly as the notes give it.
write_notes_example() {
  cat >"${SCRATCH}/make_plate.py" <<'EOF'
import sys
import traceback

import FreeCAD
import Part


def main(output):
    doc = FreeCAD.newDocument("plate")
    plate = doc.addObject("Part::Box", "Plate")
    plate.Length, plate.Width, plate.Height = 80, 50, 5
    hole = doc.addObject("Part::Cylinder", "Hole")
    hole.Radius, hole.Height = 6, 5
    hole.Placement.Base = FreeCAD.Vector(40, 25, 0)
    cut = doc.addObject("Part::Cut", "PlateWithHole")
    cut.Base, cut.Tool = plate, hole
    doc.recompute()
    Part.export([cut], output)
    print("volume: %.1f mm^3" % cut.Shape.Volume)


try:
    main(sys.argv[sys.argv.index("--pass") + 1])
except Exception:
    traceback.print_exc()
    sys.stdout.flush()
    sys.exit(1)
EOF
}

# Succeeds when the notes' example writes its STEP file and exits 0, and exits non-zero when its export cannot be
# written, which raises inside the script.
notes_example_follows_script() {
  local status=0
  write_notes_example
  (cd "${SCRATCH}" && timeout 120 freecadcmd make_plate.py --pass plate.step) >"${SCRATCH}/plate.log" 2>&1 || {
    cat "${SCRATCH}/plate.log" >&2
    return 1
  }
  if [[ ! -s "${SCRATCH}/plate.step" ]] || ! grep -q '^volume: 19434.5 mm^3$' "${SCRATCH}/plate.log"; then
    printf 'the example wrote no STEP file or printed no volume\n' >&2
    cat "${SCRATCH}/plate.log" >&2
    return 1
  fi
  (cd "${SCRATCH}" && timeout 120 freecadcmd make_plate.py --pass /nonexistent/plate.step) \
    >"${SCRATCH}/plate_fail.log" 2>&1 || status=$?
  [[ "${status}" == 1 ]] || {
    printf 'the raising example exited %s, expected 1\n' "${status}" >&2
    return 1
  }
}

# Succeeds when an uncaught exception alone leaves the exit status 0, the upstream behavior the notes warn about.
uncaught_exception_exits_zero() {
  printf 'raise RuntimeError("expected failure")\n' >"${SCRATCH}/raise.py"
  timeout "${LIMIT}" freecadcmd "${SCRATCH}/raise.py" >"${SCRATCH}/raise.log" 2>&1
}

# Prints, one per line and sorted, the variables a process started from a freecadcmd script sees among those the
# launcher sets and those it must not set. The arguments are `NAME=value` settings for the caller's environment.
child_environment() {
  cat >"${SCRATCH}/child.py" <<'PY'
import subprocess
import sys

names = (
    "FONTCONFIG_FILE FONTCONFIG_PATH SSL_CERT_FILE GIT_SSL_CAINFO QT_QPA_PLATFORM "
    "LD_LIBRARY_PATH PYTHONHOME PYTHONPATH"
).split()
seen = subprocess.run(["env"], capture_output=True, text=True).stdout.splitlines()
with open(sys.argv[sys.argv.index("--pass") + 1], "w") as result:
    for line in seen:
        if line.split("=", 1)[0] in names:
            result.write(line + "\n")
PY
  env --unset=FONTCONFIG_FILE --unset=FONTCONFIG_PATH --unset=SSL_CERT_FILE --unset=GIT_SSL_CAINFO \
    --unset=QT_QPA_PLATFORM --unset=LD_LIBRARY_PATH --unset=PYTHONHOME --unset=PYTHONPATH "$@" \
    timeout "${LIMIT}" freecadcmd "${SCRATCH}/child.py" --pass "${SCRATCH}/child.env" >"${SCRATCH}/child.log" 2>&1 || {
    cat "${SCRATCH}/child.log" >&2
    return 1
  }
  sort "${SCRATCH}/child.env"
}

# Succeeds when freecad, on the offscreen Qt platform and without a display, runs a script with the GUI up and exits 0.
gui_runs_offscreen() {
  cat >"${SCRATCH}/offscreen.py" <<'PY'
import os

import FreeCAD
import FreeCADGui
from PySide6 import QtCore

ok = FreeCAD.GuiUp == 1 and FreeCADGui.getMainWindow() is not None
QtCore.QTimer.singleShot(0, lambda: os._exit(0 if ok else 3))
PY
  env --unset=DISPLAY --unset=WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen \
    timeout "${LIMIT}" freecad "${SCRATCH}/offscreen.py" >"${SCRATCH}/offscreen.log" 2>&1 || {
    cat "${SCRATCH}/offscreen.log" >&2
    return 1
  }
}

# Succeeds when freecad, with no display and no Qt platform chosen, fails with Qt's platform plugin message.
gui_fails_without_display() {
  if env --unset=DISPLAY --unset=WAYLAND_DISPLAY --unset=QT_QPA_PLATFORM timeout "${LIMIT}" freecad \
    >"${SCRATCH}/nodisplay.log" 2>&1; then
    printf 'freecad started without a display\n' >&2
    return 1
  fi
  grep -q 'no Qt platform plugin could be initialized' "${SCRATCH}/nodisplay.log" || {
    cat "${SCRATCH}/nodisplay.log" >&2
    return 1
  }
}

# Installs Xvfb from the image's repositories and starts it on display :99. This is test preparation: the feature
# itself provides no display.
start_x_server() {
  local as_root=()
  local attempt
  if [[ "$(id -u)" != 0 ]]; then as_root=(sudo -n); fi
  if command -v apt-get >/dev/null; then
    "${as_root[@]}" env DEBIAN_FRONTEND=noninteractive apt-get update >"${SCRATCH}/xvfb.log" 2>&1
    "${as_root[@]}" env DEBIAN_FRONTEND=noninteractive apt-get -y --no-install-recommends install xvfb \
      >>"${SCRATCH}/xvfb.log" 2>&1
  else
    "${as_root[@]}" dnf -y --setopt=install_weak_deps=False install xorg-x11-server-Xvfb >"${SCRATCH}/xvfb.log" 2>&1
  fi
  Xvfb "${DISPLAY_NUMBER}" -screen 0 1280x800x24 -ac >>"${SCRATCH}/xvfb.log" 2>&1 &
  for attempt in $(seq 1 30); do
    if [[ -S "/tmp/.X11-unix/X${DISPLAY_NUMBER#:}" ]]; then return; fi
    sleep 1
  done
  printf 'Xvfb did not start after %s attempts\n' "${attempt}" >&2
  cat "${SCRATCH}/xvfb.log" >&2
  return 1
}

# Writes the GUI example of NOTES.md to ${SCRATCH}/render_view.py, exactly as the notes give it.
write_notes_gui_example() {
  cat >"${SCRATCH}/render_view.py" <<'EOF'
import os
import sys

import FreeCAD
import FreeCADGui
from PySide6 import QtCore

output = sys.argv[sys.argv.index("--pass") + 1]
doc = FreeCAD.newDocument("view")
doc.addObject("Part::Box", "Box")
doc.recompute()
view = FreeCADGui.ActiveDocument.ActiveView
view.viewIsometric()
view.fitAll()
view.saveImage(output, 640, 480, "White")
# A GUI session stays open after its script; end it once the image is written.
QtCore.QTimer.singleShot(0, lambda: os._exit(0))
EOF
}

# Runs the notes' GUI example against the X server on :99 and succeeds when freecad exits 0 and the saved image of
# the 3D view shows the model, that is, holds more than the background color. The arguments are a command prefix
# such as `sudo -n`.
gui_renders_view() {
  local out="${SCRATCH}/view_$#"
  rm -rf "${out}"
  mkdir -p "${out}"
  chmod 0777 "${out}"
  write_notes_gui_example
  "$@" env DISPLAY="${DISPLAY_NUMBER}" timeout "${LIMIT}" freecad "${SCRATCH}/render_view.py" --pass "${out}/view.png" \
    >"${out}/log" 2>&1 || {
    cat "${out}/log" >&2
    return 1
  }
  cat >"${out}/colors.py" <<'PY'
import sys

from PySide6 import QtGui

image = QtGui.QImage(sys.argv[sys.argv.index("--pass") + 1])
colors = {image.pixel(x, y) for x in range(0, image.width(), 4) for y in range(0, image.height(), 4)}
sys.exit(0 if image.width() == 640 and len(colors) > 1 else 3)
PY
  timeout "${LIMIT}" freecadcmd "${out}/colors.py" --pass "${out}/view.png" >"${out}/colors.log" 2>&1 || {
    printf 'the image %s does not show the model\n' "${out}/view.png" >&2
    cat "${out}/log" >&2
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
