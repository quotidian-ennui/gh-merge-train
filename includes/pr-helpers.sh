#!/usr/bin/env bash

gh_pr_by_dependabot() {
  local pr_number=$1
  local is_dependabot=""
  is_dependabot=$(gh pr view "$pr_number" --json "author" --jq ".author.login")
  if [[ "$is_dependabot" == "app/dependabot" ]]; then
    return 0
  else
    return 1
  fi
}

gh_pr_view_field() {
  local field="$1"
  local pr_number="$2"
  gh pr view "$pr_number" --json "$field" --jq ".$field"
}

gh_pr_is_draft() {
  gh_pr_view_field "isDraft" "$1"
}

gh_approve_then_merge() {
  local pr_number="$1"
  local async_mode="${2:-false}"
  local squash_merge_args=()

  __approve_if_not_author "$pr_number"
  squash_merge_args+=("$(__bot_squash_merge_param "$pr_number")")
  if [[ "$async_mode" == "true" ]]; then
    squash_merge_args+=("--async")
  fi
  gh squash-merge "$pr_number" "${squash_merge_args[@]}"
}

__checks_pending() {
  local pr_number="$1"
  local error_file=""
  local result=0
  local retry_interval_secs=5

  error_file=$(mktemp)
  while true; do
    if gh pr checks "$pr_number" --json name,bucket >/dev/null 2>"$error_file"; then
      rm -f "$error_file"
      return 0
    else
      result=$?
    fi
    if [[ "$result" -eq 1 ]] && grep -Fq "no checks reported" "$error_file"; then
      echo "💤 ... no checks reported yet; retrying in ${retry_interval_secs}s"
      sleep "$retry_interval_secs"
    else
      cat "$error_file" >&2
      rm -f "$error_file"
      return "$result"
    fi
  done
}

gh_wait_for_checks() {
  local pr_number="$1"

  echo "🔎 ... waiting for checks to complete using gh pr checks"
  __checks_pending "$pr_number" || return $?
  gh pr checks "$pr_number" --watch --fail-fast --interval "$POLL_INTERVAL_SECS"
}

__is_valid_label() {
  local pr_number="$1"
  local label_to_find="$2"
  local found_label=""
  local repo=""
  local alt_repo_args=()

  if [[ "$pr_number" =~ http* ]]; then
    ## github URL, so strip it out.
    repo="${pr_number##https://github.com/}"
    repo="${repo%%/pull*}"
    alt_repo_args+=("--repo")
    alt_repo_args+=("$repo")
  fi
  found_label=$(gh label list "${alt_repo_args[@]}" --json "name" | jq -r --arg label "$label_to_find" -c '.[] | select (.name == $label) | .name')
  if [[ "$found_label" == "$label_to_find" ]]; then
    return 0
  fi
  echo "🏷️ label $label_to_find not found in repo for $pr_number"
  return 1
}

__label_if_bot() {
  local pr_number=$1
  if [[ -n "$GH_MERGE_TRAIN_BOT_LABEL" ]]; then
    if __is_valid_label "$pr_number" "$GH_MERGE_TRAIN_BOT_LABEL"; then
      if __is_bot "$pr_number"; then
        echo "ℹ️ Applying label $GH_MERGE_TRAIN_BOT_LABEL"
        gh pr edit "$pr_number" --add-label "$GH_MERGE_TRAIN_BOT_LABEL"
        # If there are skipped jobs, then labelling may start them, so give it a chance.
        __wait_if_skipped_jobs "$pr_number"
      fi
    fi
  fi
}

__approve_if_not_author() {
  local pr_number="$1"
  local pr_author=""
  local me=""

  me=$(gh_whoami)
  pr_author="$(gh pr view "$pr_number" --json "author" | jq -r '.author.login')"
  echo "ℹ️ PR Authored by $pr_author"
  if [[ "$me" != "$pr_author" ]]; then
    if ! gh pr review --approve "$pr_number"; then
      echo "⚠️ Failed to approve, this might not matter. If it does then gh squash-merge should break..."
    fi
  else
    echo "👀 Not going to try and approve your own PR!"
  fi
}

__wait_if_skipped_jobs() {
  local pr_number=$1
  local skipped_jobs=0
  skipped_jobs=$(gh pr checks "$pr_number" --json "name,state" | jq -r -c '.[] | select (.state == "SKIPPED") | .name' | wc -l)
  if [[ "$skipped_jobs" -gt 0 ]]; then
    wait_quietly "💤 ... Waiting for skipped jobs to potentially fire"
  fi
}

__extract_squash_merge_message() {
  local pr_number=$1
  local body=""
  local message=""

  body=$(gh pr view "$pr_number" --json "body" --jq ".body")

  # Check if both markers exist before extraction
  if echo "$body" | grep -q "SQUASH_MERGE_START" && echo "$body" | grep -q "SQUASH_MERGE_END"; then
    # Extract content between markers, excluding the exact marker lines (HTML comments)
    message=$(echo "$body" | awk '/SQUASH_MERGE_START/,/SQUASH_MERGE_END/' | grep -Ev "<!--[[:space:]]*SQUASH_MERGE_(START|END)[[:space:]]*-->")
  fi

  echo "$message"
}

__bot_squash_merge_param() {
  local pr_number=$1
  if __is_bot "$pr_number"; then
    local squash_message=""
    local trimmed=""
    squash_message=$(__extract_squash_merge_message "$pr_number")
    trimmed=$(echo "$squash_message" | tr -d '[:space:]')

    # If there's a viable squash-merge message (non-empty after trimming all whitespace), don't use default message
    if [[ -n "$trimmed" ]]; then
      echo ""
    else
      echo "--use-default-msg"
    fi
  else
    echo ""
  fi
}

__is_bot() {
  local pr_number=$1
  local is_bot="false"
  is_bot=$(gh pr view "$pr_number" --json "author" --jq ".author.is_bot")
  if [[ "$is_bot" == "true" ]]; then
    return 0
  else
    return 1
  fi
}
