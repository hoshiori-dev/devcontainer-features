#!/usr/bin/env bash
# Runs the examples of NOTES.md as written, as the remote user in a container without network access: the headless
# preview with a succeeding and a raising script, and the extension workflow with an enabled and a missing extension.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib
# shellcheck source=/dev/null
source "$(dirname "$0")/helpers.sh"

before="$(tree_manifest)"
cd "${SCRATCH}"

check "the container has no network access" bash -c '! curl -fsS --max-time 10 https://download.blender.org/release/'

# From NOTES.md, Headless use for scripts and agents.
cat >render_preview.py <<'EOF'
import sys

import bpy

output = sys.argv[sys.argv.index("--") + 1]
scene = bpy.context.scene
scene.render.resolution_x = 320
scene.render.resolution_y = 240
scene.render.filepath = output
bpy.ops.render.render(write_still=True)
EOF
check "the headless example exits 0" \
  timeout 600 blender -b --factory-startup --python-exit-code 1 --python render_preview.py -- "${PWD}/preview.png"
check "the headless example writes its preview" test -s preview.png
printf 'raise RuntimeError("expected failure")\n' >raise_error.py
check "the headless example exits non-zero when the script raises" \
  bash -c "! timeout 600 blender -b --factory-startup --python-exit-code 1 --python raise_error.py -- '${PWD}/x.png'"

# From NOTES.md, Developing extensions, with a minimal extension named my_extension.
make_extension my_extension my_extension
check "the extension validates offline" blender -b -c extension validate my_extension
mkdir -p dist
check "the extension builds offline" blender -b -c extension build --source-dir my_extension --output-dir dist
check "the built extension installs offline" \
  blender -b -c extension install-file -r user_default --enable dist/my_extension-1.0.0.zip
check "the extension is installed under the user's home" \
  compgen -G "${HOME}/.config/blender/*/extensions/user_default/my_extension/blender_manifest.toml"
cat >check_extension.py <<'EOF'
import addon_utils

loaded, enabled = addon_utils.check("bl_ext.user_default.my_extension")
if not enabled:
    raise SystemExit("my_extension is not enabled")
EOF
check "the installed extension is enabled in the user's preferences" \
  timeout 600 blender -b --python-exit-code 1 --python check_extension.py
check "a script runs with the extension enabled under factory settings" \
  timeout 600 blender -b --factory-startup --addons bl_ext.user_default.my_extension --python-exit-code 1 \
  --python check_extension.py
sed 's/my_extension/missing_extension/g' check_extension.py >check_missing.py
check "the check fails the run when the extension cannot load" \
  bash -c '! timeout 600 blender -b --factory-startup --addons bl_ext.user_default.missing_extension \
    --python-exit-code 1 --python check_missing.py'
check "running Blender leaves the installation tree unchanged" test "$(tree_manifest)" = "${before}"

reportResults
