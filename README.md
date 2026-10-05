# devcontainer-features

A collection of [Dev Container Features](https://containers.dev/implementors/features/) maintained by hoshiori-dev. Each
feature is published independently to GitHub Container Registry and versioned with SemVer.

## Usage

Reference a feature from your `devcontainer.json` by its id and major version:

```jsonc
{
  "features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/<feature-id>:1": {}
  }
}
```

Each feature's options and notes are in `src/<feature-id>/README.md`.

## Features

| Feature                                                     | Description                                                                                                                                           |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`apt-packages`](src/apt-packages/)                         | Installs a list of system packages with `apt-get` from the repositories a Debian or Ubuntu image already configures.                                  |
| [deno](src/deno/)                                           | Installs the Deno CLI, verified against its published checksums, with global tools on `PATH` for every user.                                          |
| [glab](src/glab/)                                           | The GitLab CLI, installed from its checksum-verified release archive with no authentication configured.                                               |
| [`hf-cli`](src/hf-cli/)                                     | Installs the Hugging Face CLI with its standalone installer for the remote user, optionally with its agent skill.                                     |
| [`nvidia-container-toolkit`](src/nvidia-container-toolkit/) | Installs the NVIDIA Container Toolkit from NVIDIA's signed repository and registers its runtime with a Docker daemon in the dev container.            |
| [uv](src/uv/)                                               | Installs Astral's uv and uvx, optionally Python command-line tools, and keeps uv's interpreters and cache on a per-container volume.                  |
| [dnf-packages](src/dnf-packages/)                           | Installs listed system packages with dnf.                                                                                                             |
| [apk-packages](src/apk-packages/)                           | Installs listed system packages with apk.                                                                                                             |
| [pacman-packages](src/pacman-packages/)                     | Installs listed system packages with pacman.                                                                                                          |
| [zypper-packages](src/zypper-packages/)                     | Installs listed system packages with zypper.                                                                                                          |
| [firewall](src/firewall/)                                   | Restricts a dev container's outbound traffic to an allowlist of presets, domains, and CIDRs (or keeps it from a denylist), re-applied at every start. |

## Development

Features are developed spec-first with [OpenSpec](https://openspec.dev) and tested on every image their compatibility
list names. Open the repository in its dev container, then run `just` to list the available tasks. Security issues: see
[SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
