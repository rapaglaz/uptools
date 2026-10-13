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
      run_with_check "APT" "${sudo_cmd[@]}" apt upgrade -y || return 1
      # apt upgrade never removes packages; whatever is still upgradable was kept back
      local kept_back
      kept_back=$(env APT_PAGER=cat apt list --upgradable 2>/dev/null | grep -c '/')
      if ((kept_back > 0)); then
        echo -e "${YELLOW}${kept_back} package(s) kept back; review with 'apt list --upgradable' and run 'sudo apt full-upgrade' if the removals are acceptable${RESET}"
      fi
    else
      # No refresh here: it needs root. The list reflects the last 'apt update'.
      # apt >= 3.0 pipes its output through $PAGER on a terminal; keep it inline
      local upgradable
      upgradable=$(env APT_PAGER=cat apt list --upgradable 2>/dev/null) || {
        handle_error "APT" "Command failed: apt list --upgradable"
        return 1
      }
      upgradable=$(grep '/' <<<"$upgradable")
      if [[ -n "$upgradable" ]]; then
        echo -e "${BOLD_WHITE}Packages to upgrade:${RESET}"
        echo "$upgradable"
      else
        echo "All APT packages are up to date"
      fi
    fi
  fi
}

register_tool "apt" "apt_update" "update APT packages"
