"""Verify and smoke-test the distributed archive against its recorded source commit.

This deliberately does not rebuild the archive or compare it with the checkout's
current source: a source-only commit may retain the preceding release bundle.
The manifest's source commit must exist in this checkout's history.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOTS = {"R", "man", "inst", "data", "src", "tests", "vignettes"}
PACKAGE_FILES = {"DESCRIPTION", "NAMESPACE", "LICENSE", "LICENCE", "LICENSE.note",
                 "NEWS", "NEWS.md", "NEWS.Rd", "README", "README.md", "README.Rmd"}
# R CMD build writes these itself and they have no counterpart in git:
# partial.rdb while preparing lazy loading, and vignette.rds as the index of
# the vignettes it built. Built vignette products land in inst/doc/ and are
# derived per vignette, so they are computed from the source commit rather
# than whitelisted by prefix: an unexpected file under inst/doc/ must still fail.
GENERATED_FILES = {"build/partial.rdb", "build/vignette.rds"}
VIGNETTE_PRODUCT_SUFFIXES = (".R", ".html", ".pdf")
GENERATED_FIELDS = {"Packaged", "Built", "NeedsCompilation"}
MAX_FILES = 10000
MAX_BYTES = 512 * 1024 * 1024
MAX_FILE_BYTES = 128 * 1024 * 1024


def git(root: Path, *arguments: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.PIPE)


def read_dcf(content: bytes) -> dict[str, str]:
    result: dict[str, str] = {}
    key = None
    for line in content.decode("utf-8").splitlines():
        if not line.strip():
            continue
        if line[0].isspace():
            if key is None:
                raise ValueError("DESCRIPTION has an orphan continuation")
            result[key] += " " + line.strip()
        else:
            key, separator, value = line.partition(":")
            if not separator or key in result:
                raise ValueError("Invalid or duplicate DESCRIPTION field")
            result[key] = value.strip()
    return {key: " ".join(value.split()) for key, value in result.items()}


def read_archive(path: Path, package: str) -> dict[str, bytes]:
    """Read regular files only; never call tarfile.extract or trust member paths."""
    files: dict[str, bytes] = {}
    seen = set()
    total = 0
    with tarfile.open(path, "r:gz") as archive:
        for index, member in enumerate(archive, 1):
            name = member.name.rstrip("/")
            parts = name.split("/")
            if (index > MAX_FILES or not name or "\\" in name or
                    any(part in {"", ".", ".."} for part in parts) or
                    PurePosixPath(name).is_absolute() or parts[0] != package):
                raise ValueError("Unsafe archive member: " + member.name)
            if name in seen:
                raise ValueError("Duplicate archive member: " + name)
            seen.add(name)
            if not (member.isdir() or member.isfile()):
                raise ValueError("Archive links and special files are not permitted: " + name)
            if member.isdir():
                continue
            if len(parts) < 2:
                raise ValueError("Expected files inside package directory")
            total += member.size
            if member.size < 0 or member.size > MAX_FILE_BYTES or total > MAX_BYTES:
                raise ValueError("Archive exceeds inspection size limit")
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError("Cannot read archive member: " + name)
            content = stream.read(MAX_FILE_BYTES + 1)
            if len(content) != member.size:
                raise ValueError("Truncated archive member: " + name)
            files["/".join(parts[1:])] = content
    return files


def package_source_paths(root: Path, commit: str) -> set[str]:
    names = git(root, "ls-tree", "-r", "--name-only", "-z", commit).decode().split("\0")
    ignore = git(root, "show", commit + ":.Rbuildignore").decode().splitlines()
    patterns = [re.compile(pattern, re.I) for pattern in ignore if pattern.strip()]
    def included(name: str) -> bool:
        parts = PurePosixPath(name).parts
        if not parts or not (parts[0] in PACKAGE_ROOTS or name in PACKAGE_FILES):
            return False
        prefixes = ["/".join(parts[:i]) for i in range(1, len(parts) + 1)]
        return not any(pattern.search(prefix) for pattern in patterns for prefix in prefixes)
    return {name for name in names if included(name)}


def vignette_products(source_paths: set[str]) -> set[str]:
    """Paths R CMD build derives in inst/doc/ from each declared vignette.

    Only the products of vignettes that exist in the source commit are
    excused, so an unexpected file under inst/doc/ still fails the inventory.
    """
    products: set[str] = set()
    for name in source_paths:
        parts = PurePosixPath(name)
        if parts.parent.as_posix() != "vignettes":
            continue
        products.add("inst/doc/" + parts.name)
        for suffix in VIGNETTE_PRODUCT_SUFFIXES:
            products.add("inst/doc/" + parts.stem + suffix)
    return products


def verify_bundle(root: Path, manifest_path: Path) -> tuple[dict, dict[str, bytes]]:
    manifest = json.loads(manifest_path.read_text())
    package, version, commit = (manifest[key] for key in ("package", "version", "source_commit"))
    if not isinstance(package, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9.]*", package):
        raise ValueError("Invalid manifest package name")
    if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:[.-][0-9]+)*", version):
        raise ValueError("Invalid manifest version")
    if not isinstance(commit, str) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("Manifest source_commit must be a full commit hash")
    if git(root, "rev-parse", commit + "^{commit}").decode().strip() != commit:
        raise ValueError("Manifest source_commit does not resolve to the declared commit")
    if subprocess.run(["git", "-C", str(root), "merge-base", "--is-ancestor", commit, "HEAD"],
                      capture_output=True).returncode:
        raise ValueError("Manifest source_commit is not an ancestor of HEAD")
    archive_name, manual_name = f"{package}_{version}.tar.gz", f"{package}-manual.pdf"
    if set(manifest["files"]) != {archive_name, manual_name}:
        raise ValueError("Manifest must describe exactly the package archive and manual")
    verified = {}
    for name, expected in manifest["files"].items():
        path = manifest_path.parent / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("Expected regular artifact file: " + name)
        actual_size = path.stat().st_size
        if actual_size != expected["bytes"]:
            raise ValueError("Artifact size mismatch: " + name)
        checksum = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                checksum.update(chunk)
        digest = checksum.hexdigest()
        if digest != expected["sha256"]:
            raise ValueError("Artifact checksum mismatch: " + name)
        verified[name] = {"bytes": actual_size, "sha256": digest}
    with (manifest_path.parent / manual_name).open("rb") as stream:
        if stream.read(5) != b"%PDF-":
            raise ValueError("Manual does not have a PDF header")
    files = read_archive(manifest_path.parent / archive_name, package)
    if "DESCRIPTION" not in files or "tests/package-smoke.R" not in files:
        raise ValueError("Archive is missing DESCRIPTION or its installed smoke test")
    actual = read_dcf(files["DESCRIPTION"])
    expected = read_dcf(git(root, "show", commit + ":DESCRIPTION"))
    if actual.get("Package") != package or actual.get("Version") != version:
        raise ValueError("Archive package/version differs from manifest")
    if expected.get("Package") != package or expected.get("Version") != version:
        raise ValueError("Source commit package/version differs from manifest")
    if any(actual.get(key) != value for key, value in expected.items()):
        raise ValueError("Archive DESCRIPTION differs from declared source metadata")
    if set(actual) - set(expected) - GENERATED_FIELDS:
        raise ValueError("Unexpected generated DESCRIPTION fields")
    source_paths = package_source_paths(root, commit)
    packaged_paths = set(files) - GENERATED_FILES - vignette_products(source_paths)
    if source_paths != packaged_paths:
        raise ValueError("Archive/source file inventory differs: missing=" +
                         str(sorted(source_paths - packaged_paths)) + "; extra=" +
                         str(sorted(packaged_paths - source_paths)))
    compared = []
    for name in sorted(packaged_paths - {"DESCRIPTION"}):
        if files[name] != git(root, "show", commit + ":" + name):
            raise ValueError("Archive content differs from declared source: " + name)
        compared.append(name)
    return {"package": package, "version": version, "source_commit": commit,
            "files": verified, "source_files_compared": compared,
            "description_metadata_matches": True, "archive": str(manifest_path.parent / archive_name)}, files


RELEASE_STATES = ("prepared", "published")


def local_release_tag(root: Path, tag: str) -> bool:
    """Whether this checkout can resolve the tag, without contacting a remote."""
    return not subprocess.run(["git", "-C", str(root), "rev-parse", "--verify",
                               "--quiet", f"refs/tags/{tag}^{{commit}}"],
                              capture_output=True).returncode


def verify_published_prose(root: Path, version: str, *, neutral_source: bool = False) -> None:
    """Catch known stale publication claims outside the identity markers.

    README and development status describe the present. NEWS and archived
    release documents retain history and are deliberately outside this check.
    Neutral-source preparation additionally checks the current NEWS section,
    before publication can make stale prose permanent. This is a regression
    guard for known contradictions, not a language parser.
    """
    release = r"v?" + re.escape(version) + r"(?![\d.])"
    patterns = (
        rf"\buntil (?:the )?{release}(?: release)? is published\b",
        rf"\b{release}(?: release)? (?:is not|isn't|has not been|hasn't been) published\b",
        rf"\bno {release} (?:release|tag)(?: exists)?\b",
        r"\bno (?:github )?release (?:is published|exists)\b",
        r"\bonce releases exist\b",
    )
    names = ("README.md", "NEWS.md") if neutral_source else ("README.md", "docs/DEVELOPMENT_STATUS.md")
    if neutral_source:
        patterns += (r"\brelease state: (?:prepared|published)\b",)
    for name in names:
        path = root / name
        if not path.is_file():
            continue
        prose = path.read_text(encoding="utf-8")
        if name == "NEWS.md":
            sections = re.split(r"(?m)^# [^\n]*$", prose, maxsplit=2)
            prose = "\n".join(sections[:2])
        prose = re.sub(r"(?ms)^```[^\n]*\n.*?^```[^\n]*$", "", prose)
        prose = re.sub(r"(?m)^>.*$", "", prose)
        prose = re.sub(r"[`*_]", "", prose)
        prose = " ".join(prose.split())
        if any(re.search(pattern, prose, re.I) for pattern in patterns):
            context = f"neutral source version {version}" if neutral_source else f"the published {version} bundle"
            raise ValueError(f"{name}: stale unpublished-release prose contradicts {context}")


DEVELOPMENT_VERSION = re.compile(r"(?P<target>[0-9]+(?:\.[0-9]+)*)\.(?P<series>9[0-9]{3,})")


def release_order(version: str) -> tuple[int, ...]:
    """Order release versions numerically rather than as text.

    "0.10.0" follows "0.9.0"; string comparison would put it before. The
    accepted syntax allows a variable number of components, so trailing zero
    components are dropped before comparing: otherwise tuple comparison makes
    "0.2" precede "0.2.0", and two spellings of one release would not compare
    equal.
    """
    parts = [int(part) for part in version.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def verify_release_identity(root: Path, manifest_path: Path,
                            release_tag: str | None = None) -> dict:
    """Check current release prose without rewriting historical archive contents.

    The manifest is the release identity. A .9000 development checkout may keep
    that release, but must say which source and artifact versions it describes.
    A release-tag check additionally verifies the tag's metadata and manifest.
    Archive byte integrity/source correspondence remain verify_bundle's job.

    The manifest also declares whether the bundle is only prepared locally or
    actually published. A locally prepared bundle and a published release are
    different states, and prose calling a bundle published while no version tag
    exists is the drift this check exists to catch, in either direction.
    """
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    package, version = manifest["package"], manifest["version"]
    state = manifest.get("release_state")
    if state not in RELEASE_STATES:
        raise ValueError("Artifact manifest must declare release_state as one of: " +
                         ", ".join(RELEASE_STATES))
    description = read_dcf((root / "DESCRIPTION").read_bytes())
    source_version = description.get("Version")
    if description.get("Package") != package:
        raise ValueError("Release package mismatch: DESCRIPTION versus artifact manifest")
    # A development checkout is labelled <target>.9000, where <target> is the
    # release it is working towards. That target may be the released version
    # (0.1.0 -> 0.1.0.9000) or a later one (0.1.0 -> 0.2.0.9000); both are
    # ordinary R practice. It may never be earlier than the released bundle.
    labelled = DEVELOPMENT_VERSION.fullmatch(source_version or "")
    development = bool(labelled) and (
        release_order(labelled.group("target")) >= release_order(version))
    if source_version != version and not development:
        raise ValueError("Release version mismatch: DESCRIPTION versus artifact manifest; "
                         "use an explicitly labelled .9000 checkout for development")
    archive_name = f"{package}_{version}.tar.gz"
    if set(manifest["files"]) != {archive_name, f"{package}-manual.pdf"}:
        raise ValueError("Release archive filename/version mismatch with artifact manifest")
    for name in ("README.md", "NEWS.md"):
        prose = (root / name).read_text(encoding="utf-8")
        blocks = re.findall(r"<!-- release-identity:start -->(.*?)<!-- release-identity:end -->",
                            prose, re.S)
        if len(blocks) != 1:
            raise ValueError(f"{name}: expected one release-identity summary")
        neutral = re.findall(r"Source version: \*\*([^*]+)\*\*\.", blocks[0])
        if neutral:
            verify_published_prose(root, source_version, neutral_source=True)
            if neutral != [source_version]:
                raise ValueError(f"{name}: source version mismatch with DESCRIPTION")
            if re.search(r"(?:Release state|Current artifact bundle|Checkout version):", blocks[0]):
                raise ValueError(f"{name}: neutral source summary contains mutable release metadata")
            if "artifacts/manifest.json" not in blocks[0] or "/releases" not in blocks[0]:
                raise ValueError(f"{name}: neutral source summary must link repository release metadata")
        else:
            # Published historical checkouts retain their original format and bytes.
            declared = re.findall(r"Current artifact bundle: \*\*([^*]+)\*\*\.", blocks[0])
            if declared != [version]:
                raise ValueError(f"{name}: current artifact version mismatch with manifest ({version})")
            declared_state = re.findall(r"Release state: \*\*([^*]+)\*\*\.", blocks[0])
            if declared_state != [state]:
                raise ValueError(f"{name}: release state mismatch with manifest ({state})")
            if name == "README.md":
                current = re.findall(r"Checkout version: \*\*([^*]+)\*\*\.", blocks[0])
                if current != [source_version]:
                    raise ValueError("README.md: checkout version mismatch with DESCRIPTION")
    if state == "published":
        verify_published_prose(root, version)
    heading = (manifest_path.parent / "README.md").read_text(encoding="utf-8").splitlines()[0]
    if heading != f"# {package} {version} release":
        raise ValueError("artifacts/README.md: release version mismatch with manifest")
    # A declared state is only worth as much as the git evidence behind it.
    version_tag = f"v{version}"
    tag_present = local_release_tag(root, version_tag)
    if state == "published" and not tag_present:
        raise ValueError(f"Release state 'published' requires the {version_tag} tag in this "
                         "checkout; fetch tags, or declare release_state 'prepared'")
    if state == "prepared" and tag_present and not development:
        raise ValueError(f"Release state 'prepared' contradicts the existing {version_tag} tag; "
                         "update release_state to 'published' after publication")
    def check_tag(tag: str) -> None:
        """Compare the tag's own metadata with the bundle it claims to publish."""
        ref = f"refs/tags/{tag}"
        try:
            tagged = read_dcf(git(root, "show", ref + ":DESCRIPTION"))
            tagged_manifest = json.loads(git(root, "show", ref + ":artifacts/manifest.json"))
        except subprocess.CalledProcessError as error:
            raise ValueError("Release tag is unavailable locally; fetch its history first") from error
        if tagged.get("Package") != package or tagged.get("Version") != version:
            raise ValueError("Release tag DESCRIPTION version/package mismatch")
        if tagged_manifest != manifest:
            raise ValueError("Release tag manifest differs from the distributed bundle manifest")

    if release_tag is not None:
        # An explicit tag asserts that this checkout is that release, so a
        # development checkout cannot claim it.
        if release_tag != version_tag or development:
            raise ValueError("Release tag/version mismatch with manifest or checkout")
        check_tag(release_tag)
    elif state == "published":
        # A published bundle is always tag-checked, including from a later
        # development checkout that legitimately retains the prior release.
        check_tag(version_tag)
        release_tag = version_tag
    return {"package": package, "source_version": source_version,
            "artifact_version": version, "archive": archive_name,
            "source_commit": manifest["source_commit"], "development_checkout": development,
            "release_state": state, "version_tag_present": tag_present,
            "release_tag": release_tag, "release_tag_checked": release_tag is not None,
            "published": state == "published",
            "archive_matches_current_checkout": "not_asserted; compared to recorded source commit"}


def install_and_smoke(report: dict, files: dict[str, bytes], work: Path, rscript: str, environment: dict) -> None:
    library = work / "library"
    library.mkdir()  # A reused installed package cannot satisfy this check.
    smoke = work / "package-smoke.R"
    smoke.write_bytes(files["tests/package-smoke.R"])
    report["steps"] = []
    def run(name: str, command: list[str]) -> None:
        result = subprocess.run(command, cwd=work, env=environment, capture_output=True, text=True)
        (work / (name + ".log")).write_text(sanitize(result.stdout + result.stderr, work))
        report["steps"].append({"name": name, "exit_code": result.returncode})
        print(sanitize(result.stdout + result.stderr, work), flush=True)
        if result.returncode:
            raise RuntimeError(name + " failed")
    # Obtain R from the selected Rscript rather than a possibly different PATH R.
    runtime_script = work / "runtime.R"
    runtime_script.write_bytes('cat(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))'.encode("utf-8"))
    r = subprocess.check_output([rscript, "--vanilla", str(runtime_script)],
                                env=environment, text=True).strip()
    run("install", [r, "CMD", "INSTALL", "--library=" + str(library), report["archive"]])
    code = '''args <- commandArgs(TRUE)
.libPaths(c(args[1L], .libPaths()))
expected <- normalizePath(file.path(args[1L], args[2L]), mustWork=TRUE)
actual <- normalizePath(find.package(args[2L]), mustWork=TRUE)
stopifnot(identical(actual, expected),
          packageDescription(args[2L], fields="Version") == args[3L])
source(args[4L], chdir=FALSE)
stopifnot(identical(normalizePath(getNamespaceInfo(asNamespace(args[2L]), "path")), expected))
if (identical(args[2L], "Gtheory4LLM")) {
  loader <- getExportedValue(args[2L], "gt_example")
  for (name in loader()$name)
    stopifnot(identical(loader(name)$source_provenance$data_kind, "public_llm_annotations"))
}
'''
    wrapper = work / "archived-smoke-wrapper.R"
    wrapper.write_bytes(code.encode("utf-8"))
    run("archived_smoke", [rscript, "--vanilla", str(wrapper), str(library),
                           report["package"], report["version"], str(smoke)])
    report["isolated_library"] = str(library)
    report["archived_smoke_test_run"] = True
    report["public_llm_annotations_checked"] = report["package"] == "Gtheory4LLM"


def sanitize(value, work):
    if isinstance(value, dict): return {key: sanitize(item, work) for key, item in value.items()}
    if isinstance(value, list): return [sanitize(item, work) for item in value]
    if isinstance(value, str):
        for path, label in ((ROOT, "<source>"), (work, "<validation>"), (Path.home(), "<home>")):
            value = value.replace(str(path), label).replace(str(path).replace("\\", "/"), label)
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rscript", default="Rscript")
    parser.add_argument("--manifest", type=Path, default=ROOT / "artifacts/manifest.json")
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--verify-only", action="store_true", help="Check integrity and source correspondence without installing; this is not a smoke-test pass.")
    parser.add_argument("--check-release-identity", action="store_true", help="Also check current DESCRIPTION and release summaries against the manifest.")
    parser.add_argument("--release-tag", help="Also verify this locally available release tag, e.g. v0.1.0.")
    args = parser.parse_args(argv)
    work = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix="gtheory-committed-artifact-"))
    work.mkdir(parents=True, exist_ok=True)
    report = {"success": False, "workspace": str(work), "mode": "integrity_only" if args.verify_only else "integrity_install_smoke"}
    environment = os.environ.copy()
    environment.update({"R_PROFILE_USER": os.devnull, "R_ENVIRON_USER": os.devnull})
    try:
        evidence, files = verify_bundle(ROOT, args.manifest.resolve())
        report.update(evidence)
        if args.check_release_identity or args.release_tag:
            report["release_identity"] = verify_release_identity(ROOT, args.manifest.resolve(), args.release_tag)
        if not args.verify_only:
            install_and_smoke(report, files, work, args.rscript, environment)
        report["success"] = True
    except Exception as error:
        report["error"] = str(error)
    report = sanitize(report, work)
    (work / "committed_artifact_validation.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2), flush=True)
    return 0 if report["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
