"""Guard CI coverage and immutable actions without running hosted jobs or fits."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
EXPECTED = {"full-validation.yml", "compatibility.yml", "cran-readiness.yml"}
REVIEWED_SHAS = {
    "actions/checkout": "3d3c42e5aac5ba805825da76410c181273ba90b1",
    "actions/setup-python": "5fda3b95a4ea91299a34e894583c3862153e4b97",
    "actions/cache": "55cc8345863c7cc4c66a329aec7e433d2d1c52a9",
    "actions/upload-artifact": "043fb46d1a93c77aae656e7c1c64a875d1fc6a0a",
    "actions/download-artifact": "3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c",
    "r-lib/actions/setup-r": "465b7d8e732ca3921382b1674c59bada9cbf3399",
    "r-lib/actions/setup-tinytex": "465b7d8e732ca3921382b1674c59bada9cbf3399",
    "r-lib/actions/setup-pandoc": "465b7d8e732ca3921382b1674c59bada9cbf3399",
    "r-lib/actions/setup-r-dependencies": "465b7d8e732ca3921382b1674c59bada9cbf3399",
}
MAJORS = {
    "actions/checkout": "v7",
    "actions/setup-python": "v7",
    "actions/cache": "v6",
    "actions/upload-artifact": "v7",
    "actions/download-artifact": "v8",
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
        if (match is None or MAJORS.get(match[1]) != match[3]
                or REVIEWED_SHAS.get(match[1]) != match[2]):
            raise AssertionError(f"Action must match its reviewed full SHA and major comment: {value}")


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


def assert_exact_platform_candidates(text):
    """Reject platform jobs that rebuild or fail to retain same-archive proof."""
    match = re.search(r"(?ms)^  check-platforms:\n(.*?)(?=^  [A-Za-z][\w-]*:\n|\Z)", text)
    if match is None:
        raise AssertionError("Missing exact-archive platform job")
    job = match[1]
    required = (
        "needs: build-release", "os: [macos-latest, windows-latest]",
        "r-version: release", "name: cran-candidate-built-${{ github.sha }}",
        "path: ${{ runner.temp }}/downloaded-cran-candidate",
        'python scripts/cran_readiness.py check --expected-data-kind public_llm_annotations '
        '--candidate-dir "$RUNNER_TEMP/downloaded-cran-candidate" '
        '--output-dir "$RUNNER_TEMP/cran-checked"',
        "name: cran-candidate-platform-evidence-${{ matrix.os }}-${{ github.sha }}",
        "${{ runner.temp }}/cran-checked/*.json", "${{ runner.temp }}/cran-checked/*.Rcheck",
        "if: always()", "TEXLIVE_PREFETCH: '0'", "$process.WaitForExit(300000)",
        "$attempt -le 2", "taskkill.exe /PID $process.Id /T /F", "timeout-minutes: 15",
    )
    if any(fragment not in job for fragment in required):
        raise AssertionError("Platform checks must preserve the bounded same-archive contract")
    forbidden = ("cran_readiness.py build", "R CMD build", "run_validation.py",
                 "stage_validation_bundle.py", "--require-devel", "continue-on-error:",
                 "--no-manual", "--no-tests")
    if any(fragment in job for fragment in forbidden):
        raise AssertionError("Platform candidates must be checked without rebuilding or skipping gates")


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
        for value in ["actions/checkout@v7", "actions/checkout@abcdef0 # v7",
                      f"actions/checkout@{sha} # v8", f"actions/checkout@{sha}",
                      f"actions/checkout@{sha} # v7"]:
            with self.subTest(value=value), self.assertRaises(AssertionError):
                assert_pinned_actions(f"      - uses: {value}\n")

    def test_shallow_source_checkouts_are_rejected(self):
        for name in sorted(EXPECTED):
            original = (WORKFLOWS / name).read_text(encoding="utf-8")
            for changed in (original.replace("fetch-depth: 0", "fetch-depth: 1", 1),
                            original.replace("          fetch-depth: 0\n", "", 1)):
                with self.subTest(workflow=name), self.assertRaisesRegex(AssertionError, "full checkout history"):
                    assert_source_checkout_has_history(changed)

    def test_platform_jobs_check_the_same_archive_with_required_manual(self):
        original = (WORKFLOWS / "cran-readiness.yml").read_text(encoding="utf-8")
        assert_exact_platform_candidates(original)
        mutations = [
            original.replace("os: [macos-latest, windows-latest]", "os: [macos-latest]"),
            original.replace("python scripts/cran_readiness.py check --expected-data-kind",
                             "python scripts/cran_readiness.py build --expected-data-kind"),
            original.replace('"$RUNNER_TEMP/downloaded-cran-candidate" --output-dir',
                             '"$RUNNER_TEMP/rebuilt-candidate" --output-dir'),
            original.replace("name: cran-candidate-platform-evidence-${{ matrix.os }}-${{ github.sha }}",
                             "name: cran-candidate-platform-evidence-${{ github.sha }}"),
            original.replace("$process.WaitForExit(300000)", "$process.WaitForExit()"),
            original.replace("        timeout-minutes: 15", "        continue-on-error: true"),
        ]
        for changed in mutations:
            with self.assertRaises(AssertionError):
                assert_exact_platform_candidates(changed)


if __name__ == "__main__":
    unittest.main()
