#!/usr/bin/env bash
# Render the unchanged base UI with the current screenshot fixtures on Linux.
# Existing target/overflow defects in the base remain visible in its images;
# only the base's new hit-target assertion is disabled, never head validation.
set -euo pipefail
base_sha="$(git rev-parse --verify "${1:?base commit required}^{commit}")"
root="$(git rev-parse --show-toplevel)"
baseline="$(mktemp -d /tmp/settlo-ui-baseline.XXXXXX)"
rmdir "$baseline"
git worktree add --detach "$baseline" "$base_sha"
trap 'git worktree remove --force "$baseline"' EXIT
cp "$root"/app/test/*_golden_test.dart "$baseline/app/test/"
cp "$root/app/test/sheet_hit_test.dart" "$baseline/app/test/"
cp "$root/packages/test_support/lib/golden.dart" "$baseline/packages/test_support/lib/golden.dart"
# New Loan's baseline uses ListView rather than SingleChildScrollView.
git show "$base_sha:app/test/new_loan_golden_test.dart" > "$baseline/app/test/new_loan_golden_test.dart"
python3 - "$baseline" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]) / 'packages/test_support/lib/golden.dart'
s = p.read_text()
s = re.sub(r'static const accessible = <GoldenDevice>\[.*?\n  \];',
           'static const accessible = all;', s, flags=re.S)
s = s[:s.index('/// Walks each screen')] + '''// The base predates the 44px audit; head still runs the complete assertion.
void expectSettloTapTargets(WidgetTester tester) {}
'''
p.write_text(s)
PY
(
  cd "$baseline"
  flutter pub get
  cd app
  flutter test --update-goldens test/*_golden_test.dart test/sheet_hit_test.dart
)
mkdir -p "$root/docs/design/145/before"
cp "$baseline"/app/test/goldens/*.png "$root/docs/design/145/before/"
printf '%s\n' "$base_sha" > "$root/docs/design/145/before/base-sha.txt"
