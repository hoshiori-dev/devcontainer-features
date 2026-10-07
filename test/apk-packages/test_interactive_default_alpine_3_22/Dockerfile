# alpine:3.22 with util-linux-misc, added with the image's own package manager for its script command: the scenario
# needs a terminal, the test harness attaches none, and BusyBox has no applet that opens one. The index apk fetched
# for it is removed, so /var/cache/apk is empty as in the compatibility image.
FROM alpine:3.22

RUN apk add --no-cache util-linux-misc \
  && rm -f /var/cache/apk/*
