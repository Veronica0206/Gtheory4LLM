"""Fail closed on private research content in the public package tree/history.

This checks concrete paths, file types, known private-workspace identifiers,
and serialized resource structure. It does not establish redistribution rights
or replace a human review of the material intended for publication. No files
are deleted, no Git state is changed, and no network requests are made.
"""
from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "Gtheory4LLM"
VERSION = "0.0.7"
PUBLIC_DATA_KINDS = ("synthetic", "public_llm_annotations")
CURRENT_ARTIFACTS = {
    f"{PACKAGE}_{VERSION}.tar.gz", f"{PACKAGE}-manual.pdf", "manifest.json", "README.md"
}
PUBLIC_DIRECTORIES = {
    ".github", "R", "man", "inst", "data", "src", "tests", "vignettes",
    "scripts", "examples", "docs", "artifacts"
}
PUBLIC_FILES = {
    "DESCRIPTION", "NAMESPACE", "LICENSE", "LICENCE", "LICENSE.note",
    "NEWS", "NEWS.md", "NEWS.Rd", "README", "README.md", "README.Rmd",
    "renv.lock", "load_functions.R", ".gitignore", ".Rbuildignore",
    "cran-comments.md", "CRAN-SUBMISSION", "CITATION", "configure", "cleanup"
}
# Operating-system metadata files carry no publishable content, are already
# ignored by git, and are recreated by the desktop environment on sight. They
# are skipped only in a working-tree scan, and only by exact name: an audit that
# a maintainer learns to ignore is worse than one that is slightly narrower.
OS_METADATA_FILES = {".DS_Store", "Thumbs.db", "desktop.ini", "._.DS_Store"}
# R CMD build writes these into the archive itself: partial.rdb while preparing
# lazy loading, and vignette.rds as the index of the vignettes it just built.
# vignette.rds appears only once a package actually has vignettes.
GENERATED_BUILD_FILES = {"build/partial.rdb", "build/vignette.rds"}
PRIVATE_DIRECTORIES = {
    "companion", "reference", "review", "planning", "provenance", "archive",
    "archives", "skills", ".agents", ".codex", ".claude"
}
MAX_FILES = 30000
MAX_FILE_BYTES = 128 * 1024**2
MAX_ARCHIVE_BYTES = 512 * 1024**2
MAX_COMMITS = 10000
MAX_FINDINGS = 100

# Pattern spelling avoids matching this audit's own rule definitions. Match
# actual private paths/identifiers, not ordinary scientific prose words.
PRIVATE_PATTERNS = {
    "private home-directory path": re.compile(rb"/(?:Users|home)/[A-Za-z0-9_.-]+/"),
    "private Windows profile path": re.compile(rb"[A-Za-z]:[/\\]Users[/\\][^\s/\\]+[/\\]", re.I),
    "private working-folder identifier": re.compile(rb"00[_]AIWorkingFolder"),
    "private revision-folder identifier": re.compile(rb"03[_]ManuscriptRevision|01[_]R1_WORKING|00[_]R0_FROZEN"),
    "private source-archive identifier": re.compile(rb"manuscript_[R]1"),
    "private research-relative path": re.compile(
        rb"(?:^|[\s\"'(<>=])(?:companion|reference|review|planning|provenance|archives?)[/\\][A-Za-z0-9_.-]",
        re.M),
    "private skill-resource URI": re.compile(rb"skill[:][/][/]", re.I),
}

RDS_AUDIT = r'''
args <- commandArgs(trailingOnly = TRUE)
x <- readRDS(args[[1L]])
if (!is.list(x) || is.data.frame(x))
  stop("Example resource must be a metadata-bearing list.", call. = FALSE)
nodes <- 0L
private <- c("/(Users|home)/[[:alnum:]_.-]+/", "/private/", "/var/folders/",
  "[A-Za-z]:/Users/", "00[_]AIWorkingFolder",
  "03[_]ManuscriptRevision", "01[_]R1_WORKING", "00[_]R0_FROZEN",
  "manuscript_[R]1", "(^|[[:space:]\"'(<>=])(companion|reference|review|planning|provenance|archives?)/[[:alnum:]_.-]",
  "skill[:][/][/]")
walk <- function(value, depth = 0L) {
  nodes <<- nodes + 1L
  if (depth > 100L || nodes > 1000000L)
    stop("Serialized object exceeds the structural inspection limit.", call. = FALSE)
  if (is.environment(value) || is.function(value) ||
      !typeof(value) %in% c("NULL", "logical", "integer", "double", "complex", "character", "list"))
    stop("Serialized resource contains an environment, function, or unsupported executable/reference type.", call. = FALSE)
  if (is.character(value)) {
    normalized <- gsub(intToUtf8(92L), "/", value, fixed = TRUE)
    if (any(grepl("^(/|[A-Za-z]:/|~/)", normalized), na.rm = TRUE))
      stop("Serialized resource contains an absolute filesystem path.", call. = FALSE)
    for (pattern in private)
      if (any(grepl(pattern, normalized, perl = TRUE), na.rm = TRUE))
        stop("Serialized resource contains a private path or workspace identifier.", call. = FALSE)
  }
  if (is.list(value)) for (entry in value) walk(entry, depth + 1L)
  attr <- attributes(value)
  if (!is.null(attr)) {
    walk(names(attr), depth + 1L)
    for (entry in attr) walk(entry, depth + 1L)
  }
}
walk(x)
kind <- x$source_provenance$data_kind
if (!is.list(x$source_provenance) || !is.character(kind) ||
    length(kind) != 1L || is.na(kind) || !kind %in% args[-1L])
  stop("Example resource data_kind is missing, invalid, or outside the approved public kinds for this scope.", call. = FALSE)
cat("OK\n")
'''


class PublicAudit:
    def __init__(self, root: Path, expected_data_kind: str):
        if expected_data_kind not in PUBLIC_DATA_KINDS:
            raise ValueError("The expected data kind must be an explicitly approved public kind.")
        self.root = root.resolve()
        self.expected_data_kind = expected_data_kind
        self.findings: list[dict[str, str]] = []
        self.skipped_os_metadata: list[str] = []
        self.files_checked = 0
        self.rds_checked = 0
        self.archives_checked = 0
        self.commits_checked = 0
        self.scopes_requested: list[str] = []
        self.content_cache: set[tuple[str, str]] = set()

    def fail(self, label: str, reason: str) -> None:
        self.findings.append({"path": label, "reason": reason})
        if len(self.findings) >= MAX_FINDINGS:
            raise ValueError("Finding limit reached; publication is blocked.")

    def allowed_path(self, relative: str, label: str, *, archive: bool = False,
                     directory: bool = False) -> bool:
        path = PurePosixPath(relative)
        parts = relative.split("/")
        if (not relative or path.is_absolute() or "\\" in relative or
                any(part in {"", ".", ".."} for part in parts)):
            self.fail(label, "Unsafe or ambiguous relative path.")
            return False
        if any(part.lower() in PRIVATE_DIRECTORIES for part in parts):
            self.fail(label, "Private research or skill directory is forbidden.")
            return False
        if archive and parts[0] == "build":
            allowed = (directory and relative == "build") or relative in GENERATED_BUILD_FILES
            if not allowed:
                self.fail(label, "Unexpected generated package-build file.")
            return allowed
        if not archive and parts[-1] in OS_METADATA_FILES and not directory:
            self.skipped_os_metadata.append(relative)
            return False
        if parts[0] not in PUBLIC_DIRECTORIES and not (len(parts) == 1 and relative in PUBLIC_FILES):
            self.fail(label, "Unexpected top-level package content.")
            return False
        if parts[0] == "artifacts":
            if archive or not (directory and len(parts) == 1 or
                               len(parts) == 2 and parts[1] in CURRENT_ARTIFACTS):
                self.fail(label, "Only the current public release artifact set is permitted.")
                return False
        if directory:
            return True
        lower = relative.lower()
        if lower.endswith((".tex", ".ipynb", ".patch", ".zip", ".skill", ".skill.enc", ".rda", ".rdata")):
            self.fail(label, "Private document, notebook, opaque data bundle, or development archive type is forbidden.")
            return False
        if lower.endswith((".csv", ".tsv")) and relative != "inst/extdata/manifest.csv":
            self.fail(label, "Only the bundled-resource manifest CSV is permitted.")
            return False
        if lower.endswith((".gz", ".tgz", ".tar", ".bz2", ".xz", ".7z")) and relative != f"artifacts/{PACKAGE}_{VERSION}.tar.gz":
            self.fail(label, "Unexpected or historical archive is forbidden.")
            return False
        if lower.endswith(".pdf") and relative != f"artifacts/{PACKAGE}-manual.pdf":
            self.fail(label, "Only the current package reference manual PDF is permitted.")
            return False
        if lower.endswith(".rds") and not relative.startswith("inst/extdata/"):
            self.fail(label, "Serialized resources must be in the audited bundled-example directory.")
            return False
        return True

    def inspect_rds(self, content: bytes, label: str, *, historical: bool = False) -> None:
        rscript = shutil.which("Rscript")
        if rscript is None:
            self.fail(label, "Rscript is required to inspect serialized resources.")
            return
        allowed_kinds = PUBLIC_DATA_KINDS if historical else (self.expected_data_kind,)
        with tempfile.TemporaryDirectory(prefix="gtheory-public-rds-") as temporary:
            path = Path(temporary) / "resource.rds"
            path.write_bytes(content)
            script = Path(temporary) / "inspect-resource.R"
            script.write_bytes(RDS_AUDIT.encode("utf-8"))
            result = subprocess.run([rscript, "--vanilla", str(script), str(path), *allowed_kinds],
                                    text=True, capture_output=True, timeout=60)
        self.rds_checked += 1
        if result.returncode != 0 or result.stdout.strip() != "OK":
            message = result.stderr.strip().splitlines()
            self.fail(label, message[0][:400] if message else "Serialized-resource inspection failed.")

    def inspect_content(self, relative: str, content: bytes, label: str, *,
                        archive: bool = False, historical: bool = False) -> None:
        self.files_checked += 1
        if self.files_checked > MAX_FILES or len(content) > MAX_FILE_BYTES:
            raise ValueError("File inspection size/count limit exceeded.")
        for reason, pattern in PRIVATE_PATTERNS.items():
            if pattern.search(content):
                self.fail(label, reason)
        if relative in GENERATED_BUILD_FILES:
            # R CMD build owns these. vignette.rds is its index of built
            # vignettes, not an example resource, so the bundled-example
            # metadata rules do not apply. The private-pattern scan above
            # still ran over their bytes.
            return
        if relative.endswith(".rds"):
            self.inspect_rds(content, label, historical=historical)
        elif relative == f"artifacts/{PACKAGE}_{VERSION}.tar.gz":
            if archive:
                self.fail(label, "Nested release archives are forbidden.")
            else:
                self.inspect_archive(content, label, historical=historical)

    def inspect_archive(self, content: bytes, label: str, *, historical: bool = False) -> None:
        self.archives_checked += 1
        total = 0
        seen = set()
        with tarfile.open(fileobj=io.BytesIO(content), mode="r:gz") as bundle:
            for index, member in enumerate(bundle, 1):
                name = member.name.rstrip("/")
                member_label = label + "!" + name
                parts = name.split("/")
                if (index > MAX_FILES or "\\" in name or not name or
                        any(part in {"", ".", ".."} for part in parts) or
                        parts[0] != PACKAGE or name in seen):
                    self.fail(member_label, "Unsafe, duplicate, or unexpected package archive member.")
                    continue
                seen.add(name)
                if member.isdir() and len(parts) == 1:
                    continue
                if not (member.isdir() or member.isfile()):
                    self.fail(member_label, "Archive links and special files are forbidden.")
                    continue
                relative = "/".join(parts[1:])
                if not self.allowed_path(relative, member_label, archive=True, directory=member.isdir()):
                    continue
                if member.isdir():
                    continue
                total += member.size
                if member.size < 0 or member.size > MAX_FILE_BYTES or total > MAX_ARCHIVE_BYTES:
                    raise ValueError("Archive inspection size limit exceeded.")
                stream = bundle.extractfile(member)
                if stream is None:
                    self.fail(member_label, "Unreadable archive member.")
                    continue
                value = stream.read(MAX_FILE_BYTES + 1)
                if len(value) != member.size:
                    self.fail(member_label, "Truncated archive member.")
                    continue
                self.inspect_content(relative, value, member_label, archive=True, historical=historical)

    def working_tree(self) -> None:
        self.scopes_requested.append("working_tree")
        # Include ignored and untracked content: a clean Git status alone is
        # not evidence that a directory is safe to publish or archive.
        for base, directories, files in os.walk(self.root, followlinks=False):
            for name in list(directories):
                path = Path(base) / name
                relative = path.relative_to(self.root).as_posix()
                if relative == ".git" and not path.is_symlink():
                    directories.remove(name)
                    continue
                if path.is_symlink():
                    self.fail(relative, "Symbolic links are forbidden; target was not inspected.")
                    directories.remove(name)
                elif not self.allowed_path(relative, relative, directory=True):
                    directories.remove(name)
            for name in files:
                path = Path(base) / name
                relative = path.relative_to(self.root).as_posix()
                mode = path.lstat().st_mode
                if not stat.S_ISREG(mode):
                    self.fail(relative, "Only regular files are permitted; target was not inspected.")
                    continue
                if not self.allowed_path(relative, relative):
                    continue
                if path.stat().st_size > MAX_FILE_BYTES:
                    self.fail(relative, "File exceeds inspection size limit.")
                    continue
                self.inspect_content(relative, path.read_bytes(), relative)

    def git(self, *arguments: str) -> bytes:
        environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        return subprocess.check_output(["git", "-C", str(self.root), *arguments],
                                       stderr=subprocess.PIPE, env=environment, timeout=60)

    def history(self) -> None:
        self.scopes_requested.append("reachable_git_history")
        gitdir = self.root / ".git"
        if not gitdir.is_dir() or gitdir.is_symlink() or (gitdir / "commondir").exists():
            raise ValueError("History audit requires a self-contained .git directory inside the requested repository.")
        alternates = gitdir / "objects" / "info" / "alternates"
        if alternates.exists() or (gitdir / "objects").is_symlink():
            raise ValueError("External Git object stores are not inspected.")
        if Path(self.git("rev-parse", "--show-toplevel").decode().strip()).resolve() != self.root:
            raise ValueError("Git repository root does not match the requested directory.")
        commits = self.git("rev-list", "--all").decode().splitlines()
        if not commits or len(commits) > MAX_COMMITS:
            raise ValueError("History must contain at least one commit and stay within the inspection limit.")
        checked_paths = set()
        for commit in commits:
            self.commits_checked += 1
            self.inspect_content("commit", self.git("cat-file", "commit", commit), "git:" + commit[:12] + ":message")
            for entry in self.git("ls-tree", "-rz", "--full-tree", commit).split(b"\0"):
                if not entry:
                    continue
                metadata, raw_path = entry.split(b"\t", 1)
                mode, kind, oid = metadata.decode().split()
                relative = raw_path.decode("utf-8", errors="strict")
                label = "git:" + commit[:12] + ":" + relative
                if (relative, mode) not in checked_paths:
                    checked_paths.add((relative, mode))
                    if mode not in {"100644", "100755"} or kind != "blob":
                        self.fail(label, "History contains a symbolic link, submodule, or special file.")
                        continue
                    if not self.allowed_path(relative, label):
                        continue
                elif mode not in {"100644", "100755"} or not self.allowed_path_silent(relative):
                    continue
                cache_key = (oid, PurePosixPath(relative).suffix)
                if cache_key in self.content_cache:
                    continue
                self.content_cache.add(cache_key)
                size = int(self.git("cat-file", "-s", oid).strip())
                if size > MAX_FILE_BYTES:
                    self.fail(label, "Historical file exceeds inspection size limit.")
                    continue
                # Published historical versions can use either approved public kind.
                # Current files and release artifacts are checked separately against
                # the explicitly selected release kind by working_tree().
                self.inspect_content(relative, self.git("cat-file", "blob", oid), label, historical=True)

    def allowed_path_silent(self, relative: str) -> bool:
        # History repeats filenames. Cache allowed paths independently from
        # blobs so a repeated forbidden path cannot trigger data extraction.
        probe = PublicAudit(self.root, self.expected_data_kind)
        return probe.allowed_path(relative, relative)

    def report(self) -> dict:
        return {"passed": not self.findings, "scopes_requested": self.scopes_requested,
                "expected_data_kind": self.expected_data_kind,
                "historical_data_kinds": list(PUBLIC_DATA_KINDS),
                "files_checked": self.files_checked, "serialized_resources_checked": self.rds_checked,
                "archives_checked": self.archives_checked, "commits_checked": self.commits_checked,
                "findings": self.findings,
                "skipped_os_metadata": sorted(set(self.skipped_os_metadata)),
                "scope": "Concrete public-content policy; not a redistribution-rights determination or a substitute for human publication review."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--working-tree", action="store_true", help="Inspect all working files, including ignored/untracked files.")
    parser.add_argument("--history", action="store_true", help="Inspect every reachable Git tree; either approved public data kind is allowed in historical snapshots.")
    parser.add_argument("--expected-data-kind", choices=PUBLIC_DATA_KINDS, required=True,
                        help="Required provenance kind for current files and release archives. History permits either approved public kind.")
    parser.add_argument("--output", type=Path, help="Optional JSON evidence file; otherwise print JSON.")
    args = parser.parse_args()
    audit = PublicAudit(args.root, args.expected_data_kind)
    try:
        if not args.root.is_dir() or args.root.is_symlink():
            raise ValueError("The requested root must be an existing ordinary directory.")
        if args.working_tree or not args.history:
            audit.working_tree()
        if args.history:
            audit.history()
    except (ValueError, OSError, subprocess.SubprocessError, tarfile.TarError) as error:
        audit.findings.append({"path": "audit", "reason": str(error)[:500]})
    report = audit.report()
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered, encoding="utf-8")
        print("Public-content audit:", "PASS" if report["passed"] else "FAIL", "-", args.output)
    else:
        print(rendered, end="")
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
