"""Deliberate dependency drift must fail before environment restoration."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("documentation_lock", ROOT / "scripts/check_documentation_lock.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class DocumentationLockTests(unittest.TestCase):
    def setUp(self):
        self.numerical = json.loads((ROOT / "renv.lock").read_text())
        self.documentation = json.loads(module.DOC_LOCK.read_text())

    def test_current_lock_preserves_numerical_environment(self):
        module.validate_locks(self.numerical, self.documentation)

    def test_runtime_dependency_changes_and_omissions_fail(self):
        for name in self.numerical["Packages"]:
            for change in ("version", "omit"):
                candidate = copy.deepcopy(self.documentation)
                if change == "version":
                    candidate["Packages"][name]["Version"] = "0.0.0"
                else:
                    del candidate["Packages"][name]
                with self.subTest(package=name, change=change), self.assertRaisesRegex(ValueError, name):
                    module.validate_locks(self.numerical, candidate)

    def test_r_and_documentation_roots_cannot_drift(self):
        candidate = copy.deepcopy(self.documentation)
        candidate["R"]["Version"] = "0.0.0"
        with self.assertRaisesRegex(ValueError, "R and repositories"):
            module.validate_locks(self.numerical, candidate)
        for name in ("knitr", "rmarkdown"):
            candidate = copy.deepcopy(self.documentation)
            del candidate["Packages"][name]
            with self.assertRaisesRegex(ValueError, "knitr and rmarkdown"):
                module.validate_locks(self.numerical, candidate)


if __name__ == "__main__":
    unittest.main()
