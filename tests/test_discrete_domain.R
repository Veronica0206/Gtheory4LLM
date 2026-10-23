# Run the same contract on source-loaded functions and in the built archive.
Sys.setenv(GT_DOMAIN_TEST_SOURCE = "true")
source("tests/package-discrete-domain.R")
