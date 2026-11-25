# debian:13 with a Go toolchain of the image's own, first on PATH: a stand-in that fails whenever it runs, with a
# digest the test compares it against. The feature must build with its own toolchain and leave this one alone.
FROM debian:13
RUN mkdir -p /usr/local/go/bin \
    && printf '#!/bin/sh\necho "the go of the image: the feature must not run it" >&2\nexit 1\n' >/usr/local/go/bin/go \
    && chmod +x /usr/local/go/bin/go \
    && sha256sum /usr/local/go/bin/go >/usr/local/go/digest
ENV PATH=/usr/local/go/bin:$PATH
