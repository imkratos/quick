"""Check language selection and compatibility using the production settings and views."""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/main.swift").read_text().split("let app=NSApplication.shared")[0]
with tempfile.TemporaryDirectory(prefix="quick-language-check-") as directory:
    work = Path(directory)
    main = work / "main.swift"
    main.write_text(source + (root / "checks/localization-check.swift").read_text())
    binary = work / "check"
    subprocess.run(["swiftc", "-swift-version", "5", "-disable-sandbox", str(root / "Sources/Mechanics.swift"), str(root / "Sources/Localization.swift"), str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary), *sys.argv[1:]], check=True)
