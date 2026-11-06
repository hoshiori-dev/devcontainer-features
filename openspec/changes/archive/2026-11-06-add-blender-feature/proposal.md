# Proposal

## Why

Developers who write Blender add-ons and extensions, and coding agents that need a 3D tool they can drive from the
command line, need the official Blender build inside their dev container. Today they would have to download and unpack
it by hand, and many published container recipes fetch it from third-party mirrors without verifying it.

Implements https://github.com/hoshiori-dev/devcontainer-features/issues/186.

## What Changes

- Add the `blender` feature, initially version `1.0.0`, which installs an official Blender release build for every user
  of the container, with a single `version` option selecting the newest release, the newest release of a series, or an
  exact release.
- Define where releases come from, how a release is verified, and why Blender's mirror network is never used.
- Make headless use work on CPU-only containers: Python scripting, and rendering with Cycles, Workbench, and EEVEE in
  background mode, without a display server or GPU.
- Make extension development work offline: validating, building, and installing an extension package with Blender's own
  command line.
- Define supported platforms (amd64 only, since Blender publishes no Linux arm64 build), conflicts with other Blender
  installations, repeated installation, and recovery from a failed replacement.
- Document headless use for scripts and agents, and the extension workflow, in `NOTES.md`.

## Capabilities

### New Capabilities

- `blender`: installation, release selection and verification, and headless and extension-development readiness of
  Blender in a dev container.

### Modified Capabilities

None.

## Impact

The implementation adds `src/blender/`, `test/blender/`, and `openspec/specs/blender/`; the feature `blender` begins at
`1.0.0`, and no other feature's version changes. The generated feature README and the root feature list gain Blender,
with the matching translation in `README.zh.md`. The approval package contains no task list; `tasks.md` follows the pull
request's `spec:approved`.

## Acceptance

**Becomes true**

- The scenarios of the delta spec's Option version, Release resolution, Verified official archive, Download host, and
  Checksum trust requirements establish release selection and integrity.
- Its Supported platforms, Runtime libraries, System-wide installation, Precompiled bytecode, and Headless rendering
  scenarios that a successful container build can show hold on every image in `test/blender/compatibility.json`, for
  root and for the image's remote user; the rejection scenarios and the Extension development scenario hold in the
  checks design.md names for them, run once.
- Its Existing installation conflicts, Repeat installation, and Failed replacement scenarios establish preservation of
  foreign and previous installations and repeatable installation.
- Its Upstream defaults and Usage guidance scenarios establish that the feature changes none of Blender's own defaults
  and that the documented examples work as written.
- `src/blender/devcontainer-feature.json` has version `1.0.0`, with its install-twice test, NOTES, and generated
  documentation; `just check`, `just test blender`, and `just test-scenarios blender` pass.

**Stays true**

- Existing features keep their options, behavior, and versions.
- Nothing the feature installs comes from a host other than `download.blender.org` and the image's configured package
  repositories.
- The feature adds no mount, privileged mode, capability, security option, entrypoint, or lifecycle command, and enables
  no network access for Blender itself.
