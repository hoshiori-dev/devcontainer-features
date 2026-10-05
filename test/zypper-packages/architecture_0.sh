#!/bin/bash
set -e
[ "$(rpm -q --qf '%{ARCH}' bc)" = x86_64 ]
