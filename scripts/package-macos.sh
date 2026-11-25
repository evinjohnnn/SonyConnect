#!/usr/bin/env bash
# Package the macOS app for release: dist/Sound Connect.app and a .dmg.
#
#   ./scripts/package-macos.sh
#
# The app is universal (Apple silicon and Intel). The version comes from
# apps/macos/SonyCompanion/Support/Info.plist.
#
# Signing: set SIGN_IDENTITY to a codesigning identity. Without it the script
# uses the first "Developer ID Application" identity in the keychain, or signs
# ad hoc (for local use only) when there is none.
#
# Notarisation: set NOTARY_PROFILE to a profile saved with
#   xcrun notarytool store-credentials <profile>
# and the .dmg is notarised and stapled. Without it, notarisation is skipped.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pkg="$root/apps/macos/SonyCompanion"
dist="$root/dist"

app_name="Sound Connect"
exe_name="SoundConnect"
bundle_id="io.github.evinjohnnn.soundconnect"
plist_src="$pkg/Support/Info.plist"
pb=/usr/libexec/PlistBuddy

version="$("$pb" -c 'Print :CFBundleShortVersionString' "$plist_src")"
build="$("$pb" -c 'Print :CFBundleVersion' "$plist_src")"
echo "==> $app_name $version ($build)"

echo "==> building Rust core for arm64 and x86_64"
for t in aarch64-apple-darwin x86_64-apple-darwin; do
    cargo build --release --target "$t" --manifest-path "$root/core/Cargo.toml" -p mdr-ffi
done
universal="$root/core/target/universal"
mkdir -p "$universal"
lipo -create \
    "$root/core/target/aarch64-apple-darwin/release/libmdr_ffi.a" \
    "$root/core/target/x86_64-apple-darwin/release/libmdr_ffi.a" \
    -output "$universal/libmdr_ffi.a"

echo "==> building the app (release, universal)"
cd "$pkg"
export MDR_CORE_LIB_DIR="$universal"
swift_args=(-c release --arch arm64 --arch x86_64 --product SonyCompanionApp)
swift build "${swift_args[@]}"
bin="$(swift build "${swift_args[@]}" --show-bin-path)"

echo "==> assembling $app_name.app"
app="$dist/$app_name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/SonyCompanionApp" "$app/Contents/MacOS/$exe_name"
cp -R "$bin/SonyCompanion_SonyCompanionApp.bundle" "$app/Contents/Resources/"
cp "$pkg/Sources/SonyCompanionApp/Resources/AppIcon.icns" "$app/Contents/Resources/"
printf 'APPL????' > "$app/Contents/PkgInfo"

plist="$app/Contents/Info.plist"
cp "$plist_src" "$plist"
add() { "$pb" -c "Add :$1 $2 $3" "$plist"; }
add CFBundleIdentifier string "$bundle_id"
add CFBundleExecutable string "$exe_name"
add CFBundleIconFile string AppIcon
add CFBundlePackageType string APPL
add CFBundleInfoDictionaryVersion string 6.0
add CFBundleDevelopmentRegion string en
add LSMinimumSystemVersion string 26.0
add LSApplicationCategoryType string public.app-category.utilities
add NSPrincipalClass string NSApplication
add NSHighResolutionCapable bool true
add NSBluetoothAlwaysUsageDescription string \
    "Sound Connect talks to your headphones over Bluetooth to read and change their settings."
add NSHumanReadableCopyright string \
    "Free software under the GNU GPL v3. Not affiliated with Sony."
plutil -lint "$plist" >/dev/null

echo "==> signing"
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
    identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [[ -n "$identity" ]]; then
    sign=(codesign --force --timestamp --options runtime --sign "$identity")
else
    echo "    no Developer ID identity: signing ad hoc (this Mac only)"
    identity="-"
    sign=(codesign --force --sign -)
fi
"${sign[@]}" "$app/Contents/Resources/SonyCompanion_SonyCompanionApp.bundle"
"${sign[@]}" "$app"
codesign --verify --strict --deep "$app"

echo "==> making the disk image"
dmg="$dist/SoundConnect-$version.dmg"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "$app_name $version" -srcfolder "$stage" \
    -fs HFS+ -format UDZO "$dmg"
if [[ "$identity" != "-" ]]; then
    codesign --force --timestamp --sign "$identity" "$dmg"
fi

if [[ -n "${NOTARY_PROFILE:-}" && "$identity" != "-" ]]; then
    echo "==> notarising"
    xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$dmg"
else
    echo "    notarisation skipped (set NOTARY_PROFILE to notarise)"
fi

(cd "$dist" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "==> done"
echo "    app: $app"
echo "    dmg: $dmg"
