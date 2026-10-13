#!/usr/bin/env bash

flutter_update() {
  local mode="${1:-check}"
  if command_exists "flutter" "Flutter"; then
    print_section "Flutter"
    if [[ "$mode" == "update" ]]; then
      run_with_check "FLUTTER" flutter upgrade && run_with_check "FLUTTER" flutter doctor
    else
      run_with_check "FLUTTER" flutter upgrade --verify-only
    fi
  fi
}

register_tool "flutter" "flutter_update" "update Flutter SDK"
