"""Exercise production keyboard handling against two real disposable macOS apps."""
from pathlib import Path
import plistlib
import subprocess
import tempfile
import sys
import fcntl

root = Path(__file__).resolve().parents[1]
# These tests share the desktop and global shortcut registry and must run alone.
(root / ".build").mkdir(exist_ok=True)
lock = (root / ".build/keyboard-e2e.lock").open("w")
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit("已有跨应用键盘检查正在运行，请等待其完成。")
subprocess.run(["swift", "package", "resolve"], cwd=root, check=True)
framework = next((root / ".build/artifacts").glob("sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"))
source = (root / "Sources/main.swift").read_text().split("let app=NSApplication.shared")[0]
with tempfile.TemporaryDirectory(prefix="glassswitch-keyboard-") as directory:
    work = Path(directory)
    target_main = work / "target" / "main.swift"
    target_main.parent.mkdir()
    target_main.write_text((root / "checks/keyboard-target.swift").read_text())
    target_binary = work / "target-bin"
    subprocess.run(["swiftc", str(target_main), "-o", str(target_binary)], check=True)
    for name in ("A", "B"):
        contents = work / f"{name}.app" / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/Target").write_bytes(target_binary.read_bytes())
        (contents / "MacOS/Target").chmod(0o755)
        (contents / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": f"local.glassswitch.keyboard-check.{name}", "CFBundleExecutable": "Target", "CFBundleName": f"Keyboard Target {name}", "CFBundlePackageType": "APPL"}))
        subprocess.run(["codesign", "--force", "--sign", "-", str(contents.parent)], check=True, capture_output=True)
    main = work / "main.swift"
    main.write_text(source + (root / "checks/keyboard-e2e.swift").read_text())
    binary = work / "check"
    subprocess.run(["swiftc", "-swift-version", "5", "-disable-sandbox", "-F", str(framework), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(framework), str(root / "Sources/Mechanics.swift"), str(root / "Sources/Localization.swift"), str(main), "-o", str(binary)], check=True)
    for mode in sys.argv[1:] or ("fallback", "tap"):
        subprocess.run([str(binary), str(work), mode, str(root / "quick.app")], check=True, timeout=45)
