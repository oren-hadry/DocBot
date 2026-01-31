#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${ROOT_DIR}/app"

cd "${APP_DIR}"

if [ ! -d ".dart_tool" ]; then
  flutter pub get
fi

if [ -f "assets/app_icon.png" ]; then
  dart run flutter_launcher_icons
fi

flutter run
