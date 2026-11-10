#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/ModuleCache build
architecture="$(uname -m)"
architectures=("$architecture")
release=false
for argument in "$@"; do
    case "$argument" in
        --universal) architectures=(arm64 x86_64) ;;
        --release) release=true ;;
        *) printf 'Usage: %s [--universal] [--release]\n' "$0" >&2; exit 2 ;;
    esac
done
nocaps_identity="$(openssl x509 -in signing/NoCaps.pem -noout -fingerprint -sha1 | cut -d= -f2 | tr -d :)"
nocaps_find_identity=(security find-identity -p codesigning)
nocaps_signing_options=(--timestamp=none)
if [[ -n "${NOCAPS_SIGNING_KEYCHAIN:-}" ]]; then
    nocaps_find_identity+=("$NOCAPS_SIGNING_KEYCHAIN")
    nocaps_signing_options+=(--keychain "$NOCAPS_SIGNING_KEYCHAIN")
fi
# Untrusted self-signed identities still provide stable identity; -v would omit them.
if [[ "${CI:-false}" == true && "$release" == false ]]; then
    nocaps_identity="-"
elif ! "${nocaps_find_identity[@]}" |
    awk -v identity="$nocaps_identity" '$2 == identity { found = 1 } END { exit !found }'; then
    if [[ "$release" == true ]]; then
        printf 'Release signing identity unavailable. Import the original NoCaps certificate and private key; refusing an ad hoc release.\n' >&2
        exit 1
    fi
    nocaps_identity="-"
fi
if [[ "$nocaps_identity" == "-" ]]; then
    printf 'Using ad hoc signing for this development build. Replacing the installed app may require granting keyboard access again.\n' >&2
fi
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
codesign --force --sign "$nocaps_identity" --identifier app.nocaps.NoCaps "${nocaps_signing_options[@]}" "$app_bundle"
codesign --verify --strict --all-architectures "$app_bundle"
if [[ "$nocaps_identity" != "-" ]]; then
    codesign --verify --strict --all-architectures \
        -R="identifier \"app.nocaps.NoCaps\" and certificate leaf = H\"$nocaps_identity\"" "$app_bundle"
fi
ditto -c -k --keepParent --norsrc --noextattr "$app_bundle" build/NoCaps.zip
(cd build && shasum -a 256 NoCaps.zip > NoCaps.zip.sha256)
printf '%s\n' "$app_bundle" > .build/app-path
printf 'Built %s\nArchive: %s/build/NoCaps.zip\n' "$app_bundle" "$PWD"
