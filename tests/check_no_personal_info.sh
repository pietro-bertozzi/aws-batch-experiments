#!/usr/bin/env bash
# Fails if a tracked file contains an email address (other than placeholders), or, with
# --author, if the git author email is not a GitHub noreply address.
# Used by CI (files only); run it with --author before committing to check the author too.
# Usage: tests/check_no_personal_info.sh [--author]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

status=0
allowed='@(example\.(com|org)|users\.noreply\.github\.com)$|^noreply@'

while IFS= read -r hit; do
  addr="${hit##*:}"
  if ! grep -qE "$allowed" <<<"$addr"; then
    echo "personal info? email address in tracked file: $hit" >&2
    status=1
  fi
done < <(git ls-files -z | xargs -0 grep -IHoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' 2>/dev/null || true)

if [ "${1:-}" = "--author" ]; then
  ident="$(git var GIT_AUTHOR_IDENT)"
  email="${ident#*<}"
  email="${email%%>*}"
  if ! grep -qE '@users\.noreply\.github\.com$' <<<"$email"; then
    echo "git author email is not a GitHub noreply address; it would be public in the history." >&2
    echo "fix: git config user.email '<id>+<username>@users.noreply.github.com'" >&2
    status=1
  fi
fi
exit "$status"
