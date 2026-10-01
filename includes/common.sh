#!/usr/bin/env bash

GH_REST_API_VERSION="X-GitHub-Api-Version: 2022-11-28"
GH_ACCEPT="Accept: application/vnd.github+json"

wait_quietly() {
  local msg="$1"
  echo -e "$msg"
  sleep "$POLL_INTERVAL_SECS"
}

gh_api() {
  gh api -H "$GH_REST_API_VERSION" -H "$GH_ACCEPT" "$@"
}

# Because I often just use GH_TOKEN, and don't have 'gh config get user' available.
# This is _weak_ but it will work for my purposes.
gh_whoami() {
  local me=""
  me=$(gh config get user -h github.com 2>/dev/null || true)
  if [[ -z "$me" ]]; then
    me=$(gh auth status -h github.com | grep "Logged in" | sed -e "s/^[[:blank:]]*//" -e "s/[[:blank:]]*$//" | cut -f7 -d ' ')
  fi
  echo "$me"
}

gh_is_repo() {
  if ! gh repo view --json "name" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

gh_repo_info() {
  gh repo view --json "name,owner" | jq -r '"\(.owner.login)/\(.name)"'
}
