# Proposal

Implements [#60](https://github.com/hoshiori-dev/devcontainer-features/issues/60), part of the epic
[#127](https://github.com/hoshiori-dev/devcontainer-features/issues/127) (package-manager features: phase 2 controls).

## Why

After phase 1 a developer can list packages and choose the cleanup policy, but cannot say which of the image's
repositories a package comes from, and cannot change how many downloads `pacman` runs at once without editing the
image's `pacman.conf`. Both are choices among things the image already provides. The epic asks each package-manager
feature to expose such choices where its manager supports them, and to behave exactly as after phase 1 when none is
used.

## What Changes

- An entry of `packages` may name one of the image's configured repositories in `pacman`'s own `repository/target` form,
  so that `pacman` resolves that entry only there. Entries without a repository behave as before.
- A new option `parallelDownloads` sets the number of simultaneous downloads for the feature's one `pacman` call. Left
  empty, the image's own setting applies and the call is the one phase 1 makes.
- The spec states what the feature does not control because `pacman` offers no bounded native control for it: download
  retries, waiting for the database lock, numeric timeouts, and proxies. The image's and `pacman`'s own behavior
  applies, and NOTES.md documents it.
- Entries that hold one `/` and were refused by every earlier version can now be accepted. Paths, URLs, and every other
  entry refused before stay refused.

Not part of this change: custom `CacheDir` or `DBPath` handling (cleanup keeps its two default directories), a switch
for `--disable-download-timeout`, enabling repositories the image ships disabled, historical versions, and any downgrade
or conflict policy (phase 3). The design records why, and its open questions list what the maintainer is asked to
confirm.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pacman-packages`: the entry grammar gains the repository qualifier; the option `parallelDownloads` is added; the
  validation, authentication, and install-twice requirements are extended to cover both; one requirement states the
  controls the feature leaves to the image.

## Impact

- Feature ids touched: `pacman-packages`, version 1.0.1 to 1.1.0 (MINOR: a new option and backward-compatible new
  behavior, `.agents/knowledge/feature-authoring.md`, Versions). No other feature is touched.
- The main spec's Purpose and its "Upstream sources" list stay as they are: the change adds no reference link the list
  lacks (pacman.conf(5) is already named in a requirement), so this package carries no Purpose correction.
- Implementation after approval: `src/pacman-packages/install.sh`, `devcontainer-feature.json`, `NOTES.md`, the
  generated `README.md`, and the feature's tests under `test/pacman-packages/`. No compatibility list, harness,
  workflow, or dev container configuration change.
- This commit carries the approval package only. The metadata version and the implementation follow the package gate.

## Acceptance

**Becomes true:**

- Every scenario of the delta spec's ADDED requirements "Option parallelDownloads", "Parallel downloads are bounded",
  and "Unsupported download controls stay native" passes on every image of `test/pacman-packages/compatibility.json`,
  with the check, image, and result recorded in the PR.
- Every scenario the delta adds to the MODIFIED requirements passes there too: "Repository-qualified entry is accepted",
  "Malformed repository qualifier is refused" (Entries are validated before anything changes); "Qualified entry resolves
  in the named repository", "Qualified entry outside the named repository fails", "Unknown repository fails",
  "Repository name is matched exactly", "Qualified entry is not a pin", "Qualified entry reaches a repository not
  enabled for installation", "Qualified entry offering an older version" (Entries select packages as pacman matches
  them); "Explicit parallel downloads keep the image configuration" (Repository authentication stays in effect);
  "Parallel download boundaries are validated" (Installation controls are validated before changes); "Download controls
  do not persist to the second install" (Installing the feature twice).
- `parallelDownloads` agrees between the delta spec, `devcontainer-feature.json`, NOTES.md, and the generated README,
  and the feature's version is 1.1.0.
- NOTES.md carries the four sections the five package-manager features share ("What the feature sets explicitly", "What
  is inherited", "Proxy", "Locks and retries"), no longer says that every entry holding `/` is refused or that the
  feature uses no pacman configuration of its own, and labels as not verified every upstream fact the design marks so.
- `just check`, `just test pacman-packages`, and `just test-scenarios pacman-packages` pass.

**Stays true:**

- With `parallelDownloads` omitted and no qualified entry, the feature makes the same `pacman` call with the same
  arguments, creates no file of its own, and gives the same results as version 1.0.1; every scenario of the main spec
  that the delta does not modify still passes unchanged, and every scenario name of a MODIFIED requirement is kept.
- `packages` and `cleanup` keep their names, types, defaults, and values; `packages` keeps its proposals.
- An empty list stays a no-op on any image, also with a valid non-default control; an invalid control or entry still
  fails with status 1 before `pacman` is looked for.
- Signature checking, the image's repositories, mirrors, keyring, sandbox and download-user settings, and every file
  under `/etc/pacman.conf` and `/etc/pacman.d` stay as the image has them; no setting of the feature outlives its run.
- Every non-empty installation stays one transaction that is a full system upgrade; no partial upgrade, forced refresh,
  or downgrade switch is introduced.
- The compatibility images and architectures stay as they are, and the feature gains no privilege, mount, lifecycle
  hook, environment variable, or feature dependency.
