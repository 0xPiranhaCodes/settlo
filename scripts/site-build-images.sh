#!/usr/bin/env bash
# Rebuild pinned iOS 26 SabkiJeb captures; requires Pillow 13 with AVIF support.
set -euo pipefail
cd "$(dirname "$0")/.."
"${SITE_IMAGE_PYTHON:-python3}" scripts/site-phones.py
