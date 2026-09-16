#!/bin/bash
# 打包脚本：把 SwiftPM release 产物组装成可双击运行的 FloatingTodo.app
set -euo pipefail
cd "$(dirname "$0")"

MODULE_CACHE="$PWD/.build/ModuleCache"
mkdir -p "$MODULE_CACHE"
env \
  CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
  SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE" \
  swift build --disable-sandbox --build-system native -c release "$@"

APP="FloatingTodo.app"
BIN=".build/release/FloatingTodo"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FloatingTodo"
cp "Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>FloatingTodo</string>
	<key>CFBundleIdentifier</key>
	<!-- 注意：不要改回 local.tools.FloatingTodo。macOS 26 的菜单栏布局按 bundle ID 持久记忆，
	     旧 ID 在系统里存了一个屏幕外的坏位置，会导致状态栏图标永远不可见。 -->
	<string>local.tools.FloatingTodo2</string>
	<key>CFBundleName</key>
	<string>FloatingTodo</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

# ad-hoc 签名，避免本机 Gatekeeper/权限问题
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "已生成 ${APP}，可拖入「应用程序」并加入登录项。"
