// Constants every script may import without pulling in a dependency. This module imports nothing,
// so a script that runs with a write token (scripts/sync_pr_labels.ts) can take its one constant
// from here and keep remote code out of its job; scripts/lib/repo.ts re-exports it for the rest.

/** GitHub repository, which is also the OCI namespace path the features are published under. */
export const REPO = "hoshiori-dev/devcontainer-features";
