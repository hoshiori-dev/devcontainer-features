
# Hugging Face hf-mount (hf-mount)

Installs the hf-mount daemon and its NFS and FUSE backends from upstream release binaries, to mount Hugging Face Buckets and repositories as local filesystems.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/hf-mount:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The upstream release to install: latest, or a release number of the form MAJOR.MINOR.PATCH without a leading v. | string | latest |
| backend | The backends installed next to the daemon, which is always installed: hf-mount-nfs, hf-mount-fuse, or both. | string | both |
| installMountDependencies | Install the mount helpers of the selected backends: nfs-common or nfs-utils for NFS, fuse3 for FUSE. | boolean | true |

## What is installed

The feature installs the upstream [`hf-mount`](https://github.com/huggingface/hf-mount) daemon as
`/usr/local/bin/hf-mount` and, next to it, the backends `backend` selects: `hf-mount-nfs`, `hf-mount-fuse`, or both.
With `installMountDependencies` enabled it also installs the mount helpers of those backends from the image's own
repositories: `nfs-common` (Debian, Ubuntu) or `nfs-utils` (Fedora) for NFS, and `fuse3` for FUSE.

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
  pass `--fuse-owner-only`, which restricts the mount to the mounting user and needs no change to `/etc/fuse.conf`. With
  `hf-mount` 0.13.1 on a Linux 6.18 host, a `--fuse-owner-only` mount started but refused every access, including the
  mounting user's; if the mount point answers `Permission denied`, use `user_allow_other` instead.

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


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/hf-mount/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
