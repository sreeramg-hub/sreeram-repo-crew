#!/usr/bin/env bash
# Wait for a successful GitHub deployment of a commit (Vercel reports these) and print its URL.
# Prints nothing if none succeeds before the timeout.
# usage: wait-deployment.sh <sha> <timeout-seconds> [environment-substring, e.g. production|preview]
# env:   GH_TOKEN, GH_REPO
set -uo pipefail

sha="${1:?sha}"; timeout="${2:?timeout seconds}"; filter="$(printf '%s' "${3:-}" | tr '[:upper:]' '[:lower:]')"
deadline=$((SECONDS + timeout))

while :; do
  ids="$(gh api "repos/$GH_REPO/deployments?sha=$sha&per_page=20" \
    --jq ".[] | select(.environment | ascii_downcase | contains(\"$filter\")) | .id" 2>/dev/null)"
  for id in $ids; do
    url="$(gh api "repos/$GH_REPO/deployments/$id/statuses?per_page=5" \
      --jq '[.[] | select(.state == "success")] | first | (.environment_url // .target_url // empty)' 2>/dev/null)"
    if [ -n "$url" ]; then printf '%s\n' "$url"; exit 0; fi
  done
  [ "$SECONDS" -lt "$deadline" ] || exit 0
  sleep 15
done
