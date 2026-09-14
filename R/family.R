# Documentation policy: man/*.Rd and NAMESPACE are hand written and are
# the only source of truth. These comments describe the code for readers;
# they are deliberately not roxygen, so running roxygen2 cannot replace the
# richer Rd pages or drop the S3 methods registered in NAMESPACE.
# Explicitly distinct Gaussian, binary, ordinal, and unordered categorical families.

# Define the observation distribution for a G-theory outcome
# family: gaussian, binary, ordinal, or categorical (unordered, >=3 levels).
# link: identity for Gaussian; probit or logit for binary/ordinal;
#   softmax for unordered categorical responses.
# levels: Category labels. Binary levels are negative then positive;
#   ordinal levels specify their substantive order; categorical levels only
#   identify categories, without ordering them.
# reference: Reference category for categorical models only.
gt_family <- function(family = "gaussian", link = NULL, levels = NULL,
                      reference = NULL) {
  choices <- c("gaussian", "binary", "ordinal", "categorical")
  if (!is.character(family) || length(family) != 1L || is.na(family) ||
      !family %in% choices) stop("family must be gaussian, binary, ordinal, or categorical.", call. = FALSE)
  links <- switch(family, gaussian = "identity", binary = c("probit", "logit"),
                  ordinal = c("probit", "logit"), categorical = "softmax")
  if (is.null(link)) link <- links[1L]
  if (!is.character(link) || length(link) != 1L || is.na(link) || !link %in% links)
    stop("Unsupported link for ", family, "; use ", paste(links, collapse = " or "), ".", call. = FALSE)
  if (!is.null(levels)) {
    if (!is.atomic(levels) || anyNA(levels)) stop("levels must contain distinct nonmissing category labels.", call. = FALSE)
    levels <- as.character(levels)
    if (any(!nzchar(levels)) || anyDuplicated(levels))
      stop("levels must contain distinct nonempty category labels.", call. = FALSE)
    if (family == "gaussian") stop("Gaussian outcomes do not have category levels.", call. = FALSE)
    if (family == "binary" && length(levels) != 2L) stop("Binary outcomes require two levels.", call. = FALSE)
    if (family %in% c("ordinal", "categorical") && length(levels) < 3L)
      stop("Use binary for two categories; ordinal/categorical here require at least three levels.", call. = FALSE)
  }
  if (!is.null(reference)) {
    if (family != "categorical") stop("reference applies only to unordered categorical outcomes.", call. = FALSE)
    if (length(reference) != 1L || is.na(reference)) stop("reference must name one category.", call. = FALSE)
    reference <- as.character(reference)
    if (!is.null(levels) && !reference %in% levels) stop("reference must be in levels.", call. = FALSE)
  }
  structure(list(family = family, link = link, levels = levels,
                 reference = reference, ordered = family == "ordinal"), class = "gt_family")
}

.gt_resolve_families <- function(data, outcomes, family) {
  if (inherits(family, "gt_family")) {
    families <- stats::setNames(rep(list(family), length(outcomes)), outcomes)
  } else {
    if (!is.list(family) || is.null(names(family)) || anyDuplicated(names(family)) ||
        !setequal(names(family), outcomes) ||
        !all(vapply(family, inherits, logical(1), what = "gt_family")))
      stop("family must be a gt_family object or a named family list matching outcomes exactly.", call. = FALSE)
    families <- family[outcomes]
  }
  encoded <- data
  for (outcome in outcomes) {
    spec <- families[[outcome]]
    x <- data[[outcome]]
    if (!is.atomic(x) || anyNA(x)) stop("Outcome ", outcome, " contains missing or unsupported values.", call. = FALSE)
    if (spec$family == "gaussian") {
      if (!is.numeric(x) || any(!is.finite(x)) || length(unique(x)) < 2L)
        stop("Gaussian outcome ", outcome, " must be finite, numeric, and nonconstant; categories are never silently converted.", call. = FALSE)
      next
    }
    labels <- as.character(x)
    if (spec$family == "binary" && (is.numeric(x) || is.logical(x))) {
      if (any(!is.finite(x)) || !all(x %in% c(0, 1))) stop("Numeric binary outcomes must be 0/1.", call. = FALSE)
      labels <- as.character(as.integer(x))
      if (is.null(spec$levels)) spec$levels <- c("0", "1")
      if (!identical(spec$levels, c("0", "1")))
        stop("Numeric/logical binary input uses levels c('0','1'); convert to labeled factor for other category labels.", call. = FALSE)
    }
    if (is.null(spec$levels)) {
      if (spec$family == "ordinal" && !is.ordered(x))
        stop("Ordinal outcome ", outcome, " needs explicit ordered levels or an ordered factor.", call. = FALSE)
      if (!is.factor(x)) stop("Declare levels explicitly or supply a factor for outcome ", outcome, ".", call. = FALSE)
      spec$levels <- levels(x)
    }
    spec <- gt_family(spec$family, spec$link, spec$levels, spec$reference)
    if (any(!labels %in% spec$levels)) stop("Undeclared categories in ", outcome, ".", call. = FALSE)
    if (!setequal(unique(labels), spec$levels))
      stop("Every declared category must occur in ", outcome, "; absent categories are not estimable in this initial implementation.", call. = FALSE)
    if (spec$family == "binary") {
      encoded[[outcome]] <- match(labels, spec$levels) - 1L
    } else if (spec$family == "ordinal") {
      encoded[[outcome]] <- ordered(labels, levels = spec$levels)
    } else {
      if (is.null(spec$reference)) spec$reference <- spec$levels[1L]
      encoded[[outcome]] <- factor(labels, levels = spec$levels)
    }
    families[[outcome]] <- spec
  }
  list(data = encoded, families = families)
}

# Retained fit components. Every default is TRUE, so a fit keeps exactly what it
# kept before these controls existed; a caller who does not want a component
# must say so. The names describe what is dropped, not what is recomputed:
# nothing here changes an estimate, a diagnostic decision, or a coefficient.
.gt_retention_defaults <- c(data = TRUE, model = TRUE, retry_log = TRUE, session = TRUE)

.gt_validate_retention <- function(retain) {
  if (!is.list(retain) && !is.logical(retain))
    stop("retain must be a named list or logical vector of retention switches.", call. = FALSE)
  if (length(retain) && (is.null(names(retain)) || anyNA(names(retain)) ||
      any(!nzchar(names(retain))) || anyDuplicated(names(retain))))
    stop("retain must be uniquely named.", call. = FALSE)
  unknown <- setdiff(names(retain), names(.gt_retention_defaults))
  if (length(unknown))
    stop("Unsupported retention setting(s): ", paste(unknown, collapse = ", "),
         ". Supported: ", paste(names(.gt_retention_defaults), collapse = ", "), ".", call. = FALSE)
  values <- .gt_retention_defaults
  for (name in names(retain)) {
    value <- retain[[name]]
    if (!is.logical(value) || length(value) != 1L || is.na(value))
      stop("Retention setting ", name, " must be TRUE or FALSE.", call. = FALSE)
    values[[name]] <- value
  }
  values
}

# Separate controls for exact Gaussian and approximate discrete fitting
# retain: which optional fit components to keep. See gt_control() documentation.
gt_control <- function(gaussian = list(), discrete = list(), retain = list()) {
  for (x in list(gaussian, discrete)) {
    if (!is.list(x) || (length(x) && (is.null(names(x)) || anyNA(names(x)) ||
        any(!nzchar(names(x))) || anyDuplicated(names(x)))))
      stop("Each engine control must be a uniquely named list.", call. = FALSE)
  }
  structure(list(gaussian = gaussian, discrete = discrete,
                 retain = .gt_validate_retention(retain)), class = "gt_control")
}
