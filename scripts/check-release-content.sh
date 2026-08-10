#!/usr/bin/env bash
#
# Refuses content whose review status does not match the build's channel, and
# refuses content that does not match the checksum shipped beside it.
#
# The channel is read out of the built Info.plist, not passed in. A gate that
# depends on its caller remembering `--channel store` is a gate that passes when
# the flag is forgotten.
#
# Packs are found by inspecting every JSON resource for a manifest, not by
# matching a filename. The Release xcconfig excludes unverified content *by
# filename*; if this gate also keyed on filenames the two would fail open
# together the moment a resource were renamed.
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

while IFS= read -r candidate; do
  # A strategy pack is any JSON resource carrying a manifest review status.
  status="$(plutil -extract manifest.reviewStatus raw "$candidate" 2>/dev/null || true)"
  [[ -n "$status" ]] || continue

  found=$((found + 1))
  pack_id="$(plutil -extract manifest.id raw "$candidate")"
  name="$(basename "$candidate")"

  permitted=0
  for allowed_status in "${allowed[@]}"; do
    if [[ "$allowed_status" == "$status" ]]; then
      permitted=1
      break
    fi
  done
  if [[ "$permitted" -eq 0 ]]; then
    echo "FAIL: channel '$channel' forbids '$status' but $pack_id ($name) carries it" >&2
    violations=$((violations + 1))
  fi

  # Content the app will train against has to match the digest recorded beside
  # it. Without this the gate reads a manifest field and nothing else, so a pack
  # with rewritten EVs — which would misgrade every answer — sails through and
  # only fails at launch.
  sidecar="${candidate%.json}.sha256"
  if [[ -f "$sidecar" ]]; then
    recorded="$(tr -d '[:space:]' < "$sidecar")"
    actual="$(shasum -a 256 "$candidate" | awk '{print $1}')"
    if [[ "$recorded" != "$actual" ]]; then
      echo "FAIL: $pack_id ($name) does not match its recorded digest" >&2
      echo "      recorded $recorded" >&2
      echo "      actual   $actual" >&2
      violations=$((violations + 1))
    fi
  elif [[ "$status" == "reviewed" ]]; then
    # A missing sidecar silently disables verification, so reviewed content is
    # required to carry one. Anything less makes the digest optional in exactly
    # the case where it matters.
    echo "FAIL: reviewed pack $pack_id ($name) ships without a .sha256" >&2
    violations=$((violations + 1))
  fi
done < <(find "$app_path" -maxdepth 1 -name '*.json')

if [[ "$found" -eq 0 ]]; then
  echo "FAIL: $app_path bundles no strategy pack at all" >&2
  exit 1
fi

if [[ "$violations" -gt 0 ]]; then
  exit 1
fi

echo "OK: channel '$channel', $found pack(s), all within {${allowed[*]}} and matching their digests"
