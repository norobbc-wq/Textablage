#!/usr/bin/env python3
"""Generate the checked-in Xcode project with Python's standard library only.

Run from any directory: python3 scripts/generate_project.py
The project root is derived from this file; no account or private file is read.
"""

from __future__ import annotations

import hashlib
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "Textablage.xcodeproj"


class Ref(str):
    """A reference to another PBX object, serialized without string quotes."""


class ProjectBuilder:
    def __init__(self):
        self.objects: dict[Ref, dict] = {}
        self.names: dict[Ref, str] = {}
        self.id_keys: dict[Ref, str] = {}

    def ref(self, key: str) -> Ref:
        object_id = Ref(hashlib.sha256(key.encode("utf-8")).hexdigest()[:24].upper())
        previous = self.id_keys.setdefault(object_id, key)
        if previous != key:
            raise ValueError(f"PBX identifier collision: {key}")
        return object_id

    def add(self, key: str, label: str, **fields) -> Ref:
        object_id = self.ref(key)
        if object_id in self.objects:
            raise ValueError(f"Duplicate PBX object: {key}")
        self.objects[object_id] = fields
        self.names[object_id] = label
        return object_id

    def encode(self, value, level: int = 0) -> str:
        if isinstance(value, Ref):
            comment = self.names.get(value, "").replace("*/", "")
            return f"{value} /* {comment} */" if comment else str(value)
        if isinstance(value, str):
            escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
            return f'"{escaped}"'
        if isinstance(value, int):
            return str(value)
        if isinstance(value, list):
            if not value:
                return "()"
            pad = "\t" * level
            return "(\n" + "".join(f"{pad}\t{self.encode(item, level + 1)},\n" for item in value) + pad + ")"
        if isinstance(value, dict):
            if not value:
                return "{}"
            pad = "\t" * level
            rows = []
            for key, item in value.items():
                encoded_key = key if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key) else self.encode(key)
                rows.append(f"{pad}\t{encoded_key} = {self.encode(item, level + 1)};\n")
            return "{\n" + "".join(rows) + pad + "}"
        raise TypeError(f"Unsupported PBX value: {type(value)}")

    def serialize(self, project_id: Ref) -> str:
        sections = []
        for kind in sorted({obj["isa"] for obj in self.objects.values()}):
            sections.append(f"\n/* Begin {kind} section */\n")
            for object_id in sorted(self.objects):
                obj = self.objects[object_id]
                if obj["isa"] == kind:
                    sections.append(f"\t\t{self.encode(object_id)} = {self.encode(obj, 2)};\n")
            sections.append(f"/* End {kind} section */\n")
        return (
            "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n"
            "\tobjects = {\n" + "".join(sections) + "\t};\n"
            f"\trootObject = {self.encode(project_id)};\n}}\n"
        )

    def validate(self):
        def check(value):
            if isinstance(value, Ref):
                if value not in self.objects:
                    raise ValueError(f"Unresolved PBX reference: {value}")
            elif isinstance(value, dict):
                for item in value.values():
                    check(item)
            elif isinstance(value, list):
                for item in value:
                    check(item)

        for obj in self.objects.values():
            check(obj)

        targets = {ref: obj for ref, obj in self.objects.items() if obj["isa"] == "PBXNativeTarget"}
        visiting, visited = set(), set()

        def visit(ref):
            if ref in visiting:
                raise ValueError("Cycle in target dependencies")
            if ref in visited:
                return
            visiting.add(ref)
            for dependency in targets[ref]["dependencies"]:
                target = self.objects[dependency]["target"]
                if target not in targets:
                    raise ValueError("Dependency does not reference a native target")
                visit(target)
            visiting.remove(ref)
            visited.add(ref)

        for ref in targets:
            visit(ref)
            target = targets[ref]
            source_phases = [self.objects[phase] for phase in target["buildPhases"] if self.objects[phase]["isa"] == "PBXSourcesBuildPhase"]
            if len(source_phases) != 1 or not source_phases[0]["files"]:
                raise ValueError(f"Missing source files for {target['name']}")


def checked_path(relative: str) -> Path:
    path = ROOT / relative
    if not path.exists():
        raise FileNotFoundError(f"Required project input is missing: {relative}")
    path.resolve().relative_to(ROOT)
    return path


def source_inputs():
    folders = {}
    for folder in ("App", "Shared", "Keyboard", "Widgets"):
        directory = checked_path(folder)
        paths = sorted(path.relative_to(ROOT).as_posix() for path in directory.rglob("*.swift") if path.is_file())
        if not paths:
            raise ValueError(f"No Swift sources in {folder}")
        for path in paths:
            checked_path(path)
        folders[folder] = paths
    for relative in (
        "App/Info.plist", "Keyboard/Info.plist", "Widgets/Info.plist",
        "Resources/Assets.xcassets", "Resources/Assets.xcassets/Contents.json",
        "Resources/Assets.xcassets/AppIcon.appiconset/Contents.json",
        "Resources/PrivacyInfo.xcprivacy", "Config/Shared.entitlements",
    ):
        checked_path(relative)
    for relative in ("App/Info.plist", "Keyboard/Info.plist", "Widgets/Info.plist", "Resources/PrivacyInfo.xcprivacy", "Config/Shared.entitlements"):
        with checked_path(relative).open("rb") as stream:
            plistlib.load(stream)
    for folder in ("App", "Keyboard", "Widgets"):
        with checked_path(f"{folder}/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        required = ("CFBundleExecutable", "CFBundleIdentifier", "CFBundleName", "CFBundlePackageType", "CFBundleShortVersionString", "CFBundleVersion")
        for key in required:
            if not isinstance(info.get(key), str) or not info[key]:
                raise ValueError(f"Missing bundle metadata: {folder}/Info.plist {key}")
        expected_type = "APPL" if folder == "App" else "XPC!"
        if info["CFBundlePackageType"] != expected_type:
            raise ValueError(f"Invalid bundle type: {folder}/Info.plist")
    return folders


def make_scheme(builder: ProjectBuilder, app: Ref, extensions: list[Ref]) -> bytes:
    root = ET.Element("Scheme", {"LastUpgradeVersion": "1500", "version": "1.7"})

    def buildable(parent, ref):
        target = builder.objects[ref]
        ET.SubElement(parent, "BuildableReference", {
            "BuildableIdentifier": "primary", "BlueprintIdentifier": str(ref),
            "BuildableName": builder.objects[target["productReference"]]["path"],
            "BlueprintName": target["name"], "ReferencedContainer": "container:Textablage.xcodeproj",
        })

    action = ET.SubElement(root, "BuildAction", {"parallelizeBuildables": "YES", "buildImplicitDependencies": "YES"})
    entries = ET.SubElement(action, "BuildActionEntries")
    for ref in [*extensions, app]:
        entry = ET.SubElement(entries, "BuildActionEntry", {
            "buildForTesting": "YES", "buildForRunning": "YES", "buildForProfiling": "YES",
            "buildForArchiving": "YES", "buildForAnalyzing": "YES",
        })
        buildable(entry, ref)
    test = ET.SubElement(root, "TestAction", {"buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB", "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB", "shouldUseLaunchSchemeArgsEnv": "YES"})
    ET.SubElement(test, "Testables")
    launch = ET.SubElement(root, "LaunchAction", {"buildConfiguration": "Debug", "selectedDebuggerIdentifier": "Xcode.DebuggerFoundation.Debugger.LLDB", "selectedLauncherIdentifier": "Xcode.DebuggerFoundation.Launcher.LLDB", "launchStyle": "0", "useCustomWorkingDirectory": "NO", "ignoresPersistentStateOnLaunch": "NO", "debugDocumentVersioning": "YES", "debugServiceExtension": "internal", "allowLocationSimulation": "YES"})
    buildable(ET.SubElement(launch, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), app)
    profile = ET.SubElement(root, "ProfileAction", {"buildConfiguration": "Release", "shouldUseLaunchSchemeArgsEnv": "YES", "savedToolIdentifier": "", "useCustomWorkingDirectory": "NO", "debugDocumentVersioning": "YES"})
    buildable(ET.SubElement(profile, "BuildableProductRunnable", {"runnableDebuggingMode": "0"}), app)
    ET.SubElement(root, "AnalyzeAction", {"buildConfiguration": "Debug"})
    ET.SubElement(root, "ArchiveAction", {"buildConfiguration": "Release", "revealArchiveInOrganizer": "YES"})
    ET.indent(root, space="  ")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True) + b"\n"


def generate():
    sources = source_inputs()
    builder = ProjectBuilder()
    project_ref = builder.ref("project")
    target_specs = [
        ("Textablage", "App", "de.textablage.personal", False, ["TextablageKeyboard"]),
        ("TextablageKeyboard", "Keyboard", "de.textablage.personal.keyboard", False, []),
        ("TextablageShared", "App", "de.textablage.personal.shared", True, ["TextablageKeyboardShared", "TextablageWidgets"]),
        ("TextablageKeyboardShared", "Keyboard", "de.textablage.personal.shared.keyboard", True, []),
        ("TextablageWidgets", "Widgets", "de.textablage.personal.shared.widgets", True, []),
    ]
    target_refs = {name: builder.ref(f"target:{name}") for name, *_ in target_specs}
    file_refs = {}
    groups = []
    suffix_types = {".swift": "sourcecode.swift", ".plist": "text.plist.xml", ".xcprivacy": "text.xml", ".entitlements": "text.plist.entitlements", ".xcassets": "folder.assetcatalog"}
    folder_files = {**sources, "Resources": ["Resources/Assets.xcassets", "Resources/PrivacyInfo.xcprivacy"], "Config": ["Config/Shared.entitlements"]}
    for folder in ("App", "Shared", "Keyboard", "Widgets"):
        if folder != "Shared":
            folder_files[folder] = [*folder_files[folder], f"{folder}/Info.plist"]
    for folder, paths in folder_files.items():
        children = []
        for path in paths:
            relative = Path(path).relative_to(folder).as_posix()
            file_ref = builder.add(f"file:{path}", Path(path).name, isa="PBXFileReference", lastKnownFileType=suffix_types[Path(path).suffix], path=relative, sourceTree="<group>")
            file_refs[path] = file_ref
            children.append(file_ref)
        groups.append(builder.add(f"group:{folder}", folder, isa="PBXGroup", children=children, path=folder, sourceTree="<group>"))

    products = []
    for name, folder, bundle_id, shared, embeds in target_specs:
        is_app = folder == "App"
        product = builder.add(f"product:{name}", name + (".app" if is_app else ".appex"), isa="PBXFileReference", explicitFileType="wrapper.application" if is_app else "wrapper.app-extension", includeInIndex=0, path=name + (".app" if is_app else ".appex"), sourceTree="BUILT_PRODUCTS_DIR")
        products.append(product)
        source_files = []
        for path in [*sources[folder], *sources["Shared"]]:
            source_files.append(builder.add(f"build:{name}:source:{path}", f"{Path(path).name} in Sources", isa="PBXBuildFile", fileRef=file_refs[path]))
        resources = ["Resources/PrivacyInfo.xcprivacy"]
        if is_app:
            resources.insert(0, "Resources/Assets.xcassets")
        resource_files = [builder.add(f"build:{name}:resource:{path}", f"{Path(path).name} in Resources", isa="PBXBuildFile", fileRef=file_refs[path]) for path in resources]
        phases = []
        for kind, files, label in (("PBXSourcesBuildPhase", source_files, "Sources"), ("PBXFrameworksBuildPhase", [], "Frameworks"), ("PBXResourcesBuildPhase", resource_files, "Resources")):
            phases.append(builder.add(f"phase:{name}:{label}", label, isa=kind, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0))
        dependencies = []
        if embeds:
            embed_files = []
            for child in embeds:
                child_product = builder.ref(f"product:{child}")
                embed_files.append(builder.add(f"build:{name}:embed:{child}", f"{child}.appex in Embed App Extensions", isa="PBXBuildFile", fileRef=child_product, settings={"ATTRIBUTES": ["CodeSignOnCopy", "RemoveHeadersOnCopy"]}))
                proxy = builder.add(f"proxy:{name}:{child}", "PBXContainerItemProxy", isa="PBXContainerItemProxy", containerPortal=project_ref, proxyType=1, remoteGlobalIDString=target_refs[child], remoteInfo=child)
                dependencies.append(builder.add(f"dependency:{name}:{child}", child, isa="PBXTargetDependency", target=target_refs[child], targetProxy=proxy))
            phases.append(builder.add(f"phase:{name}:embed", "Embed App Extensions", isa="PBXCopyFilesBuildPhase", buildActionMask=2147483647, dstPath="", dstSubfolderSpec=13, files=embed_files, name="Embed App Extensions", runOnlyForDeploymentPostprocessing=0))
        configs = []
        for configuration in ("Debug", "Release"):
            settings = {
                "CODE_SIGN_STYLE": "Automatic", "DEVELOPMENT_TEAM": "",
                "CURRENT_PROJECT_VERSION": "1", "MARKETING_VERSION": "1.0.0",
                "GENERATE_INFOPLIST_FILE": "NO", "INFOPLIST_FILE": f"{folder}/Info.plist",
                "PRODUCT_BUNDLE_IDENTIFIER": bundle_id, "PRODUCT_NAME": "$(TARGET_NAME)",
                "SWIFT_VERSION": "5.0", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
                "TARGETED_DEVICE_FAMILY": "1", "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                "SUPPORTS_MACCATALYST": "NO", "SKIP_INSTALL": "NO" if is_app else "YES",
                "TEXTABLAGE_APP_GROUP": "group.de.textablage.personal" if shared else "",
                "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", *([] if is_app else ["@executable_path/../../Frameworks"])],
            }
            if is_app:
                settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = "AppIcon"
            else:
                settings["APPLICATION_EXTENSION_API_ONLY"] = "YES"
            if shared:
                settings["CODE_SIGN_ENTITLEMENTS"] = "Config/Shared.entitlements"
            configs.append(builder.add(f"config:{name}:{configuration}", configuration, isa="XCBuildConfiguration", buildSettings=settings, name=configuration))
        configuration_list = builder.add(f"config-list:{name}", f"Build configuration list for {name}", isa="XCConfigurationList", buildConfigurations=configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
        builder.add(f"target:{name}", name, isa="PBXNativeTarget", buildConfigurationList=configuration_list, buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name, productReference=product, productType="com.apple.product-type.application" if is_app else "com.apple.product-type.app-extension")

    products_group = builder.add("group:products", "Products", isa="PBXGroup", children=products, name="Products", sourceTree="<group>")
    main_group = builder.add("group:main", "Main Group", isa="PBXGroup", children=[*groups, products_group], sourceTree="<group>")
    project_configs = []
    for configuration in ("Debug", "Release"):
        settings = {"CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES", "SDKROOT": "iphoneos", "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SWIFT_VERSION": "5.0", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "DEBUG_INFORMATION_FORMAT": "dwarf" if configuration == "Debug" else "dwarf-with-dsym", "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if configuration == "Debug" else "-O"}
        if configuration == "Debug":
            settings.update({"ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": ["DEBUG", "$(inherited)"]})
        else:
            settings["SWIFT_COMPILATION_MODE"] = "wholemodule"
        project_configs.append(builder.add(f"config:project:{configuration}", configuration, isa="XCBuildConfiguration", buildSettings=settings, name=configuration))
    project_configs_ref = builder.add("config-list:project", "Build configuration list for project", isa="XCConfigurationList", buildConfigurations=project_configs, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
    builder.add("project", "Project object", isa="PBXProject", attributes={"LastSwiftUpdateCheck": "1500", "LastUpgradeCheck": "1500", "TargetAttributes": {str(ref): {"CreatedOnToolsVersion": "15.0", "ProvisioningStyle": "Automatic"} for ref in target_refs.values()}}, buildConfigurationList=project_configs_ref, compatibilityVersion="Xcode 14.0", developmentRegion="de", hasScannedForEncodings=0, knownRegions=["de", "en", "Base"], mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="", targets=list(target_refs.values()))
    builder.validate()
    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(builder.serialize(project_ref), encoding="utf-8")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    for scheme_name, app_name, extension_names in (("Textablage", "Textablage", ["TextablageKeyboard"]), ("Textablage-Gemeinsam", "TextablageShared", ["TextablageKeyboardShared", "TextablageWidgets"])):
        (schemes / f"{scheme_name}.xcscheme").write_bytes(make_scheme(builder, target_refs[app_name], [target_refs[name] for name in extension_names]))
    print(f"Generated {len(target_specs)} targets and 2 shared schemes; {len(builder.objects)} PBX objects validated.")


if __name__ == "__main__":
    generate()
