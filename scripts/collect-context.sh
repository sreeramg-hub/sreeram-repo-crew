#!/usr/bin/env bash
# Print the Coder's spec as markdown.
# usage: collect-context.sh implement <issue>
#        collect-context.sh fix <pr> [owner instruction]
# env:   GH_REPO, GH_TOKEN, CREW_OWNER
# Only the owner's comments are included besides the crew's own review; nobody else's text reaches the Coder.
set -euo pipefail

mode="${1:?mode}"; n="${2:?number}"; instruction="${3:-}"
owner="${CREW_OWNER:?CREW_OWNER not set}"

issue_spec() {
  gh issue view "$1" --json number,title,body,comments \
    | jq -r --arg owner "$owner" '
        "# Issue #\(.number): \(.title)\n\n\(.body)\n"
        + ([.comments[] | select(.author.login == $owner) | "\n**Owner comment:** " + .body] | join("\n"))'
}

case "$mode" in
  implement)
    issue_spec "$n"
    ;;
  fix)
    pr_json="$(gh pr view "$n" --json title,body)"
    echo "# Pull request #$n: $(jq -r .title <<<"$pr_json")"
    linked="$(jq -r .body <<<"$pr_json" | grep -oiE '(closes|fixes|resolves) #[0-9]+' | head -1 | grep -oE '[0-9]+' || true)"
    if [ -n "$linked" ]; then
      echo; echo "## Original spec"; echo
      issue_spec "$linked"
    fi

    reviews="$(gh api "repos/$GH_REPO/pulls/$n/reviews" --paginate | jq -s 'add // []')"
    last="$(jq -c '[.[] | select(.body | contains("crew-review"))] | last // empty' <<<"$reviews")"
    if [ -n "$last" ]; then
      rid="$(jq -r .id <<<"$last")"
      echo; echo "## Latest review"; echo
      jq -r .body <<<"$last"
      echo; echo "## Inline review comments"; echo
      gh api "repos/$GH_REPO/pulls/$n/comments" --paginate | jq -s -r --argjson rid "$rid" \
        'add // [] | map(select(.pull_request_review_id == $rid)) | map("- `\(.path):\(.line // .original_line)`: \(.body)") | join("\n")'
    fi
    if [ -n "$instruction" ]; then
      echo; echo "## Owner instruction"; echo
      printf '%s\n' "$instruction"
    fi
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
