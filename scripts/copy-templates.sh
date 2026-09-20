#!/usr/bin/env bash
# Copy the project templates into a project without overwriting anything that already exists.
# usage: copy-templates.sh <project-dir>
# Always exits 0 when nothing needed copying (BSD `cp -n` exits 1 in that case, which is why this is not cp -Rn).
set -euo pipefail

crew_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$crew_root/templates/project"
dest="${1:?usage: copy-templates.sh <project-dir>}"
added=0
kept=0

while IFS= read -r f; do
  rel="${f#"$src"/}"
  if [ -e "$dest/$rel" ]; then
    kept=$((kept + 1))
  else
    mkdir -p "$(dirname "$dest/$rel")"
    cp "$f" "$dest/$rel"
    added=$((added + 1))
    echo "    added $rel"
  fi
done < <(find "$src" -type f | sort)

echo "    $added added, $kept already present (left untouched)"
