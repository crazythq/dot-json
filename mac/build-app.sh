#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# 由 SwiftPM 返回真实输出目录，避免把 CPU 架构和构建目录硬编码在脚本中。
swift build
BUILD_DIR="$(swift build --show-bin-path)"
APP_DIR="$BUILD_DIR/DotJSON.app"
BINARY="$BUILD_DIR/DotJSON"
BUNDLE="$BUILD_DIR/DotJSON_DotJSON.bundle"
INFO_PLIST="Info.plist"
ICNS="Sources/DotJSON/Resources/AppIcon.icns"

# 每次都重建 bundle，防止旧资源或旧 Info.plist 留在产物中。
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# 复制可执行文件、图标和 SwiftPM 资源 bundle。
cp "$BINARY" "$APP_DIR/Contents/MacOS/DotJSON"
chmod +x "$APP_DIR/Contents/MacOS/DotJSON"
cp "$ICNS" "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -d "$BUNDLE" ]]; then
    cp -R "$BUNDLE" "$APP_DIR/Contents/Resources/"
fi
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# 本地 ad-hoc 签名保证 Finder 可以稳定启动手工组装的 app bundle。
codesign --force --deep --sign - "$APP_DIR"

echo "✅ App bundle created at $APP_DIR"
echo "   open $APP_DIR"
