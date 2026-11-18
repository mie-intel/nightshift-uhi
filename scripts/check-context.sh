#!/usr/bin/env bash
# Verify every @import path in CLAUDE.md and .claude/rules/*.md resolves to a real file.
# Resolves each @path relative to the directory of the file it appears in. (TODO Phase 0.7)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail=0
checked=0

files=("CLAUDE.md")
while IFS= read -r f; do files+=("$f"); done < <(find .claude/rules -name '*.md' 2>/dev/null | sort)

for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "MISSING FILE: $f"; fail=1; continue; }
  dir="$(dirname "$f")"
  # extract @tokens (paths have no spaces); ignore @ inside fenced code is not needed — we have none
  while IFS= read -r tok; do
    rel="${tok#@}"
    target="$(cd "$dir" 2>/dev/null && realpath -m "$rel")"
    checked=$((checked+1))
    if [ -f "$target" ]; then
      echo "OK   $f -> $rel"
    else
      echo "FAIL $f -> $rel (resolved: $target)"
      fail=1
    fi
  done < <(grep -oE '@[./A-Za-z0-9_-]+' "$f" || true)
done

echo "---"
echo "checked $checked import(s)"
if [ "$fail" -ne 0 ]; then
  echo "context check FAILED"
  exit 1
fi
echo "context check PASSED"
