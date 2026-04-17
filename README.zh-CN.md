# Codex Island

[English](README.md) | 简体中文

一个运行在本机上的 macOS 顶部状态栏伴侣应用，支持 Codex、Claude Code CLI 和 CodeBuddy。

Codex Island 会停留在屏幕顶部，帮你持续看到当前 AI 编程会话的状态，并且可以一键跳回对应工具。

## 功能说明

- 监听 Codex、Claude Code CLI 和 CodeBuddy 的本机会话数据
- 自动选择当前最活跃的 provider，并在紧凑 hub 中展示任务状态
- 鼠标移入后展开最近会话列表，包含消息和工具预览
- 展开态详情区域支持 Markdown 渲染
- 点击会话卡片可以跳回 Codex、Claude Code CLI 或 CodeBuddy
- 内置提示音开关，可控制完成提醒声音
- 默认只在 hub 内保留完成状态，不再弹 macOS 系统横幅通知
- 首次启动会自动完成本地 Codex wrapper 的轻量配置，尽量不需要手动改 shell

## 本地数据来源

- `~/.codex/session_index.jsonl`
- `~/.codex/state_5.sqlite`
- `~/.codex/logs_2.sqlite`
- `~/.claude/projects/**/*.jsonl`
- `~/Library/Application Support/CodeBuddy CN/codebuddy-sessions.vscdb`
- `~/Library/Application Support/CodeBuddy CN/User/globalStorage/tencent-cloud.coding-copilot/todos/*.json`
- `~/Library/Application Support/CodeBuddy CN/User/globalStorage/tencent-cloud.coding-copilot/genie-history/*/current.json`

应用只在本机读取这些数据，不会把 provider 会话内容上传到服务器。

## 本地运行

```bash
git clone <repository-url>
cd codex-island
swift build
./.build/debug/CodexIslandApp
```

## 打包成 macOS 应用

```bash
./Scripts/package-app.sh --open
```

生成产物：

- `dist/Codex Island.app`

## 生成可分享的 zip

```bash
./Scripts/release-zip.sh --reveal
```

生成产物：

- `dist/Codex Island.app.zip`

你可以直接把这个 zip 发给朋友。对方解压后，把 `Codex Island.app` 拖到 `Applications`，就可以像普通 macOS 应用一样启动。

## 安装到 Applications

```bash
./Scripts/install-app.sh --open
```

会把打包后的应用复制到：

- `~/Applications/Codex Island.app`

## 支持项目

如果 Codex Island 对你有帮助，也欢迎用微信赞赏支持后续开发。

![WeChat Pay QR](Assets/wechat-pay.jpg)

## 首次启动行为

第一次成功启动后，应用会：

- 创建 `~/Library/Application Support/CodexIsland/bin/codex`
- 向 `~/.zshrc` 追加一段 `codex-island` 的 PATH 配置

这样可以保持初始化足够轻量，尽量不需要你手动接线。

## 说明

- 分享出去的 zip 是 ad-hoc 签名，在其他 Mac 上首次启动时，可能需要右键应用后选择一次 `Open`
- 当前打包产物是 `arm64`，因此分享出的 app 主要面向 Apple Silicon Mac
- Codex 会话跳转使用 `codex://threads/<thread-id>`
- Claude Code CLI 会话跳转使用 `claude -r <session-id>`，通过 Terminal 尽力恢复会话
- CodeBuddy 会先尝试通过本地 CodeBuddy CLI 打开关联工作区，失败时回退为激活应用
- 打包时会在本地自动生成应用图标，因此不需要手动维护单独的 `.icns` 二进制文件
- `swift test` 已通过 `swift-testing` 接好，所以可以直接在本地包环境里执行测试
