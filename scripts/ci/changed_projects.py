#!/usr/bin/env python3
"""Work out which project files a change affects and build the CI matrix.

Rules:
  - an added or modified projects/<bu>/<project>/<env>.yaml is planned (and applied on main);
  - a change to projects/_platform/platform.yaml plans every project;
  - a deleted (or renamed) project file never destroys anything: a pull request fails with
    instructions, and a push to main only warns;
  - any other file under projects/ is rejected, except Markdown.

Usage:
  changed_projects.py --mode pr|push --base REF [--head REF] [--report FILE.md]
  changed_projects.py --mode dispatch --files FILE [FILE...]

Writes `matrix` (JSON for strategy.matrix) and `count` to $GITHUB_OUTPUT when it is set.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[2]
PLATFORM = "projects/_platform/platform.yaml"
ZERO_SHA = "0" * 40

DELETED = """`{path}` was deleted. Deleting a project file never destroys its resources: they would \
stay in Azure without an owner, so the pipeline stops here.
- Mistake or rename? Restore the file at its original path. Renaming a business unit, project or \
environment is not supported, because the path is the state key and part of every resource name.
- Decommissioning the project? Restore the file and ask the platform team \
(docs/guia-alta-proyecto.md, section "Dar de baja un proyecto")."""

DELETED_ON_MAIN = """`{path}` was deleted on main. Nothing was destroyed: its resources still exist in Azure \
but are no longer managed. Restore the file or ask the platform team to decommission them."""


def project_pattern():
    catalog = yaml.safe_load((REPO / "engine" / "catalog" / "catalog.yaml").read_text(encoding="utf-8"))
    envs = "|".join(map(re.escape, catalog["environments"]))
    return re.compile(rf"^projects/([a-z][a-z0-9]{{1,5}})/([a-z][a-z0-9]{{1,13}})/({envs})\.yaml$")


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, check=True).stdout


def diff(base, head):
    """[(status, path)] between two commits, with renames split into delete + add."""
    if not base or base == ZERO_SHA:
        base = f"{head}^"
    out = git("diff", "--name-status", "--no-renames", base, head, "--", "projects/")
    return [tuple(line.split("\t", 1)) for line in out.splitlines() if line]


def all_projects(pattern):
    out = git("ls-files", "projects/")
    return sorted(path for path in out.splitlines() if pattern.match(path))


def engine_version(path):
    try:
        data = yaml.safe_load((REPO / path).read_text(encoding="utf-8"))
        return str(data.get("engine_version", "")) if isinstance(data, dict) else ""
    except (OSError, yaml.YAMLError):
        return ""


def entry(path, pattern):
    bu, project, env = pattern.match(path).groups()
    return {
        "file": path,
        "name": f"{bu}/{project}/{env}",
        "id": f"{bu}-{project}-{env}",
        "key": f"{bu}/{project}/{env}.tfstate",
        "environment": env,
        "engine_version": engine_version(path),
    }


def classify(changes, mode, pattern, every_project):
    """Return (files to run, errors, warnings)."""
    selected, errors, warnings = set(), [], []
    for status, path in changes:
        if path == PLATFORM:
            if status == "D":
                errors.append(f"`{PLATFORM}` cannot be deleted: every project reads it.")
            else:
                selected.update(every_project)
        elif pattern.match(path):
            if status == "D":
                if mode == "pr":
                    errors.append(DELETED.format(path=path))
                else:
                    warnings.append(DELETED_ON_MAIN.format(path=path))
            else:
                selected.add(path)
        elif path.endswith(".md"):
            continue
        elif status != "D":
            errors.append(
                f"`{path}` is not a valid project file. Project files live at "
                "projects/<business_unit>/<project>/<environment>.yaml, all lowercase, "
                "with an environment from the engine catalog."
            )
    return sorted(selected), errors, warnings


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mode", choices=["pr", "push", "dispatch"], required=True)
    parser.add_argument("--base")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--files", nargs="*", default=[])
    parser.add_argument("--report", help="append errors as Markdown to this file")
    args = parser.parse_args(argv)

    pattern = project_pattern()
    if args.mode == "dispatch":
        changes = [("M", path) for path in args.files]
        missing = [path for path in args.files if not (REPO / path).is_file()]
    else:
        changes = diff(args.base, args.head)
        missing = []

    files, errors, warnings = classify(changes, args.mode, pattern, all_projects(pattern))
    errors += [f"`{path}` does not exist on this branch." for path in missing]

    for warning in warnings:
        print(f"::warning::{warning}")
    for error in errors:
        print(error, file=sys.stderr)
    if errors and args.report:
        with open(args.report, "a", encoding="utf-8") as report:
            report.write("#### Changes the pipeline cannot accept\n\n")
            report.writelines("- " + error.replace("\n", "\n  ") + "\n" for error in errors)
            report.write("\n")
    if errors:
        return 1

    matrix = [entry(path, pattern) for path in files if path not in missing]
    print(f"{len(matrix)} project file(s) to run: {', '.join(e['file'] for e in matrix) or 'none'}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"matrix={json.dumps({'include': matrix})}\n")
            out.write(f"count={len(matrix)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
