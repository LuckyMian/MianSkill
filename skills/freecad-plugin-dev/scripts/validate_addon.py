#!/usr/bin/env python3
"""Validate a FreeCAD 1.1 Python workbench package in this repository."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


DEFAULT_FREECAD_CMD = Path(r"C:\Program Files\FreeCAD 1.1\bin\FreeCADCmd.exe")
EXPECTED_REPOSITORY = "https://github.com/LuckyMian/FreeCad_Plugins"
ADDON_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
PLACEHOLDER_RE = re.compile(r"__[A-Z][A-Z0-9_]*__")


class ValidationError(Exception):
    pass


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child_text(element: ET.Element, name: str) -> str:
    for child in element:
        if local_name(child.tag) == name:
            return (child.text or "").strip()
    return ""


def package_children(root: ET.Element, name: str) -> list[ET.Element]:
    return [child for child in root if local_name(child.tag) == name]


def validate_package(plugin_root: Path) -> tuple[str, str]:
    package_path = plugin_root / "package.xml"
    if not package_path.is_file():
        raise ValidationError(f"missing package.xml: {package_path}")

    try:
        tree = ET.parse(package_path)
    except ET.ParseError as exc:
        raise ValidationError(f"invalid package.xml: {exc}") from exc

    root = tree.getroot()
    if local_name(root.tag) != "package":
        raise ValidationError("package.xml root element must be <package>")

    package_name = child_text(root, "name")
    description = child_text(root, "description")
    version = child_text(root, "version")
    release_date = child_text(root, "date")
    maintainer = package_children(root, "maintainer")
    license_name = child_text(root, "license")

    if not package_name:
        raise ValidationError("package.xml is missing <name>")
    if not description:
        raise ValidationError("package.xml is missing <description>")
    if not VERSION_RE.fullmatch(version):
        raise ValidationError(f"<version> must be a semantic version, got {version!r}")
    if not DATE_RE.fullmatch(release_date):
        raise ValidationError(f"<date> must use YYYY-MM-DD, got {release_date!r}")
    if not maintainer or not (maintainer[0].text or "").strip():
        raise ValidationError("package.xml is missing a non-empty <maintainer>")
    if not license_name:
        raise ValidationError("package.xml is missing <license>")

    urls = package_children(root, "url")
    repository_urls = [
        ((url.text or "").strip(), url.attrib.get("branch", ""))
        for url in urls
        if url.attrib.get("type") == "repository"
    ]
    if not repository_urls:
        raise ValidationError("package.xml is missing a repository <url>")
    repository_url, branch = repository_urls[0]
    normalized_repository = repository_url.removesuffix(".git").rstrip("/")
    if normalized_repository != EXPECTED_REPOSITORY:
        raise ValidationError(
            f"repository URL must be {EXPECTED_REPOSITORY}, got {repository_url!r}"
        )
    if branch != "main":
        raise ValidationError(f"repository branch must be 'main', got {branch!r}")

    content = next(
        (child for child in root if local_name(child.tag) == "content"),
        None,
    )
    if content is None:
        raise ValidationError("package.xml is missing <content>")
    workbench = next(
        (child for child in content if local_name(child.tag) == "workbench"),
        None,
    )
    if workbench is None:
        raise ValidationError("package.xml must declare a <workbench>")

    workbench_name = child_text(workbench, "name")
    subdirectory = child_text(workbench, "subdirectory")
    if not workbench_name:
        raise ValidationError("<workbench> is missing <name>")
    if not subdirectory:
        raise ValidationError("<workbench> is missing <subdirectory>")

    resolved_subdirectory = (plugin_root / subdirectory).resolve()
    try:
        resolved_subdirectory.relative_to(plugin_root.resolve())
    except ValueError as exc:
        raise ValidationError("<subdirectory> must stay inside the plugin root") from exc
    if not resolved_subdirectory.is_dir():
        raise ValidationError(
            f"workbench subdirectory does not exist: {resolved_subdirectory}"
        )

    return workbench_name, package_name


def validate_files(plugin_root: Path) -> None:
    addon_id = plugin_root.name
    if not ADDON_ID_RE.fullmatch(addon_id):
        raise ValidationError(
            f"plugin directory must be lowercase letters, digits, and hyphens: {addon_id!r}"
        )

    gui_entry = plugin_root / "InitGui.py"
    if not gui_entry.is_file():
        raise ValidationError(f"missing InitGui.py: {gui_entry}")
    gui_source = gui_entry.read_text(encoding="utf-8")
    if "addWorkbench" not in gui_source:
        raise ValidationError("InitGui.py must call FreeCADGui.addWorkbench(...)")

    python_files = sorted(
        path
        for path in plugin_root.rglob("*.py")
        if "__pycache__" not in path.parts
    )
    if not python_files:
        raise ValidationError("plugin contains no Python files")

    for path in python_files:
        source = path.read_text(encoding="utf-8")
        placeholders = sorted(set(PLACEHOLDER_RE.findall(source)))
        if placeholders:
            joined = ", ".join(placeholders)
            raise ValidationError(f"unreplaced template placeholders in {path}: {joined}")
        try:
            compile(source, str(path), "exec")
        except SyntaxError as exc:
            raise ValidationError(f"Python syntax error in {path}: {exc}") from exc


def detect_smoke_module(plugin_root: Path) -> str:
    if (plugin_root / "core.py").is_file():
        return "core"

    packages = sorted(
        path.name
        for path in plugin_root.iterdir()
        if path.is_dir()
        and path.name != "tests"
        and (path / "__init__.py").is_file()
    )
    return packages[0] if len(packages) == 1 else ""


def run_freecad_smoke(plugin_root: Path, freecad_cmd: Path) -> None:
    if not freecad_cmd.is_file():
        raise ValidationError(f"FreeCADCmd not found: {freecad_cmd}")

    plugin_path = str(plugin_root.resolve())
    smoke_module = detect_smoke_module(plugin_root)
    if smoke_module and smoke_module != "core":
        package_core = plugin_root / smoke_module / "core.py"
        if package_core.is_file():
            smoke_module = f"{smoke_module}.core"
    code = (
        "import sys; "
        f"sys.path.insert(0, {plugin_path!r}); "
        "import FreeCAD; "
        "print('FREECAD=' + '.'.join(FreeCAD.Version()[:3])); "
    )
    if smoke_module:
        code += f"import {smoke_module}; print('SMOKE_IMPORT={smoke_module}')"
    else:
        code += "print('SMOKE_IMPORT=none')"

    result = subprocess.run(
        [str(freecad_cmd), "-c", code],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        check=False,
    )
    output = "\n".join(part for part in (result.stdout, result.stderr) if part).strip()
    if result.returncode != 0:
        raise ValidationError(f"FreeCADCmd smoke test failed:\n{output}")
    if "SMOKE_IMPORT=" not in output:
        raise ValidationError(f"FreeCADCmd did not complete the smoke test:\n{output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plugin_root", type=Path, help="Path to plugins/<addon-id>")
    parser.add_argument(
        "--freecad-cmd",
        type=Path,
        default=DEFAULT_FREECAD_CMD,
        help=f"FreeCADCmd.exe path (default: {DEFAULT_FREECAD_CMD})",
    )
    parser.add_argument(
        "--skip-freecad",
        action="store_true",
        help="Skip the FreeCADCmd smoke test",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    plugin_root = args.plugin_root.resolve()
    try:
        if not plugin_root.is_dir():
            raise ValidationError(f"plugin directory not found: {plugin_root}")
        workbench_name, package_name = validate_package(plugin_root)
        validate_files(plugin_root)
        if not args.skip_freecad:
            run_freecad_smoke(plugin_root, args.freecad_cmd)
    except (ValidationError, OSError, subprocess.SubprocessError) as exc:
        print(f"[ERROR] {exc}", file=sys.stderr)
        return 1

    print(f"[OK] package: {package_name}")
    print(f"[OK] workbench: {workbench_name}")
    print(f"[OK] plugin root: {plugin_root}")
    if not args.skip_freecad:
        print("[OK] FreeCADCmd smoke test")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
