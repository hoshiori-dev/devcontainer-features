
# distrobuilder (lxc-distrobuilder)

Builds distrobuilder, the image building tool for Incus and LXC, from upstream's signature-verified release source and installs it with the tools it runs, in a container that holds the SYS_ADMIN capability the tool needs to build container images.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/lxc-distrobuilder:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | distrobuilder release to build: 'latest', the release upstream marks as latest, or a release such as 3.4.0 (a leading 'v' is accepted; 3.3.1 or later). | string | latest |
| vmSupport | Install the tools 'distrobuilder build-incus --vm' runs (Btrfs, ext4, and FAT file systems, GPT partitioning, qemu-img, udev). Building a virtual machine image also needs a privileged container; see the notes. | boolean | false |
| windowsSupport | Install the tools 'distrobuilder repack-windows' runs (hivex, wimlib, genisoimage). Repacking also needs a privileged container; see the notes. | boolean | false |

## What it does

Builds [distrobuilder](https://linuxcontainers.org/distrobuilder/introduction/), the image building tool for Incus and
LXC, from upstream's signed release source and installs it as `/usr/local/bin/distrobuilder`, with the tools it runs to
build container images. Upstream publishes distrobuilder as source only, so the feature compiles it during the image
build: it downloads the Go release the source names, verifies it, builds from the modules the source archive carries,
without network access, and removes the toolchain again. The build adds about a minute to an image build.

The full behavior is specified in
[openspec/specs/lxc-distrobuilder/spec.md](../../openspec/specs/lxc-distrobuilder/spec.md).

```sh
sudo distrobuilder build-incus alpine.yaml
sudo distrobuilder build-lxc alpine.yaml
```

Image definitions are YAML files; those of the community image server are in
[lxc-ci](https://github.com/lxc/lxc-ci/tree/main/images).

distrobuilder runs only as root. The feature gives no user a way to become root: a remote user who is not root needs the
image's own `sudo`.

## Security

- **The container holds the capability `SYS_ADMIN` and runs without an AppArmor profile** (`apparmor=unconfined`).
  distrobuilder creates namespaces and mounts file systems as soon as it starts, which a default container forbids, and
  Docker's default AppArmor profile forbids mounting also where the capability is held. A process with `SYS_ADMIN` and
  no AppArmor profile is not confined against the host. Unlike `privileged`, this leaves the system call filter, the
  masked system paths, and the device restrictions in place.
- distrobuilder is compiled from source during the image build. The source archive is used only with a good signature by
  the release manager's key, which the feature pins by fingerprint, and the Go toolchain only when it matches the
  checksum the Go project publishes.

Use this feature only for dev containers whose users you would trust with root on the host.

## What needs a privileged container

Building container images (`build-dir`, `build-incus`, `build-lxc`, and the `pack-` commands) works in the container as
the feature declares it.

**Building a virtual machine image (`build-incus --vm`) and repacking Windows media (`repack-windows`) need loop
devices**, which a feature cannot request singly. The options `vmSupport` and `windowsSupport` install the tools those
commands run and nothing else; to use them, declare the container privileged yourself:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/lxc-distrobuilder:1": { "vmSupport": true }
  },
  "privileged": true
}
```

A configuration that also installs the [incus](../incus/README.md) feature is privileged already.

## Versions

`version` is `latest`, the release upstream marks as latest on GitHub when the image is built, or a release such as
`3.4.0`. Releases before `3.3.1` are not supported: their tags and archive names have another form.

What the build needs and the image lacked (a C compiler, the C library's headers, curl, GnuPG) stays in the image after
the install.

## OS support

See [test/lxc-distrobuilder/compatibility.json](../../test/lxc-distrobuilder/compatibility.json).


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/lxc-distrobuilder/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
