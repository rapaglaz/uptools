#!/usr/bin/env bash

[[ -n "${_UPTOOLS_CORE_LOADED:-}" ]] && return 0
_UPTOOLS_CORE_LOADED=1

# Allow callers (e.g. tests) that source core.sh directly without uptools
SCRIPT_EXIT_CODE="${SCRIPT_EXIT_CODE:-0}"

# Colors — disabled when NO_COLOR env var is set (https://no-color.org/)
if [[ -z "${NO_COLOR:-}" ]]; then
  BOLD_WHITE="\033[1;37m"
  RED="\033[0;31m"
  YELLOW="\033[1;33m"
  GREEN="\033[0;32m"
  BOLD_MAGENTA="\033[1;35m"
  RESET="\033[0m"
else
  BOLD_WHITE="" RED="" YELLOW="" GREEN="" BOLD_MAGENTA="" RESET=""
fi

# Error handling function
handle_error() {
  local tool_name="$1"
  local error_msg="$2"
  SCRIPT_EXIT_CODE=1
  echo >&2 -e "${RED}[ ERROR ] ${tool_name}${RESET}"
  echo >&2 -e "${error_msg}"
  return 1
}

# Check if a command exists; prints a skip warning if not found
command_exists() {
  local cmd="$1"
  local tool_name="${2:-}"

  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo -e "\n${YELLOW}[ SKIP ] ${tool_name:-$cmd}${RESET}: '$cmd' not found, skipping"
    return 1
  fi
  return 0
}

# Run a command with error checking; streams stdout and stderr live
run_with_check() {
  local label="$1"
  shift
  "$@" || handle_error "$label" "Command failed: ${*@Q}"
}

# Print section headers
print_section() {
  echo -e "\n${BOLD_WHITE}==> ${BOLD_MAGENTA}${1}${RESET}"
}
