# Every example script the package installs must still run.
#
# A shipped script that no longer works is worse than no script: it is the
# first thing a new user runs. These are sourced in this process against the
# installed package, exactly as the documentation tells a user to run them.
library(Gtheory4LLM)

directory <- system.file("examples", package = "Gtheory4LLM", mustWork = TRUE)
scripts <- sort(list.files(directory, pattern = "[.]R$", full.names = TRUE))
if (!length(scripts)) stop("The package installs no example scripts to check.")

for (script in scripts) {
  name <- basename(script)
  cat("running", name, "\n")
  failures <- character()
  result <- withCallingHandlers(
    tryCatch({ source(script, local = new.env(), echo = FALSE); TRUE },
             error = function(e) {
               failures <<- c(failures, paste("error:", conditionMessage(e)))
               FALSE
             }),
    # A discrete fit that is not accepted warns on purpose, and an example may
    # be demonstrating exactly that. Other warnings are recorded and shown.
    warning = function(w) {
      message <- conditionMessage(w)
      if (!grepl("did not converge under numerical acceptance", message, fixed = TRUE))
        failures <<- c(failures, paste("warning:", message))
      invokeRestart("muffleWarning")
    })
  if (!isTRUE(result) || length(failures))
    stop("Installed example ", name, " did not run cleanly:\n",
         paste0("  - ", failures, collapse = "\n"))
}

cat("PASS:", length(scripts), "installed example script(s) ran cleanly.\n")
