#!/usr/bin/env python3
"""Run the JSON Schema test cases in engine/schema/tests.

Layout: engine/schema/tests/<schema>/{valid,invalid}/*.yaml, validated against
engine/schema/<schema>.schema.json. Every invalid case starts with a comment
'# expect: <text>' that must appear in at least one validation error.
"""

import json
import pathlib
import sys

import jsonschema
import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "engine" / "schema"


def errors_for(validator, path):
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return [error.message for error in validator.iter_errors(data)]


def main():
    failures = 0
    cases = 0
    for suite in sorted((SCHEMAS / "tests").iterdir()):
        schema = json.loads((SCHEMAS / f"{suite.name}.schema.json").read_text(encoding="utf-8"))
        validator = jsonschema.Draft7Validator(schema, format_checker=jsonschema.Draft7Validator.FORMAT_CHECKER)

        for path in sorted((suite / "valid").glob("*.yaml")):
            cases += 1
            errors = errors_for(validator, path)
            if errors:
                failures += 1
                print(f"FAIL {path.relative_to(ROOT)}: expected valid, got {errors}")

        for path in sorted((suite / "invalid").glob("*.yaml")):
            cases += 1
            first = path.read_text(encoding="utf-8").splitlines()[0]
            if not first.startswith("# expect: "):
                failures += 1
                print(f"FAIL {path.relative_to(ROOT)}: missing '# expect: ...' header")
                continue
            expected = first.removeprefix("# expect: ")
            errors = errors_for(validator, path)
            if not any(expected in message for message in errors):
                failures += 1
                print(f"FAIL {path.relative_to(ROOT)}: expected an error containing {expected!r}, got {errors}")

    print(f"{cases - failures}/{cases} schema cases passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
