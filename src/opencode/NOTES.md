## Using OpenCode

Run `opencode` in the VS Code or JetBrains **container terminal**. `version` accepts `latest` (the release the `latest`
dist-tag of `@opencode/cli` names at build time) or an exact stable 2.x release such as `2.1.3`; OpenCode 1.x and
prereleases are rejected. Installing again with another release replaces the CLI and keeps its state.

### Why a direct download

The feature downloads upstream's native executable directly instead of installing it with a package manager. It is the
same single executable that upstream's v2 installer installs: the feature reads the platform package
`@opencode/cli-<target>` from `registry.npmjs.org`, checks the tarball's SHA-512 against the `dist.integrity` the
registry publishes, and installs `package/bin/opencode` to `/usr/local/bin/opencode`. Installing `@opencode/cli` with
npm instead would make this feature install or require Node.js and npm, and that could get in the way of the Node.js
version you choose with your own Node feature. The native executable needs neither, so Node features keep their own
options and defaults.

Upstream publishes no signature for these packages, so the package metadata relies on TLS to the registry. The feature
never runs upstream's installer script, which installs per user under `~/.opencode/bin` and edits shell startup files.
OpenCode's own updater does not manage an executable in `/usr/local/bin`; change `version` and rebuild instead of
running `opencode upgrade`.

The target follows upstream's installer: `linux-x64` or `linux-arm64`, with `-baseline` on x86_64 CPUs without AVX2 and
`-musl` on musl systems. Images outside the tested compatibility list get a warning and an installation attempt; other
systems and CPUs fail with the reason.

## Project state

OpenCode keeps its data, configuration, state, and cache in four XDG directories. Each is a link into the named volume
`opencode-${devcontainerId}`, mounted at `/var/lib/opencode`:

| OpenCode directory (default) | Volume directory           | Holds                                             |
| ---------------------------- | -------------------------- | ------------------------------------------------- |
| `~/.local/share/opencode`    | `/var/lib/opencode/data`   | `opencode.db` with credentials and sessions, logs |
| `~/.config/opencode`         | `/var/lib/opencode/config` | user configuration such as `opencode.json`        |
| `~/.local/state/opencode`    | `/var/lib/opencode/state`  | runtime state                                     |
| `~/.cache/opencode`          | `/var/lib/opencode/cache`  | caches and downloaded tools                       |

When `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, or `XDG_CACHE_HOME` is set, the initializer also creates the
link inside that root; the feature never sets these variables and never links a whole XDG root, so other tools' files
stay where they are. The roots must be absolute paths. Configuration that points OpenCode elsewhere, such as
`OPENCODE_CONFIG`, `OPENCODE_CONFIG_DIR`, or `OPENCODE_DB`, and project configuration in your checkout, are outside the
volume and outside this persistence guarantee.

An existing OpenCode directory, a file, a dangling link, or a link to another location is a conflict: initialization
stops with an error and changes nothing. Back up such content, move it aside, and migrate it explicitly.

The creation hook `/usr/local/share/opencode-feature/initialize` runs once per container creation. It checks the mount,
the links at the effective XDG paths, ownership, private permissions (`0700` directories, `0600` credential database),
and that you can write to each directory. A healthy volume needs no recursive scan. When the volume belongs to another
UID, the hook repairs ownership inside `/var/lib/opencode` only, through noninteractive sudo, without following links
out of it. Without sudo it fails with the reason; restore the volume's ownership to your numeric UID and GID instead of
making it world-readable. Ordinary restarts and editor attachments run no check. After changing the user, home, XDG
roots, or mounts, recreate the container or run the hook again in the container terminal as the remote user.

The volume holds credentials and source text. Do not share it between unrelated projects or users working at the same
time. Rebuilding a container reuses its volume; deleting the volume loses the saved state. Moving a checkout, changing
its configuration, or switching Docker hosts can select another `devcontainerId` and so an empty volume; nothing is
migrated or pruned automatically. To find a container's volume, replace `CONTAINER_ID` and run:

```sh
docker inspect CONTAINER_ID --format '{{range .Mounts}}{{if eq .Destination "/var/lib/opencode"}}{{.Name}}{{end}}{{end}}'
```

To migrate, stop every OpenCode process (`opencode service stop`), back up the old volume privately, copy its four
directories into the new container's `/var/lib/opencode` as the remote user, keep `opencode.db` with its `-wal` and
`-shm` files together, remove group and other access, and run the hook. Check that your login and sessions are back
before deleting the backup.

## Authentication

Sign in after the container is created; nothing is requested or stored during the image build. `opencode auth login`
connects a provider with its supported methods, such as an API key or an account login; OpenCode stores those
credentials in `opencode.db` in its data directory, which the volume keeps. API keys you supply through environment
variables, files outside the four directories, and any keyring are yours to persist; the feature does not configure,
unlock, or back them up. To keep such a store, add your own entry to `mounts` in `devcontainer.json` (a named volume or
a bind mount for the file's directory), and pass API keys from the host with `remoteEnv`, for example
`"ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"`, or with your platform's secrets, rather than committing them. A
retained database file does not guarantee that a provider still accepts the login: tokens can expire or be revoked.
`opencode auth export` prints secrets; never paste its output into logs or issues.

## Editor integrations

The supported entry point is the IDE's container terminal. Two first-party routes are optional manual setups outside the
persistence guarantee, because their container-side state has not been verified:

- The OpenCode VS Code extension `sst-dev.opencode`.
- JetBrains' built-in ACP client running `opencode acp`, as described in
  [OpenCode's ACP documentation](https://opencode.ai/docs/acp/).

When such a route runs OpenCode inside the container, it uses the same XDG directories as the CLI. The feature installs
no editor extension or community plugin and never edits the host IDE's configuration.
