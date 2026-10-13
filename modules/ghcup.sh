#!/usr/bin/env bash

# Print one "tool installed-versions target-version" line for every installed ghcup tool
# whose installed versions carry neither the "latest" nor the "recommended" tag.
# "ghcup list" only reads the (cached) metadata; it installs nothing.
_ghcup_outdated() {
  local installed_rows all_rows
  installed_rows=$(ghcup list -r -c installed 2>/dev/null) || return 1
  all_rows=$(ghcup list -r 2>/dev/null) || return 1

  local -A installed_versions=() current=() target=()
  local -a order=()
  local tool version tags
  while read -r tool version tags _; do
    [[ -z "$tool" ]] && continue
    [[ -z "${installed_versions[$tool]+set}" ]] && order+=("$tool")
    installed_versions[$tool]+="${installed_versions[$tool]:+,}${version}"
    [[ ",${tags}," == *,latest,* || ",${tags}," == *,recommended,* ]] && current[$tool]=1
  done <<<"$installed_rows"

  while read -r tool version tags _; do
    [[ -n "${installed_versions[$tool]+set}" && -z "${current[$tool]+set}" ]] || continue
    if [[ ",${tags}," == *,recommended,* ]]; then
      target[$tool]="$version"
    elif [[ ",${tags}," == *,latest,* && -z "${target[$tool]+set}" ]]; then
      target[$tool]="$version"
    fi
  done <<<"$all_rows"

  for tool in "${order[@]}"; do
    [[ -n "${current[$tool]+set}" || -z "${target[$tool]+set}" ]] && continue
    printf '%s %s %s\n' "$tool" "${installed_versions[$tool]}" "${target[$tool]}"
  done
}

ghcup_update() {
  local mode="${1:-check}"
  command_exists "ghcup" "ghcup" || return 0
  print_section "ghcup"

  local outdated line
  outdated=$(_ghcup_outdated) || {
    handle_error "GHCUP" "Command failed: ghcup list"
    return 1
  }
  if [[ -z "$outdated" ]]; then
    echo "All installed ghcup tools are up to date"
  else
    echo -e "${BOLD_WHITE}Updates available (installed -> recommended/latest):${RESET}"
    while read -r line; do
      read -r tool versions target <<<"$line"
      echo -e "${BOLD_MAGENTA}${tool} ${versions} -> ${target}${RESET}"
    done <<<"$outdated"
    echo "Install with: ghcup install <tool> <version>   (ghcup itself: uptools update ghcup)"
  fi

  # ghcup upgrade replaces ghcup itself; it never touches the installed GHC/cabal/hls/stack
  [[ "$mode" == "update" ]] && { run_with_check "GHCUP" ghcup upgrade || return 1; }
  return 0
}

register_tool "ghcup" "ghcup_update" "update Haskell toolchain manager and list tool updates"
