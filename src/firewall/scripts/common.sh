# shellcheck shell=sh disable=SC2034 # the variables set here are read by the scripts that source it
# Option handling shared by install.sh (build time) and apply.sh (every start) of the firewall feature,
# so both validate with the same rules. POSIX sh; needs awk, jq, sed, sort, tail, and tr. A checker
# prints its normalized entries on standard output; on the first invalid entry it prints one line
# naming that entry and returns non-zero.

# The options as install.sh stores them; apply.sh reads them back with fw_read_options.
FW_OPTION_KEYS="defaultAction presets allowedDomains allowedCidrs deniedDomains deniedCidrs failureMode filterForward"

# fw_list VALUE: the comma-separated entries of VALUE, one per line, trimmed, without empty entries.
fw_list() {
  printf '%s\n' "$1" | tr ',' '\n' | awk '{ gsub(/^[ \t\r]+|[ \t\r]+$/, ""); if ($0 != "") print }'
}

# fw_join: the lines of standard input joined with commas.
fw_join() {
  awk 'BEGIN { ORS = "" } { if (NR > 1) print ","; print } END { print "\n" }'
}

# fw_preset_domains NAME: the domains of a preset (Requirement: Presets); non-zero for an unknown name.
fw_preset_domains() {
  case $1 in
    github) printf '%s\n' github.com githubusercontent.com ;;
    npm) printf '%s\n' registry.npmjs.org ;;
    pypi) printf '%s\n' pypi.org files.pythonhosted.org ;;
    anthropic) printf '%s\n' api.anthropic.com claude.ai platform.claude.com ;;
    vscode)
      printf '%s\n' update.code.visualstudio.com vscode.download.prss.microsoft.com vscode-cdn.net \
        marketplace.visualstudio.com gallery.vsassets.io gallerycdn.vsassets.io
      ;;
    *) return 1 ;;
  esac
}

# fw_check_presets: preset names on standard input.
fw_check_presets() {
  while IFS= read -r fw_preset; do
    if ! fw_preset_domains "$fw_preset" >/dev/null; then
      printf 'presets: "%s" is not a known preset (known: github, npm, pypi, anthropic, vscode)\n' "$fw_preset"
      return 1
    fi
    printf '%s\n' "$fw_preset"
  done
}

# fw_check_domains LABEL: DNS names on standard input, printed in lower case. Wildcard labels are
# rejected: every entry already includes its subdomains.
fw_check_domains() {
  awk -v label="$1" '
    function bad(why) { printf "%s: \"%s\" %s\n", label, $0, why; exit 1 }
    {
      d = tolower($0)
      if (length(d) > 253) bad("is not a valid DNS name (longer than 253 characters)")
      n = split(d, l, "[.]")
      for (i = 1; i <= n; i++)
        if (length(l[i]) > 63 || l[i] !~ /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/)
          bad(index(d, "*") ? "is not a valid DNS name (write it without a wildcard: subdomains are always included)" \
            : "is not a valid DNS name")
      if (l[n] ~ /^[0-9]+$/) bad("is not a valid DNS name (addresses belong in the CIDR options)")
      print d
    }'
}

# fw_check_cidrs KIND LABEL: IPv4 or IPv6 addresses or CIDRs on standard input, printed as
# "<family> <prefix length> <canonical CIDR>". Every KIND (allowed, denied, fetched, or address)
# rejects bits set outside the prefix length; "allowed" and "fetched" also reject a range containing
# 192.0.2.1, the address the start check probes, and "fetched" (GitHub meta ranges) rejects prefixes
# shorter than /8 for IPv4 and /16 for IPv6.
fw_check_cidrs() {
  awk -v kind="$1" -v label="$2" '
    function bad(why) { printf "%s: \"%s\" %s\n", label, $0, why; exit 1 }
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
    {
      slash = index($0, "/")
      if (slash) { a = substr($0, 1, slash - 1); p = substr($0, slash + 1) } else { a = $0; p = "" }
      if (index(a, ":")) { fam = 6; max = 128; ok = v6(a, g) } else { fam = 4; max = 32; ok = v4(a, g) }
      if (!ok) bad("is not a valid IPv4 or IPv6 address or CIDR")
      if (p == "") len = max
      else if ((len = dec(p, max)) < 0) bad("is not a valid IPv4 or IPv6 address or CIDR (prefix length)")
      if (fam == 4) {
        v = ((g[1] * 256 + g[2]) * 256 + g[3]) * 256 + g[4]
        size = 2 ^ (32 - len)
        if (v % size != 0) bad("has bits set outside its prefix length")
        if ((kind == "allowed" || kind == "fetched") && int(v / size) == int(3221225985 / size))
          bad("contains 192.0.2.1, the address the start check probes")
        if (kind == "fetched" && len < 8) bad("is shorter than the minimum prefix /8")
        printf "4 %d %d.%d.%d.%d/%d\n", len, g[1], g[2], g[3], g[4], len
      } else {
        for (i = 1; i <= 8; i++) {
          keep = len - 16 * (i - 1)
          if (keep >= 16) continue
          if ((keep <= 0 && g[i] != 0) || (keep > 0 && g[i] % (2 ^ (16 - keep)) != 0))
            bad("has bits set outside its prefix length")
        }
        if (kind == "fetched" && len < 16) bad("is shorter than the minimum prefix /16")
        printf "6 %d %x:%x:%x:%x:%x:%x:%x:%x/%d\n", len, g[1], g[2], g[3], g[4], g[5], g[6], g[7], g[8], len
      }
    }'
}

# fw_meta_ranges FILE: the validated ranges of the web, api, and git lists of a GitHub meta response
# (https://api.github.com/meta), as fw_check_cidrs prints them, without duplicates. A malformed
# response or any invalid range prints one line naming the problem and returns non-zero.
fw_meta_ranges() {
  if ! fw_ranges=$(jq -r '
      if type != "object" then error("the response is not a JSON object")
      elif (.web | type) != "array" or (.api | type) != "array" or (.git | type) != "array"
      then error("the response lacks a web, api, or git list")
      else (.web + .api + .git)[] | if type == "string" then . else error("a range is not a string") end
      end' "$1" 2>&1); then
    printf 'malformed GitHub meta response: %s\n' "$(printf '%s\n' "$fw_ranges" | tail -n 1)"
    return 1
  fi
  [ -n "$fw_ranges" ] || return 0
  if ! fw_ranges=$(printf '%s\n' "$fw_ranges" | fw_check_cidrs fetched "GitHub meta range"); then
    printf '%s\n' "$fw_ranges" | tail -n 1
    return 1
  fi
  printf '%s\n' "$fw_ranges" | sort -u
}

# fw_checked VAR VALUE CHECKER [ARGS]: runs CHECKER on the entries of VALUE and stores its sorted,
# unique output in VAR; on failure stores its message in FW_ERROR and returns non-zero.
fw_checked() {
  fw_var=$1
  fw_value=$2
  shift 2
  if ! fw_out=$(fw_list "$fw_value" | "$@"); then
    FW_ERROR=$(printf '%s\n' "$fw_out" | tail -n 1)
    return 1
  fi
  fw_out=$(printf '%s\n' "$fw_out" | sed '/^$/d' | sort -u)
  eval "$fw_var=\$fw_out"
}

# fw_validate_options: validates OPT_DEFAULT_ACTION, OPT_PRESETS, OPT_ALLOWED_DOMAINS,
# OPT_ALLOWED_CIDRS, OPT_DENIED_DOMAINS, OPT_DENIED_CIDRS, OPT_FAILURE_MODE, and OPT_FILTER_FORWARD.
# Sets FW_PRESETS, FW_ALLOWED_DOMAINS, FW_DENIED_DOMAINS (one entry per line) and FW_ALLOWED_CIDRS,
# FW_DENIED_CIDRS (fw_check_cidrs lines); on the first invalid value sets FW_ERROR and returns non-zero.
fw_validate_options() {
  FW_ERROR=
  case $OPT_DEFAULT_ACTION in
    deny | allow) ;;
    *) FW_ERROR="defaultAction: \"$OPT_DEFAULT_ACTION\" is neither deny nor allow" && return 1 ;;
  esac
  case $OPT_FAILURE_MODE in
    closed | warn) ;;
    *) FW_ERROR="failureMode: \"$OPT_FAILURE_MODE\" is neither closed nor warn" && return 1 ;;
  esac
  case $OPT_FILTER_FORWARD in
    true | false) ;;
    *) FW_ERROR="filterForward: \"$OPT_FILTER_FORWARD\" is neither true nor false" && return 1 ;;
  esac
  fw_checked FW_PRESETS "$OPT_PRESETS" fw_check_presets \
    && fw_checked FW_ALLOWED_DOMAINS "$OPT_ALLOWED_DOMAINS" fw_check_domains allowedDomains \
    && fw_checked FW_ALLOWED_CIDRS "$OPT_ALLOWED_CIDRS" fw_check_cidrs allowed allowedCidrs \
    && fw_checked FW_DENIED_DOMAINS "$OPT_DENIED_DOMAINS" fw_check_domains deniedDomains \
    && fw_checked FW_DENIED_CIDRS "$OPT_DENIED_CIDRS" fw_check_cidrs denied deniedCidrs
}

# fw_write_options FILE: stores the OPT_* values, each list trimmed, atomically and readable by all.
fw_write_options() {
  {
    printf 'defaultAction=%s\n' "$OPT_DEFAULT_ACTION"
    printf 'presets=%s\n' "$(fw_list "$OPT_PRESETS" | fw_join)"
    printf 'allowedDomains=%s\n' "$(fw_list "$OPT_ALLOWED_DOMAINS" | fw_join)"
    printf 'allowedCidrs=%s\n' "$(fw_list "$OPT_ALLOWED_CIDRS" | fw_join)"
    printf 'deniedDomains=%s\n' "$(fw_list "$OPT_DENIED_DOMAINS" | fw_join)"
    printf 'deniedCidrs=%s\n' "$(fw_list "$OPT_DENIED_CIDRS" | fw_join)"
    printf 'failureMode=%s\n' "$OPT_FAILURE_MODE"
    printf 'filterForward=%s\n' "$OPT_FILTER_FORWARD"
  } >"$1.tmp"
  chmod 0644 "$1.tmp"
  mv -f "$1.tmp" "$1"
}

# fw_read_options FILE: sets the OPT_* values from a file fw_write_options wrote; non-zero with
# FW_ERROR set when the file is missing or lacks an option.
fw_read_options() {
  OPT_DEFAULT_ACTION='' OPT_PRESETS='' OPT_ALLOWED_DOMAINS='' OPT_ALLOWED_CIDRS=''
  OPT_DENIED_DOMAINS='' OPT_DENIED_CIDRS='' OPT_FAILURE_MODE='' OPT_FILTER_FORWARD=''
  if [ ! -r "$1" ]; then
    FW_ERROR="$1 is missing"
    return 1
  fi
  fw_seen=
  while IFS= read -r fw_line || [ -n "$fw_line" ]; do
    fw_value=${fw_line#*=}
    case $fw_line in
      defaultAction=*) OPT_DEFAULT_ACTION=$fw_value ;;
      presets=*) OPT_PRESETS=$fw_value ;;
      allowedDomains=*) OPT_ALLOWED_DOMAINS=$fw_value ;;
      allowedCidrs=*) OPT_ALLOWED_CIDRS=$fw_value ;;
      deniedDomains=*) OPT_DENIED_DOMAINS=$fw_value ;;
      deniedCidrs=*) OPT_DENIED_CIDRS=$fw_value ;;
      failureMode=*) OPT_FAILURE_MODE=$fw_value ;;
      filterForward=*) OPT_FILTER_FORWARD=$fw_value ;;
      *) continue ;;
    esac
    fw_seen="$fw_seen ${fw_line%%=*}"
  done <"$1"
  for fw_key in $FW_OPTION_KEYS; do
    case " $fw_seen " in
      *" $fw_key "*) ;;
      *) FW_ERROR="$1 lacks the option $fw_key" && return 1 ;;
    esac
  done
}
