#!/usr/bin/env bash
#
# Guards the one-way door in the OpenSpec workflow.
#
# At archive time a proposal's Requirement blocks *replace* the corresponding
# blocks in openspec/specs/. A proposal that lists a capability under "Modified
# Capabilities" but rewrites it from memory therefore deletes every requirement
# and scenario it forgot to carry over -- silently, with no diff to review,
# because the proposal reads as a complete and coherent document on its own.
#
# This script fails when a Requirement or Scenario present in the current spec
# is absent from the proposal. Carrying a heading over unchanged is the whole
# point; a genuine removal must be declared under "Removed Capabilities" and
# listed in ALLOW_REMOVED below.
#
# Usage: bash scripts/check-proposal-completeness.sh <change-id>

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <change-id>" >&2
  exit 2
fi

change_id="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proposal="$repo_root/openspec/changes/$change_id/proposal.md"

if [[ ! -f "$proposal" ]]; then
  echo "no proposal at $proposal" >&2
  exit 2
fi

python3 - "$repo_root" "$proposal" <<'PYTHON'
import pathlib
import re
import sys

repo_root = pathlib.Path(sys.argv[1])
proposal_text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

# Capabilities the proposal declares it is changing in place. Only these are
# checked: a new capability has no prior spec, and a removed one is meant to
# lose its requirements.
modified_section = re.search(
    r"^### Modified Capabilities\s*\n(.*?)(?=^###? )",
    proposal_text,
    re.MULTILINE | re.DOTALL,
)
if modified_section is None:
    print("proposal has no '### Modified Capabilities' section; nothing to check")
    sys.exit(0)

capabilities = re.findall(r"^- `([^`]+)`", modified_section.group(1), re.MULTILINE)
if not capabilities:
    print("no modified capabilities listed; nothing to check")
    sys.exit(0)

# Headings carry one more '#' in a proposal than in a spec, so compare on kind
# and name rather than name alone. Demoting a Requirement to a Scenario keeps
# the name but discards the SHALL statement, which is the part that binds.
proposal_headings = set(
    re.findall(r"^#{4,5} (Requirement|Scenario): (.+)$", proposal_text, re.MULTILINE)
)

failures = []
for capability in capabilities:
    spec_path = repo_root / "openspec" / "specs" / capability / "spec.md"
    if not spec_path.exists():
        failures.append(
            f"{capability}: listed as modified but openspec/specs/{capability}/spec.md "
            f"does not exist -- it belongs under New Capabilities"
        )
        continue

    spec_text = spec_path.read_text(encoding="utf-8")
    for line_number, line in enumerate(spec_text.splitlines(), start=1):
        heading = re.match(r"^#{2,3} (Requirement|Scenario): (.+)$", line)
        if heading is None:
            continue
        kind, name = heading.group(1), heading.group(2)
        if (kind, name) not in proposal_headings:
            demoted = any(
                other_kind != kind and other_name == name
                for other_kind, other_name in proposal_headings
            )
            detail = (
                f"appears in the proposal as a {'Scenario' if kind == 'Requirement' else 'Requirement'} "
                f"instead, which drops its original binding"
                if demoted
                else "is missing from the proposal and would be deleted at archive"
            )
            failures.append(
                f"{capability}: {kind} “{name}” "
                f"(openspec/specs/{capability}/spec.md:{line_number}) {detail}"
            )

if failures:
    print("Modified capabilities drop existing behavior:\n", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    print(
        "\nCarry each heading into the proposal verbatim, or declare the removal "
        "under '### Removed Capabilities' with a migration path.",
        file=sys.stderr,
    )
    sys.exit(1)

checked = ", ".join(capabilities)
print(f"modified capabilities preserve all existing requirements and scenarios: {checked}")
PYTHON
