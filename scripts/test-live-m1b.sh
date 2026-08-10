#!/usr/bin/env bash
# Runs the iOS client against a real Go service on a real MySQL.
#
# Every other suite tests one side against a double written in its own
# language, so both sides can be internally perfect and still disagree about
# the wire — which is exactly what happened: an extra field, an identifier
# casing, and a 204 with no body all shipped green. This is the only place the
# actual client code talks to the actual server code.
#
# Everything is temporary: a throwaway mysqld from test-server-mysql.sh, a
# freshly built API on an OS-assigned loopback port, both torn down by traps.
# No existing MySQL service or schema is touched.
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
cd "$repository_root"

destination="${M1B_LIVE_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro,OS=latest}"

# Delegates the database to the existing isolated harness, then runs the rest
# of this script inside it so the server and tests share that instance.
if [[ "${M1B_LIVE_INNER:-}" != "1" ]]; then
  # Absolute paths: the harness runs its command from Server/, so a relative
  # re-invocation would not resolve.
  exec bash "$repository_root/scripts/test-server-mysql.sh" \
    env M1B_LIVE_INNER=1 M1B_LIVE_DESTINATION="$destination" \
    bash "$repository_root/scripts/test-live-m1b.sh"
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/pokercoach-live.XXXXXX")"
api_pid=""

cleanup() {
  if [[ -n "$api_pid" ]] && kill -0 "$api_pid" 2>/dev/null; then
    kill "$api_pid" 2>/dev/null || true
    wait "$api_pid" 2>/dev/null || true
  fi
  [[ -d "$work_dir" ]] && rm -rf -- "$work_dir"
  rm -f -- "$address_file"
}
trap cleanup EXIT

# An OS-assigned port avoids colliding with anything already listening.
port="$(
  python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
)"
base_url="http://127.0.0.1:$port"
address_file="/tmp/pokercoach-live-api-url"

echo "==> Build the API"
(cd Server && go build -o "$work_dir/pokercoach-api" ./cmd/api)

echo "==> Start the API on $base_url"
(
  cd Server
  POKER_COACH_ENV=development \
  POKER_COACH_HTTP_ADDR="127.0.0.1:$port" \
  POKER_COACH_MYSQL_DSN="$POKER_COACH_MYSQL_DSN" \
  "$work_dir/pokercoach-api" >"$work_dir/api.log" 2>&1 &
  echo $! >"$work_dir/api.pid"
)
api_pid="$(cat "$work_dir/api.pid")"

echo "==> Wait for readiness"
ready=""
for _ in $(seq 1 60); do
  if curl -fsS "$base_url/health" >/dev/null 2>&1; then
    ready="yes"
    break
  fi
  if ! kill -0 "$api_pid" 2>/dev/null; then
    echo "error: the API exited during startup" >&2
    cat "$work_dir/api.log" >&2
    exit 1
  fi
  sleep 0.5
done
if [[ -z "$ready" ]]; then
  echo "error: the API never became ready" >&2
  cat "$work_dir/api.log" >&2
  exit 1
fi

echo "==> Run the live client contract tests"
xcodegen generate >/dev/null
printf '%s' "$base_url" >"$address_file"

test_log="$work_dir/xcodebuild.log"
set +e
xcodebuild test \
  -project PokerCoach.xcodeproj \
  -scheme PokerCoach \
  -destination "$destination" \
  -only-testing:PokerCoachTests/LiveServerSyncContractTests \
  >"$test_log" 2>&1
test_status=$?
set -e

if [[ "$test_status" -ne 0 ]]; then
  grep -E "error:|XCTAssert|Executed .* tests" "$test_log" | tail -20 >&2
  echo "error: live contract tests failed" >&2
  exit "$test_status"
fi

# A skipped suite is the failure mode this whole script exists to prevent: it
# reports success while asserting nothing.
if grep -qE "[1-9][0-9]* tests? skipped" "$test_log"; then
  grep -E "Executed .* tests" "$test_log" | tail -2 >&2
  echo "error: the live tests were skipped, so nothing was verified" >&2
  exit 1
fi
if ! grep -qE "Executed [1-9][0-9]* tests?, with 0 failures" "$test_log"; then
  echo "error: no live tests executed" >&2
  exit 1
fi

grep -E "Executed .* tests" "$test_log" | tail -1
echo "==> Live M1B contract tests passed"
