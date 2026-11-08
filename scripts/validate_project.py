#!/usr/bin/env python3
"""Validate data files against the JSON Schema of the engine version they declare.

A project file is validated with the schema of its own `engine_version`:
  - the working tree schema (engine/schema/) when it matches engine/VERSION;
  - otherwise the schema stored in the git tag engine/v<engine_version>.
With --schema, every file is validated against that schema instead (CI uses it with the
schema of the engine checkout, and for projects/_platform/platform.yaml).

Usage: validate_project.py [--schema SCHEMA.json] FILE [FILE...]
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import yaml
from jsonschema import Draft7Validator

REPO = Path(__file__).resolve().parent.parent
SCHEMA_PATH = "engine/schema/project.schema.json"
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def current_version():
    return (REPO / "engine" / "VERSION").read_text(encoding="utf-8").strip()


def published_versions():
    out = subprocess.run(
        ["git", "-C", str(REPO), "tag", "--list", "engine/v*", "--sort=-v:refname"],
        capture_output=True, text=True, check=False,
    ).stdout
    return [line.removeprefix("engine/v") for line in out.split()]


def tag_schema(version):
    """Schema of a published engine version, or None when the tag does not exist."""
    result = subprocess.run(
        ["git", "-C", str(REPO), "show", f"refs/tags/engine/v{version}:{SCHEMA_PATH}"],
        capture_output=True, text=True, check=False,
    )
    return json.loads(result.stdout) if result.returncode == 0 else None


def schema_for(data, working_schema):
    """Return (schema, problem) for a project document."""
    version = data.get("engine_version") if isinstance(data, dict) else None
    if not isinstance(version, str) or not SEMVER.match(version) or version == current_version():
        # Missing or malformed versions are reported by the current schema itself.
        return working_schema, None
    schema = tag_schema(version)
    if schema is None:
        known = ", ".join(published_versions()[:5]) or "none yet"
        return None, (
            f"engine_version '{version}' is not a published engine version "
            f"(latest: {known}; unreleased on main: {current_version()})."
        )
    return schema, None


def location(error):
    parts = ""
    for part in error.absolute_path:
        parts += f"[{part}]" if isinstance(part, int) else (f".{part}" if parts else str(part))
    return parts or "(file)"


def message(error):
    """Readable message: a regex means nothing to the person writing the YAML."""
    if error.validator == "pattern" and error.schema.get("title"):
        examples = error.schema.get("examples") or []
        hint = f" (example: {examples[0]})" if examples else ""
        return f"{error.instance!r} is not a valid {error.schema['title']}{hint}"
    return error.message


def validate(data, schema):
    validator = Draft7Validator(schema, format_checker=Draft7Validator.FORMAT_CHECKER)
    return sorted(f"{location(e)}: {message(e)}" for e in validator.iter_errors(data))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--schema", help="validate every file against this schema")
    parser.add_argument("files", nargs="+")
    args = parser.parse_args(argv)

    fixed = json.loads(Path(args.schema).read_text(encoding="utf-8")) if args.schema else None
    working = json.loads((REPO / SCHEMA_PATH).read_text(encoding="utf-8"))

    failed = False
    for path in args.files:
        try:
            with open(path, encoding="utf-8") as handle:
                data = yaml.safe_load(handle)
        except (OSError, yaml.YAMLError) as exc:
            print(f"{path}: cannot be read as YAML: {exc}", file=sys.stderr)
            failed = True
            continue

        schema, problem = (fixed, None) if fixed else schema_for(data, working)
        if problem:
            print(f"{path}: {problem}", file=sys.stderr)
            failed = True
            continue
        errors = validate(data, schema)
        for error in errors:
            print(f"{path}: {error}", file=sys.stderr)
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
