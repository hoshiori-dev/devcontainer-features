
# LaTeX (via TinyTeX) (latex)

User-managed LaTeX environment with academic packages, Chinese and Japanese support, formatting, linting, and highlighting.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/latex:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| profile | Package tier: TinyTeX-1, TinyTeX plus academic essentials, or TinyTeX-2 (full TeX Live). | string | standard |
| languages | Additional languages, comma-separated: zh, ja, both, or none. | string | zh,ja |
| packages | Additional TeX Live package names separated by spaces or commas. | string | - |
| ctanMirror | HTTPS TeX Live repository URL without credentials; empty uses automatic CTAN routing. | string | - |

## Customizations

### VS Code Extensions

- `James-Yu.latex-workshop`

## Installation and packages

Add the feature to `devcontainer.json`. This example selects the default academic tier and both CJK languages, with one
extra package:

```json
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/latex:1": {
      "profile": "standard",
      "languages": "zh,ja",
      "packages": "csquotes"
    }
  }
}
```

Use `zh`, `ja`, or `none` to change the language selection. The option table in the feature README lists defaults and
accepted values.

The feature installs TinyTeX into the configured remote user's `~/.TinyTeX`. Executable links are in `~/.local/bin`; a
managed PATH bridge makes those commands available in VS Code tasks and terminals. TeX packages, formats, and Lua font
caches are owned by that user. Run `tlmgr` without sudo:

```bash
# Find the package containing a missing file.
tlmgr search --global --file '/somepackage.sty'
# Install the package and expose any new executables.
tlmgr install somepackage
tlmgr path add
```

Declare packages needed after a rebuild in the `packages` option. Packages added in a running container are part of that
container's filesystem; Docker's build cache does not preserve them across a fresh rebuild.

The profiles start from TinyTeX-1 (`basic`), TinyTeX with academic templates, minted, and bibliography tools
(`standard`), or TinyTeX-2 with the full TeX Live package scheme (`full`). Every profile includes pdfLaTeX, XeLaTeX,
LuaLaTeX, latexmk, latexindent, chktex, and Pygments. Language additions apply to all profiles. `languages=none`
requests no CJK additions; a bundle can already include some of those packages.

Installing the feature again reuses its own tree and adds missing packages. Choosing a smaller profile or fewer
languages does not uninstall anything. An unrelated or broken installation at `~/.TinyTeX` is preserved and rejected;
move it before installing this feature. A repository from a different TeX Live year requires a clean rebuild or a
matching repository, rather than an implicit destructive upgrade.

`ctanMirror` accepts an HTTPS TeX Live repository URL, for example a mirror's `/systems/texlive/tlnet` directory,
without credentials. Use a specific mirror rather than an additional redirector, so its index and packages come from the
same snapshot. Leave `ctanMirror` empty to use automatic CTAN routing. Both bundle and package transfers require HTTPS,
including redirects. When GitHub publishes an asset digest, the feature verifies it. If the publisher introduces a
checksum or signature format that is not yet supported, installation fails until verification support is added. When no
digest, checksum, or signature is published, installation relies on HTTPS and logs that limitation.

Daily TinyTeX bundles and live CTAN packages change over time. Pin a built container image by digest when you need to
preserve an exact environment.

## Fonts and templates

Chinese support includes ctex, xeCJK, Fandol, and Noto CJK system fonts. Japanese support includes LuaTeX-ja, zxjatype,
pLaTeX, upLaTeX, dvipdfmx, Japanese bibliography tools, Harano Aji, and IPAex fonts. Traditional Japanese font maps use
Harano Aji. Fontconfig and the target user's Lua font index are prepared during image construction.

For portable Chinese documents, use `\documentclass[fontset=fandol]{ctexart}` with XeLaTeX or LuaLaTeX. Japanese
LuaLaTeX documents can use `ltjsarticle`; upLaTeX documents can use `\documentclass[uplatex,dvipdfmx]{jsarticle}`.
Publisher templates that require proprietary fonts, historical engines, or additional packages may need explicit
configuration. The feature does not promise compatibility with every publisher template.

## VS Code configuration

The feature adds LaTeX Workshop to the container's VS Code extensions list and leaves your settings unchanged. Copy this
configuration into your project's `.vscode/settings.json` and select the appropriate recipe for your document. The
upLaTeX recipe generates DVI and then runs dvipdfmx.

```json
{
  "latex-workshop.formatting.latex": "latexindent",
  "latex-workshop.latex.recipes": [
    { "name": "latexmk (pdflatex)", "tools": ["latexmk-pdf"] },
    { "name": "latexmk (xelatex)", "tools": ["latexmk-xe"] },
    { "name": "latexmk (lualatex)", "tools": ["latexmk-lua"] },
    { "name": "latexmk (uplatex)", "tools": ["latexmk-up"] }
  ],
  "latex-workshop.latex.tools": [
    {
      "name": "latexmk-pdf",
      "command": "latexmk",
      "args": ["-pdf", "-interaction=nonstopmode", "-halt-on-error", "-synctex=1", "%DOC%"]
    },
    {
      "name": "latexmk-xe",
      "command": "latexmk",
      "args": ["-xelatex", "-interaction=nonstopmode", "-halt-on-error", "-synctex=1", "%DOC%"]
    },
    {
      "name": "latexmk-lua",
      "command": "latexmk",
      "args": ["-lualatex", "-interaction=nonstopmode", "-halt-on-error", "-synctex=1", "%DOC%"]
    },
    {
      "name": "latexmk-up",
      "command": "latexmk",
      "args": [
        "-pdfdvi",
        "-latex=uplatex %O %S",
        "-e",
        "$dvipdf = 'dvipdfmx %O -o %D %S';",
        "-interaction=nonstopmode",
        "-halt-on-error",
        "-synctex=1",
        "%DOC%"
      ]
    }
  ]
}
```

Current minted uses `latexminted` with its bundled Python libraries, and current TeX Live normally runs it through
restricted shell escape. The default recipes therefore need no `-shell-escape`. If a trusted older template needs
unrestricted shell escape, add `"-shell-escape"` to that recipe's tool arguments yourself; it allows the document to
execute arbitrary shell commands. The system `pygmentize` command also supports older minted workflows.

`standard` and `full` include minted and bibliography tools. With `basic`, request additional packages such as `minted`,
`biblatex`, and `biber` through `packages` when needed.

## Installation time and supported platforms

The three-minute build benchmark covers `basic` and `standard` with default languages and no extra packages on native
GitHub-hosted Ubuntu 24.04 runners, using supported base images that are already downloaded and no installation-layer or
download caches. It includes dependencies, bundle transfer and verification, package additions, font maps, and font
caches. Network outages and retries are reported separately; ordinary successful slow transfers count. Every qualifying
run must pass before release. Base-image pulling and unrelated Features are outside the measurement. `full` and custom
package additions have no three-minute guarantee. A successful installation is never interrupted solely because it
reaches 180 seconds.

Supported image/architecture pairs are recorded in
[`test/latex/compatibility.json`](https://github.com/hoshiori-dev/devcontainer-features/blob/main/test/latex/compatibility.json).
Alpine/musl and Arch ARM are unsupported. AlmaLinux coverage does not imply all RHEL-compatible releases are tested.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/latex/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
