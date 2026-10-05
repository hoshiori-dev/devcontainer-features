# Design

## Context

See [proposal.md](proposal.md) for motivation. Upstream recommends `uv tool install google-colab-cli`, exposes the
`colab` command, and requires Python >=3.12 in its
[package metadata](https://github.com/googlecolab/google-colab-cli/blob/main/pyproject.toml), checked on 2026-10-05. The
repository's uv feature already provides tool storage, PATH integration, and the `uv` group. Its managed Python
directory normally points into a runtime volume, which cannot hold the interpreter used by a build-time tool.

## Goals / Non-Goals

**Goals:**

- Reuse the uv dependency's tool directories and group integration; check through metadata, tool listing, permissions,
  and non-root scenarios, including a changed UID.
- Keep the build-time interpreter in the image; check the tool interpreter's resolved path and run with an empty uv
  volume mounted at runtime.
- Use an isolated installation environment; check that alternate uv environment settings and configuration files cannot
  redirect the package index or disable verification.

**Non-Goals:**

- Change the dependency's implementation or lifecycle hooks; verify the diff touches only the new feature, tests, and
  this change record.
- Change system Python commands or introduce an additional Python feature; verify their state before and after install.

## Decisions

### Dependency and installation

Declare `dependsOn` with `ghcr.io/hoshiori-dev/devcontainer-features/uv:1` and empty dependency options. Install the CLI
separately so the new feature's `version` controls the package. Require uv >=0.12.16 for index hash verification,
matching the dependency's existing minimum for build-time tools. Use `uv tool install --python 3.12 --managed-python`
with `/usr/local/share/uv/python` for managed interpreters, `/usr/local/share/uv/tools` for tool environments, and
`/usr/local/share/uv/bin` for executables. Cache only in a temporary directory removed on exit.

Run uv with a clean environment and `--no-config`, supplying only required locale, system PATH, temporary HOME/cache,
tool directories, and managed Python selection. The runtime uv environment and the remote user's home remain as the
dependency configured them. Package sources and interpreter checks follow the delta spec; no shell installer or
additional package repository is needed.

An `installsAfter` entry alone would not install uv. Configuring the dependency's `toolsToInstall` with a static package
would not implement this feature's version option. A pip/system-Python approach would conflict with the user's choice
and require additional interpreter provisioning. A private tool directory would add PATH and ownership integration
already supplied by uv.

### Version selection and repeated installation

Pass a validated exact release as `google-colab-cli==<version>`. Inspect installed package metadata and the interpreter
path to skip a matching exact release only when it already uses managed Python 3.12 in the image.

For `latest`, use uv's package upgrade semantics and compare the installed release against the newest stable release
listed by `https://pypi.org/simple/google-colab-cli/`. Read that endpoint's JSON representation through the
[Simple Repository API](https://packaging.python.org/en/latest/specifications/simple-repository-api/). Exclude yanked
files, prereleases, and development releases when selecting `latest`. For an existing installation with the correct
interpreter, check the index before invoking uv and skip package installation when the release matches. Verify the
result after installation as well: if uv selected an older release because the newest one requires a newer Python, fail
rather than report that older release as `latest`.

Run version and help probes without authentication, then restore permissions, including bytecode directories created by
those probes. A changed version replaces the same tool environment, including a downgrade requested by an exact pin. No
prerelease selector, URL, arbitrary requirement, or leading `v` is accepted.

| Option  | Type   | Default  | Enum | Meaning                                    |
| ------- | ------ | -------- | ---- | ------------------------------------------ |
| version | string | `latest` | None | Newest stable release or MAJOR.MINOR.PATCH |

The [Option version requirement](specs/colab-cli/spec.md#requirement-option-version) defines the option contract;
suggested values live in feature metadata. `latest` follows the collection's CLI convention. An exact release stays
available for reproducible builds. Additional Python/version/index options would widen the contract without helping the
requested installation and are excluded.

### Ownership and compatibility

New paths created under uv's shared tree inherit the dependency's remote-user/group model. Restore owner and group
permissions for the installed tool and newly downloaded interpreters without changing unrelated tool contents or
granting write access to everyone. Group write access must survive a remote-user UID change; root installations remain
writable by root. Reuse the dependency's PATH integration, including login shells, rather than adding another profile
snippet or symlink.

Initially declare `mcr.microsoft.com/devcontainers/base:ubuntu24.04` with remote user `vscode`, and `debian:12` with
root, both on amd64 and arm64; run scenarios on both architectures. These pairs belong to uv's supported matrix and
provide glibc hosts for CPython and package wheels without adding native build prerequisites. Bash is available in these
images. Other distributions, including Alpine, are outside the initial matrix; broad uv support alone does not prove the
CLI's dependency wheels work on every libc and image.

The `uv_and_colab_cli` global scenario selects both features on the Ubuntu image as `vscode`, pinning uv to 0.12.16 and
configuring two build-time tools. It checks that colab-cli's dependency declaration preserves the explicit uv version
and tools, as well as uv's runtime variables, tool directories, writable volume, and login-shell integration. Managing
one configured tool must leave the other tool and colab runnable. This verifies the existing uv contract without
changing either feature's installation behavior or the global test infrastructure.

## Risks / Trade-offs

- Upstream may raise its Python minimum above 3.12: latest then fails clearly; a future change can review interpreter
  policy, while exact pins remain available.
- Latest is resolved at build time and can change between build and verification: tests compare against the installed
  package and PyPI's stable release metadata; a release race requires a rerun.
- PyPI's transitive dependencies can change: exact package versions do not lock the full dependency graph; uv verifies
  fetched files against the index, and compatibility tests validate the resolved installation.
- Sharing uv's tool store exposes normal `uv tool` upgrades/uninstalls to the remote user: this matches the dependency's
  contract and avoids a separate management interface.

## Migration Plan

This is a new feature at `1.0.0`; existing consumers require no migration. Publication follows the repository's normal
review, explicit archive command, maintainer merge, and release workflow.
