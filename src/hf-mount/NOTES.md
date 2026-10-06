## What is installed

The feature installs the upstream [`hf-mount`](https://github.com/huggingface/hf-mount) daemon as
`/usr/local/bin/hf-mount` and, next to it, the backends `backend` selects: `hf-mount-nfs`, `hf-mount-fuse`, or both.
With `installMountDependencies` enabled it also installs the mount helpers of those backends from the image's own
repositories: `nfs-common` (Debian, Ubuntu) or `nfs-utils` (Fedora) for NFS, and `fuse3` for FUSE. To download the
binaries, it installs `curl` and `ca-certificates` from the image's repositories when the image lacks them.

It installs tools only. It starts no mount and no `hf-mount` process, grants the container no privilege, capability, or
device, leaves `/etc/fuse.conf` and the sudo configuration as they are, and reads or stores no Hugging Face credential:
`hf-mount` takes the token itself at run time, from `HF_TOKEN` or `--token-file`.

## Container settings a mount needs

A mount is started by you, inside the running container, and the container must be allowed to mount. Add the settings to
`runArgs` in `devcontainer.json`:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/hf-mount:1": {}
  },
  "runArgs": ["--cap-add=SYS_ADMIN", "--device=/dev/fuse"]
}
```

- `--cap-add=SYS_ADMIN`: needed by every mount, NFS or FUSE.
- `--device=/dev/fuse`: needed by the FUSE backend (`hf-mount start --fuse`).
- `--security-opt=apparmor=unconfined`: needed in addition where the container runs under an AppArmor profile, since
  Docker's default profile denies `mount`.
- `--privileged`: the broad alternative to the three settings above. It grants far more than a mount needs; prefer the
  narrow settings.

Then, for example:

```bash
hf-mount start repo openai-community/gpt2 /tmp/gpt2          # NFS backend
hf-mount start --fuse repo openai-community/gpt2 /tmp/gpt2   # FUSE backend
hf-mount status
hf-mount stop /tmp/gpt2
```

## Mounting as a non-root user

As root, the settings above are enough. A non-root user, such as `vscode`, needs more, and the feature sets none of it
up:

- NFS: passwordless `sudo`. `hf-mount` runs `mount.nfs` and `umount` through `sudo -n`.
- FUSE: `user_allow_other` on a line of its own in `/etc/fuse.conf`, because `hf-mount` mounts with `allow_other`; or
  pass `--fuse-owner-only`, which restricts the mount to the mounting user and needs no change to `/etc/fuse.conf`. In
  this feature's hand checks (`hf-mount` 0.10.0, 0.12.0, and 0.13.1 on one WSL2 host), a `--fuse-owner-only` mount
  started but refused every access, the mounting user's included, whether root or `vscode` had mounted; if the mount
  point answers `Permission denied`, use `user_allow_other` instead.

## Passing a token from your machine

Public repositories mount without a token. For private repositories and private Buckets, `hf-mount` reads the token from
`HF_TOKEN`, from `--hf-token`, or from the file `--token-file` names. To hand the container a token that already exists
on the host, set the variable on the host and forward it with `remoteEnv`:

```jsonc
{
  "remoteEnv": {
    "HF_TOKEN": "${localEnv:HF_TOKEN}"
  }
}
```

`${localEnv:HF_TOKEN}` takes the value from the environment of the tool on your machine, so the token stays out of the
repository and out of the image; a tool that was already running, such as VS Code, may need a restart to see a variable
you have just set. Prefer `remoteEnv` to `containerEnv` for a token: `containerEnv` stores the value in the container's
configuration, where `docker inspect` shows it. Prefer the variable to `--hf-token` as well, since a command-line
argument is visible in the process list. If you logged in with `hf auth login`,
`--token-file ~/.cache/huggingface/token` points `hf-mount` at the token that command stored.

## The cache

`hf-mount` keeps its own disk cache, apart from the `hf` CLI's, in `/tmp/hf-mount-cache` unless `--cache-dir` names
another directory. `--cache-size` caps its chunk cache at about 10 GB by default; the staging files of
`--advanced-writes` live in the same directory and have no cap unless `--max-staging-size` sets one. It is in the
container's filesystem, so a rebuild discards it. The feature mounts nothing there on purpose: a mount works without a
persistent cache, and where the cache lives and how large it grows are your decisions. To keep it, mount a volume or a
host folder and name it when you start the mount:

```jsonc
{
  "mounts": [{ "source": "hf-mount-cache-${devcontainerId}", "target": "/var/cache/hf-mount", "type": "volume" }],
  "postCreateCommand": "sudo chown \"$(id -u):$(id -g)\" /var/cache/hf-mount"
}
```

```bash
hf-mount start --cache-dir /var/cache/hf-mount repo openai-community/gpt2 /tmp/gpt2
```

A new volume belongs to root, so the `chown` (which needs passwordless `sudo`) hands it to your user. The `HF_HOME`,
`HF_HUB_CACHE`, and `HF_XET_*` variables are documented for the `huggingface_hub` Python library and the `hf` CLI;
upstream documents none of them for `hf-mount`. Its flags are listed in the
[upstream README](https://github.com/huggingface/hf-mount#options); a pinned older release may not have all of them.

## Downloads

The binaries come from the GitHub releases of `huggingface/hf-mount`:
`https://github.com/huggingface/hf-mount/releases/download/v<version>/<asset>`, and `latest` is resolved from
`https://github.com/huggingface/hf-mount/releases/latest`. Upstream publishes no checksum and no signature for any
release, so the feature verifies none: the integrity and authenticity of every download rest on TLS alone. Every request
uses HTTPS, including redirects, and carries no credential.

`latest` installs whatever upstream has released when the image is built, and upstream releases several times a month.
Set `version` to a release number, such as `0.13.1`, for a build that does not change under you.

## Installing twice

A second installation downloads and replaces the daemon and every backend it selects, at its own `version`, including an
older one. It removes nothing: a backend installed earlier and not selected again stays at its earlier version, next to
the daemon of the second installation, and packages installed earlier stay whatever `installMountDependencies` says
later.

## OS support

Debian, Ubuntu, and Fedora images with glibc 2.34 or later, on x86_64 and aarch64; the tested images are listed in
[test/hf-mount/compatibility.json](../../test/hf-mount/compatibility.json). On a musl-based image such as Alpine, with
an older glibc, on another architecture, or on another distribution, the install fails with a message naming the reason,
before it changes anything.
