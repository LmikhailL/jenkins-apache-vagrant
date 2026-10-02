#!/usr/bin/env bash
# Analyse Apache logs for 4xx and 5xx responses.
# Usage: check_logs.sh [access_log] [error_log]
set -euo pipefail

ACCESS_LOG="${1:-/var/log/apache2/access.log}"
ERROR_LOG="${2:-/var/log/apache2/error.log}"

[ -r "$ACCESS_LOG" ] || { echo "Cannot read $ACCESS_LOG" >&2; exit 2; }

# Combined log format: ... "REQUEST" STATUS SIZE "REFERER" "UA"
# Splitting on '"' puts the status code at the start of field 3.
status_of='{ split($3, a, " "); print a[1] }'

total=$(wc -l < "$ACCESS_LOG" | tr -d ' ')
c4xx=$(awk -F'"' "$status_of" "$ACCESS_LOG" | grep -c '^4' || true)
c5xx=$(awk -F'"' "$status_of" "$ACCESS_LOG" | grep -c '^5' || true)

echo "=== Apache log analysis on $(hostname) at $(date -Is) ==="
echo "Access log : $ACCESS_LOG"
echo "Total requests : $total"
echo "4xx responses  : $c4xx"
echo "5xx responses  : $c5xx"
echo

echo "--- Responses by status code ---"
awk -F'"' "$status_of" "$ACCESS_LOG" | sort | uniq -c | sort -k2n
echo

for class in 4 5; do
  echo "--- ${class}xx requests (status | client | request) ---"
  awk -F'"' -v c="$class" '{ split($3, a, " "); split($1, h, " ");
       if (substr(a[1],1,1) == c) printf "%s | %s | %s\n", a[1], h[1], $2 }' "$ACCESS_LOG" \
    | sort | uniq -c | sort -rn
  echo
done

if [ -r "$ERROR_LOG" ]; then
  echo "--- error.log: last 15 lines with error/warn ---"
  grep -E '\[(.*:)?(error|warn|crit|alert|emerg)\]' "$ERROR_LOG" | tail -n 15 || echo "(none)"
fi

# Machine-readable summary for the pipeline
echo
echo "SUMMARY total=$total 4xx=$c4xx 5xx=$c5xx"
