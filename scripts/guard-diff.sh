#!/usr/bin/env bash
# Fail if the branch changes protected paths or dependencies.
# usage: guard-diff.sh <base-ref>
# env:   CREW_PROTECTED  JSON array of globs (default below)
#        CREW_ALLOW_DEPS "true" to permit dependency and lockfile changes
# exit:  0 ok, 1 violation, 2 no changes at all
set -euo pipefail

base="${1:?usage: guard-diff.sh <base-ref>}"
protected="${CREW_PROTECTED:-}"
[ -n "$protected" ] || protected='[".github/**",".crew/**",".env*","*.pem","*.key"]'
allow_deps="${CREW_ALLOW_DEPS:-false}"
violations=""

changed="$(git diff --name-only "$base"...HEAD)"
if [ -z "$changed" ]; then
  echo "guard: no changes against $base" >&2
  exit 2
fi

# In [[ == ]] patterns, * already matches across slashes, so ** collapses to *.
while IFS= read -r f; do
  while IFS= read -r pat; do
    glob="${pat//\*\*/*}"
    # shellcheck disable=SC2053
    if [[ "$f" == $glob ]]; then
      violations+="protected path changed: $f (matches $pat)"$'\n'
    fi
  done < <(jq -r '.[]' <<<"$protected")
done <<<"$changed"

if [ "$allow_deps" != "true" ]; then
  if grep -Eq '(^|/)(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$' <<<"$changed"; then
    violations+="lockfile changed but dependency changes are not allowed"$'\n'
  fi
  if git cat-file -e "$base:package.json" 2>/dev/null && git cat-file -e "HEAD:package.json" 2>/dev/null; then
    filter='[.dependencies, .devDependencies, .optionalDependencies, .peerDependencies]'
    before="$(git show "$base:package.json" | jq -S "$filter")"
    after="$(git show "HEAD:package.json" | jq -S "$filter")"
    if [ "$before" != "$after" ]; then
      violations+="package.json dependencies changed but dependency changes are not allowed"$'\n'
    fi
  fi
fi

if [ -n "$violations" ]; then
  printf 'guard: refusing to continue\n%s' "$violations" >&2
  exit 1
fi
echo "guard: ok ($(wc -l <<<"$changed" | tr -d ' ') files changed)"
