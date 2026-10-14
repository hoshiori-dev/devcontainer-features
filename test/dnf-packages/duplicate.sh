#!/usr/bin/env bash
# Install-twice test: the feature is installed with the `packages` list "bc,file" from its proposals and the enum value
# after each default (refreshPolicy=always, cleanup=packages, best=true), then with the defaults, whose list is empty.
# The values arrive as <OPTION> and <OPTION>__DEFAULT. The repository lists and parallelDownloads have no proposals, so
# both installations leave them empty; the scenarios test_repository_selection_* install twice with those set.
set -euo pipefail

# shellcheck source=/dev/null
source dev-container-features-test-lib

# The second installation's default best=inherit passes no override, so dnf reads the best policy from the image again.
best_values_are_as_expected() {
  [[ "${BEST-}" == true && "${BEST__DEFAULT-}" == inherit ]]
}

check "premise: the first installation ran with best=true and the second with best=inherit" best_values_are_as_expected
check "Installing the feature twice: bc, listed by the first installation, is left installed" rpm -q bc
check "Installing the feature twice: file, listed by the first installation, is left installed" rpm -q file

reportResults
