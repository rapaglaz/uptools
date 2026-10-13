#!/usr/bin/env bash

# Note: local -n (nameref) requires bash 4.3+. macOS /bin/bash is 3.2;
# this script relies on #!/usr/bin/env bash resolving to Homebrew's bash 5.x.
_homebrew_classify_casks() {
  local -n _auto_ref="$1"
  local -n _regular_ref="$2"
  local -n _cask_arr_ref="$3"

  local auto_tokens
  auto_tokens=$(brew info --cask --json=v2 "${_cask_arr_ref[@]}" 2>/dev/null |
    jq -r '.casks[] | select(.auto_updates or .version == "latest") | .token' 2>/dev/null) || auto_tokens=""

  for cask in "${_cask_arr_ref[@]}"; do
    [[ -z "$cask" ]] && continue
    if [[ -n "$auto_tokens" ]] && grep -qxF "$cask" <<<"$auto_tokens"; then
      _auto_ref+=("$cask")
    else
      _regular_ref+=("$cask")
    fi
  done
}

_homebrew_check() {
  command_exists "jq" "jq (required by homebrew module)" || return 1
  echo -e "${BOLD_WHITE}Checking for outdated packages...${RESET}"

  local _tmp_formula _tmp_cask _ret_formula _ret_cask
  _tmp_formula=$(mktemp) || {
    handle_error "HOMEBREW" "Failed to create temp file"
    return 1
  }
  _tmp_cask=$(mktemp) || {
    rm -f "$_tmp_formula"
    handle_error "HOMEBREW" "Failed to create temp file"
    return 1
  }
  trap 'rm -f "$_tmp_formula" "$_tmp_cask"; trap - RETURN' RETURN

  brew outdated --formula --quiet >"$_tmp_formula" 2>&1 &
  local _pid_formula=$!
  brew outdated --cask --greedy --quiet >"$_tmp_cask" 2>&1 &
  local _pid_cask=$!
  wait "$_pid_formula"
  _ret_formula=$?
  wait "$_pid_cask"
  _ret_cask=$?

  if ((_ret_formula != 0)); then
    handle_error "HOMEBREW" "Command failed: brew outdated --formula"
    return 1
  fi
  if ((_ret_cask != 0)); then
    handle_error "HOMEBREW" "Command failed: brew outdated --cask --greedy"
    return 1
  fi

  local -a outdated_formula_arr outdated_cask_arr
  local -a auto_updating_arr=() regular_casks_arr=()
  mapfile -t outdated_formula_arr <"$_tmp_formula"
  mapfile -t outdated_cask_arr <"$_tmp_cask"
  rm -f "$_tmp_formula" "$_tmp_cask"

  if [[ ${#outdated_cask_arr[@]} -gt 0 ]]; then
    _homebrew_classify_casks auto_updating_arr regular_casks_arr outdated_cask_arr
  fi

  if [[ ${#outdated_formula_arr[@]} -eq 0 && ${#regular_casks_arr[@]} -eq 0 && ${#auto_updating_arr[@]} -eq 0 ]]; then
    echo "All Homebrew packages are up to date"
  fi
  if [[ ${#outdated_formula_arr[@]} -gt 0 ]]; then
    echo -e "${BOLD_WHITE}Formulae to upgrade:${RESET}"
    printf "%s\n" "${outdated_formula_arr[@]}"
  fi
  if [[ ${#regular_casks_arr[@]} -gt 0 ]]; then
    echo -e "${BOLD_WHITE}Casks to upgrade:${RESET}"
    printf "%s\n" "${regular_casks_arr[@]}"
  fi
  if [[ ${#auto_updating_arr[@]} -gt 0 ]]; then
    echo -e "\n${BOLD_WHITE}Auto-updating casks (auto_updates=true / version=:latest):${RESET}"
    printf "%s\n" "${auto_updating_arr[@]}"
  fi
}

_homebrew_upgrade() {
  echo -e "${BOLD_WHITE}Upgrading all outdated Homebrew packages...${RESET}"
  brew upgrade
  local exit_code=$?
  if ((exit_code != 0)); then
    local still_outdated
    still_outdated=$(brew outdated --quiet 2>/dev/null)
    if [[ -n "$still_outdated" ]]; then
      handle_error "HOMEBREW" "Command failed: 'brew' 'upgrade'"
    fi
  fi
}

homebrew_update() {
  local mode="${1:-check}"
  if command_exists "brew" "Homebrew"; then
    print_section "Homebrew"
    brew update -q &>/dev/null || {
      handle_error "HOMEBREW" "Command failed: brew update -q"
      return 1
    }
    if [[ "$mode" == "update" ]]; then
      _homebrew_upgrade
    else
      _homebrew_check
    fi
  fi
}

# Used by "uptools show"; the binary is brew, not homebrew
homebrew_installed() {
  command -v brew >/dev/null 2>&1
}

register_tool "homebrew" "homebrew_update" "update Homebrew packages" "brew"
