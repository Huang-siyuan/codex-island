#!/bin/zsh
set -euo pipefail

PANEL_FILE="/Users/mythoshuang/IdeaProjects/codex-island/Sources/CodexIslandApp/IslandPanelController.swift"
ROOT_VIEW_FILE="/Users/mythoshuang/IdeaProjects/codex-island/Sources/CodexIslandApp/IslandRootView.swift"

if rg -q "height: 132" "$PANEL_FILE"; then
  echo "Panel still uses a hard-coded height." >&2
  exit 1
fi

rg -q "TransparentHostingView" "$PANEL_FILE" || {
  echo "Transparent hosting view is missing." >&2
  exit 1
}

rg -q "setContentSize|setFrame\\(" "$PANEL_FILE" || {
  echo "Panel size is not updated from content measurements." >&2
  exit 1
}

rg -q "onMeasuredSizeChange" "$ROOT_VIEW_FILE" || {
  echo "Root view does not report measured size changes." >&2
  exit 1
}

if rg -q "\\.shadow\\(" "$ROOT_VIEW_FILE" && ! rg -q "shadowSafeAreaInsets|shadowPadding" "$ROOT_VIEW_FILE"; then
  echo "Shadow is present without transparent padding to prevent panel-edge clipping." >&2
  exit 1
fi

echo "Island window chrome check passed."
