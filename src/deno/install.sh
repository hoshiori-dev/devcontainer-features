#!/bin/sh
# Installs the Deno CLI. Runs as root at image build time; the option arrives as VERSION.
# POSIX sh on purpose: it holds only the platform checks, so an image without bash still gets a
# clear message. Once they pass, scripts/install-deno.sh does the rest in bash.
set -eu

fail() {
    echo "deno feature: $*" >&2
    exit 1
}

# C library first: a musl image must never get a distribution or architecture message.
glibc="$(getconf GNU_LIBC_VERSION 2>/dev/null)" || glibc=""
case "${glibc}" in
    "glibc "*) ;;
    *) fail "this image does not use glibc (musl-based images such as Alpine are unsupported); Deno publishes glibc builds only." ;;
esac

# Read /etc/os-release in subshells: it defines VERSION, which would overwrite the option.
[ -r /etc/os-release ] || fail "cannot read /etc/os-release; only Debian- and Ubuntu-based images are supported."
# shellcheck source=/dev/null
os_id="$(. /etc/os-release && echo "${ID:-}")"
# shellcheck source=/dev/null
os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
# shellcheck source=/dev/null
os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-${ID:-unknown}}")"
case " ${os_id} ${os_like} " in
    *" debian "* | *" ubuntu "*) ;;
    *) fail "unsupported distribution \"${os_name}\" (ID=${os_id}); only Debian- and Ubuntu-based images are supported." ;;
esac

glibc_version="${glibc#glibc }"
glibc_major="${glibc_version%%.*}"
glibc_minor="${glibc_version#*.}"
glibc_minor="${glibc_minor%%.*}"
case "${glibc_major}" in '' | *[!0-9]*) glibc_major="" ;; esac
case "${glibc_minor}" in '' | *[!0-9]*) glibc_minor="" ;; esac
if [ -z "${glibc_major}" ] || [ -z "${glibc_minor}" ]; then
    fail "cannot read the glibc version from \"${glibc}\"; Deno needs glibc 2.27 or newer."
fi
if [ "${glibc_major}" -lt 2 ] || { [ "${glibc_major}" -eq 2 ] && [ "${glibc_minor}" -lt 27 ]; }; then
    fail "glibc ${glibc_version} found; Deno needs glibc 2.27 or newer."
fi

machine="$(uname -m)"
case "${machine}" in
    x86_64) target="x86_64-unknown-linux-gnu" ;;
    aarch64 | arm64) target="aarch64-unknown-linux-gnu" ;;
    *) fail "unsupported architecture \"${machine}\"; Deno publishes Linux builds for amd64 (x86_64) and arm64 (aarch64) only." ;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec bash "${script_dir}/scripts/install-deno.sh" "${target}"
