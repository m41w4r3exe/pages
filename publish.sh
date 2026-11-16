#!/usr/bin/env bash
# publish.sh — put one HTML page on the public site and wait until it is live.
#
#   bash publish.sh <page.html> <slug> [--password]
#     ->  https://m41w4r3exe.github.io/pages/<slug>/
#
# Accepts a full HTML document or a claude.ai artifact fragment (no doctype/head):
# a fragment gets a doctype, utf-8 charset and viewport tag. Every page gets
# <meta name="robots" content="noindex"> so search engines skip it.
# Re-publishing the same slug replaces the page; the link stays the same.
#
# --password encrypts the page with StatiCrypt (AES-256, decrypted in the
# visitor's browser) before it is committed, so the public repo only holds
# ciphertext and a password prompt. The password comes from $STATICRYPT_PASSWORD,
# or from a prompt when run in a terminal. All encrypted pages share the salt in
# .staticrypt.json, so "Remember me" on one page also opens every other page
# published with the same password. Encrypted pages get the generic title
# "Protected page". Earlier unencrypted versions of a slug stay in the public
# git history (the script warns), and an encrypted slug is never republished
# without --password (the script refuses). Use it for anything not meant for the whole
# internet: company numbers, private lists. The ciphertext is public, so a short
# password can be guessed offline; prefer 14+ characters.
set -euo pipefail

usage="usage: publish.sh <page.html> <slug> [--password]"
src=${1:?$usage}
slug=${2:?$usage}
encrypt=0
case ${3-} in
  "") ;;
  --password) encrypt=1 ;;
  *) echo "$usage" >&2; exit 2 ;;
esac
[[ $slug =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "slug may only hold a-z, 0-9 and -" >&2; exit 2; }
[[ -f $src ]] || { echo "no such file: $src" >&2; exit 2; }

repo=m41w4r3exe/pages
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$here/$slug"

# normalize <in> <out>: complete a fragment into a document and add noindex.
normalize() {
  python3 -I - "$1" "$2" <<'PY'
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
}

normalize "$src" "$tmp/index.html"

# Encrypted files carry StatiCrypt's config object; plain pages never do.
# (No `| grep -q`: grep would quit at the first match, git show would die of
# SIGPIPE, and pipefail would turn that into "not encrypted".)
is_encrypted() {
  local s
  s=$(git -C "$here" show "$1:$slug/index.html" 2>/dev/null) || return 1
  [[ $s == *staticryptConfig* ]]
}
if (( encrypt )); then
  plain=""
  for c in $(git -C "$here" log --format=%h -- "$slug/index.html"); do
    is_encrypted "$c" || plain+=" $c"
  done
  [[ -z $plain ]] ||
    echo "warning: earlier unencrypted versions of $slug stay readable in the public git history:$plain" >&2
elif is_encrypted HEAD; then
  echo "$slug is password-protected; pass --password to update it (refusing to publish it unencrypted)" >&2
  exit 2
fi

if (( encrypt )); then
  if [[ -z ${STATICRYPT_PASSWORD-} ]]; then
    [[ -t 0 ]] || { echo "--password needs STATICRYPT_PASSWORD set, or a terminal to ask in" >&2; exit 2; }
    read -rsp "Password for $slug: " STATICRYPT_PASSWORD
    echo
    [[ -n $STATICRYPT_PASSWORD ]] || { echo "empty password" >&2; exit 2; }
  fi
  (( ${#STATICRYPT_PASSWORD} >= 14 )) ||
    echo "note: the password is under 14 characters; the encrypted file is public, so it can be guessed offline" >&2

  # StatiCrypt reads its paths relative to the working directory (it prefixes
  # "./"), so it runs inside $tmp with a copy of the shared salt file.
  salt_args=()
  if [[ -f $here/.staticrypt.json ]]; then
    cp "$here/.staticrypt.json" "$tmp/.staticrypt.json"
  else
    salt_args=(-s "$(openssl rand -hex 16)")
  fi

  (cd "$tmp" && STATICRYPT_PASSWORD=$STATICRYPT_PASSWORD npx --yes staticrypt@3.5.4 index.html \
    -d enc -c .staticrypt.json ${salt_args[@]+"${salt_args[@]}"} --short --remember 30 \
    --template-title "Protected page" --template-color-primary "#c8613f" --template-color-secondary "#faf9f5" >/dev/null)
  cp "$tmp/.staticrypt.json" "$here/.staticrypt.json"
  normalize "$tmp/enc/index.html" "$here/$slug/index.html"
else
  cp "$tmp/index.html" "$here/$slug/index.html"
fi

cd "$here"
git add "$slug/index.html"
if (( encrypt )); then git add .staticrypt.json; fi
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
