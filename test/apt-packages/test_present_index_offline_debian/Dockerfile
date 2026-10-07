# debian:12 with a package index and the package files of bc, which the scenario then installs without a network.
FROM debian:12

RUN apt-get update --error-on=any \
  && apt-get install --download-only --yes --no-install-recommends bc
