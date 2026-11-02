#!/bin/bash
# Builds build/NotchApp.app. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

BUNDLE_ID=com.hamza.notchapp
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP=build/NotchApp.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchApp" "$APP/Contents/MacOS/NotchApp"
cp "$BIN_DIR/NotchHook" "$APP/Contents/MacOS/notch-hook"
cp Support/Info.plist "$APP/Contents/Info.plist"

# /usr/bin/perl runs as arm64e, so the bridge needs an arm64e slice.
clang -dynamiclib -fobjc-arc -O2 -arch arm64 -arch arm64e -mmacosx-version-min=14.0 \
    -framework Foundation Bridge/MediaRemoteBridge.m \
    -o "$APP/Contents/Resources/libNotchMediaBridge.dylib"

# A stable identity keeps macOS permissions across rebuilds (see Support/create-signing-identity.sh);
# without it, fall back to ad-hoc signing and re-grant permissions after each build.
IDENTITY="NotchApp Local Signing"
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 || IDENTITY="-"
codesign --force --sign "$IDENTITY" "$APP/Contents/Resources/libNotchMediaBridge.dylib"
codesign --force --sign "$IDENTITY" "$APP/Contents/MacOS/notch-hook"
codesign --force --sign "$IDENTITY" "$APP"
echo "Signed with: $IDENTITY"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST=/Applications/NotchApp.app
    if [[ -d "$DEST" ]] && [[ "$(defaults read "$DEST/Contents/Info" CFBundleIdentifier 2>/dev/null)" != "$BUNDLE_ID" ]]; then
        echo "Refusing to replace $DEST: it is a different app." >&2
        exit 1
    fi
    pkill -x NotchApp 2>/dev/null || true
    # Let the old process exit fully, or `open` can fail with LaunchServices error -600.
    while pgrep -x NotchApp >/dev/null; do sleep 0.2; done
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "Installed to $DEST"
fi
