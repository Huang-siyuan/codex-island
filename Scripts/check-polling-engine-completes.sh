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
    print("thread=\(result.snapshot.threadTitle)")
    print("status=\(result.snapshot.statusText)")
    semaphore.signal()
}

_ = semaphore.wait(timeout: .now() + 30)
EOF

swiftc \
  -o "$TMP_DIR/polling-probe" \
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

"$TMP_DIR/polling-probe" > "$TMP_DIR/output.txt" 2>&1 &
PROBE_PID=$!

for _ in {1..80}; do
  if ! kill -0 "$PROBE_PID" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if kill -0 "$PROBE_PID" 2>/dev/null; then
  kill "$PROBE_PID" 2>/dev/null || true
  wait "$PROBE_PID" 2>/dev/null || true
  echo "PollingEngine.pollOnce() did not finish within 8 seconds." >&2
  exit 1
fi

wait "$PROBE_PID"
grep -q '^status=' "$TMP_DIR/output.txt"
cat "$TMP_DIR/output.txt"
echo "PollingEngine completed within 8 seconds."
