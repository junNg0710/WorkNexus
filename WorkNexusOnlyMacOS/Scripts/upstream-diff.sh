#!/bin/sh
# What changed upstream since the last port? Usage: Scripts/upstream-diff.sh [--stat|--mark]
#   (no flag)  list changed Dart/asset files grouped by module, mapped to their Swift counterpart
#   --stat     git diff --stat for the same paths
#   --mark     record upstream/main HEAD as ported (writes UPSTREAM_PORTED) — run after you finish porting
set -e
ROOT="$(git rev-parse --show-toplevel)"
HERE="$ROOT/WorkNexusOnlyMacOS"
cd "$ROOT"
git fetch upstream --quiet
BASE="$(tr -d '[:space:]' < "$HERE/UPSTREAM_PORTED")"
HEAD_SHA="$(git rev-parse upstream/main)"
PATHS="lib assets pubspec.yaml"
case "$1" in
  --mark) echo "$HEAD_SHA" | cut -c1-7 > "$HERE/UPSTREAM_PORTED"; echo "UPSTREAM_PORTED -> $(cat "$HERE/UPSTREAM_PORTED")"; exit 0;;
  --stat) git diff --stat "$BASE" upstream/main -- $PATHS; exit 0;;
esac
echo "ported: $BASE   upstream/main: $(echo $HEAD_SHA | cut -c1-7)"
echo "commits:"; git log --oneline "$BASE..upstream/main" -- $PATHS | sed 's/^/  /'
echo; echo "changed files (status path -> swift counterpart):"
git diff --name-status "$BASE" upstream/main -- $PATHS | grep -v -E '\.(g|freezed|config)\.dart$' | while read st p; do
  mod="$(echo "$p" | awk -F/ '{ if ($1=="lib" && ($2=="tools"||$2=="features")) print $2"/"$3; else if ($1=="lib") print $2; else print $1 }')"
  swift="$(cat "$HERE"/PORT_MAP.md "$HERE"/PortMap/*.md 2>/dev/null | grep -F "$p" | head -1 | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
  printf '%s\t%-28s %s%s\n' "$st" "$mod" "$p" "${swift:+  ->  $swift}"
done | sort -k2
