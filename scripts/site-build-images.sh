#!/usr/bin/env bash
# Rebuild from the current app widgets, including theme/mark changes. Never
# update golden PNGs. Exports 390px detail sources and 430px phone content. Use a Pillow 13 environment via SITE_IMAGE_PYTHON.
set -euo pipefail
cd "$(dirname "$0")/.."
export GIT_CONFIG_COUNT=0
(cd app && flutter test test/marketing_export.dart)
"${SITE_IMAGE_PYTHON:-python3}" scripts/site-images.py --ref HEAD
"${SITE_IMAGE_PYTHON:-python3}" scripts/site-phones.py
