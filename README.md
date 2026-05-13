# codex-as

English · [🇨🇳 简体中文](README.zh-CN.md) · [🇹🇼 繁體中文](README.zh-TW.md)

`codex-as` is a tiny account/profile switcher for the Codex CLI.

It lets you save multiple Codex auth/provider setups and run `codex` as the
selected profile without permanently rewriting:

- `~/.codex/auth.json`
- `~/.codex/config.toml`

On Linux, it uses `bubblewrap` file bind mounts so only the child Codex process
sees the selected auth file at `~/.codex/auth.json`. On macOS, where
`bubblewrap` is not available, it uses a locked temporary auth-file swap during
the Codex startup window, then restores the original file while the Codex child
continues running.

## TLDR

```bash
git clone https://github.com/fuyu0425/codex-as.git
cd codex-as

mkdir -p ~/.local/bin ~/.local/share/codex-as/completions
install -m 0755 bin/codex-as ~/.local/bin/codex-as
install -m 0755 bin/codex ~/.local/bin/codex
install -m 0644 completions/_codex-as ~/.local/share/codex-as/completions/_codex-as

# Put the shim before the real Codex binary.
export PATH="$HOME/.local/bin:$PATH"

# Save the current Codex login, select it, then use codex normally.
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

For Linux per-process auth substitution, install `bubblewrap` so `bwrap` is on
`PATH`. On macOS, `codex-as` uses the startup-window fallback described below.

## Built-In Profiles

For quick explicit use, any saved profile can be run directly:

```bash
codex-as work
codex-as work -m gpt-5.5
```

The built-in shortcut names also work:

```bash
codex-as oauth
codex-as api
codex-as api-key
```

Shortcut resolution order:

1. If a saved profile with that name exists under
   `~/.config/codex-as/profiles/`, use that saved profile's `auth.json`,
   `profile.toml`, and optional `provider.toml`.
2. For `oauth`, `api`, and `api-key` only, fall back to the legacy fixed files:

```text
~/.codex/auth-oauth.json
~/.codex/auth-api-key.json
```

Fallback providers:

```text
oauth   ~/.codex/auth-oauth.json     provider openai
api     ~/.codex/auth-api-key.json   provider custom
```

Environment variables override both saved-profile lookup and fallback defaults:

```bash
CODEX_AS_OAUTH_AUTH=/path/to/oauth.json codex-as oauth
CODEX_AS_API_AUTH=/path/to/api.json codex-as api
CODEX_AS_OAUTH_PROVIDER=openai codex-as oauth
CODEX_AS_API_PROVIDER=custom codex-as api
```

## Why

Codex reads auth from:

```text
~/.codex/auth.json
```

and provider settings from:

```toml
model_provider = "..."

[model_providers.<name>]
...
```

Copying or symlinking `auth.json` globally is fragile when multiple Codex
sessions are running. One session can flip the file while another session is
starting.

`codex-as` avoids that on Linux by changing the filesystem view for the child
process only. It also stores a snapshot of custom provider settings and replays
them with Codex `-c` overrides, so profiles keep working even if the user later
edits `~/.codex/config.toml`.

## How It Compares

Public Codex account switchers usually optimize for account inventory, UI, or
simple global switching. `codex-as` optimizes for launching one Codex process
with one selected auth/provider view.

Examples in the ecosystem:

- [`Loongphy/codex-auth`](https://github.com/Loongphy/codex-auth): full account
  manager with interactive switching, import/export, usage display, and optional
  API-backed usage refresh. Source review: switching activates an account by
  replacing the live `~/.codex/auth.json`; it does not manage
  `model_provider` / `[model_providers.*]`.
- [`denysdovhan/codex-account`](https://github.com/denysdovhan/codex-account):
  small shell utility that saves accounts and restores them by swapping
  `~/.codex/auth.json`. Its README explicitly says to restart Codex after
  switching if it is already running. It does not touch provider config.
- [`Lampese/codex-switcher`](https://github.com/Lampese/codex-switcher):
  desktop/Tauri app for managing multiple accounts, importing `auth.json`, and
  monitoring usage limits. Source review: account switching writes
  `~/.codex/auth.json`; it does not appear to manage custom Codex providers.
- General provider switchers such as
  [`farion1231/cc-switch`](https://github.com/farion1231/cc-switch) support
  Codex custom providers, but do so by writing live `~/.codex/auth.json` and
  `~/.codex/config.toml`. Its source includes section-aware TOML editing and
  atomic write/rollback logic, which is useful for a full provider manager, but
  it is still global state mutation.

Capability summary:

| Tool | Auth switching | Provider support | Global file mutation | Per-process launch isolation |
| --- | --- | --- | --- | --- |
| `codex-auth` | Yes, account registry and usage UI | No Codex custom provider management found | Replaces live `auth.json` | No |
| `codex-account` | Yes, small shell script | No | Replaces live `auth.json` | No |
| `codex-switcher` | Yes, desktop account manager | No custom provider management found | Writes live `auth.json` | No |
| `cc-switch` | Yes | Yes, including custom `model_providers` TOML | Writes live `auth.json` and `config.toml` | No |
| `codex-as` | Yes, saved profiles and transparent shim | Yes, provider snapshots replayed via `codex -c` | Linux: no live auth/config rewrite. macOS: short locked auth startup swap | Linux: yes. macOS: startup-window fallback |

The common implementation shape is changing global state before launching
Codex:

| Approach | How it works | Tradeoff |
| --- | --- | --- |
| Copy script | Copies one saved auth file over `~/.codex/auth.json` | Simple, but concurrent launches can race and the real auth file stays changed |
| Symlink switcher | Repoints `~/.codex/auth.json` at a selected profile | Fast, but still global state; every running startup sees whichever link wins |
| Config rewriter | Edits `~/.codex/config.toml` to change `model_provider` | Easy to understand, but mixes profile switching with the user's real config |
| Separate `CODEX_HOME` | Runs Codex with a different config/state directory | Strong isolation, but Codex stores much more than auth there: sessions, logs, plugins, skills, caches, and future state |
| Shell aliases | Hard-code `codex -c ...` commands | Good for provider flags, but does not solve `auth.json` safely |

`codex-as` keeps the normal Codex home and changes only what is needed:

- On Linux, `bubblewrap` mounts the selected auth file over
  `~/.codex/auth.json` only inside the child process.
- On macOS, it performs a locked startup-window swap, restores the real
  `auth.json`, then waits for Codex to exit.
- Provider definitions are saved with the profile and replayed through `-c`,
  so `~/.codex/config.toml` does not need to be rewritten.

The main advantage is concurrency and reversibility: normal Codex state remains
normal, and profile selection does not permanently rewrite the user's live auth
or config files.

## Features

- Save named Codex profiles.
- Switch the active profile with `codex-as switch NAME`.
- Optional transparent `codex` shim, so normal `codex` uses the selected
  profile.
- Linux per-process auth substitution with `bubblewrap`.
- macOS fallback with lock, temporary auth swap, startup-window restore, and an
  opt-in session-lock mode.
- Custom provider snapshots replayed via `codex -c`.
- Zsh completions.
- Helpful typo suggestions, for example `swtich -> switch`.

## Requirements

- Bash
- Codex CLI on `PATH`
- Linux: `bubblewrap` available as `bwrap`
- macOS: no extra dependency, but see the macOS fallback notes below

Install `bubblewrap` on Linux:

```bash
# Debian / Ubuntu
sudo apt install bubblewrap

# Fedora
sudo dnf install bubblewrap

# Arch Linux
sudo pacman -S bubblewrap
```

## Install

Clone the repo, then install the two scripts:

```bash
mkdir -p ~/.local/bin ~/.local/share/codex-as/completions
install -m 0755 bin/codex-as ~/.local/bin/codex-as
install -m 0755 bin/codex ~/.local/bin/codex
install -m 0644 completions/_codex-as ~/.local/share/codex-as/completions/_codex-as
```

Make sure `~/.local/bin` is before the real Codex binary in `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Check resolution:

```bash
which codex
which codex-as
```

Expected:

```text
~/.local/bin/codex
~/.local/bin/codex-as
```

If `codex` still resolves to an asdf shim or another wrapper, move
`~/.local/bin` earlier in your shell startup file and reload the shell.

## Quick Start

Save the current login as an OAuth profile:

```bash
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

Save an API-key profile from the current `~/.codex/auth.json`:

```bash
codex-as save api --provider custom
codex-as switch api
codex -m gpt-5.5
```

List and inspect profiles:

```bash
codex-as list
codex-as current
```

Switch back:

```bash
codex-as switch oauth
```

## How Profiles Are Stored

Default storage:

```text
~/.config/codex-as/
  selected
  profiles/
    api/
      auth.json
      profile.toml
      provider.toml
    oauth/
      auth.json
      profile.toml
```

Override the storage root with:

```bash
CODEX_AS_HOME=/path/to/state codex-as list
```

`auth.json` is a copy of the saved Codex auth file.

`profile.toml` stores the provider selected for that saved profile:

```toml
model_provider = "openai"
```

For custom providers, `codex-as save` snapshots the provider definition from
`~/.codex/config.toml` into `provider.toml`, then renames it to a stable
profile-owned provider:

```toml
model_provider = "codex-as-api"
```

Example `provider.toml`:

```toml
base_url = "https://api.example.com/v1"
name = "codex-as-api"
requires_openai_auth = true
wire_api = "responses"
```

This means the `api` profile can keep working even if the global
`~/.codex/config.toml` later removes or changes `[model_providers.custom]`.

## Provider Overrides

Codex CLI supports dotted config overrides with `-c key=value`. The value is
parsed as TOML. For example:

```bash
codex -c 'model_provider="custom"'
codex -c 'model_providers.custom.base_url="https://api.example.com/v1"'
```

`codex-as` uses that mechanism to replay saved providers. A saved `api` profile
with provider `codex-as-api` launches Codex roughly like:

```bash
codex \
  -c 'model_providers.codex-as-api.base_url="https://api.example.com/v1"' \
  -c 'model_providers.codex-as-api.name="codex-as-api"' \
  -c 'model_providers.codex-as-api.requires_openai_auth=true' \
  -c 'model_providers.codex-as-api.wire_api="responses"' \
  -c 'model_provider="codex-as-api"'
```

The exact auth-file substitution depends on the platform.

## Transparent `codex` Shim

The included `bin/codex` is a shim. It resolves the next real `codex` executable
later in `PATH`, then runs:

```bash
codex-as run --codex-bin /path/to/real/codex -- "$@"
```

If the current directory, or one of its parents, contains `.codex-as-profile`,
the shim reads the first uncommented, non-empty line and runs that saved
profile:

```bash
echo work > .codex-as-profile
codex
```

You can keep alternatives in the file and switch by moving the `#`:

```text
# oauth
api
# work
```

`codex-as list` marks the project profile as an override when the current
directory is inside that project:

```text
* api   project override: /path/to/project/.codex-as-profile
  oauth selected, overridden by api
```

When stdout is a terminal, the active line is colored automatically. Set
`NO_COLOR=1` or `CODEX_AS_COLOR=never` to disable color, or
`CODEX_AS_COLOR=always` to force it.

Project-local profile files take precedence over the global selected profile.
If no project profile file exists and no global profile is selected, the shim
passes through to the real Codex binary unchanged.

## Linux Behavior

On Linux, `codex-as` uses `bubblewrap`:

```bash
bwrap \
  --bind / / \
  --dev-bind /dev /dev \
  --proc /proc \
  --bind "$profile_auth" "$HOME/.codex/auth.json" \
  codex ...
```

This is not meant to be a security sandbox. The `--bind / /` mount keeps the
normal filesystem writable so Codex can work on your projects as usual. The goal
is auth-file substitution for the child process.

Concurrent Linux sessions can use different profiles:

```bash
codex-as switch oauth
codex

codex-as switch api
codex
```

Each process sees the auth file it started with.

## macOS Behavior

`bubblewrap` is Linux-only. On macOS, `codex-as` falls back to a launch-window
swap:

1. Acquire `~/.config/codex-as/lock`.
2. Back up the real `~/.codex/auth.json`.
3. Copy the selected profile auth to `~/.codex/auth.json`.
4. Run Codex with provider `-c` overrides.
5. Wait a short startup window.
6. Restore the original `~/.codex/auth.json`.
7. Keep waiting for the Codex child process.
8. Return the child process exit status.

Default startup hold:

```bash
CODEX_AS_MACOS_AUTH_HOLD_SECONDS=3
```

Override it per launch:

```bash
CODEX_AS_MACOS_AUTH_HOLD_SECONDS=8 codex
```

If you want the older conservative behavior, hold the auth swap lock until
Codex exits:

```bash
CODEX_AS_MACOS_LOCK_MODE=session codex
```

The default launch-window mode assumes Codex reads auth during startup. That is
much less disruptive for concurrent sessions, but it is not as strong as the
Linux per-process mount. If Codex starts reading `auth.json` later in a session
for your workflow, use `CODEX_AS_MACOS_LOCK_MODE=session`.

This is not per-process filesystem isolation. It narrows the mutation window
and serializes only startup by default.

## Commands

```text
codex-as PROFILE [--debug-auth] [codex args...]
codex-as save NAME [--provider PROVIDER]
codex-as switch NAME
codex-as current
codex-as list
codex-as run [--codex-bin PATH] [--debug-auth] [-- codex args...]
codex-as oauth [--debug-auth] [codex args...]
codex-as api [--debug-auth] [codex args...]
codex-as completions [install|uninstall]
codex-as install-completions
```

## Completions

Install zsh completions:

```bash
codex-as completions install
exec zsh
```

The installer symlinks:

```text
~/.zsh-completions/_codex-as -> ~/.local/share/codex-as/completions/_codex-as
```

Make sure this appears before `compinit` in your zsh config:

```zsh
fpath=(~/.zsh-completions $fpath)
```

Uninstall:

```bash
codex-as completions uninstall
```

## Debugging

See which auth file Codex would see:

```bash
codex-as run --debug-auth
codex-as api --debug-auth
```

Common typo:

```bash
codex-as swtich api
```

Output:

```text
error: unknown command: swtich
did you mean: switch
```

Check active profile:

```bash
codex-as current
codex-as list
```

Check wrapper resolution:

```bash
which codex
which codex-as
```

## Troubleshooting

### `which codex` points to asdf

Move `~/.local/bin` before asdf shims in your shell startup:

```zsh
path=($HOME/.local/bin ${path:#$HOME/.local/bin})
rehash
```

### `Model provider custom not found`

Your global `~/.codex/config.toml` does not define `custom`. Save the profile
from a config that does define the provider, or create `provider.toml` under the
profile. New saved profiles snapshot provider definitions automatically when the
selected provider exists under `[model_providers.<name>]`.

### `bwrap not found`

On Linux, install bubblewrap:

```bash
sudo apt install bubblewrap      # Debian / Ubuntu
sudo dnf install bubblewrap      # Fedora
sudo pacman -S bubblewrap        # Arch Linux
```

On macOS, the locked-swap fallback is used automatically.

### Existing `auth.json` changes unexpectedly on macOS

macOS cannot do the Linux per-process bind mount. `codex-as` backs up and
restores the file while holding a short startup lock by default. If Codex or the
shell is force-killed during that window, inspect:

```text
~/.config/codex-as/lock
~/.config/codex-as/auth.json.backup.*
```

## Security Notes

`codex-as` is not a secret manager.

- Profile auth files are stored under `~/.config/codex-as/profiles/*/auth.json`.
- The wrapper sets saved auth files to mode `600`.
- Do not commit profile storage.
- Linux `bubblewrap` usage here is for filesystem view substitution, not a
  hardened sandbox.

## Safety / Limitations

- This is not a security sandbox.
- On Linux, bubblewrap is used only for per-process auth-file substitution.
- On macOS, `codex-as` temporarily swaps `auth.json` during Codex startup and
  restores it.
- Back up `~/.codex/auth.json` before first use if you are worried.

## License

Choose a license before publishing this repository.
