#!/usr/bin/env bash
# Print the number of the next approved proposal to build, or nothing.
# One crew PR at a time: if a crew PR is still open, print nothing.
# env: GH_REPO, GH_TOKEN
set -euo pipefail

open_prs="$(gh pr list --label crew:pr --state open --json number --jq length)"
if [ "$open_prs" -gt 0 ]; then
  exit 0
fi

gh issue list --label crew:approved --state open --limit 50 --json number,labels \
  | jq -r '[ .[] | select(all(.labels[]; .name != "crew:in-progress")) ] | sort_by(.number) | .[0].number // empty'
