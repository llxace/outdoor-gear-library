#!/usr/bin/env python3
"""Use Xcode's Swift parser to enforce the production function length rule."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
swift = Path(subprocess.check_output(["xcrun", "--find", "swiftc"], text=True).strip())
host = swift.parent.parent / "lib" / "swift" / "host"
out = root / "work" / "checks"
out.mkdir(parents=True, exist_ok=True)
binary = out / "check-structure"
subprocess.run(["xcrun", "swiftc", str(root / "tools" / "CheckStructure.swift"), "-o", str(binary),
                "-I", str(host), "-L", str(host), "-Xlinker", "-rpath", "-Xlinker", str(host),
                "-lSwiftSyntax", "-lSwiftParser"], check=True)
subprocess.run([str(binary), str(root / "Sources")], check=True)
