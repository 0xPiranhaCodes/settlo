#!/usr/bin/env bash
# Creates labels, milestones and backlog issues. Re-runnable: existing items are skipped.
set -euo pipefail
cd "$(dirname "$0")/.."
for l in area:backend area:flutter area:platform area:qa area:infra type:feature type:bug type:chore type:adr agent:claude agent:codex gate needs-owner-decision; do
  gh label create "$l" --force >/dev/null
done
ms(){ gh api "repos/{owner}/{repo}/milestones" --jq ".[].title" | grep -qxF "$1" || gh api "repos/{owner}/{repo}/milestones" -f title="$1" -f due_on="$2T23:59:59Z" >/dev/null; }
ms "M0 Foundations" 2026-11-13
ms "M1 Auth and backend core" 2026-11-22
ms "M2 Design system and app shell" 2026-11-29
ms "M3 Spaces end to end" 2026-12-06
ms "M4 Loans" 2026-12-16
ms "M5 Platform surfaces and offline" 2026-12-26
ms "M6 Release" 2027-01-04
existing=$(gh issue list --state all --limit 500 --json title --jq '.[].title')
for f in docs/backlog/*.md; do
  title=$(sed -n 1p "$f"); labels=$(sed -n 2p "$f"); milestone=$(sed -n 3p "$f")
  grep -qxF "$title" <<<"$existing" && continue
  gh issue create --title "$title" --label "$labels" --milestone "$milestone" --body "$(tail -n +4 "$f")"
done
