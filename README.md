# Codex Island

A standalone local macOS companion for Codex and IntelliJ IDEA.

## What it does

- Watches local Codex session data from `~/.codex`
- Shows the current thread title, session status, and recent tool activity
- Keeps a floating island-style panel pinned near the top of the screen
- Offers quick actions for `Open Codex` and `Open IDEA`
- Plays a sound and sends a macOS notification when a task completes
- Performs first-launch setup so the local Codex wrapper is available without manual shell edits

## Local data sources

- `~/.codex/session_index.jsonl`
- `~/.codex/state_5.sqlite`
- `~/.codex/logs_2.sqlite`

The current MVP is local-only and does not send Codex data to any remote service.

## Run locally

```bash
cd /Users/mythoshuang/IdeaProjects/codex-island
swift build
./.build/debug/CodexIslandApp
```

## Package as a macOS app

```bash
cd /Users/mythoshuang/IdeaProjects/codex-island
./Scripts/package-app.sh --open
```

That creates:

- `dist/Codex Island.app`

You can then launch it by double-clicking the app bundle in Finder.

## Install to Applications

```bash
cd /Users/mythoshuang/IdeaProjects/codex-island
./Scripts/install-app.sh --open
```

That copies the packaged app into:

- `~/Applications/Codex Island.app`

So you can keep launching it like a normal local macOS app.

## First launch behavior

On the first successful launch, the app will:

- create `~/Library/Application Support/CodexIsland/bin/codex`
- append a `codex-island` PATH snippet to `~/.zshrc`

That keeps setup lightweight and avoids asking you to wire shell config by hand.

## Notes

- The quick action is optimized for the workflow you chose: `IDEA + Codex`, not terminal tab jumping.
- Notifications are sent through `osascript` so the app can run correctly from a Swift Package executable, not only from a bundled `.app`.
- The app icon is generated locally during packaging, so you do not need to manage a separate binary `.icns` file by hand.
- In this machine's current Command Line Tools environment, `swift test` cannot run because both `XCTest` and `Testing` modules are unavailable. `swift build` and a real launch smoke test were used for verification instead.
