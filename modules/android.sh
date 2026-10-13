#!/usr/bin/env bash

# Prints "installed|available <package-path>" lines for every package from `android sdk list --all`.
_android_list_packages() {
  android sdk list --all 2>/dev/null | awk '
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
_android_new_packages() {
  local packages installed available
  packages=$(_android_list_packages)
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

  local new_packages=() pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && new_packages+=("$pkg")
  done < <(_android_new_packages)

  if [[ ${#new_packages[@]} -eq 0 ]]; then
    [[ "$mode" != "update" ]] && run_with_check "ANDROID" android sdk list
    echo "No newer SDK platform, build-tools or system image available"
    return 0
  fi

  if [[ "$mode" == "update" ]]; then
    for pkg in "${new_packages[@]}"; do
      echo
      run_with_check "ANDROID" android sdk install "$pkg"
    done
  else
    run_with_check "ANDROID" android sdk list || return 1
    echo
    echo -e "${BOLD_MAGENTA}New SDK packages available (install with: uptools update android):${RESET}"
    printf '  %s\n' "${new_packages[@]}"
  fi
}

register_tool "android" "android_update" "update Android CLI and install newer SDK packages"
