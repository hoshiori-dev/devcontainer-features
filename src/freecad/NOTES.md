## Installation

Installs the official FreeCAD release build under `/opt/freecad` and puts two commands on `PATH` for every user:
`freecadcmd`, which needs no display, and `freecad`, the GUI. The tree belongs to root.

FreeCAD publishes its Linux build as an AppImage, which cannot start in a container without FUSE. The feature downloads
the AppImage of a stable release from `https://github.com/FreeCAD/FreeCAD/releases`, verifies it against the SHA-256
checksum file of the same release, and unpacks it during the image build, so nothing needs FUSE afterwards. FreeCAD
publishes no signature for its Linux builds, so the checksum file is trusted through HTTPS alone. Release metadata comes
from the GitHub API without a token; a build host that has used up GitHub's limit for unauthenticated requests fails
with a message naming the URL, and a later build succeeds.

The feature also installs, from the image's own repositories, what the release build leaves to the host for its GUI:
Mesa's OpenGL and EGL libraries with its drivers, a fontconfig configuration, and the DejaVu fonts. It installs no
display server, no VNC server, no Vulkan driver, and no add-on, workbench, or editor extension, and it leaves FreeCAD's
preferences alone.

Plan for the size: the unpacked release takes about 3.4 GiB in the image, and a build downloads about 0.8 GiB and
briefly needs room for both.

amd64 and arm64 images are supported. Alpine and other musl-based images are not. The supported images are listed in
[compatibility.json](../../test/freecad/compatibility.json).

## Selecting a release

`version` takes `latest` (the default), a series such as `1.1`, or an exact release such as `1.1.4`; anything older than
1.1.0 is rejected. `latest` and a series are resolved whenever the feature installs, so rebuilding can pick up new
releases. Pin an exact release for reproducible images. Weekly builds and other pre-releases are not offered: FreeCAD
publishes no checksum file for them.

Installing the feature again with the same release keeps the installation without downloading it. Another release
replaces it, newer or older, and a failed replacement keeps the previous one. An existing `freecad` or `freecadcmd`
command from another source, such as a distribution package, makes the installation fail; remove it first.

## Command-line use for scripts and agents

`freecadcmd` runs a Python script with FreeCAD's modules loaded and no GUI. Arguments after `--pass` reach the script in
`sys.argv`. This script models a plate with a hole and exports it as STEP:

```python
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
```

Save it as `make_plate.py` and run it with a time limit:

```bash
timeout 120 freecadcmd make_plate.py --pass plate.step
```

Three things matter when a script or an agent depends on the result:

- **Exit status.** `freecadcmd` exits 0 when a script ends with an uncaught exception; it only prints the traceback. A
  script reports failure through `sys.exit` with a non-zero status, which is what the `try` block above is for.
- **Lost output.** `sys.exit` ends FreeCAD without flushing Python's standard output, so call `sys.stdout.flush()`
  before it, or the script's last `print` lines are lost when the output goes to a pipe or a file.
- **Time limit.** A run that waits for input or meets a geometry problem can take very long. Bound every run with
  `timeout`.

`freecadcmd` prints its banner and progress on the same streams as the script's output; write results a caller needs to
a file instead of parsing them from the output.

## Using the GUI

`freecad` needs a display, and the feature provides none. Give it one of these:

- an X11 display forwarded into the container by the editor or the host, with `DISPLAY` set;
- an X server you add to the container yourself, such as Xvfb for automated runs.

Without a GPU, FreeCAD renders through Mesa's software driver, which is slow on large models.

The launchers default `QT_QPA_PLATFORM` to `xcb`, as upstream's AppImage does, because FreeCAD has known problems on
Wayland. Without a display `freecad` therefore fails with Qt's message that no platform plugin could be initialized. Set
the variable yourself to choose another platform: `QT_QPA_PLATFORM=offscreen freecad script.py` starts the GUI without
any display, which is enough for scripts that use `FreeCADGui` but not for 3D views, which cannot render there.

A script given to `freecad` runs inside the GUI session, and the session stays open afterwards, so a script meant to
finish ends the process itself. This one saves an image of a 3D view; it needs an X server:

```python
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
```

```bash
timeout 120 freecad render_view.py --pass view.png
```

## Environment and files

The two commands are small launchers. They set five variables, each only when you have not set it yourself:
`FONTCONFIG_FILE` and `FONTCONFIG_PATH` (the image's fonts under `/etc/fonts`), `SSL_CERT_FILE` and `GIT_SSL_CAINFO`
(the certificate bundle shipped in the release, for the bundled Python and Git), and `QT_QPA_PLATFORM`. Behind a proxy
that inspects TLS, point the two certificate variables at your own bundle.

FreeCAD keeps its per-user state under the user's home (`~/.config/FreeCAD`, `~/.local/share/FreeCAD`,
`~/.cache/FreeCAD`). It is lost when the container is rebuilt unless you mount a volume there.

The release also carries a Python interpreter, pip, Gmsh, CalculiX, and Graphviz tools under `/opt/freecad/usr/bin`. The
feature leaves them off `PATH`, as upstream's AppImage does; call one by its full path when you need it. To use
FreeCAD's modules, run your script with `freecadcmd` rather than another Python interpreter.
