#!/usr/bin/env python3
"""Package only the distributable source project, without build/user files."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zipfile


ROOT = Path(__file__).resolve().parent.parent
FOLDERS = ("App", "Keyboard", "Widgets", "Shared", "Tests", "Config", "Resources", "scripts", "Textablage.xcodeproj", ".github")
FILES = ("Package.swift", "README.md", "PRUEFBERICHT.md", ".gitignore")
EXTENSIONS = {".swift", ".plist", ".xcprivacy", ".json", ".png", ".entitlements", ".py", ".md", ".yml", ".pbxproj", ".xcscheme"}


def main():
    paths = [ROOT / name for name in FILES]
    for folder in FOLDERS:
        paths.extend(path for path in (ROOT / folder).rglob("*") if path.is_file() and path.suffix in EXTENSIONS)
    paths = sorted(set(paths), key=lambda path: path.relative_to(ROOT).as_posix())
    payloads = {}
    for path in paths:
        if path.is_symlink():
            raise ValueError(f"Symlink is not distributable: {path.relative_to(ROOT)}")
        relative = path.relative_to(ROOT).as_posix()
        if any(part in {".build", "xcuserdata", "__pycache__", ".git"} for part in Path(relative).parts):
            raise ValueError(f"Private/build path in source list: {relative}")
        payloads[relative] = path.read_bytes()
    sums = "".join(f"{hashlib.sha256(data).hexdigest()}  {name}\n" for name, data in payloads.items())
    payloads["SHA256SUMS"] = sums.encode("utf-8")
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    archive = destination / "Textablage-iPhone-Projekt.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for name, data in payloads.items():
            info = zipfile.ZipInfo("Textablage/" + name, date_time=(2026, 10, 11, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            bundle.writestr(info, data)
    with zipfile.ZipFile(archive) as bundle:
        if bundle.testzip() is not None:
            raise ValueError("Corrupt ZIP")
        if len(bundle.namelist()) != len(payloads):
            raise ValueError("Incorrect ZIP entry count")
        for name, original in payloads.items():
            if bundle.read("Textablage/" + name) != original:
                raise ValueError(f"ZIP changed file: {name}")
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "Textablage-iPhone-Projekt.zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    print(json.dumps({"archive": str(archive), "files": len(payloads), "bytes": archive.stat().st_size, "sha256": digest}))


if __name__ == "__main__":
    main()
