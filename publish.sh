#!/usr/bin/env bash
# publish.sh — put one HTML page on the public site and wait until it is live.
#
#   bash publish.sh <page.html> <slug>   ->  https://m41w4r3exe.github.io/pages/<slug>/
#
# Accepts a full HTML document or a claude.ai artifact fragment (no doctype/head):
# a fragment gets a doctype, utf-8 charset and viewport tag. Every page gets
# <meta name="robots" content="noindex"> so search engines skip it.
# Re-publishing the same slug replaces the page; the link stays the same.
set -euo pipefail

src=${1:?usage: publish.sh <page.html> <slug>}
slug=${2:?usage: publish.sh <page.html> <slug>}
[[ $slug =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "slug may only hold a-z, 0-9 and -" >&2; exit 2; }
[[ -f $src ]] || { echo "no such file: $src" >&2; exit 2; }

repo=m41w4r3exe/pages
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$here/$slug"

python3 -I - "$src" "$here/$slug/index.html" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
robots = '<meta name="robots" content="noindex">'
if not re.match(r"\s*<!doctype", s, re.I):
    s = ('<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
         '<meta name="viewport" content="width=device-width, initial-scale=1">\n'
         + robots + "\n</head>\n<body>\n" + s + "\n</body>\n</html>\n")
elif 'name="robots"' not in s:
    s = re.sub(r"(<head[^>]*>)", r"\1\n" + robots, s, count=1, flags=re.I)
open(sys.argv[2], "w", encoding="utf-8").write(s)
PY

cd "$here"
git add "$slug/index.html"
if git diff --cached --quiet; then
  echo "unchanged: $slug"
else
  git commit -q -m "publish $slug" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
fi
git push -q origin main
sha=$(git rev-parse HEAD)
url="https://$(cut -d/ -f1 <<<"$repo").github.io/pages/$slug/"

# wait for the Pages build of this commit (usually 30-60 s)
for _ in $(seq 1 36); do
  st=$(gh api "repos/$repo/pages/builds/latest" --jq '.status + " " + .commit' 2>/dev/null || true)
  [[ $st == "built $sha" ]] && break
  [[ $st == errored* ]] && { echo "Pages build failed: $st" >&2; exit 1; }
  sleep 5
done
code=$(curl -s -o /dev/null -w '%{http_code}' "$url")
echo "$url  (HTTP $code)"
[[ $code == 200 ]]
