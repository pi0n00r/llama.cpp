#!/usr/bin/env sh
# AI-NOTICE:Schema-Version=0.1
# AI-NOTICE:License=MIT
# AI-NOTICE:Project=llama.cpp-pi0n00r
# AI-NOTICE:Repository=https://github.com/pi0n00r/llama.cpp

set -eu
umask 022

repo=${LLAMA_REPO:-https://github.com/pi0n00r/llama.cpp.git}
branch=${LLAMA_BRANCH:-master}
lock_file=${LLAMA_SOURCE_LOCK:-llama-source.lock}

case "$repo" in
  *[!A-Za-z0-9:/._@+-]*|'')
    printf 'ERROR: invalid LLAMA_REPO: %s\n' "$repo" >&2
    exit 2
    ;;
esac

case "$branch" in
  *[!A-Za-z0-9._/-]*|'')
    printf 'ERROR: invalid LLAMA_BRANCH: %s\n' "$branch" >&2
    exit 2
    ;;
esac

revision=$(
  git ls-remote --exit-code --refs "$repo" "refs/heads/$branch" |
    awk 'NR == 1 { print $1 }'
)

case "$revision" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *)
    printf 'ERROR: could not resolve %s at refs/heads/%s\n' "$repo" "$branch" >&2
    exit 1
    ;;
esac

tmp=${lock_file}.tmp.$$
trap 'unlink "$tmp" 2>/dev/null || true' EXIT HUP INT TERM
{
  printf 'LLAMA_REPO=%s\n' "$repo"
  printf 'LLAMA_BRANCH=%s\n' "$branch"
  printf 'LLAMA_VERSION=%s\n' "$revision"
} > "$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$lock_file"
trap - EXIT HUP INT TERM

# These values are assignment-safe because the repository, branch and revision
# alphabets are validated above.
printf 'LLAMA_REPO=%s\n' "$repo"
printf 'LLAMA_VERSION=%s\n' "$revision"
