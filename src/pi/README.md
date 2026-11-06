
# Pi (pi)

Installs the native Pi coding agent CLI and keeps its configuration, credentials, and sessions in a private project volume.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/pi:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The stable Pi release, 1.3.0 or newer: latest, or an exact MAJOR.MINOR.PATCH version. | string | latest |

## Using Pi

Run `pi` in the VS Code or JetBrains **container terminal**. `version` accepts `latest` (the newest stable release the
GitHub releases API names at build time) or an exact stable release `1.3.0` or newer, such as `1.4.0`; older releases
and prereleases are rejected. Installing again with another release replaces the CLI and keeps its state.

### Why a direct download

The feature installs upstream's native executable from the release archive instead of installing Pi with a package
manager. It reads the release from `api.github.com`, downloads `pi-linux-x64.tar.gz` or `pi-linux-arm64.tar.gz` and the
release's `SHA256SUMS` from `github.com/earendil-works/pi`, checks the archive's SHA-256, and installs the extracted
`pi` directory to `/usr/local/lib/pi` with `/usr/local/bin/pi` linked to its executable. The executable carries its own
JavaScript runtime and reads the themes and templates beside it, so the directory stays together.

Installing `@earendil-works/pi-coding-agent` with npm, or running upstream's installer (which itself installs that npm
package), would make this feature install or require Node.js 22.19 or newer and npm. That could get in the way of the
Node.js version you choose with your own Node feature. The native executable needs neither, so Node features keep their
own options and defaults. Upstream publishes no signature, so the release metadata and the checksum file rely on TLS to
GitHub. Pi cannot update this executable itself; change `version` and rebuild instead of running `pi update`.

Archives exist for glibc Linux on x86_64 and aarch64. Images outside the tested compatibility list get a warning and an
installation attempt. Pi publishes no musl build, so musl images such as Alpine are unsupported; other systems and other
CPUs fail with the reason. If the image already has another Pi at `/usr/local/bin/pi`, such as a global npm install, or
other content at `/usr/local/lib/pi`, the build stops and changes nothing; remove or move it first.

### Pi packages

`pi install npm:<package>` and `pi install git:<url>` run the `npm` (or your `npmCommand` setting) and `git` on your
`PATH`; the feature provides neither. Add a Node or git feature if you want such packages. Without npm the command fails
with `Executable not found in $PATH: "npm"`, and Pi keeps working. Packages Pi installs land in the agent directory, so
the volume keeps them.

## Project state

Pi keeps its state in its agent directory, `~/.pi/agent` by default. The feature links that whole directory to
`/var/lib/pi/agent` in the named volume `pi-${devcontainerId}`, mounted at `/var/lib/pi`. The directory holds, among
others:

| In `~/.pi/agent`                                | Holds                                                            |
| ----------------------------------------------- | ---------------------------------------------------------------- |
| `auth.json`                                     | provider API keys and OAuth credentials                          |
| `mcp-auth.json`                                 | MCP server sign-ins                                              |
| `sessions/`                                     | conversations, grouped by working directory                      |
| `settings.json`, `mcp.json`, `models.json`      | settings, package declarations, MCP servers, and model endpoints |
| `skills/`, `extensions/`, `prompts/`, `themes/` | your own resources                                               |
| `npm/`, `git/`                                  | packages `pi install` installed from npm and git                 |

The feature never sets `PI_CODING_AGENT_DIR`. If you set it, the build or initialization stops and asks you to remove
it: Pi would then keep its state outside the volume. Sessions you store elsewhere with `--session-dir`,
`PI_CODING_AGENT_SESSION_DIR`, or the `sessionDir` setting, and the project `.pi` directory in your checkout, are
outside this persistence guarantee.

An existing `~/.pi/agent` directory, a file, a dangling link, or a link to another location is a conflict: the build or
initialization stops with an error and changes nothing. Back up such content, move it aside, and migrate it explicitly.

The creation hook `/usr/local/share/pi-feature/initialize` runs once per container creation. It checks the mount, the
link at the effective home's `~/.pi/agent`, ownership, private permissions (`0700` directories, `0600` for `auth.json`
and `mcp-auth.json`), and that you can write to the agent directory. A healthy volume needs no recursive scan. When the
volume belongs to another UID, the hook repairs ownership inside `/var/lib/pi` only, through noninteractive sudo,
without following links out of it. Without sudo it fails with the reason; restore the volume's ownership to your numeric
UID and GID instead of making it world-readable. Ordinary restarts and editor attachments run no check. After changing
the user, home, or mounts, recreate the container or run the hook again in the container terminal as the remote user.

The volume holds credentials and source text. Do not share it between unrelated projects or users working at the same
time. Rebuilding a container reuses its volume; deleting the volume loses the saved state. Moving a checkout, changing
its configuration, or switching Docker hosts can select another `devcontainerId` and so an empty volume; nothing is
migrated or pruned automatically. To find a container's volume, replace `CONTAINER_ID` and run:

```sh
docker inspect CONTAINER_ID --format '{{range .Mounts}}{{if eq .Destination "/var/lib/pi"}}{{.Name}}{{end}}{{end}}'
```

To migrate, stop every Pi process, back up the old volume privately, copy its `agent` directory into the new container's
`/var/lib/pi/agent` as the remote user, remove group and other access, and run the hook. Check that your login and
sessions are back before deleting the backup.

## Authentication

Sign in after the container is created; nothing is requested or stored during the image build. In Pi, `/login` connects
a provider through its OAuth or API-key flow and saves the credential in `~/.pi/agent/auth.json`, which the volume
keeps; `pi mcp login` saves MCP sign-ins in `~/.pi/agent/mcp-auth.json`. Other choices stay yours to persist: API keys
in environment variables, an `auth.json` key that runs a command such as a secret manager (`"key": "!<command>"`),
ambient cloud credentials, and any keyring. The feature does not configure, unlock, or back them up, and keeps whatever
`auth.json` and settings select. To keep such a store, add your own entry to `mounts` in `devcontainer.json` (a named
volume or a bind mount for its directory), and pass API keys from the host with `remoteEnv`, for example
`"ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"`, or with your platform's secrets, rather than committing them. A
retained credential file does not guarantee that a provider still accepts the login: tokens can expire or be revoked.
`pi auth print-api-key` and `pi auth print-bearer-token` print secrets; never paste their output into logs or issues.

## Editor integrations

The supported entry point is the IDE's container terminal, in VS Code and in JetBrains IDEs. No first-party Pi extension
for either IDE was verified, so the feature installs no editor extension or community plugin and never edits the host
IDE's configuration. Pi run from the container terminal uses the volume-backed agent directory.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/pi/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
