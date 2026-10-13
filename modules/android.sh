#!/usr/bin/env bash

# Seconds to wait for the SDK repository before giving up; it is unreachable from time to time.
_ANDROID_NETWORK_TIMEOUT=10

# Runs "$2..." and kills it after $1 seconds; returns 124 on timeout, like GNU timeout.
# Pure bash because macOS ships neither timeout nor gtimeout.
_android_with_timeout() {
  local secs="$1" pid watchdog rc=0
  shift
  "$@" &
  pid=$!
  (
    trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM
    sleep "$secs" &
    sleeper=$!
    wait "$sleeper" || exit 0
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid" || rc=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  if ((rc == 143)); then
    rc=124
  fi
  return "$rc"
}

# Prints "installed|available <package-path>" lines for the `android sdk list --all` output on stdin.
_android_list_packages() {
  awk '
    /^Installed packages:/ { state = "installed"; next }
    /^Available packages:/ { state = "available"; next }
    state && NF { print state, $1 }
  '
}

# Prints the newest stable package matching the extended regex $1 among the lines on stdin.
_android_latest() {
  grep -E "$1" | sort -V | tail -1
}

# Prints SDK packages that are not installed yet but are newer than what is installed:
# latest stable platform, latest build-tools, and newest system image per installed image variant.
# $1 is the output of `android sdk list --all`.
_android_new_packages() {
  local packages installed available
  packages=$(_android_list_packages <<<"$1")
  installed=$(awk '$1 == "installed" { print $2 }' <<<"$packages")
  available=$(awk '$1 == "available" { print $2 }' <<<"$packages")

  local platform_re='^platforms/android-[0-9]+(\.[0-9]+)?$'
  local tools_re='^build-tools/[0-9]+\.[0-9]+\.[0-9]+$'
  local candidates=() latest

  if grep -qE "$platform_re" <<<"$installed"; then
    latest=$(grep -E "$platform_re" <<<"$available" | sort -V | tail -1)
    [[ -n "$latest" ]] && candidates+=("$latest")
  fi

  if grep -qE "$tools_re" <<<"$installed"; then
    latest=$(grep -E "$tools_re" <<<"$available" | sort -V | tail -1)
    [[ -n "$latest" ]] && candidates+=("$latest")
  fi

  # system-images/android-<api>/<variant>/<abi> — keep variant and abi, bump the api level
  local image variant
  while IFS= read -r image; do
    [[ -z "$image" ]] && continue
    variant="${image#system-images/*/}"
    latest=$(grep -E "^system-images/android-[0-9]+(\.[0-9]+)?/${variant}$" <<<"$available" | sort -V | tail -1)
    [[ -n "$latest" ]] && candidates+=("$latest")
  done < <(grep -E '^system-images/' <<<"$installed")

  local pkg
  for pkg in "${candidates[@]}"; do
    grep -qxF "$pkg" <<<"$installed" || echo "$pkg"
  done | sort -u
}

android_update() {
  local mode="${1:-check}"
  command_exists "android" "Android CLI" || return 0
  print_section "Android CLI"

  if [[ "$mode" == "update" ]]; then
    # android-cli has no check-only mode for itself, so it is only updated here
    run_with_check "ANDROID" android update || return 1
    run_with_check "ANDROID" android sdk update || return 1
  else
    run_with_check "ANDROID" android --version || return 1
    echo
  fi

  local listing rc=0
  listing=$(_android_with_timeout "$_ANDROID_NETWORK_TIMEOUT" android sdk list --all 2>&1) || rc=$?
  if ((rc != 0)); then
    if ((rc == 124)); then
      handle_error "ANDROID" "SDK repository did not answer within ${_ANDROID_NETWORK_TIMEOUT}s"
    else
      handle_error "ANDROID" "Cannot list SDK packages: ${listing:-no output}"
    fi
    return 1
  fi

  local new_packages=() pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && new_packages+=("$pkg")
  done < <(_android_new_packages "$listing")

  if [[ ${#new_packages[@]} -eq 0 ]]; then
    [[ "$mode" != "update" ]] && { run_with_check "ANDROID" _android_with_timeout "$_ANDROID_NETWORK_TIMEOUT" android sdk list || return 1; }
    echo "No newer SDK platform, build-tools or system image available"
    return 0
  fi

  if [[ "$mode" == "update" ]]; then
    for pkg in "${new_packages[@]}"; do
      echo
      run_with_check "ANDROID" android sdk install "$pkg"
    done
  else
    run_with_check "ANDROID" _android_with_timeout "$_ANDROID_NETWORK_TIMEOUT" android sdk list || return 1
    echo
    echo -e "${BOLD_MAGENTA}New SDK packages available (install with: uptools update android):${RESET}"
    printf '  %s\n' "${new_packages[@]}"
  fi
}

register_tool "android" "android_update" "update Android CLI and install newer SDK packages"
