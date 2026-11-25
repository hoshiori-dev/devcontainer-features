## Versions

- `latest` is the release that HashiCorp's Checkpoint service (`https://checkpoint-api.hashicorp.com/v1/check/packer`)
  reports as current when the image is built. Pin `version`, such as `1.15.4` (a leading `v` is accepted), when you need
  a reproducible build.
- The oldest supported release is `1.7.0`, the first with `packer init`. Pre-releases (alpha, beta) are not supported.
- Installing the feature again with the version already installed leaves the binary unchanged; any other version
  replaces it.

## License

Packer 1.10.0 and later are licensed under the
[Business Source License 1.1](https://github.com/hashicorp/packer/blob/main/LICENSE); earlier releases are under the
Mozilla Public License 2.0. The feature downloads Packer from HashiCorp when your image is built and redistributes
nothing; check that HashiCorp's terms fit your use.

## Plugins

The feature installs no plugins. Since 1.11.0 Packer bundles only a few components (such as the `null` builder and the
`file`, `shell`, and `shell-local` provisioners); every other builder comes from a plugin that your template names in a
`required_plugins` block and `packer init` downloads into `~/.config/packer/plugins`. To install them when the container
is created:

```jsonc
"postCreateCommand": "packer init ."
```

`packer init` asks the GitHub API for plugin releases; set `PACKER_GITHUB_API_TOKEN` if you run into its rate limit.

## Keeping plugins and downloads across rebuilds

Plugins, and the ISO files that builders such as QEMU download into `~/.cache/packer`, live in the container's home
directory, so a rebuild fetches them again. To keep them, point Packer at a directory in your workspace and add it to
`.gitignore`:

```jsonc
"containerEnv": {
  "PACKER_PLUGIN_PATH": "${containerWorkspaceFolder}/.packer/plugins",
  "PACKER_CACHE_DIR": "${containerWorkspaceFolder}/.packer/cache"
}
```

## What the feature leaves to you

The feature writes no Packer configuration and sets no environment variable. Common additions:

- **Builder tools.** A builder runs the tool of its platform: the QEMU builder needs QEMU, the Docker builder a Docker
  daemon, and so on. Add them with their own features or packages.
- **Version checks.** Packer asks HashiCorp's Checkpoint service for its current version and security alerts when it
  runs. To turn that off:

  ```jsonc
  "containerEnv": {
    "CHECKPOINT_DISABLE": "1"
  }
  ```

- **Shell completion.** Run `packer -autocomplete-install` once in the container as your remote user; it appends a
  `complete -C` line to that user's `~/.bashrc`, and to `~/.zshrc` when that file exists.

## Another `packer` on RHEL-family images

On RHEL-family images such as `almalinux:9`, `/usr/sbin/packer` may already exist: it belongs to cracklib and has
nothing to do with HashiCorp Packer. The feature leaves it alone. Its own `/usr/local/bin/packer` comes first on the
default `PATH`, so `packer` runs HashiCorp Packer, but `sudo packer` on these images runs cracklib's, because their
`sudo` searches a path without `/usr/local/bin`. Use `sudo /usr/local/bin/packer` there.

## What the install does

- For `latest`, reads the current version from the Checkpoint service.
- Downloads the release's `packer_<version>_SHA256SUMS`, its detached signature `packer_<version>_SHA256SUMS.sig`, and
  upstream's key `https://www.hashicorp.com/.well-known/pgp-key.txt`, and accepts the list only when it carries a good
  signature by the release key with fingerprint `C874011F0AB405110D02105534365D9472D7468F`.
- Downloads `packer_<version>_linux_<arch>.zip` from `https://releases.hashicorp.com/packer/<version>/` and installs its
  `packer` to `/usr/local/bin/packer` only when the archive's SHA-256 digest matches its entry in the verified list.
  Every request uses HTTPS and follows no redirect.
- Installs `curl`, CA certificates, GnuPG, and `unzip` from the image's own package repositories when they are missing,
  and leaves them installed. On Arch Linux, installing a missing package also upgrades the image's packages, since
  pacman supports no other way.
- Writes nothing under a home directory. Needs network access to `releases.hashicorp.com`, `www.hashicorp.com`, and, for
  `latest`, `checkpoint-api.hashicorp.com` at build time; the feature fetches nothing when the container starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, RHEL, Alpine, openSUSE, and SUSE families, and amd64 images of
Arch Linux, tested on the images in [test/packer/compatibility.json](../../test/packer/compatibility.json). Other
distributions of these families are accepted when they have the family's package manager (`apt-get`, `dnf`, `apk`,
`zypper`, or `pacman`), but only the listed images are tested; images without it fail with a clear message.
