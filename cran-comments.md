## Resubmission

This is a resubmission. The 0.0.6 submission was returned because README.md
linked to two files that the source archive does not ship,
`scripts/VALIDATION.md` and `LICENSE`. Every README link to a repository-only
file is now an absolute repository URL, and a test in the repository refuses
any such relative link. The version is 0.2.0: the package has moved on since
0.0.6, and the changes are listed in NEWS.md.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

The submitted archive was checked with `R CMD check --as-cran` under R-devel
on Ubuntu. The release sources were also checked with current R release on
macOS and Windows and with R 4.5.0 on Ubuntu. The package declares
`R (>= 4.5.0)` because OpenMx 2.22.11, which it imports, calls a C entry point
introduced in R 4.5.0.
