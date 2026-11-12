#!/usr/bin/env python3
"""Run the launcher generator without its unrelated Xcode-setting rewrites."""
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
subprocess.run([sys.executable, str(ROOT / 'scripts/derive-app-icon.py'), '--full-bleed', '--margin', '0'], check=True)
project = ROOT / 'app/ios/Runner.xcodeproj/project.pbxproj'
original = project.read_bytes()
try:
    # flutter_launcher_icons 0.14.4 replaces every ASSETCATALOG setting in
    # some configurations, including the boolean Swift-symbol flag, with
    # 'AppIcon'. This project already names its catalog AppIcon: retain all
    # native build settings and use only the generated icon resources.
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_CONFIG_')}
    subprocess.run(['dart', 'run', 'flutter_launcher_icons'], cwd=ROOT / 'app', env=env, check=True)
finally:
    project.write_bytes(original)
