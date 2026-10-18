#!/bin/bash
# Builds the demo and runs it in the iOS Simulator without Xcode's build
# system — for when Xcode cannot build for iOS yet ("iOS 26.2 is not
# installed": install it from Xcode › Settings › Components, then open
# SigmaDemo.xcodeproj instead).
#
#   ./run-in-simulator.sh                 # first available iPhone simulator
#   SIMULATOR_ID=<udid> ./run-in-simulator.sh
#   SIGMA_CLOUD=http://localhost:3333 SIGMA_KEY=sgm_test_… ./run-in-simulator.sh
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
PKG=.build/pkg
mkdir -p "$PKG/Sources/SigmaDemo"
cp SigmaDemoApp.swift "$PKG/Sources/SigmaDemo/"
cat > "$PKG/Package.swift" <<'SWIFT'
// swift-tools-version:5.10
import PackageDescription
let package = Package(
    name: "SigmaDemo",
    platforms: [.iOS(.v15)],
    dependencies: [.package(path: "../../../..")],
    targets: [.executableTarget(name: "SigmaDemo", dependencies: [.product(name: "NimbusSigma", package: "sigma-ios")])]
)
SWIFT
echo "Building…"
swift build --package-path "$PKG" --triple arm64-apple-ios15.0-simulator --sdk "$SDK" 2>&1 | grep -E "error|Build complete" || true
BIN="$PKG/.build/arm64-apple-ios-simulator/debug/SigmaDemo"
[ -x "$BIN" ] || { echo "The build failed."; exit 1; }

APP=.build/SigmaDemo.app
rm -rf "$APP" && mkdir -p "$APP" && cp "$BIN" "$APP/"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SigmaDemo</string>
<key>CFBundleIdentifier</key><string>space.nimbusgo.sigmademo</string>
<key>CFBundleName</key><string>SigmaDemo</string>
<key>CFBundleDisplayName</key><string>Sigma Demo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>MinimumOSVersion</key><string>15.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict></plist>
PLIST
codesign -s - --force "$APP" >/dev/null 2>&1

DEV=${SIMULATOR_ID:-$(xcrun simctl list devices available | grep -E "^\s+iPhone" | grep -m1 Booted | grep -oE "[0-9A-F-]{36}" || true)}
[ -n "$DEV" ] || DEV=$(xcrun simctl list devices available | grep -E "^\s+iPhone" | head -1 | grep -oE "[0-9A-F-]{36}")
[ -n "$DEV" ] || { echo "No iPhone simulator found. Add one in Xcode › Window › Devices and Simulators."; exit 1; }
xcrun simctl boot "$DEV" 2>/dev/null || true
open -a Simulator
xcrun simctl bootstatus "$DEV" -b >/dev/null
xcrun simctl install "$DEV" "$APP"
SIMCTL_CHILD_SIGMA_CLOUD="${SIGMA_CLOUD:-}" SIMCTL_CHILD_SIGMA_KEY="${SIGMA_KEY:-}" xcrun simctl launch "$DEV" space.nimbusgo.sigmademo >/dev/null
echo "Running in the simulator. Enter the cloud address and a Sigma key in Settings (the gear) if you did not pass them."
