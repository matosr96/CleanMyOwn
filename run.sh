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

# --- Firma ---------------------------------------------------------------
# Identidad estable (Apple Development / Developer ID) ⇒ el grant de FDA y
# la aprobación del asistente SOBREVIVEN a los rebuilds, y el helper exige
# a sus clientes XPC el mismo Team ID. Ad-hoc queda como último recurso.
# Override manual: CODESIGN_IDENTITY="..." ./run.sh
IDENTITY="${CODESIGN_IDENTITY:-auto}"
if [[ "$IDENTITY" == "auto" ]]; then
    if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
        IDENTITY="Developer ID Application"
    elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
        IDENTITY="Apple Development"
    else
        IDENTITY="-"
    fi
fi

if [[ "$IDENTITY" == "-" ]]; then
    echo "==> Firmando ad-hoc (sin identidad: FDA se invalida en cada rebuild)..."
    codesign --force --sign - "$APP/Contents/MacOS/$HELPER_NAME" >/dev/null
    codesign --force --sign - "$APP" >/dev/null
else
    echo "==> Firmando con: $IDENTITY"
    # Primero el helper (binario anidado), luego el bundle (sella recursos).
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
        "$APP/Contents/MacOS/$HELPER_NAME" >/dev/null
    codesign --force --options runtime --timestamp --sign "$IDENTITY" \
        "$APP" >/dev/null
fi
codesign --verify --strict "$APP"

# --- Notarización (sólo con Developer ID + Apple Developer Program) -------
# Prepara una vez:  xcrun notarytool store-credentials CleanMyOwnNotary \
#                     --apple-id <tu-apple-id> --team-id <team> --password <app-specific>
# Y luego:          ./run.sh --notarize
if [[ "${1:-}" == "--notarize" ]]; then
    if [[ "$IDENTITY" != Developer\ ID* ]]; then
        echo "ERROR: notarizar requiere 'Developer ID Application' (Apple Developer Program de pago)." >&2
        echo "       Identidad actual: $IDENTITY" >&2
        exit 1
    fi
    echo "==> Notarizando..."
    ZIP="$(mktemp -d)/CleanMyOwn.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile CleanMyOwnNotary --wait
    xcrun stapler staple "$APP"
fi

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
