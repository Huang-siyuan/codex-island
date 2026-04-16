#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
LOCATOR_FILE="$ROOT_DIR/Sources/CodexIslandApp/ActiveScreenLocator.swift"
PANEL_FILE="$ROOT_DIR/Sources/CodexIslandApp/IslandPanelController.swift"
APP_DELEGATE_FILE="$ROOT_DIR/Sources/CodexIslandApp/AppDelegate.swift"
ROOT_VIEW_FILE="$ROOT_DIR/Sources/CodexIslandApp/IslandRootView.swift"

[[ -f "$LOCATOR_FILE" ]] || {
  echo "Missing ActiveScreenLocator.swift." >&2
  exit 1
}

rg -q "CGWindowListCopyWindowInfo|frontmostApplication" "$LOCATOR_FILE" || {
  echo "Active screen locator is not using the frontmost app window." >&2
  exit 1
}

rg -q "screenLocator.activeScreen|ActiveScreenLocator\\(\\)\\.activeScreen" "$PANEL_FILE" || {
  echo "Panel controller is not positioning on the active screen." >&2
  exit 1
}

rg -q "didActivateApplicationNotification|didChangeScreenParametersNotification" "$APP_DELEGATE_FILE" || {
  echo "AppDelegate is not observing app activation or screen changes." >&2
  exit 1
}

if rg -q "\\.shadow\\(" "$ROOT_VIEW_FILE"; then
  echo "Island root view still applies an outer shadow, which can reintroduce a dark halo." >&2
  exit 1
fi

echo "Active screen following check passed."
