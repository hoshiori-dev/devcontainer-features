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

| Feature           | Description                                                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| [glab](src/glab/) | The GitLab CLI, installed from its checksum-verified release archive with no authentication configured.                              |
| [uv](src/uv/)     | Installs Astral's uv and uvx, optionally Python command-line tools, and keeps uv's interpreters and cache on a per-container volume. |

## Development

Features are developed spec-first with [OpenSpec](https://openspec.dev) and tested on every image their compatibility
list names. Open the repository in its dev container, then run `just` to list the available tasks. Security issues: see
[SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE)
