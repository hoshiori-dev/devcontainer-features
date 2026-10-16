FROM almalinux:9

# EPEL configured by the image before the feature runs, with a marker line the feature must leave in place: the feature
# adds no repository when EPEL is already configured, and installs apptainer from it as it is.
RUN dnf -y install epel-release \
    && printf '%s\n' '# preconfigured-by-scenario' >> /etc/yum.repos.d/epel.repo \
    && dnf clean all
