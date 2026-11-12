
# Lean (lean)

Installs elan, the Lean version manager, with the lean and lake commands, keeps Lean toolchains and the Lake and Mathlib caches on a volume that survives rebuilds, and optionally installs toolchains into the image.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/lean:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| elanVersion | The elan release to install: latest, the newest release at build time, or one release as MAJOR.MINOR.PATCH, 4.1.0 or later. | string | latest |
| defaultToolchain | The toolchain elan uses outside a project, set each time the container is created: stable, beta, nightly, a release such as v4.35.0, or nightly-YYYY-MM-DD, optionally prefixed with leanprover/lean4: or leanprover/lean4-nightly:. Empty leaves elan's default to you. | string | stable |
| preinstallToolchains | Toolchains to install into the image at build time, comma-separated, in the forms defaultToolchain accepts; each adds about 3 GB to the image. | string | - |

## Customizations

### VS Code Extensions

- `leanprover.lean4`

## What it installs

- elan, the Lean version manager, as `/usr/local/bin/elan`, at the release `elanVersion` names (`latest` resolves at
  build time from `https://github.com/leanprover/elan/releases/latest`; any release from 4.1.0 on can be pinned). The
  archive comes from the GitHub release. Upstream publishes no checksum or signature for it, so the download relies on
  TLS and is compared with the SHA-256 digest GitHub reports for the asset when GitHub's API answers. No installer
  script runs and no shell profile is edited.
- `lean`, `lake`, `leanc`, `leanmake`, `leanchecker`, and `leanpkg` in `/usr/local/bin`, as links to elan. elan acts as
  each of them and runs the toolchain the current project asks for.
- Git, which Lake uses to fetch dependencies, plus curl, CA certificates, tar, gzip, and find when the image lacks them.
- The VS Code extension `leanprover.lean4`.

A build behind an egress allowlist reaches `github.com` and GitHub's asset host `release-assets.githubusercontent.com`
for elan, and `api.github.com` for its digest; without that host the digest is not compared. With
`preinstallToolchains`, it also reaches `release.lean-lang.org` and `releases.lean-lang.org`, whose toolchains GitHub's
asset host serves.

No toolchain is installed at build time by default, and the feature runs no project command: it does not run
`lake build`, `lake update`, or `lake exe cache get`, and installs no Mathlib.

## Toolchains

A Lean project names its toolchain in its `lean-toolchain` file, for example `leanprover/lean4:v4.35.0`. The first
`lean` or `lake` command in the project, or opening a file of the project in VS Code, makes elan download that toolchain
(about 570 MB, about 3 GB unpacked) into elan's home on the volume. Later rebuilds of the dev container keep it. The
feature never sets `ELAN_TOOLCHAIN`, so every project keeps its own toolchain.

`defaultToolchain` is the toolchain elan uses outside a project: for a single `.lean` file, for `lake new`, and for the
editor's first start. The feature sets it each time the dev container is created, which replaces a default you set with
`elan default`. `stable`, the default, follows upstream's stable releases: elan resolves it when it is used and
downloads a new stable toolchain on first use. Set `defaultToolchain` to an empty string to leave elan's default to you;
a new volume then has no default until you run `elan default <toolchain>`.

`preinstallToolchains` installs toolchains into the image at build time, for offline use, CI, or prebuilt images:

```jsonc
"features": {
  "ghcr.io/hoshiori-dev/devcontainer-features/lean:1": {
    "preinstallToolchains": "leanprover/lean4:v4.35.0"
  }
}
```

Each toolchain adds about 3 GB to the image. They live in `/usr/local/share/lean/toolchains`, owned by root and
read-only. When the container is created they are linked into elan's home, so elan uses them without a download.
`elan toolchain uninstall` removes only the link, and the next creation links the toolchain again. Both options accept
`stable`, `beta`, `nightly`, a release such as `v4.35.0` or `v4.36.0-rc2`, or `nightly-YYYY-MM-DD`, each optionally
prefixed with `leanprover/lean4:` or `leanprover/lean4-nightly:`. Other origins, paths, and
`<repository>:lean-toolchain` references are rejected. Toolchains come from upstream's release index at
`https://release.lean-lang.org` and its download hosts, `releases.lean-lang.org` and `github.com`. Upstream publishes no
checksum or signature for them and elan verifies none, so they rely on TLS, exactly as when elan downloads them at run
time.

## The volume

Each dev container gets its own named volume, `lean-${devcontainerId}`, mounted at `/var/lib/lean`:

| Path                          | Variable            | Holds                                                    |
| ----------------------------- | ------------------- | -------------------------------------------------------- |
| `/var/lib/lean/elan`          | `ELAN_HOME`         | elan's settings and the toolchains it installs           |
| `/var/lib/lean/cache/lake`    | `LAKE_CACHE_DIR`    | Lake's artifact cache, for every toolchain               |
| `/var/lib/lean/cache/mathlib` | `MATHLIB_CACHE_DIR` | The build files Mathlib's `lake exe cache get` downloads |

All of it survives a rebuild. The volume is per dev container because toolchains are executable code: a volume shared
between projects would let one project's container change the toolchains another project runs.

To fetch Mathlib's prebuilt files once the container exists, add the command to your own configuration:

```jsonc
"postCreateCommand": "lake exe cache get"
```

The volume grows with every toolchain and Mathlib revision you use. `elan toolchain list` shows the toolchains,
`elan toolchain gc` removes those no known project uses, and `docker volume rm lean-<devcontainerId>` removes the whole
volume, also after the dev container itself is deleted.

For a non-root remote user, the feature creates a system group `lean`, adds that user, and makes the empty mount point
writable by the group, so a new volume stays writable after the dev container tooling changes the user's UID to the
host's. When a volume holds files of another UID, for example after a UID change or after root ran Lake, the
container-creation step gives them back to the remote user through passwordless `sudo`. Without it, the step prints a
warning that names `/var/lib/lean`; run `sudo chown -R -h "$(id -u):lean" /var/lib/lean` as a user who can, or remove
the volume. An existing `lean` group is used only if no other account belongs to it.

Setting `ELAN_HOME` to another directory in your own configuration moves elan's home off the volume. The feature then
neither links build-time toolchains nor sets the default toolchain there, and toolchains no longer survive a rebuild.

## Updating elan

elan's version is the feature's `elanVersion` option: pin a release or use `latest`, and rebuild. `elan self update`
writes a new elan into `$ELAN_HOME/bin`, which is not on `PATH`, so it changes nothing. elan prints a notice when a
newer release exists; the notice needs no action.

## Editor

The feature requests the `leanprover.lean4` extension, which finds elan on `PATH`. To keep the extension out of a dev
container, exclude it in your configuration:

```jsonc
"customizations": {
  "vscode": {
    "extensions": ["-leanprover.lean4"]
  }
}
```

The exclusion does not uninstall an extension that is already installed, and does not remove requests from other
sources.

## OS support

Debian- and Ubuntu-based (`apt`), RHEL- and Fedora-based (`dnf`), Arch Linux (`pacman`), and openSUSE or SUSE (`zypper`)
images on x86_64 and aarch64; any other distribution fails the build. elan and Lean toolchains need glibc, so Alpine and
other musl images are rejected. Current toolchains need glibc 2.30 or later, which rules out AlmaLinux 8 and Ubuntu
18.04. The tested images are in [test/lean/compatibility.json](../../test/lean/compatibility.json).

Missing prerequisites come from the repositories the image already configures and stay installed; the feature adds no
repository or key. On Arch Linux, installing a missing prerequisite also upgrades the image's packages (`pacman -Syu`),
because Arch supports no partial upgrade.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/lean/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
