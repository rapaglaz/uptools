#!/usr/bin/env bash

mise_update() {
  local mode="${1:-check}"
  if command_exists "mise" "Mise"; then
    print_section "Mise"
    if [[ "$mode" == "update" ]]; then
      local mise_path
      mise_path="$(command -v mise)"
      if [[ "$mise_path" == "$HOME/.local/bin/mise" ]]; then
        run_with_check "MISE" mise self-update
        printf "\n"
      fi
      run_with_check "MISE" mise upgrade
    else
      run_with_check "MISE" mise outdated
    fi
  fi
}

register_tool "mise" "mise_update" "update Mise tool versions"
