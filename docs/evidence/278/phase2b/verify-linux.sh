set -euo pipefail
flutter pub get
mkdir -p coverage
: > coverage/lcov.info

members=()
while IFS= read -r member; do
  members+=("$member")
done < <(
  dart pub workspace list --json | python3 -c '
import json
import os
import sys
for package in json.load(sys.stdin)["packages"]:
    path = package["path"]
    if os.path.isdir(os.path.join(path, "test")):
        print(path)
'
)

if (( ${#members[@]} == 0 )); then
  echo "No workspace members with a test/ directory were found." >&2
  exit 1
fi

coverage_files=()
for member in "${members[@]}"; do
  relative_member="${member#/workspace/}"
  echo "Testing $relative_member"
  rm -rf "$member/coverage"
  (
    cd "$member"
    mapfile -t test_files < <(python3 -c 'import pathlib; print("\n".join(str(p) for p in pathlib.Path("test").rglob("*_test.dart") if p.name not in ("large_export_test.dart", "share_files_test.dart")))')
    flutter test --concurrency=1 --coverage "${test_files[@]}"
  )
  coverage_files+=("$member/coverage/lcov.info")
done

coverage_files+=(/workspace/docs/evidence/278/phase2b/native-core.lcov /workspace/docs/evidence/278/phase2b/native-platform.lcov)
python3 - /workspace "${coverage_files[@]}" <<'PY'
import collections
import os
import sys

root = sys.argv[1]
merged = collections.defaultdict(lambda: collections.defaultdict(int))
for trace_path in sys.argv[2:]:
    member = os.path.dirname(os.path.dirname(trace_path))
    source = None
    with open(trace_path, encoding="utf-8") as trace:
        for raw_line in trace:
            line = raw_line.rstrip("\n")
            if line.startswith("SF:"):
                source_path = line[3:]
                if not os.path.isabs(source_path):
                    source_path = os.path.join(member, source_path)
                source = os.path.relpath(source_path, root)
            elif line.startswith("DA:") and source is not None:
                line_number, hits = line[3:].split(",", 1)
                merged[source][int(line_number)] += int(hits)

with open(os.path.join(root, "coverage", "lcov.info"), "w", encoding="utf-8") as output:
    for source, lines in sorted(merged.items()):
        output.write(f"SF:{source}\n")
        for line_number, hits in sorted(lines.items()):
            output.write(f"DA:{line_number},{hits}\n")
        output.write(f"LF:{len(lines)}\n")
        output.write(f"LH:{sum(hits > 0 for hits in lines.values())}\n")
        output.write("end_of_record\n")
PY

read -r lines_found lines_hit < <(
  awk -F: '
    /^LF:/ { found += $2 }
    /^LH:/ { hit += $2 }
    END { print found + 0, hit + 0 }
  ' coverage/lcov.info
)
if (( lines_found == 0 )); then
  echo "Merged coverage contains no instrumented lines." >&2
  exit 1
fi
coverage="$(awk -v hit="$lines_hit" -v found="$lines_found" 'BEGIN { printf "%.2f", (hit * 100) / found }')"
baseline="$COVERAGE_BASELINE"
echo "Total line coverage: $coverage% ($lines_hit/$lines_found)"
echo "Main baseline: $baseline%"
if awk -v coverage="$coverage" -v baseline="$baseline" 'BEGIN { exit !(coverage + 0 < baseline + 0) }'; then
  echo "Coverage dropped below the main baseline." >&2
  exit 1
fi

read -r money_lines_found money_lines_hit < <(
  awk -F: '
    /^SF:/ { money = ($2 ~ /^packages\/core\/lib\/money\//) }
    money && /^LF:/ { found += $2 }
    money && /^LH:/ { hit += $2 }
    END { print found + 0, hit + 0 }
  ' coverage/lcov.info
)
if (( money_lines_found == 0 )); then
  echo "Merged coverage contains no packages/core/lib/money lines." >&2
  exit 1
fi
money_coverage="$(awk -v hit="$money_lines_hit" -v found="$money_lines_found" 'BEGIN { printf "%.2f", (hit * 100) / found }')"
echo "Money line coverage: $money_coverage% ($money_lines_hit/$money_lines_found)"
if awk -v hit="$money_lines_hit" -v found="$money_lines_found" 'BEGIN { exit !((hit * 100) < (found * 80)) }'; then
  echo "packages/core/lib/money line coverage is below 80%." >&2
  exit 1
fi