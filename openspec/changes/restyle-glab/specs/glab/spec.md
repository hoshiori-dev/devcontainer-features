# Spec Delta

## ADDED Requirements

### Requirement: Leave no build residue

The feature SHALL leave none of the repository metadata that the package manager fetched for the prerequisites it
installs: after installing with `apt-get` it SHALL leave apt's package lists empty, after installing with `dnf` it SHALL
leave dnf's cache without metadata or downloaded packages, and it SHALL install with `apk` without keeping a cache. No
temporary directory or staged binary of the install SHALL remain after an install, whether it succeeds or fails.

#### Scenario: Package-manager caches after install

- **WHEN** the feature has been installed with default options on an image listed in `test/glab/compatibility.json`
- **THEN** apt's package lists, dnf's cache, and apk's cache hold no file

#### Scenario: No install residue

- **WHEN** an install has finished, successfully or not
- **THEN** no temporary directory or staged binary of the install remains in the temporary directory or in
  `/usr/local/bin`
