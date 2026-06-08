# codex-as

[English](README.md) · 🇨🇳 简体中文 · [🇹🇼 繁體中文](README.zh-TW.md)

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

Linux 安装示例：

```bash
# Debian / Ubuntu
sudo apt install bubblewrap

# Fedora
sudo dnf install bubblewrap

# Arch Linux
sudo pacman -S bubblewrap
```

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

删除保存的 profile：

```bash
codex-as delete old-profile
```

创建项目内 profile 模板：

```bash
codex-as init
codex-as set api
```

也可以直接运行任意保存的 profile：

```bash
codex-as work
codex-as work -m gpt-5.5
```

内置快捷 profile 也可以直接运行：

```bash
codex-as oauth
codex-as api
```

快捷命令的解析顺序：

1. 如果 `~/.config/codex-as/profiles/` 下面有同名保存 profile，优先使用
   该 profile 的 `auth.json`、`profile.toml` 和可选
   `provider.toml`。
2. 只有 `oauth`、`api`、`api-key` 会在没有保存 profile 时回退到固定文件：

```text
oauth   ~/.codex/auth-oauth.json     provider openai
api     ~/.codex/auth-api-key.json   provider custom
```

`CODEX_AS_OAUTH_AUTH`、`CODEX_AS_API_AUTH`、`CODEX_AS_OAUTH_PROVIDER`、
`CODEX_AS_API_PROVIDER` 会覆盖上述两种行为。

## 项目内 profile

安装 `bin/codex` shim 后，可以在项目目录写一个 `.codex-as-profile`：

```bash
echo work > .codex-as-profile
codex
```

也可以把多个选择留在文件里，通过移动 `#` 来切换：

```text
# -*- comment-start: "# " -*-
# oauth
api
# work
```

`codex-as init` 会在当前目录写入这个文件，并把所有已保存 profile 都注释掉。
`codex-as set PROFILE` 会重写这个文件，取消注释指定 profile，并注释掉其他行。
如果 `PROFILE` 不在已保存列表里，会追加到文件末尾。

在这个项目目录内运行 `codex-as list` 时，会标出项目 profile 正在覆盖全局选择：

```text
* api   project override: /path/to/project/.codex-as-profile
  oauth selected, overridden by api
```

stdout 是终端时，当前生效的行会自动上色。设置 `NO_COLOR=1` 或
`CODEX_AS_COLOR=never` 可关闭颜色；设置 `CODEX_AS_COLOR=always` 可强制开启。

`codex` wrapper 会从当前目录向上查找 `.codex-as-profile`，读取第一条未被
注释且非空的行作为 profile 名称，并优先使用这个项目内 profile。没有项目内
profile 且没有全局 selected profile 时，wrapper 会直接转发到真正的 Codex。

## profile.toml 额外配置

`profile.toml` 除了 `model_provider` 之外，还可以包含任意顶层 Codex 配置键：

```toml
model_provider = "moonbridge"
model = "deepseek-v4-pro"
model_reasoning_effort = "high"
```

除 `model_provider` 之外的所有键，都会在启动时以 `-c KEY=VALUE` 的形式传给 Codex。

如果 profile 目录下存在 `models_catalog.json` 文件，会自动加上：

```bash
-c model_catalog_json=/path/to/profiles/moonbridge/models_catalog.json
```

这对 [moon-bridge](https://github.com/ZhiYi-R/moon-bridge) 等可以生成模型目录 JSON 的 provider 很有用。

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

## 安全 / 限制

- 这不是安全沙箱。
- Linux 上的 bubblewrap 只用于单进程 auth 文件替换。
- macOS 上，`codex-as` 会在 Codex 启动期间临时替换 `auth.json`，随后恢复。
- 如果担心风险，第一次使用前可以先备份 `~/.codex/auth.json`。
