#!/usr/bin/env bash
# Build, package, sign and launch CleanMyOwn as a real macOS .app bundle.
set -euo pipefail

cd "$(dirname "$0")"

APP="CleanMyOwn.app"
BIN_NAME="CleanMyOwn"
HELPER_NAME="CleanMyOwnHelper"
HELPER_LABEL="com.matos.CleanMyOwn.helper"
CONFIG="${CONFIG:-release}"

echo "==> Compilando ($CONFIG)..."
swift build -c "$CONFIG"

# --show-bin-path resuelve la triple de la máquina (arm64 o x86_64)
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN_PATH="$BIN_DIR/$BIN_NAME"
HELPER_PATH="$BIN_DIR/$HELPER_NAME"
if [[ ! -x "$BIN_PATH" || ! -x "$HELPER_PATH" ]]; then
    echo "ERROR: binarios no encontrados en $BIN_DIR" >&2
    exit 1
fi

echo "==> Armando $APP ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp "$HELPER_PATH" "$APP/Contents/MacOS/$HELPER_NAME"

# Plist del daemon privilegiado (registrable con SMAppService.daemon).
# BundleProgram es relativo a la raíz del bundle.
cat > "$APP/Contents/Library/LaunchDaemons/$HELPER_LABEL.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$HELPER_LABEL</string>
    <key>BundleProgram</key><string>Contents/MacOS/$HELPER_NAME</string>
    <key>MachServices</key>
    <dict>
        <key>$HELPER_LABEL</key><true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>com.matos.CleanMyOwn</string>
    </array>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>CleanMyOwn</string>
    <key>CFBundleDisplayName</key><string>CleanMyOwn</string>
    <key>CFBundleIdentifier</key><string>com.matos.CleanMyOwn</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>CleanMyOwn</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <!-- Sin sudden/automatic termination: macOS podría matar la app en mitad
         de un borrado o una operación privilegiada al cerrar sesión. -->
</dict>
</plist>
PLIST

echo "==> Firmando ad-hoc..."
codesign --force --deep --sign - "$APP" >/dev/null

echo "==> Cerrando instancia previa si existe..."
pkill -x "$BIN_NAME" 2>/dev/null || true
sleep 0.5

echo "==> Lanzando..."
open "$APP"
sleep 1

if pgrep -f "$APP/Contents/MacOS/$BIN_NAME" >/dev/null; then
    echo "✅ CleanMyOwn está corriendo."
else
    echo "❌ No se pudo lanzar." >&2
    exit 1
fi
