<h1 align="center">devcontainer-features</h1>

<p align="center">
  <a href="https://containers.dev/implementors/features/">Dev Container Features</a> from hoshiori-dev.<br>
  Each one is published on its own to GitHub Container Registry and versioned with SemVer.
</p>

<p align="center">
  <b>English</b> · <a href="README.zh.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/hoshiori-dev/devcontainer-features/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/hoshiori-dev/devcontainer-features/actions/workflows/ci.yml/badge.svg?branch=main"></a>
  <a href="LICENSE"><img alt="License" src="https://img.shields.io/github/license/hoshiori-dev/devcontainer-features"></a>
</p>

<p align="center">
  <a href="#usage">Usage</a> · <a href="#features">Features</a> · <a href="#principles-and-auditing">Principles</a> ·
  <a href="#check-a-published-version-yourself">Audit</a> · <a href="#contributing">Contributing</a>
</p>

## Usage

Add a feature to your `devcontainer.json` by its id and major version:

```jsonc
{
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu24.04",
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/deno:1": {},
    "ghcr.io/hoshiori-dev/devcontainer-features/uv:1": {}
  }
}
```

Every reference has the form `ghcr.io/hoshiori-dev/devcontainer-features/<feature-id>:<major>`.

> [!NOTE]
> This collection is not in the [containers.dev index](https://containers.dev/features) yet, so editors do not offer its
> features in their pickers. Type the reference by hand.

A major tag such as `:1` follows new minor and patch versions: your next rebuild picks them up. Each feature's README
lists its options and limits.

## Features

<!-- features:start -->

| Feature                                                            | Description                                                                                                                                                                                                                    |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [apk-packages](src/apk-packages/README.md)                         | Installs a list of system packages with apk from the repositories the Alpine Linux image already configures.                                                                                                                   |
| [apt-packages](src/apt-packages/README.md)                         | Installs a list of system packages with apt-get from the repositories the Debian or Ubuntu image already configures.                                                                                                           |
| [colab-cli](src/colab-cli/README.md)                               | Installs the Google Colab CLI with uv and isolated Python 3.12 for the remote user.                                                                                                                                            |
| [deno](src/deno/README.md)                                         | Installs the Deno CLI, verified against its published checksums, with a shared PATH location for tools installed with deno install --global.                                                                                   |
| [dnf-packages](src/dnf-packages/README.md)                         | Installs listed system packages from the repositories the image already enables.                                                                                                                                               |
| [firewall](src/firewall/README.md)                                 | Restricts the container's outbound and forwarded traffic to an allowlist of presets, domains, and CIDRs (or keeps it from a denylist), applied with nftables and dnsmasq at every start. A guardrail, not a security boundary. |
| [glab](src/glab/README.md)                                         | Installs the GitLab CLI (glab) from its checksum-verified GitLab release archive and configures no authentication.                                                                                                             |
| [hf-cli](src/hf-cli/README.md)                                     | Installs the Hugging Face CLI with its standalone installer for the remote user, optionally with the upstream hf-cli agent skill.                                                                                              |
| [hf-mount](src/hf-mount/README.md)                                 | Installs the hf-mount daemon and its NFS and FUSE backends from upstream release binaries, to mount Hugging Face Buckets and repositories as local filesystems.                                                                |
| [nvidia-container-toolkit](src/nvidia-container-toolkit/README.md) | Installs the NVIDIA Container Toolkit from NVIDIA's signed package repository and registers the nvidia runtime with a Docker daemon in the dev container.                                                                      |
| [openspec](src/openspec/README.md)                                 | Installs the OpenSpec CLI (openspec) from the npm registry, verifying every package's integrity hash and registry signature, on a Node.js runtime it brings in as a dependency.                                                |
| [pacman-packages](src/pacman-packages/README.md)                   | Installs a list of system packages with pacman from the repositories the Arch Linux image already configures, as part of a full system upgrade.                                                                                |
| [uv](src/uv/README.md)                                             | Installs Astral's uv and uvx, optionally Python command-line tools, and keeps uv's Python interpreters and cache on a volume that survives rebuilds.                                                                           |
| [zypper-packages](src/zypper-packages/README.md)                   | Installs listed system packages from the repositories the image already enables.                                                                                                                                               |

<!-- features:end -->

## Principles and auditing

A feature's install script runs as root while your image is built, so you should not have to take our word for what it
does. We work by four principles:

- **Official sources only.** A feature downloads from hosts its upstream controls, the release platform the upstream
  publishes through, or the official registry, and adds no third-party mirror or repackaged build. System packages come
  from the repositories your image already configures. Every URL a feature requests itself is named in its
  specification, `openspec/specs/<feature-id>/spec.md`.
- **Verification wherever the upstream allows it.** When the upstream publishes a checksum or a signature, the feature
  fetches it and checks the download against it, and fails if it cannot. No feature turns off certificate or signature
  checking.
- **Scripts written to be read.** Each `install.sh` names, at the top, the URLs it fetches and the signing keys it
  trusts, and is written for someone who audits it before using it.
- **Options that do not hide behavior.** We design options so that a configuration which makes a feature run or reach
  something unusual looks unusual in the `devcontainer.json` you review.

Beyond the scripts themselves: every change goes through a pull request, and a change to a feature is tested on each
image that feature supports, including installing it twice. GitHub Actions are pinned by commit SHA. A version is
published only by the [Release workflow](.github/workflows/release.yml) on `main`, which then tags the commit
`<feature-id>/v<version>`.

### Check a published version yourself

You can compare what the registry serves with the source at the release tag, in four steps:

1. Fetch the source at the release tag `<feature-id>/v<version>`.
2. Fetch the published artifact straight from the registry.
3. Compare the two. They should be identical.
4. Pin the digest you checked, so a rebuild cannot pick up anything else.

The commands below do exactly that. Run them on Linux or inside any dev container; they need `git`, `curl`, `tar`, and
`sha256sum`.

<details>
<summary>Show the commands</summary>

```bash
(
    set -euo pipefail
    REPO=hoshiori-dev/devcontainer-features
    ID=deno
    VERSION=1.0.1

    # An empty directory, so nothing left from an earlier run can pass for a result.
    WORK=$(mktemp -d)
    cd "$WORK"

    # 1. The source this version was built from: the release tag.
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$ID/v$VERSION" \
        "https://github.com/$REPO.git" source

    # 2. The published artifact, straight from the registry.
    TOKEN=$(curl -fsSL "https://ghcr.io/token?scope=repository:$REPO/$ID:pull" |
        sed -nE 's/.*"token":"([^"]+)".*/\1/p')
    curl -fsSL -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.oci.image.manifest.v1+json" \
        "https://ghcr.io/v2/$REPO/$ID/manifests/$VERSION" -o manifest.json
    # A feature's manifest names two blobs: an empty config, then the one layer that is the feature.
    DIGESTS=$(grep -oE 'sha256:[0-9a-f]{64}' manifest.json)
    [ "$(echo "$DIGESTS" | wc -l)" -eq 2 ] || { echo "unexpected manifest: stop here" >&2; exit 1; }
    LAYER=$(echo "$DIGESTS" | tail -n 1)
    curl -fsSL -H "Authorization: Bearer $TOKEN" \
        "https://ghcr.io/v2/$REPO/$ID/blobs/$LAYER" -o feature.tar
    echo "${LAYER#sha256:}  feature.tar" | sha256sum --check

    # 3. Compare. Any difference is printed and stops here.
    mkdir published && tar -xf feature.tar -C published
    diff -r "source/src/$ID" published
    echo "identical to $ID/v$VERSION; read the source in $WORK/source/src/$ID"

    # 4. The reference to pin, so a rebuild cannot pick up anything else.
    DIGEST=$(sha256sum manifest.json | cut -d' ' -f1)
    echo "ghcr.io/$REPO/$ID@sha256:$DIGEST"
)
```

</details>

The commands stop at the first step that fails, and print the reference only after the comparison passed. Read
`install.sh`, and any `scripts/` beside it, in the directory they print before you trust it: that is what your build
runs and what it leaves to run when the container starts. Use the reference from step 4 in `devcontainer.json` in place
of the `:1` tag when you want the exact version you read. You then move to a new version by repeating the check.

> [!IMPORTANT]
> **What this does not give you**
>
> - Published artifacts carry no signature and no provenance attestation
>   ([#100](https://github.com/hoshiori-dev/devcontainer-features/issues/100)). The comparison above is the check that
>   exists today.
> - Where an upstream publishes no checksum or signature, the download relies on TLS alone. The feature's specification
>   says so for each such download.
> - A feature installs the upstream version you ask for. If the upstream itself ships a bad release, the feature
>   installs it.

## Contributing

| You are                   | Start here                         |
| ------------------------- | ---------------------------------- |
| A person contributing     | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Reporting a vulnerability | [SECURITY.md](SECURITY.md)         |
| A coding agent            | [AGENTS.md](AGENTS.md)             |

Coding agents: if you have not read [AGENTS.md](AGENTS.md) yet, read it before you do anything in this repository. It is
your entry point, and it routes you to the rules for the task at hand.

## License

[Apache License 2.0](LICENSE)
