#!/usr/bin/env python3
"""Checks that need every project at once and therefore cannot live in Terraform.

  - each subscription belongs to a single project file (one project x environment);
  - no two projects use overlapping address spaces;
  - no project overlaps a hub address space from the platform file.

Files that cannot be parsed are skipped: the schema check reports them.

Usage: check_cross_project.py [--projects-dir projects] [--platform FILE] [--report FILE.md]
"""

import argparse
import ipaddress
import itertools
import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent


def project_pattern():
    catalog = yaml.safe_load((REPO / "engine" / "catalog" / "catalog.yaml").read_text(encoding="utf-8"))
    envs = "|".join(map(re.escape, catalog["environments"]))
    return re.compile(rf"^[a-z][a-z0-9]{{1,5}}/[a-z][a-z0-9]{{1,13}}/({envs})\.yaml$")


def load_projects(projects_dir):
    pattern = project_pattern()
    projects = {}
    for path in sorted(Path(projects_dir).glob("*/*/*.yaml")):
        relative = path.relative_to(projects_dir).as_posix()
        if not pattern.match(relative):
            continue
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except yaml.YAMLError:
            continue
        if isinstance(data, dict):
            projects[f"projects/{relative}"] = data
    return projects


def networks(values):
    found = []
    for value in values or []:
        try:
            found.append(ipaddress.ip_network(value, strict=False))
        except (TypeError, ValueError):
            continue
    return found


def find_problems(projects, platform):
    problems = []

    by_subscription = {}
    for name, data in projects.items():
        subscription = str(data.get("subscription_id", "")).lower()
        if subscription:
            by_subscription.setdefault(subscription, []).append(name)
    for subscription, names in sorted(by_subscription.items()):
        if len(names) > 1:
            problems.append(
                f"subscription {subscription} is used by {', '.join(names)}. "
                "Each project and environment needs its own subscription: ask the platform team for one."
            )

    spaces = {
        name: networks((data.get("network") or {}).get("address_space"))
        for name, data in projects.items()
        if isinstance(data.get("network"), dict)
    }
    for (a, nets_a), (b, nets_b) in itertools.combinations(sorted(spaces.items()), 2):
        for net_a, net_b in itertools.product(nets_a, nets_b):
            if net_a.overlaps(net_b):
                problems.append(
                    f"{a} ({net_a}) overlaps {b} ({net_b}). "
                    "Ask the platform team for a free address range."
                )

    for hub in (platform or {}).get("hubs") or []:
        hub_name = f"hub {hub.get('environment')}/{hub.get('location')}"
        for net_hub in networks(hub.get("address_space")):
            for name, nets in sorted(spaces.items()):
                for net in nets:
                    if net.overlaps(net_hub):
                        problems.append(
                            f"{name} ({net}) overlaps the {hub_name} ({net_hub}). "
                            "Ask the platform team for a free address range."
                        )
    return problems


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--projects-dir", default=str(REPO / "projects"))
    parser.add_argument("--platform", default=None, help="default: <projects-dir>/_platform/platform.yaml")
    parser.add_argument("--report", help="append the problems as Markdown to this file")
    args = parser.parse_args(argv)

    platform_path = Path(args.platform or Path(args.projects_dir) / "_platform" / "platform.yaml")
    platform = yaml.safe_load(platform_path.read_text(encoding="utf-8")) if platform_path.exists() else {}

    projects = load_projects(args.projects_dir)
    problems = find_problems(projects, platform)
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems and args.report:
        with open(args.report, "a", encoding="utf-8") as report:
            report.write("#### Conflicts with other projects\n\n")
            report.writelines(f"- {problem}\n" for problem in problems)
            report.write("\n")
    if not problems:
        print(f"{len(projects)} project files checked: no shared subscriptions or overlapping address spaces.")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
