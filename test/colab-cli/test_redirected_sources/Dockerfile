FROM debian:12
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && python3 --version >/opt/system-python-version \
    && readlink -f /usr/bin/python3 >/opt/system-python-path \
    && mkdir -p /etc/uv \
    && printf 'index-url = "https://index.invalid/simple"\n' >/etc/uv/uv.toml
# These deliberately unusable settings must not reach the tool installer.
ENV UV_DEFAULT_INDEX=https://index.invalid/simple UV_INDEX_URL=https://index.invalid/simple \
    UV_PYTHON_INSTALL_MIRROR=https://python.invalid UV_PYTHON_DOWNLOADS=never \
    UV_INSECURE_HOST=pypi.org UV_NO_VERIFY_HASHES=1 UV_CONFIG_FILE=/etc/uv/uv.toml \
    PIP_INDEX_URL=https://index.invalid/simple
