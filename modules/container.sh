#!/usr/bin/env bash

container_update() {
  local mode="${1:-check}"
  if command_exists "container" "container (Apple)"; then
    print_section "container (Apple)"
    if [[ "$mode" == "update" ]]; then
      local was_running=false
      if launchctl list 2>/dev/null | grep -qE '^[0-9-]+[[:space:]]+[0-9-]+[[:space:]]+com\.apple\.container$'; then
        was_running=true
        run_with_check "CONTAINER" container system stop || return 1
      fi
      if [[ ! -x /usr/local/bin/update-container.sh ]]; then
        handle_error "CONTAINER" "Update script not found: /usr/local/bin/update-container.sh"
        return 1
      fi
      run_with_check "CONTAINER" /usr/local/bin/update-container.sh
      if [[ "$was_running" == true ]]; then
        run_with_check "CONTAINER" container system start
      fi
    else
      local current latest
      current=$(container --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1) || current=""
      if [[ -z "$current" ]]; then
        handle_error "CONTAINER" "Could not determine installed container version"
        return 1
      fi
      latest=$(curl -fsSL --max-time 10 "https://api.github.com/repos/apple/container/releases/latest" |
        jq -r '.tag_name | ltrimstr("v")' 2>/dev/null) || latest=""
      if [[ -z "$latest" ]]; then
        handle_error "CONTAINER" "Could not fetch latest container version from GitHub"
        return 1
      fi
      if [[ "$current" == "$latest" ]]; then
        echo -e "container is up to date (${GREEN}${current}${RESET})"
      else
        echo -e "${BOLD_WHITE}Update available:${RESET} ${current} → ${GREEN}${latest}${RESET}"
      fi
    fi
  fi
}

register_tool "container" "container_update" "update Apple container tool"
