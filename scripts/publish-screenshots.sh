#!/usr/bin/env bash
# Publish screenshots to an orphan `crew-screenshots` branch so they render inside PR comments on a phone.
# Every publish squashes the branch to a single commit, so history never accumulates.
# usage: publish-screenshots.sh <pr> <sha> <evidence-dir>   (evidence-dir contains manifest.json and the images)
# prints: a JSON array of { label, viewport, scheme, url } on stdout
# env:    GH_TOKEN, GH_REPO
set -euo pipefail

pr="${1:?pr}"; sha="${2:?sha}"; dir="${3:?evidence dir}"
short="${sha:0:7}"
branch="crew-screenshots"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

remote="https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"
git init -q "$work"
cd "$work"
git config user.name "crew-screenshots"
git config user.email "crew-screenshots@users.noreply.github.com"
git remote add origin "$remote"
if git fetch -q --depth 1 origin "$branch" 2>/dev/null; then
  git checkout -q -b work FETCH_HEAD
else
  git checkout -q --orphan work
fi

mkdir -p "pr-$pr/$short"
find "$dir" -maxdepth 1 -name '*.jpg' -exec cp {} "pr-$pr/$short/" \;
git add -A
git commit -q -m "screenshots for PR #$pr at $short" --allow-empty
# Squash to one commit so the branch never grows.
git checkout -q --orphan squashed
git commit -q -m "crew screenshots"
git push -q --force origin "squashed:refs/heads/$branch" >/dev/null 2>&1

base="https://github.com/${GH_REPO}/blob/${branch}/pr-${pr}/${short}"
jq --arg base "$base" '[.shots[] | {label: "\(.page) · \(.viewport) · \(.scheme)", viewport, scheme, url: ($base + "/" + .file + "?raw=true")}]' "$dir/manifest.json"
