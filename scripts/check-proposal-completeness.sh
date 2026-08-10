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
# Headings alone are not enough: keeping a heading and gutting what sits under
# it deletes the same behaviour. But a Modified Capability is expected to
# rewrite some text -- that is what "modified" means -- so demanding every
# original line survive verbatim reports every intentional edit as a loss.
#
# The body checks are therefore the two that cannot be a legitimate edit: a
# block must not shrink, and a Requirement must still state a SHALL. Replacing
# a body with a placeholder fails both; rewording a SHALL or swapping a
# scenario's assertion fails neither.
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
proposal_path = pathlib.Path(sys.argv[2])
proposal_text = proposal_path.read_text(encoding="utf-8")

failures = []


def named_list(section_title):
    """Capability names listed under a `### <title>` heading.

    The section runs to the next heading of any depth or to end of file, so a
    section placed last in the document is still read. Bullet formatting is
    matched loosely: a proposal that writes ``- **name** —`` instead of
    ``- `name` —`` must not silently turn the whole check off.
    """
    match = re.search(
        rf"^### {re.escape(section_title)}\s*\n(.*?)(?=^#|\Z)",
        proposal_text,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        return None

    names = []
    for line in match.group(1).splitlines():
        bullet = re.match(r"^-\s+(.+)$", line.strip())
        if bullet is None:
            continue
        # Strip backticks, bold markers and any trailing prose after a dash.
        label = re.split(r"\s+[—–-]\s+", bullet.group(1), maxsplit=1)[0]
        label = label.strip().strip("`*_ ")
        if label and label.lower() not in {"无", "none", "n/a"}:
            names.append(label)
    return names


modified = named_list("Modified Capabilities")
removed = named_list("Removed Capabilities") or []

if modified is None:
    failures.append(
        "proposal has no '### Modified Capabilities' section. Write it with "
        "'无' when nothing is modified; a missing section cannot be told apart "
        "from a forgotten one."
    )
    modified = []


def blocks(text, requirement_prefix, scenario_prefix):
    """Maps (kind, name) to the non-blank body lines beneath each heading."""
    found = {}
    current = None
    for line in text.splitlines():
        requirement = re.match(rf"^{requirement_prefix} (Requirement|Scenario): (.+)$", line)
        scenario = re.match(rf"^{scenario_prefix} (Requirement|Scenario): (.+)$", line)
        heading = requirement or scenario
        if heading is not None:
            current = (heading.group(1), heading.group(2).strip())
            found[current] = []
            continue
        if line.startswith("#"):
            current = None
            continue
        if current is not None and line.strip():
            found[current].append(" ".join(line.split()))
    return found


def capability_section(name):
    match = re.search(
        rf"^### Capability: {re.escape(name)}\s*\n(.*?)(?=^### |\Z)",
        proposal_text,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1) if match else None


for capability in modified:
    if capability in removed:
        continue

    spec_path = repo_root / "openspec" / "specs" / capability / "spec.md"
    if not spec_path.exists():
        failures.append(
            f"{capability}: listed as modified but openspec/specs/{capability}/spec.md "
            f"does not exist -- it belongs under New Capabilities"
        )
        continue

    section = capability_section(capability)
    if section is None:
        failures.append(
            f"{capability}: listed as modified but the proposal has no "
            f"'### Capability: {capability}' section, so archive would replace "
            f"its spec with nothing"
        )
        continue

    # Headings are scoped to this capability's own section. Collected globally,
    # a requirement carried over under one capability would satisfy another.
    proposed = blocks(section, "####", "#####")
    existing = blocks(spec_path.read_text(encoding="utf-8"), "##", "###")

    for (kind, name), body in existing.items():
        if (kind, name) not in proposed:
            demoted = any(
                other_kind != kind and other_name == name
                for other_kind, other_name in proposed
            )
            detail = (
                f"appears as a {'Scenario' if kind == 'Requirement' else 'Requirement'} "
                f"instead, which drops its original binding"
                if demoted
                else "is missing and would be deleted at archive"
            )
            failures.append(f"{capability}: {kind} “{name}” {detail}")
            continue

        proposed_body = proposed[(kind, name)]

        if len(proposed_body) < len(body):
            failures.append(
                f"{capability}: {kind} “{name}” kept its heading but its body "
                f"shrank from {len(body)} lines to {len(proposed_body)}"
            )
            continue

        if kind == "Requirement" and not any("SHALL" in line for line in proposed_body):
            failures.append(
                f"{capability}: Requirement “{name}” no longer states a SHALL, "
                f"so archive would replace a binding requirement with prose"
            )
            continue

        if kind == "Scenario":
            def bullets(lines):
                return sum(
                    1 for line in lines
                    if re.match(r"^- (GIVEN|WHEN|THEN|AND) ", line)
                )

            if bullets(proposed_body) < bullets(body):
                failures.append(
                    f"{capability}: Scenario “{name}” dropped "
                    f"{bullets(body) - bullets(proposed_body)} GIVEN/WHEN/THEN line(s)"
                )

if failures:
    print("Modified capabilities drop existing behavior:\n", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    print(
        "\nCarry each heading and its body into the proposal, or declare the "
        "removal under '### Removed Capabilities'.",
        file=sys.stderr,
    )
    sys.exit(1)

checked = ", ".join(modified) if modified else "(none)"
print(f"modified capabilities preserve every existing requirement and scenario, none gutted: {checked}")
PYTHON
