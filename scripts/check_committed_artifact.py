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
GENERATED_FILES = {"build/partial.rdb"}
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
    packaged_paths = set(files) - GENERATED_FILES
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
    r = subprocess.check_output([rscript, "--vanilla", "-e", 'cat(file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R"))'],
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
    stopifnot(identical(loader(name)$source_provenance$data_kind, "synthetic"))
}
'''
    run("archived_smoke", [rscript, "--vanilla", "-e", code, str(library),
                           report["package"], report["version"], str(smoke)])
    report["isolated_library"] = str(library)
    report["archived_smoke_test_run"] = True
    report["public_synthetic_examples_checked"] = report["package"] == "Gtheory4LLM"


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
    args = parser.parse_args(argv)
    work = args.output_dir.resolve() if args.output_dir else Path(tempfile.mkdtemp(prefix="gtheory-committed-artifact-"))
    work.mkdir(parents=True, exist_ok=True)
    report = {"success": False, "workspace": str(work), "mode": "integrity_only" if args.verify_only else "integrity_install_smoke"}
    environment = os.environ.copy()
    environment.update({"R_PROFILE_USER": os.devnull, "R_ENVIRON_USER": os.devnull})
    try:
        evidence, files = verify_bundle(ROOT, args.manifest.resolve())
        report.update(evidence)
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
