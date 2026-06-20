#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GUI_DIR="$PROJECT_DIR/gui"
TRACE_DIR="$PROJECT_DIR/.traces"
DURATION="120s"

mkdir -p "$TRACE_DIR"

echo "=== Building current version ==="
xcodebuild build -scheme TokenDashboard -destination 'platform=macOS' \
  -derivedDataPath "$GUI_DIR/.build-current" \
  -quiet 2>/dev/null

APP_PATH=$(find "$GUI_DIR/.build-current" -name "TokenDashboard" -type f -path "*/Debug/*" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: Could not find built app"
    exit 1
fi

echo "=== Found app: $APP_PATH ==="
echo "=== Recording Allocations for $DURATION ==="
xcrun xctrace record \
  --template Allocations \
  --launch -- "$APP_PATH" \
  --time-limit "$DURATION" \
  --output "$TRACE_DIR/current.trace" \
  --no-prompt

echo ""
echo "=== Trace saved to $TRACE_DIR/current.trace ==="
echo "Open in Instruments: open $TRACE_DIR/current.trace"
echo ""
echo "To compare with a previous version:"
echo "  1. mv $TRACE_DIR/current.trace $TRACE_DIR/before.trace"
echo "  2. Apply optimizations and re-run this script"
echo "  3. Open both .trace files in Instruments to compare"
