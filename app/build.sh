#!/bin/bash
#
# Builds "Apple Labs.app" (a universal SwiftUI launcher) into app/build.
#
#   app/build.sh            build only
#   app/build.sh --install  build, install to ~/Applications and register it
#                           as the handler for roblox:// links
#   app/build.sh --zip      build and zip it for a GitHub release
#
# Needs the Xcode command line tools (swiftc).

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
out="$here/build"
app="$out/Apple Labs.app"
# The bootstrapper script; the app carries a copy under its command name.
script="$root/Apple Labs"
version="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$script")"

rm -rf "$out"
mkdir -p "$out" "$app/Contents/MacOS" "$app/Contents/Resources"

for arch in arm64 x86_64; do
  echo "==> Compiling for $arch"
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$arch-apple-macos13.0" \
    -o "$out/RobloxBootstrapper-$arch" \
    "$here"/Sources/*.swift
done
lipo -create -output "$app/Contents/MacOS/RobloxBootstrapper" \
  "$out/RobloxBootstrapper-arm64" "$out/RobloxBootstrapper-x86_64"
rm -f "$out"/RobloxBootstrapper-*

echo "==> Drawing the app icon"
swiftc -O "$here/make-icon.swift" -o "$out/make-icon"
"$out/make-icon" "$out/AppIcon.iconset"
iconutil -c icns "$out/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
rm -rf "$out/make-icon" "$out/AppIcon.iconset"

sed "s/__VERSION__/$version/g" "$here/Info.plist" > "$app/Contents/Info.plist"
cp "$script" "$app/Contents/Resources/roblox-bootstrapper"
chmod +x "$app/Contents/Resources/roblox-bootstrapper"
printf 'APPL????' > "$app/Contents/PkgInfo"

codesign --force --deep --sign - "$app"
echo "==> Built $app ($version)"

case "${1:-}" in
  --install)
    dest="$HOME/Applications/Apple Labs.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$dest"
    ditto "$app" "$dest"
    # register re-signs the app and takes over roblox:// links.
    "$dest/Contents/Resources/roblox-bootstrapper" register
    ;;
  --zip)
    (cd "$out" && ditto -c -k --keepParent "Apple Labs.app" "Apple-Labs.zip")
    echo "==> $out/Apple-Labs.zip"
    ;;
esac
