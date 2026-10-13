#!/usr/bin/env bash
# Logic tests for the modules: parsing, version comparison and package selection.
# The modules are sourced and their external commands (curl, android, cargo, ...) are replaced
# by shell functions, so nothing is installed or executed. Compatible with bash >= 4.4.
#
# usage: tests/modules.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NO_COLOR=1

PASSED=0
FAILED=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# assert_eq <description> <expected> <actual>
assert_eq() {
  if [[ "$2" == "$3" ]]; then
    PASSED=$((PASSED + 1))
  else
    FAILED=$((FAILED + 1))
    printf 'FAIL: %s\n      expected: %s\n      actual:   %s\n' "$1" "${2//$'\n'/|}" "${3//$'\n'/|}"
  fi
}

# assert_file <description> <path> <present|absent>
assert_file() {
  local state=absent
  [[ -e "$2" ]] && state=present
  assert_eq "$1" "$3" "$state"
}

# The modules call register_tool when they are sourced
register_tool() { :; }

# shellcheck source=/dev/null
source "$REPO_DIR/core.sh"
for module in android rust-tools haskell-tools; do
  # shellcheck source=/dev/null
  source "$REPO_DIR/modules/$module.sh"
done

# --- android: _android_new_packages ---

SDK_LIST=""

android() {
  [[ "$*" == "sdk list --all" ]] && printf '%s\n' "$SDK_LIST"
}

SDK_LIST='Installed packages:
platforms/android-34
build-tools/34.0.0
system-images/android-34/google_apis/arm64-v8a

Available packages:
platforms/android-9
platforms/android-34
platforms/android-35
platforms/android-35-ext4
build-tools/34.0.0
build-tools/35.0.0
build-tools/36.0.0-rc1
system-images/android-34/google_apis/arm64-v8a
system-images/android-35/google_apis/arm64-v8a
system-images/android-35/google_apis_playstore/arm64-v8a'
assert_eq "android: suggests newer platform, build-tools and system image of the installed variant" \
  $'build-tools/35.0.0\nplatforms/android-35\nsystem-images/android-35/google_apis/arm64-v8a' \
  "$(_android_new_packages)"

SDK_LIST='Installed packages:
platforms/android-35
build-tools/35.0.0

Available packages:
platforms/android-34
platforms/android-35
build-tools/34.0.0
build-tools/35.0.0'
assert_eq "android: nothing to suggest when the latest is installed" "" "$(_android_new_packages)"

SDK_LIST='Installed packages:
build-tools/34.0.0

Available packages:
platforms/android-35
build-tools/35.0.0
system-images/android-35/google_apis/arm64-v8a'
assert_eq "android: does not add a platform or image the user never installed" \
  "build-tools/35.0.0" "$(_android_new_packages)"

SDK_LIST='Installed packages:
platforms/android-9

Available packages:
platforms/android-9
platforms/android-10
platforms/android-35'
assert_eq "android: compares API levels numerically" "platforms/android-35" "$(_android_new_packages)"

# --- rust-tools ---

RUST_TOOLS_CONFIG="$TMP_ROOT/rust-tools"
printf '# crates\ncargo-edit\n\n  cargo-watch  \n# cargo-nextest\n' >"$RUST_TOOLS_CONFIG"
assert_eq "rust-tools: reads crate names, skipping comments and blank lines" \
  $'cargo-edit\ncargo-watch' "$(_rust_tools_load)"

CURL_LOG="$TMP_ROOT/curl.log"
CURL_BODY=""
# The URL is the last argument; the body is whatever the test sets
curl() {
  printf '%s\n' "${*: -1}" >>"$CURL_LOG"
  printf '%s' "$CURL_BODY"
}

: >"$CURL_LOG"
for crate in a ab abc cargo-edit Cargo-Edit; do _rust_tools_latest "$crate" >/dev/null; done
assert_eq "rust-tools: crates.io sparse index paths by name length, lower-cased" \
  $'https://index.crates.io/1/a\nhttps://index.crates.io/2/ab\nhttps://index.crates.io/3/a/abc\nhttps://index.crates.io/ca/rg/cargo-edit\nhttps://index.crates.io/ca/rg/cargo-edit' \
  "$(cat "$CURL_LOG")"

CURL_BODY='{"name":"x","vers":"1.0.0","yanked":false}
{"name":"x","vers":"1.1.0","yanked":false}
{"name":"x","vers":"1.2.0-beta.1","yanked":false}
{"name":"x","vers":"1.2.0","yanked":true}'
assert_eq "rust-tools: latest version skips yanked and prerelease entries" "1.1.0" "$(_rust_tools_latest x)"

CURL_BODY=""
assert_eq "rust-tools: no version when the index is unreachable" "" "$(_rust_tools_latest x)"

INSTALLED='cargo-edit v0.13.0:
    cargo-add
    cargo-rm
cargo-nextest v0.9.100 (https://github.com/nextest-rs/nextest):
    cargo-nextest'

rust_check() {
  local dir="$TMP_ROOT/rust-state"
  rm -rf "$dir"
  mkdir -p "$dir"
  RUST_OUT="$(_rust_tools_check "$1" "$dir" "$INSTALLED")"
  RUST_STATE="$dir"
}

CURL_BODY='{"vers":"0.13.1","yanked":false}'
rust_check cargo-edit
assert_eq "rust-tools: outdated crate" "cargo-edit 0.13.0 -> 0.13.1" "$RUST_OUT"
assert_file "rust-tools: outdated crate is recorded" "$RUST_STATE/cargo-edit.outdated" present

CURL_BODY='{"vers":"0.13.0","yanked":false}'
rust_check cargo-edit
assert_eq "rust-tools: current crate" "cargo-edit 0.13.0" "$RUST_OUT"
assert_file "rust-tools: current crate is not recorded" "$RUST_STATE/cargo-edit.outdated" absent

CURL_BODY='{"vers":"0.9.101","yanked":false}'
rust_check cargo-nextest
assert_eq "rust-tools: version is read from a line with a source in parentheses" \
  "cargo-nextest 0.9.100 -> 0.9.101" "$RUST_OUT"

rust_check cargo
assert_eq "rust-tools: a name prefix does not match another crate" "✗ cargo — not installed" "$RUST_OUT"
assert_file "rust-tools: missing crate is recorded" "$RUST_STATE/cargo.missing" present

CURL_BODY=""
rust_check cargo-edit
assert_eq "rust-tools: unreachable crates.io keeps the installed version" \
  "cargo-edit 0.13.0 (crates.io unreachable or unknown crate)" "$RUST_OUT"

# --- haskell-tools ---

HASKELL_TOOLS_CONFIG="$TMP_ROOT/haskell-tools"
printf '# tools\nhlint\n\n  ghcid  \n# hoogle\n' >"$HASKELL_TOOLS_CONFIG"
assert_eq "haskell-tools: reads tool names, skipping comments and blank lines" \
  $'hlint\nghcid' "$(_haskell_tools_load)"

hlint() { echo "hlint v3.8, (C) Neil Mitchell 2006-2024"; }

haskell_check() {
  local dir="$TMP_ROOT/haskell-state"
  rm -rf "$dir"
  mkdir -p "$dir"
  HASKELL_OUT="$(_haskell_tools_check "$1" "$dir")"
  HASKELL_STATE="$dir"
}

CURL_BODY='{"normal-version":["3.10"],"deprecated-version":[]}'
haskell_check hlint
assert_eq "haskell-tools: outdated tool" "hlint 3.8 -> 3.10" "$HASKELL_OUT"
assert_eq "haskell-tools: outdated tool records both versions" "3.8 3.10" "$(cat "$HASKELL_STATE/hlint.outdated")"

CURL_BODY='{"normal-version":["3.8"],"deprecated-version":[]}'
haskell_check hlint
assert_eq "haskell-tools: current tool" "hlint 3.8" "$HASKELL_OUT"
assert_file "haskell-tools: current tool is not recorded" "$HASKELL_STATE/hlint.outdated" absent

CURL_BODY=""
haskell_check hlint
assert_eq "haskell-tools: unreachable Hackage keeps the installed version" \
  "hlint 3.8 (Hackage unreachable)" "$HASKELL_OUT"

CURL_BODY='{"normal-version":["3.10"],"deprecated-version":[]}'
haskell_check not-an-installed-tool
assert_eq "haskell-tools: a tool that is not in PATH is reported missing" \
  "✗ not-an-installed-tool — not found in PATH" "$HASKELL_OUT"
assert_file "haskell-tools: missing tool is recorded" "$HASKELL_STATE/not-an-installed-tool.missing" present

printf '\n%s passed, %s failed (bash %s)\n' "$PASSED" "$FAILED" "$BASH_VERSION"
[[ "$FAILED" -eq 0 ]]
