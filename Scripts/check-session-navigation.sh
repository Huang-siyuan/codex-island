#!/bin/zsh
set -euo pipefail

root="/Users/mythoshuang/IdeaProjects/codex-island"
view="$root/Sources/CodexIslandApp/IslandRootView.swift"
viewModel="$root/Sources/CodexIslandApp/IslandViewModel.swift"
router="$root/Sources/CodexIslandCore/FocusRouter.swift"

if rg -F -q 'Button("Open Codex")' "$view" || rg -F -q 'Button("Open IDEA")' "$view"; then
  echo "Footer launcher buttons are still present." >&2
  exit 1
fi

if ! rg -F -q 'openSession(preview)' "$view"; then
  echo "Session cards are not wired to openSession(preview)." >&2
  exit 1
fi

if ! rg -F -q 'func openSession(_ preview: SessionPreview)' "$viewModel"; then
  echo "IslandViewModel is missing openSession(_:) entry point." >&2
  exit 1
fi

if ! rg -F -q 'func activateSession(threadID: String)' "$router"; then
  echo "FocusRouter is missing activateSession(threadID:)." >&2
  exit 1
fi

if ! rg -F -q 'func sessionURL(threadID: String) -> URL?' "$router"; then
  echo "FocusRouter is missing sessionURL(threadID:)." >&2
  exit 1
fi

if ! rg -F -q 'codex://threads/' "$router"; then
  echo "FocusRouter is not building the Codex thread deeplink." >&2
  exit 1
fi

if ! rg -F -q 'NSWorkspace.shared.open(url)' "$router"; then
  echo "FocusRouter is not opening the thread deeplink." >&2
  exit 1
fi

echo "Session navigation check passed."
