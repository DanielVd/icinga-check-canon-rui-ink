#!/usr/bin/env bash
# Canon Remote UI ink/toner check for Icinga and Nagios.
set -euo pipefail
umask 077

OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

finish() {
  local state="$1"
  shift
  printf '%s\n' "$*"
  exit "$state"
}

for cmd in curl grep sed head mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || finish "$UNKNOWN" "[UNKNOWN] missing command: $cmd"
done

BASE="${BASE:-}"
NAMAE="${NAMAE:-}"
IDTYPE="${IDTYPE:-2}"
LOGIN_RETRIES="${LOGIN_RETRIES:-3}"
WAKEUP_DELAY_SECONDS="${WAKEUP_DELAY_SECONDS:-3}"
CANON_INSECURE_TLS="${CANON_INSECURE_TLS:-0}"

[[ "$BASE" =~ ^https?://[^@[:space:]]+$ ]] ||
  finish "$UNKNOWN" "[UNKNOWN] set BASE to the Canon Remote UI http(s) URL (without credentials)"
[[ -n "$NAMAE" ]] || finish "$UNKNOWN" "[UNKNOWN] NAMAE not set"
[[ "$IDTYPE" =~ ^[0-9]+$ ]] || finish "$UNKNOWN" "[UNKNOWN] invalid IDTYPE"
[[ "$LOGIN_RETRIES" =~ ^[1-9][0-9]?$ ]] ||
  finish "$UNKNOWN" "[UNKNOWN] LOGIN_RETRIES must be between 1 and 99"
[[ "$WAKEUP_DELAY_SECONDS" =~ ^[0-9]+$ ]] ||
  finish "$UNKNOWN" "[UNKNOWN] invalid WAKEUP_DELAY_SECONDS"
[[ "$CANON_INSECURE_TLS" == 0 || "$CANON_INSECURE_TLS" == 1 ]] ||
  finish "$UNKNOWN" "[UNKNOWN] CANON_INSECURE_TLS must be 0 or 1"

BASE="${BASE%/}"
CURL_OPTS=(--fail --silent --show-error --connect-timeout 5 --max-time 10)
if [[ "$CANON_INSECURE_TLS" == 1 ]]; then
  CURL_OPTS+=(--insecure)
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/canon-rui-ink.XXXXXXXX")" ||
  finish "$UNKNOWN" "[UNKNOWN] cannot create temporary directory"
trap 'rm -rf -- "$WORKDIR"' EXIT

COOKIE_JAR="$WORKDIR/cookies"
: > "$COOKIE_JAR"
printf '%s' "$NAMAE" > "$WORKDIR/namae"

# Never put NAMAE or SBID on the curl command line or in diagnostic output.
request() {
  local path="$1" headers="$2" body="$3"
  shift 3
  if curl "${CURL_OPTS[@]}" -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -D "$headers" -o "$body" "$@" -- "$BASE$path" \
    2>"$WORKDIR/curl.stderr"; then
    return 0
  fi
  return 1
}

# Best effort wake-up; the login attempts below handle an unavailable printer.
request /index.html "$WORKDIR/wakeup.headers" "$WORKDIR/wakeup.body" || true

SBID=""
for ((attempt = 1; attempt <= LOGIN_RETRIES; attempt++)); do
  if request /rui/sendpw.cgi "$WORKDIR/login.headers" "$WORKDIR/login.body" \
    --data-urlencode "NAMAE@$WORKDIR/namae" \
    --data-urlencode "IDTYPE=$IDTYPE"; then
    SBID="$(grep -aoE 'name="SBID"[^>]*value="[^"]+"' "$WORKDIR/login.body" |
      sed -E 's/.*value="([^"]+)".*/\1/' | head -n 1 || true)"
    [[ -z "$SBID" ]] || break
  fi
  if (( attempt < LOGIN_RETRIES )); then
    sleep "$WAKEUP_DELAY_SECONDS"
    request /index.html "$WORKDIR/wakeup.headers" "$WORKDIR/wakeup.body" || true
  fi
done

[[ -n "$SBID" ]] ||
  finish "$UNKNOWN" "[UNKNOWN] Canon Remote UI login failed (no session token)"
printf '%s' "$SBID" > "$WORKDIR/sbid"

request /rui/index.html "$WORKDIR/session.headers" "$WORKDIR/session.body" \
  --data-urlencode "SBID@$WORKDIR/sbid" ||
  finish "$UNKNOWN" "[UNKNOWN] Canon Remote UI session finalization failed"

request /rui/prninfo_data.cgi "$WORKDIR/ink.headers" "$WORKDIR/ink.xml" \
  --data-urlencode "GETINFO=0" --data-urlencode "SBID@$WORKDIR/sbid" ||
  finish "$UNKNOWN" "[UNKNOWN] Canon Remote UI ink request failed"

if grep -q '<SES_ERR_URL>' "$WORKDIR/ink.xml"; then
  finish "$UNKNOWN" "[UNKNOWN] Canon Remote UI session expired or invalid"
fi

mapfile -t entries < <(grep -aoE '<INKREST[0-9]+>[^<]*</INKREST[0-9]+>' "$WORKDIR/ink.xml" || true)
mapfile -t opening_tags < <(grep -aoE '<INKREST[0-9]+>' "$WORKDIR/ink.xml" || true)
if (( ${#entries[@]} == 0 || ${#entries[@]} != ${#opening_tags[@]} )); then
  finish "$UNKNOWN" "[UNKNOWN] missing or malformed Canon ink data"
fi

declare -A seen=()
details=()
perfdata=()
worst=$OK
tag_pattern='^<INKREST([0-9]+)>([^<]*)</INKREST([0-9]+)>$'
for entry in "${entries[@]}"; do
  [[ "$entry" =~ $tag_pattern ]] ||
    finish "$UNKNOWN" "[UNKNOWN] malformed Canon ink entry"
  opening_index="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  closing_index="${BASH_REMATCH[3]}"
  [[ "$opening_index" == "$closing_index" ]] ||
    finish "$UNKNOWN" "[UNKNOWN] mismatched Canon ink tags"

  IFS=',' read -r ink_type level status remainder <<< "$value"
  if [[ ! "$ink_type" =~ ^[0-9]+$ || ! "$level" =~ ^(10|11|[0-9])$ ||
        ! "$status" =~ ^[0-3]$ || -n "${remainder:-}" ]]; then
    finish "$UNKNOWN" "[UNKNOWN] unrecognized Canon ink values"
  fi
  [[ ! -v seen[$ink_type] ]] ||
    finish "$UNKNOWN" "[UNKNOWN] duplicate Canon ink cartridge"
  seen[$ink_type]=1

  case "$ink_type" in
    0) name=Color; perf_label=color ;;
    1) name=Black; perf_label=black ;;
    *) name="Ink$ink_type"; perf_label="ink$ink_type" ;;
  esac

  if [[ "$level" == 11 ]]; then
    percentage='?'
    (( status == 0 )) &&
      finish "$UNKNOWN" "[UNKNOWN] Canon reports an unreadable ink level"
  else
    percentage=$((100 - 10 * level))
    perfdata+=("${perf_label}=${percentage}%;;;0;100")
  fi

  case "$status" in
    0) severity=$OK ;;
    1|3) severity=$WARNING ;;
    2) severity=$CRITICAL ;;
  esac
  (( severity > worst )) && worst=$severity
  details+=("${name}:${percentage}%")
done

perfdata_suffix=''
if (( ${#perfdata[@]} > 0 )); then
  perfdata_suffix=" | ${perfdata[*]}"
fi
case "$worst" in
  0) finish "$OK" "[OK] ${details[*]}${perfdata_suffix}" ;;
  1) finish "$WARNING" "[WARNING] ${details[*]}${perfdata_suffix}" ;;
  2) finish "$CRITICAL" "[CRITICAL] ${details[*]}${perfdata_suffix}" ;;
esac
