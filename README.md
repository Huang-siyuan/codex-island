# Codex Island

English | [简体中文](README.zh-CN.md)

A local macOS companion for Codex, Claude Code CLI, and CodeBuddy.

Codex Island lives at the top of your screen, keeps the active AI coding session visible, and lets you jump back into the tool with one click.

## What it does

- Watches local session data from Codex, Claude Code CLI, and CodeBuddy
- Chooses the most active provider and shows its task state in a compact island
- Expands into recent sessions for the active provider, including message and tool previews
- Includes a local Usage tab for token and active-time trends, cache efficiency, activity streaks, and top models
- Shows exact daily usage when hovering over the seven-day chart
- Supports markdown rendering in the expanded session detail area
- Lets you click a session card to jump back into Codex, Claude Code CLI, or CodeBuddy
- Includes a bundled two-note completion chime used by default, with mute and custom sound controls
- Groups language, appearance, completion sounds, and launch at login in an inline Settings page, opened with the island's gear button; Sessions and Usage switch back without opening another window
- Offers an optional launch-at-login checkbox backed by macOS Login Items; changes made in System Settings are reflected in the app
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

See [CHANGELOG.md](CHANGELOG.md) for release notes.

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

## First launch behavior

Launch at login is opt-in. Open the gear button → Settings and enable **Launch at login** from the installed app. If macOS requires approval, Settings shows the pending state and a link to Login Items.

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

## UI design

[DESIGN.md](DESIGN.md) documents the shared palette, typography, surfaces and controls for Sessions, Usage and inline Settings. Reuse `IslandDesign.swift` and `IslandControls.swift` when extending the interface.
