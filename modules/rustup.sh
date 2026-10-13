#!/usr/bin/env bash

rustup_update() {
  local mode="${1:-check}"
  if command_exists "rustup" "Rustup"; then
    print_section "Rustup"
    if [[ "$mode" == "update" ]]; then
      run_with_check "RUSTUP" rustup update
    else
      rustup check
    fi
  fi
}

register_tool "rustup" "rustup_update" "update Rust toolchains via rustup"
