## Headless use

The feature installs the .NET build of the Godot editor as `godot`, for C# projects, with a .NET SDK. Use it without a
display, with `--headless`:

```sh
godot --headless --path . --build-solutions --quit   # build the project's C# scripts and exit
godot --headless --path . --quit        # run the project's main scene once and exit
godot --headless --path . --import      # import the project's resources and exit
godot --headless --editor --path . --lsp-port 6008   # serve the GDScript language server
```

The first build of a C# project downloads `Godot.NET.Sdk` and Godot's other packages from nuget.org into `~/.nuget`, so
it needs network access; later builds work offline. Godot writes a project's `.csproj` only from its editor window; a
project created without one needs it written by hand, with the release's `Godot.NET.Sdk` version and target framework,
for example for 4.7.2:

```xml
<Project Sdk="Godot.NET.Sdk/4.7.2">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
```

It installs nothing for a graphical session. To open the editor window, you need a display forwarded into the container
and the X11 or Wayland client, OpenGL or Vulkan, and audio libraries from your distribution; the feature does not test
this.

## Not together with `godot`

This feature and the [`godot`](../godot) feature both provide the `godot` command, so a dev container can have only one
of them. Whichever is installed second fails the build, naming `/usr/local/bin/godot`.

## The .NET SDK and what comes with it

The feature depends on the Dev Containers project's
[dotnet feature](https://github.com/devcontainers/features/tree/main/src/dotnet) with `"version": "lts"`, which the
build installs first. That feature, not this one, adds:

- the current long-term-support .NET SDK in `/usr/share/dotnet`, with `/usr/bin/dotnet`;
- `DOTNET_ROOT`, a `PATH` entry for it, `DOTNET_RUNNING_IN_CONTAINER`, and `DOTNET_USE_POLLING_FILE_WATCHER` in the
  container's environment, and `~/.dotnet/tools` on the `PATH` of login shells;
- `dotnet` shell completions, and the runtime's libraries, CA certificates, `wget`, `jq`, and ICU tools;
- in VS Code, the [C# extension](https://github.com/dotnet/vscode-csharp) (`ms-dotnettools.csharp`) and a GitHub Copilot
  instruction setting.

Know what the C# extension runs: in any folder you open in the container that holds a `.csproj`, it restores and loads
the projects with MSBuild, which runs the build logic the projects define, and it starts the server that
`dotnet.server.path` names, a setting the folder's own `.vscode/settings.json` can change. VS Code trusts every folder
opened in a dev container window. To leave the extension out, list it with a leading `-` in your own configuration:

```jsonc
"customizations": {
  "vscode": {
    "extensions": ["-ms-dotnettools.csharp"]
  }
}
```

The dotnet feature checks the SDK it downloads only by its size; see that feature for how it installs.

To build with another SDK as well, add your own entry, `"ghcr.io/devcontainers/features/dotnet:2"` with the `version`
that SDK needs (see that feature's options); the SDKs install side by side, and a `global.json` in the project selects
one for `dotnet build`. The Godot editor, though, runs on the newest .NET runtime in the container and builds with the
SDK of that major. An SDK of a newer major than the LTS can therefore break the editor's C# builds: with the .NET 11
release candidate, Godot 4.7.2's `--build-solutions` failed with `MSB4236` while `dotnet build` worked. An entry with
the dotnet feature's defaults installs the newest SDK.

## Godot Tools for VS Code

The feature requests no editor extension of its own. To use the
[Godot Tools](https://github.com/godotengine/godot-vscode-plugin) extension, add it in your own `devcontainer.json`. A
container has no display, so turn on its headless language server too:

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
version from `config/features` in `project.godot`; a project without a `"4.x"` entry there counts as Godot 3.

## Versions

- `latest` is the release that [the latest-release link](https://github.com/godotengine/godot/releases/latest) points to
  when the image is built. Pin `version` to the release your project uses, such as `4.6.3`, the release its `.csproj`
  names in `Godot.NET.Sdk/<release>`: the editor imports a project with the installed release and may add files a newer
  release introduces.
- `version` accepts `4.6` or `4.6.3`, with or without `-stable` (`4.6.3-stable`); `4.6.0` means `4.6`. A two-part value
  names that exact release, not the newest 4.6.x.
- Only stable releases from 4.2.2 on are installed: 4.2 is the first 4.x release with an arm64 .NET build, and 4.2.2 the
  first with `--import`. Pre-releases (dev, beta, rc) and the 3.x branch are not covered.
- Installing the feature again with the version already installed leaves the installation unchanged; any other version
  installs into a new release directory, switches `godot` to it, and removes the earlier one.

## Export templates

Exporting a project for a platform needs that release's .NET export templates, which the feature does not install (about
1.2 GB). Godot looks for them only in
`${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/<version>.stable.mono/` of the user running it. To install
them for the release you use, verified like the editor:

```sh
version=4.6.3   # the installed release, as `godot --version` starts
tag="${version}-stable"
base="https://github.com/godotengine/godot/releases/download/${tag}"
templates="Godot_v${tag}_mono_export_templates.tpz"
dir="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${version}.stable.mono"
curl --fail --location --remote-name "${base}/${templates}"
curl --fail --location --remote-name "${base}/SHA512-SUMS.txt"
grep "  ${templates}\$" SHA512-SUMS.txt | sha512sum --check \
  && mkdir -p "${dir}" && unzip -j "${templates}" 'templates/*' -d "${dir}" \
  && rm "${templates}" SHA512-SUMS.txt
```

The templates are extracted only when the checksum matches, and the downloads are removed afterwards; on a mismatch they
stay in the current directory for you to inspect.

## What the install does

- Downloads `Godot_v<tag>_mono_linux_<arch>.zip` and `SHA512-SUMS.txt` of the release from github.com over HTTPS, the
  checksum list first. It installs only when the archive's SHA-512 digest matches its one entry in the list, the archive
  holds the editor and its `GodotSharp` directory and nothing else, and the editor runs and reports the requested
  version. Upstream signs no release artifact, so this checks the archive's integrity against the published release, not
  the publisher's authenticity. The build log shows the final URL of each download.
- Puts the editor, renamed `godot`, and `GodotSharp` in a release directory under `/opt/godot-dotnet`, owned by root,
  and makes `/usr/local/bin/godot` a link to it. It refuses to touch either path when something else is there.
- Installs `curl`, `ca-certificates`, `unzip`, and the font configuration library (`libfontconfig1`) from the image's
  own package repositories when they are missing, and leaves them installed.
- Writes nothing under a home directory, sets no environment variable of its own, and runs no project at build time.
- Needs network access to github.com, and through the dotnet feature to Microsoft's download servers, at build time;
  nothing is fetched when the container starts.

## OS support

amd64 and arm64 images of the Debian and Ubuntu families, the ones the dotnet feature supports, tested on the images in
[test/godot-dotnet/compatibility.json](../../test/godot-dotnet/compatibility.json). Upstream's builds need the GNU C
library (glibc 2.28 for 4.2 to 4.7), so Alpine and other musl images are not supported. Other distributions of these
families are accepted when they have `apt-get`, but only the listed images are tested.
