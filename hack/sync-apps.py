#!/usr/bin/env python3
"""Register new app folders in the app-of-apps group files.

For every group listed in apps-root-config/bootstrap/values.yaml, scan its `subFolder`
(e.g. cluster-media-apps/) and add each app folder that the group file
(apps-root-config/applications/<group>.yaml) does not know yet as `<name>: {}`.

A folder counts as known when it is:
  - an active key under `applications:`
  - the target of an application's `path:` override
  - a commented-out entry under `applications:` (`  # name: ...` or `#   path: <dir>`),
    which is how apps are parked without deploying them

A folder counts as an app when it holds Chart.yaml, kustomization.yaml or any top-level
.yaml/.yml/.json manifest. Empty folders and dot-folders are skipped.

Only new lines are inserted; existing content, comments and blank lines stay untouched.
Entries whose folder no longer exists are reported but never removed.

Usage:
  hack/sync-apps.py                 # add missing apps to all groups
  hack/sync-apps.py --check         # list missing apps, exit 1 if any (CI / pre-commit)
  hack/sync-apps.py cluster-test    # limit to one or more groups

Requires mikefarah yq v4 on PATH.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT_CONFIG = REPO / "apps-root-config"
BOOTSTRAP_VALUES = ROOT_CONFIG / "bootstrap" / "values.yaml"
GROUP_DIR = ROOT_CONFIG / "applications"

APP_MARKERS = ("Chart.yaml", "kustomization.yaml", "kustomization.yml")
MANIFEST_SUFFIXES = (".yaml", ".yml", ".json")
TOP_LEVEL_KEY = re.compile(r"^[^\s#]")
COMMENTED_KEY = re.compile(r"^(\s*)# ?([a-z0-9][a-z0-9.-]*):")
COMMENTED_PATH = re.compile(r"^\s*#\s*path:\s*(\S+)")


def yq_json(path: Path) -> dict:
    out = subprocess.run(
        ["yq", "-o=json", ".", str(path)], check=True, capture_output=True, text=True
    ).stdout
    return json.loads(out) or {}


def is_app_folder(folder: Path) -> bool:
    if any((folder / marker).is_file() for marker in APP_MARKERS):
        return True
    return any(f.is_file() and f.suffix in MANIFEST_SUFFIXES for f in folder.iterdir())


def app_folders(sub_folder: Path) -> list[str]:
    return sorted(
        d.name
        for d in sub_folder.iterdir()
        if d.is_dir() and not d.name.startswith(".") and is_app_folder(d)
    )


def applications_block(lines: list[str]) -> tuple[int, int]:
    """Return (index of the `applications:` line, index after the block's last line)."""
    start = next(
        (i for i, line in enumerate(lines) if line.startswith("applications:")), None
    )
    if start is None:
        return -1, -1
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if TOP_LEVEL_KEY.match(lines[i]):
            end = i
            break
    return start, end


def entry_indent(lines: list[str], start: int, end: int) -> str:
    for line in lines[start + 1 : end]:
        stripped = line.lstrip(" ")
        if stripped.strip() and not stripped.startswith("#"):
            return line[: len(line) - len(stripped)]
    return "  "


def known_folders(group: dict, lines: list[str], sub_folder: str) -> set[str]:
    prefix = f"{sub_folder.rstrip('/')}/"
    apps = group.get("applications") or {}
    known = set(apps)
    for value in apps.values():
        path = (value or {}).get("path", "")
        if path.startswith(prefix):
            known.add(path[len(prefix) :].strip("/"))

    start, end = applications_block(lines)
    if start >= 0:
        indent = entry_indent(lines, start, end)
        for line in lines[start + 1 : end]:
            match = COMMENTED_KEY.match(line)
            if match and match.group(1) == indent:
                known.add(match.group(2))
            match = COMMENTED_PATH.match(line)
            if match and match.group(1).startswith(prefix):
                known.add(match.group(1)[len(prefix) :].strip("/"))
    return known


def insert_apps(path: Path, lines: list[str], names: list[str]) -> None:
    start, end = applications_block(lines)
    if start < 0:
        if lines and lines[-1].strip():
            lines.append("")
        lines.append("applications:")
        start, end = len(lines) - 1, len(lines)
    elif lines[start].split("#")[0].strip() != "applications:":
        lines[start] = "applications:"  # e.g. `applications: {}`

    indent = entry_indent(lines, start, end)
    # Insert after the last active (non-comment, non-blank) line so trailing parked
    # entries and comments stay below the live ones.
    insert_at = start + 1
    for i in range(start + 1, end):
        stripped = lines[i].strip()
        if stripped and not stripped.startswith("#"):
            insert_at = i + 1
    lines[insert_at:insert_at] = [f"{indent}{name}: {{}}" for name in names]
    path.write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("groups", nargs="*", help="group names (default: all)")
    parser.add_argument(
        "--check", action="store_true", help="report only, exit 1 if apps are missing"
    )
    args = parser.parse_args()

    bootstrap = yq_json(BOOTSTRAP_VALUES)
    groups = [entry["name"] for entry in bootstrap.get("bootstrap") or []]
    unknown = set(args.groups) - set(groups)
    if unknown:
        print(f"error: unknown group(s): {', '.join(sorted(unknown))}", file=sys.stderr)
        return 2
    if args.groups:
        groups = [g for g in groups if g in args.groups]

    missing_total = 0
    for name in groups:
        group_file = GROUP_DIR / f"{name}.yaml"
        if not group_file.is_file():
            print(f"warn: {name}: no group file {group_file.relative_to(REPO)}")
            continue
        group = yq_json(group_file)
        sub_folder = group.get("subFolder", name)
        folder = REPO / sub_folder
        if not folder.is_dir():
            print(f"warn: {name}: subFolder '{sub_folder}' does not exist")
            continue

        lines = group_file.read_text().splitlines()
        missing = sorted(
            set(app_folders(folder)) - known_folders(group, lines, sub_folder)
        )

        for app, value in (group.get("applications") or {}).items():
            value = value or {}
            app_path = value.get("path", f"{sub_folder}/{app}")
            if not value.get("disabled") and not (REPO / app_path).is_dir():
                print(f"warn: {name}: '{app}' points to missing folder {app_path}")

        if not missing:
            continue
        missing_total += len(missing)
        if args.check:
            print(f"{name}: not registered: {', '.join(missing)}")
        else:
            insert_apps(group_file, lines, missing)
            print(f"{name}: added {', '.join(missing)}")

    if args.check and missing_total:
        print(
            "\nRun hack/sync-apps.py to register them, or park a folder by adding a"
            " commented-out entry (`  # <name>: {}`) to its group file."
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
