# Design

## Context

- This is the repository's first feature to declare `mounts`, and `hf-cli` (#17) will declare `dependsOn` on it. Its
  change runs Hugging Face's standalone installer as the remote user, or as root when the remote user is root or unset,
  which installs into a virtual environment in that user's home with `uv pip install --python <venv>/bin/python`, in an
  environment `hf-cli` builds with `UV_NO_CACHE=1` and without `UV_PYTHON_INSTALL_DIR` or `UV_CACHE_DIR`, so it
  downloads no uv-managed Python and writes no cache. What this feature leaves in the image and in the build environment
  is therefore a contract for later features, not only for users.
- The Dev Container spec adds a feature's `containerEnv` to the image as `ENV` before the feature's `install.sh` runs,
  so `install.sh` and every later feature already see `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR` pointing at
  `/var/lib/uv`, while the volume is not mounted during the build. Anything written there at build time lands in the
  image's mount point: Docker copies it into a new, empty volume and hides it behind an existing one.
- When Docker creates a container with a named volume over an image directory, it copies that directory's contents and
  the directory's own owner, group, and mode, the setgid bit included, into the volume, by number and only while the
  volume is empty (moby `populateVolumes` and `copyExistingContents` into containerd continuity `fs.CopyDir`, which
  calls `os.Chmod` with the source mode and, in `copyFileInfo`, `os.Lchown` with both IDs; disabled by `volume-nocopy`;
  https://github.com/moby/moby/blob/docker-v29.8.1/daemon/container/container_unix.go,
  https://github.com/containerd/continuity/blob/v0.5.0/fs/copy.go and `fs/copy_linux.go` beside it). Docker's
  documentation (https://docs.docker.com/engine/storage/volumes/) states only the copy of the contents; owner, group,
  and mode rest on that source and on the observations below. A mount point that belongs to the group `uv` with a
  group-writable mode therefore yields a volume the members of `uv` can write, with no entrypoint.
- Facts verified on 2026-09-30 against uv 0.12.21 (released 2026-09-29), the newest release:
  - Release tags have no `v` prefix. Each Linux archive `uv-<triple>.tar.gz` holds `uv-<triple>/uv` and
    `uv-<triple>/uvx` (mode 0755) and has a `<archive>.sha256` beside it in `sha256sum` text format (`<hex>  <name>`);
    for all four x86_64/aarch64 gnu/musl archives the checksum files equal the GitHub API's `digest` field, and
    `sha256sum -c` passed on the downloaded x86_64-gnu and aarch64-musl archives. The musl builds are fully static. uv
    publishes no GPG signature; GitHub artifact attestations exist for the archives.
  - The gnu builds need glibc 2.17 (x86_64) or 2.28 (aarch64) (uv's platform policy).
  - `uv --version` prints `uv <version> (<target triple>)`, which exposes both the release and the build.
  - `uv tool install` prefers a Python found on `PATH` unless managed Python is required (`UV_MANAGED_PYTHON=1`); with
    it, uv downloads a managed CPython first from `https://releases.astral.sh/github/python-build-standalone/...` and
    falls back to the same path on GitHub, checking the SHA-256 compiled into the uv binary (`HashMismatch` in
    `crates/uv-python/src/downloads.rs`). In uv 0.12.21's `download-metadata.json`, all 2828 CPython entries for Linux
    x86_64/aarch64 gnu/musl carry a SHA-256; the 5 of 5646 entries without one are wasm32 emscripten builds.
  - A tool environment links to the patch-level interpreter directory; a `uv venv` environment links to the minor-level
    directory (`cpython-3.14-...`), so a patch upgrade on the volume keeps it working, except for an environment created
    with a patch version pinned (`uv venv -p 3.x.y`), which keeps that patch.
  - Tool packages come from `https://pypi.org/simple/` and `https://files.pythonhosted.org/`. Since uv 0.12.16
    (CHANGELOG, uv PR #21562), uv checks downloaded wheels and source distributions against the hashes the index
    supplies; PyPI lists a SHA-256 for each file it links. Earlier releases do not check index-supplied hashes by
    default, and `uv tool install` has no `--require-hashes` flag. A tool install writes nothing to `$HOME` when
    `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_PYTHON_INSTALL_DIR`, and `UV_CACHE_DIR` are set.
  - Installing an already installed tool again exits 0 and changes nothing; installing it with a different constraint
    (`pkg==X` or `pkg@X`) reinstalls it to satisfy the new constraint; an unconstrained repeat keeps the installed
    version.
  - With the cache and the target environment on different filesystems and no `UV_LINK_MODE`, uv prints "Failed to
    hardlink files; falling back to full copy" on every install; with `UV_LINK_MODE=copy` it prints nothing.
  - `mcr.microsoft.com/devcontainers/base:ubuntu24.04` ships curl, tar, `sha256sum`, CA certificates, and bash, and no
    `python3`. `debian:12` and `alpine:3.24`, pulled from the `public.ecr.aws/docker/library` mirror because Docker Hub
    rate-limited the pull: `debian:12` has tar, `sha256sum`, and bash, and lacks curl, wget, and CA certificates;
    `alpine:3.24` has busybox `wget`, tar, `sha256sum`, and CA certificates, and lacks curl and bash; root's login shell
    is `/bin/bash` and `/bin/sh` respectively.
  - `almalinux:10` (`ID_LIKE="rhel centos fedora"`, glibc 2.39), `archlinux:latest` (`ID=arch`, glibc 2.44), and
    `opensuse/leap:16.0` (`ID_LIKE="suse opensuse"`, glibc 2.40) ship curl, tar, `sha256sum`, CA certificates, and bash;
    their curl reads the `releases/latest` redirect with `--proto '=https' --proto-redir '=https'` (302 to the 0.12.21
    tag), and root's login shell is bash. `almalinux:10` and `opensuse/leap:16.0` publish amd64 and arm64 images;
    `archlinux:latest` publishes amd64 only (`docker buildx imagetools inspect`). The Arch image ships no package
    database, so `pacman -S` finds no package until a `-Sy`, and Arch supports a sync only together with a full upgrade
    (`-Syu`). Photon OS (`photon:5.0`, `ID=photon`, no `ID_LIKE`) belongs to none of the families.
  - `/etc/profile` of `debian:12`, `alpine:3.24`, and `opensuse/leap:16.0` sets `PATH` to a fixed list, so a login shell
    started inside the container drops a directory that `containerEnv` put in `PATH`; `/etc/profile` of the Ubuntu base
    image, `almalinux:10`, and `archlinux:latest` does not. Every profile sources `/etc/profile.d/*.sh` afterwards, and
    a snippet there that adds the directory when it is missing restored it on all six images, for `sh -l`, `bash -li`,
    and a login shell started with an empty environment. The devcontainer CLI (0.89.0) merges the container's `PATH`
    back into the environment its `userEnvProbe` reads from a login shell, so processes the CLI starts
    (`devcontainer exec`, the test scripts, the editor's server) keep the directory without the snippet.
  - The CLI's `dev-container-features-test-lib` (0.89.0) is a bash script (`#!/bin/bash`, arrays), and the CLI runs
    `./test.sh` and `./<scenario>.sh` through `devcontainer exec`, so the script's shebang decides the interpreter.
- Facts verified on 2026-10-01 for write access when the remote user's UID changes, with the Dev Container CLI 0.89.0,
  Docker 29.8.1 (containerd image store), and uv 0.12.21, on amd64:
  - `updateRemoteUserUID` is a property of the user's `devcontainer.json` that defaults to `true`
    (https://containers.dev/implementors/json_reference/); the properties a feature's metadata may set do not include it
    (https://github.com/devcontainers/spec/blob/main/docs/specs/devcontainer-features.md). On a Linux host, for a remote
    user that is neither `root` nor numeric, the CLI builds an image `<image>-uid` from its
    `scripts/updateUID.Dockerfile` with the UID and GID of the CLI's own process, whether or not they differ from the
    remote user's, so the image name is no evidence of a change; `devcontainer features test` starts its containers with
    that default on (https://github.com/devcontainers/cli/blob/v0.89.0/src/spec-node/containerFeatures.ts,
    `src/spec-common/cliHost.ts`, and `src/spec-node/featuresCLI/utils.ts` at the same tag).
  - That Dockerfile (https://github.com/devcontainers/cli/blob/v0.89.0/scripts/updateUID.Dockerfile) changes nothing
    when the remote user's UID and GID already equal the host's or when another user has the host's UID. Otherwise it
    rewrites the user's UID and primary GID in `/etc/passwd`, rewrites in `/etc/group` the ID of the lines that carry
    the old primary GID, and runs `chown -R` on the home folder only; when another group has the host's GID, the primary
    GID stays. Member lists in `/etc/group` name users, and no other group's ID changes, so a supplementary group
    survives the step, and nothing outside the home folder gets the new UID.
  - The failure this revision answers: in run
    https://github.com/hoshiori-dev/devcontainer-features/actions/runs/36798180381 the `uv` jobs on the Ubuntu base
    image, the only compatibility image with a non-root remote user, failed on amd64 and arm64 ("the volume is owned by
    the remote user", and in the `tools` and `runtime_python` scenarios "Failed to initialize cache at
    `/var/lib/uv/cache`" with permission denied), while every root image passed. The logs print no UID. That the
    runner's user has UID 1001 is inferred from the runner images' announcement
    (https://github.com/actions/runner-images/issues/10936), not from GitHub's documentation, and its GID is unknown.
    The local dev container runs the CLI as UID 1000, the UID of `vscode` in that image, so the step changes nothing
    there and the same tests pass.
  - The failure reproduces by hand: the image built with the owner-based layout, then the CLI's `updateUID.Dockerfile`
    with 1001:1001, a new named volume, and commands through `docker exec -u vscode`, leaves `/var/lib/uv` and
    `/usr/local/share/uv` with the numeric owner 1000 and mode 0755, and 13 of 15 uv operations fail with the errors
    above; the same image without the UID change passes 15 of 15.
  - With the group layout of Decisions, the same procedure passed on all six compatibility images (as `vscode` on the
    Ubuntu base image, as a user created with UID 1000 on the five others, with umask 022): a new volume carries the
    build-time UID, the group `uv`, and mode 2775; `id` lists `uv` for the remote user after the UID change; and 16 of
    16 uv operations succeed, among them `uv venv --managed-python` with a download to the volume, `uv pip install`,
    `uv tool install` of a new tool, `uv tool upgrade` of a build-time tool to another version,
    `uv tool install --reinstall` and `uv tool uninstall` of build-time tools, `uv python install` and `uninstall`, and
    `uv cache clean`. Group write on files, not only on directories, is needed: uv rewrites a build-time tool's
    `uv-receipt.toml` in place.
  - Every compatibility image ships what the group needs, so nothing is installed for it: `groupadd` and `usermod` on
    the Ubuntu base image, `debian:12`, `almalinux:10`, `archlinux:latest`, and `opensuse/leap:16.0`; on `alpine:3.24`
    only BusyBox `addgroup` (`addgroup -S <group>`, `addgroup <user> <group>`). Debian's own `addgroup` rejects `-S`
    (exit 51), and `groupadd` (exit 9) and BusyBox `addgroup -S` (exit 1) fail on a group that exists, while a repeated
    `usermod -aG` or BusyBox `addgroup <user> <group>` exits 0 and adds no duplicate. `opensuse/leap:16.0` ships no
    `find`: a first prototype that set modes with `find` failed its build there.
  - Cases measured with the same procedure: a root remote user gets no group and root-owned directories; a group `uv`
    that already exists, without a member or with the user as its only one, is reused with its ID; a host GID equal to
    the ID of `uv` keeps the user's primary GID and still works; a second install adds no second group line or member; a
    user outside the group cannot write either location, still runs installed tools, and cannot run uv with the
    feature's cache location; a group `uv` that is the remote user's primary group loses its access with the UID change,
    because its ID changes while the directories keep the old one; `docker exec -u <user>:<group>` drops supplementary
    groups, and with them the access.
  - What the remote user creates at runtime under umask 022 gets the group `uv` (setgid on every directory) but no group
    write. A second, different UID therefore cannot use a volume the first one filled, whether or not it is a member of
    `uv`, and passes with umask 002 for both. This item recorded "15 of 16" operations passing for the second UID
    before; the facts of 2026-10-01 on a volume that outlives its user, below, replace that count, which came from a
    second user that began with an empty cache.
  - A tool's first run does the same in the image's directories: Python writes `__pycache__` directories and `.pyc`
    files into the interpreter and the tool environments. On the Ubuntu base image, after the UID change, no entry under
    `/usr/local/share/uv` lacked group write before a tool ran, and 77 did after `pycowsay` and `pyjoke` had each run
    once as the remote user under umask 022.
  - uv creates its lock files with mode 0666 under umask 022: at build time, as root, `tools/.lock` and `python/.lock`
    under `/usr/local/share/uv`, the only two entries there writable by others; at runtime `python/.lock` and
    `cache/.lock` on the volume. uv keeps the mode of a lock file that exists: with other-write removed after the tools
    were installed (one recursive `chmod g+w,o-w`, with GNU and with BusyBox `chmod`), the two files stayed 0664 through
    the 16 operations, which passed as the remote user after the UID change on the Ubuntu base image and on
    `alpine:3.24`, and nothing under `/usr/local/share/uv` was writable by others before or after them. For a root
    remote user on `alpine:3.24`, `chmod -R go-w` left the two files 0644 and no entry writable by group or others, and
    root reinstalled a tool. The price: a user outside the group, who could run `uv tool list` with a cache of its own
    while the lock was 0666, no longer can (uv fails to create a temporary file in the tool directory); the tools still
    run for that user.
  - A member of `uv` other than the remote user has the same access: on the Ubuntu base image a second listed member,
    and an account whose primary group is `uv`, which the member list in `/etc/group` does not show, each created and
    removed a file in `/usr/local/share/uv/bin`, and the listed member renamed and put back `python/` on the volume, a
    directory it did not own.
  - The build-time UID, which after the UID change belongs to no account, can be given out again: on `alpine:3.24`, with
    the remote user changed from 1000 to 1001, BusyBox `adduser -D` gave the next account UID 1000, the first free one
    from 1000, and that account, the owner of both locations by number, wrote both; an account created with UID 1002
    could not. shadow `useradd` on the Ubuntu base image gave the next account 1002.
  - With root as the owner of both locations instead of the remote user, and the same group and modes, the remote user
    is never the owner; the 16 operations passed that way on `alpine:3.24` without a UID change, and an account created
    afterwards could not write (Open Questions, item 11).
  - A volume from the owner-based layout that is still empty is copied into again and works; one that already holds data
    keeps owner 1000 and mode 0755 and fails after a UID change, as it did before this revision.
  - The first-party features use the same pattern for image directories, at commit
    `9640551520736897481d83e92082186e4d812d50` of https://github.com/devcontainers/features: a group named after the
    tool, the user added to it, the tree owned `<user>:<group>` and group-writable with setgid directories (`node`,
    `python`, `rust`, `go`, `conda`, `ruby`, `java`); `node`'s `install.sh` gives the UID change as the reason. None
    uses an entrypoint or a lifecycle command for it. Only `ruby` falls back to BusyBox `addgroup` and skips root, and
    none applies the pattern to a volume's mount point, which here rests on the Docker facts above (moby
    `docker-v29.8.1` with continuity v0.5.0, the same call chain in `v28.0.4`, the engine the CI runner image lists, and
    a local run in which a new volume, and an existing empty one, took `1000:<gid> 2775` from the image while a volume
    holding one file was left alone).
  - Not verified: a real `devcontainer up` with a changed UID (the UID step was applied by hand, the way the CLI's
    source does it), arm64, the CI runners and their actual UID and GID, Podman, rootless Docker and user-namespace
    remapping, other implementations of the specification, the `changed_uid` scenario of Goals, the four failures this
    revision adds ("Group is the remote user's primary group", "Group has other members", "Group cannot be created",
    "Remote user cannot be added to the group"), a rebuild in which the group `uv` gets another ID (Risks), the removal
    of other-write on the four compatibility images other than the Ubuntu base image and `alpine:3.24`, and whether a uv
    release other than 0.12.21 keeps the mode of an existing lock file.
- Facts verified on 2026-10-01 for a volume that outlives its user and for repairing it, with uv 0.12.21, the Dev
  Container CLI 0.89.0, and Docker 29.8.1 (containerd image store) on amd64 under WSL2. The runs used hand-built images
  and prototype features with the layout of Decisions, not this change's `install.sh`. Unless an item says otherwise,
  each outcome was observed in one run and again in a second, independent one with its own images, volumes, scripts, and
  list of operations, with umask 022 set and printed in every command; counts, lists, and timings are those of one run.
  - What the volume buys. An environment links its interpreter by absolute path into `UV_PYTHON_INSTALL_DIR`, and uv has
    no option that copies the interpreter into the environment (https://docs.astral.sh/uv/reference/storage/, "they will
    keep referring to the old location"; https://github.com/astral-sh/uv/issues/17754, "This is not yet supported").
    Without persisted interpreters, a rebuild leaves `.venv/bin/python` dangling in a project and in a `uv venv`
    environment alike, and every direct use fails: the interpreter and console scripts with exit 127, and with them a
    pre-commit hook and a Makefile target. `uv sync` and `uv run` recover a project by downloading the interpreter again
    (34.6 MiB for CPython 3.14.7), removing the environment, and recreating it from the lockfile, which drops packages
    installed outside the lockfile and fails offline; `uv pip` and `uv venv` do not recover a `uv venv` environment, and
    `uv venv --clear`, which uv suggests, empties it. `uv python install <version>`, with the `version_info` of the
    environment's `pyvenv.cfg`, restores either kind in place with its packages (2.0 to 3.2 s, the same download);
    without the version, and without a `.python-version` that names it, uv installs its newest default and repairs
    nothing unless that is the environment's minor version. With the volume and the group layout, on a real
    `devcontainer up --remove-existing-container`, both environments worked offline after the rebuild, nothing was
    recreated, and `uv run` took 20 ms.
  - The alternatives to the volume, one run each. Interpreters installed into the image at build time keep an
    environment across a rebuild, also through a patch upgrade of the image's interpreter (the minor-version link
    follows), but an environment pinned to a patch, or one that needs a version the image lacks, dangles as above. An
    environment on the image's system Python does not dangle until the base image changes its minor version (3.10 to
    3.12); then a project cannot recover under `only-system`, and a `uv venv` environment runs without its packages and
    without an error. With only the cache on the volume, every rebuild downloads each interpreter again. With only the
    interpreters on the volume and the cache in the container, a second UID runs `uv sync`, `uv run`, `uv pip install`,
    and `uv venv`, and fails only at `uv python install`; every rebuild then downloads every package again.
  - The trigger is a changed numeric UID, not a changed name. With the same workspace and volume on a host whose user
    has UID 1000: a second account beside one that holds the host's UID (`vscode` 1000, then `dev2` 1001; the CLI's UID
    step reports "User with UID exists (vscode=1000)", read by replaying its build command, and changes nothing) fails 8
    of 9 uv operations; so does an account built with UID 1234 under `updateRemoteUserUID: false`, and `vscode` on a
    volume that root created and filled. An account with another name and the same UID, and an account built with UID
    1234 that the CLI changes to the host's UID, pass 9 of 9; with the host UID faked as 2000 in the real CLI, `vscode`
    and `dev2` both became 2000 and passed. Root as remote user passes and leaves root-owned entries, on which `vscode`
    afterwards fails `uv python install`, `uv cache clean`, and, with exit status 0, `uv python uninstall`. The same
    remote user leaves such entries with `sudo uv` (5,265 of them in one run, with the top-level directories still its
    own; one run).
  - What fails for a second UID on a volume the first filled under umask 022 (16,777 entries, of which 13,582 of the
    13,603 that are not symbolic links lack group write): 21 of 24 uv operations, as a member of `uv`, as a non-member
    that was given the three top-level directories, and as `vscode` after root. Every command that initializes the cache
    stops at "Failed to initialize cache at `/var/lib/uv/cache`", because uv opens the existing file
    `cache/sdists-v9/.git` for writing; `uv cache prune` and `uv cache clean` fail on the first entry they cannot
    remove, and `uv python uninstall` prints "Failed to uninstall" and exits 0. `uv cache dir` passes, and so does the
    interpreter of an existing workspace `.venv/` run directly: interpreters stay readable and executable. With
    `UV_NO_CACHE=1`, or `UV_CACHE_DIR` in the user's home, 17 of 24 pass; managing interpreters still fails. A failing
    command changed nothing on the volume. "15 of 16" above is this failure after the cache directory was removed: when
    the first user's last command is `uv cache clean`, the second user recreates `cache/` under the group-writable
    volume root, and only `uv python install` fails. That the earlier run ended so is inferred from its list of
    operations.
  - What makes the volume usable again. `chown -R <uid>` on the volume: 24 of 24, also for a user outside the group, and
    packages install offline from the cache the first user filled. Group write on every directory and on the 16 files uv
    rewrites in place (`sdists-v9/.git`, and in each interpreter `EXTERNALLY-MANAGED`, `_sysconfigdata_*.py`,
    `pkgconfig/*.pc`, `BUILD`): 24 of 24, and nothing less. Neither lasts through the next change of user: after
    `chown -R` the first user fails as the second did, and after `chmod -R g+w` what the second user creates lacks group
    write again, so the first user and a third fail on those entries. A default ACL for the group, set on the root of an
    empty volume by root at runtime, kept three UIDs working in both directions under umask 022, with the limits that it
    needs the `acl` package for `setfacl`, that an ACL set at build time reaches neither the image nor a new volume,
    that a file created with a restrictive mode gets an effective `r--` for the group (one wheel a source build left),
    and that it follows the group's ID: with `uv` given another ID, the member failed at once. A wrapper that runs uv
    under umask 002 keeps a volume filled through it usable for the cache, not for interpreters that were run directly,
    whose `__pycache__` Python writes under the user's own umask, and does not repair a volume filled without it.
  - `chown -R` on a named volume is cheap, and on an image layer it is not. On a volume of 90,144 entries and 8.0 GB
    (three interpreters and the cache of five projects): 0.2 to 0.5 s with a warm page cache and 2.0 to 2.5 s after
    dropping it; on 222,561 entries, 2.8 to 2.9 s cold (a copy on a loop device with direct I/O, as for the cold figure
    of the walk below); on a synthetic tree of 1,001,001 entries, 1.7 to 1.9 s warm and 6.0 s cold (a flat tree of small
    files; the real trees above were two to four times slower per entry when cold). A walk that only looks
    (`find ! -user <uid> -print -quit` on a volume in which nothing matches) costs the same as a `chown -R` that changes
    nothing: 0.2 s warm and 2.7 to 2.9 s cold on 123,567 entries. A single `stat` takes 1 ms. The same 8.0 GB tree in an
    image layer took 113 to 128 s and grew the container's writable layer by 8.28 GB, once per container, because
    overlayfs copies each file up; that is `/usr/local/share/uv` here, never the volume. GNU coreutils 9.4 and BusyBox
    1.37.0 `chown -R` change a symbolic link itself and never its target, and visit a directory after its contents, so
    an interrupted run leaves the top level unchanged. GNU `chown -R` also clears set-user-ID and set-group-ID bits on
    executable regular files, keeps setgid on directories, and descends into mounts below the tree (one run). `chown`
    refreshes every entry's ctime even when the owner stays, after which uv probes its interpreters again ("Ignoring
    stale interpreter markers", one run). uv running as the earlier UID while the owner changes fails at once with the
    cache error (12 of 12, one run), and `chown -R` exits non-zero when uv removes files under it (23 of 1,443 runs, in
    one run with uv as the new UID); the contents stayed intact.
  - Lifecycle commands. A feature may declare `onCreateCommand`, `updateContentCommand`, `postCreateCommand`,
    `postStartCommand`, and `postAttachCommand`; they run before the user's command of the same name
    (https://containers.dev/implementors/features/, "Commands provided by Features are always executed before any
    user-provided lifecycle commands"), as the remote user with its supplementary groups, umask 0022, and the volume
    mounted (https://containers.dev/implementors/spec/, "Remote User: Used to run the lifecycle scripts inside the
    container"; observed). `onCreateCommand` runs once per container, so again after a rebuild; the CLI keeps its
    markers in the remote user's home (`~/.devcontainer/.onCreateCommandMarker`), so it also runs when `remoteUser` is
    edited and `devcontainer up` is run again without a rebuild, as the new user, who is then not in the group `uv`, and
    not when `remoteUser` is changed back to an account that already has its marker. `devcontainer up` waits for it.
    When a lifecycle command exits non-zero, `devcontainer up` ends with `"outcome":"error"`, skips the commands after
    it, the user's included, and does not run it again on the next `up`, because the marker is written first.
    `devcontainer up --prebuild` stops after `updateContentCommand`. A feature cannot set `waitFor`.
  - A feature's `entrypoint` runs at every container start as the container user: root on
    `mcr.microsoft.com/devcontainers/base:ubuntu24.04` (`Config.User` root, `remoteUser` `vscode`), and the image's user
    when its Dockerfile ends with `USER <account>` or `containerUser` names one. The CLI does not wait for it: it goes
    on when the container prints "Container started", which the generated command prints before the entrypoints, so with
    an entrypoint that took 10 s the feature's `onCreateCommand` ran uv, and failed, about 10 s before the entrypoint's
    `chown` finished. A root entrypoint repaired the volume without sudo (9 to 66 ms), and the race went away when the
    entrypoint wrote a marker per container start and a lifecycle command waited for it (one run, on `debian:12`).
  - sudo. `vscode` on the Ubuntu base image passes `sudo -n true`. An account added to that image with `useradd` gets
    "sudo: a password is required", and without `-n`, "a terminal is required to read the password", after 27 ms and
    without hanging. `debian:12` with an account made by hand has no `sudo` (exit 127). The specification promises no
    sudo; the first-party `common-utils` feature writes a `NOPASSWD` rule for the account it creates (read in its
    `main.sh`, not run).
  - The repair as a lifecycle command. A first prototype, `sudo -n chown -R <uid>:uv /var/lib/uv` behind a check of one
    directory's owner or behind a walk, passing on sudo's exit status, repaired the volume in `onCreateCommand`,
    `postCreateCommand`, and `postStartCommand` alike (28 to 145 ms on 8,504 entries); afterwards the uv operations on
    the volume passed, and the one that still failed wrote into a workspace `.venv/` the earlier UID owned. It skipped a
    volume that fits in 2 to 3 ms with the `stat` and in 13 to 15 ms with the walk. Without passwordless sudo it made
    `devcontainer up` exit 1, with `sudo -n` and with plain `sudo` alike, and for a root remote user, whose image has no
    group `uv`, it failed on `chown: invalid group: '0:uv'`. The candidate, which skips root, skips a volume that fits,
    runs the `chown` only after `sudo -n true` passed, otherwise prints a warning, and always exits 0, ran as a
    `postStartCommand` only: it repaired a volume another UID filled, one that root created, and one with root-owned
    entries, which the check of one directory's owner missed; it left a new volume alone whose root has the build-time
    UID; and without passwordless sudo `devcontainer up` exited 0 and showed the warning. In the second run, a hook of
    its own, a walk and then `sudo -n chown -R`, repaired the volume in `onCreateCommand` (24 ms). On
    `opensuse/leap:16.0`, which ships no `find`, the candidate's walk found nothing and reported a volume that fits
    while the user could not write it.
  - Precedent. VS Code's documentation recommends a `postCreateCommand` with `sudo chown` for a named volume whose owner
    the UID update left behind (https://code.visualstudio.com/remote/advancedcontainers/persist-bash-history,
    `sudo chown -R $(whoami): /commandhistory`). The first-party `powershell` feature mounts a `${devcontainerId}`
    volume and declares an `onCreateCommand` whose script does nothing when the mount point's owner matches, runs
    `chown -R` as root, runs `sudo chown -R` where `sudo` exists, and otherwise prints a warning
    (https://github.com/devcontainers/features/blob/9640551520736897481d83e92082186e4d812d50/src/powershell/oncreate.sh);
    the survey above, of image directories, did not cover it. Of 55 feature manifests with the id `uv` that a code
    search returned, five keep uv's state on a volume or in the home; one runs `chown -R` on its cache volume from an
    entrypoint at every start, and one makes its volume's mount point writable by every user.
  - The volume's lifetime. Its name stayed the same through about 30 rebuilds and through changes to `devcontainer.json`
    (`remoteUser` and `updateRemoteUserUID` among them), to the image, and to the feature. It changed when the workspace
    folder was renamed or the configuration file moved, and with a custom `--id-label`; renaming the folder back
    returned the earlier volume. Nothing removed a volume. With `dockerComposeFile`, Compose prefixes the volume's name
    with its project name (`<folder>_devcontainer` by default) and `docker compose down -v` removes it (observed through
    the CLI); a Codespaces full rebuild discards volumes (read, not run). After the volume is removed, every workspace
    `.venv/` dangles as in the first item.
  - Not verified: the lifecycle command and the repair through this change's `install.sh` and through
    `devcontainer features test`; the candidate as an `onCreateCommand`, and a `chown` to the UID alone; the volume a
    Codespaces prebuild's `onCreateCommand` sees; the VS Code extension and Codespaces (when a terminal opens relative
    to `onCreateCommand`, and where the warning shows); macOS and Windows hosts, on which the CLI changes no UID (read
    in its source); Podman, rootless Docker, and user-namespace remapping; arm64; `dockerComposeFile` and
    `overrideCommand: false`; the walk on the compatibility images other than the Ubuntu base image and `debian:12`, and
    a replacement for `find` on `opensuse/leap:16.0`; that `chown -R <uid>:uv` also repairs a volume whose group number
    no longer is the ID of `uv` (inferred); a slow or networked disk; a uv release other than 0.12.21.

## Goals / Non-Goals

**Goals:**

- `install.sh` is POSIX `sh` (`#!/bin/sh`, `set -eu`), because `alpine:3.24` ships no bash. Checked by shellcheck in
  `just check` and by the alpine jobs.
- Every option value is validated before any network access or file change: `version` against `latest` or
  `^[0-9]+\.[0-9]+\.[0-9]+$`, and each trimmed, non-empty `toolsToInstall` entry against a package name with at most one
  bracketed extra and at most one constraint (`==`, `~=`, `!=`, `>=`, `<=`, `>`, `<`, or `@` followed by a version), so
  no entry can become a uv option, a URL, a path, or a shell word split. A non-empty tool list with a pinned `version`
  below 0.12.16 fails at the same point; with `latest`, the resolved release is compared before the archive is
  downloaded. Checked during implementation by building with each invalid form from the spec's scenarios and recording
  the failures in the PR's Validation section.
- Nothing from a download is used before its checksum passes, and a failed download or check leaves a previously
  installed `uv` and `uvx` untouched: the archive is verified and unpacked in a temporary directory, and the binaries
  replace the old ones by rename within `/usr/local/bin`. The two renames are not atomic as a pair: a failure between
  them, which needs a failing `mv` on one filesystem, would leave `uv` and `uvx` at different releases until the next
  install. Checked by a local run with a corrupted `.sha256` recorded in the PR.
- Build-time uv runs with the sources and checks of the "Verify build-time tool downloads" requirement: `install.sh`
  sets no index, mirror, download-metadata, or hash-policy variable, passes no such flag, and writes no `uv.toml`; an
  image that already configures uv (its own environment or `/etc/uv/uv.toml`) keeps that configuration. Checked by
  review of `install.sh` and by a scenario asserting that the container environment carries no such variable from the
  feature.
- The image's `/var/lib/uv` is empty when this feature's install ends, with owner the remote user, group `uv`, and mode
  2775 when the remote user is not root, and `root:root` 0755 when it is; build-time uv runs with
  `UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python`, `UV_CACHE_DIR` in a temporary directory removed at the end, and
  `UV_MANAGED_PYTHON=1`, so tool interpreters are uv-managed and in the image regardless of any system Python. Checked
  by `test.sh`, which asserts, before running uv, that `/var/lib/uv` is a mount, empty, and writable by the running
  user, and then, for a non-root user, that its group is `uv`, its mode 2775, and `uv` among the user's groups, and for
  root that it is `root:root` 0755 and the image has no group `uv`; and by a tools scenario asserting that each tool's
  interpreter resolves under `/usr/local/share/uv/python`. Group, mode, and membership are what the kernel consults for
  a user who is not the owner, so these assertions hold the same on a host that changes the UID and on one that does
  not; an assertion on the owner's name cannot.
- The build-time layout under `/usr/local/share/uv/` (`tools`, `python`, `bin`, and everything below them) has, when the
  remote user is not root, owner the remote user, group `uv`, group write on every entry that is not a symbolic link,
  setgid on every directory, and no entry writable by others, so the remote user can run `uv tool` at runtime whether or
  not it still owns the files (Open Questions, item 1); for root it is root's, with no entry writable by group or
  others. The modes are set without `find`, which one compatibility image lacks: the directories get their group and
  setgid before a tool is installed below them, so what root creates there inherits both, and after the tools are
  installed one recursive `chmod` adds group write and removes other-write (for root, it removes group and other write),
  which takes uv's lock files from 0666 (Context). Checked by `test.sh` (group and mode of the four directories) and by
  the `tools` scenario running as `vscode`, which asserts first, before anything in the container has run a tool or uv,
  that no entry lacks the group, that no entry other than a symbolic link lacks group write or is writable by others,
  and that no directory lacks setgid, and only then runs the tools, reinstalls one build-time tool, and uninstalls
  another. The order is part of the check: a tool's first run leaves entries without group write under umask 022
  (Context), so the same assertion after a run would pass where commands are executed with umask 0000, as in the local
  dev container, and fail where it is 022. `uv tool upgrade` alone changes no file when the tool is current.
  `duplicate.sh`, whose first install has a tool, asserts on every image with `stat` that neither lock file under
  `/usr/local/share/uv`, the only entries uv makes writable by others (Context), is writable by others, nor, for a root
  remote user, by the group.
- The group `uv` and the membership come from the account tools the image ships, with nothing installed for them and no
  direct edit of `/etc/group`: `groupadd --system` and `usermod -aG` where they exist, BusyBox `addgroup -S` and
  `addgroup <user> <group>` otherwise, each only after a check that the group or the membership is missing (Context),
  and a failure with a message naming the step when it is needed and the image has neither tool. A group `uv` the image
  already has is used only when no other account belongs to it: its line in `/etc/group` lists no other member, and no
  other account in `/etc/passwd` has its ID as primary group, both read from the files, with the remote user, before any
  download or file change (Open Questions, item 10). A root remote user gets neither group nor membership (Open
  Questions, item 8). Checked by `test.sh` and `duplicate.sh` on the Ubuntu base image, the one compatibility image with
  a non-root remote user, and by the `changed_uid` scenario below for BusyBox.
- Write access through the group is shown on the two hosts the tests run on, and on any Linux host whose CLI user is not
  root and has a UID that no account of the scenario's image has, not only on a host whose user has another UID than the
  Ubuntu base image's `vscode`: a `build` scenario `changed_uid` on `alpine:3.24`, whose Dockerfile adds bash for the
  test library and a non-root user with a UID that neither the local dev container's user (1000) nor a CI runner's
  (1001, Context) has, is installed with one tool and that user as `remoteUser`. The CLI then changes the UID on both,
  and the scenario asserts that the running user owns neither `/var/lib/uv` nor `/usr/local/share/uv` and is a member of
  `uv`, and then creates an environment with a managed interpreter on the volume, reinstalls and uninstalls a build-time
  tool, and installs a new one. It also runs the BusyBox branch as a non-root user and the musl build, which no
  compatibility image does. On the Ubuntu base image the `tools` and `runtime_python` scenarios meet the UID change on
  the CI runners only.
- The group branch of the families CI runs only as root is observed during implementation: on `debian:12`,
  `almalinux:10`, `archlinux:latest`, and `opensuse/leap:16.0`, an image with a non-root user and the feature, then the
  CLI's `updateUID.Dockerfile` with another UID, a new volume, and the operations of "Changed UID" as that user.
  "Existing group" (a group `uv` created before the install, with another ID and no member) and "User outside the group"
  (a second account without the membership, created with an explicit UID that is neither the remote user's current UID
  nor the one it had when the image was built, because BusyBox `adduser` otherwise gives it the build-time UID, the
  owner's; Context) are observed the same way on the Ubuntu base image and `alpine:3.24`. Each result is recorded in the
  PR.
- `/usr/local/share/uv/bin` stays in `PATH` in login shells: `install.sh` writes `/etc/profile.d/uv.sh`, a file this
  feature owns and overwrites on every install, which puts the directory at the front of `PATH` only when it is missing,
  and sets nothing else (Open Questions, item 5). Checked by `test.sh` asserting the `PATH` of `sh -lc` on every image.
- A second install is decided by `uv --version` of `/usr/local/bin/uv`: the same release skips the download; another
  release replaces both binaries; tools are installed with `uv tool install` into the same `UV_TOOL_DIR`, which keeps
  earlier tools. The group and the membership are added only when missing, and group and modes are applied again at the
  end of every install, so what a second install adds as root ends up like the rest. Checked by `duplicate.sh` (other
  `version` and tools first, defaults with an empty tool list second), which on the image with a non-root remote user
  also asserts one `uv` line in `/etc/group` that lists the user once and the group and group write of the first
  install's tool directory, not of what is below it, which a run of the tool changes (Context), and by running
  `install.sh` twice in one throwaway container with a non-root remote user, once with identical options and once with
  two non-empty tool lists that list one tool again with another constraint, on the Ubuntu base image and on
  `alpine:3.24`, recorded in the PR.
- Prerequisites (curl, CA certificates, tar, `sha256sum`) are installed only when missing, from the image's configured
  repositories through the family's package manager (`apt-get`, `dnf`, `pacman -Syu --needed`, `apk`, or `zypper`),
  non-interactively and without recommended or weak dependencies where the manager has such a setting, with package
  caches cleaned afterwards, and stay in the image; when nothing is missing, no package manager runs. Checked by the
  `debian:12` and `alpine:3.24` jobs, which lack curl, and by a `build` scenario on `debian:12` whose Dockerfile records
  a SHA-256 of every file under `/etc/apt/sources.list*`, `/etc/apt/trusted.gpg*`, and `/usr/share/keyrings/`, which the
  scenario test compares with the built image. The `dnf`, `pacman`, and `zypper` images lack no prerequisite, so their
  branches are observed during implementation in a throwaway container of each image with `tar` removed without its
  dependents (`rpm -e --nodeps`, `pacman -Rdd`), running `install.sh` and recording in the PR that it installs `tar` and
  succeeds.
- `test.sh`, `duplicate.sh`, and the scenario scripts are POSIX `sh` that re-execute themselves with bash before
  sourcing the bash-only test library; on an image without bash they first add it from the image's `apk` repositories,
  inside the test container only. Checked by shellcheck and by the `alpine:3.24` jobs.
- Failure scenarios a successful build cannot show are produced in a throwaway container running `install.sh`: an
  unsupported architecture with a `uname` stub earlier on `PATH` that prints another machine name (for example
  `riscv64`); an unsupported distribution on an image outside the supported families (Photon OS, `photon:5.0`); a
  mismatching or missing checksum with a `curl` wrapper earlier on `PATH` that alters or fails only the `.sha256`
  request; a missing release with an unpublished version such as `9.9.9`; a missing remote user with `_REMOTE_USER`
  naming no account; an uninstallable tool with an unpublished package name; an old release with tools with `version`
  `0.12.15` and one tool; a primary group `uv` with a user created in that group (checked with the remote user, before
  any download or file change); a group with other members with a group `uv` created beforehand, once with a second user
  in its member list and once as the primary group of a second account (checked like the primary group, before any
  download or file change); a group that cannot be created with a non-root remote user on an image whose `groupadd` and
  `addgroup` were removed; a membership that cannot be added with a group `uv` created beforehand without members on an
  image whose `usermod` and `addgroup` were removed. Each result is recorded in the PR.
- Later features find `uv` and this feature's environment during their install, because `containerEnv` is written as
  image `ENV` before they install (Context). Checked by a throwaway local feature, not committed, that installs after
  this one, runs `uv --version`, and fails unless `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv/python`; one build of it is
  recorded in the PR. From `hf-cli`'s change (#17) on, its global scenario `uv_and_hf_cli` checks this again: its build
  fails unless `hf-cli`'s install runs `uv`, and its runtime value of the variable is the one later features saw, by the
  same `ENV` fact.
- `NOTES.md` gives users the facts they check before adopting the feature: the supported distribution families with
  their package managers, pointing to `test/uv/compatibility.json` for the tested images and to the
  `mcr.microsoft.com/devcontainers/base` images of those families; the layout of the volume (`/var/lib/uv`, mounted from
  `uv-${devcontainerId}`, with `python/` as `UV_PYTHON_INSTALL_DIR` and `cache/` as `UV_CACHE_DIR`); the group `uv`, who
  is in it, and what it may write; what stops a volume from fitting its user (a changed numeric UID, not a changed name,
  and files root wrote, `sudo uv` included), the error uv then prints ("Failed to initialize cache"), and that a change
  of `remoteUser` is followed by a rebuild; the check at creation, that it repairs only where the remote user has
  passwordless `sudo`, and its warning; the repair by hand where it cannot (`chown -R` as root in the container, or from
  the host with a throwaway container that mounts the volume), the bypass until then (`UV_NO_CACHE=1`, or a
  `UV_CACHE_DIR` in the user's home, with which managing interpreters still fails), and removing the volume as the last
  resort, after which `uv python install <version>`, with the version in an environment's `pyvenv.cfg`, restores a
  workspace `.venv/`, while `uv venv --clear` would empty it; that the workspace and the environments in it are outside
  the volume and keep their owner; that the repair also re-owns whatever is mounted below `/var/lib/uv`; that
  `uv python uninstall` exits 0 when it fails for lack of access; that the volume's name follows the workspace folder
  and the configuration file's path, so a renamed folder gets a new volume, that Compose prefixes the name with its
  project name, and what removes a volume (`docker volume rm`, Compose's `down -v`, a Codespaces full rebuild); that the
  owner and group a kept volume carries are numbers a rebuilt image may give to another account or group (Risks); and
  the upstream references of the spec's Purpose. Checked by review of `NOTES.md` against the spec.
- Nothing a rebuild replaces holds a path a workspace `.venv/` links to: interpreters uv installs at runtime exist only
  on the volume. Checked by a real rebuild of a dev container built from the `changed_uid` scenario's Dockerfile with
  that user as `remoteUser`, so that the CLI changes the UID on a host with UID 1000 as well, where the Ubuntu base
  image's `vscode` would keep its own: `devcontainer up`, a workspace `.venv/` with a managed interpreter and a package,
  then `devcontainer up --remove-existing-container`, which replaces the container and keeps the volume, and the
  `.venv/` used once more. The record shows, before and after the rebuild, the output of `id` and the owner of
  `/var/lib/uv`, which is not the running user.
- The check and the repair of "Repair a volume that no longer fits the remote user" are one script, a `.sh` file of its
  own in `src/uv/`, so that `just lint` checks it, which `install.sh` copies to
  `/usr/local/share/uv-feature/repair-volume` and the feature's `onCreateCommand` names: root-owned, mode 0755, outside
  the group-writable `/usr/local/share/uv`, overwritten whole on every install, POSIX `sh` like `install.sh`, taking no
  argument and reading no option. Checked by shellcheck, by `test.sh` asserting the file's owner and mode on every
  image, and by the `repair_volume` scenario below.
- The script ends with exit status 0 on every path, the failing ones included, because a lifecycle command that exits
  non-zero ends `devcontainer up` with an error, skips the user's own commands, and is not run again (Context). It has
  no `set -e`; it calls `sudo` only as `sudo -n`, so that it never waits for a password, and only after `sudo -n true`
  passed. Checked by the scenario, which asserts the exit status in every case and uses a `sudo` stub earlier on `PATH`
  for the cases the image cannot show: one that fails `-n true`, one that passes it and fails the `chown`, and one that
  records whether it was called.
- "Fits" is decided from the whole volume, not from one directory's owner: the remote user can create files in
  `/var/lib/uv`, and no entry below it has another owner. A new volume therefore fits, also when its root keeps the
  build-time UID after a UID change, and a volume in which root left entries among the user's does not (Context). The
  script sees every entry on every compatibility image, with `find` where the image ships it and with an equivalent
  listing of the entries' owners where it does not, and it never reports a fit because it could not look (Open
  Questions, item 13). Checked by the scenario on the Ubuntu base image, and by an observation in a throwaway container
  of each other compatibility image, as a non-root account added to it, since root is skipped, with a volume that fits,
  one that another UID filled, and one with a single root-owned file deep in the cache, recorded in the PR; those images
  ship no `sudo`, so for the two volumes that do not fit the record also shows exit status 0, the warning naming the
  missing `sudo`, and the volume unchanged.
- The repair is one `chown -R` of `/var/lib/uv` to the remote user's UID and to the ID of the group `uv`, or to the UID
  alone in a container whose image has no such group, as after `remoteUser` was changed from root without a rebuild. It
  changes owner and group, preserving file contents, ordinary permission bits, and directory setgid. The ownership
  change can clear executable setuid/setgid bits (Context); the script runs no chmod to restore them. A maintainer
  accepted this exception in conversation on 2026-10-02. `chown -R` of GNU coreutils and of BusyBox changes a symbolic
  link, not its target (Context), so nothing outside the volume changes. The script never touches `/usr/local/share/uv`,
  where the same command would copy every file into the container's writable layer (Context). `sudo` is not run for root
  or on a volume that fits. Checked by the scenario, which compares a listing of every entry's mode and, for a symbolic
  link that points outside the volume, the target's owner, before and after the repair. A separate fixture checks that
  an executable goes from 6755 to 0755 with unchanged contents and that its directory keeps 2775. The scenario also
  asserts with the recording stub that a second run calls `sudo` not at all. The branch without the group is observed
  once in a throwaway container, recorded in the PR: the feature installed on the Ubuntu base image for the remote user
  root, which creates no group `uv`, and `vscode` running the script on a volume root filled.
- The warning goes to standard error, starts with `uv feature:` like the messages of `install.sh`, and names
  `/var/lib/uv`, the reason (no `sudo`, a `sudo` that asks for a password, or the failed `chown` with its message), and
  the feature's notes. Checked by the scenario.
- The `repair_volume` scenario runs on the Ubuntu base image as `vscode`, the one compatibility image whose remote user
  has passwordless sudo. It fills the volume (a managed interpreter, a package installed into an environment in the
  workspace, and in the cache a symbolic link to a root-owned file and one to a root-owned directory outside the
  volume), gives the volume to a UID and a GID that no account or group has, with `sudo chown -R`, and asserts that
  `uv venv` now fails with the cache error, so that the state it repairs is the one that breaks uv. Then it runs the
  script as the lifecycle command would: with the failing stubs ("No passwordless sudo"), with the image's `sudo`
  ("Volume filled under another UID": the remote user owns every entry, every entry has the group `uv`, a package
  installs from the cache with `--offline`, and a further interpreter installs), a second time with the recording stub
  ("Volume that fits"), and after `sudo` has created a root-owned directory and file in the cache ("Files left by
  root"). The new-volume half of "Volume that fits" and "Repair skipped for root" are asserted in `test.sh`, which runs
  the script on the new volume with the recording stub and finds the volume empty afterwards, and which, for root, gives
  a file it created in the volume to another UID, runs the script with the recording stub, finds the file's owner
  unchanged, `sudo` not called, and nothing on standard error, and removes the file.
- That the tooling runs the script when the container is created, as the remote user and before the user's own commands,
  is shown on a real dev container, since a test cannot change the remote user: a Dockerfile adds two accounts to the
  Ubuntu base image, one with a `NOPASSWD` rule and one without, on a host whose UID an account of the image holds
  (1000, `vscode`, here), so that each added account keeps a UID of its own (Context); `devcontainer up` as `vscode`,
  and uv fills the volume; `remoteUser` set to the first account and `devcontainer up --remove-existing-container`, with
  an `onCreateCommand` in `devcontainer.json` that runs `uv venv` on a path in the user's home, the workspace being the
  host user's (Risks), and records its exit status without failing; then the same with the second account. The record
  shows `id`, the owners in the volume before and after, that `uv venv` succeeded for the first account, and for the
  second that `devcontainer up` exits 0, prints the warning, and that `uv venv` failed with the cache error.

**Non-Goals:**

- Creating or syncing a project environment at build time, setting `UV_PROJECT_ENVIRONMENT`, or installing a system
  Python through the distribution's package manager (the issue's Out of scope). The workspace `.venv/` stays where uv
  puts it.
- Persisting tools installed at runtime: their environments live in the image's `UV_TOOL_DIR` and go with a rebuild
  (their interpreters, on the volume, stay).
- Persisting executables that `uv python install` places in `~/.local/bin`; uv's default stays.
- Repairing a volume without root: where the remote user has no passwordless `sudo`, the volume stays as it is, and
  `NOTES.md` gives the repair by hand (Open Questions, item 12).
- A volume that two UIDs use in turn without a repair in between: the repair hands the volume over, so the earlier user
  needs it again (Context). A change of `remoteUser` back to an account the container already ran as, without a rebuild,
  runs no lifecycle command; `NOTES.md` asks for a rebuild after `remoteUser` changes.
- Entries that root or another UID writes while the container runs: they are repaired when the next container is
  created, not at the next start (Open Questions, item 14).
- The bind-mounted workspace and the environments in it: a `.venv/` an earlier UID wrote keeps its owner.
- A volume whose group number no longer is the ID of `uv` in a rebuilt image, as long as the remote user owns everything
  below its root and can create files there: it fits, and nothing changes.
- Sharing the tool directories or the volume among several accounts: a group `uv` to which another account belongs is
  refused (Open Questions, item 10).
- Group access for a process started without the remote user's supplementary groups, as `docker exec -u <user>:<group>`
  starts it (Context).
- Podman: whether it copies the mount point's owner, group, and mode into a new volume was not verified; the
  compatibility list names Docker-run images only.
- Architectures other than x86_64 and aarch64, which have no CI runner here.

## Options

The feature has two options, both new in this change; the spec's Option requirements state them.

| Name             | Type     | Default    | Enum or proposals                | Meaning                                                                                                                            |
| ---------------- | -------- | ---------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `version`        | `string` | `"latest"` | proposals `["latest","0.12.16"]` | The uv release to install: `latest`, the newest release at build time, or one release as `MAJOR.MINOR.PATCH`                       |
| `toolsToInstall` | `string` | `""`       | proposals `["","pycowsay"]`      | Python command-line tools to install at build time, comma-separated, each a package name with at most one extra and one constraint |

- **Default `latest` for `version`.** A configuration that omits `version` follows upstream releases without a feature
  release for each; a pinned `version` gives reproducible builds (Risks). The Acceptance runs "Omitted version" in
  `test.sh`, which installs the defaults. Proposals, not an enum: every published release is valid, and each new release
  adds one. `0.12.16`, the oldest release allowed with tools (Decisions), differs from what `latest` resolves to, so the
  second install of `duplicate.sh`, with the defaults, takes the replace path.
- **Default empty `toolsToInstall`.** The default image downloads no interpreter and reaches none of URL inventory rows
  5–8, and `duplicate.sh` installs the defaults second with an empty tool list (Goals). `pycowsay` is the small tool
  verified in the URL inventory; it gives the first install of `duplicate.sh` a tool to keep.
- **Rejected shapes.** An enum of uv releases (every uv release would need a feature release, and `latest` would be
  impossible); options for a package index, a mirror, a Python download source, or a hash policy (they would let
  configuration redirect or weaken verified downloads, against "Verify build-time tool downloads"); one option per tool
  or a JSON list (options are `boolean` or `string`; a comma-separated list matches the first-party Python feature's
  `toolsToInstall`, with the limit in Risks).
- **Not in this change, pending Open Questions item 4.** An option for the Python version of build-time tools. The
  recommendation there is to leave it out, so this table does not list it; if the maintainer decides otherwise, the
  table and the delta spec gain it before implementation.

## Decisions

- **Release archive from GitHub Releases, verified against its per-archive `.sha256`.** Rejected: uv's `uv-installer.sh`
  (the download rules in `.agents/knowledge/feature-authoring.md` would allow it only saved to a file before it runs,
  with the spec stating that its content is not verified unless upstream publishes a checksum for it; it downloads the
  same archives and also edits shell rc files, so it adds a script to trust and a side effect with no gain);
  `pip`/`pipx` (need a system Python the images lack); distribution packages (not packaged for every supported
  distribution, and not pinnable to an upstream release); the same archives from `releases.astral.sh`, which uv's own
  installer uses (a second host with no gain once the checksum is checked); the aggregate `sha256.sum` (binary-mode
  `*name` lines, one file for all targets); pinning checksums inside the feature (every uv release would need a feature
  release, and `latest` would be impossible); verifying GitHub artifact attestations (needs `gh` or a Sigstore verifier
  the images lack, one more download to trust; a later MINOR can add it).
- **Resolve `latest` from the redirect of `https://github.com/astral-sh/uv/releases/latest`, read without following
  it**, so the release tag page is never fetched. Rejected: the GitHub REST API (60 unauthenticated requests per hour
  per IP, shared by CI runners); `releases/latest/download/<asset>` (the version is unknown before downloading, so the
  same-version skip is impossible, and the archive and checksum could come from two releases at a release boundary).
- **curl as the download tool on every distribution.** It reports a redirect target without following it, restricts
  every request and redirect to HTTPS, and fails on HTTP errors, identically on glibc and musl images. Rejected: busybox
  `wget` on Alpine (no redirect-target output, a second code path to test). Prerequisites the feature installs stay in
  the image: removing them could remove a package the image, the user, or a later feature relies on, and a second
  install would add them again.
- **gnu or musl chosen by the C library, not by the distribution:** musl when `/lib/ld-musl-*.so.1` exists, gnu
  otherwise. Rejected: the musl build everywhere (static and portable, but its name resolution ignores glibc's
  `/etc/nsswitch.conf`, a behavior difference users would not expect on Debian or Ubuntu).
- **uv at `/usr/local/bin`, tool executables in `/usr/local/share/uv/bin` added to `PATH` through `containerEnv`, and
  through `/etc/profile.d/uv.sh` for login shells.** `/usr/local/bin` is on `PATH` everywhere, and a separate tool
  directory means a tool can never overwrite `uv`. Rejected: `~/.local/bin` (`containerEnv` cannot name the remote
  user's home, and it is not on `PATH` on every image); editing `/etc/profile`, `/etc/bash.bashrc`, or other shared
  files (a file of the feature's own is replaced whole on a second install); narrowing the spec to processes the CLI
  starts (a login shell or `su -` in a Debian or Alpine container would lose the tools).
- **Build-time tools and their interpreters in `/usr/local/share/uv/{tools,python}` in the image; runtime interpreters
  and the cache on the volume.** Rejected: build-time interpreters on the volume (absent at build time, and a non-empty
  volume hides whatever the build put in the mount point, so tools would point at nothing after the first rebuild); a
  system Python for tools (varies by image, and another feature may replace it).
- **Tools only with uv 0.12.16 or later.** Earlier releases install packages from PyPI with TLS only. The download rules
  in `.agents/knowledge/feature-authoring.md` accept a registry package because the tool that fetches it verifies it,
  and accept TLS alone only for a direct download whose upstream publishes no checksum; PyPI supplies a SHA-256 for
  every file, and uv checks it only from 0.12.16 on. Rejected: accepting older releases as a documented exception (Open
  Questions, item 6); pinning hashes through a constraints file (not verified that `uv tool install` enforces them, and
  the user's list would need hashes).
- **A named volume `uv-${devcontainerId}` at `/var/lib/uv`, one per dev container.** `${devcontainerId}` is allowed in a
  feature's `mounts` and stable across rebuilds; the first-party docker-in-docker and powershell features use the same
  pattern. Rejected: one volume shared by all dev containers (owners differ between projects, and one project's cache
  and interpreters would leak into another); a host bind mount (depends on a host path); no mount (the issue's problem:
  after a rebuild every workspace `.venv/` dangles until its interpreter is downloaded again, which uv does by itself
  only for a project, online and by removing and recreating the environment; a creation command that runs
  `uv python install <version>` restores both kinds in place, but downloads each interpreter again at every rebuild,
  about 35 MiB, has to know each environment's version, and keeps no cache; Context); interpreters installed into the
  image through an option (an environment pinned to a patch, or needing a version the image lacks, still dangles; it can
  arrive as a MINOR beside the volume); the image's system Python (the base image decides the version, and a change of
  its minor version strands every environment); only the cache on the volume (every rebuild downloads each interpreter
  again, and environments dangle until then); only the interpreters on the volume (uv would keep working for a second
  UID, because the cache is what fails first, but every rebuild would download every package again, the other half of
  the issue's problem).
- **Write access through a group, set in the image, not through the owner and not at runtime** (maintainer decision of
  2026-10-01, replacing "ownership through the mount point"). A non-root remote user is a member of a system group `uv`;
  the image's empty `/var/lib/uv` and all of `/usr/local/share/uv` keep the remote user as owner and get the group `uv`,
  group write, setgid on directories, and no write access for others, and Docker copies owner, group, and mode of the
  mount point into a new volume. The membership names the user and the group is not the user's primary one, so the CLI's
  UID change leaves both alone (Context): the remote user then writes as a member where it is no longer the owner. The
  owner stays the remote user for the hosts on which no UID changes. Rejected: ownership alone, the approach this
  replaces (the CLI changes the UID and re-owns only the home folder, so the directories and every new volume belong to
  a UID the remote user no longer has; it passed locally and failed in CI); an `entrypoint` or a lifecycle command that
  runs `chown`, as the way a new volume becomes writable (a lifecycle command runs as the remote user and needs
  passwordless sudo, which the specification does not promise; an entrypoint runs as the container user, which is root
  only where the image's user is, and the CLI does not wait for it; the group needs neither, so a lifecycle command
  serves only the volume the group cannot cover, in the decision on repairing a volume below); a world-writable volume
  or tool directory (any account in the container could then replace what is first in `PATH`); asking users to set
  `updateRemoteUserUID` to `false` (it is the user's property, which a feature cannot set, and its default exists so
  that the bind-mounted workspace matches the host user; the feature would then work only in configurations that give
  that up); a fixed ID for the group (it can collide with a group of the image, and none of the first-party features
  read in Context pins one); a group-writable umask for the remote user, which would also cover what uv creates at
  runtime (it changes the mode of every file the user creates, uv's or not, and only in shells that read the profile);
  leaving uv's build-time lock files at the mode uv gives them, 0666 (files any account can write and lock, in a tree
  whose `bin` is first in `PATH`, against the proposal's "Stays true"; removing other-write costs a user outside the
  group `uv tool list`, Context).
- **The group comes from the image's own account tools, shadow first, BusyBox second.** `groupadd` and `usermod` where
  the image has them, BusyBox `addgroup` otherwise, and a failure with a message when a step is needed and neither
  exists. A group `uv` the image already has is used with its ID when it has no member or only the remote user, which a
  second install finds, and refused when another account belongs to it; reusing it with its members is the alternative
  of Open Questions, item 10. Rejected: trying `addgroup -S` first (Debian's `addgroup` rejects it); installing the
  `shadow` package on Alpine (a package for one line in `/etc/group`); writing `/etc/group` directly (a free ID has to
  be picked by hand, and on images with `/etc/gshadow` `grpck` then reports the missing entry); creating the group for a
  root remote user as well, as most of the first-party features read in Context do (root needs no group, and an image
  with a root remote user would carry an account entry nothing uses; Open Questions, item 8).
- **A volume that no longer fits its user is repaired when the container is created, by a lifecycle command, as far as
  the remote user's own sudo reaches** (maintainer decision of 2026-10-01, replacing the "no runtime fix" of Open
  Questions item 2). The feature declares an `onCreateCommand` whose script hands the volume to the remote user with one
  `chown -R` through `sudo -n`, and warns where it cannot. `onCreateCommand` runs once per container, as the remote
  user, before the user's own creation commands, and `devcontainer up` waits for it (Context); VS Code's documentation
  and the first-party `powershell` feature use the same means for the same problem. The group stays: it makes a new
  volume writable after a UID change without any sudo, and the repair covers what the group cannot, a volume whose
  contents another UID wrote. Rejected: no runtime fix, the earlier recommendation (a second account beside one that
  holds the host's UID keeps its own UID, and every uv command that uses the cache then fails; the remedy, removing the
  volume, costs every interpreter and cached package and leaves every workspace `.venv/` dangling); an `entrypoint` that
  runs the `chown` (it needs no sudo where the container user is root, but it is not root where the image's user is not,
  the CLI does not wait for it, so a slow repair races the user's own commands, and it adds a script that runs at every
  start; with a marker that a lifecycle command waits for, it is the alternative of Open Questions item 12);
  `postStartCommand` (it runs at every start, where the walk costs seconds on a cold page cache, and after the point
  tools wait for by default; Open Questions, item 14); `postCreateCommand` (it runs after the user's `onCreateCommand`
  and `updateContentCommand`, in which a `uv sync` would already have failed); a `chown -R` at every creation without
  the check (it would run `sudo` where nothing needs it and refresh every ctime, after which uv probes its interpreters
  again); a check of the mount point's owner alone, as `powershell` does (after a UID change a new volume's root has the
  build-time UID, so it would repair where nothing is wrong, and it misses root-owned entries inside a volume whose root
  is the user's); `chmod -R g+w` instead of `chown` (what the next user creates lacks group write again, so the change
  after that fails, and it needs root as well); a default ACL for the group on the volume (the only variant that kept
  several UIDs working with no repair in between, but it needs the `acl` package and root at runtime once per volume, an
  ACL set at build time reaches neither the image nor a new volume, and it follows the group's ID); a wrapper that runs
  uv under umask 002 (it repairs no existing volume and does not cover what Python writes when an interpreter runs
  directly); a sudo rule for the script (every image would gain a rule, and the remote user a privilege it did not
  have); failing the creation where the repair is impossible (`devcontainer up` would end with an error and skip the
  user's own commands, and the CLI does not run a failed `onCreateCommand` again).
- **`UV_LINK_MODE=copy`.** The cache volume and the workspace bind mount can be on different filesystems, where the
  default `clone` falls back to copying and warns. The cross-filesystem test uses a temporary cache on `/dev/shm` and
  asserts that its device differs from the workspace's; a named volume and a workspace can share the runner's backing
  filesystem. Rejected: the default (the warning across filesystems); `hardlink` (impossible across filesystems);
  `symlink` (uv discourages it: cleaning the cache breaks environments).
- **Distribution families, by `ID` or `ID_LIKE` in `/etc/os-release`: Debian/Ubuntu (`debian`, `ubuntu`) with `apt`,
  RHEL/Fedora (`rhel`, `centos`, `fedora`) with `dnf`, Arch Linux (`arch`) with `pacman`, Alpine (`alpine`) with `apk`,
  and openSUSE/SUSE (`suse`, `opensuse`, or an `ID` starting with `opensuse`) with `zypper`; anything else fails**
  (maintainer decision, replacing Open Questions item 3). The distribution matters only for installing prerequisites, so
  a family costs one package-manager branch and one compatibility image. Rejected: Debian/Ubuntu and Alpine only, with
  other families as later MINORs; proceeding on any distribution that already has the prerequisites (a missing one would
  then fail late, with no package manager to install it).
- **On Arch Linux, `pacman -Syu --needed` only when a prerequisite is missing.** Arch supports no partial upgrade, and
  its image ships no package database. Rejected: `pacman -Sy <pkg>` (a partial upgrade, which Arch does not support);
  failing on Arch when a prerequisite is missing (the image lacks none today, but a slimmer Arch image would fail).
- **`installsAfter: ghcr.io/devcontainers/features/common-utils`**, so a remote user that feature creates exists before
  it is added to the group and before ownership is set. No `dependsOn`: nothing is needed from another feature.

## Security review surface

| Surface               | Bound                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Downloads             | HTTPS only; exactly the URLs in the URL inventory; no installer script; no URL, path, or option from a user option reaches curl or uv (validation above).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Verification          | uv archive: SHA-256 from the same release's `.sha256`, checked before unpacking. `latest` redirect: TLS alone, stated in the spec's "Verify the uv release before installing it". Managed interpreters: SHA-256 compiled into uv, checked by uv. PyPI packages: SHA-256 supplied by the index, checked by uv 0.12.16 or later; the feature refuses tools with an older release and adds no pin of its own.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Keys                  | None. uv publishes no signing key; the feature installs no repository key.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `mounts`              | One named volume `uv-${devcontainerId}` → `/var/lib/uv`, needed so interpreters and cache survive a rebuild; no bind mount, no host path.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `containerEnv`        | `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_LINK_MODE`, and `PATH` with `/usr/local/share/uv/bin` prepended; nothing secret, nothing that changes an index or a download source.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Shell startup         | `/etc/profile.d/uv.sh` (root-owned, mode 0644) prepends `/usr/local/share/uv/bin` to `PATH` when it is missing; nothing else.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `installsAfter`       | `ghcr.io/devcontainers/features/common-utils` (ordering only).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `dependsOn`           | None.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Lifecycle command     | `onCreateCommand`: `/usr/local/share/uv-feature/repair-volume`, a root-owned script that takes no argument and reads no option. It runs as the remote user when a container is created, reads the owners of the entries under `/var/lib/uv`, and runs `sudo -n chown -R` on `/var/lib/uv`, to the remote user and, where the image has it, the group `uv`, only when the volume does not fit that user and `sudo -n true` passed. It accesses no network, follows no symbolic link, changes nothing outside `/var/lib/uv`, and always exits 0.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Not used              | `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, and any lifecycle command other than the one above.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Accounts              | One system group `uv`, created only for a non-root remote user and only when the image has none; no user, no password, no sudo rule. When the install ends its only member is the remote user: a group `uv` the image already has is used only when no other account belongs to it, as a listed member or through its primary group (Open Questions, item 10). An account added to the group later, or given it as primary group, shares the write access below.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Files owned by a user | When the remote user is not root, `/var/lib/uv` (empty mount point, mode 2775) and `/usr/local/share/uv/` (group write, setgid directories) have that user as owner and `uv` as group; the install leaves nothing writable by others, uv's lock files included, and for root nothing writable by group or others. Writers are root, the members of `uv`, and the build-time UID, which after a UID change belongs to no account until one is given it: that account then owns both locations. BusyBox `adduser` gives the next account that UID when it is the first free one from 1000, observed on `alpine:3.24`; shadow `useradd` on the Ubuntu base image did not (Open Questions, item 11). What is created at runtime has the modes of uv and of the creating user's umask; uv's lock files on the volume are 0666. A volume that does not fit the remote user is given to that user at creation, with everything in it, where the user has passwordless sudo (Decisions); the owner is then the remote user under its current UID. |
| `PATH`                | `/usr/local/share/uv/bin`, first in `PATH`, stays writable by a non-root account, as accepted with Open Questions item 1. The group changes how the remote user gets that access, not who has it, while the remote user is the group's only member.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Idempotency           | Same release skips the download; binaries replaced by rename; tool installs are additive; `/etc/profile.d/uv.sh` overwritten whole; directories, the group, and the membership created only if missing; group and modes applied again on every install. The repair script is overwritten whole, and a second run of it on a volume that fits changes nothing.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Failure behavior      | As in the spec's "Fail on unsupported platforms and invalid options", "Verify the uv release before installing it", "Option version", and "Option toolsToInstall"; a remote user that does not exist, a group `uv` that is the remote user's primary group or to which another account belongs, and an image without a tool to create the group or to add the member each fail the install. The repair never fails the creation of a container: where it cannot repair, it warns.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

Planned `test/uv/compatibility.json`:

```json
{
  "images": [
    {
      "image": "mcr.microsoft.com/devcontainers/base:ubuntu24.04",
      "arch": ["amd64", "arm64"],
      "remoteUser": "vscode"
    },
    { "image": "debian:12", "arch": ["amd64", "arm64"] },
    { "image": "alpine:3.24", "arch": ["amd64", "arm64"] },
    { "image": "almalinux:10", "arch": ["amd64", "arm64"] },
    { "image": "archlinux:latest", "arch": ["amd64"] },
    { "image": "opensuse/leap:16.0", "arch": ["amd64", "arm64"] }
  ]
}
```

The first entry covers glibc with a non-root remote user, the second glibc as root on a minimal image, the third musl.
The last three cover the `dnf`, `pacman`, and `zypper` families, each with a root remote user on the distribution's own
image. Arch Linux publishes no arm64 image, so `archlinux:latest` runs on amd64 only; its rolling `latest` tag is the
only one upstream maintains. Fedora belongs to the RHEL/Fedora family without an image of its own: it shares `dnf` with
`almalinux:10` and adds no C library. The first entry is the only one with a non-root remote user, so it alone runs the
group code in `test.sh` and `duplicate.sh`, and it meets the UID change only on a host whose user has another UID than
`vscode`; the `changed_uid` scenario and the observations of Goals cover the rest. The list is the one planned before
this revision.

## URL inventory

Every URL the feature's scripts access. The script the `onCreateCommand` runs accesses no URL, and the feature has no
start-time script, so nothing is fetched when a container is created or started. The feature configures no package
repository: prerequisites come from the repositories the image already has. Rows 5–8 are accessed at build time only
when `toolsToInstall` is not empty, by uv itself on the feature's behalf; the same hosts serve the remote user's own uv
commands at runtime.

| #  | URL / template                                                                                                                                          | Purpose                                                                         | When                                                 | Integrity / authenticity                                                                               | Official source evidence                                                                                                                                  | Verified                                                                                                                                                                             |
| -- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1  | `https://github.com/astral-sh/uv/releases/latest`                                                                                                       | Resolve `latest` to a release name; the redirect is read, not followed          | Build, `version` = `latest`                          | TLS alone (a spec Requirement); the redirect target's last path segment must match `MAJOR.MINOR.PATCH` | https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases                                                                  | 2026-09-30: 302 to `https://github.com/astral-sh/uv/releases/tag/0.12.21`                                                                                                            |
| 2  | `https://github.com/astral-sh/uv/releases/download/<version>/uv-<x86_64\|aarch64>-unknown-linux-<gnu\|musl>.tar.gz`                                     | uv release archive                                                              | Build, unless the release is already installed       | SHA-256 from row 3, checked before unpacking                                                           | https://docs.astral.sh/uv/getting-started/installation/ ("GitHub Releases"); https://github.com/astral-sh/uv/releases                                     | 2026-09-30: `0.12.21`, all four builds 200, final host `release-assets.githubusercontent.com`, `sha256sum -c` OK for x86_64-gnu and aarch64-musl; an unpublished version returns 404 |
| 3  | Row 2 + `.sha256`                                                                                                                                       | Checksum of the archive                                                         | Build, with row 2                                    | TLS; same release as the archive (integrity, not independent authenticity)                             | https://github.com/astral-sh/uv/releases (each archive lists its `.sha256`)                                                                               | 2026-09-30: all four 200, final host `release-assets.githubusercontent.com`, format `<hex>  <name>`, equal to the API `digest`                                                       |
| 4  | `https://release-assets.githubusercontent.com/github-production-release-asset/<id>/<uuid>?<signed query>`                                               | Redirect target of rows 2, 3, and 6                                             | Build, with those rows                               | Short-lived URL signed by GitHub; content checked as in the originating row                            | https://docs.github.com/en/actions/reference/runners/self-hosted-runners (lists the host)                                                                 | 2026-09-30: final host of rows 2, 3, 6, 200                                                                                                                                          |
| 5  | `https://releases.astral.sh/github/python-build-standalone/releases/download/<build>/cpython-<version>%2B<build>-<triple>-install_only_stripped.tar.gz` | Managed CPython for build-time tools (uv's first choice)                        | Build, `toolsToInstall` not empty                    | SHA-256 compiled into the uv binary, checked by uv                                                     | https://docs.astral.sh/uv/reference/environment/ (`UV_ASTRAL_MIRROR_URL`); https://github.com/astral-sh/uv/blob/0.12.21/crates/uv-python/src/downloads.rs | 2026-09-30: 3.14.7, all four triples 200 on `releases.astral.sh` with no redirect; uv 0.12.21 fetched from it in a local `uv tool install`                                           |
| 6  | `https://github.com/astral-sh/python-build-standalone/releases/download/<build>/<same file as row 5>`                                                   | Fallback when row 5 fails                                                       | Build, `toolsToInstall` not empty, row 5 unavailable | As row 5                                                                                               | https://docs.astral.sh/uv/reference/environment/ (`UV_PYTHON_INSTALL_MIRROR`); `crates/uv-python/src/downloads.rs` as in row 5                            | 2026-09-30: 3.14.7, all four triples 200, final host `release-assets.githubusercontent.com`                                                                                          |
| 7  | `https://pypi.org/simple/<package>/`                                                                                                                    | Resolve each tool and its dependencies                                          | Build, `toolsToInstall` not empty                    | TLS; supplies the SHA-256 of each file in row 8                                                        | https://docs.astral.sh/uv/concepts/indexes/ (PyPI is the default index); https://docs.pypi.org/api/index-api/                                             | 2026-09-30: `pycowsay` 200 on `pypi.org`; uv 0.12.21 requested it in a local run                                                                                                     |
| 8  | `https://files.pythonhosted.org/packages/<path>`                                                                                                        | Distribution files and their metadata                                           | Build, `toolsToInstall` not empty                    | SHA-256 from row 7, checked by uv 0.12.16 or later; the feature adds no pin                            | https://docs.pypi.org/api/index-api/ (index responses link files on this host)                                                                            | 2026-09-30: `pycowsay-0.0.0.2-py3-none-any.whl` and its `.metadata` 200 on `files.pythonhosted.org`                                                                                  |
| 9  | The image's configured `apt`, `dnf`, `pacman`, `apk`, or `zypper` repositories                                                                          | curl, CA certificates, tar, `sha256sum` when missing                            | Build, only when a prerequisite is missing           | The distribution's signed repository metadata, with keys the image already has                         | Not configured by this feature                                                                                                                            | Not applicable                                                                                                                                                                       |
| 10 | `ghcr.io/devcontainers/features/common-utils` (OCI, `installsAfter`)                                                                                    | Ordering only; this feature never fetches it, the CLI does if the user lists it | Build (Dev Container CLI)                            | OCI digests, verified by the CLI                                                                       | https://github.com/devcontainers/features/tree/main/src/common-utils                                                                                      | 2026-09-30: anonymous GHCR tag list 200, tags include `2`                                                                                                                            |

## Risks / Trade-offs

- [The `.sha256` comes from the same release as the archive, so a compromised release passes] → TLS to GitHub and
  GitHub's release storage are the trust root; attestation verification is the named upgrade path (Decisions).
- [`latest` changes what a rebuild installs] → `version` pins a release; the same-version skip keeps a repeated install
  of one release offline.
- [`test.sh` compares `uv --version` with `releases/latest` at test time, so a release published between the build and
  the test fails the job] → The window is minutes; a rerun clears it.
- [A later feature that runs uv at build time as root without its own directories writes into `/var/lib/uv` in the
  image. Docker copies those root-owned files into every new volume; the setgid mount point gives them the group `uv`,
  but root's umask gives them no group write, so the remote user's uv fails with permission denied on the cache or
  interpreter directory, and the volume no longer holds only what the remote user wrote] → `NOTES.md` states the
  contract for dependents: the paths under `/var/lib/uv` are for runtime only, and a feature that runs uv at build time,
  as any user, keeps uv's interpreter and cache writes out of it: it downloads no managed Python (for example
  `uv pip install --python <interpreter>`) or sets its own `UV_PYTHON_INSTALL_DIR` outside it, and it sets
  `UV_NO_CACHE=1` or a temporary `UV_CACHE_DIR`. `hf-cli`'s change (#17) follows it (Context) and adds the global
  scenario `uv_and_hf_cli`, which installs both features and asserts that uv installed `hf-cli`'s package, that
  `UV_PYTHON_INSTALL_DIR` is `/var/lib/uv/python`, and that `/var/lib/uv` is a mount and empty in a container started
  with a new volume. That change still words the volume as owned by the remote user, which fails after a UID change as
  it did here; it takes over the wording of "New volume" before its scenario is written.
- [A dependent that installs tools as root into `/usr/local/share/uv/tools` leaves environments there that have the
  group `uv`, inherited from the directory, but root as owner and no group write, so the remote user's
  `uv tool upgrade --all` fails on them] → `NOTES.md` asks dependents to give such environments the group `uv` and group
  write, as this feature does, or to use their own tool directory (Open Questions, item 7).
- [What the remote user creates at runtime has the group `uv` but, under the usual umask 022, no group write, so a
  later, different UID cannot use a volume the first one filled, and fails on a tool the first one ran or installed
  (Context)] → For the volume, the repair at creation hands it to the remote user where that user has passwordless sudo
  (Decisions). For the tools in the image, accepted: a rebuild installs them again for the remote user it is built for,
  and a change of `remoteUser` without a rebuild leaves them the earlier user's, which `NOTES.md` names.
- [The repair needs passwordless sudo. An account added with `useradd`, and an image without `sudo`, have none, so after
  a change to such an account uv stays unusable on the volume] → The creation continues, and the warning names the
  volume, the reason, and the notes, which give the repair by hand and the bypass (Goals). A root `entrypoint` would
  cover these images where the container user is root (Open Questions, item 12).
- [A lifecycle command that exits non-zero ends `devcontainer up` with an error, skips the user's own commands, and is
  not run again] → The script exits 0 on every path, which the scenario asserts for each failing one (Goals).
- [The repair hands the volume over and does not share it: the user it was taken from needs a repair in turn, and a
  change of `remoteUser` back to an account the container already ran as, without a rebuild, runs no lifecycle command]
  → Accepted; `NOTES.md` asks for a rebuild after `remoteUser` changes, and a rebuild runs the check.
- [The check reads every entry of the volume at every creation, and a repair writes every entry once: about 0.2 s per
  100,000 entries with a warm page cache, and about 3 s for 120,000 to 220,000 entries with a cold one, measured on a
  WSL2 virtual disk (Context); a slower or networked disk was not measured] → Accepted: it is paid once per container,
  not per start, and `NOTES.md` names `uv cache prune` for a volume that has grown.
- [`chown -R` descends into anything a user mounts below `/var/lib/uv`, and fails on a read-only mount there] →
  Accepted: the feature mounts nothing below the volume's root, and what a user mounts there, a host directory or a
  volume shared with other containers, is checked and re-owned with the volume; `NOTES.md` says so. A failing `chown`
  ends in the warning with its message, not in a failed creation.
- [uv running as the earlier UID while the owner changes fails at once (Context)] → A feature's `onCreateCommand` runs
  before the user's own commands, so with the CLI nothing of the user's runs uv yet; whether an editor opens a terminal
  earlier was not verified (Context).
- [A second account cannot write the bind-mounted workspace either, and a `.venv/` there keeps the earlier owner, so
  `uv sync` in it fails after the volume is repaired] → A non-goal: the workspace is not the feature's. `NOTES.md` names
  it.
- [Removing the volume, the remedy of last resort, leaves every workspace `.venv/` with a dangling interpreter link, and
  uv's own hint, `uv venv --clear`, empties the environment] → `NOTES.md` gives `uv python install <version>` with the
  version from `pyvenv.cfg` (Context).
- [With `devcontainer up --prebuild`, `onCreateCommand` runs in the prebuild and not again when the container is used] →
  With the CLI, the later `devcontainer up` uses the prebuilt container, and with it the volume the check ran on
  (observed: it did not run `onCreateCommand` again); whether a Codespaces prebuild sees the volume the codespace later
  mounts was not verified (Context). A later change of user needs a rebuild, as everywhere else.
- [A volume keeps the numeric owner and group it got when it was created. If a rebuilt image gives `uv` another ID,
  because the base image or a feature installed earlier added a system group, a remote user whose UID was changed can no
  longer create entries directly in `/var/lib/uv`; `python/` and `cache/`, once that user created them, stay usable. The
  numbers the volume keeps may then name another group or account of the rebuilt image, whose members can write the
  volume's top level and so rename and replace `python/` and `cache/`, which the remote user's uv runs from. Inferred
  from the facts in Context (group semantics and the rename a second member performed), not run] → A volume in whose
  root the remote user can no longer create entries does not fit, so the repair gives it, with everything in it, the
  remote user and the current ID of `uv` where that user has passwordless sudo (inferred from what `chown` does, not
  run). Elsewhere, and for a volume that still fits, accepted and documented in `NOTES.md` with the repair by hand or,
  as the last resort, removing the volume; a fixed ID was rejected (Decisions).
- [A volume that the owner-based layout created and filled keeps its owner and mode and fails after a UID change, as it
  did before] → The repair hands such a volume to the remote user where that user has passwordless sudo; elsewhere
  `docker volume rm` removes it. No release carried that layout; the volumes exist only on machines that ran this
  branch's tests.
- [An image that already has a group `uv` to which another account belongs fails the build, and so does a second install
  for another non-root remote user on an image whose first install put its own user in the group] → The message names
  the group and the account; the spec states both ("Group has other members", "Install twice"), and Open Questions item
  10 holds the alternative.
- [An account added to the group after the install, or given it as primary group, can write a directory that is first in
  `PATH` and replace what the remote user's uv runs from] → `NOTES.md` states it; the feature adds only the remote user.
- [After a UID change the build-time UID owns both locations and belongs to no account, and the next account created may
  get it: BusyBox `adduser` gives out the first free UID from 1000 (Context)] → Accepted with the owner the maintainer's
  outline names; `NOTES.md` states it. Root as owner removes the case (Open Questions, item 11).
- [With other-write removed from uv's lock files, a user outside the group can no longer run `uv tool list`, and a later
  uv release might set the mode of an existing lock file again at runtime] → Accepted: that user cannot run uv with the
  feature's cache location either, and the tools still run. The spec covers what the install leaves, which such a
  release would not change; no test would show it.
- [A remote user started as `<user>:<group>`, or any process started without supplementary groups, gets no access
  through the group] → Non-goal; `NOTES.md` names it.
- [The group code runs in CI as a non-root user on one compatibility image, and with BusyBox only in the `changed_uid`
  scenario] → The observations of Goals on the other families, recorded in the PR; a regression there would show only to
  a user with a non-root remote user on those images.
- [The `changed_uid` scenario rests on the CLI changing the UID in `devcontainer features test`, read from its source
  and not yet run] → Its assertion that the running user does not own the two locations fails if the UID was not
  changed; the implementation reports that before changing the scenario.
- [In the local dev container `docker exec` ran with umask 0000 while image builds and `docker run` used 0022, so a
  local test that only writes can pass where a missing group-write bit would fail it elsewhere; whether the CI runners
  differ was not verified] → The tests assert group and mode with `stat`, not only by writing, and assert the build-time
  layout before any command writes below it (Goals); what the remote user creates at runtime is group-writable only
  under the local umask 0000 and is asserted nowhere.
- [Interpreters installed at build time for tools are not visible to runtime uv, whose `UV_PYTHON_INSTALL_DIR` is the
  volume, so a runtime `uv venv` or `uv python list` does not see them and downloads a matching version again] → A
  deliberate trade-off: the volume must hold nothing from the build. `NOTES.md` states it.
- [GitHub has moved its release-asset host before (`objects.githubusercontent.com`,
  `github-releases.githubusercontent.com`), so an allow-list that names only row 4's host breaks when that happens
  again] → `NOTES.md` lists the hosts of the URL inventory with that caveat.
- [The volume grows as uv versions change cache layouts and interpreters accumulate] → `NOTES.md` documents
  `uv cache prune`, `uv python uninstall`, and removing the volume (`docker volume rm uv-<devcontainerId>`), which also
  outlives a deleted dev container.
- [Test runs leave one named volume per test container on the machine that ran them] → CI runners are discarded;
  locally, `docker volume prune` removes them.
- [If `devcontainer features test` does not apply feature `mounts`, the mount assertions in `test.sh` fail] → That
  failure is the signal; the implementation reports it before changing the assertions.
- [A comma-separated option cannot express an extra list or a constraint that contains a comma (`pkg[a,b]`,
  `pkg>=1,<2`)] → The same limitation as the first-party Python feature's `toolsToInstall`; a single constraint or
  `pkg@version` covers pinning.
- [Build-time tools run on the interpreter uv chooses by default] → A tool that cannot run on it fails the build visibly
  (Open Questions, item 4).

## Open Questions

Decisions for the maintainer, each with a recommendation:

1. **Who may write `/usr/local/share/uv/`, and where its `bin` goes in `PATH`.** Decided by the maintainer: the remote
   user manages tools without sudo and the directory is prepended, approved with the package; and, on 2026-10-01, the
   write access goes through the group `uv`, with the remote user still the owner (Decisions). That lets
   `uv tool install` and `uv tool upgrade` work at runtime, also after a UID change, and it keeps a directory that a
   non-root account can write at the front of `PATH` for every process, including root shells (not `sudo`, whose
   `secure_path` ignores it): the remote user of a dev container can usually become root anyway, and appending would let
   an image's older copy of a tool win. The group does not widen that while the remote user is its only member (Security
   review surface). The alternative was root ownership (runtime `uv tool` then needs sudo, and "Remote user manages
   tools" is dropped) or appending.
2. **A volume that already holds data and no longer fits its user.** Decided by the maintainer on 2026-10-01: the
   feature repairs it when the container is created, with a lifecycle command and the remote user's own passwordless
   sudo, and warns where it cannot (Decisions). This replaces the earlier recommendation, no runtime fix, which rested
   on a count of failing operations that held only for an empty cache, and on the belief that a lifecycle command runs
   as root at every start (Context). What that decision leaves open is in items 12 to 14.
3. **Distribution families.** Decided by the maintainer: Debian/Ubuntu, RHEL/Fedora, Arch Linux, Alpine, and
   openSUSE/SUSE, each with its image in the compatibility list (Decisions); anything else fails.
4. **An option for the Python version of build-time tools** (for example `toolsPythonVersion`). Recommendation: not now;
   uv's default interpreter is enough for the known consumers, and an option can arrive as a MINOR.
5. **`PATH` in login shells on images whose `/etc/profile` resets it** (`debian:12`, `alpine:3.24`,
   `opensuse/leap:16.0`). Recommendation: `/etc/profile.d/uv.sh`, as specified. The alternative is no snippet and a spec
   narrowed to processes the dev container tooling starts, with the gap documented in `NOTES.md`.
6. **Tools with a uv release older than 0.12.16**, which installs PyPI packages with TLS only. Recommendation: fail the
   build, as specified. The alternative is to allow it as an explicit exception to the download rules in
   `.agents/knowledge/feature-authoring.md` (a registry package installed on TLS alone), stated as a Requirement in the
   spec and documented in `NOTES.md`.
7. **The contract for dependents that install tools into `/usr/local/share/uv/tools`.** No planned dependent does:
   `hf-cli` (#17) installs into a virtual environment in the remote user's home through Hugging Face's installer and
   uses neither `UV_TOOL_DIR` nor `UV_TOOL_BIN_DIR`. Recommendation: `NOTES.md` asks a future dependent that installs
   tools there to give them the group `uv` and the group write this feature uses, so the remote user's
   `uv tool upgrade --all` keeps working. The alternative is a separate tool directory per dependent, with its own `bin`
   on `PATH`.
8. **A root remote user: no group at all, or the group without a member.** The maintainer's decision skips root; whether
   that also skips creating the group was not said. Recommendation: no group, and both locations stay `root:root` 0755
   as before this revision, which is what the trial ran and what the spec's "Root remote user" encodes; five of the six
   compatibility images run as root, and `test.sh` branches on it. The alternative is to create the group on every image
   and give the directories to `root:uv`, as most first-party features do, so that a user added later could be put in
   the group by hand.
9. **A group `uv` that is the remote user's primary group.** The CLI's UID change renumbers the primary group but not
   the directories, so the group access is lost exactly where it is needed (Context). Recommendation: fail the build
   with a message, checked with the remote user before any download, as the spec's "Group is the remote user's primary
   group" encodes; otherwise the feature would work on a host that changes no UID and fail on one that does, which is
   the defect this revision removes. Not prototyped. The alternative is no check, with the limit stated in the spec and
   in `NOTES.md`.
10. **A group `uv` the image already has, with accounts in it.** The maintainer chose the group on the premise that the
    remote user is its only member, and nothing was said about a group that is already there. Its members, and an
    account whose primary group it is, which the member list does not show, would get what the remote user gets: write
    access to the directory that is first in `PATH`, for root's shells too, and to the top level of the volume
    (Context); and the remote user would join a group the feature did not create and gain whatever that group already
    grants in the image. Recommendation: fail the build with a message when another account belongs to the group, as the
    spec's "Group has other members" encodes, and use an existing group only when it has no member or only the remote
    user, which keeps a second install working. That keeps the premise, and it can be relaxed in a later MINOR, while a
    reuse granted now could be withdrawn only in a MAJOR. Its price: an image that shares a group `uv` on purpose cannot
    use the feature, and a second install for another non-root remote user fails instead of handing the directories
    over, as the owner-based layout did. Not prototyped. The alternative is to reuse the group with its members, as most
    first-party features do with theirs, with the wider access stated in the spec and in `NOTES.md`; a second install
    for another remote user then leaves the first one a writer.
11. **The owner of the two locations: the remote user, or root.** The maintainer's outline names the remote user as
    owner, and the package encodes that. After a UID change that owner is a number without an account, which the next
    account created can receive (BusyBox `adduser` gives out the first free UID from 1000; Context), and a host that
    changes no UID exercises the owner's access while one that does exercises the group's, the split that hid this
    revision's defect. With root as owner and the same group and modes, the remote user writes through the group on
    every host and no UID is left behind; the 16 operations passed that way on `alpine:3.24` (Context). Recommendation:
    root as owner. It departs from the outline and from the first-party features, which keep the user as owner, so it is
    the maintainer's call; approving the package as written keeps the remote user as owner. With root as owner, the
    spec's "the owner the install set" becomes root, and the `changed_uid` scenario shows the UID change by the user's
    UID instead of by the owner. The repair does not depend on this choice: it looks below the volume's root, and a root
    the remote user can write through the group fits under either owner.
12. **Images whose remote user has no passwordless sudo.** The package warns there and leaves the volume as it is.
    Recommendation: accept that for `1.0.0`, with the repair by hand in `NOTES.md`; the accounts the first-party images
    and `common-utils` create have passwordless sudo. The alternative is a root `entrypoint` that repairs the volume and
    writes a marker at each container start, with the lifecycle command waiting for the marker so that the user's
    commands cannot run ahead of it; one run on `debian:12` without sudo showed it working (Context). It needs a
    container user that is root, adds an `entrypoint`, which runs at every start, to the feature's metadata, and was not
    tried with `dockerComposeFile` or `overrideCommand: false`. It can arrive later as a MINOR.
13. **The check on an image without `find`** (`opensuse/leap:16.0`). Recommendation: read the owners from a listing the
    image can produce, chosen and observed during implementation on that image (Goals), and come back to the maintainer
    before implementing if none proves reliable. The alternatives are to install `findutils` as a fifth prerequisite,
    which changes the spec's "Install download prerequisites only from the image's repositories", or to repair without
    the check on such an image, which runs `sudo` on a volume that fits, against "Volume that fits". Not prototyped.
14. **`onCreateCommand` only, or `postStartCommand` as well.** `onCreateCommand` covers a rebuild and the first run as
    another remote user. `postStartCommand` would also repair, at the next start, what root wrote while the container
    ran (`sudo uv`), at the price of the walk at every start, seconds on a cold page cache for a large volume, and it
    runs after the point tools wait for by default. Recommendation: `onCreateCommand` only; the notes name `sudo uv` as
    a cause and the next rebuild as the repair.
