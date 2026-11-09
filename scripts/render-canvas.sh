#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
canvas_dir="$repo_root/design/canvas"

if [[ -n "${CHROME_BIN:-}" ]]; then
  chrome_bin="$CHROME_BIN"
else
  chrome_bin=""
  candidates=(
    "$(command -v google-chrome 2>/dev/null || true)"
    "$(command -v chromium 2>/dev/null || true)"
    "$(command -v chromium-browser 2>/dev/null || true)"
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      chrome_bin="$candidate"
      break
    fi
  done
fi

if [[ -z "$chrome_bin" || ! -x "$chrome_bin" ]]; then
  echo "Chrome or Chromium was not found. Set CHROME_BIN to its executable." >&2
  exit 1
fi

shopt -s nullglob
artboards=("$canvas_dir"/*.dc.html)
if (( ${#artboards[@]} == 0 )); then
  echo "No canvas artboards found in $canvas_dir." >&2
  exit 1
fi

for viewport in "390 844" "360 800"; do
  read -r width height <<<"$viewport"
  output_dir="$repo_root/design/reference/$width"
  mkdir -p "$output_dir"

  for artboard in "${artboards[@]}"; do
    name="$(basename "$artboard" .dc.html)"
    echo "Rendering $name at ${width}x${height}"
    python3 "$repo_root/scripts/render_canvas.py" \
      --chrome "$chrome_bin" \
      --input "$artboard" \
      --output "$output_dir/$name.png" \
      --width "$width" \
      --height "$height"
  done
done

echo "Rendered $((${#artboards[@]} * 2)) reference images."
