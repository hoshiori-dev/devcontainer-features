# rockylinux/rockylinux:9 with the repository metadata and the package files of bc, which the scenario then installs
# without a network. The image's dnf configuration decides how long the metadata counts as unexpired (hours to days): a
# build cache that keeps this layer longer can hand the scenario expired metadata.
FROM rockylinux/rockylinux:9

RUN dnf install --assumeyes --downloadonly --setopt=install_weak_deps=False bc
