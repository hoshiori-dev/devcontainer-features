## Using Antigravity CLI

Run `agy` in the VS Code or JetBrains **container terminal**. The feature reads Google's official platform manifest,
downloads the archive it names from Google's distribution bucket, checks the archive against the manifest's SHA-512, and
installs the executable to `/usr/local/share/antigravity/agy` with an `agy` launcher in `/usr/local/bin`. The launcher
sets a private umask so new state files are readable by their owner only. The manifest and archive are not signed, so
the manifest itself relies on HTTPS.

Google's `install.sh` and the `agy install` subcommand are not run, so your shell profiles stay unchanged: `agy` is
already on the default PATH. The feature has no options and always installs the version the manifest currently names.
Installing again keeps an executable that already reports that version and replaces it with a newly verified one when
the manifest names a different release. Self-updates are off by default (`AGY_CLI_DISABLE_AUTO_UPDATE=true`), so the
image's version stays fixed until you rebuild; override the variable in your configuration to allow upstream updates.

Targets outside the tested compatibility list get a warning and an installation attempt when Google publishes an archive
for them. Systems or CPUs without an official archive, an unreachable manifest, a failed digest check, or an executable
that cannot run stop the installation with the cause; a working CLI is replaced only after the new one runs. Your own
Node, Python, or other runtimes are left alone: the CLI is a single static executable.

The CLI keeps Antigravity's approval and sandbox defaults. Sign in after creating the container; the image build never
asks for or stores credentials.

## Project state

The named volume `antigravity-${devcontainerId}` is mounted at `/var/lib/antigravity`. Three Antigravity-owned
directories link into it, keeping their default locations:

| Default path                   | Volume directory                      | Holds                                                       |
| ------------------------------ | ------------------------------------- | ----------------------------------------------------------- |
| `~/.gemini/antigravity-cli`    | `/var/lib/antigravity/cli`            | Login token, settings, conversations, history, logs, caches |
| `~/.gemini/config`             | `/var/lib/antigravity/gemini-config`  | Global configuration: MCP servers, projects, plugins, hooks |
| `$XDG_CONFIG_HOME/antigravity` | `/var/lib/antigravity/plugin-secrets` | Plugin secrets (`plugin-secrets.json`)                      |

`$XDG_CONFIG_HOME` defaults to `~/.config`. The rest of `~/.gemini` and `~/.config` is not linked, so other tools' data
there, such as Gemini CLI's `settings.json` and extensions, stays in the container and is unaffected. The Antigravity
IDE's own directories (`~/.gemini/antigravity`, `~/.gemini/antigravity-ide`) are not mapped either.

Existing files, directories, or links to other locations at any of the three paths cause a clear conflict; the feature
neither overwrites nor imports them. Back them up and migrate them explicitly. Options or environment variables that
move Antigravity's data elsewhere (for example a custom log file path) are outside the persistence guarantee; only
`XDG_CONFIG_HOME` is followed.

The creation hook `/usr/local/share/antigravity-feature/initialize` runs once per container creation. It checks the
mount, the links at your effective home and `XDG_CONFIG_HOME`, ownership, private permissions, and that you can read and
write each state directory, and it creates missing links. A healthy volume needs no recursive scan. A changed UID may
need noninteractive sudo to repair ownership inside the volume, without following symlinks out of it. Container creation
fails with a clear error when the volume is missing or the repair is not possible. Ordinary restarts and editor
attachments run no checks. After changing the user, home, `XDG_CONFIG_HOME`, or mounts, recreate the container or run
`/usr/local/share/antigravity-feature/initialize` in the container terminal as the remote user. If repair fails, an
administrator must restore the volume's ownership to that user's numeric UID/GID or provide noninteractive sudo; do not
make the state directory world-readable.

This volume holds credentials and source text. The state directories stay private (`0700`) and the known credential
files (`antigravity-oauth-token`, `plugin-secrets.json`) at `0600`. Do not share the volume between unrelated projects
or simultaneous independent users. Rebuilding a container reuses its volume; deleting the volume loses the saved state.
Moving a checkout, changing its container configuration, or switching Docker hosts can select a different
`devcontainerId`; inspect the old volume and migrate it explicitly rather than pruning it.

To identify a container's state volume, replace `CONTAINER_ID` with its ID and run:

```sh
docker inspect CONTAINER_ID --format '{{range .Mounts}}{{if eq .Destination "/var/lib/antigravity"}}{{.Name}}{{end}}{{end}}'
```

For an explicit migration, stop every `agy` process using the source and destination. Back up the complete old
directories, keep the backup private, and move conflicting paths aside so the initializer can create its links. Copy the
backup into the linked directories as the remote user, remove group and other access without following symlinks, rerun
the initializer, and confirm your login and conversations before deleting the backup or the old volume.

## Authentication

You can use Google-account sign-in, a Google Cloud project with Application Default Credentials, or an API key; the
feature imposes none of them and does not change what you select. What the volume retains:

- **Google account.** Without a D-Bus session bus, as in a plain dev container, the CLI stores its login token in
  `~/.gemini/antigravity-cli/antigravity-oauth-token`, which stays on the volume. When a Secret Service keyring is
  reachable, the CLI may keep the token there instead; setting up, unlocking, and persisting that keyring is yours.
- **Application Default Credentials.** The ADC file lives in the shared gcloud configuration
  (`~/.config/gcloud/application_default_credentials.json`), which the feature does not map. Persist it yourself, for
  example with your own mount or a Google Cloud CLI feature.
- **API keys** supplied through environment variables are part of your configuration and are not stored by the feature.

Plugin credentials go to `plugin-secrets.json` in the mapped plugin-secret directory. A retained file is not the same as
a working login: tokens can expire or be revoked, and a keyring or external store is outside this feature. The feature's
automated tests cover file storage, mapping, permissions, and recreation with synthetic files only; they never sign in.

To verify your own login survives a rebuild, sign in in the container terminal, run a short conversation, and rebuild
the container with the same volume. Start `agy` again and check that it does not ask you to sign in and that
`agy --continue` reopens the conversation. Never publish tokens, login codes, account identifiers, or conversation
contents as evidence.

## Editor integrations

The supported entry point is each IDE's **container terminal**. The Google VS Code extension
(`Google.google-antigravity`) and JetBrains AI's official Antigravity agent are optional manual setups outside the
persistence guarantee: where their backend runs and where it keeps its login and conversations has not been verified, so
the feature does not install or configure them and never edits your host IDE profile. Their login and conversations may
be separate from the CLI's. No community plugin or adapter is installed.

## Checking persistence locally

Contributors can run `test/antigravity/manual/state_persistence.sh IMAGE` from the checkout, where `IMAGE` is an image
built with this checkout's feature for the `vscode` user. It creates two fresh volumes, writes synthetic credential and
plugin-secret fixtures and an MCP server entry in one container, and checks in a second container that the bytes, the
private permissions, and the entry survive, and that a third container on the other volume sees none of them. It runs
without a network, uses no real credentials, and removes only its own volumes.
