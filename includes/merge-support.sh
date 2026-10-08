#!/usr/bin/env bash

# Selects failed jobs from the status_rollup with some dodgy capturing
# output to be {"runId":"24521981319","jobId":"71682061689"}
readonly JQ_FAILED_JOBS='.[] | select ( .conclusion=="FAILURE" ) | .detailsUrl | capture("/runs/(?<runId>[0-9]+)/job/(?<jobId>[0-9]+)")'

merge_train() {
  local pr="$1"
  local url
  local isDraft=""

  url="$(gh_pr_view_field url "$pr")"
  if [[ $(gh_pr_view_field state "$pr") == "MERGED" ]]; then
    echo "ℹ️ Skipping $url already merged"
    return 0
  fi
  echo "ℹ️ Working on $url"
  isDraft="$(gh_pr_is_draft "$pr")"
  if [[ "$isDraft" != "true" ]]; then
    __label_if_bot "$pr"
    if [[ ! $(__merge_support_merge_status "$pr") =~ ^(CLEAN|BLOCKED)$ ]]; then
      if ! __merge_support_update_branch "$pr"; then
        echo "⚠️ last attempt to merge"
        if ! __merge_support_update_branch "$pr" "true"; then
          return 1
        fi
      fi
      # sad but sometimes the checks don't start quick enough
      wait_quietly "💤... Waiting for checks to fire."
    fi
    if [[ "$GH_MERGE_TRAIN_RETRY_FAILED_JOBS" == "true" ]]; then
      __merge_support_wait_with_retry "$pr"
    else
      gh_wait_for_checks "$pr"
    fi
    gh_approve_then_merge "$pr"
  else
    echo "🔎 $pr is a DRAFT; skip"
  fi
}

__merge_support_dependabot_commenter() {
  local pr_number="$1"
  local max_retries=$GH_MERGE_TRAIN_MAX_ATTEMPTS
  local dependabot_comment="@dependabot rebase"

  if [[ "$GH_MERGE_TRAIN_DEPENDABOT_RECREATE" == "true" ]]; then
    dependabot_comment="@dependabot recreate"
  fi
  echo "ℹ️ Update branch using $dependabot_comment"
  if ! gh pr comment "$pr_number" --body "$dependabot_comment"; then
    echo "⚠️ Failed to rebase via comment $dependabot_comment"
    return 1
  fi
  while [[ ! $(__merge_support_merge_status "$pr_number") =~ ^(CLEAN|BLOCKED)$ ]]; do
    updateCount=$((updateCount + 1))
    if [[ "$updateCount" -ge "$max_retries" ]]; then
      echo -e "\n🚫 Branch update failed too many times"
      return 1
    else
      wait_quietly "💤 Waiting on dependabot to catch up, $POLL_INTERVAL_SECS seconds..."
    fi
  done
  return 0
}

__merge_support_merge_status() {
  local pr_number=$1
  gh_pr_view_field mergeStateStatus "$pr_number"
}

__merge_support_update_branch() {
  local pr_number="$1"
  local force_use_merge="$2"
  local updateCount=0
  local update_args=()
  local max_retries="$GH_MERGE_TRAIN_MAX_ATTEMPTS"

  if [[ "$force_use_merge" == "true" ]]; then
    max_retries=1
  fi
  if [[ "$force_use_merge" != "true" && ("$GH_MERGE_TRAIN_DEPENDABOT_REBASE" == "true" || "$GH_MERGE_TRAIN_DEPENDABOT_RECREATE" == "true") ]]; then
    if gh_pr_by_dependabot "$pr_number"; then
      if ! __merge_support_dependabot_commenter "$pr_number"; then
        return 1
      fi
      return 0
    fi
  fi

  if [[ "$GH_MERGE_TRAIN_REBASE" == "true" && "$force_use_merge" != "true" ]]; then
    update_args+=("--rebase")
  fi

  #shellcheck disable=SC2145
  echo "ℹ️ Update branch using gh pr update-branch $pr_number ${update_args[@]}"
  while ! gh pr update-branch "$pr_number" "${update_args[@]}"; do
    updateCount=$((updateCount + 1))
    if [[ "$updateCount" -ge "$max_retries" ]]; then
      echo -e "\n🚫 Branch update failed too many times"
      return 1
    else
      wait_quietly "⚠️ Update failed. Retrying in $POLL_INTERVAL_SECS seconds..."
    fi
  done
  return 0
}

# Dodgy actions, retry them once
# After that, fail. Dev should fix your damned actions!
__merge_support_wait_with_retry() {
  local pr_number="$1"

  if ! gh_wait_for_checks "$pr_number"; then
    echo "🛟 ... PR Checks had failures, retry once"
    __merge_support_retry_failed_jobs "$pr_number"
    wait_quietly "💤 ... Waiting for jobs to start"
    gh_wait_for_checks "$pr_number"
  fi
}

__merge_support_retry_failed_jobs() {
  local pr_number="$1"
  local runId
  local jobId
  local job_id_jsonlines=()

  mapfile -t job_id_jsonlines < <(gh pr view "$pr_number" --json "statusCheckRollup" --jq '.statusCheckRollup' | jq -c "$JQ_FAILED_JOBS")
  for jsonline in "${job_id_jsonlines[@]}"; do
    runId=$(echo "$jsonline" | jq -r ".runId")
    jobId=$(echo "$jsonline" | jq -r ".jobId")
    echo "🔎 ... Retry $jobId in $runId"
    gh run rerun --job "$jobId"
  done
}
