#!/usr/bin/env bash
# A curl stand-in that fail_installation.sh puts first on install.sh's PATH as `curl`. It appends every requested URL to
# ${FIXTURE_DIR}/requests, accepts only the two kinds of call install.sh makes, and answers them from the fixture
# releases the script builds under ${FIXTURE_DIR}/releases/<tag>/: the header-only read of the latest-release link
# prints the tag page of the tag in ${FIXTURE_DIR}/latest, and a download copies the release's file, or fails as curl
# --fail does on a 404 when the release has no such file or ${FIXTURE_DIR}/mode says so (checksum_list_404,
# archive_404; serve otherwise).
set -euo pipefail

readonly LATEST_URL="https://github.com/godotengine/godot/releases/latest"
readonly TAG_URL="https://github.com/godotengine/godot/releases/tag"
readonly DOWNLOAD_URL="https://github.com/godotengine/godot/releases/download"
# Where GitHub serves release assets after the redirect, with a signed query as in a real download.
readonly ASSET_URL="https://release-assets.githubusercontent.com/github-production-release-asset/1?sig=fixture"

# Every call is recorded first, by its last argument: the URL in each call install.sh makes.
printf '%s\n' "${@: -1}" >>"${FIXTURE_DIR}/requests"

https_flags=()
fail_on_error=false
head=false
location=false
output=""
write_out=""
url=""

# Prints why the call is not one install.sh makes and exits 2, curl's status for a usage error.
reject() {
  printf 'fixture curl: %s\n' "$*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --proto | --proto-redir)
      [[ "$2" == =https ]] || reject "$1 $2: every request and redirect must be restricted to HTTPS"
      https_flags+=("$1")
      shift 2
      ;;
    --retry) shift 2 ;;
    --silent | --show-error) shift ;;
    --fail)
      fail_on_error=true
      shift
      ;;
    --head)
      head=true
      shift
      ;;
    --location)
      location=true
      shift
      ;;
    --output)
      output="$2"
      shift 2
      ;;
    --write-out)
      write_out="$2"
      shift 2
      ;;
    -*) reject "unexpected option $1" ;;
    *)
      url="$1"
      shift
      ;;
  esac
done
[[ "${https_flags[*]-}" == "--proto --proto-redir" ]] || reject "--proto =https and --proto-redir =https are required"
[[ "${fail_on_error}" == true ]] || reject "--fail is required, so an HTTP error status fails the call"

mode="$(cat "${FIXTURE_DIR}/mode")"

# The latest-release link is read from its redirect header, never followed.
if [[ "${head}" == true ]]; then
  if [[ "${url}" != "${LATEST_URL}" || "${location}" == true || "${output}" != /dev/null \
    || "${write_out}" != '%{redirect_url}' ]]; then
    reject "unexpected header-only request for ${url}"
  fi
  latest="$(cat "${FIXTURE_DIR}/latest")"
  printf '%s/%s' "${TAG_URL}" "${latest}"
  exit 0
fi

if [[ "${url}" != "${DOWNLOAD_URL}"/*/* || "${location}" == false || -z "${output}" \
  || "${write_out}" != '%{url_effective}' ]]; then
  reject "unexpected request for ${url}"
fi
name="${url##*/}"
tag="${url#"${DOWNLOAD_URL}"/}"
tag="${tag%/*}"
file="${FIXTURE_DIR}/releases/${tag}/${name}"
if [[ "${mode}" == checksum_list_404 && "${name}" == SHA512-SUMS.txt ]]; then file=""; fi
if [[ "${mode}" == archive_404 && "${name}" == *.zip ]]; then file=""; fi
if [[ ! -f "${file}" ]]; then
  # What curl --fail prints and returns for an HTTP error status.
  echo 'curl: (22) The requested URL returned error: 404' >&2
  exit 22
fi
cp "${file}" "${output}"
printf '%s' "${ASSET_URL}"
