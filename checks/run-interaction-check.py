"""Compile the production event handler with interaction regression checks."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
subprocess.run(["swift", "package", "resolve"], cwd=root, check=True)
framework = next((root / ".build/artifacts").glob("sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"))
source = (root / "Sources/main.swift").read_text().split("let app=NSApplication.shared")[0]
with tempfile.TemporaryDirectory(prefix="glassswitch-check-") as directory:
    work = Path(directory)
    main = work / "main.swift"
    main.write_text(source + (root / "checks/interaction-check.swift").read_text())
    binary = work / "check"
    subprocess.run(["swiftc", "-swift-version", "5", "-disable-sandbox", "-F", str(framework), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(framework), str(root / "Sources/Mechanics.swift"), str(root / "Sources/Localization.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
