#!/usr/bin/env python3
"""Check this project's agent/skill files without starting an agent or writing files."""

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit


EXPECTED_ROLES = {
    "dicom_core": "dicom-core",
    "macos_app": "dicom-macos",
    "dicom_fixtures": "dicom-fixtures",
    "dicom_reviewer": "dicom-review",
}
EXPECTED_SKILLS = set(EXPECTED_ROLES.values()) | {
    "dicom-orchestrate",
    "dicom-ffi-contract",
}


def validate(root):
    errors = []
    try:
        import yaml
        try:
            import tomllib as toml_reader
        except ImportError:
            import tomli as toml_reader
    except ImportError as exc:
        return {"ok": False, "errors": [
            "검사에는 PyYAML과 Python 3.11+의 tomllib 또는 tomli가 필요합니다: "
            + exc.name
        ]}

    def error(path, message):
        try:
            label = str(path.relative_to(root))
        except ValueError:
            label = str(path)
        errors.append(label + ": " + message)

    def read_toml(path):
        try:
            return toml_reader.loads(path.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as exc:
            error(path, str(exc))
            return {}

    config = read_toml(root / ".codex/config.toml")
    agent_settings = config.get("agents", {})
    if agent_settings.get("enabled") is not True:
        error(root / ".codex/config.toml", "agents.enabled must be true")
    limit = agent_settings.get("max_concurrent_threads_per_session")
    if type(limit) is not int or not 1 <= limit <= 3:
        error(root / ".codex/config.toml", "concurrent subagent limit must be 1..3")

    role_files = list((root / ".codex/agents").glob("*.toml"))
    role_names = set()
    for path in role_files:
        role = read_toml(path)
        for key in ("name", "description", "developer_instructions"):
            if not isinstance(role.get(key), str) or not role[key].strip():
                error(path, "missing nonempty string " + key)
        name = role.get("name", "")
        if name in role_names:
            error(path, "duplicate role name " + name)
        role_names.add(name)
        if path.stem != name:
            error(path, "filename and role name differ")
        skill = EXPECTED_ROLES.get(name)
        if skill:
            target = ".agents/skills/" + skill + "/SKILL.md"
            if target not in role.get("developer_instructions", ""):
                error(path, "primary skill is not linked in role instructions")
            if not (root / target).is_file():
                error(path, "primary skill file does not exist")
        if name == "dicom_reviewer" and role.get("sandbox_mode") != "read-only":
            error(path, "review role must request read-only sandbox")
    if role_names != set(EXPECTED_ROLES):
        error(root / ".codex/agents", "role set differs from project role map")

    skill_files = list((root / ".agents/skills").glob("*/SKILL.md"))
    skill_names = set()
    for path in skill_files:
        try:
            content = path.read_text(encoding="utf-8")
            match = re.match(r"\A---\n(.*?)\n---(?:\n|\Z)", content, re.S)
            if not match:
                error(path, "missing YAML frontmatter")
                continue
            metadata = yaml.safe_load(match.group(1))
            if not isinstance(metadata, dict):
                error(path, "frontmatter must be a mapping")
                continue
            name = metadata.get("name", "")
            if not isinstance(name, str) or not re.fullmatch(
                    r"[a-z0-9]+(?:-[a-z0-9]+)*", name) or len(name) > 64:
                error(path, "invalid skill name")
                continue
            if name != path.parent.name or name in skill_names:
                error(path, "folder mismatch or duplicate skill name")
            skill_names.add(name)
            description = metadata.get("description")
            if not isinstance(description, str) or not description.strip():
                error(path, "missing skill description")
            if "[TODO:" in content:
                error(path, "unfinished initializer placeholder")

            ui_path = path.parent / "agents/openai.yaml"
            ui = yaml.safe_load(ui_path.read_text(encoding="utf-8"))
            if not isinstance(ui, dict):
                error(ui_path, "UI metadata must be a mapping")
                continue
            interface = ui.get("interface", {})
            for key in ("display_name", "short_description", "default_prompt"):
                if not isinstance(interface.get(key), str) or not interface[key].strip():
                    error(ui_path, "missing nonempty interface " + key)
            short = interface.get("short_description", "")
            if not 25 <= len(short) <= 64:
                error(ui_path, "short_description must be 25..64 characters")
            if "$" + name not in interface.get("default_prompt", ""):
                error(ui_path, "default_prompt must invoke its own skill")
            if ui.get("policy", {}).get("allow_implicit_invocation", True) is not True:
                error(ui_path, "project skills must allow automatic selection")
        except (OSError, UnicodeError, yaml.YAMLError, TypeError) as exc:
            error(path, str(exc))
    if skill_names != EXPECTED_SKILLS:
        error(root / ".agents/skills", "skill set differs from project skill map")

    guidance = root / "AGENTS.md"
    if not guidance.is_file():
        error(guidance, "project guidance does not exist")
    elif guidance.stat().st_size > 32768:
        error(guidance, "root guidance exceeds Codex default 32 KiB guidance budget")

    markdown_files = [root / "README.md", guidance]
    for directory in (root / "docs", root / ".agents"):
        markdown_files.extend(directory.rglob("*.md"))
    link_count = 0
    for path in markdown_files:
        if not path.is_file():
            continue
        content = path.read_text(encoding="utf-8")
        for target in re.findall(r"!?\[[^\]\n]*\]\(([^)\n]+)\)", content):
            target = target.strip().strip("<>")
            parsed = urlsplit(target)
            if parsed.scheme or not parsed.path:
                continue
            resolved = (path.parent / unquote(parsed.path)).resolve()
            link_count += 1
            if not resolved.exists():
                error(path, "broken local link " + target)

    return {
        "ok": not errors,
        "agents": len(role_files),
        "skills": len(skill_files),
        "local_links": link_count,
        "errors": errors,
        "scope": "structure and local links; no runtime agent loading or app tests",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[4])
    parser.add_argument("--json", action="store_true", help="print a machine-readable result")
    args = parser.parse_args()
    result = validate(args.root.resolve())
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif result["ok"]:
        print("PASS: {agents} roles, {skills} skills, {local_links} local links".format(**result))
        print("Scope: " + result["scope"])
    else:
        for message in result["errors"]:
            print("FAIL: " + message)
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
