#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# Canon printer ink monitoring script (Nagios/Icinga plugin)
#
# - Performs web login (sendpw.cgi -> SBID -> index.html)
# - Retrieves ink data via prninfo_data.cgi
# - Evaluates ink status and levels
#
# Output:
#   - Normal operation: prints ONLY the plugin one-liner
#   - On UNKNOWN: prints debug "full trail" to stdout
#
# Exit codes:
#   0 = OK
#   1 = WARNING
#   2 = CRITICAL
#   3 = UNKNOWN
#
# NOTE (anonymized):
# - BASE default is a placeholder FQDN
# - NAMAE is never printed in debug (only a <redacted> marker)
# ============================================================================

# === Configuration (override via env) ===
BASE="${BASE:-https://printer.example.local}"
NAMAE="${NAMAE:-}" # Password hash captured from browser DevTools (DO NOT LOG)
IDTYPE="${IDTYPE:-2}"

# Threshold handling: Canon status codes drive severity
# 0=OK, 1=LOW (WARN), 2=EMPTY (CRIT), 3=UNKNOWN_INK (WARN)

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

# --- Debug buffer: printed ONLY on UNKNOWN ---
DEBUG_BUF=()
dbg() { DEBUG_BUF+=("$*"); }

# Print final output and exit
finish() {
  local code="$1"; shift
  printf '%s\n' "$*"

  # Only on UNKNOWN we print the entire debug trail
  if [[ "$code" -eq "$UNKNOWN" ]]; then
    printf '\n--- DEBUG TRAIL (UNKNOWN) ---\n'
    for line in "${DEBUG_BUF[@]}"; do
      printf '%s\n' "$line"
    done
  fi

  exit "$code"
}

# Ensure required command exists
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || finish "$UNKNOWN" "[UNKNOWN] missing command: $1"
}

# Convert Canon ink level index to percentage (UI mapping)
lvl_to_pct() {
  case "$1" in
    0)  echo "100" ;;
    1)  echo "90"  ;;
    2)  echo "80"  ;;
    3)  echo "70"  ;;
    4)  echo "60"  ;;
    5)  echo "50"  ;;
    6)  echo "40"  ;;
    7)  echo "30"  ;;
    8)  echo "20"  ;;
    9)  echo "10"  ;;
    10) echo "0"   ;;
    11) echo "?"   ;; # Lv00X in Canon UI
    *)  echo "?"   ;;
  esac
}

# Map ink type index (TS3100 series observed via inkCOL in model.js)
ink_type_name() {
  case "$1" in
    0) echo "Color" ;;
    1) echo "Black" ;;
    *) echo "Ink$1" ;;
  esac
}

# Map Canon ink status code to label
status_label() {
  case "$1" in
    0) echo "OK" ;;
    1) echo "LOW" ;;
    2) echo "EMPTY" ;;
    3) echo "UNKNOWN_INK" ;;
    *) echo "UNKNOWN_INK" ;;
  esac
}

# Map Canon ink status code to Nagios severity
status_severity() {
  case "$1" in
    0) echo "$OK" ;;
    1) echo "$WARNING" ;;
    2) echo "$CRITICAL" ;;
    3) echo "$WARNING" ;;
    *) echo "$WARNING" ;;
  esac
}

# Safe curl wrapper:
# - Never prints to stdout/stderr directly
# - Stores stdout to a file (temp) and headers to a file (temp)
# - On failure, returns non-zero but leaves artifacts for debug dump
curl_to_files() {
  local url="$1"
  local data="$2"
  local cookiejar="$3"
  local hdr_out="$4"
  local body_out="$5"

  # -k : ignore TLS errors (printer self-signed etc.)
  # -sS: silent but show errors (we capture them)
  # -L : follow redirects
  # -m : timeout to avoid hanging checks
  # Important: no piping from curl to head/grep to avoid curl(23) broken pipe.
  local err_file="${body_out}.curlerr"

  : >"$err_file"

  if ! curl -k -sS -L -m 10 \
      -c "$cookiejar" -b "$cookiejar" \
      -H 'Content-Type: application/x-www-form-urlencoded' \
      --data "$data" \
      -D "$hdr_out" \
      -o "$body_out" \
      "$url" 2>"$err_file"
  then
    local rc=$?
    dbg "[curl] URL: $url"
    dbg "[curl] DATA: $(sed -E 's/(NAMAE=)[^&]+/\1<redacted>/' <<<"$data")"
    dbg "[curl] exit code: $rc"
    dbg "[curl] stderr:"
    dbg "$(sed -n '1,200p' "$err_file" 2>/dev/null || true)"
    return "$rc"
  fi

  return 0
}

# --- Main ---
require_cmd curl
require_cmd grep
require_cmd sed
require_cmd head
require_cmd cut
require_cmd mktemp

if [[ -z "$NAMAE" ]]; then
  finish "$UNKNOWN" "[UNKNOWN] NAMAE not set (password hash required)"
fi

# Create per-run workspace (avoids collisions/permission issues)
WORKDIR="$(mktemp -d /var/tmp/canon-ink-check.XXXXXX 2>/dev/null || mktemp -d /tmp/canon-ink-check.XXXXXX)"
COOKIE_JAR="$WORKDIR/canon.cookies"
SENDPW_HEADERS="$WORKDIR/sendpw.headers"
SENDPW_BODY="$WORKDIR/sendpw.body"
INDEX_HEADERS="$WORKDIR/index.headers"
INDEX_BODY="$WORKDIR/index.body"
PRNINFO_HEADERS="$WORKDIR/prninfo.headers"
PRNINFO_XML="$WORKDIR/prninfo.xml"

cleanup() { rm -rf "$WORKDIR" 2>/dev/null || true; }
trap cleanup EXIT

dbg "[env] BASE=$BASE"
dbg "[env] IDTYPE=$IDTYPE"
dbg "[env] WORKDIR=$WORKDIR"
dbg "[env] NAMAE=<redacted>"

# 1) Login: POST sendpw.cgi (sets SCID cookie + returns HTML containing SBID)
dbg "[step1] POST /rui/sendpw.cgi"
if ! curl_to_files "${BASE}/rui/sendpw.cgi" "NAMAE=${NAMAE}&IDTYPE=${IDTYPE}" "$COOKIE_JAR" "$SENDPW_HEADERS" "$SENDPW_BODY"; then
  dbg "[step1] headers:"
  dbg "$(sed -n '1,200p' "$SENDPW_HEADERS" 2>/dev/null || true)"
  dbg "[step1] body:"
  dbg "$(sed -n '1,200p' "$SENDPW_BODY" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] login step sendpw.cgi failed"
fi

# Extract SCID from headers (optional, mostly for debug)
SCID="$(grep -aoE 'Set-Cookie:[[:space:]]*SCID=[0-9a-f]+' "$SENDPW_HEADERS" | head -1 | sed -E 's/.*SCID=//' || true)"
dbg "[step1] SCID(from header)=${SCID:-<not found>}"

# Extract SBID from body (HTML hidden input)
SBID="$(grep -aoE 'name="SBID"[[:space:]]+value="[0-9a-f]+"' "$SENDPW_BODY" \
  | head -1 \
  | sed -E 's/.*value="([0-9a-f]+)".*/\1/' || true)"

dbg "[step1] SBID(from body)=${SBID:-<not found>}"

if [[ -z "$SBID" ]]; then
  dbg "[step1] sendpw headers dump:"
  dbg "$(sed -n '1,200p' "$SENDPW_HEADERS" 2>/dev/null || true)"
  dbg "[step1] sendpw body dump:"
  dbg "$(sed -n '1,250p' "$SENDPW_BODY" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] login failed: SBID not found"
fi

# 2) Finalize session: POST index.html with SBID
dbg "[step2] POST /rui/index.html (finalize session)"
if ! curl_to_files "${BASE}/rui/index.html" "SBID=${SBID}" "$COOKIE_JAR" "$INDEX_HEADERS" "$INDEX_BODY"; then
  dbg "[step2] headers:"
  dbg "$(sed -n '1,200p' "$INDEX_HEADERS" 2>/dev/null || true)"
  dbg "[step2] body:"
  dbg "$(sed -n '1,200p' "$INDEX_BODY" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] session finalization failed"
fi

# 3) Retrieve printer data: POST prninfo_data.cgi with GETINFO=0 and SBID
dbg "[step3] POST /rui/prninfo_data.cgi (GETINFO=0)"
if ! curl_to_files "${BASE}/rui/prninfo_data.cgi" "GETINFO=0&SBID=${SBID}" "$COOKIE_JAR" "$PRNINFO_HEADERS" "$PRNINFO_XML"; then
  dbg "[step3] headers:"
  dbg "$(sed -n '1,200p' "$PRNINFO_HEADERS" 2>/dev/null || true)"
  dbg "[step3] body(xml):"
  dbg "$(sed -n '1,250p' "$PRNINFO_XML" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] prninfo_data.cgi request failed"
fi

# Check session validity in XML
if grep -q '<SES_ERR_URL>' "$PRNINFO_XML"; then
  dbg "[step3] SES_ERR_URL present, session invalid"
  dbg "[step3] xml:"
  dbg "$(sed -n '1,250p' "$PRNINFO_XML" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] invalid session returned by printer"
fi

# Parse INKREST entries, example: <INKREST0>0,6,0</INKREST0>
mapfile -t INKS < <(
  grep -aoE '<INKREST[0-9]+>[^<]+' "$PRNINFO_XML" |
  sed -E 's/<(INKREST[0-9]+)>(.*)/\1=\2/'
)

if [[ ${#INKS[@]} -eq 0 ]]; then
  dbg "[parse] no INKREST entries found"
  dbg "[parse] xml:"
  dbg "$(sed -n '1,350p' "$PRNINFO_XML" 2>/dev/null || true)"
  finish "$UNKNOWN" "[UNKNOWN] no ink data found"
fi

# Evaluate ink states
worst="$OK"
details=()

for kv in "${INKS[@]}"; do
  val="${kv#*=}"          # "a,b,c"
  IFS=',' read -r t lvl st <<<"$val"

  pct="$(lvl_to_pct "$lvl")"
  name="$(ink_type_name "$t")"
  label="$(status_label "$st")"
  severity="$(status_severity "$st")"

  [[ "$severity" -gt "$worst" ]] && worst="$severity"
  details+=( "${name}:${pct}%(${label})" )
done

# Output only the plugin line (unless UNKNOWN, handled by finish())
case "$worst" in
  0) finish "$OK"       "[OK] ${details[*]}" ;;
  1) finish "$WARNING"  "[WARNING] ${details[*]}" ;;
  2) finish "$CRITICAL" "[CRITICAL] ${details[*]}" ;;
  *) finish "$UNKNOWN"  "[UNKNOWN] ${details[*]}" ;;
esac
