#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DELEGATE="$ROOT_DIR/Sources/CodexIslandApp/AppDelegate.swift"

if [[ ! -f "$APP_DELEGATE" ]]; then
  echo "Missing AppDelegate.swift at $APP_DELEGATE" >&2
  exit 1
fi

if rg -n 'CodexStateStore|SessionCoordinator|LogsEventParser|lastSeenLogIDByThread|fetchRecentThreads|fetchLogRows|func pollLoop' "$APP_DELEGATE" >/dev/null; then
  echo "Main-thread polling regression: AppDelegate still contains polling IO/state." >&2
  exit 1
fi

echo "Main-thread polling check passed."
