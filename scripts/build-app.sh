#!/usr/bin/env bash
# Build archer as a real macOS .app bundle (no Xcode project required).
#
# What this does:
#   1. swift build -c release
#   2. Assemble dist/Archer.app/Contents/{MacOS,Resources,Info.plist,PkgInfo}
#   3. Copy Archer + ArcherHook binaries + the SPM resource bundle into MacOS/
#      (Bundle.module looks next to the executable, which is why fonts +
#      icons live alongside the binary, not under Resources/)
#   4. Generate Info.plist with CFBundleShortVersionString sourced from
#      Sources/ArcherKit/App/AppInfo.swift's displayVersion — single source
#      of truth, no manual sync
#   5. Adhoc codesign so Gatekeeper doesn't kill it on first launch
#
# Output: dist/Archer.app — open it directly or drop into /Applications.
# This is local-distribution-only. Codesigning + notarization for public
# release is a separate step (requires Apple Developer ID).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Pull displayVersion from AppInfo.swift so About + Info.plist stay in sync.
VERSION="$(grep -E 'static let displayVersion' Sources/ArcherKit/App/AppInfo.swift \
    | sed -E 's/.*= "([^"]+)".*/\1/')"
if [ -z "$VERSION" ]; then
    echo "build-app.sh: failed to extract displayVersion from AppInfo.swift" >&2
    exit 1
fi

BUNDLE_ID="com.archsueh.archer"
APP_NAME="Archer"
APP="dist/${APP_NAME}.app"

echo "==> Building release config"
swift build -c release

echo "==> Verifying build artifacts"
for f in .build/release/Archer .build/release/ArcherHook; do
    [ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
[ -d ".build/release/Archer_ArcherKit.bundle" ] || {
    echo "missing SPM resource bundle: .build/release/Archer_ArcherKit.bundle" >&2
    exit 1
}

echo "==> Assembling ${APP} (v${VERSION})"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS"
mkdir -p "${APP}/Contents/Resources"

cp .build/release/Archer "${APP}/Contents/MacOS/${APP_NAME}"
cp .build/release/ArcherHook "${APP}/Contents/MacOS/ArcherHook"

# [archer] Vendored showagent (aytzey/showagent) Go binary — sits
# next to the app executable so the bridge resolves it via
# Bundle.main.executableURL. Git-ignored under Vendor/.
if [ -f "Vendor/showagent/showagent" ]; then
    echo "==> Embedding showagent binary"
    cp Vendor/showagent/showagent "${APP}/Contents/MacOS/showagent"
    chmod +x "${APP}/Contents/MacOS/showagent"
fi

# Sparkle.framework — SwiftPM resolves and copies it next to the build
# products but (unlike Xcode's "Embed Frameworks" phase) does nothing to get
# it into an app bundle. Embed it under Contents/Frameworks and add the
# matching rpath so the `@rpath/Sparkle.framework/...` load command in the
# Archer binary resolves at runtime.
echo "==> Embedding Sparkle.framework"
mkdir -p "${APP}/Contents/Frameworks"
cp -R .build/release/Sparkle.framework "${APP}/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP}/Contents/MacOS/${APP_NAME}"
# Bundle.module's first lookup candidate is `Bundle.main.resourceURL`
# (= Contents/Resources/), so the resource bundle has to live there or
# the running .app will silently fall back to .build/release/ on disk.
cp -R .build/release/Archer_ArcherKit.bundle "${APP}/Contents/Resources/"

# App icon — generated from branding/AppIcon.png if present. macOS reads
# .icns from CFBundleIconFile in Info.plist; we synthesize the multi-size
# .iconset via sips, then iconutil packs it. Without a source PNG we ship
# without an icon and the OS falls back to the generic blank-document.
# Pick the largest available source from branding/icons/ — asset catalog
# format names the 1024px slot `icon-512@2x.png`. Fall back to a flat
# `icon-1024.png` (older convention) then to legacy `branding/AppIcon.png`.
for cand in branding/icons/icon-512@2x.png branding/icons/icon-1024.png branding/AppIcon.png; do
    if [ -f "$cand" ]; then
        ICON_SOURCE="$cand"
        break
    fi
done
if [ -f "$ICON_SOURCE" ]; then
    echo "==> Building AppIcon.icns from ${ICON_SOURCE}"
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$ICONSET"
    # Apple's required sizes for an .icns: 16/32/128/256/512 in @1x and @2x.
    # sips resamples cleanly enough for a flat brand mark; for fine detail
    # design, hand-export from Figma/Sketch is preferred.
    for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" \
                "32:icon_32x32.png" "64:icon_32x32@2x.png" \
                "128:icon_128x128.png" "256:icon_128x128@2x.png" \
                "256:icon_256x256.png" "512:icon_256x256@2x.png" \
                "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
        size="${spec%%:*}"
        name="${spec##*:}"
        sips -z "$size" "$size" "$ICON_SOURCE" --out "${ICONSET}/${name}" >/dev/null
    done
    iconutil -c icns -o "${APP}/Contents/Resources/AppIcon.icns" "$ICONSET"
    rm -rf "$(dirname "$ICONSET")"
    APPLE_ICON_PLIST_KEYS=$(cat <<'KEYS'
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
KEYS
    )
else
    APPLE_ICON_PLIST_KEYS=""
fi

# SPM ships the resource bundle as a flat directory, but its `.bundle` suffix
# triggers codesign's bundle validator → "bundle format invalid". Promote it
# to the canonical macOS bundle layout (Contents/Info.plist +
# Contents/Resources/*) so codesign accepts it. Bundle.module still resolves
# fonts/icons via its standard resourcePath lookup.
RES_BUNDLE="${APP}/Contents/Resources/Archer_ArcherKit.bundle"
mkdir -p "${RES_BUNDLE}/Contents/Resources"
pushd "${RES_BUNDLE}" >/dev/null
# Move *all* bundle contents, including localizations (e.g. *.lproj), into
# Contents/Resources/. A narrower glob leaves stray files in the bundle root
# and triggers `unsealed contents present in the bundle root`.
shopt -s dotglob nullglob
for entry in *; do
  case "$entry" in
    Contents) continue ;;
    *) mv -f "$entry" "Contents/Resources/" ;;
  esac
done
shopt -u dotglob nullglob
popd >/dev/null
# Include xcstrings resources as well (localizations).
find "${APP}/Contents/Resources" -maxdepth 1 -type d -name "*.lproj" -exec rm -rf {} + 2>/dev/null || true
cat > "${RES_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}.resources</string>
    <key>CFBundleName</key>
    <string>Archer_ArcherKit</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
</dict>
</plist>
PLIST

# PkgInfo: 4-byte CFBundlePackageType + 4-byte CFBundleSignature.
# Modern macOS doesn't require it but Finder still uses it for some legacy
# checks; harmless 8 bytes.
printf 'APPL????' > "${APP}/Contents/PkgInfo"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/archsueh/archer/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>R8F+0R9LBA/JibvArSfUthDyrOFswtmgqMxeOEDbnvE=</string>
    <key>SUEnableAutomaticChecks</key>
    <false/>
${APPLE_ICON_PLIST_KEYS}
</dict>
</plist>
PLIST

# Compile the String Catalog into Contents/Resources/<locale>.lproj so the
# .app carries real localizations (Bundle.main) and the per-app language
# picker appears in System Settings. SwiftPM won't do this for .xcstrings.
echo "==> Generating localizations into ${APP}/Contents/Resources"
bash "$ROOT/scripts/gen-localizations.sh" "${APP}/Contents/Resources"

echo "==> Adhoc codesign (skips Gatekeeper kill on first launch)"
# Adhoc signature ('-') is enough for personal-machine launches without a
# Developer ID. Public distribution still needs a real cert + notarytool.
# Adding --entitlements with "Unspecified: true" to avoid hardened runtime
# sandbox authorization check failures that can stall the build on macOS 26+.
# Sign inside-out: inner resource bundle first, then binaries, then the
# .app — each layer wants its descendants already signed before signing
# itself.
ENTITLEMENTS="$(mktemp -d)/entitlements.plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.get-task-allow</key>
    <true/>
    <key>com.apple.security.cs.debugger</key>
    <true/>
    <key>com.apple.security.cs.anti-tamper</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.app-launcher</key>
    <true/>
</dict>
</plist>
PLIST
codesign --force --sign - --entitlements "$ENTITLEMENTS" "${APP}/Contents/Resources/Archer_ArcherKit.bundle"
# Sparkle ships its XPC services / Autoupdate / Updater.app already signed;
# sign only the outer framework wrapper so those nested signatures survive.
codesign --force --sign - "${APP}/Contents/Frameworks/Sparkle.framework"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "${APP}/Contents/MacOS/${APP_NAME}"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "${APP}/Contents/MacOS/ArcherHook"
codesign --force --sign - --entitlements "$ENTITLEMENTS" "${APP}" 2>&1 | tail -3
rm -rf "$(dirname "$ENTITLEMENTS")"

echo ""
echo "✓ Built ${APP} (v${VERSION})"
echo "  open ${APP}              # launch"
echo "  cp -R ${APP} /Applications  # install"
