# Run from the project directory with Rscript tests/test_discrete_reference.R.
#
# The frozen fixed-parameter targets in validation-studies/discrete-sparse-reference
# must still hold. Tolerances are declared here as literals so that widening one
# to make something pass is a visible edit rather than a quiet argument change.
# Their derivation is in that directory's PROTOCOL.md; do not raise one to
# accommodate an implementation.
source(file.path("validation-studies", "discrete-sparse-reference", "cases.R"))

expect <- function(condition, label) if (!isTRUE(condition)) stop("FAILED: ", label)
DIRECTORY <- file.path("validation-studies", "discrete-sparse-reference")

# kind -> (relative, absolute). NA means that comparison does not apply.
TOLERANCE <- list(
  exact      = c(relative = 0,     absolute = 0),
  algebraic  = c(relative = 1e-12, absolute = 1e-14),
  objective  = c(relative = 1e-8,  absolute = 1e-10),
  # The mode is solved only to the inner tolerance, so coordinates near zero
  # need an absolute floor of the same size rather than a relative one.
  mode       = c(relative = 1e-6,  absolute = 1e-6),
  # Curvature is a smooth function of the predictor, so its error is first
  # order in the mode error rather than smaller.
  curvature  = c(relative = 1e-6,  absolute = 1e-6),
  # A quantity whose intended value is zero cannot be compared relatively: the
  # assertion is that it is small, not that it reproduces digit for digit.
  stationary = c(relative = NA,    absolute = 1e-6),
  # An algebraic identity is not a stationarity residual and must not borrow
  # its allowance. These reconstruct exactly up to rounding in the same sums
  # the objective tolerance already covers, so they are held at that same
  # absolute rounding scale rather than at the mode-gradient tolerance.
  identity   = c(relative = NA,    absolute = 1e-10))

frozen <- read.csv(file.path(DIRECTORY, "reference.csv"), stringsAsFactors = FALSE)
current <- discrete_reference_rows()

# --- Nothing may quietly disappear -------------------------------------------
expect(setequal(frozen$case, current$case), "the same cases are evaluated")
expect(nrow(current) >= nrow(frozen),
       paste0("no frozen quantity was dropped: frozen ", nrow(frozen),
              ", recomputed ", nrow(current)))
for (case in unique(frozen$case)) {
  missing <- setdiff(frozen$quantity[frozen$case == case], current$quantity[current$case == case])
  expect(!length(missing),
         paste0("case ", case, " still reports: ", paste(missing, collapse = ", ")))
}
# The demanding cases are named here so that deleting one fails rather than
# silently shrinking what the reference covers.
for (case in c("binary_logit_single_source", "binary_probit_crossed",
               "binary_logit_crossed_interior", "ordinal_logit_crossed",
               "ordinal_probit_crossed", "ordinal_logit_tail_mass",
               "binary_logit_zero_source", "binary_probit_fixed_covariance"))
  expect(case %in% frozen$case, paste("the reference still covers", case))

# --- Every frozen value still holds ------------------------------------------
key <- paste(current$case, current$quantity)
for (i in seq_len(nrow(frozen))) {
  row <- frozen[i, ]
  where <- match(paste(row$case, row$quantity), key)
  expect(!is.na(where), paste("recomputed", row$case, row$quantity))
  got <- current$value[[where]]
  limit <- TOLERANCE[[row$kind]]
  expect(!is.null(limit), paste("known tolerance kind for", row$quantity))
  label <- paste0(row$case, " ", row$quantity, ": frozen ", format(row$value, digits = 17),
                  ", recomputed ", format(got, digits = 17))
  if (identical(row$kind, "exact")) {
    expect(identical(as.numeric(got), as.numeric(row$value)), paste("exact match for", label))
    next
  }
  difference <- abs(got - row$value)
  ok <- difference <= limit[["absolute"]]
  if (!ok && !is.na(limit[["relative"]]) && row$value != 0)
    ok <- difference / abs(row$value) <= limit[["relative"]]
  expect(ok, paste0(label, " (difference ", format(difference, digits = 3), ")"))
}

# --- A stationary residual is small, not merely reproduced --------------------
# Freezing a near-zero score would otherwise let a future implementation match
# a recorded non-solution exactly and call that agreement.
for (i in which(frozen$kind %in% c("stationary", "identity"))) {
  # Each kind against its own limit. Checking both at the stationary allowance
  # would leave the tighter identity threshold declared but never applied,
  # which is the same as not declaring it.
  limit <- TOLERANCE[[frozen$kind[[i]]]][["absolute"]]
  expect(abs(frozen$value[[i]]) <= limit,
         paste0("frozen ", frozen$case[[i]], " ", frozen$quantity[[i]], " (",
                frozen$kind[[i]], ") is a solved residual within ", format(limit),
                ", not an arbitrary recorded value; got ",
                format(abs(frozen$value[[i]]), digits = 3)))
}

# --- Declared rejections still reject ----------------------------------------
# A backend that agrees on every calculation that succeeds is not qualified.
# These must keep refusing, and keep refusing in the same way: turning an error
# into a penalty, or a penalty into an answer, is a behaviour change however
# close the arithmetic is.
frozen_rejections <- read.csv(file.path(DIRECTORY, "rejections.csv"), stringsAsFactors = FALSE)
current_rejections <- discrete_reference_rejections()
expect(setequal(frozen_rejections$case, current_rejections$case),
       "the same rejection cases are exercised")
for (i in seq_len(nrow(frozen_rejections))) {
  where <- match(frozen_rejections$case[[i]], current_rejections$case)
  expect(identical(current_rejections$outcome[[where]], frozen_rejections$outcome[[i]]),
         paste0("rejection ", frozen_rejections$case[[i]], ": expected ",
                frozen_rejections$outcome[[i]], ", observed ",
                current_rejections$outcome[[where]]))
}
expect(!any(current_rejections$outcome == "value"),
       "no declared rejection returned an ordinary value")

# --- Provenance is not stale --------------------------------------------------
hashes <- read.csv(file.path(DIRECTORY, "source-hashes.csv"), stringsAsFactors = FALSE)
recorded <- hashes$md5[hashes$file == file.path(DIRECTORY, "reference.csv")]
expect(length(recorded) == 1L, "the reference file has one recorded digest")
expect(identical(recorded, reference_digest(file.path(DIRECTORY, "reference.csv"))),
       "the recorded digest describes the committed reference file")

cat("PASS: ", nrow(frozen), " frozen fixed-parameter targets reproduce across ",
    length(unique(frozen$case)), " cases; ", nrow(frozen_rejections),
    " declared rejections still reject.\n", sep = "")
