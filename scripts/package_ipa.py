#!/usr/bin/env python3
"""Package a real, unsigned iPhone .xcarchive; never compile or sign an app."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import stat
import struct
import tempfile
import zipfile


class InvalidArchive(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidArchive(message)


def read_plist(path):
    require(path.is_file() and not path.is_symlink(), f"Missing regular plist: {path.name}")
    with path.open("rb") as stream:
        value = plistlib.load(stream)
    require(isinstance(value, dict), f"Invalid plist: {path.name}")
    return value


def safe_name(name):
    require(isinstance(name, str) and name and not any(ord(c) < 32 for c in name), "Invalid path text")
    parts = PurePosixPath(name)
    require(not parts.is_absolute() and all(p not in {"", ".", ".."} for p in name.split("/")), "Unsafe relative path")
    require("\\" not in name, "Backslash in archive path")
    return parts


def validate_macho(path, filetype=2):
    """Check every slice: ARM64, executable/dylib, iOS device, unsigned."""
    require(path.is_file() and not path.is_symlink(), f"Missing regular executable: {path.name}")
    require(path.stat().st_mode & 0o111, f"Executable permission missing: {path.name}")
    data = path.read_bytes()
    require(len(data) >= 32, f"Truncated executable: {path.name}")
    magic = data[:4]
    if magic in {b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}:
        count = struct.unpack_from(">I", data, 4)[0]
        width = 32 if magic[-1] == 0xbf else 20
        require(0 < count <= 16 and 8 + count * width <= len(data), "Invalid universal executable")
        slices = []
        for index in range(count):
            offset = 8 + index * width
            cpu = struct.unpack_from(">I", data, offset)[0]
            position, length = struct.unpack_from(">QQ" if width == 32 else ">II", data, offset + 8)
            require(cpu == 0x0100000C and position >= 8 + count * width and length >= 32, "Non-ARM64 or invalid slice")
            require(position + length <= len(data), "Executable slice exceeds file")
            require(all(position + length <= old_start or position >= old_end for old_start, old_end in slices), "Overlapping executable slices")
            slices.append((position, position + length))
    else:
        slices = [(0, len(data))]
    for start, end in slices:
        require(data[start:start + 4] == b"\xcf\xfa\xed\xfe", "Not a 64-bit little-endian Mach-O")
        _, cpu, _, kind, count, size, _, _ = struct.unpack_from("<8I", data, start)
        require(cpu == 0x0100000C and kind == filetype, "Wrong Mach-O architecture or file type")
        require(count > 0 and size >= 8 * count and start + 32 + size <= end, "Invalid Mach-O commands")
        position, limit, device_platform, has_entry = start + 32, start + 32 + size, False, False
        for _ in range(count):
            require(position + 8 <= limit, "Truncated Mach-O command")
            command, length = struct.unpack_from("<II", data, position)
            require(length >= 8 and length % 8 == 0 and position + length <= limit, "Invalid Mach-O command size")
            require(command != 0x1d, "Signed binary found; this packager only accepts unsigned archives")
            if command == 0x32:  # LC_BUILD_VERSION: platform 2=iOS, 7=iOS simulator.
                require(length >= 24, "Invalid build-version command")
                platform, _, _, tools = struct.unpack_from("<4I", data, position + 8)
                require(platform == 2 and 24 + tools * 8 == length, "Executable is not an iPhone device build")
                device_platform = True
            if command == 0x80000028:  # LC_MAIN
                require(length == 24, "Invalid executable entry command")
                entry = struct.unpack_from("<Q", data, position + 8)[0]
                require(0 < entry < end - start, "Invalid executable entry point")
                has_entry = True
            position += length
        require(position == limit and device_platform, "Missing valid iOS device build metadata")
        require(filetype != 2 or has_entry, "Missing executable entry point")


def validate_bundle(bundle, package_type, parent_identifier=None):
    info = read_plist(bundle / "Info.plist")
    identifier, executable = info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")
    require(isinstance(identifier, str) and re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", identifier), "Missing valid resolved bundle identifier")
    require(info.get("CFBundlePackageType") == package_type, f"Wrong bundle package type: {bundle.name}")
    require(isinstance(executable, str) and "$" not in executable and len(safe_name(executable).parts) == 1, "Invalid bundle executable name")
    require(all(isinstance(info.get(key), str) and info[key] and "$" not in info[key]
                for key in ("CFBundleShortVersionString", "CFBundleVersion")), "Missing resolved bundle versions")
    require(info.get("CFBundleSupportedPlatforms") == ["iPhoneOS"], "Bundle is not an iPhone device build")
    if parent_identifier:
        require(identifier.startswith(parent_identifier + "."), "Extension identifier must belong to app")
        extension = info.get("NSExtension")
        require(isinstance(extension, dict) and isinstance(extension.get("NSExtensionPointIdentifier"), str)
                and extension["NSExtensionPointIdentifier"], "Missing extension point")
    validate_macho(bundle / executable, 6 if package_type == "FMWK" else 2)
    return identifier


def collect_files(app):
    entries = [(app, "Payload/" + app.name)]
    for root, directories, files in os.walk(app, followlinks=False):
        for name in sorted(directories + files):
            path = Path(root) / name
            if name in {".DS_Store", "__MACOSX"}:
                if name in directories:
                    directories.remove(name)
                continue
            relative = path.relative_to(app).as_posix()
            safe_name(relative)
            require(name not in {".git", "_CodeSignature", "embedded.mobileprovision"}, "Unexpected repository or signing data")
            require(path.suffix.lower() not in {".p12", ".pfx", ".mobileprovision"}, "Signing credentials must not enter an IPA")
            mode = path.lstat().st_mode
            require(stat.S_ISREG(mode) or stat.S_ISDIR(mode) or stat.S_ISLNK(mode), "Unsupported filesystem entry")
            require(not mode & 0o7000, "Unexpected privileged file mode")
            if stat.S_ISLNK(mode):
                target = os.readlink(path)
                require(not Path(target).is_absolute() and "\\" not in target, "Unsafe symlink target")
                require(not any(ord(c) < 32 for c in target), "Invalid symlink target")
                resolved = path.resolve(strict=True)
                require(resolved.is_relative_to(app), "Symlink escapes app bundle")
            entries.append((path, "Payload/" + app.name + "/" + relative))
    return sorted(entries, key=lambda pair: pair[1])


def package(archive, output):
    archive = archive.resolve(strict=True)
    require(archive.is_dir() and archive.suffix == ".xcarchive", "Input must be an actual .xcarchive directory")
    archive_info = read_plist(archive / "Info.plist")
    properties = archive_info.get("ApplicationProperties")
    require(isinstance(properties, dict), "Archive has no application properties")
    application_path = safe_name(properties.get("ApplicationPath"))
    require(len(application_path.parts) == 2 and application_path.parts[0] == "Applications", "Invalid application path in archive")
    application_dir = archive / "Products" / "Applications"
    app = application_dir / application_path.name
    require(app.is_dir() and app.suffix == ".app" and not app.is_symlink(), "Missing archive app bundle")
    require(app.resolve() == app and app.is_relative_to(archive), "Archive app path traverses symlinks")
    require(list(application_dir.glob("*.app")) == [app], "Archive must contain exactly one app")
    identifier = validate_bundle(app, "APPL")
    require(properties.get("CFBundleIdentifier") == identifier, "Archive and app identifiers disagree")
    extensions = []
    for extension in sorted(app.rglob("*.appex")):
        require(extension.parent == app / "PlugIns" and not extension.is_symlink(), "Unexpected nested extension")
        extensions.append(validate_bundle(extension, "XPC!", identifier))
    require(len(extensions) == len(set(extensions)), "Duplicate extension identifier")
    for framework in sorted(app.rglob("*.framework")):
        require(not framework.is_symlink(), "Unexpected framework symlink")
        validate_bundle(framework, "FMWK")
    for library in sorted(app.rglob("*.dylib")):
        validate_macho(library, 6)
    require(not any(app.rglob("*.app")), "Unexpected app nested inside bundle")
    entries = collect_files(app)
    output = output.absolute()
    require(output.suffix.lower() == ".ipa" and not output.resolve().is_relative_to(archive), "Output must be an .ipa outside the input archive")
    output.parent.mkdir(parents=True, exist_ok=True)
    metadata_path, checksum_path = Path(str(output) + ".json"), Path(str(output) + ".sha256")
    require(not any(p.exists() or p.is_symlink() for p in (output, metadata_path, checksum_path)), "Output already exists; choose a new path")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".tmp", delete=False) as file:
            temporary = Path(file.name)
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
            payload = zipfile.ZipInfo("Payload/", date_time=(1980, 1, 1, 0, 0, 0))
            payload.create_system, payload.external_attr = 3, (stat.S_IFDIR | 0o755) << 16 | 0x10
            bundle.writestr(payload, b"")
            for path, name in entries:
                mode = path.lstat().st_mode
                info = zipfile.ZipInfo(name + ("/" if stat.S_ISDIR(mode) else ""), date_time=(1980, 1, 1, 0, 0, 0))
                info.create_system, info.compress_type = 3, zipfile.ZIP_DEFLATED
                info.external_attr = (stat.S_IFMT(mode) | stat.S_IMODE(mode)) << 16
                if stat.S_ISDIR(mode):
                    info.external_attr |= 0x10
                    data = b""
                else:
                    data = os.readlink(path).encode("utf-8") if stat.S_ISLNK(mode) else path.read_bytes()
                bundle.writestr(info, data)
        with zipfile.ZipFile(temporary) as bundle:
            require(bundle.testzip() is None and len(bundle.namelist()) == len(entries) + 1, "IPA verification failed")
        digest = hashlib.sha256(temporary.read_bytes()).hexdigest()
        metadata = {"formatVersion": 1, "kind": "unsigned-iPhone-IPA", "bundleIdentifier": identifier,
                    "extensions": extensions, "architecture": "arm64", "platform": "iPhoneOS",
                    "signed": False, "requiresSigningBeforeInstallation": True, "sha256": digest,
                    "filename": output.name, "zipEntries": len(entries) + 1}
        os.replace(temporary, output)
        temporary = None
        checksum_path.write_text(f"{digest}  {output.name}\n", encoding="utf-8")
        metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        return metadata
    except BaseException:
        for path in (output, checksum_path, metadata_path):
            path.unlink(missing_ok=True)
        raise
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path, help="Apple-SDK-built unsigned .xcarchive")
    parser.add_argument("--output", type=Path, required=True, help="New output .ipa file")
    args = parser.parse_args()
    try:
        print(json.dumps(package(args.archive, args.output)))
    except (OSError, ValueError, RuntimeError, struct.error, plistlib.InvalidFileException) as error:
        parser.exit(1, f"IPA not created: {error}\n")


if __name__ == "__main__":
    main()
