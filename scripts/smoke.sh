#!/usr/bin/env bash
# Smoke-test a deployed site: every configured page must answer 200 with a non-trivial body.
# usage: smoke.sh <base-url>
# env:   CREW_PAGES (json array of paths, default ["/"])
# Prints a markdown table; exits 1 if any page fails after retries.
set -uo pipefail

base="${1:?usage: smoke.sh <base-url>}"
pages="${CREW_PAGES:-}"
[ -n "$pages" ] || pages='["/"]'
failed=0

echo "| page | status | bytes |"
echo "|---|---|---|"
for p in $(jq -r '.[]' <<<"$pages"); do
  url="${base%/}$p"
  code="000"; size="0"
  for attempt in 1 2 3; do
    out="$(curl -sL -o /dev/null -w '%{http_code} %{size_download}' --max-time 30 "$url" 2>/dev/null || echo "000 0")"
    code="${out% *}"; size="${out#* }"
    if [ "$code" = "200" ] && [ "$size" -gt 500 ]; then break; fi
    [ "$attempt" -lt 3 ] && sleep "${SMOKE_RETRY_SLEEP:-10}"
  done
  if [ "$code" = "200" ] && [ "$size" -gt 500 ]; then icon="✅"; else icon="❌"; failed=1; fi
  echo "| $p | $icon $code | $size |"
done
exit "$failed"
