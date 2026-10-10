#!/usr/bin/env bash
# Builds the universal (Apple Silicon and Intel) release app with the version
# embedded, and zips it into dist/ (spec §15).
#   scripts/build-app.sh <version>    e.g. 0.4.0 or 0.4.0-rc.2
set -euo pipefail

version=${1:?usage: build-app.sh <version>}
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
  echo "version must be X.Y.Z or X.Y.Z-suffix with no leading v, e.g. 0.4.0 or 0.4.0-rc.2; got '$version'" >&2
  exit 1
fi
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
derived=build/DerivedData
app="$derived/Build/Products/Release/LiveSplit One.app"
zip="dist/livesplit-one-macos-$version-macos-universal.zip"
# Bundle versions must be numbers, so candidates use the X.Y.Z part there.
# The full version goes in LSOVersion, which the app shows.
short=${version%%-*}

# Start from a clean build. With an earlier build's DerivedData, Xcode can
# skip the core build phase as up to date and link whatever LiveSplitCore/lib
# holds, such as debug or single-architecture Rust libraries.
rm -rf "$derived"
xcodegen generate
xcodebuild build \
  -project LiveSplitOne.xcodeproj -scheme LiveSplitOne -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$short" CURRENT_PROJECT_VERSION="$short" LSO_VERSION="$version"

# Check what is about to ship.
executable="$app/Contents/MacOS/LiveSplit One"
archs=$(lipo -archs "$executable")
if [[ "$archs" != *arm64* || "$archs" != *x86_64* ]]; then
  echo "expected arm64 and x86_64, got: $archs" >&2
  exit 1
fi
plist="$app/Contents/Info.plist"
for key in CFBundleShortVersionString:"$short" CFBundleVersion:"$short" \
  LSOVersion:"$version" CFBundleIdentifier:dev.alexcosta.livesplit-one-macos; do
  actual=$(/usr/libexec/PlistBuddy -c "Print :${key%%:*}" "$plist")
  if [[ "$actual" != "${key#*:}" ]]; then
    echo "${key%%:*} is '$actual', expected '${key#*:}'" >&2
    exit 1
  fi
done

mkdir -p dist
rm -f "$zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
ls dist
