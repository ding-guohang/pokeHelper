#!/usr/bin/env bash
# One-command M1B verification.
#
# Runs the M1A regression first: M1B must not have cost anything the offline
# slice already guaranteed. Then the Go suites, the two-device end-to-end run
# against a temporary MySQL, the iOS account and sync tests on both device
# families, and finally the release-secret gate.
#
# Every step is a hard gate. The script never touches an existing MySQL service
# or schema; scripts/test-server-mysql.sh starts a throwaway server in a
# temporary directory and tears it down through a trap.
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
cd "$repository_root"

iphone_destination="${M1B_IPHONE_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro,OS=latest}"

# Matches verify-m1a.sh: prefer the M4 iPad, fall back to M5, fail loudly
# rather than skipping the tablet.
if [[ -n "${M1B_IPAD_DESTINATION:-}" ]]; then
  ipad_destination="$M1B_IPAD_DESTINATION"
else
  available_devices="$(xcrun simctl list devices available)"
  if grep -Fq "iPad Pro 13-inch (M4) (" <<<"$available_devices"; then
    ipad_destination="platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=latest"
  elif grep -Fq "iPad Pro 13-inch (M5) (" <<<"$available_devices"; then
    ipad_destination="platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest"
  else
    echo "error: no available iPad Pro 13-inch (M4) or (M5) simulator was found" >&2
    exit 1
  fi
fi

echo "==> M1A regression"
bash scripts/verify-m1a.sh

echo "==> Go unit tests and static checks"
(
  cd Server
  go vet ./...
  go vet -tags=integration ./...
  unformatted="$(gofmt -l .)"
  if [[ -n "$unformatted" ]]; then
    echo "error: gofmt reports unformatted files:" >&2
    echo "$unformatted" >&2
    exit 1
  fi
  go test ./...
)

echo "==> Go integration and end-to-end tests on an isolated MySQL"
bash scripts/test-server-mysql.sh go test -tags=integration ./...

echo "==> iOS account and sync tests"
xcodegen generate
only_testing=()
for suite in \
  PokerCoachTests/PasswordPolicyTests \
  PokerCoachTests/CredentialStoreTests \
  PokerCoachTests/AccountSessionControllerTests \
  PokerCoachTests/ProfileAssociationStoreTests \
  PokerCoachTests/ActiveProfileControllerTests \
  PokerCoachTests/ProfileLifecycleControllerTests \
  PokerCoachTests/ProfileMigrationTests \
  PokerCoachTests/FileOutboxStoreTests \
  PokerCoachTests/SyncTrackingTrainingEventStoreTests \
  PokerCoachTests/OutboxReconciliationTests \
  PokerCoachTests/SyncEngineTests \
  PokerCoachTests/TwoProfileConvergenceTests \
  PokerCoachTests/AccountExportBuilderTests \
  PokerCoachTests/AccountDeletionTests \
  PokerCoachTests/OfflineLogoutTests
do
  only_testing+=(-only-testing:"$suite")
done
xcodebuild test \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -destination "$iphone_destination" \
  "${only_testing[@]}"

# The account UI suites are named separately because they are the only evidence
# that signing in never blocks training. An earlier version of this script
# listed unit suites only, so they were silently never run.
echo "==> iOS account UI tests on iPhone and iPad"
for destination in "$iphone_destination" "$ipad_destination"; do
  xcodebuild test \
    -project PokerCoach.xcodeproj \
    -scheme PokerCoach \
    -destination "$destination" \
    -only-testing:PokerCoachUITests/AnonymousAccountEntryTests
done

echo "==> Live client/server contract loop"
bash scripts/test-live-m1b.sh

echo "==> Release secret gate"
bash scripts/check-m1b-release-secrets.sh

echo "==> Check the working-tree diff"
git diff --check

echo "==> M1B verification passed"
