#!/usr/bin/env python3
"""Engine release rules (docs/adr/0003).

  check   (pull requests) if engine/VERSION changes, the new version must be greater than the
          base one, must not be published yet and needs a "## [X.Y.Z] - YYYY-MM-DD" section in
          engine/CHANGELOG.md.
  release (push to main) same checks against the published tags; writes the CHANGELOG section
          to --notes and the version to $GITHUB_OUTPUT (`version`, `tag`).

Usage:
  check_release.py check --base REF
  check_release.py release --notes FILE
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SEMVER = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def parse(version):
    match = SEMVER.match(version or "")
    return tuple(int(part) for part in match.groups()) if match else None


def changelog_section(changelog, version):
    """Body of '## [version] - YYYY-MM-DD', or None when the heading is missing."""
    heading = re.compile(rf"^## \[{re.escape(version)}\] - \d{{4}}-\d{{2}}-\d{{2}}\s*$", re.MULTILINE)
    match = heading.search(changelog)
    if not match:
        return None
    following = re.compile(r"^## ", re.MULTILINE).search(changelog, match.end())
    return changelog[match.end():following.start() if following else len(changelog)].strip()


def problems(new, old, changelog, published):
    found = []
    if parse(new) is None:
        return [f"engine/VERSION must be X.Y.Z (SemVer), found '{new}'."]
    if new in published:
        found.append(f"engine/v{new} is already published: choose the next version.")
    elif old is not None and parse(old) is not None and parse(new) <= parse(old):
        found.append(f"engine/VERSION goes from {old} to {new}: a new version must be greater.")
    section = changelog_section(changelog, new)
    if section is None:
        found.append(f"engine/CHANGELOG.md needs a '## [{new}] - YYYY-MM-DD' section for this release.")
    elif not section:
        found.append(f"The engine/CHANGELOG.md section for {new} is empty.")
    return found


def git(*args):
    result = subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True, check=False)
    return result.stdout if result.returncode == 0 else None


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=["check", "release"])
    parser.add_argument("--base", help="check: base commit of the pull request")
    parser.add_argument("--notes", help="release: write the release notes here")
    args = parser.parse_args(argv)

    new = (REPO / "engine" / "VERSION").read_text(encoding="utf-8").strip()
    changelog = (REPO / "engine" / "CHANGELOG.md").read_text(encoding="utf-8")
    published = [t.removeprefix("engine/v") for t in (git("tag", "--list", "engine/v*") or "").split()]
    latest = max(published, key=lambda v: parse(v) or (-1,), default=None)

    if args.command == "check":
        old = git("show", f"{args.base}:engine/VERSION")
        old = old.strip() if old is not None else None
        if old == new:
            print(f"engine/VERSION unchanged ({new}): nothing to release.")
            return 0
        found = problems(new, old or latest, changelog, published)
    else:
        found = problems(new, latest, changelog, published)

    for problem in found:
        print(problem, file=sys.stderr)
    if found:
        return 1

    print(f"engine/v{new} is ready to be released.")
    if args.command == "release":
        Path(args.notes).write_text(changelog_section(changelog, new) + "\n", encoding="utf-8")
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
                out.write(f"version={new}\ntag=engine/v{new}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
