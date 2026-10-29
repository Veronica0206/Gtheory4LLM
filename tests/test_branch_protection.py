"""The declared protection policy must describe checks that actually exist.

No network access and no repository settings are involved: this exercises the
policy file, the workflow-context parser, and the comparison logic against
constructed API responses.
"""
from __future__ import annotations

import importlib.util
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("branch_protection",
                                              ROOT / "scripts/check_branch_protection.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)

POLICY = json.loads((ROOT / "docs/branch-protection.json").read_text(encoding="utf-8"))


def compliant() -> dict:
    return {
        "required_status_checks": {"strict": True,
                                   "contexts": list(POLICY["required_status_checks"]["contexts"])},
        "required_pull_request_reviews": {
            "required_approving_review_count":
                POLICY["required_pull_request_reviews"]["required_approving_review_count"],
            "dismiss_stale_reviews": True},
        "enforce_admins": {"enabled": True},
        "required_linear_history": {"enabled": True},
        "required_conversation_resolution": {"enabled": True},
        "allow_force_pushes": {"enabled": False},
        "allow_deletions": {"enabled": False},
    }


class PolicyContextTests(unittest.TestCase):
    def test_every_required_context_is_produced_by_a_workflow_job(self):
        produced = CHECK.workflow_job_names(ROOT)
        for context in POLICY["required_status_checks"]["contexts"]:
            with self.subTest(context=context):
                self.assertIn(context, produced,
                              "a required context no job produces would block every merge")

    def test_every_workflow_job_is_a_required_context(self):
        # A job that runs but is not required stops being a gate silently.
        required = set(POLICY["required_status_checks"]["contexts"])
        for context in sorted(CHECK.workflow_job_names(ROOT)):
            with self.subTest(context=context):
                self.assertIn(context, required)

    def test_both_exact_archive_platforms_are_independently_required(self):
        # These literal expectations must not come from the inventory itself:
        # previously an unsupported inline matrix vanished from both sides.
        exact = {"Exact archive / macos-latest / R release",
                 "Exact archive / windows-latest / R release"}
        self.assertTrue(exact <= CHECK.workflow_job_names(ROOT))
        self.assertTrue(exact <= set(POLICY["required_status_checks"]["contexts"]))

    def test_the_prose_counts_the_contexts_it_lists(self):
        # The policy document is the authoritative admin instruction, so a count
        # in it that disagrees with the payload is a defect in the instruction.
        words = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five",
                 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}
        expected = words[len(POLICY["required_status_checks"]["contexts"])]
        document = (ROOT / "docs/REPOSITORY_POLICY.md").read_text(encoding="utf-8")
        self.assertIn(f"The {expected} contexts below", document,
                      "the prose must count the contexts the payload actually lists")
        for count, word in words.items():
            if word != expected:
                self.assertNotIn(f"The {word} contexts below", document)

    def test_matrix_job_names_are_expanded(self):
        produced = CHECK.workflow_job_names(ROOT)
        self.assertIn("ubuntu-22.04 / R 4.5.0", produced)
        self.assertNotIn("${{ matrix.os }} / R ${{ matrix.r }}", produced)


class InventoryFixtureTests(unittest.TestCase):
    def inventory(self, body: str) -> set[str]:
        # A separate root makes the expected inventory independent of current
        # workflow text, and catches accidentally reading the module's ROOT.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workflows = root / ".github/workflows"
            workflows.mkdir(parents=True)
            (workflows / "fixture.yaml").write_text("name: Fixture\njobs:\n" + body,
                                                    encoding="utf-8")
            return CHECK.workflow_job_names(root)

    def test_inline_axes_form_a_cartesian_product(self):
        self.assertEqual(self.inventory("""  check:
    name: Exact / ${{ matrix.os }} / ${{ matrix.r }}
    strategy:
      matrix:
        os: [macos-latest, windows-latest]
        r: ['4.5.0', release]
    steps:
      - run: true
"""), {"Exact / macos-latest / 4.5.0", "Exact / macos-latest / release",
       "Exact / windows-latest / 4.5.0", "Exact / windows-latest / release"})

    def test_block_axes_and_quoted_template(self):
        self.assertEqual(self.inventory("""  check:
    name: 'Check / ${{ matrix.os }}'
    strategy:
      matrix:
        os:
          - macos-latest
          - 'windows-latest'
"""), {"Check / macos-latest", "Check / windows-latest"})

    def test_include_only_rows_preserve_paired_values(self):
        self.assertEqual(self.inventory("""  check:
    name: ${{ matrix.os }} / R ${{ matrix.r }}
    strategy:
      matrix:
        include:
          - os: macos-latest
            r: release
          - os: ubuntu-22.04
            r: '4.5.0'
"""), {"macos-latest / R release", "ubuntu-22.04 / R 4.5.0"})

    def test_unsupported_or_incomplete_matrices_fail_explicitly(self):
        for matrix in (
            "        os: [macos-latest]\n        exclude:\n          - os: macos-latest\n",
            "        os: ${{ fromJSON(inputs.os) }}\n",
            "        os: [macos-latest]\n        include:\n          - os: windows-latest\n",
            "        include:\n        os: [macos-latest]\n",
            "        include:\n          - r: release\n",
            "        os: []\n",
            "        os: [null]\n",
            "        os: [4.50]\n",
            "        os: [macos-latest, macos-latest]\n",
            "        os:\n          - label: macos-latest\n",
            "        os: [macos-latest]\n          - windows-latest\n",
            "        os: [macos-latest]\n        os: [windows-latest]\n",
            "        os: [macos-latest]\n        r: [release, devel]\n",
        ):
            with self.subTest(matrix=matrix):
                with self.assertRaises(CHECK.WorkflowInventoryError):
                    self.inventory("  check:\n    name: ${{ matrix.os }}\n"
                                   "    strategy:\n      matrix:\n" + matrix)

    def test_dynamic_matrix_and_strategy_fail_explicitly(self):
        for strategy in (
            "    strategy:\n      matrix: ${{ fromJSON(needs.setup.outputs.matrix) }}\n",
            "    strategy: {matrix: {os: [linux]}}\n",
        ):
            with self.subTest(strategy=strategy):
                with self.assertRaises(CHECK.WorkflowInventoryError):
                    self.inventory("  check:\n    name: ${{ matrix.os }}\n" + strategy)

    def test_unsupported_mapping_cannot_hide_a_matrix_behind_a_static_name(self):
        for body in (
            "  check:\n    name: Static\n    strategy:\n        matrix:\n          os: [linux]\n",
            "  check:\n    name: Static\n    'strategy':\n      matrix:\n        os: [linux]\n",
            "  check:\n    name: Static\n    strategy:\n      'matrix':\n        os: [linux]\n",
            "  check:\n      name: Static\n      strategy:\n        matrix:\n          os: [linux]\n",
        ):
            with self.subTest(body=body):
                with self.assertRaises(CHECK.WorkflowInventoryError):
                    self.inventory(body)

    def test_matrix_requires_explicit_name(self):
        with self.assertRaisesRegex(CHECK.WorkflowInventoryError, "explicit name"):
            self.inventory("  check:\n    strategy:\n      matrix:\n        os: [linux]\n")


class ComparisonTests(unittest.TestCase):
    def test_a_compliant_repository_reports_no_problems(self):
        self.assertEqual(CHECK.compare(POLICY, compliant()), [])

    def test_each_relaxation_is_reported(self):
        for mutate, expected in (
            (lambda live: live["required_status_checks"]["contexts"].remove("validate"),
             "required status checks missing"),
            (lambda live: live["required_status_checks"].update(strict=False),
             "not strict"),
            (lambda live: live["required_pull_request_reviews"].update(dismiss_stale_reviews=False),
             "stale reviews are not dismissed"),
            (lambda live: live["enforce_admins"].update(enabled=False),
             "administrators are not covered"),
            (lambda live: live["required_linear_history"].update(enabled=False),
             "linear history is not required"),
            (lambda live: live["required_conversation_resolution"].update(enabled=False),
             "conversation resolution is not required"),
            (lambda live: live["allow_force_pushes"].update(enabled=True),
             "force pushes are allowed"),
            (lambda live: live["allow_deletions"].update(enabled=True),
             "branch deletion is allowed"),
        ):
            with self.subTest(expected=expected):
                live = compliant()
                mutate(live)
                self.assertTrue(any(expected in problem for problem in CHECK.compare(POLICY, live)),
                                f"relaxation not reported: {expected}")

    def test_a_live_review_count_below_the_declared_one_is_reported(self):
        # The declared count is currently zero, so no live value can fall below
        # it and the table above cannot exercise this. The comparison still has
        # to work, because the count is the setting most likely to be raised
        # again once a second person can review.
        policy = json.loads(json.dumps(POLICY))
        policy["required_pull_request_reviews"]["required_approving_review_count"] = 1
        live = compliant()
        live["required_pull_request_reviews"]["required_approving_review_count"] = 0
        self.assertTrue(any("approving reviews below policy" in problem
                            for problem in CHECK.compare(policy, live)))
        live["required_pull_request_reviews"]["required_approving_review_count"] = 1
        self.assertEqual(CHECK.compare(policy, live), [])


class ReportingTests(unittest.TestCase):
    def test_unreachable_protection_is_unverified_not_passing(self):
        with patch.object(CHECK, "live_protection", return_value=(None, "gh is not installed")):
            self.assertEqual(CHECK.main([]), 0)
            self.assertEqual(CHECK.main(["--require"]), 1)

    def test_a_verified_compliant_repository_satisfies_require(self):
        with patch.object(CHECK, "live_protection", return_value=(compliant(), None)):
            self.assertEqual(CHECK.main(["--require"]), 0)

    def test_a_verified_noncompliant_repository_fails_require(self):
        live = compliant()
        live["enforce_admins"]["enabled"] = False
        with patch.object(CHECK, "live_protection", return_value=(live, None)):
            self.assertEqual(CHECK.main(["--require"]), 1)

    def test_inventory_failure_is_nonzero_and_does_not_contact_github(self):
        with patch.object(CHECK, "workflow_job_names",
                          side_effect=CHECK.WorkflowInventoryError("unsupported matrix")), \
                patch.object(CHECK, "live_protection") as live, redirect_stdout(io.StringIO()) as out:
            self.assertEqual(CHECK.main([]), 1)
            live.assert_not_called()
        report = json.loads(out.getvalue())
        self.assertFalse(report["verified"])
        self.assertIn("unsupported matrix", report["problems"][0])

    def test_produced_but_unrequired_context_fails_live_verification(self):
        produced = CHECK.workflow_job_names(ROOT) | {"new unchecked job"}
        with patch.object(CHECK, "workflow_job_names", return_value=produced), \
                patch.object(CHECK, "live_protection", return_value=(compliant(), None)), \
                redirect_stdout(io.StringIO()) as out:
            self.assertEqual(CHECK.main(["--require"]), 1)
        self.assertIn("new unchecked job", json.loads(out.getvalue())["problems"][0])

    def test_the_policy_is_documented_where_a_maintainer_will_look(self):
        policy_document = (ROOT / "docs/REPOSITORY_POLICY.md").read_text(encoding="utf-8")
        for context in POLICY["required_status_checks"]["contexts"]:
            with self.subTest(context=context):
                self.assertIn(context, policy_document)


if __name__ == "__main__":
    unittest.main()
