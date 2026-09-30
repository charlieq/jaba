#!/bin/bash
# Archive JABA and upload to App Store Connect (TestFlight). Usage: scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Bump the build number (every upload needs a higher one).
current=$(xcodebuild -project JABA.xcodeproj -scheme JABA -showBuildSettings 2>/dev/null | awk '/ CURRENT_PROJECT_VERSION =/{print $3; exit}')
next=$((current + 1))
sed -i '' "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $next;/" JABA.xcodeproj/project.pbxproj
echo "Build number: $current -> $next"

rm -rf build
xcodebuild archive -project JABA.xcodeproj -scheme JABA -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/JABA.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/JABA.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export -allowProvisioningUpdates
echo "Uploaded build $next. Check App Store Connect > TestFlight."
