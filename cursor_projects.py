#!/usr/bin/env python3

"""Read Cursor's recent projects for the Omarchy Cursor shell plugin."""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlsplit


RECENT_PROJECTS_KEY = "history.recentlyOpenedPathsList"


class ProjectReadError(RuntimeError):
    """A user-facing failure while reading Cursor's project history."""


def default_database_path() -> Path:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return config_home / "Cursor/User/globalStorage/state.vscdb"


def compact_path(path: Path, home: Path) -> str:
    try:
        relative = path.relative_to(home)
    except ValueError:
        return str(path)
    return "~" if not relative.parts else f"~/{relative}"


def remote_metadata(uri: str) -> tuple[str, str]:
    parsed = urlsplit(uri)
    authority = unquote(parsed.netloc)
    remote_path = unquote(parsed.path) or "/"

    if authority.startswith("ssh-remote+"):
        encoded_host = authority.split("+", 1)[1]
        hostname = "remote"
        try:
            host_data = json.loads(bytes.fromhex(encoded_host).decode("utf-8"))
            if isinstance(host_data, dict):
                hostname = str(host_data.get("hostName") or hostname)
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
            if encoded_host:
                hostname = encoded_host
        return "SSH", f"{hostname} · {remote_path}"

    if authority.startswith("dev-container+"):
        return "Container", remote_path

    readable_authority = authority.split("+", 1)[0].replace("-", " ").title()
    return readable_authority or "Remote", remote_path


def project_from_entry(entry: Any, home: Path) -> dict[str, Any] | None:
    if not isinstance(entry, dict):
        return None

    uri = entry.get("folderUri")
    is_workspace = False
    if not uri:
        workspace = entry.get("workspace")
        if isinstance(workspace, dict):
            uri = workspace.get("configPath")
            is_workspace = bool(uri)

    if not isinstance(uri, str) or not uri:
        return None

    label = entry.get("label")
    label = str(label).strip() if label else ""

    if uri.startswith("file://"):
        parsed = urlsplit(uri)
        path = Path(unquote(parsed.path))
        if is_workspace:
            if not path.is_file():
                return None
            project_type = "Workspace"
        else:
            if not path.is_dir():
                return None
            project_type = "Local"

        name = label or path.name or str(path)
        return {
            "name": name,
            "detail": compact_path(path, home),
            "target": str(path),
            "remote": False,
            "projectType": project_type,
        }

    if uri.startswith("vscode-remote://"):
        project_type, detail = remote_metadata(uri)
        remote_path = unquote(urlsplit(uri).path)
        name = label or Path(remote_path).name or remote_path or "Remote project"
        return {
            "name": name,
            "detail": detail,
            "target": uri,
            "remote": True,
            "projectType": project_type,
        }

    return None


def projects_from_payload(payload: Any, home: Path | None = None) -> list[dict[str, Any]]:
    if not isinstance(payload, dict):
        raise ProjectReadError("Cursor's recent-project data is not a JSON object")

    entries = payload.get("entries", [])
    if not isinstance(entries, list):
        raise ProjectReadError("Cursor's recent-project list has an unexpected format")

    resolved_home = home or Path.home()
    projects: list[dict[str, Any]] = []
    seen_targets: set[str] = set()
    for entry in entries:
        project = project_from_entry(entry, resolved_home)
        if not project or project["target"] in seen_targets:
            continue
        seen_targets.add(project["target"])
        projects.append(project)
    return projects


def read_recent_projects(database_path: Path | None = None) -> list[dict[str, Any]]:
    path = database_path or default_database_path()
    if not path.is_file():
        raise ProjectReadError(f"Cursor project history was not found at {path}")

    database_uri = f"{path.resolve().as_uri()}?mode=ro"
    try:
        with sqlite3.connect(database_uri, uri=True, timeout=2) as connection:
            row = connection.execute(
                "SELECT value FROM ItemTable WHERE key = ?", (RECENT_PROJECTS_KEY,)
            ).fetchone()
    except sqlite3.Error as error:
        raise ProjectReadError(f"Cursor project history could not be read: {error}") from error

    if not row:
        return []

    try:
        raw_payload = row[0]
        if isinstance(raw_payload, bytes):
            raw_payload = raw_payload.decode("utf-8")
        payload = json.loads(raw_payload)
    except (TypeError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProjectReadError("Cursor's recent-project data is not valid JSON") from error
    return projects_from_payload(payload)


def list_command() -> int:
    try:
        result = {"projects": read_recent_projects(), "error": ""}
    except ProjectReadError as error:
        result = {"projects": [], "error": str(error)}
    json.dump(result, sys.stdout, ensure_ascii=False, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


def main(argv: list[str]) -> int:
    if argv in ([], ["list"]):
        return list_command()
    print("usage: cursor_projects.py list", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
