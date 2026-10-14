# uptools

Check and update your developer tools with one command.

`uptools` runs a small module per tool (Homebrew, mise, rustup, ghcup, Flutter, ...), shows what
is outdated and, when asked, upgrades it. It is a plain Bash script: no build step, and adding a
tool means dropping one file into `modules/`.

```bash
uptools check              # check the tools listed in your config
uptools update             # upgrade them (short form: uptools up)
uptools update brew mise   # upgrade only these tools
uptools check brew         # check only these tools
uptools check rustup       # check a tool that is not in your config
uptools show               # list known tools: in config? installed?
```

## Requirements

- **Bash 4.4 or newer.** macOS ships Bash 3.2, which is too old. 4.4 is the real minimum, not just
  a safe choice: `${var@Q}` and empty arrays under `set -u` need 4.4, namerefs 4.3, associative
  arrays 4.0. Every maintained Linux distribution ships 4.4 or newer.
  Install a current one with `brew install bash`. The `#!/usr/bin/env bash` shebang picks it up
  from your `PATH`; when `PATH` still resolves to the old system bash (login shells, cron,
  launchd) `uptools` re-runs itself under `/opt/homebrew/bin/bash` or `/usr/local/bin/bash` if
  present, and otherwise exits with a clear message.
- **macOS** is the platform it is developed and tested on (Apple Silicon). Some modules are
  macOS specific (`container`); the others should work anywhere their tool does, but that is not
  tested.
- `jq` for the `homebrew` and `container` modules, `curl` for `haskell-tools` and `rust-tools`,
  `sudo` for `apt` in update mode (not needed as root).
- Each module needs only its own tool; a missing tool is skipped with a `[ SKIP ]` notice.

## Installation

```bash
git clone <repository URL> ~/.uptools
~/.uptools/install.sh
```

`install.sh` links `~/.local/bin/uptools` to the script (make sure `~/.local/bin` is in your
`PATH`) and creates `~/.config/uptools/config` from `examples/config.example`. Files from an older
install (`config`, `haskell-tools`, `rust-tools` next to the script) are moved there. The repository
can live anywhere; `uptools` resolves its own location, including through symlinks.

`install.sh --dry-run` shows what it would link and create without changing anything.

The installer ends with an overview: the available modules (`uptools show`), how to choose what
runs by default or leave out unwanted tools, how the list-driven modules (`haskell-tools`,
`rust-tools`) work, and how to add your own module.

## Usage

Keywords can be combined in any order. `check`, `update` and `-s`/`--skip` collect the names that
follow them (comma or space separated) until the next keyword.

| Command | Description |
| --- | --- |
| `check [names]` | Check for available updates without installing. Names after it run exactly these tools instead of the config |
| `update [names]`, `up [names]` | Install available updates. Names after it run exactly these tools instead of the config |
| `show` | List all known tools with their config and installed state |
| `completion zsh\|fish\|bash` | Print the shell completion script |
| `-s`, `--skip <names>` | Exclude tools for this run |
| `-h`, `--help` | Show help |

```bash
uptools update brew,mise            # same as: uptools update brew mise
uptools brew update                 # error: names need a keyword in front of them
uptools update -s mise brew         # order of keywords does not matter
uptools up brew                     # short form of update
uptools check -s mise               # the config tools except mise
```

`uptools` without a command (or with `--skip` alone) runs nothing and prints the help. Bare tool
names are only accepted after `check`, `update`, `up` or `-s`/`--skip`. An explicit selection that expands to nothing
prints `No tools selected` and exits; it never falls back to the config. The keywords `check`,
`update`, `up`, `target` (removed, kept reserved), `show` and `completion` are reserved and cannot be used as tool
names.

Colors are disabled when the `NO_COLOR` environment variable is set. The exit code is non-zero
when any tool failed.

### `uptools show`

```text
==> Tools
  NAME            CONFIG  INSTALLED  DESCRIPTION
  homebrew        yes     yes        update Homebrew packages
  mise            yes     yes        update Mise tool versions
  rustup          no      yes        update Rust toolchains via rustup
  sdkman          no      no         update SDKMAN! and managed SDKs
```

A tool is *installed* when it is found in `$PATH`. A module whose command differs from its name
defines `<handler prefix>_installed` (for example `homebrew_installed` looks for `brew`).

## Configuration

`config` lives in `${XDG_CONFIG_HOME:-~/.config}/uptools/` (or in `$UPTOOLS_HOME` when set) and
lists the tools that `uptools check` and `uptools update` run, one per line; lines starting with
`#` are comments. It is an **allow list**: a tool that is not listed is not run, so a newly added
module never runs by accident. Use `check`/`update <names>` for anything else.
Without a `config` file `uptools` prints a hint and runs nothing.

```text
homebrew
mise
# rustup   <- known, but not run by default
```

The config directory is outside the repository, so personal state is never committed and updating
the checkout never touches it. `examples/config.example` is the template that `install.sh` copies;
every tool in it is commented out, so a fresh install runs nothing until you uncomment what you want.

## Available tools

| Tool | Aliases | Description |
| --- | --- | --- |
| `homebrew` | `brew` | Homebrew formulae and casks |
| `apt` | | APT packages (Debian/Ubuntu); `update` uses `sudo` unless run as root |
| `ghcup` | | ghcup itself, plus a list of available updates for the tools it installed (GHC, cabal, HLS, stack, ...) |
| `haskell-tools` | | cabal-installed Haskell tools listed in the `haskell-tools` file |
| `mise` | | mise tool versions |
| `rustup` | | Rust toolchains |
| `rust-tools` | | Crates installed with `cargo install`, listed in the `rust-tools` file |
| `flutter` | | Flutter SDK |
| `sdkman` | | SDKMAN! and its SDKs |
| `container` | | Apple `container` tool |
| `android` | | Android CLI and SDK packages |

`apt` only lists packages in check mode (`apt list --upgradable`). It does not refresh the package
index, because that needs root, so the list reflects the last `apt update`. In update mode it runs
`apt update` and `apt upgrade -y`, through `sudo` unless `uptools` already runs as root. It never
uses `full-upgrade` (which may remove packages); packages that `upgrade` keeps back are reported so
you can run `sudo apt full-upgrade` yourself. `sudo` asks for the password in the terminal, so run
`sudo -v` first or add a narrow `NOPASSWD` rule for those two commands when running unattended.

The cabal tools that `haskell-tools` tracks are listed in the `haskell-tools` file and the cargo
crates that `rust-tools` tracks in the `rust-tools` file (one name per line, both in the config directory; see
`examples/haskell-tools.example` and `examples/rust-tools.example`). `rust-tools` compares the installed versions
(`cargo install --list`) with the crates.io index and, in update mode, runs
`cargo install <crate> --locked`.

`ghcup` only reads the tool metadata in check mode: it lists installed tools that are not on
ghcup's `latest` or `recommended` version. In update mode it runs `ghcup upgrade`, which replaces
ghcup itself; it never installs a different GHC, cabal, HLS or stack for you.

## Shell completion

Completion is available for **zsh**, **fish** and **bash**. Tool names are resolved when you press Tab (via
the hidden `uptools --complete-tools`), so new modules show up without regenerating anything.
Only the tools listed in your `config`, and their aliases, are offered; type any other name by hand.

```bash
# zsh (the directory must be in your fpath)
uptools completion zsh >| ~/.local/share/zsh/site-functions/_uptools

# fish
uptools completion fish >| ~/.config/fish/completions/uptools.fish
```

`>|` overrides `noclobber`; plain `>` is fine when your shell does not set it. Regenerate only
when the commands of `uptools` itself change.

Bash is different: the completion script does not use any helper from the `bash-completion`
package, but nothing loads it by itself unless that package is installed. Add one line to your
`~/.bashrc`:

```bash
source <(uptools completion bash)
```

`~/.bashrc` is only read by interactive *non-login* shells. Terminal.app and iTerm2 on macOS start
login shells, which read `~/.bash_profile` instead, so make it load `~/.bashrc` as well:

```bash
# ~/.bash_profile
[[ -f ~/.bashrc ]] && . ~/.bashrc
```

If you have the `bash-completion` package (`brew install bash-completion@2`, then follow its
caveats to load it), you can instead write the script where it auto-loads from:

```bash
uptools completion bash >| ~/.local/share/bash-completion/completions/uptools
```

It completes keywords, tool names, comma separated lists and the shell argument of `completion`.
Bash has no completion descriptions, so only the names are shown.

## Adding a module

Create `modules/foo.sh`; it is loaded automatically, `uptools` and `core.sh` stay untouched:

```bash
#!/usr/bin/env bash

foo_update() {
  local mode="${1:-check}"
  if command_exists "foo" "Foo"; then
    print_section "Foo"
    if [[ "$mode" == "update" ]]; then
      run_with_check "FOO" foo upgrade
    else
      run_with_check "FOO" foo outdated
    fi
  fi
}

register_tool "foo" "foo_update" "update Foo"
```

`register_tool "<name>" "<function>" "<description>" ["<alias>"|"<alias>:<description>" ...]`

- The handler receives `mode` (`check` or `update`) and the name or alias the user typed.
- Helpers from `core.sh`: `command_exists`, `run_with_check`, `handle_error`, `print_section`
  and the color variables (`BOLD_WHITE`, `RED`, `YELLOW`, `BOLD_MAGENTA`, `RESET`).
- Optionally define `foo_installed` (return 0 when installed) if the check is not simply
  `command -v foo`.

## Development

Tool versions are pinned in `mise.toml`.

```bash
mise install            # shellcheck, shfmt, lefthook, actionlint, zizmor
mise run setup          # install the git hooks
mise run lint           # shellcheck
mise run lint-actions   # actionlint and zizmor for .github/workflows
mise run fmt            # shfmt (fmt-check only reports)
mise run test           # smoke tests (tests/smoke.sh)
mise run test-bash44    # the same under bash 4.4, needs Docker
```

The pre-commit hook runs shfmt and shellcheck on the staged shell files and actionlint on workflows; the commit-msg hook
requires Conventional Commits (`feat`, `fix`, `chore`, `refactor`, `test`, `docs`, ...).

## License

[MIT](LICENSE)
