"""Compile the production event handler with interaction regression checks."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/main.swift").read_text().split("let app=NSApplication.shared")[0]
with tempfile.TemporaryDirectory(prefix="glassswitch-check-") as directory:
    work = Path(directory)
    main = work / "main.swift"
    main.write_text(source + (root / "checks/interaction-check.swift").read_text())
    binary = work / "check"
    subprocess.run(["swiftc", str(root / "Sources/Mechanics.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
