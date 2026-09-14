"""Check the R sources against this project's deliberately narrow style rules.

The rules here are the ones where a violation is a defect rather than a taste:
a tab that renders differently for the next reader, trailing whitespace that
makes a diff noisier than the change, `T` and `F` used as logicals when either
can be reassigned, and a code line so long that it has to be scrolled to read.

Long lines that are mostly an error message are deliberately exempt. A message
kept on one line can be found with grep from a user's bug report, which is worth
more than the column limit. The limit applies to code.

No R process is started; this reads the files.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
CODE_LINE_LIMIT = 120
STRING_SHARE = 0.45
# `T` and `F` are ordinary variables in R and can be reassigned, so code that
# means TRUE or FALSE has to say so.
LOGICAL_ABBREVIATION = re.compile(r"(?<![\w.$@])(?:T|F)(?![\w.])\s*(?:$|[,)\]])")
STRING = re.compile(r'"[^"\\]*(?:\\.[^"\\]*)*"|\'[^\'\\]*(?:\\.[^\'\\]*)*\'')


def sources(root: Path) -> list[Path]:
    return sorted(list((root / "R").glob("*.R")) + [root / "load_functions.R"])


def mostly_message(line: str) -> bool:
    """Whether the line is dominated by literal text rather than by code."""
    quoted = sum(len(match.group(0)) for match in STRING.finditer(line))
    return quoted > STRING_SHARE * len(line)


def findings(path: Path) -> list[dict]:
    result = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        def report(rule: str, detail: str) -> None:
            result.append({"file": str(path.relative_to(ROOT)), "line": number,
                           "rule": rule, "detail": detail})
        if "\t" in line:
            report("tab", "tabs render differently for the next reader; use spaces")
        if line != line.rstrip():
            report("trailing_whitespace", "trailing whitespace makes diffs noisier than the change")
        if len(line) > CODE_LINE_LIMIT and not mostly_message(line):
            report("long_code_line",
                   f"{len(line)} characters of code exceeds {CODE_LINE_LIMIT}")
        without_strings = STRING.sub('""', line.split("#", 1)[0])
        if LOGICAL_ABBREVIATION.search(without_strings):
            report("logical_abbreviation", "write TRUE or FALSE; T and F can be reassigned")
    return result


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT)
    options = parser.parse_args(argv)
    checked = sources(options.root)
    problems = [finding for path in checked for finding in findings(path)]
    report = {"files_checked": len(checked), "code_line_limit": CODE_LINE_LIMIT,
              "message_lines_exempt": True, "findings": problems, "passed": not problems}
    print(json.dumps(report, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
