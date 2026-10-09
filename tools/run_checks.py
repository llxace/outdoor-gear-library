#!/usr/bin/env python3
"""Compile each independent Swift check entry point without launching the app."""
import argparse
from pathlib import Path
import subprocess
import sys
import shutil
import plistlib

PROJECT = Path(__file__).resolve().parents[1]
CHECKS = ["Tests", "ExcelTests", "ThemeTests", "RefactorRegressionTests", "AsyncWorkflowTests", "WeatherRegressionTests", "BorrowingLifecycleTests", "PhotoPipelineTests", "HistoryEquipmentTests"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checks", nargs="*", help="Entry point names; default: all")
    parser.add_argument("--excel", type=Path, help="Six-sheet baseline workbook for ExcelTests")
    args = parser.parse_args()
    selected = args.checks or CHECKS
    unknown = set(selected) - set(CHECKS)
    if unknown:
        parser.error("Unknown checks: " + ", ".join(sorted(unknown)))
    sources = sorted(str(p) for p in (PROJECT / "Sources").rglob("*.swift") if p.name != "OutdoorGearApp.swift")
    output = PROJECT / "work" / "checks"
    output.mkdir(parents=True, exist_ok=True)
    failures = []
    for name in selected:
        if name == "ExcelTests" and not args.excel:
            print("ExcelTests: SKIP (pass --excel <workbook>)", flush=True)
            continue
        binary = output / name
        if name == "PhotoPipelineTests":
            bundle = output / (name + ".app")
            resources = bundle / "Contents" / "Resources"
            resources.mkdir(parents=True, exist_ok=True)
            shutil.copy2(PROJECT / "Resources" / "product_photo.py", resources / "product_photo.py")
            binary = bundle / "Contents" / "MacOS" / name
            binary.parent.mkdir(exist_ok=True)
            (bundle / "Contents" / "Info.plist").write_bytes(plistlib.dumps({
                "CFBundleExecutable": name, "CFBundleIdentifier": "local.llxace.gear.photo-checks",
                "CFBundlePackageType": "APPL"}))
        command = ["xcrun", "swiftc", "-swift-version", "5", "-parse-as-library", *sources,
                   str(PROJECT / "Tests" / (name + ".swift")), "-o", str(binary)]
        with (output / (name + "-compile.log")).open("w") as log:
            compiled = subprocess.run(command, cwd=PROJECT, stdout=log, stderr=subprocess.STDOUT)
        if compiled.returncode:
            print(name + ": compile failed; see " + str(output / (name + "-compile.log")), flush=True)
            failures.append(name)
            continue
        command = [str(binary)]
        if name == "ExcelTests" and args.excel:
            command.append(str(args.excel.resolve()))
        try:
            result = subprocess.run(command, cwd=PROJECT, capture_output=True, text=True, timeout=120)
            (output / (name + "-run.log")).write_text(result.stdout + result.stderr)
            print(name + ": " + ("PASS" if result.returncode == 0 else "FAIL"), flush=True)
            print(result.stdout.strip(), flush=True)
            if result.returncode:
                failures.append(name)
        except subprocess.TimeoutExpired:
            print(name + ": timed out", flush=True)
            failures.append(name)
    return bool(failures)


if __name__ == "__main__":
    sys.exit(main())
