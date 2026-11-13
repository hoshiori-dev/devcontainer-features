
# OpenTofu (opentofu)

Installs OpenTofu's tofu command, which plans and applies infrastructure-as-code configurations, from its signature-verified GitHub release archive, and requests the OpenTofu VS Code extension.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/opentofu:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | OpenTofu version to install: 'latest', the release upstream marks as latest, or a release such as 1.13.9 (a leading 'v' is accepted; 1.6.3 or later). | string | latest |

## Customizations

### VS Code Extensions

- `opentofu.vscode-opentofu`

## Versions

- `latest` is the release that https://github.com/opentofu/opentofu/releases/latest points to when the image is built:
  the release upstream marks as latest on GitHub. Upstream maintains more than one release line at a time, so pin
  `version`, such as `1.13.9` (a leading `v` is accepted), when your configuration needs a particular line or a
  reproducible build.
- The oldest supported release is `1.6.3`, the first with `.tar.gz` archives. Pre-releases (alpha, beta, rc) are not
  supported.
- Installing the feature again with the version already installed leaves the binary unchanged; any other version
  replaces it.
- A `tofu` from the distribution's packages at `/usr/bin/tofu` stays installed, but the feature's `/usr/local/bin/tofu`
  comes first on the default `PATH`.

## Editor extension

The feature asks VS Code to install the official [OpenTofu extension](https://github.com/opentofu/vscode-opentofu)
(`opentofu.vscode-opentofu`), which runs `tofu` from `PATH`. To leave it out, list it with a leading `-` in your own
`devcontainer.json`:

```jsonc
"customizations": {
  "vscode": {
    "extensions": ["-opentofu.vscode-opentofu"]
  }
}
```

## What the feature leaves to you

The feature writes no OpenTofu configuration, sets no environment variable, and installs no `terraform` command. Common
additions:

- **git.** Modules with a `git::` source need `git` in the image. Most dev container base images have it; otherwise add
  the `ghcr.io/devcontainers/features/git` feature.
- **Provider plugin cache.** Providers are downloaded into each configuration's `.terraform` directory, which lives in
  your workspace and survives a rebuild. To share them between configurations, set a cache directory; OpenTofu does not
  create it, so create it when the container is created:

  ```jsonc
  "containerEnv": {
    "TF_PLUGIN_CACHE_DIR": "/home/vscode/.cache/opentofu/plugins"
  },
  "postCreateCommand": "mkdir -p /home/vscode/.cache/opentofu/plugins"
  ```

  Use your remote user's home in place of `/home/vscode`.
- **Shell completion.** Run `tofu -install-autocomplete` once in the container as your remote user; it appends a
  `complete -C` line to that user's `~/.bashrc`, and to `~/.zshrc` when that file exists, where zsh also needs
  `bashcompinit` loaded.

## What the install does

- Downloads the release's `tofu_<version>_SHA256SUMS`, its detached signature `tofu_<version>_SHA256SUMS.gpgsig`, and
  upstream's key `https://get.opentofu.org/opentofu.asc`, and accepts the list only when it carries a good signature by
  the release key with fingerprint `E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80`.
- Downloads `tofu_<version>_linux_<arch>.tar.gz` from the GitHub release and installs its `tofu` to
  `/usr/local/bin/tofu` only when the archive's SHA-256 digest matches its entry in the verified list. Every request
  uses HTTPS, including GitHub's redirects to its download host.
- Installs `curl`, CA certificates, GnuPG, `tar`, and `gzip` from the image's own package repositories when they are
  missing, and leaves them installed. On Arch Linux, installing a missing package also upgrades the image's packages,
  since pacman supports no other way.
- Writes nothing under a home directory. Needs network access to `github.com` and `get.opentofu.org` at build time;
  nothing is fetched when the container starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, RHEL, Alpine, openSUSE, and SUSE families, and amd64 images of
Arch Linux, tested on the images in [test/opentofu/compatibility.json](../../test/opentofu/compatibility.json). Other
distributions of these families are accepted when they have the family's package manager (`apt-get`, `dnf`, `apk`,
`zypper`, or `pacman`), but only the listed images are tested; images without it fail with a clear message.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/opentofu/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
