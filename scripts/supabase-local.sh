#!/usr/bin/env bash
# Runs the Supabase CLI against supabase/config.toml + supabase/config.local-dev.toml in a
# generated workdir, so the committed config.toml stays production-safe. Local commands only.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
gen="$root/.supabase-local"

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
cat "$root/supabase/config.toml" "$root/supabase/config.local-dev.toml" > "$gen/supabase/config.toml"

exec "${SUPABASE_BIN:-supabase}" --workdir "$gen" "$@"
