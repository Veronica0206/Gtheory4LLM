"""Documentation must stay synchronized with the code and with itself.

NAMESPACE and man/*.Rd are hand written on purpose: the Rd pages carry more than
a generator would produce. The cost of that choice is synchronization, so it is
checked here rather than assumed. No R process is started and no fit is run.
"""
from __future__ import annotations

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MAN = ROOT / "man"
# Datasets and topic pages document resources rather than exported functions.
TOPIC_ALIASES = {
    "Gtheory4LLM-package", "Gtheory4LLM", "Gtheory4LLM-datasets", "gtheory_datasets",
    "gtheory_hate_speech", "gtheory_mental_health", "gtheory_drug_review",
    "gt_fit_methods",
}


def description_fields() -> dict[str, str]:
    fields: dict[str, str] = {}
    key = None
    for line in (ROOT / "DESCRIPTION").read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        if line[0].isspace():
            fields[key] += " " + line.strip()
        else:
            key, _, value = line.partition(":")
            fields[key] = value.strip()
    return {key: " ".join(value.split()) for key, value in fields.items()}


def namespace_entries() -> tuple[set[str], set[tuple[str, str]]]:
    text = (ROOT / "NAMESPACE").read_text(encoding="utf-8")
    exports = set(re.findall(r"^export\(([^)]+)\)", text, re.M))
    methods = {tuple(part.strip() for part in entry.split(","))
               for entry in re.findall(r"^S3method\(([^)]+)\)", text, re.M)}
    return exports, methods


def rd_aliases() -> dict[str, Path]:
    aliases: dict[str, Path] = {}
    for path in sorted(MAN.glob("*.Rd")):
        for alias in re.findall(r"\\alias\{([^}]+)\}", path.read_text(encoding="utf-8")):
            aliases[alias] = path
    return aliases


class DocumentationSyncTests(unittest.TestCase):
    def test_every_export_and_s3_method_is_documented(self):
        exports, methods = namespace_entries()
        aliases = rd_aliases()
        self.assertTrue(exports, "NAMESPACE declares no exports")
        for name in sorted(exports):
            with self.subTest(export=name):
                self.assertIn(name, aliases, f"exported {name}() has no \\alias in man/")
        for generic, cls in sorted(methods):
            with self.subTest(method=f"{generic}.{cls}"):
                self.assertIn(f"{generic}.{cls}", aliases,
                              f"registered S3 method {generic}.{cls} has no \\alias in man/")

    def test_no_documentation_page_describes_a_missing_object(self):
        exports, methods = namespace_entries()
        # Bundled resources are documented by name and reached with gt_example(),
        # so the installed files define which names a topic page may describe.
        resources = {path.stem for path in (ROOT / "inst/extdata").glob("*.rds")}
        self.assertTrue(resources, "no bundled resources found to document")
        known = exports | {f"{generic}.{cls}" for generic, cls in methods} | TOPIC_ALIASES | resources
        for alias, path in sorted(rd_aliases().items()):
            with self.subTest(alias=alias):
                self.assertIn(alias, known,
                              f"{path.name} documents {alias}, which is neither exported, "
                              "a registered S3 method, nor a declared topic page")

    def test_usage_sections_name_the_object_they_document(self):
        exports, _ = namespace_entries()
        for path in sorted(MAN.glob("*.Rd")):
            text = path.read_text(encoding="utf-8")
            documented = set(re.findall(r"\\alias\{([^}]+)\}", text)) & exports
            usage = re.search(r"\\usage\{(.*?)\n\}", text, re.S)
            if not documented or usage is None:
                continue
            with self.subTest(page=path.name):
                for name in sorted(documented):
                    self.assertRegex(usage.group(1), rf"(?m)^{re.escape(name)}\(",
                                     f"{path.name} has no \\usage entry for {name}()")


class VersionFloorTests(unittest.TestCase):
    """The R floor is inherited from OpenMx, so its justification must agree."""

    def setUp(self):
        self.fields = description_fields()
        self.r_floor = re.search(r"R \(>= ([0-9.]+)\)", self.fields["Depends"]).group(1)
        self.openmx = re.search(r"OpenMx \(>= ([0-9.]+)\)", self.fields["Imports"]).group(1)

    def test_the_declared_floor_is_justified_where_a_user_installs(self):
        # The reasoning lives once, in the README's install section, because
        # that is where someone meets the requirement. A future OpenMx bump must
        # not leave that explanation behind.
        short = ".".join(self.r_floor.split(".")[:2])
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn(f"R {short}", readme)
        self.assertIn(f"OpenMx {self.openmx}", readme)
        self.assertIn(f"introduced in R {self.r_floor}", readme)
        self.assertIn("R (>= 3.5.0)", readme,
                      "the justification must say what OpenMx itself declares")

    def test_the_limitations_page_states_the_floor_and_points_at_the_reasoning(self):
        # It must carry the rule, and must not carry a second copy of the
        # reasoning that could drift away from the README's.
        short = ".".join(self.r_floor.split(".")[:2])
        limitations = (ROOT / "docs/LIMITATIONS.md").read_text(encoding="utf-8")
        self.assertIn(f"R {self.r_floor} or later is required", limitations)
        self.assertIn("README", limitations)
        self.assertNotIn("R (>= 3.5.0)", limitations,
                         "the reasoning belongs in one place, not two")
        del short

    def test_installation_text_names_the_archive_a_user_can_download(self):
        # That is the bundle's version from the manifest, which a development
        # checkout deliberately leaves behind its own.
        import json
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        manifest = json.loads((ROOT / "artifacts/manifest.json").read_text(encoding="utf-8"))
        archive = f"{manifest['package']}_{manifest['version']}.tar.gz"
        self.assertIn(archive, readme)
        self.assertIn(archive, manifest["files"], "the manifest must describe the archive it names")


class DocumentLinkTests(unittest.TestCase):
    """A limitations page nobody can reach is not a limitations page."""

    LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")

    def documents(self):
        return [ROOT / "README.md", ROOT / "NEWS.md", ROOT / "artifacts/README.md",
                *sorted((ROOT / "docs").glob("*.md")), ROOT / "scripts/VALIDATION.md",
                ROOT / "validation-studies/README.md"]

    def test_every_relative_link_resolves(self):
        for document in self.documents():
            text = document.read_text(encoding="utf-8")
            for target in self.LINK.findall(text):
                if target.startswith(("http://", "https://", "mailto:", "#")):
                    continue
                with self.subTest(document=document.name, target=target):
                    resolved = (document.parent / target.split("#", 1)[0]).resolve()
                    self.assertTrue(resolved.exists(), f"{document.name} links to a missing {target}")

    def test_the_limitations_page_is_reachable_from_the_readme(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("docs/LIMITATIONS.md", readme)

    def test_the_readme_maps_every_document(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for name in sorted((ROOT / "docs").glob("*.md")):
            with self.subTest(document=name.name):
                self.assertIn(f"docs/{name.name}", readme,
                              "a document nobody is pointed to will drift")


class DuplicationTests(unittest.TestCase):
    """One statement, one home.

    Repeating a paragraph across documents is how two of them end up
    contradicting each other. This measures near-duplicate sentences across the
    documentation set so that consolidation stays consolidated.
    """

    DOCUMENTS = ("README.md", "docs/LIMITATIONS.md", "docs/VALIDATION_SCOPE.md",
                 "docs/DEVELOPMENT_STATUS.md", "docs/REAL_DATA_WORKFLOW.md",
                 "docs/ROADMAP.md")
    SIMILARITY = 0.8
    MINIMUM_LENGTH = 60

    def sentences(self, name):
        text = re.sub(r"```.*?```", " ", (ROOT / name).read_text(encoding="utf-8"), flags=re.S)
        text = re.sub(r"\s+", " ", text)
        return [part.strip() for part in re.split(r"(?<=[.!?]) ", text)
                if len(part.strip()) >= self.MINIMUM_LENGTH]

    def test_no_sentence_is_repeated_across_documents(self):
        import itertools
        words = lambda s: set(re.sub(r"[^a-z ]", "", s.lower()).split())
        content = {name: [(s, words(s)) for s in self.sentences(name)] for name in self.DOCUMENTS}
        repeated = []
        for first, second in itertools.combinations(self.DOCUMENTS, 2):
            for text_a, set_a in content[first]:
                for text_b, set_b in content[second]:
                    union = set_a | set_b
                    if union and len(set_a & set_b) / len(union) >= self.SIMILARITY:
                        repeated.append(f"{first} <-> {second}\n    {text_a[:100]}\n    {text_b[:100]}")
        self.assertEqual(repeated, [], "near-duplicate prose:\n  " + "\n  ".join(repeated))


if __name__ == "__main__":
    unittest.main()
