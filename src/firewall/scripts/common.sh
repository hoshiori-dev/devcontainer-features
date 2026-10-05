# shellcheck shell=sh
# Option rules of the firewall feature, shared by install.sh (image build) and apply.sh (every container start), so
# that the build and each start validate with one copy. Sourced, never run. It defines functions and constants only,
# and reads the option variables of the script that sources it: DEFAULTACTION, PRESETS, ALLOWEDDOMAINS, ALLOWEDCIDRS,
# DENIEDDOMAINS, DENIEDCIDRS, FAILUREMODE, and FILTERFORWARD. It calls neither log nor fail: a function that rejects
# a value says why in one line, and the sourcing script fails the build or records the start with that reason.
# validate_options and read_options put the line in the global reason; every other function prints it and returns 1.
# POSIX sh, because Alpine images ship no bash. Needs awk, jq, sort, and tr.

# The address the start check probes (TEST-NET-1, RFC 5737). The rules always refuse it, so no allowed entry and no
# fetched range may contain it.
readonly PROBE_ADDRESS="192.0.2.1"
# The names of the options, as the options file stores them.
readonly OPTION_NAMES="defaultAction presets allowedDomains allowedCidrs deniedDomains deniedCidrs failureMode \
filterForward"
readonly NL='
'

# Prints the entries of the comma-separated list $2, one per line: split at commas only, whitespace around an entry
# (line breaks included) removed, empty entries skipped. An entry that holds a line break is none: prints why, naming
# the list as $1 ("option presets"), and returns 1.
list_entries() {
  list_entries_name="$1"
  # Each comma-separated entry becomes one positional parameter, so an entry that holds a line break stays one entry.
  # IFS and globbing are restored before any entry is used.
  list_entries_ifs="${IFS}"
  set -f
  IFS=,
  # The list is split into its entries on purpose.
  # shellcheck disable=SC2086
  set -- $2
  IFS="${list_entries_ifs}"
  set +f
  for list_entries_entry in "$@"; do
    # Removes the longest run of whitespace at the start of the entry, then the one at its end.
    list_entries_entry="${list_entries_entry#"${list_entries_entry%%[![:space:]]*}"}"
    list_entries_entry="${list_entries_entry%"${list_entries_entry##*[![:space:]]}"}"
    case "${list_entries_entry}" in
      "") ;;
      *"${NL}"*)
        list_entries_start="${list_entries_entry%%"${NL}"*}"
        list_entries_fault="has a line break inside the entry that starts with \"${list_entries_start}\""
        printf '%s\n' "${list_entries_name} ${list_entries_fault}; separate entries with commas"
        return 1
        ;;
      *) printf '%s\n' "${list_entries_entry}" ;;
    esac
  done
}

# Prints the non-empty lines of $1 on one line, joined by $2.
join_lines() {
  join_lines_joined=""
  while IFS= read -r join_lines_line; do
    if [ -z "${join_lines_line}" ]; then continue; fi
    join_lines_joined="${join_lines_joined:+${join_lines_joined}$2}${join_lines_line}"
  done <<EOF
$1
EOF
  printf '%s\n' "${join_lines_joined}"
}

# Prints the domains of the presets named in $1, one name per line, as Requirement: Presets of the feature's spec
# lists them. For a name that is no preset, prints why and returns 1.
preset_domains() {
  preset_domains_found=""
  while IFS= read -r preset_domains_name; do
    case "${preset_domains_name}" in
      "") continue ;;
      github) preset_domains_domains="github.com githubusercontent.com" ;;
      npm) preset_domains_domains="registry.npmjs.org" ;;
      pypi) preset_domains_domains="pypi.org files.pythonhosted.org" ;;
      anthropic) preset_domains_domains="api.anthropic.com claude.ai platform.claude.com" ;;
      vscode)
        preset_domains_domains="update.code.visualstudio.com vscode.download.prss.microsoft.com vscode-cdn.net"
        preset_domains_domains="${preset_domains_domains} marketplace.visualstudio.com gallery.vsassets.io"
        preset_domains_domains="${preset_domains_domains} gallerycdn.vsassets.io"
        ;;
      *)
        preset_domains_fault="option presets entry \"${preset_domains_name}\" is not a known preset"
        printf '%s\n' "${preset_domains_fault}; use github, npm, pypi, anthropic, or vscode"
        return 1
        ;;
    esac
    for preset_domains_domain in ${preset_domains_domains}; do
      preset_domains_found="${preset_domains_found}${preset_domains_domain}${NL}"
    done
  done <<EOF
$1
EOF
  printf '%s' "${preset_domains_found}"
}

# Prints the DNS names $2, one per line, in lower case and without duplicates. $1 is the option they come from,
# allowedDomains or deniedDomains. A name has at most 253 characters in labels of 1 to 63 letters, digits, and inner
# hyphens, and its last label is not a number. For any other entry, prints why and returns 1.
domain_names() {
  domain_names_valid=""
  while IFS= read -r domain_names_entry; do
    if [ -z "${domain_names_entry}" ]; then continue; fi
    domain_names_fault=""
    if [ "${#domain_names_entry}" -gt 253 ]; then domain_names_fault="is not a DNS name"; fi
    domain_names_rest="${domain_names_entry}."
    while [ -n "${domain_names_rest}" ]; do
      domain_names_label="${domain_names_rest%%.*}"
      domain_names_rest="${domain_names_rest#*.}"
      case "${domain_names_label}" in
        "" | -* | *- | *[!A-Za-z0-9-]*) domain_names_fault="is not a DNS name" ;;
      esac
      if [ "${#domain_names_label}" -gt 63 ]; then domain_names_fault="is not a DNS name"; fi
    done
    domain_names_fix="write dot-separated labels of letters, digits, and inner hyphens, such as example.com"
    case "${domain_names_label}" in
      "" | *[!0-9]*) ;;
      *)
        domain_names_fault="is an address or ends in a number, so it is not a DNS name"
        domain_names_fix="list addresses in ${1%Domains}Cidrs"
        ;;
    esac
    case "${domain_names_entry}" in
      *"*"*)
        domain_names_fault="has a wildcard, so it is not a DNS name"
        domain_names_fix="write the name without it, since an entry includes every subdomain"
        ;;
    esac
    if [ -n "${domain_names_fault}" ]; then
      printf '%s\n' "option $1 entry \"${domain_names_entry}\" ${domain_names_fault}; ${domain_names_fix}"
      return 1
    fi
    domain_names_valid="${domain_names_valid}${domain_names_entry}${NL}"
  done <<EOF
$2
EOF
  if [ -z "${domain_names_valid}" ]; then return 0; fi
  domain_names_valid="$(
    tr '[:upper:]' '[:lower:]' <<EOF
${domain_names_valid}
EOF
  )"
  sort -u <<EOF
${domain_names_valid}
EOF
}

# Prints the IPv4 or IPv6 addresses or CIDRs $3, one per line, as "<family> <prefix length> <canonical CIDR>" lines
# without duplicates; the canonical CIDR is printed again from the numbers parsed, never copied from the entry. $2
# names an entry in a message. $1 is the kind of entry: every kind rejects bits set outside the prefix length;
# "allowed" (allowedCidrs) and "fetched" (a range of GitHub's meta response) reject a range that contains
# PROBE_ADDRESS; "fetched" rejects a prefix shorter than /8 for IPv4 and /16 for IPv6; "denied" (deniedCidrs) adds
# nothing; "address" (a nameserver, a looked-up address) rejects a prefix. For the first entry it rejects, prints why
# and returns 1; the message of an "allowed" or "denied" entry also says how to fix it.
cidr_lines() {
  if ! cidr_lines_found="$(
    awk -v kind="$1" -v label="$2" -v probe="${PROBE_ADDRESS}" '
      function bad(why, fix) {
        if (kind == "allowed" || kind == "denied") why = why "; " fix
        printf "%s \"%s\" %s\n", label, $0, why
        failed = 1
        exit 1
      }
      function dec(s, max) {
        if (s !~ /^(0|[1-9][0-9]*)$/ || length(s) > 3 || s + 0 > max) return -1
        return s + 0
      }
      function hex(s,   i, v) {
        v = 0
        s = tolower(s)
        for (i = 1; i <= length(s); i++) v = v * 16 + index("0123456789abcdef", substr(s, i, 1)) - 1
        return v
      }
      function h16(s) { return s ~ /^[0-9A-Fa-f]+$/ && length(s) <= 4 }
      # Arrays are global (octets, v4part, heads, tails): not every awk passes local arrays on.
      function v4(s, o,   n, i) {
        n = split(s, octets, "[.]")
        if (n != 4) return 0
        for (i = 1; i <= 4; i++) { o[i] = dec(octets[i], 255); if (o[i] < 0) return 0 }
        return 1
      }
      function v6(s, g,   dbl, head, tail, nh, nt, i, n) {
        if (s !~ /^[0-9A-Fa-f:.]+$/) return 0
        if (index(s, ".")) {
          if (!match(s, /:[^:]*$/) || !v4(substr(s, RSTART + 1), v4part)) return 0
          s = substr(s, 1, RSTART) sprintf("%x:%x", v4part[1] * 256 + v4part[2], v4part[3] * 256 + v4part[4])
        }
        dbl = index(s, "::")
        if (dbl) {
          head = substr(s, 1, dbl - 1)
          tail = substr(s, dbl + 2)
          if (index(tail, "::")) return 0
        } else {
          head = s
          tail = ""
        }
        nh = (head == "") ? 0 : split(head, heads, ":")
        nt = (tail == "") ? 0 : split(tail, tails, ":")
        if ((dbl && nh + nt > 7) || (!dbl && nh != 8)) return 0
        n = 0
        for (i = 1; i <= nh; i++) { if (!h16(heads[i])) return 0; g[++n] = hex(heads[i]) }
        if (dbl) while (n < 8 - nt) g[++n] = 0
        for (i = 1; i <= nt; i++) { if (!h16(tails[i])) return 0; g[++n] = hex(tails[i]) }
        return 1
      }
      BEGIN {
        v4(probe, p)
        probe_number = ((p[1] * 256 + p[2]) * 256 + p[3]) * 256 + p[4]
        form = (kind == "address") ? "address" : "address or CIDR"
        form_fix = "write an address such as 10.0.0.5 or a range such as 172.18.0.0/16"
        bits_fix = "write the first address of the range, or a longer prefix"
        probe_fix = "list narrower ranges, or set defaultAction to allow to let unlisted traffic through"
      }
      $0 == "" { next }
      {
        slash = index($0, "/")
        if (slash) { a = substr($0, 1, slash - 1); pl = substr($0, slash + 1) } else { a = $0; pl = "" }
        if (index(a, ":")) { fam = 6; max = 128; ok = v6(a, g) } else { fam = 4; max = 32; ok = v4(a, g) }
        if (!ok || (slash && kind == "address")) bad("is not an IPv4 or IPv6 " form, form_fix)
        if (!slash) len = max
        else if ((len = dec(pl, max)) < 0) bad("is not an IPv4 or IPv6 " form, form_fix)
        if (fam == 4) {
          v = ((g[1] * 256 + g[2]) * 256 + g[3]) * 256 + g[4]
          size = 2 ^ (32 - len)
          if (v % size != 0) bad("has bits set outside its prefix length", bits_fix)
          if ((kind == "allowed" || kind == "fetched") && int(v / size) == int(probe_number / size))
            bad("contains " probe ", the address the start check probes", probe_fix)
          if (kind == "fetched" && len < 8) bad("is shorter than the minimum prefix /8", "")
          line = sprintf("4 %d %d.%d.%d.%d/%d", len, g[1], g[2], g[3], g[4], len)
        } else {
          for (i = 1; i <= 8; i++) {
            keep = len - 16 * (i - 1)
            if (keep >= 16) continue
            if ((keep <= 0 && g[i] != 0) || (keep > 0 && g[i] % (2 ^ (16 - keep)) != 0))
              bad("has bits set outside its prefix length", bits_fix)
          }
          if (kind == "fetched" && len < 16) bad("is shorter than the minimum prefix /16", "")
          line = sprintf("6 %d %x:%x:%x:%x:%x:%x:%x:%x/%d", len, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], len)
        }
        lines = lines line "\n"
      }
      END {
        if (!failed) printf "%s", lines
        exit failed
      }' <<EOF
$3
EOF
  )"; then
    printf '%s\n' "${cidr_lines_found}"
    return 1
  fi
  if [ -z "${cidr_lines_found}" ]; then return 0; fi
  sort -u <<EOF
${cidr_lines_found}
EOF
}

# Prints the ranges of the web, api, and git lists of the GitHub meta response in the file $1
# (https://api.github.com/meta), each validated as cidr_lines validates a "fetched" entry. For a malformed response or
# the first range it rejects, prints why and returns 1.
meta_ranges() {
  if ! meta_ranges_list="$(
    jq --raw-output '
      if type != "object" then error("the response is not a JSON object")
      elif (.web | type) != "array" or (.api | type) != "array" or (.git | type) != "array"
      then error("the response lacks a web, api, or git list")
      else
        (.web + .api + .git) | map(if type == "string" then . else error("a range is not a string") end) | join(",")
      end' "$1" 2>&1
  )"; then
    printf '%s\n' "malformed GitHub meta response: ${meta_ranges_list##*"${NL}"}"
    return 1
  fi
  # The same split as an option's list, so each range is matched as a whole.
  if ! meta_ranges_entries="$(list_entries "the GitHub meta response" "${meta_ranges_list}")"; then
    printf '%s\n' "malformed GitHub meta response: a range holds a line break"
    return 1
  fi
  cidr_lines fetched "GitHub meta range" "${meta_ranges_entries}"
}

# Validates the eight option variables as the Option requirements of the feature's spec state them. Sets preset_list
# (the selected presets) and preset_domain_list (their domains), allowed_domain_list and denied_domain_list (DNS
# names), one entry per line, and allowed_cidr_lines and denied_cidr_lines (cidr_lines lines). Returns 1 at the first
# value it rejects, with the reason in reason.
validate_options() {
  reason=""
  case "${DEFAULTACTION}" in
    deny | allow) ;;
    *)
      reason="option defaultAction is \"${DEFAULTACTION}\"; use \"deny\" or \"allow\""
      return 1
      ;;
  esac
  case "${FAILUREMODE}" in
    closed | warn) ;;
    *)
      reason="option failureMode is \"${FAILUREMODE}\"; use \"closed\" or \"warn\""
      return 1
      ;;
  esac
  case "${FILTERFORWARD}" in
    true | false) ;;
    *)
      reason="option filterForward is \"${FILTERFORWARD}\"; use true or false"
      return 1
      ;;
  esac
  # Each list is split into its entries, then its entries are validated. The script that sources this file reads the
  # six results; this file only assigns them.
  # shellcheck disable=SC2034
  if ! preset_list="$(list_entries "option presets" "${PRESETS}")"; then
    reason="${preset_list}"
  elif ! preset_domain_list="$(preset_domains "${preset_list}")"; then
    reason="${preset_domain_list}"
  elif ! allowed_domain_list="$(list_entries "option allowedDomains" "${ALLOWEDDOMAINS}")"; then
    reason="${allowed_domain_list}"
  elif ! allowed_domain_list="$(domain_names allowedDomains "${allowed_domain_list}")"; then
    reason="${allowed_domain_list}"
  elif ! allowed_cidr_lines="$(list_entries "option allowedCidrs" "${ALLOWEDCIDRS}")"; then
    reason="${allowed_cidr_lines}"
  elif ! allowed_cidr_lines="$(cidr_lines allowed "option allowedCidrs entry" "${allowed_cidr_lines}")"; then
    reason="${allowed_cidr_lines}"
  elif ! denied_domain_list="$(list_entries "option deniedDomains" "${DENIEDDOMAINS}")"; then
    reason="${denied_domain_list}"
  elif ! denied_domain_list="$(domain_names deniedDomains "${denied_domain_list}")"; then
    reason="${denied_domain_list}"
  elif ! denied_cidr_lines="$(list_entries "option deniedCidrs" "${DENIEDCIDRS}")"; then
    reason="${denied_cidr_lines}"
  elif ! denied_cidr_lines="$(cidr_lines denied "option deniedCidrs entry" "${denied_cidr_lines}")"; then
    reason="${denied_cidr_lines}"
  fi
  [ -z "${reason}" ]
}

# Writes the option variables to the file $1, one "name=value" line each, every list as its entries joined by commas.
# Call it after validate_options has accepted them.
write_options() {
  write_options_presets="$(list_entries "option presets" "${PRESETS}")"
  write_options_presets="$(join_lines "${write_options_presets}" ",")"
  write_options_allowed_domains="$(list_entries "option allowedDomains" "${ALLOWEDDOMAINS}")"
  write_options_allowed_domains="$(join_lines "${write_options_allowed_domains}" ",")"
  write_options_allowed_cidrs="$(list_entries "option allowedCidrs" "${ALLOWEDCIDRS}")"
  write_options_allowed_cidrs="$(join_lines "${write_options_allowed_cidrs}" ",")"
  write_options_denied_domains="$(list_entries "option deniedDomains" "${DENIEDDOMAINS}")"
  write_options_denied_domains="$(join_lines "${write_options_denied_domains}" ",")"
  write_options_denied_cidrs="$(list_entries "option deniedCidrs" "${DENIEDCIDRS}")"
  write_options_denied_cidrs="$(join_lines "${write_options_denied_cidrs}" ",")"
  {
    printf 'defaultAction=%s\n' "${DEFAULTACTION}"
    printf 'presets=%s\n' "${write_options_presets}"
    printf 'allowedDomains=%s\n' "${write_options_allowed_domains}"
    printf 'allowedCidrs=%s\n' "${write_options_allowed_cidrs}"
    printf 'deniedDomains=%s\n' "${write_options_denied_domains}"
    printf 'deniedCidrs=%s\n' "${write_options_denied_cidrs}"
    printf 'failureMode=%s\n' "${FAILUREMODE}"
    printf 'filterForward=%s\n' "${FILTERFORWARD}"
  } >"$1"
}

# Sets the option variables from the file $1, which write_options wrote. Returns 1 with the reason in reason when
# the file is missing or lacks an option.
read_options() {
  reason=""
  if [ ! -r "$1" ]; then
    reason="$1 is missing; rebuild the container image"
    return 1
  fi
  read_options_seen=""
  while IFS= read -r read_options_line; do
    read_options_value="${read_options_line#*=}"
    case "${read_options_line}" in
      defaultAction=*) DEFAULTACTION="${read_options_value}" ;;
      presets=*) PRESETS="${read_options_value}" ;;
      allowedDomains=*) ALLOWEDDOMAINS="${read_options_value}" ;;
      allowedCidrs=*) ALLOWEDCIDRS="${read_options_value}" ;;
      deniedDomains=*) DENIEDDOMAINS="${read_options_value}" ;;
      deniedCidrs=*) DENIEDCIDRS="${read_options_value}" ;;
      failureMode=*) FAILUREMODE="${read_options_value}" ;;
      filterForward=*) FILTERFORWARD="${read_options_value}" ;;
      *) continue ;;
    esac
    read_options_seen="${read_options_seen} ${read_options_line%%=*}"
  done <"$1"
  for read_options_name in ${OPTION_NAMES}; do
    case " ${read_options_seen} " in
      *" ${read_options_name} "*) ;;
      *)
        reason="$1 lacks the option ${read_options_name}; rebuild the container image"
        return 1
        ;;
    esac
  done
}
