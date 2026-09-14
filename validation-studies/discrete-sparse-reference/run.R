# Freeze the fixed-parameter targets a sparse discrete backend must reproduce.
#
# Run from the project directory:
#   Rscript validation-studies/discrete-sparse-reference/run.R
#
# Regenerating changes committed reference values and their recorded hashes,
# which is the point: a sparse implementation must be made to meet these
# numbers, and moving the numbers to meet an implementation has to be visible
# in a diff rather than quiet.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))

out_dir <- file.path("validation-studies", "discrete-sparse-reference")
reference <- discrete_reference_rows()
reference$value <- vapply(reference$value, function(x) as.numeric(sprintf("%.17g", x)), numeric(1))
path <- file.path(out_dir, "reference.csv")
write.csv(reference, path, row.names = FALSE, quote = FALSE)

rejections <- discrete_reference_rejections()
write.csv(rejections, file.path(out_dir, "rejections.csv"), row.names = FALSE, quote = FALSE)

# Source provenance: the reference is only meaningful alongside the code that
# produced it, and a later change must not be able to move one without the
# other becoming visible.
sources <- c(file.path("R", c("design.R", "family.R", "discrete_response.R",
                              "discrete_dense.R", "discrete_mode.R", "discrete.R")),
             file.path(out_dir, c("cases.R", "run.R")), path,
             file.path(out_dir, "rejections.csv"))
hashes <- data.frame(file = sources, md5 = unname(tools::md5sum(sources)),
                     stringsAsFactors = FALSE)
write.csv(hashes, file.path(out_dir, "source-hashes.csv"), row.names = FALSE, quote = FALSE)
cat("Froze", nrow(reference), "reference quantities and",
    nrow(rejections), "declared rejections.\n")
cat("reference.csv md5:", unname(tools::md5sum(path)), "\n")
