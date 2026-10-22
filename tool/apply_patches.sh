#!/usr/bin/env bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_DIR/patch_media_kit_linux.sh"
bash "$SCRIPT_DIR/patch_volume_controller.sh"
echo "All patches applied"
