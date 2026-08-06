#!/usr/bin/env bash
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
cd "$repository_root"

iphone_destination="${M1A_IPHONE_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro,OS=latest}"

echo "==> Generate the Xcode project"
xcodegen generate

if [[ -n "${M1A_IPAD_DESTINATION:-}" ]]; then
  ipad_destination="$M1A_IPAD_DESTINATION"
  ipad_destination_source="M1A_IPAD_DESTINATION override"
else
  available_devices="$(xcrun simctl list devices available)"
  if grep -Fq "iPad Pro 13-inch (M4) (" <<<"$available_devices"; then
    ipad_destination="platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest"
    ipad_destination_source="automatic M4 selection"
  elif grep -Fq "iPad Pro 13-inch (M5) (" <<<"$available_devices"; then
    ipad_destination="platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest"
    ipad_destination_source="automatic M5 fallback"
  else
    echo "error: no available iPad Pro 13-inch (M4) or (M5) simulator was found" >&2
    echo "Set M1A_IPAD_DESTINATION to an explicit iPad Simulator destination to override detection." >&2
    exit 1
  fi
fi

echo "==> iPhone destination: $iphone_destination"
echo "==> iPad destination: $ipad_destination ($ipad_destination_source)"

temp_parent="${TMPDIR:-/tmp}"
temp_parent="${temp_parent%/}"
derived_data_dir="$(
  mktemp -d "$temp_parent/pokercoach-m1a-derived-data.XXXXXX"
)"

cleanup() {
  if [[
    -n "${derived_data_dir:-}"
    && -d "$derived_data_dir"
    && "$derived_data_dir" == "$temp_parent"/pokercoach-m1a-derived-data.*
  ]]; then
    rm -rf -- "$derived_data_dir"
  fi
}
trap cleanup EXIT

echo "==> Test PokerCore"
swift test --package-path Packages/PokerCore

echo "==> Test StrategyContent"
swift test --package-path Packages/StrategyContent

echo "==> Test TrainingDomain"
swift test --package-path Packages/TrainingDomain

echo "==> Test PokerCoach unit tests"
xcodebuild test \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -destination "$iphone_destination" \
  -only-testing:PokerCoachTests

echo "==> Test the iPhone cash-coach happy path"
xcodebuild test \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -destination "$iphone_destination" \
  -only-testing:PokerCoachUITests/CashCoachHappyPathTests

echo "==> Test the iPad layout"
xcodebuild test \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -destination "$ipad_destination" \
  -only-testing:PokerCoachUITests/IPadLayoutTests

echo "==> Build Release for iOS Simulator"
xcodebuild build \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -configuration Release \
  -destination "generic/platform=iOS Simulator" \
  -derivedDataPath "$derived_data_dir"

release_fixture="$(
  find "$derived_data_dir" \
    -type f \
    -name "DevStrategyPack.json" \
    -print \
    -quit
)"
if [[ -n "$release_fixture" ]]; then
  echo "error: Release DerivedData contains the development strategy fixture:" >&2
  echo "$release_fixture" >&2
  exit 1
fi
echo "==> Release exclusion: DevStrategyPack.json absent"

echo "==> Check the working-tree diff"
git diff --check

echo "==> M1A verification passed"
