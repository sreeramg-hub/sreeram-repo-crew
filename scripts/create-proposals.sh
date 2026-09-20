#!/usr/bin/env bash
# Turn the Scout's proposals into one issue each plus a weekly tracking issue.
# usage: create-proposals.sh <proposals.json> <week, e.g. 2026-W39>
# env:   GH_REPO, GH_TOKEN, CREW_OWNER, CREW_MAX_SIZE, CREW_SCOUT_MAX, CREW_SCOUT_TRACKS
# Set CREW_DRY_RUN=1 to print the issues instead of creating them.
set -euo pipefail

in="${1:?usage: create-proposals.sh <proposals.json> <week>}"
week="${2:?week}"
short="${week#*-}"
owner="${CREW_OWNER:?CREW_OWNER not set}"
max_size="${CREW_MAX_SIZE:-M}"
max_total="${CREW_SCOUT_MAX:-5}"
tracks="${CREW_SCOUT_TRACKS:-}"
[ -n "$tracks" ] || tracks='{"quality":2,"feature":2,"learn":2}'

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Enforce size, per-track and total caps in code, whatever the model returned.
selected="$(jq -c --arg max "$max_size" --argjson total "$max_total" --argjson caps "$tracks" '
  [ .proposals[] | select(.size == "S" or (.size == "M" and $max == "M")) ]
  | reduce .[] as $p ({out: [], counts: {}};
      if (.out | length) >= $total then .
      elif ((.counts[$p.track] // 0) >= ($caps[$p.track] // 0)) then .
      else .out += [$p] | .counts[$p.track] = ((.counts[$p.track] // 0) + 1) end)
  | .out' "$in")"
count="$(jq length <<<"$selected")"

create_issue() { # title, body-file, labels
  if [ "${CREW_DRY_RUN:-0}" = "1" ]; then
    echo "[dry-run] issue: $1 (labels: $3)" >&2
    echo "https://example.invalid/issues/0"
  else
    gh issue create --title "$1" --body-file "$2" --label "$3"
  fi
}

track_label() {
  case "$1" in
    quality) echo "🔧 Quality" ;;
    feature) echo "✨ Feature" ;;
    learn) echo "📚 Learn" ;;
    *) echo "$1" ;;
  esac
}

map='[]'
list=""
i=0
while [ "$i" -lt "$count" ]; do
  p="$(jq -c ".[$i]" <<<"$selected")"
  idx=$((i + 1))
  track="$(jq -r .track <<<"$p")"
  size="$(jq -r .size <<<"$p")"
  risk="$(jq -r .risk <<<"$p")"
  title="$(jq -r .title <<<"$p")"

  jq -r --arg week "$week" --arg tl "$(track_label "$track")" '
    "<!-- crew-week: \($week) -->\n"
    + "**\($tl) · size \(.size) · \(.risk) risk**\n\n"
    + .summary + "\n\n**Why:** " + .why
    + "\n\n### Acceptance criteria\n" + ([.acceptance_criteria[] | "- [ ] " + .] | join("\n"))
    + (if (.files_hint | length) > 0 then "\n\n### Likely files\n" + ([.files_hint[] | "- `" + . + "`"] | join("\n")) else "" end)
    + (if (.sources | length) > 0 then "\n\n### Sources\n" + ([.sources[] | "- [" + .title + "](" + .url + ") (as of " + .as_of + ")"] | join("\n")) else "" end)
    + (if (.needs_owner_input | length) > 0 then "\n\n### Needs your input\n" + ([.needs_owner_input[] | "- " + .] | join("\n")) else "" end)
    + "\n\n---\n_Proposed by the crew Scout. Approve by replying on the weekly proposals issue._"
  ' <<<"$p" > "$tmp/body-$idx.md"

  url="$(create_issue "[$short-$idx] $title" "$tmp/body-$idx.md" "crew:proposal,track:$track,size:$size")"
  num="${url##*/}"
  map="$(jq -c --argjson i "$idx" --argjson n "$num" '. + [{index: $i, number: $n}]' <<<"$map")"

  list+="### $idx. $(track_label "$track") · $size · $risk risk"$'\n'
  list+="**$title** (#$num)"$'\n'
  list+="$(jq -r .summary <<<"$p")"$'\n'
  needs="$(jq -r '.needs_owner_input | length' <<<"$p")"
  if [ "$needs" -gt 0 ]; then list+="_Needs your input before it can be finished._"$'\n'; fi
  list+=$'\n'
  i=$((i + 1))
done

if [ "$count" -eq 0 ]; then
  printf '<!-- crew-week: %s -->\nNo proposals this week.\n' "$week" > "$tmp/tracking.md"
else
  {
    printf '<!-- crew-week: %s -->\n' "$week"
    printf '<!-- crew-map: %s -->\n' "$map"
    printf '@%s here are this week'"'"'s proposals.\n\n' "$owner"
    printf '**Reply with a comment** in plain English, for example: `do 1 and 3, skip 2, keep 3 minimal`.\n'
    printf 'Approved items are built one at a time. Each one becomes a PR you can preview and merge from your phone.\n\n'
    printf '%s' "$list"
    printf -- '---\nCommands: `/scout` runs the Scout again.\n'
  } > "$tmp/tracking.md"
fi

url="$(create_issue "Proposals $week" "$tmp/tracking.md" "crew:proposals")"
tracking="${url##*/}"
if [ "$count" -eq 0 ] && [ "${CREW_DRY_RUN:-0}" != "1" ]; then
  gh issue close "$tracking" --reason "not planned" >/dev/null
fi

echo "created $count proposals; tracking issue #$tracking"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "tracking=$tracking" >> "$GITHUB_OUTPUT"
  echo "count=$count" >> "$GITHUB_OUTPUT"
fi
[ "${CREW_DRY_RUN:-0}" != "1" ] || cat "$tmp/tracking.md"
