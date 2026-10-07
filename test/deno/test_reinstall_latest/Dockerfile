# A stub deno that reports 2.8.0, as an earlier install would, and a tool already in the global
# tools directory. test_reinstall_same_version and test_reinstall_latest each hold an identical
# copy of this file; change both together.
FROM debian:12
RUN printf '#!/bin/sh\necho "deno 2.8.0 (stable, release, x86_64-unknown-linux-gnu)"\n' >/usr/local/bin/deno \
    && chmod 0755 /usr/local/bin/deno \
    && sha256sum /usr/local/bin/deno >/opt/deno-stub.sha256 \
    && mkdir -p /usr/local/share/deno/bin \
    && printf '#!/bin/sh\necho "preinstalled tool"\n' >/usr/local/share/deno/bin/preinstalled-tool \
    && chmod 0755 /usr/local/share/deno/bin/preinstalled-tool
