## Configuration and credentials

The feature writes no rclone configuration. Run `rclone config` in the container to create
`~/.config/rclone/rclone.conf`, or bring the configuration from your machine with a bind mount in your own
`devcontainer.json`:

```jsonc
"mounts": [
  "source=${localEnv:HOME}/.config/rclone,target=/home/vscode/.config/rclone,type=bind"
]
```

Use your remote user's home as the target. The file holds your remotes' tokens and passwords, so everything running in
the container can read them; mount only the remotes the container needs, or define them through `RCLONE_CONFIG_*`
environment variables instead.

## Shell completions

The feature writes the completion scripts the installed rclone generates for its own version:

| Shell | File                                                  | Active when                                     |
| ----- | ----------------------------------------------------- | ----------------------------------------------- |
| bash  | `/usr/local/share/bash-completion/completions/rclone` | the `bash-completion` package is loaded         |
| zsh   | `/usr/local/share/zsh/site-functions/_rclone`         | zsh's completion system (`compinit`) is enabled |
| fish  | `/usr/share/fish/vendor_completions.d/rclone.fish`    | fish is installed                               |

The `mcr.microsoft.com/devcontainers/base` images already load bash-completion and enable zsh's completion system. The
feature installs none of these shells or packages; on images without them, the files do nothing.

## Mounting with rclone mount

Set `installMountDependencies` to `true` to install `fuse3`, which provides the `fusermount3` helper `rclone mount`
needs. A mount is started by you, inside the running container, and the container must be allowed to mount. The feature
grants nothing; add the settings to `runArgs` in `devcontainer.json`:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/rclone:1": {
      "installMountDependencies": true
    }
  },
  "runArgs": ["--cap-add=SYS_ADMIN", "--device=/dev/fuse", "--security-opt=apparmor=unconfined"]
}
```

- `--cap-add=SYS_ADMIN` and `--device=/dev/fuse` are needed by every FUSE mount.
- `--security-opt=apparmor=unconfined` is needed where the host runs AppArmor, such as Ubuntu, since Docker's default
  profile denies `mount`.
- `--privileged` is the broad alternative to the three settings above. It grants far more than a mount needs.

Then, for example:

```bash
mkdir -p ~/mnt/remote
rclone mount remote:path ~/mnt/remote --daemon
ls ~/mnt/remote
fusermount3 -u ~/mnt/remote
```

A non-root user, such as `vscode`, mounts through the set-user-ID `fusermount3` and needs nothing more for a mount only
that user reads. `--allow-other`, which lets other users read the mount, also needs a line `user_allow_other` in
`/etc/fuse.conf`; the feature leaves that file as the `fuse3` package installs it, so add the line yourself if you need
it.

## Versions

- `latest` is the release that [version.txt](https://downloads.rclone.org/version.txt) names when the image is built.
  Pin `version`, such as `1.76.0` (a leading `v` is accepted), for reproducible builds.
- The oldest supported release is `1.63.0`, the first with the `rclone completion` command. Beta builds are not
  supported: upstream publishes no checksum list for them.
- Installing the feature again with the version already installed leaves the binary unchanged and rewrites the
  completion files; any other version replaces both.
- `rclone selfupdate` replaces `/usr/local/bin/rclone` outside the feature's control; the next build installs the
  requested release again. An rclone from the distribution's packages at `/usr/bin/rclone` stays installed, but the
  feature's `/usr/local/bin/rclone` comes first on the default `PATH`.

## What the install does

- Downloads the release's `SHA256SUMS` and upstream's key list `https://rclone.org/KEYS`, and accepts the list only when
  it carries a good signature by the release key `FBF737ECE9F8AB18604BD2AC93935E02FF3B54FA` that
  [upstream's release signing page](https://rclone.org/release_signing/) documents. That key is a DSA-1024 key signing
  with SHA-1 digests, weaker than current recommendations; it is the only signature upstream publishes.
- Downloads `rclone-v<version>-linux-<arch>.zip` from `downloads.rclone.org` and installs its `rclone` to
  `/usr/local/bin/rclone` only when the archive's SHA-256 digest matches its entry in the signed text. Every request
  uses HTTPS and fails on a redirect.
- Installs `curl`, `ca-certificates`, GnuPG, and `unzip` from the image's own package repositories when they are
  missing, and leaves them installed.
- Writes nothing under a home directory and sets no environment variable. It starts no transfer and no mount.
- Needs network access to `downloads.rclone.org` and `rclone.org` at build time; nothing is fetched when the container
  starts.

## OS support

amd64 and arm64 images of the Debian, Ubuntu, Fedora, and Alpine families, tested on the images in
[test/rclone/compatibility.json](../../test/rclone/compatibility.json). Other distributions of these families are
accepted when they have the family's package manager (`apt-get`, `dnf`, or `apk`), but only the listed images are
tested; images without it fail with a clear message.
