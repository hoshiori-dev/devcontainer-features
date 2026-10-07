# An image without pacman, outside the compatibility list, whose /bin/sh is busybox (Docker Hub official image). bash is
# added for the test script and its library; the feature's install.sh runs under the image's /bin/sh.
FROM alpine:3.24@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6

RUN apk add --no-cache bash
