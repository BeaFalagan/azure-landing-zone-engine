#!/usr/bin/env python3
"""Reject YAML features the engine does not support in data files.

Project and platform files must be plain YAML: a single document, no anchors (&),
aliases (*), merge keys (<<), explicit tags (!!str, !Ref...) or duplicate keys.
They hide values from reviewers and are not rendered by Backstage.

Usage: check_plain_yaml.py FILE [FILE...]
"""

import sys

import yaml


def problems(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    try:
        events = list(yaml.parse(text, Loader=yaml.SafeLoader))
    except yaml.YAMLError as exc:
        return [f"invalid YAML: {exc}"]

    found = []
    documents = 0
    for event in events:
        line = getattr(event, "start_mark", None)
        where = f"line {line.line + 1}" if line else "?"
        if isinstance(event, yaml.DocumentStartEvent):
            documents += 1
        elif isinstance(event, yaml.AliasEvent):
            found.append(f"{where}: alias '*{event.anchor}' is not allowed")
        elif isinstance(event, yaml.NodeEvent):
            if event.anchor:
                found.append(f"{where}: anchor '&{event.anchor}' is not allowed")
            if getattr(event, "tag", None) and not _implicit(event):
                found.append(f"{where}: explicit tag '{event.tag}' is not allowed")
            if isinstance(event, yaml.ScalarEvent) and event.value == "<<" and event.style is None:
                found.append(f"{where}: merge key '<<' is not allowed")
    if documents > 1:
        found.append("only one YAML document per file is allowed ('---' separators)")
    if not found:
        found.extend(_duplicate_keys(text))
    return found


def _implicit(event):
    # Plain scalars resolved by the YAML core schema carry no explicit tag.
    implicit = getattr(event, "implicit", True)
    return any(implicit) if isinstance(implicit, tuple) else bool(implicit)


def _duplicate_keys(text):
    found = []

    def walk(node):
        if isinstance(node, yaml.MappingNode):
            seen = {}
            for key, value in node.value:
                name = key.value
                if name in seen:
                    found.append(f"line {key.start_mark.line + 1}: duplicate key '{name}' (first at line {seen[name]})")
                else:
                    seen[name] = key.start_mark.line + 1
                walk(value)
        elif isinstance(node, yaml.SequenceNode):
            for item in node.value:
                walk(item)

    walk(yaml.compose(text, Loader=yaml.SafeLoader))
    return found


def main(paths):
    failed = False
    for path in paths:
        for problem in problems(path):
            failed = True
            print(f"{path}: {problem}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
