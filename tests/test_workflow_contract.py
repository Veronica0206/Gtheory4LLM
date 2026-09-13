"""Guard CI coverage and immutable actions without running hosted jobs or fits."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
EXPECTED = {"full-validation.yml", "compatibility.yml", "cran-readiness.yml"}
MAJORS = {
    "actions/checkout": "v4",
    "actions/setup-python": "v5",
    "actions/cache": "v4",
    "actions/upload-artifact": "v4",
    "actions/download-artifact": "v4",
    "r-lib/actions/setup-r": "v2",
    "r-lib/actions/setup-tinytex": "v2",
    "r-lib/actions/setup-pandoc": "v2",
    "r-lib/actions/setup-r-dependencies": "v2",
}


def block(text, key):
    """Read one unquoted top-level block in our deliberately simple YAML."""
    match = re.search(rf"(?ms)^{re.escape(key)}:\n(.*?)(?=^\S|\Z)", text)
    if match is None:
        raise AssertionError(f"Missing top-level {key} block")
    return [line.rstrip() for line in match.group(1).splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def assert_all_change_triggers(text):
    lines = block(text, "on")
    # No duplicated package-content inventory: any changed filename is covered.
    # Only the candidate workflow's existing main-branch restriction is allowed.
    required = {"  push:", "  pull_request:", "  workflow_dispatch:"}
    if not required.issubset(lines):
        raise AssertionError("Push, ordinary PR, and manual triggers are required")
    if any(line not in required | {"    branches: [main]"} for line in lines):
        raise AssertionError("Unexpected event or filter could leave a trigger hole")
    if len(lines) != len(set(lines)):
        raise AssertionError("Duplicate workflow trigger configuration")


def assert_pinned_actions(text):
    uses = re.findall(r"(?m)^\s*(?:- )?uses:\s*(.*?)\s*$", text)
    if not uses:
        raise AssertionError("Workflow contains no checked actions")
    for value in uses:
        match = re.fullmatch(r"([^@\s]+)@([0-9a-f]{40})\s+# (v\d+)", value)
        if match is None or MAJORS.get(match[1]) != match[3]:
            raise AssertionError(f"Action needs a reviewed full SHA and major comment: {value}")


def assert_source_checkout_has_history(text):
    # Every first job verifies source/artifact ancestry or audits public history.
    # R-devel's later downloaded-archive job needs only its own source commit.
    checkout = re.search(r"(?m)^( +)- uses: actions/checkout@[^\n]+\n", text)
    if checkout is None:
        raise AssertionError("Missing source checkout")
    tail = text[checkout.end():]
    next_step = re.search(rf"(?m)^{checkout[1]}- ", tail)
    settings = tail[:next_step.start()] if next_step else tail
    if not re.search(r"(?m)^\s+fetch-depth:\s+0\s*$", settings):
        raise AssertionError("Source release verification requires full checkout history")


class WorkflowContractTests(unittest.TestCase):
    def test_current_workflows_cover_all_changed_files_and_pin_actions(self):
        self.assertEqual({p.name for p in WORKFLOWS.glob("*.yml")}, EXPECTED)
        for name in sorted(EXPECTED):
            with self.subTest(workflow=name):
                text = (WORKFLOWS / name).read_text(encoding="utf-8")
                assert_all_change_triggers(text)
                assert_pinned_actions(text)
                assert_source_checkout_has_history(text)
                self.assertEqual(block(text, "permissions"), ["  contents: read"])
                self.assertEqual(block(text, "concurrency"), [
                    "  group: ${{ github.workflow }}-${{ github.ref }}",
                    "  cancel-in-progress: true",
                ])

    def test_path_filters_or_narrower_events_are_rejected(self):
        original = (WORKFLOWS / "cran-readiness.yml").read_text(encoding="utf-8")
        mutations = [
            original.replace("  pull_request:", "  pull_request:\n    paths: ['R/**']"),
            original.replace("  push:", "  push:\n    paths-ignore: ['vignettes/**']"),
            original.replace("branches: [main]", "branches: [release]"),
            original.replace("  pull_request:", "  pull_request_target:"),
            original.replace("  workflow_dispatch:\n", ""),
        ]
        for text in mutations:
            with self.assertRaises(AssertionError):
                assert_all_change_triggers(text)

    def test_movable_refs_and_major_upgrades_are_rejected(self):
        sha = "a" * 40
        for value in ["actions/checkout@v4", "actions/checkout@abcdef0 # v4",
                      f"actions/checkout@{sha} # v5", f"actions/checkout@{sha}"]:
            with self.subTest(value=value), self.assertRaises(AssertionError):
                assert_pinned_actions(f"      - uses: {value}\n")

    def test_shallow_source_checkouts_are_rejected(self):
        for name in sorted(EXPECTED):
            original = (WORKFLOWS / name).read_text(encoding="utf-8")
            for changed in (original.replace("fetch-depth: 0", "fetch-depth: 1", 1),
                            original.replace("          fetch-depth: 0\n", "", 1)):
                with self.subTest(workflow=name), self.assertRaisesRegex(AssertionError, "full checkout history"):
                    assert_source_checkout_has_history(changed)


if __name__ == "__main__":
    unittest.main()
