#!/usr/bin/env bash
# Apply the Approver's structured decisions to the proposal issues.
# usage: apply-decisions.sh <decisions.json> <tracking-issue-number>
# env:   GH_REPO, GH_TOKEN
# Set CREW_DRY_RUN=1 to print actions instead of performing them.
# Only issue numbers listed in the tracking issue's crew-map can be touched, whatever the model returned.
set -euo pipefail

decisions="${1:?usage: apply-decisions.sh <decisions.json> <tracking-issue>}"
tracking="${2:?tracking issue number}"
dry="${CREW_DRY_RUN:-0}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run() { if [ "$dry" = "1" ]; then echo "[dry-run] $*" >&2; else "$@"; fi; }

body="$(gh issue view "$tracking" --json body --jq .body)"
map="$(sed -n 's/.*<!-- crew-map: \(.*\) -->.*/\1/p' <<<"$body" | head -1)"
[ -n "$map" ] || { echo "no crew-map in tracking issue #$tracking" >&2; exit 1; }

reply="$(jq -r '.reply' "$decisions")"
clarify="$(jq -r '.needs_clarification' "$decisions")"
approved=0
lines=""

if [ "$clarify" != "true" ]; then
  n="$(jq '.decisions | length' "$decisions")"
  i=0
  while [ "$i" -lt "$n" ]; do
    d="$(jq -c ".decisions[$i]" "$decisions")"
    i=$((i + 1))
    idx="$(jq -r .index <<<"$d")"
    action="$(jq -r .action <<<"$d")"
    note="$(jq -r .note <<<"$d")"
    num="$(jq -r --argjson i "$idx" '.[] | select(.index == $i) | .number' <<<"$map")"
    if [ -z "$num" ]; then
      lines+="- ⚠️ #$idx is not on this week's list, ignored"$'\n'
      continue
    fi
    state="$(gh issue view "$num" --json state,labels --jq '{state, labels: [.labels[].name]}')"
    if [ "$(jq -r .state <<<"$state")" != "OPEN" ]; then
      lines+="- ⚠️ #$num is already closed, ignored"$'\n'
      continue
    fi
    case "$action" in
      approve)
        if jq -e '.labels | index("crew:approved")' <<<"$state" >/dev/null; then
          lines+="- #$num was already approved"$'\n'
          continue
        fi
        if [ -n "$note" ]; then
          printf '**Owner note for the coder:** %s\n' "$note" > "$tmp/note.md"
          run gh issue comment "$num" --body-file "$tmp/note.md"
          if [ "$dry" = "1" ]; then cat "$tmp/note.md" >&2; fi
        fi
        run gh issue edit "$num" --add-label "crew:approved"
        lines+="- ✅ #$num approved"$'\n'
        approved=$((approved + 1))
        ;;
      skip)
        run gh issue edit "$num" --add-label "crew:skipped"
        run gh issue close "$num" --reason "not planned"
        lines+="- ⏭️ #$num skipped"$'\n'
        ;;
      hold)
        lines+="- ⏸️ #$num on hold"$'\n'
        ;;
    esac
  done
fi

{
  printf '%s\n' "$reply"
  if [ -n "$lines" ]; then printf '\n%s' "$lines"; fi
} > "$tmp/reply.md"
run gh issue comment "$tracking" --body-file "$tmp/reply.md"

echo "approved=$approved"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "approved=$approved" >> "$GITHUB_OUTPUT"; fi
[ "$dry" != "1" ] || cat "$tmp/reply.md"
