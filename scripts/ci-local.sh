#!/usr/bin/env bash
# Optional developer preflight; hosted GitHub Actions remain the merge gate.
set -euo pipefail

# Orca may inject an empty Git config overlay; discard it when its keys are
# absent so Flutter's internal Git probes remain usable.
if [[ -n "${GIT_CONFIG_COUNT:-}" && -z "${GIT_CONFIG_KEY_0:-}" ]]; then
  for ((index = 0; index < GIT_CONFIG_COUNT; index++)); do
    unset "GIT_CONFIG_VALUE_$index"
  done
  unset GIT_CONFIG_COUNT
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter_version="$(sed -nE 's/.*"flutter"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$root/.fvmrc")"
if [[ -z "$flutter_version" ]]; then
  echo "ci-local: .fvmrc does not contain an exact Flutter version." >&2
  exit 2
fi
golden_image="settlo/flutter-goldens:${flutter_version}-amd64"
update_goldens=false

if [[ "${1:-}" == "--update-goldens" ]]; then
  update_goldens=true
  shift
fi
if (( $# != 0 )); then
  echo "Usage: scripts/ci-local.sh [--update-goldens]" >&2
  exit 2
fi

cd "$root"

for command in docker flutter git python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ci-local: required command '$command' is not installed." >&2
    exit 2
  fi
done

coverage_baseline="$(git show origin/main:.github/coverage-baseline.txt)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/settlo-ci.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

sha="$(git rev-parse HEAD)"
analyze_status=NOT_RUN
tests_status=NOT_RUN
goldens_status=NOT_RUN
supabase_status=NOT_RUN
android_status=NOT_RUN
ios_status=NOT_RUN
coverage_summary='not measured'
money_summary='not measured'
overall=PASS

run_logged() {
  local name="$1"
  shift
  echo
  echo "==> $name"
  set +e
  "$@" 2>&1 | tee "$tmp/$name.log"
  local status="${PIPESTATUS[0]}"
  set -e
  return "$status"
}

build_golden_image() {
  docker build \
    --platform linux/amd64 \
    --file scripts/Dockerfile.flutter-goldens \
    --tag "$golden_image" \
    .
}

in_linux() {
  docker run --rm \
    --platform linux/amd64 \
    --env CI=true \
    --env "COVERAGE_BASELINE=$coverage_baseline" \
    --env HOME=/tmp/settlo-home \
    --volume "$root:/workspace" \
    --workdir /workspace \
    "$golden_image" \
    bash -lc "$1"
}

run_analyze() {
  local installed
  installed="$(flutter --version | sed -n '1s/^Flutter \([^ ]*\).*/\1/p')"
  if [[ "$installed" != "$flutter_version" ]]; then
    echo "ci-local: Flutter $flutter_version is required; found ${installed:-unknown}." >&2
    return 1
  fi
  flutter pub get && flutter analyze
}

linux_tests='set -euo pipefail
flutter pub get
mkdir -p coverage
: > coverage/lcov.info

members=()
while IFS= read -r member; do
  members+=("$member")
done < <(
  dart pub workspace list --json | python3 -c '\''
import json
import os
import sys
for package in json.load(sys.stdin)["packages"]:
    path = package["path"]
    if os.path.isdir(os.path.join(path, "test")):
        print(path)
'\''
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
    flutter test --coverage
  )
  coverage_files+=("$member/coverage/lcov.info")
done

python3 - /workspace "${coverage_files[@]}" <<'\''PY'\''
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
  awk -F: '\''
    /^LF:/ { found += $2 }
    /^LH:/ { hit += $2 }
    END { print found + 0, hit + 0 }
  '\'' coverage/lcov.info
)
if (( lines_found == 0 )); then
  echo "Merged coverage contains no instrumented lines." >&2
  exit 1
fi
coverage="$(awk -v hit="$lines_hit" -v found="$lines_found" '\''BEGIN { printf "%.2f", (hit * 100) / found }'\'')"
baseline="$COVERAGE_BASELINE"
echo "Total line coverage: $coverage% ($lines_hit/$lines_found)"
echo "Main baseline: $baseline%"
if awk -v coverage="$coverage" -v baseline="$baseline" '\''BEGIN { exit !(coverage + 0 < baseline + 0) }'\''; then
  echo "Coverage dropped below the main baseline." >&2
  exit 1
fi

read -r money_lines_found money_lines_hit < <(
  awk -F: '\''
    /^SF:/ { money = ($2 ~ /^packages\/core\/lib\/money\//) }
    money && /^LF:/ { found += $2 }
    money && /^LH:/ { hit += $2 }
    END { print found + 0, hit + 0 }
  '\'' coverage/lcov.info
)
if (( money_lines_found == 0 )); then
  echo "Merged coverage contains no packages/core/lib/money lines." >&2
  exit 1
fi
money_coverage="$(awk -v hit="$money_lines_hit" -v found="$money_lines_found" '\''BEGIN { printf "%.2f", (hit * 100) / found }'\'')"
echo "Money line coverage: $money_coverage% ($money_lines_hit/$money_lines_found)"
if awk -v hit="$money_lines_hit" -v found="$money_lines_found" '\''BEGIN { exit !((hit * 100) < (found * 80)) }'\''; then
  echo "packages/core/lib/money line coverage is below 80%." >&2
  exit 1
fi'

run_tests() {
  in_linux "$linux_tests"
}

compare_goldens() {
  in_linux 'set -euo pipefail
flutter pub get
(cd app && flutter test test/golden_harness_sample_test.dart test/auth_golden_test.dart test/home_golden_test.dart test/shell_golden_test.dart)
(cd packages/core && flutter test test/theme/theme_golden_test.dart test/widgets/components_golden_test.dart)'
}

regenerate_core_goldens() {
  in_linux 'set -euo pipefail
flutter pub get
# App images are canonical already: compare them before changing any PNG.
(cd app && flutter test test/golden_harness_sample_test.dart test/auth_golden_test.dart test/home_golden_test.dart test/shell_golden_test.dart)
(cd packages/core && flutter test --update-goldens test/theme/theme_golden_test.dart test/widgets/components_golden_test.dart)'
}

run_supabase() (
  set -uo pipefail
  if ! command -v supabase >/dev/null 2>&1; then
    echo "ci-local: Supabase CLI is not installed." >&2
    exit 1
  fi
  if ! command -v deno >/dev/null 2>&1; then
    echo "ci-local: Deno is not installed." >&2
    exit 1
  fi
  # Reset a disposable stack so the developer's normal local database and
  # running services are never modified by this preflight.
  export SUPABASE_LOCAL_DIR="$tmp/supabase-local"
  export SUPABASE_LOCAL_IDENTITY="$tmp/supabase-stack"
  trap 'scripts/supabase-local.sh stop >/dev/null 2>&1 || true' EXIT
  scripts/supabase-local.sh start &&
    scripts/supabase-local.sh db reset &&
    scripts/supabase-local.sh test db &&
    (cd supabase/functions && deno test)
)

run_android() {
  (cd app && flutter build apk --debug)
}

run_ios() {
  (cd app && flutter build ios --no-codesign --debug)
}

if run_logged analyze run_analyze; then
  analyze_status=PASS
else
  analyze_status=FAIL
  overall=FAIL
fi

if run_logged golden-image build_golden_image; then
  if $update_goldens; then
    if run_logged regenerate-core-goldens regenerate_core_goldens; then
      goldens_status=UPDATED
    else
      goldens_status=FAIL
      overall=FAIL
    fi
  fi

  if run_logged tests run_tests; then
    tests_status=PASS
    coverage_summary="$(sed -n 's/^Total line coverage: //p' "$tmp/tests.log" | tail -1)"
    money_summary="$(sed -n 's/^Money line coverage: //p' "$tmp/tests.log" | tail -1)"
  else
    tests_status=FAIL
    overall=FAIL
  fi

  if run_logged goldens compare_goldens; then
    goldens_status=PASS
  else
    goldens_status=FAIL
    overall=FAIL
  fi
else
  tests_status=BLOCKED
  goldens_status=BLOCKED
  overall=FAIL
fi

if run_logged supabase run_supabase; then
  supabase_status=PASS
else
  supabase_status=FAIL
  overall=FAIL
fi

if run_logged android run_android; then
  android_status=PASS
else
  if grep -Eqi 'Unable to locate Android SDK|No Android SDK found|Android sdkmanager not found|cmdline-tools component is missing' "$tmp/android.log"; then
    android_status='SKIP (Android SDK/cmdline-tools unavailable)'
  else
    android_status=FAIL
    overall=FAIL
  fi
fi

if [[ "$(uname -s)" != Darwin ]]; then
  ios_status='SKIP (requires macOS)'
elif run_logged ios run_ios; then
  ios_status=PASS
else
  ios_status=FAIL
  overall=FAIL
fi

echo
echo 'Settlo local CI summary'
echo "Commit: $sha"
echo "Analyze: $analyze_status"
echo "Tests + coverage: $tests_status ($coverage_summary; money $money_summary)"
echo "Linux goldens: $goldens_status"
echo "Supabase: $supabase_status"
echo "Android debug build: $android_status"
echo "iOS debug build: $ios_status"
echo "Overall: $overall"

[[ "$overall" == PASS ]]
