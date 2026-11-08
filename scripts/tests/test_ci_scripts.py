"""Unit tests of the CI scripts. Run: python3 -m unittest discover -s scripts/tests -t scripts"""

import json
import unittest
from pathlib import Path

import check_cross_project
import validate_project
from ci import changed_projects, check_release

REPO = Path(__file__).resolve().parents[2]
EXAMPLE = REPO / "engine" / "examples" / "projects" / "demo" / "webapp" / "pro.yaml"


class ChangedProjects(unittest.TestCase):
    pattern = changed_projects.project_pattern()
    every = ["projects/a1/web/dev.yaml", "projects/a1/web/pro.yaml", "projects/b2/api/pre.yaml"]

    def classify(self, changes, mode="pr"):
        return changed_projects.classify(changes, mode, self.pattern, self.every)

    def test_added_and_modified_files_are_selected(self):
        files, errors, _ = self.classify([("A", "projects/a1/web/dev.yaml"), ("M", "projects/b2/api/pre.yaml")])
        self.assertEqual(files, ["projects/a1/web/dev.yaml", "projects/b2/api/pre.yaml"])
        self.assertEqual(errors, [])

    def test_platform_change_selects_every_project(self):
        files, errors, _ = self.classify([("M", changed_projects.PLATFORM)])
        self.assertEqual(files, self.every)
        self.assertEqual(errors, [])

    def test_deleted_file_fails_a_pull_request_with_instructions(self):
        files, errors, _ = self.classify([("D", "projects/a1/web/dev.yaml")])
        self.assertEqual(files, [])
        self.assertEqual(len(errors), 1)
        self.assertIn("never destroys", errors[0])
        self.assertIn("Restore the file", errors[0])

    def test_rename_is_a_delete_plus_an_add(self):
        _, errors, _ = self.classify([("D", "projects/a1/web/dev.yaml"), ("A", "projects/a1/webapp/dev.yaml")])
        self.assertEqual(len(errors), 1)

    def test_deleted_file_only_warns_on_main(self):
        files, errors, warnings = self.classify([("D", "projects/a1/web/dev.yaml")], mode="push")
        self.assertEqual((files, errors, len(warnings)), ([], [], 1))

    def test_files_outside_the_layout_are_rejected(self):
        for path in ["projects/a1/web/prod.yaml", "projects/A1/web/dev.yaml", "projects/a1/dev.yaml", "projects/a1/web/dev.yml"]:
            with self.subTest(path=path):
                _, errors, _ = self.classify([("A", path)])
                self.assertEqual(len(errors), 1)

    def test_markdown_is_ignored(self):
        self.assertEqual(self.classify([("A", "projects/a1/README.md")]), ([], [], []))

    def test_matrix_entry(self):
        entry = changed_projects.entry("projects/demo/webapp/pro.yaml", self.pattern)
        self.assertEqual(entry["key"], "demo/webapp/pro.tfstate")
        self.assertEqual(entry["id"], "demo-webapp-pro")
        self.assertEqual(entry["environment"], "pro")


class CrossProject(unittest.TestCase):
    platform = {"hubs": [{"environment": "dev", "location": "westeurope", "address_space": ["10.0.0.0/22"]}]}

    @staticmethod
    def project(subscription, *spaces):
        data = {"subscription_id": subscription}
        if spaces:
            data["network"] = {"address_space": list(spaces)}
        return data

    def test_clean_projects(self):
        projects = {
            "projects/a1/web/dev.yaml": self.project("1", "10.1.0.0/24"),
            "projects/a1/web/pro.yaml": self.project("2", "10.1.1.0/24"),
            "projects/a1/min/dev.yaml": self.project("3"),
        }
        self.assertEqual(check_cross_project.find_problems(projects, self.platform), [])

    def test_shared_subscription(self):
        projects = {"projects/a1/web/dev.yaml": self.project("1"), "projects/b2/api/dev.yaml": self.project("1")}
        problems = check_cross_project.find_problems(projects, self.platform)
        self.assertEqual(len(problems), 1)
        self.assertIn("projects/a1/web/dev.yaml, projects/b2/api/dev.yaml", problems[0])

    def test_overlap_between_projects(self):
        projects = {
            "projects/a1/web/dev.yaml": self.project("1", "10.1.0.0/16"),
            "projects/b2/api/dev.yaml": self.project("2", "10.1.4.0/24"),
        }
        problems = check_cross_project.find_problems(projects, self.platform)
        self.assertEqual(len(problems), 1)
        self.assertIn("10.1.0.0/16", problems[0])

    def test_overlap_with_a_hub(self):
        projects = {"projects/a1/web/dev.yaml": self.project("1", "10.0.2.0/24")}
        problems = check_cross_project.find_problems(projects, self.platform)
        self.assertEqual(len(problems), 1)
        self.assertIn("hub dev/westeurope", problems[0])

    def test_examples_are_consistent(self):
        projects = check_cross_project.load_projects(REPO / "engine" / "examples" / "projects")
        self.assertEqual(len(projects), 3)
        platform = check_cross_project.yaml.safe_load((REPO / "engine" / "examples" / "platform.yaml").read_text())
        self.assertEqual(check_cross_project.find_problems(projects, platform), [])


class Release(unittest.TestCase):
    changelog = "# Changelog\n\n## [Sin publicar]\n\n## [1.1.0] - 2026-12-01\n\n### Añadido\n- algo\n\n## [1.0.0] - 2026-11-10\n\n- inicial\n"

    def test_valid_release(self):
        self.assertEqual(check_release.problems("1.1.0", "1.0.0", self.changelog, ["1.0.0"]), [])

    def test_section_body(self):
        self.assertEqual(check_release.changelog_section(self.changelog, "1.1.0"), "### Añadido\n- algo")
        self.assertEqual(check_release.changelog_section(self.changelog, "1.0.0"), "- inicial")

    def test_missing_changelog_entry(self):
        problems = check_release.problems("1.2.0", "1.1.0", self.changelog, ["1.0.0", "1.1.0"])
        self.assertEqual(len(problems), 1)
        self.assertIn("## [1.2.0] - YYYY-MM-DD", problems[0])

    def test_version_must_be_new(self):
        problems = check_release.problems("1.0.0", "1.1.0", self.changelog, ["1.0.0", "1.1.0"])
        self.assertEqual(problems, ["engine/v1.0.0 is already published: choose the next version."])

    def test_version_must_grow(self):
        problems = check_release.problems("1.0.0", "1.1.0", self.changelog, [])
        self.assertEqual(problems, ["engine/VERSION goes from 1.1.0 to 1.0.0: a new version must be greater."])

    def test_semver_only(self):
        self.assertEqual(len(check_release.problems("1.1", None, self.changelog, [])), 1)
        self.assertGreater(check_release.parse("1.10.0"), check_release.parse("1.9.0"))


class ValidateProject(unittest.TestCase):
    working = json.loads((REPO / validate_project.SCHEMA_PATH).read_text())

    def load(self):
        return validate_project.yaml.safe_load(EXAMPLE.read_text())

    def test_current_version_uses_the_working_tree_schema(self):
        schema, problem = validate_project.schema_for(self.load(), self.working)
        self.assertIs(schema, self.working)
        self.assertIsNone(problem)
        self.assertEqual(validate_project.validate(self.load(), schema), [])

    def test_unpublished_version_is_reported(self):
        data = self.load() | {"engine_version": "0.0.1"}
        schema, problem = validate_project.schema_for(data, self.working)
        self.assertIsNone(schema)
        self.assertIn("'0.0.1' is not a published engine version", problem)

    def test_errors_name_the_field(self):
        data = self.load()
        data["network"]["subnets"][1]["prefix"] = "10.48.49.0/33"
        errors = validate_project.validate(data, self.working)
        self.assertTrue(errors)
        self.assertEqual(errors, ["network.subnets[1].prefix: '10.48.49.0/33' is not a valid CIDR (example: 10.48.48.0/24)"])


if __name__ == "__main__":
    unittest.main()
