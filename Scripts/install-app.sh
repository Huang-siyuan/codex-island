#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
APP_NAME="Codex Island"
INSTALL_DIR="$HOME/Applications"
OPEN_AFTER_INSTALL=0

usage() {
  cat <<'EOF'
Usage: ./Scripts/install-app.sh [--debug|--release] [--open] [--install-dir <path>]

Options:
  --debug              Build and install the debug app bundle
  --release            Build and install the release app bundle (default)
  --open               Launch the installed app after copying
  --install-dir <dir>  Install destination (default: ~/Applications)
  --help               Show this help text
EOF
}

PACKAGE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug|--release)
      PACKAGE_ARGS+=("$1")
      ;;
    --open)
      OPEN_AFTER_INSTALL=1
      ;;
    --install-dir)
      shift
      INSTALL_DIR="${1:?missing value for --install-dir}"
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

"$ROOT_DIR/Scripts/package-app.sh" "${PACKAGE_ARGS[@]}"

SOURCE_APP="$ROOT_DIR/dist/$APP_NAME.app"
TARGET_APP="$INSTALL_DIR/$APP_NAME.app"
APP_EXECUTABLE="CodexIslandApp"

mkdir -p "$INSTALL_DIR"
pkill -x "$APP_EXECUTABLE" 2>/dev/null || true
rm -rf "$TARGET_APP"
ditto "$SOURCE_APP" "$TARGET_APP"

echo "Installed app bundle:"
echo "  $TARGET_APP"

if (( OPEN_AFTER_INSTALL )); then
  open "$TARGET_APP"
fi
