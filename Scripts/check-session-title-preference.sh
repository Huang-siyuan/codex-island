#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 - <<'PY' > "$TMP_DIR/mismatch.json"
import json
import pathlib
import sqlite3

state = pathlib.Path.home() / ".codex" / "state_5.sqlite"
index = pathlib.Path.home() / ".codex" / "session_index.jsonl"

conn = sqlite3.connect(state)
rows = conn.execute(
    """
    select id, title
    from threads
    where archived = 0
    order by updated_at desc
    limit 30
    """
).fetchall()

index_titles = {}
for line in index.read_text().splitlines():
    if not line.strip():
        continue
    payload = json.loads(line)
    thread_name = payload.get("thread_name")
    if thread_name:
        index_titles[payload["id"]] = thread_name

for thread_id, state_title in rows:
    override = index_titles.get(thread_id)
    if override and override != state_title:
        print(json.dumps({"thread_id": thread_id, "expected_title": override}, ensure_ascii=False))
        break
else:
    raise SystemExit("No recent mismatch found between sqlite title and session_index thread_name.")
PY

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

let threadID = ProcessInfo.processInfo.environment["THREAD_ID"]!
let store = CodexStateStore()
let threads = try store.fetchRecentThreads(limit: 30)
guard let snapshot = threads.first(where: { $0.threadID == threadID }) else {
    fputs("Missing thread in store output.\n", stderr)
    exit(1)
}
print(snapshot.title)
EOF

swiftc \
  -o "$TMP_DIR/title-probe" \
  "$ROOT_DIR/Sources/CodexIslandCore/AppEnvironment.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/CodexModels.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionIndexParser.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/SessionIndexReader.swift" \
  "$ROOT_DIR/Sources/CodexIslandCore/CodexStateStore.swift" \
  "$TMP_DIR/main.swift"

thread_id="$(python3 - <<'PY' "$TMP_DIR/mismatch.json"
import json, sys
print(json.load(open(sys.argv[1]))["thread_id"])
PY
)"

expected_title="$(python3 - <<'PY' "$TMP_DIR/mismatch.json"
import json, sys
print(json.load(open(sys.argv[1]))["expected_title"])
PY
)"

actual_title="$(THREAD_ID="$thread_id" "$TMP_DIR/title-probe")"

if [[ "$actual_title" != "$expected_title" ]]; then
  echo "Expected store title override '$expected_title' but got '$actual_title'." >&2
  exit 1
fi

echo "Session title preference check passed."
