"""The declared protection policy must describe checks that actually exist.

No network access and no repository settings are involved: this exercises the
policy file, the workflow-context parser, and the comparison logic against
constructed API responses.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
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
        "required_pull_request_reviews": {"required_approving_review_count": 1,
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

    def test_matrix_job_names_are_expanded(self):
        produced = CHECK.workflow_job_names(ROOT)
        self.assertIn("ubuntu-22.04 / R 4.5.0", produced)
        self.assertNotIn("${{ matrix.os }} / R ${{ matrix.r }}", produced)


class ComparisonTests(unittest.TestCase):
    def test_a_compliant_repository_reports_no_problems(self):
        self.assertEqual(CHECK.compare(POLICY, compliant()), [])

    def test_each_relaxation_is_reported(self):
        for mutate, expected in (
            (lambda live: live["required_status_checks"]["contexts"].remove("validate"),
             "required status checks missing"),
            (lambda live: live["required_status_checks"].update(strict=False),
             "not strict"),
            (lambda live: live["required_pull_request_reviews"].update(required_approving_review_count=0),
             "approving reviews below policy"),
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

    def test_the_policy_is_documented_where_a_maintainer_will_look(self):
        policy_document = (ROOT / "docs/REPOSITORY_POLICY.md").read_text(encoding="utf-8")
        for context in POLICY["required_status_checks"]["contexts"]:
            with self.subTest(context=context):
                self.assertIn(context, policy_document)


if __name__ == "__main__":
    unittest.main()
