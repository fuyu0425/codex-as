# codex-as

[English](README.md) · [🇨🇳 简体中文](README.zh-CN.md) · 🇹🇼 繁體中文

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

Linux 安裝範例：

```bash
# Debian / Ubuntu
sudo apt install bubblewrap

# Fedora
sudo dnf install bubblewrap

# Arch Linux
sudo pacman -S bubblewrap
```

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

刪除保存的 profile：

```bash
codex-as delete old-profile
```

建立專案內 profile 模板：

```bash
codex-as init
```

也可以直接執行任意保存的 profile：

```bash
codex-as work
codex-as work -m gpt-5.5
```

內建快捷 profile 也可以直接執行：

```bash
codex-as oauth
codex-as api
```

快捷命令的解析順序：

1. 如果 `~/.config/codex-as/profiles/` 底下有同名保存 profile，優先使用
   該 profile 的 `auth.json`、`profile.toml` 和可選的
   `provider.toml`。
2. 只有 `oauth`、`api`、`api-key` 會在沒有保存 profile 時回退到固定檔案：

```text
oauth   ~/.codex/auth-oauth.json     provider openai
api     ~/.codex/auth-api-key.json   provider custom
```

`CODEX_AS_OAUTH_AUTH`、`CODEX_AS_API_AUTH`、`CODEX_AS_OAUTH_PROVIDER`、
`CODEX_AS_API_PROVIDER` 會覆蓋上述兩種行為。

## 專案內 profile

安裝 `bin/codex` shim 後，可以在專案目錄寫一個 `.codex-as-profile`：

```bash
echo work > .codex-as-profile
codex
```

也可以把多個選擇留在檔案裡，透過移動 `#` 來切換：

```text
# -*- comment-start: "# " -*-
# oauth
api
# work
```

`codex-as init` 會在目前目錄寫入這個檔案，並把所有已保存 profile 都註解掉。
專案需要固定 profile 時，取消註解其中一行即可。

在這個專案目錄內執行 `codex-as list` 時，會標出專案 profile 正在覆蓋全域選擇：

```text
* api   project override: /path/to/project/.codex-as-profile
  oauth selected, overridden by api
```

stdout 是終端時，目前生效的行會自動上色。設定 `NO_COLOR=1` 或
`CODEX_AS_COLOR=never` 可關閉顏色；設定 `CODEX_AS_COLOR=always` 可強制開啟。

`codex` wrapper 會從目前目錄向上查找 `.codex-as-profile`，讀取第一條未被
註解且非空的行作為 profile 名稱，並優先使用這個專案內 profile。沒有專案內
profile 且沒有全域 selected profile 時，wrapper 會直接轉發到真正的 Codex。

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

## 安全 / 限制

- 這不是安全沙箱。
- Linux 上的 bubblewrap 只用於單一行程的 auth 檔案替換。
- macOS 上，`codex-as` 會在 Codex 啟動期間暫時替換 `auth.json`，之後恢復。
- 如果擔心風險，第一次使用前可以先備份 `~/.codex/auth.json`。
