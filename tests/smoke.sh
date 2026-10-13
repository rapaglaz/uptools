#!/usr/bin/env bash
# Smoke tests for uptools: CLI parsing, dispatch, dedup, config handling, completions.
# Every test runs against a throw-away copy of the repo with a fake module, so no real
# tool (brew, rustup, ...) is ever invoked. Compatible with bash >= 4.4.
#
# usage: tests/smoke.sh

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NO_COLOR=1

PASSED=0
FAILED=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

# Result of the last run_uptools call
OUT="" ERR="" RC=0
SANDBOX="" CALL_LOG=""
CURRENT_TEST=""

# new_sandbox: copy the scripts into a fresh directory and add the fake module
new_sandbox() {
  SANDBOX="$(mktemp -d "$TMP_ROOT/sandbox.XXXXXX")"
  export UPTOOLS_HOME="$SANDBOX" # config lives in the sandbox, never in the real ~/.config
  cp "$REPO_DIR/uptools" "$REPO_DIR/core.sh" "$SANDBOX/"
  mkdir "$SANDBOX/modules"
  CALL_LOG="$SANDBOX/calls.log"
  : >"$CALL_LOG"
  cat >"$SANDBOX/modules/fake.sh" <<'EOF'
#!/usr/bin/env bash

fake_update() { echo "fake mode=$1 name=$2" >>"$CALL_LOG"; }
other_update() { echo "other mode=$1 name=$2" >>"$CALL_LOG"; }
broken_update() { handle_error "BROKEN" "boom"; }

register_tool "fake" "fake_update" "fake tool" "fk" "fkd:custom alias text"
register_tool "other" "other_update" "other tool"
register_tool "broken" "broken_update" "always fails"
EOF
}

# write_config <tool...>: one tool per line in the sandbox config
write_config() {
  printf '%s\n' "$@" >"$SANDBOX/config"
}

# run_uptools <args...>: run the sandboxed uptools, capture stdout, stderr and exit code
run_uptools() {
  OUT="$(CALL_LOG="$CALL_LOG" "$BASH" "$SANDBOX/uptools" "$@" 2>"$SANDBOX/stderr")"
  RC=$?
  ERR="$(<"$SANDBOX/stderr")"
}

calls() { cat "$CALL_LOG"; }

test_case() { CURRENT_TEST="$1"; }

pass() { PASSED=$((PASSED + 1)); }

fail() {
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n      %s\n' "$CURRENT_TEST" "$1"
  printf '      rc=%s\n      stdout: %s\n      stderr: %s\n      calls: %s\n' \
    "$RC" "$OUT" "$ERR" "$(calls | tr '\n' '|')"
}

# assert_rc <expected>
assert_rc() { if [[ "$RC" == "$1" ]]; then pass; else fail "expected exit code $1"; fi; }

# assert_contains <haystack> <needle>
assert_contains() { if [[ "$1" == *"$2"* ]]; then pass; else fail "expected to find: $2"; fi; }

# assert_not_contains <haystack> <needle>
assert_not_contains() { if [[ "$1" != *"$2"* ]]; then pass; else fail "expected NOT to find: $2"; fi; }

# assert_calls <expected log, lines separated by newlines; empty for no calls>
assert_calls() {
  if [[ "$(calls)" == "$1" ]]; then pass; else fail "expected calls: $(printf '%s' "$1" | tr '\n' '|')"; fi
}

# --- help and completion ---

test_case "help lists tools and aliases, exits 0"
new_sandbox
run_uptools --help
assert_rc 0
assert_contains "$OUT" "Usage:"
assert_contains "$OUT" "fake tool"
assert_contains "$OUT" "fake tool (alias for fake)"
assert_contains "$OUT" "custom alias text"

test_case "help is plain when NO_COLOR is set"
new_sandbox
run_uptools --help
assert_not_contains "$OUT" $'\033'

test_case "--complete-tools prints tab separated tools and aliases"
new_sandbox
run_uptools --complete-tools
assert_rc 0
assert_contains "$OUT" $'fake\tfake tool'
assert_contains "$OUT" $'fk\tfake tool (alias for fake)'
assert_contains "$OUT" $'fkd\tcustom alias text'

for shell in zsh fish bash; do
  test_case "completion $shell prints a script"
  new_sandbox
  run_uptools completion "$shell"
  assert_rc 0
  assert_contains "$OUT" "uptools"
done

test_case "bash completion script is syntactically valid"
new_sandbox
run_uptools completion bash
printf '%s\n' "$OUT" >"$SANDBOX/completion.bash"
"$BASH" -n "$SANDBOX/completion.bash" 2>"$SANDBOX/stderr"
RC=$?
ERR="$(<"$SANDBOX/stderr")"
assert_rc 0

test_case "completion with an unknown shell exits 2"
new_sandbox
run_uptools completion powershell
assert_rc 2
assert_contains "$ERR" "Usage: uptools completion"

# --- argument errors ---

test_case "bare word without keyword exits 2"
new_sandbox
run_uptools fake
assert_rc 2
assert_contains "$ERR" "Unexpected argument: fake"

test_case "unknown option exits 2"
new_sandbox
run_uptools --nope
assert_rc 2
assert_contains "$ERR" "Unknown option: --nope"

test_case "removed flags are rejected"
new_sandbox
run_uptools -u
assert_rc 2

test_case "show takes no arguments"
new_sandbox
run_uptools show fake
assert_rc 2
assert_contains "$ERR" "show takes no arguments"

# --- dispatch ---

test_case "target runs the tool in check mode"
new_sandbox
run_uptools target fake
assert_rc 0
assert_calls "fake mode=check name=fake"

test_case "update <names> runs the tool in update mode"
new_sandbox
run_uptools update fake
assert_rc 0
assert_calls "fake mode=update name=fake"

test_case "target <names> update is the same as update <names>"
new_sandbox
run_uptools target fake update
assert_rc 0
assert_calls "fake mode=update name=fake"

test_case "alias is passed to the handler as typed"
new_sandbox
run_uptools target fk
assert_rc 0
assert_calls "fake mode=check name=fk"

test_case "comma and space separated lists are equivalent"
new_sandbox
run_uptools target fake,other
assert_rc 0
assert_calls $'fake mode=check name=fake\nother mode=check name=other'

test_case "space separated names work too"
new_sandbox
run_uptools target other fake
assert_rc 0
assert_calls $'other mode=check name=other\nfake mode=check name=fake'

test_case "dedup keeps the first requested name"
new_sandbox
run_uptools target fk,fake
assert_rc 0
assert_calls "fake mode=check name=fk"

test_case "skip removes tools, aliases included"
new_sandbox
run_uptools target fake,other skip fk
assert_rc 0
assert_calls "other mode=check name=other"

test_case "unknown tool warns and exits 1"
new_sandbox
run_uptools target nope
assert_rc 1
assert_contains "$ERR" "Unknown tool: 'nope'"

test_case "unknown tool does not stop the others"
new_sandbox
run_uptools target nope,fake
assert_rc 1
assert_calls "fake mode=check name=fake"

test_case "a failing handler makes the exit code 1"
new_sandbox
run_uptools target broken,fake
assert_rc 1
assert_contains "$ERR" "BROKEN"
assert_calls "fake mode=check name=fake"

test_case "target without names runs nothing and does not fall back to config"
new_sandbox
write_config fake
run_uptools target
assert_rc 0
assert_contains "$ERR" "No tools selected"
assert_calls ""

# --- config ---

test_case "bare uptools runs only the tools in config"
new_sandbox
write_config fake
run_uptools
assert_rc 0
assert_calls "fake mode=check name=fake"

test_case "bare update runs config tools in update mode"
new_sandbox
write_config fake
run_uptools update
assert_rc 0
assert_calls "fake mode=update name=fake"

test_case "config ignores comments and blank lines"
new_sandbox
printf '# comment\n\n  other  \n# fake\n' >"$SANDBOX/config"
run_uptools
assert_rc 0
assert_calls "other mode=check name=other"

test_case "config accepts aliases"
new_sandbox
write_config fk
run_uptools
assert_rc 0
assert_calls "fake mode=check name=fk"

test_case "skip applies to the config"
new_sandbox
write_config fake other
run_uptools skip other
assert_rc 0
assert_calls "fake mode=check name=fake"

test_case "target ignores the config"
new_sandbox
write_config fake
run_uptools target other
assert_rc 0
assert_calls "other mode=check name=other"

test_case "missing config prints a hint and runs nothing"
new_sandbox
run_uptools
assert_rc 0
assert_contains "$ERR" "No config file"
assert_calls ""

test_case "config is read from XDG_CONFIG_HOME when UPTOOLS_HOME is unset"
new_sandbox
mkdir -p "$SANDBOX/xdg/uptools"
printf 'fake\n' >"$SANDBOX/xdg/uptools/config"
OUT="$(env -u UPTOOLS_HOME XDG_CONFIG_HOME="$SANDBOX/xdg" CALL_LOG="$CALL_LOG" "$BASH" "$SANDBOX/uptools" 2>"$SANDBOX/stderr")"
RC=$?
assert_rc 0
assert_calls "fake mode=check name=fake"

test_case "unknown tool in config exits 1"
new_sandbox
write_config nope fake
run_uptools
assert_rc 1
assert_contains "$ERR" "Unknown tool: 'nope'"
assert_calls "fake mode=check name=fake"

# --- show ---

test_case "show lists config and installed state"
new_sandbox
write_config fake
run_uptools show
assert_rc 0
assert_contains "$OUT" "NAME"
assert_contains "$OUT" "fake tool"
assert_contains "$OUT" "other tool"
assert_calls ""

# --- registry ---

for reserved in update target skip show completion; do
  test_case "register_tool rejects the reserved name '$reserved'"
  new_sandbox
  printf 'register_tool "%s" "fake_update" "reserved"\n' "$reserved" >"$SANDBOX/modules/reserved.sh"
  run_uptools --help
  assert_contains "$ERR" "'$reserved' is a reserved name"
done

test_case "register_tool rejects a reserved alias"
new_sandbox
printf 'register_tool "fine" "fake_update" "ok" "show"\n' >"$SANDBOX/modules/reserved.sh"
run_uptools --help
assert_contains "$ERR" "'show' is a reserved name"

# --- real modules ---

test_case "real modules all load without errors"
SANDBOX="$TMP_ROOT/real"
mkdir "$SANDBOX"
export UPTOOLS_HOME="$SANDBOX"
cp -R "$REPO_DIR/uptools" "$REPO_DIR/core.sh" "$REPO_DIR/modules" "$SANDBOX/"
CALL_LOG="$SANDBOX/calls.log"
: >"$CALL_LOG"
run_uptools --complete-tools
assert_rc 0
assert_calls ""
if [[ -z "$ERR" ]]; then pass; else fail "modules wrote to stderr"; fi
if [[ "$(printf '%s\n' "$OUT" | wc -l)" -ge "$(find "$REPO_DIR/modules" -name '*.sh' | wc -l)" ]]; then
  pass
else
  fail "fewer registered tools than module files"
fi

printf '\n%s passed, %s failed (bash %s)\n' "$PASSED" "$FAILED" "$BASH_VERSION"
[[ "$FAILED" -eq 0 ]]
