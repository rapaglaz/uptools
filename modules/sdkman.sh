#!/usr/bin/env bash

sdkman_update() {
  local mode="${1:-check}"
  local sdkman_init="${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
  # SDKMAN is not a binary — it is a shell function loaded by its init script.
  # If the init script is missing, SDKMAN is not installed.
  if [[ ! -f "$sdkman_init" ]]; then
    echo -e "${YELLOW}[ SKIP ] SDKMAN!${RESET}: not installed, skipping"
    return 0
  fi
  print_section "SDKMAN!"
  # SDKMAN's scripts reference variables that may be unset (e.g. $2, ZSH_VERSION).
  # A subshell isolates set+u so the parent's strict mode is never disrupted.
  local _sdk_exit
  (
    set +u
    # shellcheck source=/dev/null
    source "$sdkman_init"
    if [[ "$mode" == "update" ]]; then
      # Update SDKMAN itself, refresh the candidate list, then upgrade all installed SDKs.
      sdk update && sdk upgrade
    else
      # In check mode, sdk upgrade lists outdated candidates without installing.
      sdk upgrade
    fi
  )
  _sdk_exit=$?
  ((_sdk_exit != 0)) && handle_error "SDKMAN!" "sdk command failed (exit ${_sdk_exit})"
}

# Used by "uptools show"; SDKMAN is a shell function, not a binary in PATH
sdkman_installed() {
  [[ -f "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh" ]]
}

register_tool "sdkman" "sdkman_update" "update SDKMAN! and managed SDKs"
