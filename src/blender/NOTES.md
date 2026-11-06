## Installation

Installs the official Blender release build under `/opt/blender` and links its executable to `/usr/local/bin/blender`
for every user. The tree belongs to root. The archive comes from `https://download.blender.org/release/`, Blender's own
release host, and is verified against the SHA-256 checksum file published next to it before anything is extracted.
Blender publishes no signature for its releases, so the checksum file is trusted through HTTPS alone. The download page
on www.blender.org sends downloads to third-party mirrors; this feature never uses them, and it fails instead of
following a redirect.

The feature also installs the X11 client, OpenGL, and EGL libraries Blender needs, with Mesa's drivers, from the image's
own repositories. It installs no display server, no Vulkan driver, no GPU driver beyond Mesa's, and no Python package,
add-on, extension, or editor extension. It sets no environment variable and leaves Blender's preferences alone, so
online access stays off.

Plan for the size: the release takes about 1.2 GiB in the image and the libraries about 200 MB more; a build downloads
an archive of about 370 MiB.

Only amd64 images are supported, because Blender publishes no Linux build for arm64 or other architectures. Alpine and
other musl-based images are unsupported. The supported images are listed in
[compatibility.json](../../test/blender/compatibility.json).

## Selecting a release

`version` takes `latest` (the default), a series such as `5.2`, or an exact release such as `5.2.3`; anything older than
4.2.0 is rejected. `latest` and a series are resolved from the release listings whenever the feature installs, so
rebuilding can pick up new releases. A series follows the patch releases of one line, which suits add-on work against a
long-term support line; the [LTS page](https://www.blender.org/download/lts/) lists the maintained ones. Pin an exact
release for reproducible images.

Installing the feature again with the same release keeps the installation without downloading it. Another release
replaces it, newer or older, and a failed replacement keeps the previous one. An existing `blender` command from another
source, such as a distribution package, makes the installation fail; remove it first.

## Headless use for scripts and agents

Blender has no display in a dev container, so run it in background mode (`-b`). This command renders a preview of the
factory startup scene with a script; arguments after `--` reach the script in `sys.argv`:

```bash
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
timeout 600 blender -b --factory-startup --python-exit-code 1 --python render_preview.py -- "${PWD}/preview.png"
```

- `--python-exit-code 1` must come before `--python`. Without it, a script that raises still makes Blender exit 0.
  `sys.exit(n)` in a script exits with `n`.
- Bound every run with `timeout`: Blender 4.5 waits forever in background mode when `-E` names an engine it does not
  know.
- Check that the expected output exists. An unknown `-F` format, for example, still exits 0.
- `--factory-startup` ignores the user's preferences and enabled add-ons, which keeps runs reproducible.
- Engines for `-E`: `CYCLES`, `BLENDER_WORKBENCH`, and `BLENDER_EEVEE` (named `BLENDER_EEVEE_NEXT` in 4.2 to 4.5).
  Cycles renders on the CPU, and Workbench and EEVEE use Mesa's software OpenGL driver. The first EEVEE render takes 10
  to 20 seconds while shaders compile; later ones reuse the cache in `~/.cache`. Lines such as
  `EGL Error (0x3009): EGL_BAD_MATCH` are harmless.

## Developing extensions

Blender's own command line validates, builds, and installs an extension without network access. The package is named
`<id>-<version>.zip` and the module `bl_ext.user_default.<id>`, both from `blender_manifest.toml`. For an extension in
`my_extension/` whose manifest sets `id = "my_extension"` and `version = "1.0.0"`:

```bash
blender -b -c extension validate my_extension
mkdir -p dist
blender -b -c extension build --source-dir my_extension --output-dir dist
blender -b -c extension install-file -r user_default --enable dist/my_extension-1.0.0.zip
```

The last command installs it for the current user only, under `~/.config/blender/<MAJOR>.<MINOR>/extensions/`.

To run a script with the extension enabled under factory settings, name it with `--addons`. A module that `--addons`
cannot load does not change the exit status, so let the script check it:

```bash
cat >check_extension.py <<'EOF'
import addon_utils

loaded, enabled = addon_utils.check("bl_ext.user_default.my_extension")
if not enabled:
    raise SystemExit("my_extension is not enabled")
EOF
timeout 600 blender -b --factory-startup --addons bl_ext.user_default.my_extension --python-exit-code 1 \
  --python check_extension.py
```

Installing from extensions.blender.org or any other repository, including a `file://` one, needs Blender's online
access: put `--online-mode` before `-c`, for example `blender -b --online-mode -c extension sync`. Leave it out
otherwise.

Blender's bundled Python ignores `PYTHONPATH` and packages installed with `pip install --user`. Bundle the wheels an
extension needs in the extension itself, or, for local scripts, set `PYTHONPATH` and pass `--python-use-system-env`
before `--python`.

## Per-user state

Blender keeps preferences, installed extensions, and scripts in `~/.config/blender/<MAJOR>.<MINOR>/`, and caches in
`~/.cache`. They are lost when the container is rebuilt unless you mount a volume there.

## GPUs and library paths

Rendering uses the CPU and Mesa's software driver. Giving the container a GPU is outside this feature. From Blender 5.3,
Vulkan is the default backend on Linux; without a Vulkan driver, Blender falls back to OpenGL.

`/usr/local/bin/blender` runs Blender's executable directly, so processes a script starts inherit your environment
unchanged. If the image sets `LD_LIBRARY_PATH` and its libraries conflict with Blender's own, run
`/opt/blender/blender-launcher` instead: it puts Blender's libraries first.
