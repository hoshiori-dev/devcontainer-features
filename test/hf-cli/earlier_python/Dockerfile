FROM python:3.12-slim-bullseye
# Debian 11 supplies a real older interpreter; the existing /usr/local Python remains usable.
# Its security package URLs now return 404. Use Debian's signed main snapshot;
# this suite has no Valid-Until header, so no verification setting is disabled.
RUN rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources \
    && printf 'deb [signed-by=/usr/share/keyrings/debian-archive-keyring.gpg] https://snapshot.debian.org/archive/debian/20260801T000000Z/ bullseye main\n' > /etc/apt/sources.list \
    && apt-get update && apt-get install -y --no-install-recommends python3 \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /usr/local/python/current/bin \
    && ln -s /usr/bin/python3 /usr/local/python/current/bin/python3 \
    && ln -s /usr/local/bin/python3 /usr/local/python/current/bin/python
