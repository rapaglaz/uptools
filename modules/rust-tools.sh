#!/usr/bin/env bash

RUST_TOOLS_CONFIG="${UPTOOLS_CONFIG_DIR}/rust-tools"

# Crate names to track, one per line (# for comments)
_rust_tools_load() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//[[:space:]]/}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done <"$RUST_TOOLS_CONFIG"
}

# Latest non-yanked, non-prerelease version from the crates.io sparse index
_rust_tools_latest() {
  local name="${1,,}" path
  case ${#name} in
  1) path="1/${name}" ;;
  2) path="2/${name}" ;;
  3) path="3/${name:0:1}/${name}" ;;
  *) path="${name:0:2}/${name:2:2}/${name}" ;;
  esac
  curl -s --max-time 30 "https://index.crates.io/${path}" 2>/dev/null |
    grep -v '"yanked":true' | grep -o '"vers":"[0-9][0-9.]*"' | tail -1 | grep -o '[0-9][0-9.]*'
}

# Compare one crate with crates.io; records state files in tmpdir
_rust_tools_check() {
  local crate="$1" tmpdir="$2" installed_list="$3"
  local installed latest
  installed=$(sed -n -E "s/^${crate//./\\.} v([0-9][^[:space:]:]*).*/\1/p" <<<"$installed_list" | head -1)
  if [[ -z "$installed" ]]; then
    echo -e "${RED}✗ $crate — not installed${RESET}"
    touch "$tmpdir/$crate.missing"
    return
  fi
  latest=$(_rust_tools_latest "$crate")
  if [[ -z "$latest" ]]; then
    echo "$crate $installed (crates.io unreachable or unknown crate)"
    return
  fi
  if [[ "$installed" == "$latest" ]]; then
    echo -e "${GREEN}$crate $installed${RESET}"
  else
    echo -e "${BOLD_MAGENTA}$crate $installed -> $latest${RESET}"
    touch "$tmpdir/$crate.outdated"
  fi
}

rust_tools_update() {
  local mode="${1:-check}"

  if [[ ! -f "$RUST_TOOLS_CONFIG" ]]; then
    echo -e "\n${YELLOW}[ SKIP ] rust-tools${RESET}: no crate list at '$RUST_TOOLS_CONFIG', skipping"
    return 0
  fi
  command_exists "cargo" "rust-tools" || return 0

  local crates=() crate
  mapfile -t crates < <(_rust_tools_load)
  [[ ${#crates[@]} -eq 0 ]] && return 0

  print_section "Rust tools"

  local installed_list tmpdir
  installed_list=$(cargo install --list 2>/dev/null)
  tmpdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$tmpdir'" RETURN

  for crate in "${crates[@]}"; do
    _rust_tools_check "$crate" "$tmpdir" "$installed_list" >"$tmpdir/$crate.out" &
  done
  wait

  for crate in "${crates[@]}"; do
    cat "$tmpdir/$crate.out"
  done

  [[ "$mode" != "update" ]] && return 0

  for crate in "${crates[@]}"; do
    if [[ -f "$tmpdir/$crate.missing" || -f "$tmpdir/$crate.outdated" ]]; then
      echo
      run_with_check "RUST-TOOLS" cargo install "$crate" --locked
    fi
  done
}

# Used by "uptools show"; the tools are installed with cargo
rust_tools_installed() {
  command -v cargo >/dev/null 2>&1
}

register_tool "rust-tools" "rust_tools_update" "update Rust crates installed with cargo, listed in the rust-tools file"
