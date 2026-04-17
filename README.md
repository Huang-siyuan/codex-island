# Codex Island

English | [简体中文](README.zh-CN.md)

A local macOS companion for Codex, Claude Code CLI, and CodeBuddy.

Codex Island lives at the top of your screen, keeps the active AI coding session visible, and lets you jump back into the tool with one click.

## What it does

- Watches local session data from Codex, Claude Code CLI, and CodeBuddy
- Chooses the most active provider and shows its task state in a compact island
- Expands into recent sessions for the active provider, including message and tool previews
- Supports markdown rendering in the expanded session detail area
- Lets you click a session card to jump back into Codex, Claude Code CLI, or CodeBuddy
- Includes an in-app sound toggle for completion alerts
- Keeps completion state in the hub without showing macOS system banners by default
- Performs first-launch setup so the local Codex wrapper is available without manual shell edits

## Local data sources

- `~/.codex/session_index.jsonl`
- `~/.codex/state_5.sqlite`
- `~/.codex/logs_2.sqlite`
- `~/.claude/projects/**/*.jsonl`
- `~/Library/Application Support/CodeBuddy CN/codebuddy-sessions.vscdb`
- `~/Library/Application Support/CodeBuddy CN/User/globalStorage/tencent-cloud.coding-copilot/todos/*.json`
- `~/Library/Application Support/CodeBuddy CN/User/globalStorage/tencent-cloud.coding-copilot/genie-history/*/current.json`

The app is local-only and does not upload provider session data to a server.

## Run locally

```bash
git clone <repository-url>
cd codex-island
swift build
./.build/debug/CodexIslandApp
```

## Package as a macOS app

```bash
./Scripts/package-app.sh --open
```

That creates:

- `dist/Codex Island.app`

## Create a sharable zip

```bash
./Scripts/release-zip.sh --reveal
```

That creates:

- `dist/Codex Island.app.zip`

You can send that zip to a friend. They can unzip it, move `Codex Island.app` into `Applications`, and launch it like a normal macOS app.

## Install to Applications

```bash
./Scripts/install-app.sh --open
```

That copies the packaged app into:

- `~/Applications/Codex Island.app`

## Support the project

If Codex Island saves you time and you want to support future work, you can tip via WeChat Pay.

![WeChat Pay QR](Assets/wechat-pay.jpg)

## First launch behavior

On the first successful launch, the app will:

- create `~/Library/Application Support/CodexIsland/bin/codex`
- append a `codex-island` PATH snippet to `~/.zshrc`

That keeps setup lightweight and avoids manual shell wiring.

## Notes

- Shared zip builds are ad-hoc signed. On another Mac, the first launch may require right-clicking the app and choosing `Open` once.
- The current packaged build is `arm64`, so the shared app bundle targets Apple Silicon Macs.
- Codex session jumps use `codex://threads/<thread-id>`.
- Claude Code CLI jumps use `claude -r <session-id>` in Terminal as a best-effort resume flow.
- CodeBuddy jumps try to reopen the related workspace via the local CodeBuddy CLI, then fall back to activating the app.
- The app icon is generated locally during packaging, so you do not need to manage a separate binary `.icns` file by hand.
- `swift test` is wired through `swift-testing`, so the test suite can run in the local package environment.
