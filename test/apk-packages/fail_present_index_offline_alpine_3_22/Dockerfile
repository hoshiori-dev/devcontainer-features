# alpine:3.22 with a configured cache, /etc/apk/cache, that holds a fresh package index and the package files of file
# and its dependencies. The scenario then runs without a network.
FROM alpine:3.22

RUN ln -s /var/cache/apk /etc/apk/cache \
  && apk update \
  && apk cache download file
