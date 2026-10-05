#!/bin/bash
set -e
rpm -q ipcalc >/dev/null
! rpm -q geolite2-city >/dev/null 2>&1
