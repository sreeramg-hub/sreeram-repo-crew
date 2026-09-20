# Build a GitHub "create review" payload from the Reviewer's structured output.
#
# Input object:
#   reviewer      the Reviewer's JSON (verdict, summary, checklist, findings, fact_checks)
#   verdict       final verdict after hard checks: "approve" | "changes_requested"
#   hard          array of failed automated checks, e.g. ["lint failed"]
#   round, max_rounds, sha
#   preview       preview URL or ""
#   shots         array of { label, viewport, scheme, url }
#   all_general   true to fold inline findings into the body (used when GitHub rejects inline anchors)
#
# Output: { commit_id, event, body, comments }

def icon: ({"blocker": "🛑", "major": "🟠", "minor": "🟡", "nit": "⚪"}[.] // "•");
def rank: ({"blocker": 0, "major": 1, "minor": 2, "nit": 3}[.] // 4);
def mark: ({"pass": "✅", "concern": "⚠️", "fail": "❌", "n/a": "➖"}[.] // "➖");
def anchored: ((.path // "") != "") and ((.line // 0) > 0);
def fmt: "\(.severity | icon) **\(.severity)** · \(.category): \(.body)";
def fmt_located: "\(.severity | icon) **\(.severity)** · \(.category) · `\(.path):\(.line)`: \(.body)";
def fact_icon: (if . == "supported" then "✅" elif . == "unsupported" then "❌" else "❔" end);

. as $in
| ($in.reviewer.findings // [] | sort_by(.severity | rank)) as $f
| ($in.all_general // false) as $fold
| (if $fold then [] else ($f | map(select(anchored))) end) as $inline
| (if $fold then $f else ($f | map(select(anchored | not))) end) as $general
| ($in.reviewer.checklist // {}) as $c
| ($in.reviewer.fact_checks // []) as $facts
| ($in.shots // []) as $shots
| {
    commit_id: $in.sha,
    event: "COMMENT",
    body: (
      "<!-- crew-review round=\($in.round) sha=\($in.sha) -->\n"
      + (if $in.verdict == "approve" then "## ✅ Review passed" else "## ✋ Changes requested" end)
      + " · round \($in.round)/\($in.max_rounds)\n\n"
      + ($in.reviewer.summary // "") + "\n\n"
      + (if ($in.hard | length) > 0 then "**Automated checks failed:** " + ($in.hard | join(", ")) + "\n\n" else "" end)
      + "| UI | Standards | Correctness | A11y | Scope | Content |\n|:-:|:-:|:-:|:-:|:-:|:-:|\n"
      + "| \($c.ui | mark) | \($c.standards | mark) | \($c.correctness | mark) | \($c.accessibility | mark) | \($c.scope | mark) | \($c.content_accuracy | mark) |\n"
      + (if ($general | length) > 0
          then "\n### Findings\n" + ($general | map("- " + (if anchored then fmt_located else fmt end)) | join("\n")) + "\n"
          else "" end)
      + (if ($facts | length) > 0
          then "\n### Fact checks\n" + ($facts | map("- \(.result | fact_icon) \(.claim) ([source](\(.source_url)))" + (if (.note // "") != "" then ": " + .note else "" end)) | join("\n")) + "\n"
          else "" end)
      + (if ($shots | length) > 0
          then "\n### Screenshots\n"
               + ($shots | group_by(.viewport)
                  | map("<details><summary>" + (.[0].viewport // "view") + "</summary>\n\n"
                        + (map("**\(.label)**\n\n![\(.label)](\(.url))") | join("\n\n"))
                        + "\n\n</details>")
                  | join("\n"))
               + "\n"
          else "" end)
      + (if ($in.preview // "") != "" then "\n**Preview:** \($in.preview)\n" else "" end)
    ),
    comments: ($inline | map({path: .path, line: .line, side: "RIGHT", body: fmt}))
  }
