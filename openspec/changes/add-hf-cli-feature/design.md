# Design

## Context

Upstream facts, read on 2026-09-30:

- **Documented method.** The installation guide's "Install the Hugging Face CLI"
  (`https://huggingface.co/docs/huggingface_hub/main/en/installation.md`) gives
  `curl -LsSf https://hf.co/cli/install.sh | bash` and says `hf update` detects how `hf` was installed. The CLI guide's
  "Standalone installer (Recommended)" (`.../main/en/guides/cli.md`) gives the same command, says the installer also
  installs the `hf-cli` skill "for Claude Code and any agent reading `~/.agents/skills`" unless `--exclude-skill` is
  passed, and that `HF_HUB_DISABLE_UPDATE_CHECK=1` silences the new-version warning.
- **Where the installer lives.** `https://hf.co/cli/install.sh` answers 307 to `https://huggingface.co/cli/install.sh`
  (583 lines, SHA-256 `e657ec04c665a308a57b626c5f4410add270861bc03cb7ad642866c832af6eb8`), byte-identical to
  `utils/installers/install.sh` of `huggingface/huggingface_hub` at `main` and at the tags `v1.33.0` and `v2.0.0`.
  GitHub's page for that file at `v2.0.0` names `https://github.com/huggingface/huggingface_hub/raw/refs/tags/v2.0.0/…`
  as its raw form, which answers 302 to
  `https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v2.0.0/…`; that URL answers 200 directly, and
  a tag that does not exist (`v2.0.1`) answers 404. The repository has branches named `v1.x-release`, none equal to a
  release tag. Git tags can be moved by the repository's maintainers; nothing upstream pins or signs the file.
- **Installer history across the stable tags `v1.0.0`–`v2.0.0`** (each tag's file fetched and hashed): it appears in
  `v1.0.0` (huggingface/huggingface_hub#3464); the uv path arrives in `v1.2.0` (huggingface/huggingface_hub#3486);
  `--exclude-skill` and the skill step arrive in `v1.27.0` (huggingface/huggingface_hub#4608); `v1.27.0`–`v1.32.0` run
  the skill step with `--claude`; `v1.33.0` and `v2.0.0` are identical. From `v1.27.0` on there are three distinct
  revisions (`6915d02a…`, `d3b44425…`, `e657ec04…`), all accepting `--force`, `--no-modify-path`, and `--exclude-skill`.
  Earlier revisions reject `--exclude-skill` with "Unknown option" and exit 1.
- **What the installer does** (`v2.0.0`): re-executes itself under bash (fails without bash); takes `python3`, then
  `python`, from `PATH` and requires 3.10 or later; checks `python -m venv --help`; uses `$HF_HOME/cli/venv`, else
  `~/.hf-cli/venv`; with `--force` removes an existing venv, otherwise reuses it; when it creates the venv, writes
  `.hf_installer_marker` into it and runs `python -m pip install --upgrade pip`; installs the unpinned `huggingface_hub`
  with `uv pip install --python <venv>/bin/python --upgrade` when `uv` is on `PATH`, else with the venv's pip, appending
  `$HF_CLI_PIP_ARGS` (or `$HF_PIP_ARGS`) unquoted; also upgrades `transformers` if the venv already holds it; links `hf`
  into `$HF_CLI_BIN_DIR` (default `~/.local/bin`) with `ln -sf`; unless `--exclude-skill`, runs
  `hf skills add hf-cli --global --force` and only warns when it fails; appends a `PATH` line to a shell rc file only
  when that directory is not on `PATH` and `--no-modify-path` is absent; finally runs `hf version`. It has no version
  option and no checksum of its own.
- **`hf update`** (`cli/system.py`, `cli/_cli_utils.py`, `utils/_runtime.py` at `v2.0.0`): `installation_method()` is
  `hf_installer` when `sys.prefix` holds `.hf_installer_marker`; the update then runs
  `bash -c "curl -LsSf https://hf.co/cli/install.sh | bash -"` (with `-s -- --exclude-skill` when no global skill is
  installed), without `--no-modify-path` or `--force`, and afterwards `hf skills update hf-cli -g`. It needs `curl`.
- **Skills.** From `1.27.0` on, `hf skills add hf-cli --global --force` generates the skill locally from the installed
  version (`_install_to`, `DEFAULT_SKILL_ID`) into `~/.agents/skills/hf-cli` and links it into `~/.claude/skills`
  (`1.27.0`–`1.32.0` through `--claude`, which those installers pass; from `1.33.0` always, honoring
  `CLAUDE_CONFIG_DIR`). The generated `SKILL.md` says "Generated with `huggingface_hub v<version>`"; upstream's own
  installer CI (`.github/workflows/check-installers.yml`) checks that line. Other skill names come from a marketplace.
- **Package.** `info.version` of `https://pypi.org/pypi/huggingface_hub/json` is `2.0.0`; `2.0.0rc0` exists; `1.16.3` is
  yanked. `huggingface_hub` requires Python `>=3.10` and ships the `hf` and `tiny-agents` scripts; the installer links
  only `hf`. Native dependencies are `hf-xet` and PyYAML, with manylinux wheels for x86_64 and aarch64.
- **Checks, tested locally** against a local simple index whose link advertised a wrong SHA-256 for a wheel: uv 0.12.21
  `uv pip install --python <venv>` failed with "Hash mismatch" and installed nothing, and installed with the true
  digest; pip 23.0.1 (Debian 12's `python3-pip-whl`, in a venv from `python3-venv`) and pip 24.0 (Ubuntu 24.04's) failed
  with "THESE PACKAGES DO NOT MATCH THE HASHES". uv 0.12.21's `uv pip install --python <venv>/bin/python` writes `uv`
  into the `INSTALLER` file of each distribution it installs. pip's documentation ("Using hashes from PyPI") calls this
  check a protection against corruption, not against tampering. uv checks index hashes from 0.12.16 on
  ([astral-sh/uv#21562](https://github.com/astral-sh/uv/pull/21562)).
- **Pinning, tested locally:** `UV_CONSTRAINT` (uv: "Equivalent to the `--constraints` command-line argument", listed
  for `uv pip install`) and `PIP_CONSTRAINT` (pip: environment variable of `--constraint`) naming a file with
  `huggingface_hub==1.33.0` made `--upgrade huggingface_hub` resolve 1.33.0, and left pip's own upgrade (26.2.1)
  untouched. `UV_NO_CONFIG` "disables the discovery of any persistent configuration", system-level included;
  `PIP_CONFIG_FILE=os.devnull` "disables the loading of all configuration files"; `UV_NO_BUILD`, `UV_NO_CACHE`, and
  `UV_COMPILE_BYTECODE` are the variables of `--no-build`, `--no-cache`, and `--compile-bytecode`.
- **End to end, tested in `debian:12` on amd64:** `python3` 3.11.2, `python3-venv`, and `ca-certificates` from apt, uv
  0.12.21 in `/usr/local/bin`, the tagged installers run as a non-root user in an environment built from the variables
  in Goals. `v1.33.0` with the skill: 1.33.0 installed through uv, marker, `~/.local/bin/hf`, the skill, and its
  `~/.claude/skills` link. Then `v2.0.0` with `--force --exclude-skill`: 2.0.0 installed, the skill generated by 1.33.0
  kept. No rc or profile line, no uv or pip cache, `installation_method()` is `hf_installer`, `/usr/local/bin/hf`
  pointing into the venv runs for root and the user and leaves no root-owned file in the venv, and
  `hf models info openai-community/gpt2` succeeds. `v1.27.0` with the skill: "Using uv", 1.27.0, skill and link. Without
  `python3-venv`, `python3 -m venv --help` succeeds but `ensurepip` is missing and creating the venv fails.
- **Images**, from each image's `dpkg` status on amd64 and arm64: neither `mcr.microsoft.com/devcontainers/base` nor
  `debian:12` has `python3`; the base image has `ca-certificates` and `curl`, `debian:12` neither. `debian:12`
  configures `deb.debian.org/debian` (`bookworm`, `bookworm-updates`) and `deb.debian.org/debian-security`; the base
  image `archive.ubuntu.com/ubuntu` (`noble`, `-updates`, `-backports`) and `security.ubuntu.com/ubuntu`
  (`noble-security`) on amd64, `ports.ubuntu.com/ubuntu-ports` on arm64.
- **The `uv` feature (#14)**, not merged; its draft installs `/usr/local/bin/uv` and sets in `containerEnv`
  `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR` under `/var/lib/uv-data` (a volume, absent at build time), `UV_TOOL_DIR`,
  `UV_TOOL_BIN_DIR` (ahead in `PATH`), and `UV_LINK_MODE`. A feature's `containerEnv` is emitted as `ENV` before its
  `install.sh` runs, so these variables are set while this feature installs. Its draft asks a feature that runs uv at
  build time to write nothing under `/var/lib/uv-data` (no managed Python there; `UV_NO_CACHE=1` or a temporary cache),
  because Docker copies the image's mount point into every new volume. Its "Later feature runs uv" scenario is observed
  in its own PR with a throwaway feature, and this change's global scenario `uv_and_hf_cli` becomes its lasting
  regression check. Its design lists as unverified whether `devcontainer features test` applies feature `mounts`.
- `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` creates `/home/vscode` with mode 0750 (`HOME_MODE 0750` in its
  `/etc/login.defs`), checked on 2026-09-30, so users other than `vscode` and root cannot reach a file under it.
- The dev container CLI's duplicate test first installs with non-default options (a boolean flipped, a string option set
  to the `proposals` entry after its default), then with defaults.

## Goals / Non-Goals

**Goals:**

- The installer is a file downloaded from
  `https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh` and
  run with `bash <file>`; nothing is piped into a shell, and nothing is fetched from `hf.co`, `huggingface.co/cli`, or a
  branch. Checked by review of `install.sh`.
- The user is `_REMOTE_USER` and the home `_REMOTE_USER_HOME` (root and root's home when the remote user is root or
  unset); a user without an entry in the image's passwd database fails before anything is downloaded. Checked by the
  failure observations below.
- The installer runs unmodified, as the remote user (root when the remote user is root or unset), in an environment
  built from nothing but `HOME`, `USER`, `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, and the
  feature's own `UV_NO_CONFIG=1`, `UV_NO_CACHE=1`, `UV_NO_BUILD=1`, `UV_COMPILE_BYTECODE=1`, `UV_CONSTRAINT`,
  `PIP_CONSTRAINT`, `PIP_CONFIG_FILE=/dev/null`, `PIP_NO_CACHE_DIR=1`, and `HF_HUB_DISABLE_UPDATE_CHECK=1`: no
  `HF_HOME`, `HF_CLI_BIN_DIR`, `HF_CLI_PIP_ARGS`, `HF_PIP_ARGS`, `CLAUDE_CONFIG_DIR`, or other `UV_*` or `PIP_*`
  variable from the build or the `uv` feature reaches it. The fixed `PATH` makes the installer take the first `python3`
  and `uv` there. Its arguments are `--no-modify-path`, plus `--exclude-skill` unless `installSkill` is enabled, plus
  `--force` unless the requested version is already installed with the marker; never `--with-transformers`. Checked by
  the `redirected_sources` scenario and review.
- The constraint file holds exactly `huggingface_hub==<version>`, lives in a temporary directory readable by the remote
  user, and is removed afterwards. After the installer, the venv's interpreter, run as the remote user, reads the
  installed version with `importlib.metadata`; a mismatch fails the build before `/usr/local/bin/hf` is written. Checked
  by `test.sh`, the `pinned_version` scenario, and `duplicate.sh`.
- `version` is matched against `^[0-9]+\.[0-9]+\.[0-9]+$` and the `1.27.0` floor before any download; `latest` is read
  with `python3`'s `json` module and passes the same match. Checked by the failure observations below and review.
- The feature's own two requests (the PyPI JSON and the installer) are made by `python3`'s `urllib` with its default TLS
  context (certificates verified against the system store), HTTPS only, following no redirect; anything but a 200 fails.
  Checked by review.
- `uv --version` of the `uv` on the installer's `PATH` is at least `0.12.16`, checked before the installer is
  downloaded. Checked by the failure observations below.
- Distribution packages: `python3`, `python3-venv`, and `ca-certificates`, only those missing, with apt lists removed
  afterwards; a `python3` below 3.10 fails before the installer is downloaded. Checked by `test.sh` (`dpkg -s`) and the
  failure observations below.
- Every file under the remote user's `~/.hf-cli` belongs to the remote user, and every build-time command that runs the
  venv's interpreter runs as that user. Checked by `test.sh` (`find ~/.hf-cli ! -user <remote user>` is empty).
- `/usr/local/bin/hf` is a root-owned symbolic link to `<home>/.hf-cli/venv/bin/hf`, replaced only after the version
  check passes. Checked by `test.sh`.
- No uv or pip cache is written, and nothing under `/var/lib/uv-data` (the `uv` feature's volume path) is touched: the
  installer's environment names no `UV_CACHE_DIR` or `UV_PYTHON_INSTALL_DIR`, and `uv pip install --python` downloads no
  interpreter. Checked by the `uv_and_hf_cli` global scenario (`/var/lib/uv-data` is empty and owned by the remote
  user), by `test.sh` (no `~/.cache/uv` or `~/.cache/pip` in root's or the remote user's home), and by review.
- With `installSkill`, `~/.agents/skills/hf-cli/SKILL.md` must exist after the installer and contain
  `huggingface_hub v<version>`, else the build fails. Checked by the `install_skill` scenario and review.
- A second install skips the installer when the marker is present, the installed version equals the requested one, and
  either `installSkill` is disabled or the skill already names that version; when only the skill is missing it runs the
  installer without `--force`, which reuses the venv, finds the constrained package satisfied, and adds the skill;
  anything else runs with `--force`. Checked by `duplicate.sh` and by installing twice with identical options in one
  container (below).
- Failure scenarios a successful build cannot show are produced in a throwaway container running `install.sh`, each
  result recorded in the PR's Validation section. The installer's fixed `PATH` puts `/usr/local/sbin` ahead of
  `/usr/local/bin`, so a stub there replaces a tool for the feature and the installer only:
  - malformed version with `2.0` and `2.0.0rc0`; below the floor with `1.26.1`; no release tag with `9.9.9`;
  - endpoint unusable with `latest` in a container without network access, prerequisites installed beforehand; the half
    where the endpoint answers something other than a version is checked by review;
  - uv too old with a `uv` stub that prints `uv 0.12.15`; uv missing with no `uv` installed;
  - release absent from PyPI with a `uv` wrapper that replaces the constraint with a release PyPI lacks and runs the
    real `uv`; installed version differs with a wrapper that drops the constraint while `1.33.0` is requested;
  - Python too old on `debian:11`, whose `python3` is 3.9;
  - skill generation fails with a root-owned `~/.agents/skills` for the non-root remote user of `base:ubuntu-24.04`;
  - unsupported distribution on an image outside the Debian and Ubuntu family (for example Fedora); unsupported
    architecture with a `uname` stub that prints another machine name; remote user missing with `_REMOTE_USER` naming no
    account;
  - same options twice by running `install.sh` twice in one container with identical options: the second run logs the
    skip and changes no file in the venv.

**Non-Goals:**

- Supporting `hf update` inside the container: it works (the environment is installer-managed), but it pipes the mutable
  `hf.co` script into bash, may edit rc files, needs `curl`, and its result is lost on rebuild. `NOTES.md` says to
  rebuild with another `version`.
- A system-wide, root-owned installation; running `hf` as users other than the remote user and root.
- An `HF_HOME` override, pre-downloading models or datasets, any authentication (issue #17), and the `transformers` CLI.
- Musl (Alpine), RPM, or other distributions in 1.0.0; each can be added later as a MINOR bump.
- Removing a skill when a later install disables `installSkill`, and installing any skill other than `hf-cli`.
- Verifying the installer's content (upstream publishes no checksum or signature for it; Decisions), locking transitive
  dependency versions, and verifying PEP 740 attestations.

## Options

The feature has two options, both new in this change; the spec's Option requirements state them.

| Name           | Type      | Default    | Enum or proposals               | Meaning                                                                                                                           |
| -------------- | --------- | ---------- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `version`      | `string`  | `"latest"` | proposals `["latest","1.33.0"]` | The `huggingface_hub` release to install: `latest`, resolved from PyPI at build time, or `MAJOR.MINOR.PATCH` at or above `1.27.0` |
| `installSkill` | `boolean` | `false`    | none                            | Let the installer add the upstream `hf-cli` agent skill for the remote user                                                       |

- **Default `latest` for `version`.** A configuration that omits `version` gets the current release, as upstream's own
  installer does, yet each build installs exactly one release and logs it; a pinned `version` gives reproducible builds.
  Proposals, not an enum: every release from the floor on is valid, and each new release adds one. `1.33.0` is the
  proposal after the default, so the duplicate test installs it with `installSkill` enabled and then the defaults
  (Context); its installer is identical to `v2.0.0`'s, and it differs from what `latest` resolves to, so the second
  install takes the `--force` path.
- **Default `false` for `installSkill`** (Open Questions, item 2). The skill changes what coding agents in the container
  read and writes into `~/.claude`, so the feature adds it only on request, although upstream's installer adds it by
  default.
- **Rejected shapes.** A token, login, or credential option (issue #17; the spec's "Take no credentials"); options for a
  package index, a mirror, or extra installer arguments (they would let configuration redirect or weaken verified
  downloads, against "Verify package downloads"; Open Questions, item 1); an `HF_HOME` location or `--with-transformers`
  option (Non-Goals); a `disableUpdateCheck` option (`containerEnv` has no option substitution; Decisions); an enum of
  releases (every upstream release would need a feature release).

## Test fixtures

Scenario jobs run on amd64 only. The `pinned_version` scenario installs `1.27.0`, the floor. The `install_skill`
scenario runs on `base:ubuntu-24.04` as `vscode`. The `redirected_sources` scenario is a `build` scenario on `debian:12`
whose Dockerfile sets `UV_DEFAULT_INDEX`, `UV_INDEX_URL`, `PIP_INDEX_URL`, `HF_CLI_PIP_ARGS`, and `HF_HOME` to unusable
values, and writes `/etc/uv/uv.toml` and `/etc/pip.conf` naming an unreachable index. Those `ENV` values stay set in the
running container, so its test asserts the venv path and the installed version, and runs `hf version` with them cleared
(`env -u`): they are the scenario's build input, not the runtime contract.

The `uv_and_hf_cli` global scenario (`test/_global/`) installs the `uv` feature and this feature, both with default
options, on `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` as `vscode`. Its test asserts that `huggingface_hub`'s
`INSTALLER` record in `~/.hf-cli/venv` is `uv`, that `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv-data/python` in the
container's environment, and that `/var/lib/uv-data` is a mount, empty, and owned by `vscode`. For the `uv` change's
(#14) "Later feature runs uv", which this scenario checks again from this change on: the build succeeding shows that a
later feature found and ran `uv` during its install, because this feature runs `uv --version` for its floor check and
fails without it; the runtime value of `UV_PYTHON_INSTALL_DIR` equals the value later features saw during their install,
because the `uv` feature's `containerEnv` is written as image `ENV` before they install (Context). This feature's
`install.sh` does not assert that variable itself, since it keeps it away from the installer.

`test.sh` and the global scenario see the `uv` feature's volume only if `devcontainer features test` applies feature
`mounts`, which the `uv` change's Risks list as unverified. If it does not, those assertions fail; the implementation
reports that before changing them, and observes the mounted-volume scenarios with `devcontainer up` instead, recorded in
the PR's Validation section. The non-empty case of "Container with the uv volume mounted" is observed that way in any
case: a dev container with both features is rebuilt with its `uv` volume kept after uv has written to it, and
`hf version` runs for the remote user.

## Decisions

- **Hugging Face's standalone installer, run by the feature** (maintainer decision). It is the method both upstream
  guides recommend, and it leaves an installation `hf update` recognizes. Rejected: `uv tool install hf` into a
  root-owned environment with a uv-managed CPython (the previous draft of this change: not the documented method, and
  `hf update` reports an unknown installation method); system `pip install` (PEP 668 blocks it on both images); pipx (a
  system Python plus another tool); Homebrew and conda (absent from the images, another package ecosystem).
- **The installer comes from `raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/…`.** The
  upstream repository controls it, and the tag matches the version being installed. Rejected: piping
  `https://hf.co/cli/install.sh` into bash, as documented (a mutable redirect, unpinned, and a partial download would
  run); downloading `hf.co/cli/install.sh` to a file (still mutable and not tied to a version); the `main` branch
  (moves); the short ref form `…/v<version>/…` (the maintainer's first template: GitHub resolves a branch of that name
  too, and GitHub's own raw link uses `refs/tags/`); a copy of the installer in `src/hf-cli/` (the installer would no
  longer match the installed version); the SHA-256 digests of reviewed installer revisions, failing on any other (hashes
  tied to upstream versions, which `feature-authoring.md` forbids without a change to that rule, and each new upstream
  revision would break `latest` until a PATCH release).
- **The installer download complies with `feature-authoring.md`'s download rules** (#36). Installer scripts: upstream
  documents the installer, the feature fetches it from the upstream repository's tag, saves it to a file, and never
  pipes it into a shell; upstream publishes no checksum or signature for it, so the spec's "Download the installer from
  the release tag" states that its content is not verified and names what the installer downloads. Sources: the URL is
  HTTPS, answers 200 without a redirect, and is named in the spec. Direct downloads relying on TLS alone (the installer
  and the latest-version answer) are stated in the spec's Requirements.
- **The download's answer is the tag check.** A 404 means no tag of that name holds the installer; the failure names the
  tag. Rejected: the GitHub REST API (`api.github.com/…/git/ref/tags/v<version>`: 60 unauthenticated requests per hour
  per IP address, shared on CI runners), and `git ls-remote` (`debian:12` has no git).
- **Pin through `UV_CONSTRAINT` and `PIP_CONSTRAINT`, then compare the installed version.** The installer runs
  unmodified, whichever package tool it picks honors the pin, and the comparison catches anything else. Rejected:
  editing the downloaded installer (diverges from upstream and breaks on each revision); `HF_CLI_PIP_ARGS` (unquoted
  word splitting, and the feature clears it); installing the version first and running the installer without `--force`
  (its `--upgrade` would move to the newest release).
- **`latest` is `info.version` of `https://pypi.org/pypi/huggingface_hub/json`**, the package the installer installs and
  the endpoint the CLI's own update check reads. Rejected: the `hf` project's JSON (not the package installed); GitHub's
  latest release (a tag can exist before its PyPI release).
- **Floor `1.27.0`.** One set of installer flags works from there on, and every accepted installer has the uv path.
  Rejected: `1.1.0` with version-dependent flags (no `--exclude-skill` before `1.27.0`, no uv path before `1.2.0`).
- **`dependsOn` the `uv` feature, kept so the installer takes its uv path.** uv checks index hashes (from 0.12.16) and
  lets the feature require wheels only. pip also checks the index hash (tested), so the dependency does not add a
  stronger trust root; it adds the uv floor, `UV_NO_BUILD`, and consistency with the collection. Rejected: letting the
  installer fall back to pip.
- **The pair's contract in a global scenario, `uv_and_hf_cli`.** It installs both features by name, so the checks both
  changes rely on (uv found and used during this install, the `uv` volume path left empty and owned by the remote user)
  live in one place that runs when either feature or `test/_global/` changes. Rejected: only this feature's `test.sh`,
  which installs `uv` implicitly through `dependsOn`, so the pair's contract would sit among this feature's own checks.
- **The distribution's `python3` and `python3-venv`, installed when missing.** Both images lack Python; apt verifies the
  packages against the image's archive keyring; the installer and `hf update` are written for a system Python. Rejected:
  a uv-managed CPython on the installer's `PATH` (the venv would depend on an interpreter directory the feature must own
  outside the `uv` volume, plus python-build-standalone downloads); `python3-full` or `python3-pip` (more than the
  installer needs); requiring users to add Python themselves.
- **The feature's requests go through `python3`'s `urllib`.** `python3` is required anyway and parses JSON. Rejected:
  `curl` plus `jq` from apt (two more packages on `debian:12`); relying on the `uv` feature's `curl` (a prerequisite of
  that feature, not an interface).
- **Per-user install for the remote user, exposed as `/usr/local/bin/hf`** (maintainer decision). The venv and marker
  belong to the user, so `hf update` and `hf skills` work for them, and the link reaches every `PATH`. Rejected: running
  the installer as root with `HF_HOME` and `HF_CLI_BIN_DIR` in `/usr/local` (a root-owned venv the user's `hf update`
  cannot change); installing into root's home for everyone (other users cannot enter `/root`).
- **An environment built from scratch instead of unsetting a list.** A list misses variables that add sources or weaken
  checks, and uv, pip, and the installer add variables over time.
- **`UV_COMPILE_BYTECODE=1`.** Bytecode is written by the user at install time, so root running the user's `hf` does not
  create root-owned `__pycache__` directories that the user's later `--force` or `hf update` could not remove.
- **The skill is the installer's step, verified afterwards.** Rejected: always `--exclude-skill` and a separate
  `hf skills add` (repeats the installer's per-version flags); trusting the installer (it only warns on failure).
- **`HF_HUB_DISABLE_UPDATE_CHECK=1` in `containerEnv`** (Open Questions, item 3). Rejected: dropping it (the daily
  notice then advertises `hf update`); a `disableUpdateCheck` option (Options).
- **Distribution family as in the `uv` feature: `ID` or `ID_LIKE` in `/etc/os-release` naming `debian` or `ubuntu`.**
  Only the prerequisites depend on the distribution, and derivatives use the same apt package names. Rejected: `ID`
  alone (refuses Mint, Pop!_OS, Kali, or Raspbian, on which the `uv` feature installs).
- **`ca-certificates` when missing.** The CLI verifies TLS against the system trust store at run time, and the feature's
  own requests need it at build time. Rejected: relying on the `uv` feature's prerequisites.

## Security review

- **Downloads and verification** (every URL in the inventory below):
  - The installer: TLS to `raw.githubusercontent.com` and a path naming the upstream release tag. Its content is not
    verified: upstream publishes no checksum or signature, and a tag can be moved. `feature-authoring.md`'s "Installer
    scripts" rule allows this, since the file is saved and run, never piped, and the spec states it (Decisions).
  - `huggingface_hub` and its dependencies: SHA-256 digests from PyPI's simple index, enforced by uv (0.12.16 or later),
    wheels only.
  - `pip`, upgraded by the installer inside the new venv: the SHA-256 digest from the index, enforced by the pip that
    `python3-venv` provides (tested), a check pip documents as protection against corruption.
  - `python3`, `python3-venv`, `ca-certificates`: apt's signed repository metadata and the image's keyrings.
  - The latest-version answer: TLS to `pypi.org` alone, as the spec's "Resolve the latest version" states, then
    validated as a version.
  - The uv binary's verification belongs to the `uv` feature.
- **Keys:** none pinned by the feature. PyPI's digests arrive over TLS from the index, so the trust root is PyPI and the
  Web PKI; for the installer it is GitHub, the Web PKI, and the upstream repository's tag.
- **Code executed at build time:** the installer (as the remote user, not as root), the packages' install steps (wheels
  only, as the remote user), and `hf version` and `hf skills add` from the installed package (as the remote user). Root
  runs only `install.sh`, apt, and the checks, and writes `/usr/local/bin/hf`.
- **Code executed at run time by root:** `/usr/local/bin/hf` runs the remote user's venv, which that user owns and can
  change, so anything running as the remote user can get code run as root the next time root runs `hf`. This is the same
  kind of trust inversion as the `uv` feature's user-writable tool directory ahead in `PATH` (Open Questions, item 7).
- **Metadata:** `dependsOn` `ghcr.io/hoshiori-dev/devcontainer-features/uv:1`; `containerEnv`
  `HF_HUB_DISABLE_UPDATE_CHECK=1`, which only silences the CLI. No `installsAfter`, `mounts`, `capAdd`, `privileged`,
  `securityOpt`, `entrypoint`, `init`, or lifecycle command.
- **Files outside the feature's link:** in the remote user's home, `~/.hf-cli/venv`, `~/.local/bin/hf`, an empty
  `~/.cache/huggingface`, and with `installSkill` `~/.agents/skills/hf-cli` and `~/.claude/skills/hf-cli`. No shell rc
  or profile file is edited.
- **Inputs:** `version` is validated before any use; `installSkill` is a boolean. No option takes a credential. The
  build environment's uv, pip, and `HF_*` variables and configuration files are not inputs.
- **Idempotency:** see Goals and the spec's "Install twice".
- **Failure behavior:** the spec's "Option version", "Resolve the latest version", "Download the installer from the
  release tag", "Pin the installed version", "Require a verifying uv", "Provide the installer's Python", "Option
  installSkill", "Refuse unsupported platforms", and the missing remote user in "Install the Hugging Face CLI with the
  standalone installer"; each fails before `/usr/local/bin/hf` is written.

## Supported images

The planned `test/hf-cli/compatibility.json`, the glibc images the `uv` feature plans to list:

| Image                                               | Architectures | `remoteUser`                                   |
| --------------------------------------------------- | ------------- | ---------------------------------------------- |
| `mcr.microsoft.com/devcontainers/base:ubuntu-24.04` | amd64, arm64  | `vscode` (the image's `devcontainer.metadata`) |
| `debian:12`                                         | amd64, arm64  | none (root)                                    |

Both images publish amd64 and arm64 manifests; neither ships `python3`, so both exercise the Python prerequisite. If the
merged `uv` feature lists a different glibc set, this list follows it before implementation.

## URL inventory

Every URL the feature's script, the installer it runs, the tools they call, or its tests access, with templates
instantiated for version `2.0.0`. Nothing is accessed at container start: the feature has no lifecycle command, the
update check is off, and the skill is generated locally. The CLI's own traffic when a user runs it is user-initiated and
outside the feature, except the requests `test.sh` makes. The pulls of the test images themselves (`mcr.microsoft.com`,
Docker Hub) are left out, as in the `uv` change's inventory.

| URL / template                                                                                                                                                                                                                                                                                                                                                                                         | Purpose                                                                                          | When                                                                                                                        | Integrity / authenticity                                                                                       | Official source evidence                                                                                                                                                                                                                                                                                                                                                               | Verified                                                                                                                                                                                                                                                                   |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `https://pypi.org/pypi/huggingface_hub/json`                                                                                                                                                                                                                                                                                                                                                           | Resolve `latest` from `info.version`                                                             | Build (when `version` is `latest`) and test                                                                                 | TLS to `pypi.org`; the value is validated as `MAJOR.MINOR.PATCH`                                               | https://docs.pypi.org/api/json/                                                                                                                                                                                                                                                                                                                                                        | 2026-09-30: 200, no redirect, `info.version` `2.0.0`                                                                                                                                                                                                                       |
| `https://raw.githubusercontent.com/huggingface/huggingface_hub/refs/tags/v<version>/utils/installers/install.sh`                                                                                                                                                                                                                                                                                       | The installer; a 404 is the tag check                                                            | Build                                                                                                                       | TLS to `raw.githubusercontent.com`; the path names the upstream release tag; no upstream checksum or signature | GitHub's page https://github.com/huggingface/huggingface_hub/blob/v2.0.0/utils/installers/install.sh names `https://github.com/huggingface/huggingface_hub/raw/refs/tags/v2.0.0/utils/installers/install.sh`, which answers 302 to this host and path                                                                                                                                  | 2026-09-30: `v2.0.0` 200, no redirect, 583 lines, SHA-256 `e657ec04…6eb8` (equal to `main` and to `huggingface.co/cli/install.sh`); `v1.27.0` 200; `v2.0.1` 404                                                                                                            |
| `https://pypi.org/simple/<project>/` for `huggingface-hub`, each dependency, and `pip`                                                                                                                                                                                                                                                                                                                 | Resolution; lists every file with its SHA-256                                                    | Build                                                                                                                       | TLS to `pypi.org`; source of the digests uv and pip enforce                                                    | https://docs.pypi.org/api/index-api/; PyPI as uv's default index: https://docs.astral.sh/uv/concepts/indexes/; pip's `--index-url` default `https://pypi.org/simple`: https://pip.pypa.io/en/stable/cli/pip_install/                                                                                                                                                                   | 2026-09-30: `/simple/huggingface-hub/` and `/simple/pip/` 200, no redirect; `huggingface_hub-2.0.0-py3-none-any.whl` listed with `b3eecb60…d6dd`, `pip-26.2.1-py3-none-any.whl` with `71138adf…ed3e`                                                                       |
| `https://files.pythonhosted.org/packages/<path>/<file>` (wheels and their `.metadata` files)                                                                                                                                                                                                                                                                                                           | Package downloads, including the `pip` wheel of the installer's pip upgrade                      | Build                                                                                                                       | SHA-256 from the simple index, checked by uv ≥ 0.12.16 (packages) and by pip (`pip` itself)                    | https://docs.pypi.org/api/ (names `files.pythonhosted.org` as the file host)                                                                                                                                                                                                                                                                                                           | 2026-09-30: `huggingface_hub-2.0.0-py3-none-any.whl`, its `.metadata`, and `pip-26.2.1-py3-none-any.whl` 200, no redirect                                                                                                                                                  |
| `http://deb.debian.org/debian` (`bookworm`, `bookworm-updates`), `http://deb.debian.org/debian-security` (`bookworm-security`)                                                                                                                                                                                                                                                                         | `python3`, `python3-venv`, `ca-certificates` when missing; the repositories the image configures | Build, `debian:12`                                                                                                          | apt checks the signed `InRelease` against the image's `debian-archive-keyring`                                 | https://www.debian.org/mirror/list ("The Debian project maintains deb.debian.org"); https://deb.debian.org/ lists `/debian-security/`                                                                                                                                                                                                                                                  | 2026-09-30: all three `InRelease` 200, no redirect                                                                                                                                                                                                                         |
| `http://archive.ubuntu.com/ubuntu` (`noble`, `-updates`, `-backports`) and `http://security.ubuntu.com/ubuntu` (`noble-security`) on amd64; `http://ports.ubuntu.com/ubuntu-ports` (all four) on arm64                                                                                                                                                                                                 | `python3`, `python3-venv` when missing; the repositories the image configures                    | Build, `base:ubuntu-24.04`                                                                                                  | apt checks the signed `InRelease` against the image's `ubuntu-archive-keyring`                                 | The image's `/etc/apt/sources.list.d/ubuntu.sources` (Ubuntu's default, `Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg`); https://ubuntu.com/project/docs/how-ubuntu-is-made/concepts/package-archive/ (Canonical) names `archive.ubuntu.com` and `security.ubuntu.com`; no Canonical page found naming `ports.ubuntu.com`, whose evidence is the image's own sources file | 2026-09-30: all eight `InRelease` 200, no redirect                                                                                                                                                                                                                         |
| `ghcr.io/hoshiori-dev/devcontainer-features/uv:1`: `https://ghcr.io/token?scope=repository:hoshiori-dev/devcontainer-features/uv:pull`, `https://ghcr.io/v2/hoshiori-dev/devcontainer-features/uv/manifests/1`, and `https://ghcr.io/v2/hoshiori-dev/devcontainer-features/uv/blobs/sha256:<digest>`, which answers 307 to `https://pkg-containers.githubusercontent.com/<path>/blobs/sha256:<digest>` | `dependsOn`, pulled by the dev container CLI                                                     | Build, for users; the repository's tests pull it from their local staging registry instead (`.agents/knowledge/testing.md`) | OCI manifest and blob digests; published by this repository's release workflow                                 | https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry (names `ghcr.io`); https://api.github.com/meta (`domains.packages` lists `*.ghcr.io` and `*.githubusercontent.com`); the ref form: https://github.com/hoshiori-dev/devcontainer-features/blob/main/.agents/knowledge/feature-authoring.md                              | 2026-09-30: the `uv` token request 403, expected: `uv` (#14) is not published yet; re-check before implementation. The same flow on the public `ghcr.io/devcontainers/features/common-utils:2`: token and manifest 200, blob 307 to `pkg-containers.githubusercontent.com` |
| The `uv` feature's downloads: rows 1–4 of the `uv` change's URL inventory (`https://github.com/astral-sh/uv/releases/…` and `https://release-assets.githubusercontent.com/…`)                                                                                                                                                                                                                          | The `uv` feature's own install, which `dependsOn` runs                                           | Build and test                                                                                                              | SHA-256 from the release's `.sha256`, checked by the `uv` feature                                              | The `uv` change's (#14) design                                                                                                                                                                                                                                                                                                                                                         | As recorded there; rows 5–8 there only when a user sets that feature's `toolsToInstall`                                                                                                                                                                                    |
| `https://huggingface.co/api/models/openai-community/gpt2`                                                                                                                                                                                                                                                                                                                                              | The anonymous Hub request of `test.sh` (`hf models info openai-community/gpt2`)                  | Test only                                                                                                                   | TLS verified by `truststore` against the system trust store                                                    | Default endpoint `_HF_DEFAULT_ENDPOINT` in https://github.com/huggingface/huggingface_hub/blob/v2.0.0/src/huggingface_hub/constants.py; `model_info` path in https://github.com/huggingface/huggingface_hub/blob/v2.0.0/src/huggingface_hub/hf_api.py; https://huggingface.co/docs/hub/api                                                                                             | 2026-09-30: 200, no redirect; the command succeeded in `debian:12` (see Context)                                                                                                                                                                                           |
| `https://hf.co/cli/install.sh`, answering 307 to `https://huggingface.co/cli/install.sh`                                                                                                                                                                                                                                                                                                               | The documented installer URL, which `hf update` pipes into bash                                  | Never by the feature or its tests; only if a user runs `hf update` in a container                                           | TLS only; mutable, not tied to a version                                                                       | https://huggingface.co/docs/huggingface_hub/main/en/installation.md; https://huggingface.co/docs/huggingface_hub/main/en/guides/cli.md                                                                                                                                                                                                                                                 | 2026-09-30: 307 to `huggingface.co`, then 200; SHA-256 `e657ec04…6eb8`                                                                                                                                                                                                     |

Not accessed: `api.github.com` (rejected tag check), python-build-standalone (no uv-managed interpreter), and the skills
marketplace (only `hf-cli` is installed, generated locally). On a Debian or Ubuntu image outside the compatibility list,
apt uses the repositories that image's own sources name; the feature adds none.

## Risks / Trade-offs

- [The installer's content is not verified, and a moved tag would change it] → accepted under `feature-authoring.md`'s
  installer-script rule, as the spec states; the file runs as the remote user, not root, with a fixed argument list and
  environment, and the version and skill checks run after it.
- [A future installer revision adds a default step, drops a flag, or changes paths] → an unknown flag or a moved venv
  fails the build visibly (the marker, version, and link checks); a new default step would run unseen until a test or
  review notices. CI tests `latest` only when this feature or its dependency changes.
- [The installer's pip upgrade is unpinned] → accepted; the file is checked against the index digest.
- [Transitive dependencies float within `huggingface_hub`'s ranges, so two builds of one `version` can differ] →
  accepted for 1.0.0.
- [`hf update` in a container pipes the mutable `hf.co` script into bash, may edit rc files, needs `curl`, and is lost
  on rebuild; with `HF_HOME` set it creates a second venv and repoints `~/.local/bin/hf` but not `/usr/local/bin/hf`] →
  the update check stays off, and `NOTES.md` says to rebuild with another `version`.
- [Users other than the remote user and root cannot run `hf` when the remote user's home is not searchable by others, as
  on `base:ubuntu-24.04` (Context)] → the per-user install is the maintainer's decision; `NOTES.md` states it.
- [Root running `hf` runs code the remote user can change] → Open Questions, item 7.
- [The `uv` feature puts `/usr/local/share/uv/bin` ahead of `/usr/local/bin` in `PATH`, so `huggingface_hub` in its
  `toolsToInstall` puts another `hf` first] → that `hf`, not this feature's, runs by name; the spec's
  `/usr/local/bin/hf` is a path, not a promise about name resolution. `NOTES.md` says not to list `huggingface_hub`
  there as well.
- [A later install with `installSkill` disabled keeps a skill that names the earlier version] → accepted, as the spec
  states; `NOTES.md` says so.
- [A volume mounted over the remote user's home, `~/.hf-cli`, or `~/.claude` hides what the build wrote there] → `hf`
  breaks or the skill link disappears; `NOTES.md` states it.
- [The image gains a system `python3`] → other tools in the container may pick it up. uv prefers an installed
  interpreter that satisfies a request, a system one included, over downloading a managed one (uv's Python discovery,
  not re-verified for this change), so a plain `uv venv` by the user would likely use `/usr/bin/python3` instead of an
  interpreter on the `uv` volume that the `uv` feature's "Runtime interpreter on the volume" relies on. `NOTES.md`
  states it and names uv's `--managed-python` flag and `UV_MANAGED_PYTHON` variable.
- [The `refs/tags/` raw path is GitHub behavior observed and linked by GitHub's own pages, not a documented API] → if it
  changes, every build fails with a message naming the tag.
- [The `uv` feature may merge with other directories, variables, or minimum version] → the installer's environment is
  built from scratch; the inventory's `uv:1` row and the supported images are re-checked when #14 merges.
- [`test.sh` compares the installed version with the endpoint at test time] → a release published between build and test
  fails the job once; a rerun passes.
- [The Hub request makes `test.sh` depend on `huggingface.co` being reachable from CI, and anonymous requests from
  shared runner addresses can be rate-limited (HTTP 429)] → accepted; it is the only check that TLS works at run time,
  and a rerun clears a rate limit.
- [A PyPI release published before its GitHub tag makes `latest` fail with "no release tag" until the tag appears] → the
  failure names the tag; pinning `version` to the previous release works meanwhile.
- [Fixing the package sources blocks users whose builds may only reach an internal index or mirror] → only proxies keep
  working; Open Questions, item 1.

## Open Questions

Decisions for the maintainer, each with a recommendation:

1. **Fix the package sources, or honor a configured index or mirror?** Recommendation: fix them, so the URL inventory is
   complete and a build environment cannot redirect the install, weaken its checks, or add installer arguments.
   Alternative: pass through uv and pip configuration, which breaks the inventory and the redirect scenario. The spec's
   "Verify package downloads" encodes the recommendation, so approving the spec decides it.
2. **`installSkill` default.** Upstream installs the skill by default; the feature does not. Recommendation: `false`,
   since the skill changes what coding agents in the container read and writes into `~/.claude`. The spec's "Option
   installSkill" writes `false`, so approving the spec decides it.
3. **Keep `HF_HUB_DISABLE_UPDATE_CHECK=1`?** Now that `hf update` recognizes the installation, the daily notice would
   offer it. Recommendation: keep it, because that update pipes the mutable `hf.co` script into bash, may edit rc files,
   needs `curl` (absent from `debian:12`), and is undone by the next rebuild, which installs the pinned `version`.
   Alternative: drop it, and let users update in place between rebuilds. The spec's "Disable the update check" encodes
   the recommendation, so approving the spec decides it.
4. **Accepted versions.** Recommendation: stable `MAJOR.MINOR.PATCH` at or above `1.27.0`, pre-releases rejected. The
   spec's "Option version" encodes it, so approving the spec decides it.
5. **Lock transitive dependencies?** Recommendation: not in 1.0.0; the top-level pin plus digest checks suffice.
6. **Images for 1.0.0.** Recommendation: the two glibc images above on amd64 and arm64. The `uv` feature plans
   `alpine:3.24`; Alpine can follow as a MINOR bump once `python3` from `apk` is shown to suit the installer.
7. **Root running the remote user's `hf`.** Recommendation: accept it, as the `uv` change recommends for its
   user-writable tool directory: the remote user of a dev container can usually become root anyway, and `NOTES.md`
   states it. The spec's "The CLI SHALL run for the remote user and for root" encodes this, so approving the spec
   decides it. Alternative: drop "and for root" from the spec and tell root in `NOTES.md` not to run `hf`; a root-owned
   venv was rejected with the per-user install (Decisions).
