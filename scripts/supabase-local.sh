#!/usr/bin/env bash
# Runs the Supabase CLI against supabase/config.toml + supabase/config.local-dev.toml in a
# generated workdir, so the committed config.toml stays production-safe. Local commands only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
gen="${SUPABASE_LOCAL_DIR:-$root/.supabase-local}"
identity="${SUPABASE_LOCAL_IDENTITY:-$root}"

# The generated config carries test OTPs; refuse anything that writes to a hosted project.
case "${1:-}" in
  start|stop|status|test|migration|gen|seed|services) ;;
  db)
    case "${2:-}" in
      push|pull) echo "supabase-local: 'db ${2}' targets a hosted project; run it with the raw CLI." >&2; exit 2 ;;
    esac ;;
  *) echo "supabase-local: '${1:-}' is not a local command; see supabase/README.md." >&2; exit 2 ;;
esac

mkdir -p "$gen/supabase"
find "$gen/supabase" -maxdepth 1 -type l -delete
shopt -s nullglob dotglob
for entry in "$root"/supabase/*; do
  name="$(basename "$entry")"
  case "$name" in
    config.toml|config.local-dev.toml|.temp|.branches) ;;
    # Symlinks were just cleared, so anything still here is CLI-created state (e.g. snippets/); keep it.
    *) [ -e "$gen/supabase/$name" ] || ln -s "$entry" "$gen/supabase/$name" ;;
  esac
done

# Each identity gets its own project_id (Docker containers and volumes) and a 10-port block, both
# derived from a stable hash. The default identity is the repo root; callers can supply a disposable
# identity and generated-config directory for isolated runs.
# Slot 0 would be 54400-54409; the base config's 54320-54329 block is never used.
hash="$(printf '%s' "$identity" | cksum | cut -d' ' -f1)"
slot="${SUPABASE_LOCAL_SLOT:-$((hash % 500))}"
base=$((54400 + slot * 10))
project_id="settlo-$(printf '%08x' "$hash")"
cat "$root/supabase/config.toml" "$root/supabase/config.local-dev.toml" |
  awk -v id="$project_id" -v b="$base" '
    /^\[/ { section = $0 }
    /^project_id = / { $0 = "project_id = \"" id "\"" }
    section == "[db]" && /^shadow_port = / { $0 = "shadow_port = " b }
    section == "[api]" && /^port = / { $0 = "port = " b + 1 }
    section == "[db]" && /^port = / { $0 = "port = " b + 2 }
    section == "[studio]" && /^port = / { $0 = "port = " b + 3 }
    section == "[local_smtp]" && /^port = / { $0 = "port = " b + 4 }
    section == "[analytics]" && /^port = / { $0 = "port = " b + 7 }
    section == "[edge_runtime]" && /^inspector_port = / { $0 = "inspector_port = " b + 8 }
    section == "[db.pooler]" && /^port = / { $0 = "port = " b + 9 }
    { print }
  ' > "$gen/supabase/config.toml"

if [ "$1" = start ]; then
  echo "supabase-local: project_id $project_id, API port $((base + 1)), DB port $((base + 2)) (slot $slot)" >&2
fi

exec "${SUPABASE_BIN:-supabase}" --workdir "$gen" "$@"
