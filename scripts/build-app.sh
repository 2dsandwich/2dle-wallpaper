#!/bin/zsh
# Builds build/2dle.app from the Swift package. Pass --install to copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
swift scripts/make-icon.swift Resources/fonts/ComforterBrush-Regular.ttf build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
APP=build/2dle.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/2dle "$APP/Contents/MacOS/2dle"
cp -R Resources/textures Resources/models Resources/hdri Resources/backdrops Resources/fonts Resources/CREDITS.txt "$APP/Contents/Resources/"
cp -R Resources/sounds "$APP/Contents/Resources/"
cp build/AppIcon.icns "$APP/Contents/Resources/"
# Cache record previews in the app bundle so the menu can show them immediately.
.build/release/2dle --snapshot build/record-previews --record-previews
cp -R build/record-previews "$APP/Contents/Resources/"
# The menu shows stills of every scene, turntable and clock; they are made here, once.
rm -rf build/menu-previews
.build/release/2dle --snapshot build/menu-previews --menu-previews
cp -R build/menu-previews "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>2dle</string>
    <key>CFBundleDisplayName</key><string>2dle</string>
    <key>CFBundleIdentifier</key><string>app.spindle.Spindle.core</string>
    <key>CFBundleExecutable</key><string>2dle</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>We'd love to see what you're playing, so the record on your desk can spin along! We only read the song and its cover, and press play, pause or skip when you ask.</string>
</dict>
</plist>
PLIST

# A real signing identity keeps the Spotify permission across rebuilds; fall back to ad-hoc. Everyday builds prefer the
# Apple Development certificate; scripts/release.sh passes SPINDLE_IDENTITY, the Developer ID one.
pick() { security find-identity -v -p codesigning | awk -F'"' -v kind="$1" 'index($0, kind) {print $2; exit}'; }
IDENTITY=${SPINDLE_IDENTITY:-$(pick "Apple Development")}
[[ -n "$IDENTITY" ]] || IDENTITY=$(pick "Developer ID Application")
SIGN=(--force --sign "$IDENTITY")
RUNTIME=()
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    # For people downloading it: the hardened runtime and a timestamp, which notarising needs, and the entitlements the
    # runtime asks for before the app may talk to the music apps or ask where the Mac is. The screen saver inside is
    # signed again the same way, since notarising looks at everything in the bundle.
    SIGN+=(--options runtime --timestamp)
    plutil -convert xml1 -o build/2dle-release.entitlements scripts/2dle-release.entitlements
    RUNTIME=(--entitlements build/2dle-release.entitlements)
    codesign "${SIGN[@]}" "$APP/Contents/Resources/2dle.saver"
fi
if [[ -n "${SPINDLE_PROFILE:-}" ]]; then
    # Only when asked: signed for Sign in with Apple, with SPINDLE_PROFILE the macOS provisioning profile
    # (.provisionprofile) for app.spindle.Spindle with that capability, and SPINDLE_IDENTITY the certificate it names
    # if it is not the first one found. No falling back to ad-hoc here: an app claiming the entitlement without its
    # profile will not start.
    PROFILE_PLIST=build/profile.plist ENTITLEMENTS=build/2dle-signed.entitlements
    security cms -D -i "$SPINDLE_PROFILE" > "$PROFILE_PLIST"
    APPID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$PROFILE_PLIST")
    TEAM=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$PROFILE_PLIST")
    if [[ "$APPID" != "$TEAM.app.spindle.Spindle" ]] || ! /usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.applesignin" "$PROFILE_PLIST" >/dev/null 2>&1; then
        echo "That profile is not for app.spindle.Spindle with Sign in with Apple ($APPID)." >&2; exit 1
    fi
    plutil -convert xml1 -o "$ENTITLEMENTS" scripts/2dle.entitlements
    /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APPID" -c "Add :com.apple.developer.team-identifier string $TEAM" "$ENTITLEMENTS"
    (( ${#RUNTIME} )) && /usr/libexec/PlistBuddy -c "Merge build/2dle-release.entitlements" "$ENTITLEMENTS"
    cp "$SPINDLE_PROFILE" "$APP/Contents/embedded.provisionprofile"
    codesign "${SIGN[@]}" --entitlements "$ENTITLEMENTS" "$APP"
    echo "Signed with: $IDENTITY, for Sign in with Apple"
elif (( ${#RUNTIME} )); then
    # No falling back to ad-hoc for a release: a failed signature (a timestamp needs the internet) stops the build.
    codesign "${SIGN[@]}" "${RUNTIME[@]}" "$APP"
    echo "Signed with: $IDENTITY, hardened runtime"
elif [[ -n "$IDENTITY" ]] && codesign "${SIGN[@]}" "$APP" 2>/dev/null; then
    echo "Signed with: $IDENTITY"
else
    codesign --force --sign - "$APP"
    echo "Signed ad-hoc"
fi

if [[ "${1:-}" == "--install" ]]; then
    # (/Applications, beside the full app's ~/Applications/2dle.app: same name, its own bundle id and settings.)
    rm -rf /Applications/2dle.app
    cp -R "$APP" /Applications/2dle.app
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    "$LSREGISTER" -u "$PWD/$APP" >/dev/null 2>&1 || true
    "$LSREGISTER" -f /Applications/2dle.app >/dev/null 2>&1 || true
    echo "Installed to /Applications/2dle.app."
fi
echo "Built $APP"
