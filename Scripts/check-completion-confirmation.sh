#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

@main
struct CompletionConfirmationProbe {
    static func main() {
        var currentTime = Date(timeIntervalSince1970: 202)
        let coordinator = SessionCoordinator(
            now: { currentTime },
            completionIdleThreshold: 4,
            completionConfirmationThreshold: 2
        )
        let thread = ThreadSnapshot(
            threadID: "thread-1",
            title: "Example",
            source: "desktop",
            cwd: nil,
            updatedAt: Date(timeIntervalSince1970: 180),
            firstUserMessage: nil
        )
        let completion = CodexLogEvent(
            threadID: "thread-1",
            kind: .responseCompleted,
            toolName: nil,
            summary: "Completed",
            timestamp: Date(timeIntervalSince1970: 200)
        )

        coordinator.apply(threadSnapshots: [thread])
        coordinator.apply(logEvents: [completion])

        func report(_ label: String) {
            let snapshot = coordinator.currentSnapshot
            print("\(label): status=\(snapshot.statusText) notify=\(snapshot.shouldNotifyCompletion)")
        }

        report("t+2")
        currentTime = Date(timeIntervalSince1970: 205)
        report("t+5")
        currentTime = Date(timeIntervalSince1970: 207)
        report("t+7")

        if coordinator.currentSnapshot.statusText != "Done" || !coordinator.currentSnapshot.shouldNotifyCompletion {
            fputs("Completion confirmation never stabilized.\n", stderr)
            exit(1)
        }
    }
}
EOF

swiftc \
  -parse-as-library \
  -o "$TMP_DIR/completion-confirmation-probe" \
  "$ROOT_DIR/Sources/CodexIslandCore/CodexModels.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionPreviewParser.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionCoordinator.swift" \
  "$TMP_DIR/main.swift"

"$TMP_DIR/completion-confirmation-probe" > "$TMP_DIR/output.txt"
grep -q '^t+2: status=Running notify=false$' "$TMP_DIR/output.txt"
grep -q '^t+5: status=Running notify=false$' "$TMP_DIR/output.txt"
grep -q '^t+7: status=Done notify=true$' "$TMP_DIR/output.txt"
cat "$TMP_DIR/output.txt"
echo "Completion confirmation check passed."
