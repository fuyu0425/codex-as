# AGENTS.md

## Project Scope

This repository contains `codex-as`, a small Bash wrapper for launching Codex
with selected auth/provider profiles.

## Development Notes

- Keep the implementation small and shell-first.
- Do not commit downloaded reference repos under `refs/`; they are local
  research material.
- Do not commit `docs/superpowers/`; keep those files local if generated.
- Prefer `codex -c` runtime overrides over editing `~/.codex/config.toml`.
- Preserve the core design goal: avoid permanent global mutation of
  `~/.codex/auth.json` and `~/.codex/config.toml`.
- On Linux, prefer the `bubblewrap` backend for per-process auth substitution.
- On macOS, keep the startup-window fallback as the default and session-lock
  mode as the stricter opt-in behavior.

## Verification

Before publishing changes, run:

```bash
test/codex-as-test.bash
shellcheck bin/codex bin/codex-as test/codex-as-test.bash
zsh -n completions/_codex-as
git diff --check
```
