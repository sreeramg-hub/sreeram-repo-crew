#!/usr/bin/env bash
# Onboard a project repository to the crew.
# usage: onboard.sh [path-to-project]   (default: current directory)
# Needs the GitHub CLI, logged in as the repo owner: `brew install gh && gh auth login`.
# Nothing is overwritten: existing .crew/ and workflow files are left alone.
set -euo pipefail

crew_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${1:-.}"

command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Run: gh auth login" >&2; exit 1; }

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
branch="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
echo "Onboarding $repo (default branch: $branch)"

echo "1/5 Copying templates (no overwrite)"
"$crew_root/scripts/copy-templates.sh" .
echo "    Edit .crew/config.yml, .crew/goals.md and .crew/sources.yml, then commit them on a branch."

echo "2/5 Creating labels"
GH_REPO="$repo" "$crew_root/scripts/ensure-labels.sh"

echo "3/5 Anthropic API key secret"
existing_secrets="$(gh secret list --repo "$repo" 2>/dev/null || true)"
if grep -q '^ANTHROPIC_API_KEY' <<<"$existing_secrets"; then
  echo "    ANTHROPIC_API_KEY already set"
else
  echo "    Paste your key when prompted (input is hidden and goes straight to GitHub):"
  gh secret set ANTHROPIC_API_KEY --repo "$repo"
fi

echo "4/5 Letting Actions open pull requests"
gh api --method PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true >/dev/null
echo "    done"

echo "5/5 Branch protection on $branch"
read -r -p "    Require the crew/review status before merging into $branch? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  gh api --method PUT "repos/$repo/branches/$branch/protection" --input - >/dev/null <<'JSON'
{
  "required_status_checks": { "strict": false, "contexts": ["crew/review"] },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
JSON
  echo "    protected. You (the admin) can still merge in an emergency; agents cannot push to $branch."
else
  echo "    skipped. Add it later in Settings > Branches."
fi

echo
echo "Done. Next: commit the .crew/ and .github/workflows/crew-*.yml files via a PR, then run the"
echo "'crew-scout' workflow once (Actions tab, Run workflow) to see the first proposals."
