#!/usr/bin/env bash

HASKELL_TOOLS_CONFIG="${UPTOOLS_HOME:-${SCRIPT_DIR:-$HOME/.uptools}}/haskell-tools"

_haskell_tools_load() {
  local line tools=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//[[:space:]]/}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    tools+=("$line")
  done <"$HASKELL_TOOLS_CONFIG"
  printf '%s\n' "${tools[@]}"
}

_haskell_tools_check() {
  local tool="$1" tmpdir="$2"
  local installed latest
  installed=$("$tool" --version 2>&1 | grep -o '[0-9][0-9.]*' | head -1)
  if [[ -z "$installed" ]]; then
    echo -e "${RED}✗ $tool — not found in PATH${RESET}"
    touch "$tmpdir/$tool.missing"
    return
  fi
  latest=$(curl -s --max-time 30 "https://hackage.haskell.org/package/$tool/preferred.json" 2>/dev/null |
    grep -o '"normal-version":\["[^"]*' | grep -o '[0-9][0-9.]*' | head -1)
  if [[ -z "$latest" ]]; then
    echo "$tool $installed (Hackage unreachable)"
    return
  fi
  if [[ "$installed" == "$latest" ]]; then
    echo -e "${GREEN}$tool $installed${RESET}"
  else
    echo -e "${BOLD_MAGENTA}$tool $installed -> $latest${RESET}"
    echo "$installed $latest" >"$tmpdir/$tool.outdated"
  fi
}

haskell_tools_update() {
  local mode="${1:-check}"

  if [[ ! -f "$HASKELL_TOOLS_CONFIG" ]]; then
    echo -e "\n${YELLOW}[ SKIP ] haskell-tools${RESET}: no tool list at '$HASKELL_TOOLS_CONFIG', skipping"
    return 0
  fi
  local tools=() tool
  mapfile -t tools < <(_haskell_tools_load)
  [[ ${#tools[@]} -eq 0 ]] && return 0

  print_section "Haskell tools"

  local tmpdir
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  for tool in "${tools[@]}"; do
    _haskell_tools_check "$tool" "$tmpdir" >"$tmpdir/$tool.out" &
  done
  wait

  for tool in "${tools[@]}"; do
    cat "$tmpdir/$tool.out"
  done

  [[ "$mode" != "update" ]] && return 0

  local outdated=() missing=()
  for tool in "${tools[@]}"; do
    [[ -f "$tmpdir/$tool.outdated" ]] && outdated+=("$tool")
    [[ -f "$tmpdir/$tool.missing" ]] && missing+=("$tool")
  done

  [[ ${#outdated[@]} -eq 0 && ${#missing[@]} -eq 0 ]] && return 0

  if ! command -v cabal >/dev/null 2>&1; then
    handle_error "HASKELL-TOOLS" "'cabal' not found — cannot install or update tools"
    return 1
  fi

  [[ ${#outdated[@]} -gt 0 ]] && { run_with_check "HASKELL-TOOLS" cabal update || return 1; }

  for tool in "${missing[@]}" "${outdated[@]}"; do
    echo
    run_with_check "HASKELL-TOOLS" cabal install "$tool" --overwrite-policy=always
  done
}

# Used by "uptools show"; the tools are installed with cabal
haskell_tools_installed() {
  command -v cabal >/dev/null 2>&1
}

register_tool "haskell-tools" "haskell_tools_update" "update Haskell cabal tools listed in the haskell-tools file"
