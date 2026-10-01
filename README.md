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

| Feature                                   | Description                                                                                                                                      |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| [`pacman-packages`](src/pacman-packages/) | Installs a list of system packages with `pacman` from the repositories an Arch Linux image already configures, as part of a full system upgrade. |

## Development

Features are developed spec-first with [OpenSpec](https://openspec.dev) and tested on every image their compatibility
list names. Open the repository in its dev container, then run `just` to list the available tasks. Security issues: see
[SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
