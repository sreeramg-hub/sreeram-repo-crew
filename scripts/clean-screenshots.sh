#!/usr/bin/env bash
# Remove a closed PR's screenshots from the `crew-screenshots` branch (and squash it again).
# usage: clean-screenshots.sh <pr>
# env:   GH_TOKEN, GH_REPO
set -euo pipefail

pr="${1:?pr}"
branch="crew-screenshots"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git init -q "$work"
cd "$work"
git config user.name "crew-screenshots"
git config user.email "crew-screenshots@users.noreply.github.com"
git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/${GH_REPO}.git"
git fetch -q --depth 1 origin "$branch" 2>/dev/null || { echo "no $branch branch, nothing to clean"; exit 0; }
git checkout -q -b work FETCH_HEAD
[ -d "pr-$pr" ] || { echo "no screenshots for PR #$pr"; exit 0; }
git rm -rq "pr-$pr"
git checkout -q --orphan squashed
git commit -q --allow-empty -m "crew screenshots"
git push -q --force origin "squashed:refs/heads/$branch" >/dev/null 2>&1
echo "removed screenshots for PR #$pr"
