#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache build
architecture="$(uname -m)"
architectures=("$architecture")
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi
if [[ "${1:-}" == "--universal" ]]; then architectures=(arm64 x86_64); fi
compiler=(xcrun swiftc -swift-version 5 -module-cache-path .build/ModuleCache)
"${compiler[@]}" -target "${architecture}-apple-macosx13.0" Sources/KeyBehavior.swift Sources/KeyboardMapping.swift Sources/KeyRemapper.swift Sources/SessionState.swift Tests/*.swift -o .build/NoCapsChecks
.build/NoCapsChecks
# Cloud providers add bundle metadata that breaks signing; build the app locally.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/nocaps.XXXXXX")"
app_bundle="$staging_dir/NoCaps.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
binaries=()
for architecture in "${architectures[@]}"; do
    binary="$staging_dir/NoCaps-$architecture"
    "${compiler[@]}" -target "${architecture}-apple-macosx13.0" -O Sources/*.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$app_bundle/Contents/MacOS/NoCaps"
for architecture in "${architectures[@]}"; do
    xcrun lipo "$app_bundle/Contents/MacOS/NoCaps" -verify_arch "$architecture"
done
cp Info.plist "$app_bundle/Contents/Info.plist"
"${compiler[@]}" scripts/render-icons.swift -o .build/RenderIcons
.build/RenderIcons "$staging_dir/NoCaps.iconset" "$app_bundle/Contents/Resources/NoCapsMenu.pdf"
iconutil -c icns "$staging_dir/NoCaps.iconset" -o "$app_bundle/Contents/Resources/NoCaps.icns"
cp "$staging_dir/NoCaps.iconset/icon_512x512@2x.png" build/NoCaps.png
plutil -lint "$app_bundle/Contents/Info.plist"
if [[ "${CI:-false}" == "true" ]]; then
    # shortcut: CI uses ad hoc signing; add Developer ID and notarization for trusted distribution.
    nocaps_signing_identity="-"
else
    nocaps_signing_identity="$(security find-identity -v -p codesigning | awk '/"(Apple Development|Mac Developer|Developer ID Application):/ {print $2; exit}')"
    if [[ -z "$nocaps_signing_identity" ]]; then
        printf 'No signing certificate available; using ad hoc signing. Keyboard access may need to be granted again after rebuilding.\n' >&2
    fi
fi
codesign --force --sign "${nocaps_signing_identity:--}" --identifier app.nocaps.NoCaps "$app_bundle"
codesign --verify --strict "$app_bundle"
ditto -c -k --keepParent --norsrc --noextattr "$app_bundle" build/NoCaps.zip
(cd build && shasum -a 256 NoCaps.zip > NoCaps.zip.sha256)
printf '%s\n' "$app_bundle" > .build/app-path
printf 'Built %s\nArchive: %s/build/NoCaps.zip\n' "$app_bundle" "$PWD"
