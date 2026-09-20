#!/usr/bin/env bash
# Turn the Reviewer's output plus automated evidence into a PR review, a commit status, labels and the next hand-off.
# A bot cannot approve or request changes on its own PR, so the verdict travels as the `crew/review` commit status
# (required by branch protection) and as labels; the review itself is a COMMENT review.
#
# env (required): GH_TOKEN GH_REPO PR SHA ROUND MAX_ROUNDS CREW_OWNER REVIEWER_JSON CHECKS_JSON
# env (optional): SHOTS_JSON PREVIEW_URL RUN_URL CREW_SCRIPTS (dir of this script's siblings)
# Set CREW_DRY_RUN=1 to print the payload and decisions without calling GitHub.
set -euo pipefail

scripts="${CREW_SCRIPTS:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
dry="${CREW_DRY_RUN:-0}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

: "${PR:?}" "${SHA:?}" "${ROUND:?}" "${MAX_ROUNDS:?}" "${CREW_OWNER:?}" "${REVIEWER_JSON:?}" "${CHECKS_JSON:?}"
shots="${SHOTS_JSON:-}"
[ -n "$shots" ] && [ -f "$shots" ] || { echo '[]' > "$tmp/shots.json"; shots="$tmp/shots.json"; }

# 1. Hard failures come from real tool exit codes, never from the model.
hard="$(jq -c '[to_entries[] | select(.value.status == "fail") | (.key + " failed")]' "$CHECKS_JSON")"
blocking="$(jq '([.findings[] | select(.severity == "blocker" or .severity == "major")] | length) + ([(.criteria // [])[] | select(.status == "not_met")] | length)' "$REVIEWER_JSON")"
unverifiable="$(jq -r '[(.criteria // [])[] | select(.status == "not_verifiable") | "- " + .criterion + (if (.note // "") != "" then " (" + .note + ")" else "" end)] | join("\n")' "$REVIEWER_JSON")"
model_verdict="$(jq -r .verdict "$REVIEWER_JSON")"

verdict="changes_requested"
if [ "$model_verdict" = "approve" ] && [ "$(jq length <<<"$hard")" -eq 0 ] && [ "$blocking" -eq 0 ]; then
  verdict="approve"
fi

build_payload() { # $1 = all_general true|false
  jq -n \
    --slurpfile reviewer "$REVIEWER_JSON" \
    --slurpfile shots "$shots" \
    --argjson hard "$hard" \
    --arg verdict "$verdict" \
    --argjson round "$ROUND" --argjson max "$MAX_ROUNDS" \
    --arg sha "$SHA" --arg preview "${PREVIEW_URL:-}" \
    --argjson fold "$1" '
      {reviewer: $reviewer[0], shots: $shots[0], hard: $hard, verdict: $verdict, round: $round,
       max_rounds: $max, sha: $sha, preview: $preview, all_general: $fold}' \
    | jq -f "$scripts/review-payload.jq"
}

api() { gh api "$@"; }

if [ "$dry" = "1" ]; then
  build_payload false
  echo "verdict=$verdict hard=$hard blocking=$blocking" >&2
  exit 0
fi

# 2. Post the review. If GitHub rejects the inline anchors, retry with everything in the body.
build_payload false > "$tmp/review.json"
if ! api --method POST "repos/$GH_REPO/pulls/$PR/reviews" --input "$tmp/review.json" >/dev/null 2>"$tmp/err"; then
  echo "inline review rejected ($(head -c 200 "$tmp/err")); retrying without inline comments" >&2
  build_payload true > "$tmp/review.json"
  api --method POST "repos/$GH_REPO/pulls/$PR/reviews" --input "$tmp/review.json" >/dev/null
fi

# 3. Commit status that branch protection can require.
if [ "$verdict" = "approve" ]; then state="success"; desc="Reviewer approved"; else state="failure"; desc="Changes requested (round $ROUND/$MAX_ROUNDS)"; fi
api --method POST "repos/$GH_REPO/statuses/$SHA" \
  -f state="$state" -f context="crew/review" -f description="$desc" \
  -f target_url="${RUN_URL:-https://github.com/$GH_REPO/pull/$PR}" >/dev/null

# 4. Labels.
if [ "$verdict" = "approve" ]; then
  gh pr edit "$PR" --add-label "crew:review-approved" --remove-label "crew:changes-requested" >/dev/null
else
  gh pr edit "$PR" --add-label "crew:changes-requested" --remove-label "crew:review-approved" >/dev/null
fi

# 5. Hand off. Only PRs the Coder opened get an automatic fix loop; owner-run reviews of other PRs stop here.
is_crew_pr="$(gh pr view "$PR" --json labels --jq '[.labels[].name] | index("crew:pr") != null')"
if [ "$verdict" = "approve" ]; then
  {
    printf '@%s ✅ **Ready for you.** The reviewer approved this PR'"'"'s changes' "$CREW_OWNER"
    [ "$ROUND" -gt 1 ] && printf ' after %s rounds' "$ROUND"
    printf '.\n\n'
    [ -n "${PREVIEW_URL:-}" ] && printf 'Preview: %s\n\n' "$PREVIEW_URL"
    [ -n "$unverifiable" ] && printf '👀 **Please check these yourself, the crew cannot verify them:**\n%s\n\n' "$unverifiable"
    printf 'Check the preview on your phone, then merge. To ask for a change instead, comment `/fix <what to change>`.\n'
  } > "$tmp/ready.md"
  gh pr comment "$PR" --body-file "$tmp/ready.md" >/dev/null
elif [ "$is_crew_pr" != "true" ]; then
  echo "not a crew PR; no automatic fix round"
elif [ "$ROUND" -lt "$MAX_ROUNDS" ]; then
  gh workflow run crew-coder.yml -f mode=fix -f pr="$PR" >/dev/null
  echo "dispatched coder fix (round $((ROUND + 1)))"
else
  gh pr edit "$PR" --add-label "crew:needs-human" >/dev/null
  printf '@%s 🚧 Still not passing review after %s rounds. I have stopped here so it does not loop. Comment `/fix <instructions>` to steer it, or close the PR.\n' \
    "$CREW_OWNER" "$MAX_ROUNDS" > "$tmp/stuck.md"
  gh pr comment "$PR" --body-file "$tmp/stuck.md" >/dev/null
fi

echo "verdict=$verdict"
if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "verdict=$verdict" >> "$GITHUB_OUTPUT"; fi
