#!/usr/bin/env bash

__stack_create_pr_list_from_stack() {
  local stack_number="$1"
  gh_api "/repos/:owner/:repo/stacks/$stack_number" | jq -r '.pull_requests.[].number'
}

# Get the stack and navigate closest to trunk
# gh stack checkout 1234 will checkout the stack if 1234 is just a PR number
# So we could find out the stack associated with this PR by
# gh_api /repos/:owner/:repo/pulls/2136 | jq '.select(.stack != null) | .stack.number'
# And that becomes the stack number we work with.
__stack_checkout_stack() {
  local stack_number="$1"
  local stack_up_msg=""

  if is_stack_open "$stack_number"; then
    gh stack checkout "$stack_number"
    gh stack bottom
    # Can't rebase unless you have checked out each stack PR
    # since it will try to use git under the covers.
    while [[ "$stack_up_msg" != "Already at the top of the stack" ]]; do
      stack_up_msg="$(gh stack up 2>&1)"
    done
    gh stack rebase
    gh stack push
    return 0
  else
    return 1
  fi
}

gh_is_stack_open() {
  local info="$1"
  local open
  open="$(echo "$info" | jq -r '.open')"
  if [[ "$open" == "true" ]]; then
    return 0
  else
    return 1
  fi
}

gh_stack_info() {
  local stack_number="$1"
  gh_api "/repos/:owner/:repo/stacks/$stack_number"
}

gh_stack_get_stack_num() {
  local url="$1"
  local stack_num
  local url_re='^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)/?$'
  local number_re='^[0-9]+$'
  local name_with_owner
  local local_repo
  local pr_number

  # If we are not in a repo, then we can never succeed since stack work
  # requires us to do eventually do a gh stack rebase.
  if gh_is_repo; then
    local_repo="$(gh_repo_info)"
    if [[ $url =~ $url_re ]]; then
      name_with_owner="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
      pr_number="${BASH_REMATCH[3]}"
    elif [[ $url =~ $number_re ]]; then
      pr_number="$url"
      name_with_owner="$local_repo"
    fi
    # If we are in the same repo, then we could be in a stack, so lets check that.
    if [[ "$name_with_owner" == "$local_repo" ]]; then
      stack_num="$(gh_api "/repos/$name_with_owner/pulls/$pr_number" | jq -r 'select(.stack != null) | .stack.number')"
    fi
    if [[ -n "$stack_num" ]]; then
      echo "$stack_num"
    else
      echo ""
    fi
  else
    echo ""
  fi
}

stack_merge() {
  local stack_num="$1"
  local prs_in_stack=()
  local pr
  local first="true"
  local stack_info

  stack_info="$(gh_stack_info "$stack_num")"
  if gh_is_stack_open "$stack_info"; then
    __stack_checkout_stack "$stack_num"
    mapfile -t prs_in_stack < <(__stack_create_pr_list_from_stack "$stack_num")
    for pr in "${prs_in_stack[@]}"; do
      url="$(gh_pr_view_field url "$pr")"
      if [[ $(gh_pr_view_field state "$pr") == "MERGED" ]]; then
        echo "ℹ️ Skipping $url already merged"
        first="false"
        continue
      fi
      if [[ "$first" != "true" ]]; then
        wait_quietly "💤..."
      fi
      first="false"
      echo "ℹ️ Working on $url"
      __label_if_bot "$pr"
      gh_wait_for_checks "$pr"
      gh_approve_then_merge "$pr" "true"
    done
  else
    echo "🔎 stack#$stack_num is not open (all PRs merged?); skipping"
  fi
}
