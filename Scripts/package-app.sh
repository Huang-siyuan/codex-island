#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"

APP_NAME="Codex Island"
PRODUCT_NAME="CodexIslandApp"
CONFIGURATION="release"
OPEN_AFTER_BUILD=0
OUTPUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
PLIST_PATH="$ROOT_DIR/Packaging/Info.plist"
ICON_NAME="CodexIsland"
ICON_SCRIPT="$ROOT_DIR/Scripts/render-app-icon.swift"

usage() {
  cat <<'EOF'
Usage: ./Scripts/package-app.sh [--debug|--release] [--open] [--output-dir <path>]

Options:
  --debug             Package the debug build instead of release
  --release           Package the release build (default)
  --open              Launch the packaged app after bundling
  --output-dir <path> Write the .app bundle to a custom directory
  --help              Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      CONFIGURATION="debug"
      ;;
    --release)
      CONFIGURATION="release"
      ;;
    --open)
      OPEN_AFTER_BUILD=1
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:?missing value for --output-dir}"
      APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

cd "$ROOT_DIR"

echo "Building $PRODUCT_NAME ($CONFIGURATION)..."
swift build -c "$CONFIGURATION" --product "$PRODUCT_NAME"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
  echo "Built executable not found at: $BIN_PATH" >&2
  exit 1
fi

/usr/bin/plutil -lint "$PLIST_PATH" >/dev/null

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$PRODUCT_NAME"
cp "$PLIST_PATH" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-island-iconset.XXXXXX")"
ICONSET_DIR="$TEMP_DIR/$ICON_NAME.iconset"
MASTER_ICON="$ICONSET_DIR/master.png"

cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$ICONSET_DIR"
swift "$ICON_SCRIPT" "$MASTER_ICON"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  read -r size filename <<< "$spec"
  sips -z "$size" "$size" "$MASTER_ICON" --out "$ICONSET_DIR/$filename" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/$ICON_NAME.icns"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Packaged app bundle:"
echo "  $APP_DIR"

if (( OPEN_AFTER_BUILD )); then
  open "$APP_DIR"
fi
