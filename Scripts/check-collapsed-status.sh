#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("\(message)\n", stderr)
        exit(1)
    }
}

expect(IslandStatusPresentation.compactLabelText(for: "Done") == "Watching", "Done should collapse to Watching.")
expect(IslandStatusPresentation.compactTone(for: "Done") == .passive, "Done should stay passive in compact mode.")
expect(IslandStatusPresentation.compactLabelText(for: "Running") == "Running", "Running should stay visible in compact mode.")
expect(IslandStatusPresentation.compactLabelText(for: "Tool active") == "Tool active", "Tool-active state should stay explicit in compact mode.")

let metrics = CompactIslandShellStyle.metrics(forHeight: 33)
expect(metrics.topCornerRadius < metrics.bottomCornerRadius, "Compact shell should have a flatter top than bottom.")
expect(Int(metrics.topCornerRadius.rounded()) == 7, "Compact shell top corner radius drifted.")
expect(Int(metrics.bottomCornerRadius.rounded()) == 16, "Compact shell bottom corner radius drifted.")

print("Collapsed status presentation check passed.")
EOF

swiftc \
  -o "$TMP_DIR/status-probe" \
  "$ROOT_DIR/Sources/CodexIslandCore/IslandStatusPresentation.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/CompactIslandShellStyle.swift" \
  "$TMP_DIR/main.swift"

"$TMP_DIR/status-probe"
