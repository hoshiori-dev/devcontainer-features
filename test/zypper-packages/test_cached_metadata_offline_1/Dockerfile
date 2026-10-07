# opensuse/tumbleweed with a zypp configuration file that moves libzypp's caches, the repository metadata refreshed
# into them, and bc installed from it: what a run of the feature with ZYPP_CONF and cleanup=none leaves. The scenario
# then runs install.sh without a network.
FROM opensuse/tumbleweed

RUN printf '[main]\ncachedir=/tmp/owned-zypp\nmetadatadir=/tmp/owned-metadata\n' >/tmp/custom-zypp.conf \
  && ZYPP_CONF=/tmp/custom-zypp.conf zypper --non-interactive refresh \
  && ZYPP_CONF=/tmp/custom-zypp.conf zypper --non-interactive --no-refresh install --no-recommends -- bc
