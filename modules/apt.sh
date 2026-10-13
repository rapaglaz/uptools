#!/usr/bin/env bash

apt_update() {
  local mode="${1:-check}"
  if command_exists "apt" "APT"; then
    print_section "APT"
    if [[ "$mode" == "update" ]]; then
      local -a sudo_cmd=()
      if ((EUID != 0)); then
        command_exists "sudo" "sudo (required by apt module)" || return 1
        sudo_cmd=(sudo)
      fi
      run_with_check "APT" "${sudo_cmd[@]}" apt update || return 1
      run_with_check "APT" "${sudo_cmd[@]}" apt upgrade -y
    else
      # No refresh here: it needs root. The list reflects the last 'apt update'.
      run_with_check "APT" apt list --upgradable
    fi
  fi
}

register_tool "apt" "apt_update" "update APT packages"
