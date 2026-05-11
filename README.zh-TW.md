# codex-as

[English](README.md) · [简体中文](README.zh-CN.md) · 🇹🇼 繁體中文

`codex-as` 是一個很小的 Codex CLI 帳號/profile 切換器。

它可以保存多組 Codex `auth.json` + `model_provider` 設定，並用選定的
profile 啟動 `codex`，目標是盡量不要永久改寫：

- `~/.codex/auth.json`
- `~/.codex/config.toml`

Linux 上使用 `bubblewrap` 做單一子行程內的檔案視圖替換；macOS 沒有
`bubblewrap`，所以預設使用有鎖的啟動視窗暫時替換方案。

## TLDR

```bash
git clone https://github.com/fuyu0425/codex-as.git
cd codex-as

mkdir -p ~/.local/bin ~/.local/share/codex-as/completions
install -m 0755 bin/codex-as ~/.local/bin/codex-as
install -m 0755 bin/codex ~/.local/bin/codex
install -m 0644 completions/_codex-as ~/.local/share/codex-as/completions/_codex-as

# 讓 shim 排在真正的 codex 前面。
export PATH="$HOME/.local/bin:$PATH"

# 保存目前的 Codex 登入，選擇它，然後照常使用 codex。
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

Linux 使用者需要安裝 `bubblewrap`，確保 `bwrap` 在 `PATH` 中。macOS 使用者不需要額外依賴。

## 常用命令

保存目前的 OAuth 登入：

```bash
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

保存 API key 登入和自訂 provider：

```bash
codex-as save api --provider custom
codex-as switch api
codex -m gpt-5.5
```

查看狀態：

```bash
codex-as list
codex-as current
```

也可以直接執行內建快捷 profile：

```bash
codex-as oauth
codex-as api
```

如果已經保存同名 profile，快捷命令會優先使用保存的 profile。

## 為什麼不是直接複製或符號連結 auth.json？

許多工具透過複製、符號連結，或直接改寫 `~/.codex/auth.json` 來切換帳號。
這很簡單，但多個 Codex session 同時啟動時容易互相覆蓋狀態。

`codex-as` 的取捨是：

- Linux：用 `bwrap` 只讓子行程看到選定的 `auth.json`。
- macOS：預設只在 Codex 啟動視窗內暫時替換 `auth.json`，之後恢復。
- provider：保存 profile 時快照自訂 provider，並透過 `codex -c` 回放，不直接改寫全域 `config.toml`。

這不是強安全沙箱；目標是讓每個 Codex 行程看到正確的帳號和 provider。

## macOS 行為

macOS 預設模式：

1. 取得 `~/.config/codex-as/lock`。
2. 備份真正的 `~/.codex/auth.json`。
3. 把 profile 的 auth 暫時複製到 `~/.codex/auth.json`。
4. 啟動 Codex，並注入 provider `-c` 覆蓋。
5. 等待一個短啟動視窗。
6. 恢復原始 `auth.json`。
7. 繼續等待 Codex 子行程退出。

預設啟動視窗：

```bash
CODEX_AS_MACOS_AUTH_HOLD_SECONDS=3
```

如果想保守一些，可以讓鎖一直保持到 Codex 退出：

```bash
CODEX_AS_MACOS_LOCK_MODE=session codex
```

## 安裝補全

```bash
codex-as completions install
```

## 疑難排解

如果 `which codex` 仍然指向 asdf 或其他 shim，把 `~/.local/bin` 放到更前面：

```zsh
path=($HOME/.local/bin ${path:#$HOME/.local/bin})
rehash
```

如果出現 `Model provider custom not found`，代表全域 `config.toml` 沒有定義該 provider。
請從包含 provider 定義的設定重新保存 profile，或使用已保存的 `provider.toml`。
