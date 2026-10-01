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
    write. A second, different UID on a volume the first one filled therefore fails where it must write into the first's
    directories (`uv python install`, 15 of 16), and passes with umask 002 for both.
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
  is in it, and what it may write; the volumes the feature does not repair (Non-Goals), and that the owner and group a
  kept volume carries are numbers a rebuilt image may give to another account or group (Risks); and the upstream
  references of the spec's Purpose. Checked by review of `NOTES.md` against the spec.
- Nothing a rebuild replaces holds a path a workspace `.venv/` links to: interpreters uv installs at runtime exist only
  on the volume. Checked by a real rebuild of a dev container built from the `changed_uid` scenario's Dockerfile with
  that user as `remoteUser`, so that the CLI changes the UID on a host with UID 1000 as well, where the Ubuntu base
  image's `vscode` would keep its own: `devcontainer up`, a workspace `.venv/` with a managed interpreter and a package,
  then `devcontainer up --remove-existing-container`, which replaces the container and keeps the volume, and the
  `.venv/` used once more. The record shows, before and after the rebuild, the output of `id` and the owner of
  `/var/lib/uv`, which is not the running user.

**Non-Goals:**

- Creating or syncing a project environment at build time, setting `UV_PROJECT_ENVIRONMENT`, or installing a system
  Python through the distribution's package manager (the issue's Out of scope). The workspace `.venv/` stays where uv
  puts it.
- Persisting tools installed at runtime: their environments live in the image's `UV_TOOL_DIR` and go with a rebuild
  (their interpreters, on the volume, stay).
- Persisting executables that `uv python install` places in `~/.local/bin`; uv's default stays.
- Repairing a volume that already holds data (Open Questions, item 2): one filled under one UID and then used under
  another, because the host user or the remote user changed (what the first UID created has the group `uv` but no group
  write under the usual umask 022); and one whose group ID no longer is the ID of `uv` in a rebuilt image.
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
  and interpreters would leak into another); a host bind mount (depends on a host path); no mount (the issue's problem).
- **Write access through a group, set in the image, not through the owner and not at runtime** (maintainer decision of
  2026-10-01, replacing "ownership through the mount point"). A non-root remote user is a member of a system group `uv`;
  the image's empty `/var/lib/uv` and all of `/usr/local/share/uv` keep the remote user as owner and get the group `uv`,
  group write, setgid on directories, and no write access for others, and Docker copies owner, group, and mode of the
  mount point into a new volume. The membership names the user and the group is not the user's primary one, so the CLI's
  UID change leaves both alone (Context): the remote user then writes as a member where it is no longer the owner. The
  owner stays the remote user for the hosts on which no UID changes. Rejected: ownership alone, the approach this
  replaces (the CLI changes the UID and re-owns only the home folder, so the directories and every new volume belong to
  a UID the remote user no longer has; it passed locally and failed in CI); an `entrypoint`, `postStartCommand`, or
  other lifecycle command that runs `chown` (runs as root on every start, widens metadata, and cannot run as root in
  every setup); a world-writable volume or tool directory (any account in the container could then replace what is first
  in `PATH`); asking users to set `updateRemoteUserUID` to `false` (it is the user's property, which a feature cannot
  set, and its default exists so that the bind-mounted workspace matches the host user; the feature would then work only
  in configurations that give that up); a fixed ID for the group (it can collide with a group of the image, and none of
  the first-party features read in Context pins one); a group-writable umask for the remote user, which would also cover
  what uv creates at runtime (it changes the mode of every file the user creates, uv's or not, and only in shells that
  read the profile); leaving uv's build-time lock files at the mode uv gives them, 0666 (files any account can write and
  lock, in a tree whose `bin` is first in `PATH`, against the proposal's "Stays true"; removing other-write costs a user
  outside the group `uv tool list`, Context).
- **The group comes from the image's own account tools, shadow first, BusyBox second.** `groupadd` and `usermod` where
  the image has them, BusyBox `addgroup` otherwise, and a failure with a message when a step is needed and neither
  exists. A group `uv` the image already has is used with its ID when it has no member or only the remote user, which a
  second install finds, and refused when another account belongs to it; reusing it with its members is the alternative
  of Open Questions, item 10. Rejected: trying `addgroup -S` first (Debian's `addgroup` rejects it); installing the
  `shadow` package on Alpine (a package for one line in `/etc/group`); writing `/etc/group` directly (a free ID has to
  be picked by hand, and on images with `/etc/gshadow` `grpck` then reports the missing entry); creating the group for a
  root remote user as well, as most of the first-party features read in Context do (root needs no group, and an image
  with a root remote user would carry an account entry nothing uses; Open Questions, item 8).
- **`UV_LINK_MODE=copy`.** The cache volume and the workspace bind mount are always different filesystems, so the
  default `clone` always falls back to copying and warns on every install. Rejected: the default (the warning);
  `hardlink` (impossible across filesystems); `symlink` (uv discourages it: cleaning the cache breaks environments).
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

| Surface               | Bound                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Downloads             | HTTPS only; exactly the URLs in the URL inventory; no installer script; no URL, path, or option from a user option reaches curl or uv (validation above).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Verification          | uv archive: SHA-256 from the same release's `.sha256`, checked before unpacking. `latest` redirect: TLS alone, stated in the spec's "Verify the uv release before installing it". Managed interpreters: SHA-256 compiled into uv, checked by uv. PyPI packages: SHA-256 supplied by the index, checked by uv 0.12.16 or later; the feature refuses tools with an older release and adds no pin of its own.                                                                                                                                                                                                                                                                                                                                                                                                                |
| Keys                  | None. uv publishes no signing key; the feature installs no repository key.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| `mounts`              | One named volume `uv-${devcontainerId}` → `/var/lib/uv`, needed so interpreters and cache survive a rebuild; no bind mount, no host path.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| `containerEnv`        | `UV_PYTHON_INSTALL_DIR`, `UV_CACHE_DIR`, `UV_TOOL_DIR`, `UV_TOOL_BIN_DIR`, `UV_LINK_MODE`, and `PATH` with `/usr/local/share/uv/bin` prepended; nothing secret, nothing that changes an index or a download source.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Shell startup         | `/etc/profile.d/uv.sh` (root-owned, mode 0644) prepends `/usr/local/share/uv/bin` to `PATH` when it is missing; nothing else.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| `installsAfter`       | `ghcr.io/devcontainers/features/common-utils` (ordering only).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| `dependsOn`           | None.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Not used              | `privileged`, `capAdd`, `securityOpt`, `entrypoint`, `init`, lifecycle commands.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| Accounts              | One system group `uv`, created only for a non-root remote user and only when the image has none; no user, no password, no sudo rule. When the install ends its only member is the remote user: a group `uv` the image already has is used only when no other account belongs to it, as a listed member or through its primary group (Open Questions, item 10). An account added to the group later, or given it as primary group, shares the write access below.                                                                                                                                                                                                                                                                                                                                                          |
| Files owned by a user | When the remote user is not root, `/var/lib/uv` (empty mount point, mode 2775) and `/usr/local/share/uv/` (group write, setgid directories) have that user as owner and `uv` as group; the install leaves nothing writable by others, uv's lock files included, and for root nothing writable by group or others. Writers are root, the members of `uv`, and the build-time UID, which after a UID change belongs to no account until one is given it: that account then owns both locations. BusyBox `adduser` gives the next account that UID when it is the first free one from 1000, observed on `alpine:3.24`; shadow `useradd` on the Ubuntu base image did not (Open Questions, item 11). What is created at runtime has the modes of uv and of the creating user's umask; uv's lock files on the volume are 0666. |
| `PATH`                | `/usr/local/share/uv/bin`, first in `PATH`, stays writable by a non-root account, as accepted with Open Questions item 1. The group changes how the remote user gets that access, not who has it, while the remote user is the group's only member.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Idempotency           | Same release skips the download; binaries replaced by rename; tool installs are additive; `/etc/profile.d/uv.sh` overwritten whole; directories, the group, and the membership created only if missing; group and modes applied again on every install.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Failure behavior      | As in the spec's "Fail on unsupported platforms and invalid options", "Verify the uv release before installing it", "Option version", and "Option toolsToInstall"; a remote user that does not exist, a group `uv` that is the remote user's primary group or to which another account belongs, and an image without a tool to create the group or to add the member each fail the install.                                                                                                                                                                                                                                                                                                                                                                                                                               |

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

Every URL the feature's scripts access. The feature has no start-time script, so nothing is fetched at start. The
feature configures no package repository: prerequisites come from the repositories the image already has. Rows 5–8 are
accessed at build time only when `toolsToInstall` is not empty, by uv itself on the feature's behalf; the same hosts
serve the remote user's own uv commands at runtime.

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
  volume or a tool one UID filled is only partly usable by another: a later, different UID fails where it writes into
  the first's directories (Context)] → Accepted: one dev container's volume is used by one host user, and a rebuild for
  the same host user keeps the UID. `NOTES.md` names the case and the remedy, removing the volume (Non-Goals).
- [A volume keeps the numeric owner and group it got when it was created. If a rebuilt image gives `uv` another ID,
  because the base image or a feature installed earlier added a system group, a remote user whose UID was changed can no
  longer create entries directly in `/var/lib/uv`; `python/` and `cache/`, once that user created them, stay usable. The
  numbers the volume keeps may then name another group or account of the rebuilt image, whose members can write the
  volume's top level and so rename and replace `python/` and `cache/`, which the remote user's uv runs from. Inferred
  from the facts in Context (group semantics and the rename a second member performed), not run] → Accepted and
  documented in `NOTES.md` with the same remedy, removing the volume after a change of base image, feature set, or
  remote user; a fixed ID was rejected (Decisions).
- [A volume that the owner-based layout created and filled keeps its owner and mode and fails after a UID change, as it
  did before] → No release carried that layout; the volumes exist only on machines that ran this branch's tests, where
  `docker volume rm` removes them.
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
2. **A volume that already holds data and no longer fits its user.** The case that was not rare, the CLI changing the
   remote user's UID before the volume is first created, is now covered by the group. What remains is a volume filled
   under one UID and used under another (another host user, another remote user) and a rebuilt image in which `uv` has
   another group ID (Non-Goals, Risks). Recommendation: no runtime fix; `NOTES.md` documents removing the volume. An
   `entrypoint` that repairs owners or modes would widen metadata, and the spec's "change nothing on a volume that
   already holds data" encodes this recommendation.
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
    UID instead of by the owner.
