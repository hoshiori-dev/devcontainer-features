
# Deno (deno)

Installs the Deno CLI, verified against its published checksums, with a shared PATH location for tools installed with deno install --global.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/deno:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | Deno version to install: latest, or an exact release version MAJOR.MINOR.PATCH (2.7.14, or 2.8.0 and later). | string | latest |

## Versions

`version` takes `latest` or an exact release version such as `2.9.7`; partial versions (`2.9`) and a `v` prefix are
rejected. `latest` is read from `https://dl.deno.land/release-latest.txt` at build time. Only stable releases are
installed, never LTS, release-candidate, or canary builds.

The archive comes from the Deno GitHub release. Its SHA-256 is checked against the release's
`deno-<target>.zip.sha256sum` before extraction, and the extracted `deno` against `deno-<target>.sha256sum` before it is
installed. Only releases that publish both files install: `2.7.14`, and `2.8.0` and later. Other releases fail with a
message naming the missing checksum file.

Installing the feature again with the version already installed keeps `/usr/local/bin/deno` and downloads nothing;
another version replaces it. A failed installation leaves the previous `deno` in place.

## Global tools

`DENO_INSTALL_ROOT` is `/usr/local/share/deno`, and `/usr/local/share/deno/bin` is appended to `PATH`, so tools
installed with `deno install --global` run by name in every shell. The directory is owned by the remote user when that
user exists at build time and is not root, so installing a tool needs no `sudo`; otherwise it is owned by root. Because
the directory comes last on `PATH`, a tool named like a system command runs only by its full path. The feature installs
after `common-utils` when both are used, so a remote user that feature creates owns the directory.

`DENO_DIR` (Deno's cache) keeps its per-user default.

## Updates

`DENO_NO_UPDATE_CHECK` is `1`: the feature manages the installed version, so change `version` and rebuild instead of
running `deno upgrade`.

## Prerequisites

On an image without `curl`, `ca-certificates`, or `unzip`, the missing packages are installed with apt and kept.

## OS support

Debian- and Ubuntu-based images with glibc 2.27 or newer, on amd64 and arm64; Deno publishes no musl build, so Alpine is
unsupported. Tested images: [test/deno/compatibility.json](../../test/deno/compatibility.json).


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/deno/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
