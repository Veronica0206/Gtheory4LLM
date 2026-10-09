# Run from the project root: Rscript --vanilla tests/test_batch_reliability.R
Sys.setenv(GT_BATCH_TEST_SOURCE = "true")
source("tests/package-batch-reliability.R")
