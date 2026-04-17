#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_NAME="Codex Island"
OUTPUT_DIR="$ROOT_DIR/dist"
ZIP_NAME="$APP_NAME.app.zip"
OPEN_AFTER_BUILD=0
REVEAL_AFTER_BUILD=0

PACKAGE_ARGS=()

usage() {
  cat <<'EOF'
Usage: ./Scripts/release-zip.sh [--debug|--release] [--output-dir <path>] [--zip-name <name>] [--open] [--reveal]

Options:
  --debug              Build the debug app bundle before zipping
  --release            Build the release app bundle before zipping (default)
  --output-dir <path>  Directory for the packaged app and distributable zip
  --zip-name <name>    Zip file name (default: Codex Island.app.zip)
  --open               Open the output directory in Finder after packaging
  --reveal             Reveal the generated zip in Finder after packaging
  --help               Show this help text
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug|--release)
      PACKAGE_ARGS+=("$1")
      ;;
    --output-dir)
      shift
      OUTPUT_DIR="${1:?missing value for --output-dir}"
      ;;
    --zip-name)
      shift
      ZIP_NAME="${1:?missing value for --zip-name}"
      ;;
    --open)
      OPEN_AFTER_BUILD=1
      ;;
    --reveal)
      REVEAL_AFTER_BUILD=1
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

"$ROOT_DIR/Scripts/package-app.sh" "${PACKAGE_ARGS[@]}" --output-dir "$OUTPUT_DIR"

APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Packaged app bundle not found at: $APP_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -f "$ZIP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Created distributable zip:"
echo "  $ZIP_PATH"

if (( REVEAL_AFTER_BUILD )); then
  open -R "$ZIP_PATH"
elif (( OPEN_AFTER_BUILD )); then
  open "$OUTPUT_DIR"
fi
