# Proposal

## Why

Developers who script parametric CAD models, convert CAD files, or write FreeCAD macros and workbenches, and coding
agents that need a CAD kernel they can drive from the command line, need the official FreeCAD build inside their dev
container. Upstream ships it for Linux only as an AppImage, which cannot start in a container without FUSE, so today
they unpack it by hand, usually without verifying it.

Implements https://github.com/hoshiori-dev/devcontainer-features/issues/214.

## What Changes

- Add the `freecad` feature, initially version `1.0.0`, which installs an official FreeCAD release build for every user
  of the container, with a single `version` option selecting the newest stable release, the newest release of a series,
  or an exact release.
- Define where releases come from and how a release is verified; weekly and other pre-release builds are never
  installed.
- Put two commands on `PATH`: `freecadcmd` for use without a display, and `freecad` for the GUI.
- Make the GUI able to start on a display the developer provides, by installing the system libraries the release build
  leaves to the host; the feature installs no display server.
- Define supported platforms (amd64 and arm64), conflicts with other FreeCAD installations, repeated installation, and
  recovery from a failed replacement.
- Document command-line use for scripts and agents, and how to give the GUI a display, in `NOTES.md`.

## Capabilities

### New Capabilities

- `freecad`: installation, release selection and verification, and command-line and GUI readiness of FreeCAD in a dev
  container.

### Modified Capabilities

None.

## Impact

The implementation adds `src/freecad/`, `test/freecad/`, and `openspec/specs/freecad/`; the feature `freecad` begins at
`1.0.0`, and no other feature's version changes. The generated feature README and the root feature list gain FreeCAD,
with the matching translation in `README.zh.md`. The approval package contains no task list; `tasks.md` follows the pull
request's `spec:approved`.

## Acceptance

**Becomes true**

- The scenarios of the delta spec's Option version, Release resolution, Stable releases only, Release asset, Verified
  official AppImage, and Checksum trust requirements establish release selection and integrity.
- Its Unpacked installation, Supported platforms, Runtime libraries, System-wide installation, Commands, Launch
  environment, Unchanged installation tree, Command-line use, and GUI use scenarios that a successful container build
  can show hold on every image and architecture in `test/freecad/compatibility.json`, for root and for the image's
  remote user; the rejection scenarios hold in the checks design.md names for them, run once.
- Its Existing installation conflicts, Repeat installation, and Failed replacement scenarios establish preservation of
  foreign and previous installations and repeatable installation.
- Its Upstream defaults and Usage guidance scenarios establish that the feature changes none of FreeCAD's own defaults
  and that the documented examples work as written.
- `src/freecad/devcontainer-feature.json` has version `1.0.0`, with its install-twice test, NOTES, and generated
  documentation; `just check`, `just test freecad`, and `just test-scenarios freecad` pass.

**Stays true**

- Existing features keep their options, behavior, and versions.
- Nothing the feature installs comes from a source other than the FreeCAD project's GitHub releases and the image's
  configured package repositories.
- The feature adds no mount, privileged mode, capability, security option, entrypoint, or lifecycle command, and starts
  no process when the container starts.
