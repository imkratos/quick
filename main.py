"""Craft Anything entrypoint; the application and all UI are native Swift."""
import os
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent
binary = root / "quick.app/Contents/MacOS/GlassSwitch"
sources = [root / "Sources/main.swift", root / "Package.swift", root / "build.sh", root / "Resources/AppIcon.icns"]
if not binary.exists() or any(p.stat().st_mtime > binary.stat().st_mtime for p in sources):
    subprocess.run(["/bin/sh", str(root / "build.sh")], cwd=root, check=True)
os.execv(str(binary), [str(binary), *sys.argv[1:]])
