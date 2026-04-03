#!/bin/bash
set -e

APP="LunaPad.app"
BINARY=".build/release/LunaPad"
ICON_SOURCE="assets/image.png"
ICONSET_DIR="$APP/Contents/Resources/LunaPad.iconset"
ICON_FILE="$APP/Contents/Resources/LunaPad.icns"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/LunaPad"

mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
rm -rf "$ICONSET_DIR"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>LunaPad</string>
    <key>CFBundleExecutable</key>
    <string>LunaPad</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.gkeane.LunaPad</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIconFile</key>
    <string>LunaPad</string>
    <key>CFBundleName</key>
    <string>LunaPad</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.0</string>
    <key>CFBundleVersion</key>
    <string>3</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txt</string>
                <string>text</string>
                <string>md</string>
                <string>markdown</string>
                <string>log</string>
                <string>json</string>
                <string>xml</string>
                <string>yaml</string>
                <string>yml</string>
                <string>toml</string>
                <string>csv</string>
                <string>tsv</string>
                <string>sh</string>
                <string>zsh</string>
                <string>bash</string>
                <string>swift</string>
                <string>js</string>
                <string>ts</string>
                <string>jsx</string>
                <string>tsx</string>
                <string>py</string>
                <string>rb</string>
                <string>java</string>
                <string>c</string>
                <string>h</string>
                <string>m</string>
                <string>mm</string>
                <string>cpp</string>
                <string>hpp</string>
                <string>css</string>
                <string>scss</string>
                <string>html</string>
                <string>htm</string>
                <string>sql</string>
                <string>ini</string>
                <string>conf</string>
                <string>cfg</string>
            </array>
            <key>CFBundleTypeName</key>
            <string>Text and Source Files</string>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>LSHandlerRank</key>
            <string>Default</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.text</string>
                <string>public.plain-text</string>
                <string>public.utf8-plain-text</string>
                <string>public.source-code</string>
                <string>public.log</string>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Built: $APP"
