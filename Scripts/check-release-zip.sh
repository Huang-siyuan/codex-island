#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-island-release-zip.XXXXXX")"
OUTPUT_DIR="$TEMP_DIR/out"
ZIP_PATH="$OUTPUT_DIR/Codex Island.app.zip"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

"$ROOT_DIR/Scripts/release-zip.sh" --output-dir "$OUTPUT_DIR" >/dev/null

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Expected zip was not created at: $ZIP_PATH" >&2
  exit 1
fi

ZIP_LISTING="$(zipinfo -1 "$ZIP_PATH")"

if ! grep -Fxq "Codex Island.app/Contents/Info.plist" <<<"$ZIP_LISTING"; then
  echo "Zip archive does not contain the app Info.plist." >&2
  exit 1
fi

if ! grep -Fxq "Codex Island.app/Contents/MacOS/CodexIslandApp" <<<"$ZIP_LISTING"; then
  echo "Zip archive does not contain the app executable." >&2
  exit 1
fi

echo "Release zip check passed."
