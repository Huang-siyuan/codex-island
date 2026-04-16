#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
STORE="$ROOT_DIR/Sources/CodexIslandCore/SoundPreferenceStore.swift"
NOTIFICATIONS="$ROOT_DIR/Sources/CodexIslandCore/NotificationManager.swift"
VIEW="$ROOT_DIR/Sources/CodexIslandApp/IslandRootView.swift"
VIEW_MODEL="$ROOT_DIR/Sources/CodexIslandApp/IslandViewModel.swift"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$STORE" ]]; then
  echo "Missing SoundPreferenceStore.swift." >&2
  exit 1
fi

if ! rg -F -q 'toggleSoundEnabled' "$VIEW"; then
  echo "Hub mute button is not wired to toggleSoundEnabled." >&2
  exit 1
fi

if ! rg -F -q 'speaker.slash.fill' "$VIEW" || ! rg -F -q 'speaker.wave.2.fill' "$VIEW"; then
  echo "Hub is missing the mute/unmute button icons." >&2
  exit 1
fi

if ! rg -F -q 'soundPreferenceStore.isSoundEnabled' "$NOTIFICATIONS"; then
  echo "NotificationManager is not respecting the sound preference." >&2
  exit 1
fi

if ! rg -F -q '@Published var isSoundEnabled' "$VIEW_MODEL"; then
  echo "IslandViewModel is missing isSoundEnabled state." >&2
  exit 1
fi

cat > "$TMP_DIR/main.swift" <<'EOF'
import Foundation

@main
struct SoundPreferenceProbe {
    static func main() {
        let suiteName = "check-sound-toggle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let store = SoundPreferenceStore(userDefaults: defaults)
        print("default=\(store.isSoundEnabled)")
        print("afterToggle=\(store.toggleSoundEnabled())")
        print("persisted=\(SoundPreferenceStore(userDefaults: defaults).isSoundEnabled)")
    }
}
EOF

swiftc \
  -parse-as-library \
  -o "$TMP_DIR/sound-preference-probe" \
  "$STORE" \
  "$TMP_DIR/main.swift"

"$TMP_DIR/sound-preference-probe" > "$TMP_DIR/output.txt"
grep -q '^default=true$' "$TMP_DIR/output.txt"
grep -q '^afterToggle=false$' "$TMP_DIR/output.txt"
grep -q '^persisted=false$' "$TMP_DIR/output.txt"
cat "$TMP_DIR/output.txt"
echo "Sound toggle check passed."
