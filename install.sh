#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: install.sh [--dry-run]

Links ~/.local/bin/uptools to this checkout and creates config from config.example.

  -n, --dry-run   Show what would be done without changing anything
  -h, --help      Show this help
USAGE
}

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
  -n | --dry-run) DRY_RUN=true ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo >&2 "Unknown option: $arg"
    usage >&2
    exit 2
    ;;
  esac
done

# Colors only on a terminal and when NO_COLOR is unset (https://no-color.org/)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  WHITE=$'\033[1;37m' MAGENTA=$'\033[1;35m' CYAN=$'\033[36m' GREEN=$'\033[32m'
  YELLOW=$'\033[33m' DIM=$'\033[2m' RESET=$'\033[0m'
else
  WHITE="" MAGENTA="" CYAN="" GREEN="" YELLOW="" DIM="" RESET=""
  export NO_COLOR=1 # keeps the output of "uptools show" plain as well
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/uptools"

# Shorten $HOME to ~ for display
tilde() {
  if [[ "$1" == "$HOME"* ]]; then printf '~%s' "${1#"$HOME"}"; else printf '%s' "$1"; fi
}
heading() { printf '\n%s==> %s%s%s\n' "$WHITE" "$MAGENTA" "$1" "$RESET"; }
row() { printf '  %-36s %s%s%s\n' "$1" "$CYAN" "$2" "$RESET"; }
done_line() { printf '%s✓%s %s\n' "$GREEN" "$RESET" "$1"; }
plan_line() { printf '%s[dry-run]%s %s\n' "$YELLOW" "$RESET" "$1"; }

D_SCRIPT="$(tilde "$SCRIPT_DIR")"
D_TARGET="$(tilde "$TARGET")"

heading "Installing uptools"
if [[ "$DRY_RUN" == true ]]; then
  plan_line "Nothing will be changed."
  [[ -d "$BIN_DIR" ]] || plan_line "would create directory: $(tilde "$BIN_DIR")"
  plan_line "would link: ${D_TARGET} -> ${D_SCRIPT}/uptools"
  if [[ -L "$TARGET" ]]; then
    plan_line "  currently links to: $(tilde "$(readlink "$TARGET")")"
  elif [[ -e "$TARGET" ]]; then
    plan_line "  warning: ${D_TARGET} exists and is not a symlink; it would be replaced"
  fi
  if [[ -f "${SCRIPT_DIR}/config" ]]; then
    plan_line "config exists, would keep: ${D_SCRIPT}/config"
  else
    plan_line "would create: ${D_SCRIPT}/config (copy of config.example)"
  fi
else
  mkdir -p "$BIN_DIR"
  ln -sf "${SCRIPT_DIR}/uptools" "$TARGET"
  done_line "Linked ${D_TARGET} -> ${D_SCRIPT}/uptools"

  # Start from the example config; it is git-ignored so local edits never conflict with updates
  if [[ ! -f "${SCRIPT_DIR}/config" ]]; then
    cp "${SCRIPT_DIR}/config.example" "${SCRIPT_DIR}/config"
    done_line "Created ${D_SCRIPT}/config (edit it to choose the default tools)"
  fi
fi

case ":${PATH}:" in
*":${BIN_DIR}:"*) ;;
*) printf '%s!%s %s is not in your PATH; add it to use the uptools command\n' "$YELLOW" "$RESET" "$(tilde "$BIN_DIR")" ;;
esac

# "show" lists every module with its config / installed state; never fail the install over it
"${SCRIPT_DIR}/uptools" show 2>/dev/null ||
  printf '\n%s(run "uptools show" once your shell finds the command)%s\n' "$DIM" "$RESET"

heading "Choosing what runs"
printf '  %sconfig%s is an allow list: %suptools%s and %suptools update%s run only the tools listed\n' "$WHITE" "$RESET" "$CYAN" "$RESET" "$CYAN" "$RESET"
printf '  there, one per line (%s#%s starts a comment).\n\n' "$DIM" "$RESET"
row "Stop running a tool by default" "remove or comment it out in ${D_SCRIPT}/config"
row "Still run it on demand" "uptools target <name>"
row "Skip it for a single run" "uptools skip <name>"
row "Remove a module for good" "delete its file in ${D_SCRIPT}/modules/"

heading "Tools that track a list"
printf '  Some tools are installed through a package manager (cabal, cargo), so there is no\n'
printf '  single program to update. %shaskell-tools%s and %srust-tools%s read the packages to keep\n' "$WHITE" "$RESET" "$WHITE" "$RESET"
printf '  current from a plain text list, one name per line (%s#%s starts a comment):\n\n' "$DIM" "$RESET"
row "haskell-tools  cabal, Hackage" "${D_SCRIPT}/haskell-tools"
row "rust-tools     cargo, crates.io" "${D_SCRIPT}/rust-tools"
printf '\n  Start from the examples. The lists are git-ignored, so your edits are never overwritten:\n\n'
printf '    %scp %s/haskell-tools.example %s/haskell-tools%s\n' "$CYAN" "$D_SCRIPT" "$D_SCRIPT" "$RESET"
printf '    %scp %s/rust-tools.example %s/rust-tools%s\n' "$CYAN" "$D_SCRIPT" "$D_SCRIPT" "$RESET"
printf '\n  Without a list the module is skipped. Add its name to config to run it by default.\n'

heading "Adding your own module"
printf '  Create %s%s/modules/<name>.sh%s. It is loaded automatically and appears in\n' "$CYAN" "$D_SCRIPT" "$RESET"
printf '  %suptools show%s and in tab completion. See "Adding a module" in README.md.\n' "$CYAN" "$RESET"

printf '\n%sNext:%s %suptools show%s  %s·%s  %suptools%s  %s·%s  %suptools --help%s\n' \
  "$WHITE" "$RESET" "$CYAN" "$RESET" "$DIM" "$RESET" "$CYAN" "$RESET" "$DIM" "$RESET" "$CYAN" "$RESET"
