#!/bin/bash
set -e
rpm -q less >/dev/null
! rpm -q file >/dev/null 2>&1
