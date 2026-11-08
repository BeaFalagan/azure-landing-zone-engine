#!/usr/bin/env python3
"""Check that every closed list in the JSON Schemas matches engine/catalog/catalog.yaml.

The catalog is the source of truth; the schemas repeat its keys as enums so that
editors and Backstage can offer drop-downs. This check keeps both in sync.
"""

import json
import pathlib
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent
ENGINE = ROOT / "engine"


def load_json(name):
    return json.loads((ENGINE / "schema" / name).read_text(encoding="utf-8"))


def main():
    catalog = yaml.safe_load((ENGINE / "catalog" / "catalog.yaml").read_text(encoding="utf-8"))
    project = load_json("project.schema.json")
    platform = load_json("platform.schema.json")
    defs = project["definitions"]
    hub = platform["definitions"]["hub"]["properties"]

    pairs = {
        "project.location": (project["properties"]["location"]["enum"], catalog["regions"].keys()),
        "project.environment": (project["properties"]["environment"]["enum"], catalog["environments"]),
        "project.access.roles": (defs["access_entry"]["properties"]["roles"]["items"]["enum"], catalog["roles"].keys()),
        "project.subnet.delegation": (defs["subnet"]["properties"]["delegation"]["enum"], catalog["delegations"].keys()),
        "project.subnet.service_endpoints": (
            defs["subnet"]["properties"]["service_endpoints"]["items"]["enum"],
            catalog["service_endpoints"],
        ),
        "project.address aliases": (defs["address"]["anyOf"][0]["enum"], catalog["address_aliases"].keys()),
        "platform.hub.location": (hub["location"]["enum"], catalog["regions"].keys()),
        "platform.hub.environment": (hub["environment"]["enum"], catalog["environments"]),
    }

    failed = False
    for name, (schema_values, catalog_values) in pairs.items():
        missing = sorted(set(catalog_values) - set(schema_values))
        extra = sorted(set(schema_values) - set(catalog_values))
        if missing or extra:
            failed = True
            print(f"{name}: missing in schema {missing}, not in catalog {extra}", file=sys.stderr)

    for field in ("location", "environment"):
        prop = project["properties"][field]
        if "enumNames" in prop and len(prop["enumNames"]) != len(prop["enum"]):
            failed = True
            print(f"project.{field}: enumNames and enum have different lengths", file=sys.stderr)

    if not failed:
        print(f"schemas and catalog are in sync ({len(pairs)} lists)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
