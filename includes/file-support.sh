#!/usr/bin/env bash

__fs_delete_entry() {
  local file="$1"
  local entry="$2"

  sed -i "s#^$entry\$##g" "$file"
  __fs_delete_blank_lines "$file"
}

__fs_delete_blank_lines() {
  sed -i '/^$/d' "$file"
}

process_entries_in() {
  local file="$1"
  local entry=""
  local first="true"

  __fs_delete_blank_lines "$file"
  entry="$(head -n1 "$file")"
  while [[ "$entry" != "" ]]; do
    if [[ "$first" != "true" ]]; then
      wait_quietly "💤..."
    fi
    first=false
    stack_or_merge "$entry"
    __fs_delete_entry "$file" "$entry"
    entry="$(head -n1 "$file")"
  done
  # Delete empty files after processing.
  # Edge case being that if the file was always empty, then it just gets deleted.
  # I find this acceptable.
  if [[ ! -s "$file" ]]; then
    rm -f "$file"
  fi
}
