# codex-as

[English](README.md) · 简体中文 · [🇹🇼 繁體中文](README.zh-TW.md)

`codex-as` 是一个很小的 Codex CLI 账号/配置切换器。

它可以保存多个 Codex `auth.json` + `model_provider` 配置，并用选中的
profile 启动 `codex`，目标是尽量不永久改写：

- `~/.codex/auth.json`
- `~/.codex/config.toml`

Linux 上使用 `bubblewrap` 做进程内文件视图替换；macOS 没有
`bubblewrap`，所以默认使用带锁的启动窗口临时替换方案。

## TLDR

```bash
git clone https://github.com/fuyu0425/codex-as.git
cd codex-as

mkdir -p ~/.local/bin ~/.local/share/codex-as/completions
install -m 0755 bin/codex-as ~/.local/bin/codex-as
install -m 0755 bin/codex ~/.local/bin/codex
install -m 0644 completions/_codex-as ~/.local/share/codex-as/completions/_codex-as

# 让 shim 排在真正的 codex 前面。
export PATH="$HOME/.local/bin:$PATH"

# 保存当前 Codex 登录，选择它，然后正常使用 codex。
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

Linux 用户需要安装 `bubblewrap`，确保 `bwrap` 在 `PATH` 中。macOS 用户不需要额外依赖。

## 常用命令

保存当前 OAuth 登录：

```bash
codex-as save oauth --provider openai
codex-as switch oauth
codex
```

保存 API key 登录和自定义 provider：

```bash
codex-as save api --provider custom
codex-as switch api
codex -m gpt-5.5
```

查看状态：

```bash
codex-as list
codex-as current
```

也可以直接运行内置快捷 profile：

```bash
codex-as oauth
codex-as api
```

如果已经保存了同名 profile，快捷命令会优先使用保存的 profile。

## 为什么不是直接复制或软链接 auth.json？

很多工具通过复制、软链接或直接改写 `~/.codex/auth.json` 来切换账号。
这很简单，但多个 Codex 会话同时启动时容易互相踩状态。

`codex-as` 的取舍是：

- Linux：用 `bwrap` 只让子进程看到选中的 `auth.json`。
- macOS：默认只在 Codex 启动窗口内临时替换 `auth.json`，随后恢复。
- provider：保存 profile 时快照自定义 provider，并通过 `codex -c` 回放，不直接改写全局 `config.toml`。

这不是强安全沙箱；目标是让每个 Codex 进程看到正确的账号和 provider。

## macOS 行为

macOS 默认模式：

1. 获取 `~/.config/codex-as/lock`。
2. 备份真实的 `~/.codex/auth.json`。
3. 把 profile 的 auth 临时复制到 `~/.codex/auth.json`。
4. 启动 Codex，并注入 provider `-c` 覆盖。
5. 等待一个短启动窗口。
6. 恢复原始 `auth.json`。
7. 继续等待 Codex 子进程退出。

默认启动窗口：

```bash
CODEX_AS_MACOS_AUTH_HOLD_SECONDS=3
```

如果想保守一些，可以让锁一直保持到 Codex 退出：

```bash
CODEX_AS_MACOS_LOCK_MODE=session codex
```

## 安装补全

```bash
codex-as completions install
```

## 故障排查

如果 `which codex` 仍然指向 asdf 或其他 shim，把 `~/.local/bin` 放到更靠前的位置：

```zsh
path=($HOME/.local/bin ${path:#$HOME/.local/bin})
rehash
```

如果出现 `Model provider custom not found`，说明全局 `config.toml` 没有定义该 provider。
重新从包含 provider 定义的配置保存 profile，或者使用已保存的 `provider.toml`。
