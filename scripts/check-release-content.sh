#!/usr/bin/env bash
#
# Refuses content whose review status does not match the build's channel.
#
# The channel is read out of the built Info.plist, not passed in. A gate that
# depends on its caller remembering `--channel store` is a gate that passes when
# the flag is forgotten — the same failure mode as a grep whose pattern can
# never match: green, and proving nothing.
#
# Usage: bash scripts/check-release-content.sh <path to PokerCoach.app>

set -euo pipefail

app_path="${1:?usage: $0 <path to PokerCoach.app>}"
plist="$app_path/Info.plist"

if [[ ! -f "$plist" ]]; then
  echo "FAIL: no Info.plist at $plist" >&2
  exit 1
fi

channel="$(plutil -extract PCContentChannel raw "$plist" 2>/dev/null || true)"
if [[ -z "$channel" ]]; then
  echo "FAIL: $plist carries no PCContentChannel" >&2
  exit 1
fi

case "$channel" in
  debug)   allowed=("testFixture" "unverifiedDraft" "reviewed") ;;
  dogfood) allowed=("unverifiedDraft" "reviewed") ;;
  store)   allowed=("reviewed") ;;
  *)
    echo "FAIL: unknown PCContentChannel '$channel'" >&2
    exit 1
    ;;
esac

violations=0
found=0

while IFS= read -r pack; do
  found=$((found + 1))
  pack_id="$(plutil -extract manifest.id raw "$pack")"
  status="$(plutil -extract manifest.reviewStatus raw "$pack")"

  permitted=0
  for candidate in "${allowed[@]}"; do
    if [[ "$candidate" == "$status" ]]; then
      permitted=1
      break
    fi
  done

  if [[ "$permitted" -eq 0 ]]; then
    echo "FAIL: channel '$channel' forbids '$status' but $pack_id carries it" >&2
    violations=$((violations + 1))
  fi
done < <(find "$app_path" -maxdepth 1 -name '*StrategyPack.json')

if [[ "$found" -eq 0 ]]; then
  echo "FAIL: $app_path bundles no strategy pack at all" >&2
  exit 1
fi

if [[ "$violations" -gt 0 ]]; then
  exit 1
fi

echo "OK: channel '$channel', $found pack(s), all within {${allowed[*]}}"
