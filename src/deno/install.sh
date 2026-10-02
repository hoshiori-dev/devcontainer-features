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
    *)
        for loader in /lib/ld-musl-*; do
            [ ! -e "${loader}" ] || fail "this image uses musl; Deno publishes glibc builds only."
        done
        fail "the C library could not be identified; Deno needs glibc 2.27 or newer."
        ;;
esac

# Read /etc/os-release in subshells: it defines VERSION, which would overwrite the option.
[ -r /etc/os-release ] || fail "cannot read /etc/os-release; supported families are Debian, Fedora, and openSUSE."
# shellcheck source=/dev/null
os_id="$(. /etc/os-release && echo "${ID:-}")"
# shellcheck source=/dev/null
os_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
# shellcheck source=/dev/null
os_name="$(. /etc/os-release && echo "${PRETTY_NAME:-${ID:-unknown}}")"
family=""
for word in ${os_id} ${os_like}; do
    case "${word}" in
        debian | ubuntu) family=debian ;;
        fedora | rhel | centos) family=fedora ;;
        opensuse) family=opensuse ;;
        *) continue ;;
    esac
    break
done
[ -n "${family}" ] || fail "unsupported distribution \"${os_name}\" (ID=${os_id}); supported families are Debian, Fedora, and openSUSE."

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

command -v bash >/dev/null 2>&1 || fail "bash is required after the platform checks."

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec bash "${script_dir}/scripts/install-deno.sh" "${target}" "${family}"
