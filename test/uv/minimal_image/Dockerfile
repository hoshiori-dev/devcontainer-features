# "Minimal image": debian:12 without curl or CA certificates. Records a SHA-256 of every apt
# source and signing key before the feature installs its prerequisites; minimal_image.sh compares.
FROM debian:12

RUN if command -v curl >/dev/null || [ -e /etc/ssl/certs/ca-certificates.crt ]; then \
        echo "debian:12 now ships curl or CA certificates; pick an image without them" >&2; exit 1; \
    fi \
    && mkdir -p /opt/uv-test \
    && find /etc/apt /usr/share/keyrings -type f \
        \( -path '/etc/apt/sources.list*' -o -path '/etc/apt/trusted.gpg*' -o -path '/usr/share/keyrings/*' \) \
        -exec sha256sum {} + | sort >/opt/uv-test/apt-before.sha256 \
    && test -s /opt/uv-test/apt-before.sha256
