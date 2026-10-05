FROM debian:12
# Build inputs try to redirect the installer, its package clients and its home.
ENV UV_DEFAULT_INDEX=https://index.invalid/simple UV_INDEX_URL=https://index.invalid/simple \
    PIP_INDEX_URL=https://index.invalid/simple PIP_EXTRA_INDEX_URL=https://index.invalid/simple \
    HF_CLI_PIP_ARGS=--invalid-build-option HF_PIP_ARGS=--invalid-build-option HF_HOME=/invalid-hf-home \
    UV_INSECURE_HOST=index.invalid PIP_TRUSTED_HOST=index.invalid
RUN mkdir -p /etc/uv && printf 'index-url = "https://index.invalid/simple"\n' > /etc/uv/uv.toml \
    && printf '[global]\nindex-url = https://index.invalid/simple\n' > /etc/pip.conf
