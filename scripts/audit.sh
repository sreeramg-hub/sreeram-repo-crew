#!/usr/bin/env bash
# Best-effort project audit for the Scout. Prints markdown; never fails the run.
# env: CREW_PM, CREW_PROD_URL, CREW_PAGES
set +e

pm="${CREW_PM:-pnpm}"
echo "# Audit"

echo; echo "## Dependency audit"
case "$pm" in
  pnpm) pnpm audit --audit-level moderate 2>&1 | tail -n 40 ;;
  npm) npm audit --audit-level=moderate 2>&1 | tail -n 40 ;;
  yarn) yarn audit --level moderate 2>&1 | tail -n 40 ;;
esac

echo; echo "## Outdated dependencies"
case "$pm" in
  pnpm) pnpm outdated 2>&1 | head -n 40 ;;
  npm) npm outdated 2>&1 | head -n 40 ;;
  yarn) yarn outdated 2>&1 | head -n 40 ;;
esac

if [ -n "${CREW_PROD_URL:-}" ]; then
  echo; echo "## Lighthouse on production (mobile emulation)"
  echo "| page | performance | accessibility | best practices | SEO |"
  echo "|---|---|---|---|---|"
  for p in $(jq -r '.[0:3][]' <<<"${CREW_PAGES:-[\"/\"]}"); do
    out="$(mktemp)"
    npx --yes lighthouse@12 "${CREW_PROD_URL%/}$p" --quiet --output=json --output-path="$out" \
      --only-categories=performance,accessibility,best-practices,seo \
      --chrome-flags="--headless=new --no-sandbox" >/dev/null 2>&1
    if [ -s "$out" ]; then
      jq -r --arg p "$p" '"| \($p) | \(.categories.performance.score * 100 | floor) | \(.categories.accessibility.score * 100 | floor) | \(.categories["best-practices"].score * 100 | floor) | \(.categories.seo.score * 100 | floor) |"' "$out"
    else
      echo "| $p | n/a | n/a | n/a | n/a |"
    fi
    rm -f "$out"
  done
fi

echo; echo "## Repository inventory"
echo '```'
git ls-files | grep -vE '(^|/)(node_modules|\.next|public/examples)/' | head -n 150
echo '```'
echo; echo "Open TODO/FIXME markers: $(git grep -nE 'TODO|FIXME' -- . ':!*.lock' ':!pnpm-lock.yaml' ':!package-lock.json' 2>/dev/null | wc -l | tr -d ' ')"
echo; echo "## Recent commits"
git log --oneline -20
exit 0
