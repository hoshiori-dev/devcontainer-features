
# OpenAI Codex (codex)

Installs the Codex CLI and preserves its home in a private project volume, including credentials, configuration, skills, and sessions.

## Example Usage

```json
"features": {
    "ghcr.io/hoshiori-dev/devcontainer-features/codex:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| version | The stable Codex release: latest, or an exact MAJOR.MINOR.PATCH version. | string | latest |

## Using Codex

Run `codex` in the VS Code or JetBrains **container terminal**. The feature installs Node 24 and the official
`@openai/codex` npm package. `version` accepts `latest` or an exact stable release; installing again selects the newly
requested release without importing or deleting account state. A release must support the native configuration API used
to select file credential storage. Unsupported releases fail before replacing the installed CLI.

Sign in with `codex login` after creating the container. Authentication never runs during the image build. The CLI
wrapper sets a private umask without changing Codex's approval or sandbox defaults.

## Project state

`~/.codex` links to `/var/lib/codex`, mounted from the named volume `codex-${devcontainerId}`. The whole Codex home,
including configuration, file credentials, sessions, companion databases, and skills, stays on that volume. Files under
`~/.agents/skills` are left alone and need separate persistence if you install user skills there.

Keep `CODEX_HOME` unset. Existing `.codex` files, directories, or links to other locations cause a clear conflict; the
feature does not overwrite or automatically migrate them. Back them up and migrate them explicitly before enabling this
feature. Existing keyring-only or managed policies that conflict with file credentials must be resolved first.
Compatible settings are preserved through Codex's own TOML configuration API.

The creation hook `/usr/local/share/codex-feature/initialize` checks the mount, home link, ownership, private
permissions, and user access once. Healthy volumes require no recursive scan. A changed UID may need noninteractive sudo
to repair only the state volume, without following external symlinks. Container creation fails with a clear error if the
mount is missing or the initializer cannot repair the volume. Ordinary restarts and editor attachments add no checks.
After changing the user, home, or mounts, recreate the container or run `/usr/local/share/codex-feature/initialize` in
the container terminal as the remote user. If ownership repair fails, an administrator must restore the volume's
ownership to that user's numeric UID/GID or provide noninteractive sudo; do not make the state directory world-writable.

This volume contains credentials and source text. Keep its root private (`0700`) and credential files private (`0600`).
Do not share it between unrelated projects or simultaneous independent users. Rebuilding a container reuses its volume;
deleting that volume loses the saved state. Moving a checkout, changing its container configuration, or switching Docker
hosts can select a different `devcontainerId`; inspect the old volume and migrate it explicitly rather than pruning it.

To identify a container's state volume, replace `CONTAINER_ID` with its ID and run:

```sh
docker inspect CONTAINER_ID --format '{{range .Mounts}}{{if eq .Destination "/var/lib/codex"}}{{.Name}}{{end}}{{end}}'
```

For an explicit migration, stop every Codex process using the source and destination. Back up the complete old Codex
home, including database companion files; keep the backup private. Move a conflicting home directory or link aside, then
let the initializer create the new home link. Copy the complete backup into the linked directory as the remote user,
remove group/other access from copied files and directories without following symlinks, and rerun the initializer. Keep
directories traversable by their owner and preserve owner execute bits on executable skills. The initializer repairs
known credential/configuration permissions; it does not scan an otherwise healthy copied tree. Verify login and
conversation restoration before deleting the backup or old volume. When changing volume identity, copy from the
identified old volume rather than an empty new one. The feature deliberately performs none of these migration steps
automatically.

## Editor integrations

The supported initial entry point is each IDE's container terminal. The official
[Codex VS Code extension](https://learn.chatgpt.com/docs/codex/ide) (`openai.chatgpt`) and
[Codex in JetBrains](https://learn.chatgpt.com/docs/codex/ide) are optional manual integrations. Their process location
and credential/session stores must be verified separately before claiming project-volume persistence; the feature does
not install them automatically or modify the host IDE profile. CLI and IDE sessions need not be shared. No community
adapter is installed.

## Authenticated rebuild verification

Before relying on saved login, sign in and complete a short CLI conversation in your container. Record only whether
`codex login status` succeeds and whether `codex resume --last` can reopen that conversation. Rebuild the container with
the same volume, run those checks again, and confirm a new request works without signing in again. Never publish tokens,
login codes, account identifiers, or conversation contents as test evidence. Automated fixture tests cover file storage
and mapping, but do not establish real account restoration.

Contributors can use `test/codex/manual/devcontainer.json` to verify the local feature. From the checkout root, run the
following commands in an interactive terminal. Choose an empty scratch workspace and keep both paths fixed throughout
the check:

```sh
workspace=/tmp/codex-login-check
mkdir -p "$workspace/.devcontainer"
cp -R src/codex "$workspace/.devcontainer/codex"
cp test/codex/manual/devcontainer.json "$workspace/.devcontainer/devcontainer.json"
config="$workspace/.devcontainer/devcontainer.json"
devcontainer up --workspace-folder "$workspace" --config "$config"
devcontainer exec --workspace-folder "$workspace" --config "$config" codex login
devcontainer exec --workspace-folder "$workspace" --config "$config" codex
```

Complete a short conversation and exit Codex. Copy `containerId` from the `up` result, inspect its volume using the
command above, and remove only that container with `docker rm --force CONTAINER_ID`. Do not remove its volume. Run the
same `up` command again, then:

```sh
devcontainer exec --workspace-folder "$workspace" --config "$config" codex login status
devcontainer exec --workspace-folder "$workspace" --config "$config" codex resume --last
```

Confirm the previous conversation opens and a new request completes. The CLI forwards the interactive terminal when run
this way. This fixture adds no CI job or host credential mount.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/hoshiori-dev/devcontainer-features/blob/main/src/codex/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
