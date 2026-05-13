#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/bin/codex-as"
SHIM="$ROOT/bin/codex"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  grep -F -- "$needle" "$file" >/dev/null || {
    printf 'expected %s to contain:\n%s\nactual:\n' "$file" "$needle" >&2
    sed -n '1,200p' "$file" >&2 || true
    exit 1
  }
}

make_home() {
  local dir="$1"
  mkdir -p "$dir/.codex"
  printf 'oauth-secret\n' >"$dir/.codex/auth-oauth.json"
  printf 'api-secret\n' >"$dir/.codex/auth-api-key.json"
  printf 'real-auth\n' >"$dir/.codex/auth.json"
  cat >"$dir/.codex/config.toml" <<'EOF'
model_provider = 'saved-provider'

[model_providers.saved-provider]
base_url = "https://example.test/v1"
name = "saved-provider"
requires_openai_auth = true
wire_api = "responses"
EOF
  chmod 600 "$dir/.codex"/auth*.json
}

make_fake_path() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/bwrap" <<'FAKE_BWRAP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$CODEX_AS_CAPTURE"
FAKE_BWRAP
  chmod +x "$dir/bwrap"

  cat >"$dir/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${CODEX_FAKE_RUN_CAPTURE:-}" ]]; then
  printf '%s\n' "$@" >"$CODEX_FAKE_RUN_CAPTURE"
fi
if [[ -n "${CODEX_FAKE_AUTH_CAPTURE:-}" ]]; then
  cat "$HOME/.codex/auth.json" >"$CODEX_FAKE_AUTH_CAPTURE"
fi
exit 0
FAKE_CODEX
  chmod +x "$dir/codex"
}

run_case() {
  local name="$1"
  shift
  local tmp
  tmp="$(mktemp -d)"
  make_home "$tmp/home"
  make_fake_path "$tmp/bin"
  export HOME="$tmp/home"
  export USER="tester"
  export PATH="$tmp/bin:/usr/bin:/bin"
  export CODEX_AS_CAPTURE="$tmp/capture"

  "$@" "$tmp" || fail "$name"
  rm -rf "$tmp"
  printf 'ok - %s\n' "$name"
}

test_api_profile_mounts_api_auth_and_custom_provider() {
  local tmp="$1"
  "$SCRIPT" api -m gpt-5.5

  assert_file_contains "$tmp/capture" "--bind"
  assert_file_contains "$tmp/capture" "$HOME/.codex/auth-api-key.json"
  assert_file_contains "$tmp/capture" "$HOME/.codex/auth.json"
  assert_file_contains "$tmp/capture" "-c"
  assert_file_contains "$tmp/capture" 'model_provider="custom"'
  assert_file_contains "$tmp/capture" "-m"
  assert_file_contains "$tmp/capture" "gpt-5.5"
  [[ "$(cat "$HOME/.codex/auth.json")" == "real-auth" ]] || return 1
}

test_oauth_profile_mounts_oauth_auth_and_openai_provider() {
  local tmp="$1"
  "$SCRIPT" oauth --dangerously-bypass-approvals-and-sandbox

  assert_file_contains "$tmp/capture" "$HOME/.codex/auth-oauth.json"
  assert_file_contains "$tmp/capture" 'model_provider="openai"'
  assert_file_contains "$tmp/capture" "--dangerously-bypass-approvals-and-sandbox"
}

test_named_profile_prefers_saved_profile_auth_when_present() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save oauth
  rm "$HOME/.codex/auth-oauth.json"

  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" oauth

  assert_file_contains "$tmp/capture" "$HOME/.config/codex-as/profiles/oauth/auth.json"
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-oauth.base_url="https://example.test/v1"'
  assert_file_contains "$tmp/capture" 'model_provider="codex-as-oauth"'
}

test_env_overrides_auth_and_provider() {
  local tmp="$1"
  printf 'alt\n' >"$tmp/alt-auth.json"
  chmod 600 "$tmp/alt-auth.json"
  CODEX_AS_API_AUTH="$tmp/alt-auth.json" CODEX_AS_API_PROVIDER="local-provider" "$SCRIPT" api-key

  assert_file_contains "$tmp/capture" "$tmp/alt-auth.json"
  assert_file_contains "$tmp/capture" 'model_provider="local-provider"'
}

test_creates_missing_auth_placeholder_without_overwriting_selected_auth() {
  local tmp="$1"
  rm "$HOME/.codex/auth.json"
  "$SCRIPT" oauth

  [[ -f "$HOME/.codex/auth.json" ]] || return 1
  [[ ! -s "$HOME/.codex/auth.json" ]] || return 1
  assert_file_contains "$tmp/capture" "$HOME/.codex/auth.json"
}

test_missing_bwrap_is_clear_error() {
  local tmp="$1"
  rm "$tmp/bin/bwrap"
  cat >"$tmp/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
echo Linux
FAKE_UNAME
  chmod +x "$tmp/bin/uname"
  if "$SCRIPT" api >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi
  assert_file_contains "$tmp/err" "error: bwrap not found"
}

test_missing_codex_is_clear_error() {
  local tmp="$1"
  rm "$tmp/bin/codex"
  if "$SCRIPT" api >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi
  assert_file_contains "$tmp/err" "error: codex not found"
}

test_missing_auth_file_is_clear_error() {
  local tmp="$1"
  rm "$HOME/.codex/auth-api-key.json"
  if "$SCRIPT" api >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi
  assert_file_contains "$tmp/err" "error: auth file does not exist"
}

test_debug_auth_uses_shell_probe_instead_of_codex() {
  local tmp="$1"
  "$SCRIPT" api --debug-auth

  assert_file_contains "$tmp/capture" "sh"
  assert_file_contains "$tmp/capture" "inside auth:"
  assert_file_contains "$tmp/capture" "$HOME/.codex/auth-api-key.json"
  if grep -Fx -- "codex" "$tmp/capture" >/dev/null; then
    return 1
  fi
}

test_world_readable_auth_warns_but_runs() {
  local tmp="$1"
  chmod 644 "$HOME/.codex/auth-api-key.json"
  "$SCRIPT" api >"$tmp/out" 2>"$tmp/err"

  assert_file_contains "$tmp/err" "warning: auth file is world-readable"
  assert_file_contains "$tmp/capture" "$HOME/.codex/auth-api-key.json"
}

test_save_current_profile_copies_auth_and_provider() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work

  [[ "$(cat "$HOME/.config/codex-as/profiles/work/auth.json")" == "real-auth" ]] || return 1
  assert_file_contains "$HOME/.config/codex-as/profiles/work/profile.toml" 'model_provider = "codex-as-work"'
  assert_file_contains "$HOME/.config/codex-as/profiles/work/provider.toml" 'base_url = "https://example.test/v1"'
  assert_file_contains "$HOME/.config/codex-as/profiles/work/provider.toml" 'name = "codex-as-work"'
  assert_file_contains "$HOME/.config/codex-as/profiles/work/provider.toml" 'requires_openai_auth = true'
  assert_file_contains "$HOME/.config/codex-as/profiles/work/provider.toml" 'wire_api = "responses"'
}

test_save_current_profile_accepts_provider_override() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work --provider override-provider

  assert_file_contains "$HOME/.config/codex-as/profiles/work/profile.toml" 'model_provider = "override-provider"'
}

test_switch_selects_existing_profile_and_current_prints_it() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" switch work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" current >"$tmp/out"

  [[ "$(cat "$HOME/.config/codex-as/selected")" == "work" ]] || return 1
  [[ "$(cat "$tmp/out")" == "work" ]] || return 1
}

test_list_marks_selected_profile() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" switch work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" list >"$tmp/out"

  assert_file_contains "$tmp/out" "* work"
}

test_run_uses_selected_saved_profile_and_real_codex_binary() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" switch work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" run --codex-bin "$tmp/bin/codex" -- -m gpt-5.5

  assert_file_contains "$tmp/capture" "$HOME/.config/codex-as/profiles/work/auth.json"
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-work.base_url="https://example.test/v1"'
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-work.name="codex-as-work"'
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-work.requires_openai_auth=true'
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-work.wire_api="responses"'
  assert_file_contains "$tmp/capture" 'model_provider="codex-as-work"'
  assert_file_contains "$tmp/capture" "$tmp/bin/codex"
  assert_file_contains "$tmp/capture" "-m"
  assert_file_contains "$tmp/capture" "gpt-5.5"
}

test_direct_saved_profile_name_runs_profile() {
  local tmp="$1"
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" save work
  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" work -m gpt-5.5

  assert_file_contains "$tmp/capture" "$HOME/.config/codex-as/profiles/work/auth.json"
  assert_file_contains "$tmp/capture" 'model_providers.codex-as-work.base_url="https://example.test/v1"'
  assert_file_contains "$tmp/capture" 'model_provider="codex-as-work"'
  assert_file_contains "$tmp/capture" "-m"
  assert_file_contains "$tmp/capture" "gpt-5.5"
}

test_run_preserves_legacy_profile_without_provider_snapshot() {
  local tmp="$1"
  local dir="$HOME/.config/codex-as/profiles/legacy"
  mkdir -p "$dir"
  printf 'legacy-auth\n' >"$dir/auth.json"
  chmod 600 "$dir/auth.json"
  printf 'model_provider = "custom"\n' >"$dir/profile.toml"
  printf 'legacy\n' >"$HOME/.config/codex-as/selected"

  CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" run --codex-bin "$tmp/bin/codex" -- -m gpt-5.5

  assert_file_contains "$tmp/capture" 'model_provider="custom"'
  if grep -F -- 'model_providers.custom.' "$tmp/capture" >/dev/null; then
    return 1
  fi
}

test_run_without_selected_profile_is_clear_error() {
  local tmp="$1"
  if CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" run --codex-bin "$tmp/bin/codex" -- >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi
  assert_file_contains "$tmp/err" "error: no selected profile"
}

test_direct_missing_profile_is_clear_error() {
  local tmp="$1"
  if CODEX_AS_HOME="$HOME/.config/codex-as" "$SCRIPT" missing >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi

  assert_file_contains "$tmp/err" "error: profile does not exist: missing"
}

test_codex_shim_calls_codex_as_with_real_codex_binary() {
  local tmp="$1"
  local shim_dir real_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  mkdir -p "$shim_dir" "$real_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$shim_dir/codex-as" <<'FAKE_CODEX_AS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CODEX_SHIM_CAPTURE"
FAKE_CODEX_AS
  chmod +x "$shim_dir/codex-as"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
exit 0
REAL_CODEX
  chmod +x "$real_dir/codex"

  CODEX_SHIM_CAPTURE="$tmp/shim-capture" PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex" -m gpt-5.5

  assert_file_contains "$tmp/shim-capture" "run"
  assert_file_contains "$tmp/shim-capture" "--codex-bin"
  assert_file_contains "$tmp/shim-capture" "$real_dir/codex"
  assert_file_contains "$tmp/shim-capture" "--"
  assert_file_contains "$tmp/shim-capture" "-m"
  assert_file_contains "$tmp/shim-capture" "gpt-5.5"
}

test_codex_shim_passes_through_when_no_profile_is_selected() {
  local tmp="$1"
  local shim_dir real_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  mkdir -p "$shim_dir" "$real_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$shim_dir/codex-as" <<'FAKE_CODEX_AS'
#!/usr/bin/env bash
if [[ "${1:-}" == "current" ]]; then
  exit 1
fi
exit 99
FAKE_CODEX_AS
  chmod +x "$shim_dir/codex-as"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CODEX_SHIM_CAPTURE"
REAL_CODEX
  chmod +x "$real_dir/codex"

  CODEX_SHIM_CAPTURE="$tmp/shim-capture" PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex" -m gpt-5.5

  assert_file_contains "$tmp/shim-capture" "-m"
  assert_file_contains "$tmp/shim-capture" "gpt-5.5"
}

test_codex_shim_uses_project_profile_file() {
  local tmp="$1"
  local shim_dir real_dir project_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  project_dir="$tmp/project/subdir"
  mkdir -p "$shim_dir" "$real_dir" "$project_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$shim_dir/codex-as" <<'FAKE_CODEX_AS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CODEX_SHIM_CAPTURE"
FAKE_CODEX_AS
  chmod +x "$shim_dir/codex-as"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
exit 0
REAL_CODEX
  chmod +x "$real_dir/codex"
  printf 'work\n' >"$tmp/project/.codex-as-profile"

  (
    cd "$project_dir"
    CODEX_SHIM_CAPTURE="$tmp/shim-capture" PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex" -m gpt-5.5
  )

  assert_file_contains "$tmp/shim-capture" "work"
  assert_file_contains "$tmp/shim-capture" "--codex-bin"
  assert_file_contains "$tmp/shim-capture" "$real_dir/codex"
  assert_file_contains "$tmp/shim-capture" "--"
  assert_file_contains "$tmp/shim-capture" "-m"
  assert_file_contains "$tmp/shim-capture" "gpt-5.5"
}

test_codex_shim_uses_first_uncommented_project_profile_line() {
  local tmp="$1"
  local shim_dir real_dir project_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  project_dir="$tmp/project/subdir"
  mkdir -p "$shim_dir" "$real_dir" "$project_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$shim_dir/codex-as" <<'FAKE_CODEX_AS'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$CODEX_SHIM_CAPTURE"
FAKE_CODEX_AS
  chmod +x "$shim_dir/codex-as"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
exit 0
REAL_CODEX
  chmod +x "$real_dir/codex"
  cat >"$tmp/project/.codex-as-profile" <<'PROFILE'
# oauth

api
# work
PROFILE

  (
    cd "$project_dir"
    CODEX_SHIM_CAPTURE="$tmp/shim-capture" PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex"
  )

  assert_file_contains "$tmp/shim-capture" "api"
  if grep -Fxq "oauth" "$tmp/shim-capture"; then
    return 1
  fi
}

test_codex_shim_errors_on_empty_project_profile_file() {
  local tmp="$1"
  local shim_dir real_dir project_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  project_dir="$tmp/project"
  mkdir -p "$shim_dir" "$real_dir" "$project_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$shim_dir/codex-as" <<'FAKE_CODEX_AS'
#!/usr/bin/env bash
exit 99
FAKE_CODEX_AS
  chmod +x "$shim_dir/codex-as"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
exit 0
REAL_CODEX
  chmod +x "$real_dir/codex"
  : >"$project_dir/.codex-as-profile"

  if (
    cd "$project_dir"
    PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex" >"$tmp/out" 2>"$tmp/err"
  ); then
    return 1
  fi

  assert_file_contains "$tmp/err" "error: empty project profile file"
}

test_codex_shim_errors_when_codex_as_is_missing() {
  local tmp="$1"
  local shim_dir real_dir
  shim_dir="$tmp/shim"
  real_dir="$tmp/real"
  mkdir -p "$shim_dir" "$real_dir"
  ln -s "$SHIM" "$shim_dir/codex"
  cat >"$real_dir/codex" <<'REAL_CODEX'
#!/usr/bin/env bash
exit 0
REAL_CODEX
  chmod +x "$real_dir/codex"

  if PATH="$shim_dir:$real_dir:/usr/bin:/bin" "$shim_dir/codex" >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi

  assert_file_contains "$tmp/err" "error: codex-as not found in PATH"
}

test_macos_without_bwrap_swaps_auth_under_lock_and_restores() {
  local tmp="$1"
  rm "$tmp/bin/bwrap"
  cat >"$tmp/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
echo Darwin
FAKE_UNAME
  chmod +x "$tmp/bin/uname"

  CODEX_FAKE_RUN_CAPTURE="$tmp/run-capture" \
    CODEX_FAKE_AUTH_CAPTURE="$tmp/auth-capture" \
    "$SCRIPT" api -m gpt-5.5 >"$tmp/out" 2>"$tmp/err"

  assert_file_contains "$tmp/err" "warning: bwrap not found; using macOS locked auth swap fallback"
  assert_file_contains "$tmp/run-capture" "-c"
  assert_file_contains "$tmp/run-capture" 'model_provider="custom"'
  assert_file_contains "$tmp/run-capture" "-m"
  assert_file_contains "$tmp/run-capture" "gpt-5.5"
  [[ "$(cat "$tmp/auth-capture")" == "api-secret" ]] || return 1
  [[ "$(cat "$HOME/.codex/auth.json")" == "real-auth" ]] || return 1
  [[ ! -e "$HOME/.config/codex-as/lock" ]] || return 1
}

test_macos_fallback_restores_auth_before_child_exits_by_default() {
  local tmp="$1"
  rm "$tmp/bin/bwrap"
  cat >"$tmp/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
echo Darwin
FAKE_UNAME
  chmod +x "$tmp/bin/uname"
  cat >"$tmp/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
printf 'started\n' >"$CODEX_CHILD_STARTED"
sleep 2
cat "$HOME/.codex/auth.json" >"$CODEX_FAKE_AUTH_CAPTURE"
FAKE_CODEX
  chmod +x "$tmp/bin/codex"

  CODEX_AS_MACOS_AUTH_HOLD_SECONDS=0 \
    CODEX_CHILD_STARTED="$tmp/started" \
    CODEX_FAKE_AUTH_CAPTURE="$tmp/auth-after-restore" \
    "$SCRIPT" api >"$tmp/out" 2>"$tmp/err" &
  local pid=$!

  for _ in {1..50}; do
    [[ -f "$tmp/started" ]] && break
    sleep 0.05
  done

  for _ in {1..50}; do
    if [[ "$(cat "$HOME/.codex/auth.json")" == "real-auth" && ! -e "$HOME/.config/codex-as/lock" ]]; then
      break
    fi
    sleep 0.05
  done

  [[ "$(cat "$HOME/.codex/auth.json")" == "real-auth" ]] || return 1
  [[ ! -e "$HOME/.config/codex-as/lock" ]] || return 1
  wait "$pid"
  [[ "$(cat "$tmp/auth-after-restore")" == "real-auth" ]] || return 1
}

test_macos_session_lock_mode_restores_after_child_exits() {
  local tmp="$1"
  rm "$tmp/bin/bwrap"
  cat >"$tmp/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
echo Darwin
FAKE_UNAME
  chmod +x "$tmp/bin/uname"
  cat >"$tmp/bin/codex" <<'FAKE_CODEX'
#!/usr/bin/env bash
set -euo pipefail
cat "$HOME/.codex/auth.json" >"$CODEX_FAKE_AUTH_CAPTURE"
FAKE_CODEX
  chmod +x "$tmp/bin/codex"

  CODEX_AS_MACOS_LOCK_MODE=session \
    CODEX_FAKE_AUTH_CAPTURE="$tmp/auth-during-session" \
    "$SCRIPT" api >"$tmp/out" 2>"$tmp/err"

  [[ "$(cat "$tmp/auth-during-session")" == "api-secret" ]] || return 1
  [[ "$(cat "$HOME/.codex/auth.json")" == "real-auth" ]] || return 1
  [[ ! -e "$HOME/.config/codex-as/lock" ]] || return 1
}

test_unknown_command_suggests_nearest_subcommand() {
  local tmp="$1"
  if "$SCRIPT" swtich api >"$tmp/out" 2>"$tmp/err"; then
    return 1
  fi

  assert_file_contains "$tmp/err" "error: unknown command: swtich"
  assert_file_contains "$tmp/err" "did you mean: switch"
}

test_completions_install_and_uninstall_zsh_file() {
  local tmp="$1"
  "$SCRIPT" completions install >"$tmp/out" 2>"$tmp/err"

  [[ -L "$HOME/.zsh-completions/_codex-as" ]] || return 1
  assert_file_contains "$tmp/out" "installed zsh completion"
  assert_file_contains "$HOME/.zsh-completions/_codex-as" "#compdef codex-as"

  "$SCRIPT" completions uninstall >"$tmp/out2" 2>"$tmp/err2"
  [[ ! -e "$HOME/.zsh-completions/_codex-as" ]] || return 1
  assert_file_contains "$tmp/out2" "removed zsh completion"
}

test_install_completions_alias_installs_zsh_file() {
  local tmp="$1"
  "$SCRIPT" install-completions >"$tmp/out" 2>"$tmp/err"

  [[ -L "$HOME/.zsh-completions/_codex-as" ]] || return 1
}

run_case "api profile binds api auth and custom provider" test_api_profile_mounts_api_auth_and_custom_provider
run_case "oauth profile binds oauth auth and openai provider" test_oauth_profile_mounts_oauth_auth_and_openai_provider
run_case "named profile prefers saved profile auth" test_named_profile_prefers_saved_profile_auth_when_present
run_case "env overrides auth and provider" test_env_overrides_auth_and_provider
run_case "missing auth target creates placeholder only" test_creates_missing_auth_placeholder_without_overwriting_selected_auth
run_case "missing bwrap has clear error" test_missing_bwrap_is_clear_error
run_case "missing codex has clear error" test_missing_codex_is_clear_error
run_case "missing auth file has clear error" test_missing_auth_file_is_clear_error
run_case "debug auth runs shell probe" test_debug_auth_uses_shell_probe_instead_of_codex
run_case "world-readable auth warns but runs" test_world_readable_auth_warns_but_runs
run_case "save copies current auth and provider" test_save_current_profile_copies_auth_and_provider
run_case "save accepts provider override" test_save_current_profile_accepts_provider_override
run_case "switch selects profile and current prints it" test_switch_selects_existing_profile_and_current_prints_it
run_case "list marks selected profile" test_list_marks_selected_profile
run_case "run uses selected saved profile" test_run_uses_selected_saved_profile_and_real_codex_binary
run_case "direct saved profile name runs profile" test_direct_saved_profile_name_runs_profile
run_case "run preserves legacy profile without provider snapshot" test_run_preserves_legacy_profile_without_provider_snapshot
run_case "run without selected profile has clear error" test_run_without_selected_profile_is_clear_error
run_case "direct missing profile has clear error" test_direct_missing_profile_is_clear_error
run_case "codex shim forwards to codex-as run" test_codex_shim_calls_codex_as_with_real_codex_binary
run_case "codex shim passes through with no selected profile" test_codex_shim_passes_through_when_no_profile_is_selected
run_case "codex shim uses project profile file" test_codex_shim_uses_project_profile_file
run_case "codex shim uses first uncommented project profile line" test_codex_shim_uses_first_uncommented_project_profile_line
run_case "codex shim errors on empty project profile file" test_codex_shim_errors_on_empty_project_profile_file
run_case "codex shim errors when codex-as is missing" test_codex_shim_errors_when_codex_as_is_missing
run_case "macOS without bwrap swaps auth under lock and restores" test_macos_without_bwrap_swaps_auth_under_lock_and_restores
run_case "macOS fallback restores before child exits by default" test_macos_fallback_restores_auth_before_child_exits_by_default
run_case "macOS session lock mode restores after child exits" test_macos_session_lock_mode_restores_after_child_exits
run_case "unknown command suggests nearest subcommand" test_unknown_command_suggests_nearest_subcommand
run_case "completions install and uninstall zsh file" test_completions_install_and_uninstall_zsh_file
run_case "install-completions alias installs zsh file" test_install_completions_alias_installs_zsh_file
