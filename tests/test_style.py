"""The style check must hold, and must actually catch what it claims to."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("check_style", ROOT / "scripts/check_style.py")
STYLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STYLE)


class StyleRuleTests(unittest.TestCase):
    def check(self, text):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.R"
            path.write_text(text, encoding="utf-8")
            original = STYLE.ROOT
            STYLE.ROOT = Path(directory)
            try:
                return {finding["rule"] for finding in STYLE.findings(path)}
            finally:
                STYLE.ROOT = original

    def test_clean_code_reports_nothing(self):
        self.assertEqual(self.check("x <- c(TRUE, FALSE)\nf <- function(a) a + 1\n"), set())

    def test_each_rule_catches_its_own_defect(self):
        for text, rule in (
            ("x <-\tTRUE\n", "tab"),
            ("x <- TRUE   \n", "trailing_whitespace"),
            ("x <- " + " + ".join(["variable"] * 20) + "\n", "long_code_line"),
            ("f(check = T)\n", "logical_abbreviation"),
            ("x <- c(a, T)\n", "logical_abbreviation"),
        ):
            with self.subTest(rule=rule):
                self.assertIn(rule, self.check(text))

    def test_a_long_error_message_is_not_a_long_code_line(self):
        message = ('  stop("' + "a deliberately long explanation " * 5 + '", call. = FALSE)\n')
        self.assertGreater(len(message), STYLE.CODE_LINE_LIMIT)
        self.assertNotIn("long_code_line", self.check(message))

    def test_t_inside_a_string_or_comment_is_not_an_abbreviation(self):
        self.assertNotIn("logical_abbreviation", self.check('x <- "T"\n'))
        self.assertNotIn("logical_abbreviation", self.check("x <- 1  # T\n"))
        self.assertNotIn("logical_abbreviation", self.check("x <- data$T\n"))


class RepositoryStyleTests(unittest.TestCase):
    def test_the_r_sources_pass(self):
        problems = [finding for path in STYLE.sources(ROOT) for finding in STYLE.findings(path)]
        self.assertEqual(problems, [], "\n".join(
            f"{p['file']}:{p['line']} {p['rule']}: {p['detail']}" for p in problems))

    def test_every_source_file_is_checked(self):
        checked = {path.name for path in STYLE.sources(ROOT)}
        declared = {line.strip().strip("',") for line in
                    (ROOT / "DESCRIPTION").read_text().splitlines() if line.startswith("    '")}
        self.assertTrue(declared, "DESCRIPTION declares no Collate entries")
        self.assertTrue(declared <= checked,
                        f"Collate names files the style check skips: {sorted(declared - checked)}")


if __name__ == "__main__":
    unittest.main()
