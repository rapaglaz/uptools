# uptools — AI instructions

## Project layout

```text
uptools          # main script: registry, arg parsing, dedup, dispatch
core.sh          # shared utilities: colors, handle_error, command_exists, run_with_check, print_section
modules/*.sh     # one file per tool; self-register via register_tool
config.example   # template for the git-ignored `config` (install.sh copies it)
haskell-tools.example  # templates for the git-ignored `haskell-tools` / `rust-tools` lists
rust-tools.example
install.sh       # symlinks ~/.local/bin/uptools, creates `config`, prints a usage overview (--dry-run)
```

The repository is public: never commit personal state. `config`, `haskell-tools`, `rust-tools` and `.claude/` are
git-ignored; keep examples in `*.example`.

Requires bash >= 4.4 (associative arrays, `local -n`, `${var@Q}`); `uptools` exits early with a
message on older versions (macOS ships 3.2). It first re-execs a Homebrew bash
(`/opt/homebrew/bin/bash`, `/usr/local/bin/bash`) because `env bash` resolves to the system bash in
login shells, cron and launchd. Do not add bash-4-only syntax before that block.

## Adding a module

1. Create `modules/foo.sh`:

```bash
#!/usr/bin/env bash

foo_update() {
  local mode="${1:-check}" requested="${2:-foo}"
  if command_exists "foo" "Foo"; then
    print_section "Foo"
    if [[ "$mode" == "update" ]]; then
      run_with_check "FOO" foo upgrade
    else
      run_with_check "FOO" foo outdated
    fi
  fi
}

register_tool "foo" "foo_update" "description shown in --help"
```

No changes to `uptools` or `core.sh` are needed — modules are auto-loaded from `modules/`, and
completions pick up new tools at runtime (no regeneration, see **Completions**).

The names `update`, `target`, `skip`, `show` and `completion` are reserved; `register_tool`
rejects them as tool or alias names.

Optionally define `foo_installed` (prefix = handler name without `_update`) when the tool is not
simply a binary named `foo` in `$PATH`. `uptools show` calls it; the default is `command -v <name>`.
See `homebrew_installed`, `haskell_tools_installed`, `sdkman_installed`.

## CLI

Keyword based, no short flags. Keywords combine in any order; `target`, `update` and `skip` collect
the names that follow them (comma or space separated) until the next keyword.

```text
uptools [update [names]] [target <names>] [skip <names>] [show] [-h|--help]
uptools completion zsh|fish|bash
```

| Command | Meaning |
| --- | --- |
| `update [names]` | upgrade instead of check (`mode="update"` in handlers); names after it are targets, so `update brew` = `target brew update` |
| `target <names>` | run exactly these tools instead of the config |
| `skip <names>` | exclude tools for this run |
| `show` | list all known tools with `config` / `installed` state (no arguments) |
| `completion zsh\|fish\|bash` | print the completion script |

Bare words without `target`/`update`/`skip` before them are an error. Removed: the flags `-t`,
`--tool`, `--only`, `-u`, `--update`, `--all`, `--skip`, `-s`, `--show`, `--no-color`,
`--completion`, and the groups `default`, `optional`, `all`, `disabled` (plus the `disabled` file).

### Config

`config` is an allow list: bare `uptools` / `uptools update` run only the tools listed there.
Everything else needs an explicit `target`/`update <names>`. A missing config prints a hint and
runs nothing (no fallback to all tools). An explicit selection that expands to nothing prints
`No tools selected` and exits; it must not fall back to `config`.

## register_tool signature

```bash
register_tool "<name>" "<function>" "<description>" ["<alias>"|"<alias>:<description>" ...]
```

- Aliases without `:description` get auto-description: `"<canonical desc> (alias for <name>)"`.
- Aliases with `:description` use the provided text verbatim.

## run_tool dispatch

`run_tool` calls the handler with two args:

1. `mode` — `"check"` (default) or `"update"` (when the `update` keyword is given)
2. `name` — the original name/alias requested by the user (preserved through dedup)

The handler may use `name` to tell which alias was requested, but prefer one tool per module
(`ghcup` and `haskell-tools` are separate modules, not one module with aliases).

## Core utilities (from core.sh)

| Function | Usage |
| --- | --- |
| `command_exists "cmd" "Label"` | prints skip warning and returns 1 if not found |
| `run_with_check "LABEL" cmd args...` | runs cmd; calls handle_error on failure |
| `handle_error "LABEL" "msg"` | sets exit code to 1, prints error |
| `print_section "Name"` | prints `==> Name` section header |

## Help colors

`uptools --help` has its own muted palette (functions `help_colors`, `help_highlight`, ... in
`uptools`), independent of the `core.sh` variables above. It is plain when stdout is not a
terminal or `NO_COLOR` is set, uses 24-bit color when `COLORTERM` is `truecolor`/`24bit` and the 16
ANSI colors otherwise. Roles: keywords/headings blue, tool names and arguments green, options
italic grey-blue, paths light blue, hints muted blue-grey.

## Color variables

`BOLD_WHITE`, `RED`, `YELLOW`, `BOLD_MAGENTA`, `RESET` — all empty when `NO_COLOR` is set.

## What NOT to change

- **`uptools`** — rarely needs changes; new tools go in modules (CLI and completion
  generators are the exception and live here). The dedup loop (near
  the bottom) must preserve the original requested name (not the canonical), so that `requested`
  in handlers reflects what the user typed.
- **`core.sh`** — stable; extend only if adding a utility used by 3+ modules.
- **`SCRIPT_EXIT_CODE`** — must stay global; it accumulates failures across all tools.

## Temporary directories

Use `trap ... RETURN` to clean up, not `EXIT` (which would affect the parent process):

```bash
local tmpdir
tmpdir=$(mktemp -d)
# shellcheck disable=SC2064
trap "rm -rf '$tmpdir'" RETURN
```

## Completions

Tool names are resolved at completion time by the hidden `uptools --complete-tools`
(tab-separated `name<TAB>description`, tools and aliases). The generated scripts only contain the
CLI grammar (keywords, flags), so:

- Adding or renaming a module, or changing aliases/descriptions, needs **no** regeneration.
- Regenerate only after changing the CLI itself: keywords, flags, or the
  `print_completion_*` functions in `uptools`.

Use `>|` rather than `>`: the interactive shell has `noclobber` set, so `>` fails with
`file exists` and leaves the old completion in place.

```bash
uptools completion zsh  >| ~/.local/share/zsh/site-functions/_uptools
uptools completion fish >| ~/.config/fish/completions/uptools.fish
```

Bash has no auto-loading without the `bash-completion` package, so users load it with
`source <(uptools completion bash)`; the generated file under `bash-completion/completions/` only
works when that package is installed.
