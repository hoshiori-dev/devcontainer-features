
# Claude Code (claude-code)

Installs Claude Code and preserves application state in a private project volume.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/claude-code:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The stable Claude Code release: latest, or an exact MAJOR.MINOR.PATCH version. | string | latest |

## Usage and installation

Run `claude` in the container terminal and configure authentication yourself. Official native releases at or above
2.1.89 are installed outside the state volume. The manifest signature is checked against Anthropic's pinned signing
fingerprint, and the binary is checked against the signed SHA-256. No Node runtime is installed. Automatic native
updates are disabled by the launcher; rebuild with another version to change the installation.

## State and authentication

The project volume `claude-code-${devcontainerId}` mounts at `/var/lib/claude-code`. The remote user's `~/.claude` links
to it. The CLI launcher uses the official `CLAUDE_CONFIG_DIR` mapping to retain app configuration alongside directory
state, including `.claude.json`, credential files, settings, skills, and sessions. This override affects configuration
and skill discovery as well as credentials. Keep caller-provided `CLAUDE_CONFIG_DIR` unset.

The volume follows `devcontainerId` on one Docker host. Moving the checkout, changing its configuration, or switching
Docker hosts can select different storage. Use `docker inspect <container>` to inspect mounts and migrate volumes
explicitly when needed.

An existing `~/.claude.json` outside the mapped directory must also be migrated explicitly. Existing conflicting home
content is preserved and causes an error; back it up and migrate it explicitly before using the feature. Creation-time
initialization checks the mount, links, private permissions, and user access. Ownership repair requires root or
noninteractive sudo and stays inside the state volume. After changing users, homes, or mounts, recreate the container or
rerun `/usr/local/share/claude-code-feature/initialize` as the remote user.

Credential backends and authentication settings remain your choice. Credential files inside the mapped directory
persist; external keyrings, environment variables, and custom credential paths need separate consumer-managed storage.
The feature does not install, start, unlock, or persist a keyring. Keep the volume private and never commit credential
files. Preserving files does not establish valid authentication, refreshable tokens, or account restoration.

## Editors

The supported initial route in VS Code and JetBrains is the container terminal. Anthropic's official VS Code extension
`anthropic.claude-code` and JetBrains plugin `com.anthropic.code.plugin` are optional manual installations. Their
backend location and file mappings need separate verification; the feature installs no editor extension automatically.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/claude-code/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
