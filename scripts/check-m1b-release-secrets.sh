#!/usr/bin/env bash
# Fails if credential material, development-only behaviour, or the M1A
# development strategy fixture can reach a release build.
#
# Two scans, because they catch different mistakes: the tracked-source scan
# catches a secret committed to the repository, and the artifact scan catches a
# secret or development affordance compiled into something shippable.
set -euo pipefail

repository_root="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.."
  pwd
)"
cd "$repository_root"

failures=0

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

echo "==> Scan tracked sources for credential material"

# The M1A fixture is tracked on purpose. It is excluded from Release by
# Config/Release.xcconfig, which the artifact scan below re-verifies.
allowed_fixture="PokerCoach/Resources/DevStrategyPack.json"

while IFS= read -r file; do
  [[ "$file" == "$allowed_fixture" ]] && continue
  [[ "$file" == scripts/check-m1b-release-secrets.sh ]] && continue

  if grep -qE 'BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY' "$file" 2>/dev/null; then
    fail "$file contains a private key"
  fi
  if grep -qE '(POKER_COACH_SMTP_PASSWORD|POKER_COACH_THROTTLE_SECRET)[[:space:]]*=[[:space:]]*["'"'"'][^"'"'"']+' "$file" 2>/dev/null; then
    fail "$file hard-codes a production secret"
  fi
done < <(git ls-files)

if ! git ls-files --error-unmatch "$allowed_fixture" >/dev/null 2>&1; then
  fail "$allowed_fixture is missing; the Release exclusion assertion depends on it"
fi

echo "==> Verify the Release configuration excludes the development fixture"
if ! grep -Fq 'EXCLUDED_SOURCE_FILE_NAMES = DevStrategyPack.json' Config/Release.xcconfig; then
  fail "Config/Release.xcconfig no longer excludes DevStrategyPack.json"
fi
if ! grep -Fq 'DEVELOPMENT_STRATEGY_FIXTURES' Config/Debug.xcconfig; then
  fail "Config/Debug.xcconfig no longer defines DEVELOPMENT_STRATEGY_FIXTURES"
fi
if grep -Fq 'DEVELOPMENT_STRATEGY_FIXTURES' Config/Release.xcconfig; then
  fail "Config/Release.xcconfig must not define DEVELOPMENT_STRATEGY_FIXTURES"
fi

echo "==> Verify production refuses development affordances"
# A development mailer in production would write verification links to a log,
# which turns a log into a credential store.
if ! grep -Fq 'settings.Environment == config.Production' Server/cmd/api/main.go; then
  fail "Server/cmd/api/main.go no longer gates production behaviour"
fi
for guard in POKER_COACH_THROTTLE_SECRET POKER_COACH_APPLE_CLIENT_ID; do
  if ! grep -Fq "$guard" Server/cmd/api/main.go; then
    fail "$guard is no longer required at startup"
  fi
done

# The development mailbox exposes verification tokens. It must not merely be
# discouraged in production — it must not be constructed there.
if ! grep -Fq 'environment == config.Production' Server/internal/httpapi/development_mailbox.go; then
  fail "the development mailbox route is no longer gated on the environment"
fi
if grep -Fq 'v1/dev/' Server/internal/httpapi/router.go; then
  fail "a development route is mounted unconditionally in the router"
fi

# ATS may relax loopback for the local development service, but never
# arbitrary loads.
if grep -Fq 'NSAllowsArbitraryLoads' project.yml; then
  fail "project.yml disables App Transport Security for arbitrary hosts"
fi

if [[ "${1:-}" != "--sources-only" ]]; then
  echo "==> Scan the Release app bundle"
  derived_data="$(mktemp -d "${TMPDIR:-/tmp}/pokercoach-release-scan.XXXXXX")"
  cleanup() {
    [[ -d "$derived_data" ]] && rm -rf -- "$derived_data"
  }
  trap cleanup EXIT

  xcodegen generate >/dev/null
  xcodebuild build \
    -project PokerCoach.xcodeproj \
    -scheme PokerCoach \
    -configuration Release \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$derived_data" >/dev/null

  bundle="$(find "$derived_data" -type d -name 'PokerCoach.app' -print -quit)"
  if [[ -z "$bundle" ]]; then
    fail "the Release build produced no app bundle to scan"
  else
    if find "$bundle" -name 'DevStrategyPack.json' | grep -q .; then
      fail "the Release bundle ships the development strategy fixture"
    fi
    # strings output is captured before matching. Piping into `grep -q` would
    # let grep exit on the first match, SIGPIPE the producer, and — under
    # `set -o pipefail` — make a genuine hit look like a miss, turning every
    # check below into a no-op.
    binary_strings="$(strings "$bundle/PokerCoach" 2>/dev/null || true)"

    # Markers must be things that can actually appear in a compiled Swift
    # binary. An earlier version scanned for a compilation-condition name and
    # for a Go-only environment variable; neither can ever be emitted here, so
    # those checks passed no matter what the build contained.
    for marker in \
      '仅开发演示数据请勿用于真实决策' \
      'DevStrategyPack' \
      'X-Debug-Bypass-Auth'
    do
      if grep -Fq -- "$marker" <<<"$binary_strings"; then
        fail "the Release binary contains the development marker $marker"
      fi
    done

    # Proof the scan can see into this binary at all. Without it a change that
    # silently produced empty output would make every marker check vacuous.
    if ! grep -Fq -- 'PokerCoach' <<<"$binary_strings"; then
      fail "the binary scan produced no readable strings, so its checks prove nothing"
    fi
  fi

  echo "==> Scan the Go production binary"
  go_binary="$derived_data/pokercoach-api"
  (cd Server && go build -o "$go_binary" ./cmd/api)

  # The development mailer is linked into the binary because Go builds one
  # executable for every environment. What matters is that it stays
  # unreachable, which the production gate in main.go enforces and the source
  # scan above verifies. What the binary can prove is that its configuration
  # comes from the environment rather than being baked in.
  go_strings="$(strings "$go_binary" 2>/dev/null || true)"
  if ! grep -Fq 'POKER_COACH_MYSQL_DSN' <<<"$go_strings"; then
    fail "the Go binary does not read its database configuration from the environment"
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  echo "==> $failures release-secret check(s) failed" >&2
  exit 1
fi
echo "==> Release secret checks passed"
