#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

let semaphore = DispatchSemaphore(value: 0)

Task {
    let result = await PollingEngine().pollOnce()
    let previews = result.snapshot.sessionPreviews

    print("preview_count=\(previews.count)")
    for (index, preview) in previews.enumerated() {
        print("session[\(index)].title=\(preview.title)")
        print("session[\(index)].status=\(preview.statusText)")
        print("session[\(index)].user=\(preview.userPreview ?? "-")")
        print("session[\(index)].assistant=\((preview.assistantPreview ?? preview.latestToolSummary) ?? "-")")
    }
    semaphore.signal()
}

_ = semaphore.wait(timeout: .now() + 30)
EOF

swiftc \
  -o "$TMP_DIR/session-preview-probe" \
  "$ROOT_DIR/Sources/CodexIslandCore/AppEnvironment.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/CodexModels.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionIndexParser.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionIndexReader.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/CodexStateStore.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/LogsEventParser.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionPreviewParser.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionCoordinator.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/PollingEngine.swift" \
  "$TMP_DIR/main.swift"

"$TMP_DIR/session-preview-probe" > "$TMP_DIR/output.txt" 2>&1

grep -q '^preview_count=' "$TMP_DIR/output.txt"
cat "$TMP_DIR/output.txt"
echo "Session previews resolved successfully."
