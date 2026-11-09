
# Godot (godot)

Installs the standard build of the Godot editor from verified official releases, for headless use.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/godot:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Godot stable release: latest, or MAJOR.MINOR or MAJOR.MINOR.PATCH at or above 4.2.2, optionally with -stable. | string | latest |

## Headless use

The feature installs the standard (GDScript) build of the Godot editor as `godot`. Use it without a display, with
`--headless`:

```sh
godot --headless --path . --quit        # run the project's main scene once and exit
godot --headless --path . --import      # import the project's resources and exit
godot --headless --editor --path . --lsp-port 6008   # serve the GDScript language server
```

It installs nothing for a graphical session. To open the editor window, you need a display forwarded into the container
and the X11 or Wayland client, OpenGL or Vulkan, and audio libraries from your distribution; the feature does not test
this.

## Godot Tools for VS Code

The feature requests no editor extension. To use the [Godot Tools](https://github.com/godotengine/godot-vscode-plugin)
extension, add it in your own `devcontainer.json`. A container has no display, so turn on its headless language server
too:

```jsonc
"customizations": {
  "vscode": {
    "extensions": ["geequlim.godot-tools"],
    "settings": { "godotTools.lsp.headless": true }
  }
}
```

Know what this runs before you add it:

- Every time the extension activates in a folder that holds a `project.godot`, it runs the Godot executable named by its
  `godotTools.editorPath.*` settings with `--version`, or, when that name does not run, the file of that name in the
  folder. A folder's own `.vscode/settings.json` can change those settings, and VS Code trusts every folder opened in a
  dev container window, so a folder you open decides what that command runs.
- With `godotTools.lsp.headless`, the extension also starts the Godot editor on the folder's project as soon as it
  activates. The editor runs the project's enabled editor plugins and `@tool` scripts, as opening the project in the
  editor would.

For a Godot 4 project, the extension finds the installed `godot` through its default path. It reads the project's Godot
version from `config/features` in `project.godot`, which the editor writes when it creates a project; a project without
a `"4.x"` entry there counts as Godot 3, and the extension then looks for `godot3`, which the feature does not install.

## Versions

- `latest` is the release that [the latest-release link](https://github.com/godotengine/godot/releases/latest) points to
  when the image is built. Pin `version` to the release your project uses, such as `4.6.3`: the editor imports a project
  with the installed release and may add files a newer release introduces.
- `version` accepts `4.6` or `4.6.3`, with or without `-stable` (`4.6.3-stable`); `4.6.0` means `4.6`. A two-part value
  names that exact release, not the newest 4.6.x.
- Only stable releases from 4.2.2 on are installed: 4.2 is the first 4.x release with an arm64 build, and 4.2.2 the
  first with `--import`. Pre-releases (dev, beta, rc) and the 3.x branch are not covered.
- Installing the feature again with the version already installed leaves the executable unchanged; any other version
  replaces it.

## Export templates

Exporting a project for a platform needs that release's export templates, which the feature does not install (about 1.3
GB). Godot looks for them only in `${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/<version>.stable/` of the
user running it. To install them for the release you use, verified like the editor:

```sh
version=4.6.3   # the installed release, as `godot --version` starts
tag="${version}-stable"
base="https://github.com/godotengine/godot/releases/download/${tag}"
templates="Godot_v${tag}_export_templates.tpz"
dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable"
curl --fail --location --remote-name "${base}/${templates}"
curl --fail --location --remote-name "${base}/SHA512-SUMS.txt"
grep "  ${templates}\$" SHA512-SUMS.txt | sha512sum --check \
  && mkdir -p "${dir}" && unzip -j "${templates}" 'templates/*' -d "${dir}" \
  && rm "${templates}" SHA512-SUMS.txt
```

The templates are extracted only when the checksum matches, and the downloads are removed afterwards; on a mismatch they
stay in the current directory for you to inspect.

`--export-pack` needs no templates.

## .NET (C#)

The feature installs the standard build only. The .NET build of Godot, which C# projects need, is not covered.

## What the install does

- Downloads `Godot_v<tag>_linux.<arch>.zip` and `SHA512-SUMS.txt` of the release from github.com over HTTPS, the
  checksum list first. It installs the executable to `/usr/local/bin/godot` only when the archive's SHA-512 digest
  matches its one entry in the list, the archive holds nothing else, and the executable runs and reports the requested
  version. Upstream signs no release artifact, so this checks the archive's integrity against the published release, not
  the publisher's authenticity. The build log shows the final URL of each download.
- Installs `curl`, `ca-certificates`, `unzip`, and the font configuration library (`libfontconfig1` or `fontconfig`)
  from the image's own package repositories when they are missing, and leaves them installed.
- Writes nothing under a home directory, sets no environment variable, and runs no project at build time.
- Needs network access to github.com at build time; nothing is fetched when the container starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, and Fedora families, tested on the images in
[test/godot/compatibility.json](../../test/godot/compatibility.json). Upstream's builds need the GNU C library (glibc
2.28 for 4.2 to 4.7), so Alpine and other musl images are not supported. Other distributions of these families are
accepted when they have the family's package manager (`apt-get` or `dnf`), but only the listed images are tested; images
without it, such as Amazon Linux 2, fail with a clear message.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/godot/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
