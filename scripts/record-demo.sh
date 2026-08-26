#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v vhs >/dev/null 2>&1; then
    echo "⚠️  VHS is not installed."
    echo "To install on macOS:  brew install vhs"
    echo "To install on Linux:  sudo apt install vhs (or via go install github.com/charmbracelet/vhs@latest)"
    exit 1
fi

echo "🎬 Recording terminal demo with VHS..."
cd "${SCRIPT_DIR}"
vhs .github/assets/demo.tape
echo "✅ Demo recorded: .github/assets/demo.gif and .github/assets/demo.mp4"
