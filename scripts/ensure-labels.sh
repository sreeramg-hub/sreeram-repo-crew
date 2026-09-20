#!/usr/bin/env bash
# Create or update every label the crew uses. Safe to run repeatedly.
# env: GH_REPO (or run inside a clone), GH_TOKEN
set -euo pipefail

labels=(
  "crew:proposals|5319e7|Weekly proposals tracking issue"
  "crew:proposal|8250df|A proposal from the Scout"
  "crew:approved|0e8a16|Approved by the owner, waiting for the Coder"
  "crew:in-progress|fbca04|Coder is working on it or a PR is open"
  "crew:skipped|cccccc|Skipped by the owner"
  "crew:needs-human|d93f0b|The crew is stuck and needs the owner"
  "crew:pr|1d76db|Pull request opened by the Coder"
  "crew:review-approved|0e8a16|Reviewer passed this PR"
  "crew:changes-requested|e99695|Reviewer requested changes"
  "track:quality|c5def5|Quality track"
  "track:feature|c5def5|Feature track"
  "track:learn|c5def5|Learn track"
  "size:S|ededed|Small change"
  "size:M|ededed|Medium change"
)

for entry in "${labels[@]}"; do
  IFS='|' read -r name color desc <<<"$entry"
  gh label create "$name" --color "$color" --description "$desc" --force >/dev/null
done
echo "labels ok (${#labels[@]})"
