# The analytic gradient of the first-order Laplace objective at a fixed point.
#
# The sparse engine evaluates L(theta) = f(u*, theta) + log det H(u*, theta) / 2
# with f(u, theta) = loss(eta, theta) + u'u / 2, eta = b(theta) + W(theta) u,
# response score g and curvature C, H = I + W' C W, and u* the conditional
# mode. For a stored coordinate theta_j, with u*_j = -H^{-1} f_{u theta_j} from
# the implicit function theorem,
#
#   L_j = f_{theta_j} + tr(H^{-1} H_{theta_j}) / 2 - a' f_{u theta_j},
#   a = H^{-1} z,  z_k = tr(H^{-1} H_{u_k}) / 2.
#
# The term in a is the dependence of the log determinant on the mode; without
# it the gradient is wrong by a first-order amount, which the negative-control
# tests measure. Per observation only the block Q_i = W_i H^{-1} W_i' is needed:
# with v_i = sum_ab Q_i[a, b] dC_i[a, b] / d eta_i / 2 (binary and ordinal rows:
# Q_i[d, d] times the loss's third derivative, halved; nominal rows:
# C_i (diag Q_i - 2 Q_i p_i) / 2), z = W' v, t = W a and r_i = g_i + v_i - C_i t_i,
#
#   intercept of dimension d:            sum_i r_i[d]
#   ordinal threshold coordinate:        sum_i { loss_theta - t_i[d] score_theta + Q_i[d, d] curvature_theta / 2 }
#   factor entry L_s[a, b], coordinate k: sum_i { r_i[a] u[k] - g_i[a] a[k] + (C_i W_i S_i)[a, k] }
#
# where k is the observation's random coordinate of source s and dimension b
# and S_i is the block of H^{-1} at the observation's coordinates. The
# selected entries come from the compiled selected inverse on the structural
# envelope's factor (R/discrete_sparse_envelope.R), the local contractions from
# R/selected_inverse.R, and the third derivatives from
# .gt_d_response_third(). Log-Cholesky diagonals, direct variances and
# exchangeable variances follow by the chain rule off zero; at an exact zero
# the square-root maps have one-sided derivatives and the evaluation is
# refused. Gradients are returned in stored coordinates; optim() applies its
# own scaling.
#
# Nothing here evaluates the objective differently, forms a mode differently
# or decides acceptance. Every refusal names its reason; a zero gradient never
# stands in for a failed gradient. A fit calls this only when the discrete
# control requests gradient = "analytic", through .gt_d_gradient_route() below.

# The fit's prologue, for fixed-point tools and tests: the same preparation,
# grouping, covariance setup and declared domain as .gt_fit_discrete(), without
# the fit's resource guards and rank checks, with the sparse context and the
# structural envelope added. The fit itself is unchanged.
.gt_d_laplace_problem <- function(data, outcomes, design, families, covariance = "unstructured",
                                  control = list()) {
  control <- .gt_d_control(control)
  prep <- .gt_d_prepare(data, outcomes, families)
  groups <- lapply(design$term_members, function(members) .gt_d_group(data, members))
  setup <- .gt_d_covariance_setup(groups, prep$q, covariance, control, prep$dimensions, prep$blocks)
  domain <- .gt_d_parameter_domain(prep, setup, control)
  context <- .gt_d_sparse_context(groups, prep$n, prep$q)
  list(prep = domain$prep, setup = domain$setup, groups = groups, control = control,
       start = domain$start, lower = domain$lower, upper = domain$upper,
       context = context, envelope = .gt_d_sparse_envelope(context))
}

# The response curvature blocks as the n-by-q-by-q array the local contractions
# take, with the same clipping the Hessian assembly applies.
.gt_d_curvature_array <- function(response, prep) {
  C <- array(0, c(prep$n, prep$q, prep$q))
  for (j in seq_along(prep$blocks)) {
    curvature <- response$curvature[[j]]
    d <- curvature$dims
    if (!is.null(curvature$diagonal)) {
      C[, d, d] <- pmax(0, curvature$diagonal)
    } else {
      p <- curvature$probability
      for (a in seq_along(d)) for (b in seq_along(d))
        C[, d[a], d[b]] <- if (a == b) .gt_d_nominal_diagonal(curvature, a) else -p[, a] * p[, b]
    }
  }
  C
}

# C_i w_i for a nominal block, with the Hessian's stable diagonal.
.gt_d_nominal_multiply <- function(curvature, w) {
  p <- curvature$probability
  out <- matrix(0, nrow(p), ncol(p), dimnames = dimnames(p))
  # Form the diagonal and off-diagonal terms separately. Subtracting the
  # weighted mean from w first can erase off-diagonal contributions when a
  # probability rounds to one; repairing the diagonal afterward cannot
  # recover those lost terms.
  for (a in seq_len(ncol(p))) {
    out[, a] <- .gt_d_nominal_diagonal(curvature, a) * w[, a]
    for (b in seq_len(ncol(p))) if (b != a)
      out[, a] <- out[, a] - (p[, a] * p[, b]) * w[, b]
  }
  out
}

.gt_d_gradient <- function(parameters, prep, groups, setup, control, context, envelope,
                           record = NULL, evaluator = NULL,
                           parts = c("explicit", "log_determinant", "implicit")) {
  started <- proc.time()[["elapsed"]]
  timings <- list()
  mark <- function(name) timings[[name]] <<- proc.time()[["elapsed"]] - started
  refusal <- function(reason, detail = NULL)
    list(valid = FALSE, reason = reason, detail = detail, timings = timings)
  # `parts` exists for the negative controls: the two corrections, the
  # log-determinant term and the implicit-mode term, can each be dropped to
  # show that the gradient is wrong without it. The explicit term is the
  # gradient's base and is always computed, so a selection without it is
  # refused rather than silently answered with it.
  if (!is.character(parts) || !all(parts %in% c("explicit", "log_determinant", "implicit")))
    .gt_d_stop("parts must name a subset of explicit, log_determinant and implicit.")
  if (!"explicit" %in% parts)
    .gt_d_stop("parts must include explicit; only the log_determinant and implicit corrections can be omitted.")
  with_log_determinant <- "log_determinant" %in% parts
  with_implicit <- "implicit" %in% parts
  if (is.null(record)) {
    if (is.null(evaluator)) evaluator <- .gt_d_sparse_evaluator()
    record <- evaluator(parameters, prep, groups, setup, control, details = TRUE)
  }
  if (!.gt_d_evaluation_usable(record))
    return(refusal("invalid_evaluation", "the conditional mode at these parameters is not usable"))
  n <- prep$n
  q <- prep$q
  fixed_length <- length(prep$start)
  factors <- record$factors
  if (is.null(factors)) factors <- .gt_d_covariance_factors(parameters[-seq_len(fixed_length)], setup)
  backend <- .gt_d_sparse_backend_from(context, factors)
  W <- backend$W
  u <- record$mode
  eta <- record$eta
  response <- .gt_d_response_kernel(eta, parameters, prep)
  if (!isTRUE(response$valid)) return(refusal("invalid_response", "the response kernel is invalid at the mode"))
  third <- .gt_d_response_third(eta, parameters, prep, response)
  if (!isTRUE(third$valid))
    return(refusal(third$reason, paste("third derivatives unavailable for block", third$block)))
  mark("response")
  H <- .gt_d_sparse_hessian(response$curvature, W, n)
  production <- tryCatch(.gt_d_sparse_factor(H, counts = FALSE), error = function(e) NULL)
  if (is.null(production))
    return(refusal("hessian_not_positive_definite", "the conditional Hessian has no Cholesky factor"))
  probes <- .gt_d_sparse_final_factor_check(H, production)
  if (!isTRUE(probes$valid))
    return(refusal("production_factor_invalid", "the production factor does not solve its own probes"))
  mark("hessian")
  overlay <- .gt_d_sparse_envelope_factor(H, envelope, production)
  if (!isTRUE(overlay$valid)) return(refusal(overlay$reason, overlay$detail))
  mark("envelope")
  selected <- tryCatch(.gt_selected_inverse(overlay$factorization), error = identity)
  if (inherits(selected, "error"))
    return(refusal(if (grepl("cap", conditionMessage(selected), fixed = TRUE)) "cap_exceeded" else
                     "selected_inverse_unavailable", conditionMessage(selected)))
  mark("selected_inverse")
  index <- .gt_selected_local_index(context)
  design <- .gt_selected_local_design(factors, q)
  C <- .gt_d_curvature_array(response, prep)
  contraction <- tryCatch(.gt_selected_contractions(selected, index, design, C), error = identity)
  if (inherits(contraction, "error"))
    return(refusal(if (grepl("structural pattern", conditionMessage(contraction), fixed = TRUE))
                     "missing_envelope_support" else if (grepl("cap", conditionMessage(contraction), fixed = TRUE))
                     "cap_exceeded" else "contraction_unavailable", conditionMessage(contraction)))
  Q <- contraction$Q
  mark("contractions")
  g <- matrix(response$gradient, n, q)
  # v: half the contraction of each observation's local inverse block with the
  # derivative of its curvature in its own linear predictor.
  v <- matrix(0, n, q)
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    d <- b$dims
    if (b$family == "categorical") {
      curvature <- response$curvature[[j]]
      m <- length(d)
      Qd <- Q[, d, d, drop = FALSE]
      diagonal <- matrix(0, n, m)
      Qp <- matrix(0, n, m)
      for (a in seq_len(m)) {
        diagonal[, a] <- Qd[, a, a]
        Qp[, a] <- rowSums(matrix(Qd[, a, ], n, m) * curvature$probability)
      }
      v[, d] <- 0.5 * .gt_d_nominal_multiply(curvature, diagonal - 2 * Qp)
    } else {
      v[, d] <- 0.5 * Q[, d, d] * third$blocks[[j]]$third
    }
  }
  if (!with_log_determinant) v[] <- 0
  # The adjoint: the mode's dependence on the parameters, through one solve
  # against the production factor, checked as every solve is.
  a <- numeric(ncol(W))
  if (with_implicit) {
    z <- as.numeric(Matrix::crossprod(W, as.vector(v)))
    a <- .gt_d_sparse_solve(production, z)
    adjoint <- .gt_d_solve_check(H, z, a)
    if (!isTRUE(adjoint$valid))
      return(refusal("adjoint_solve_invalid", "the adjoint solve fails the backward-error invariant"))
  }
  t <- matrix(as.numeric(W %*% a), n, q)
  Ct <- matrix(0, n, q)
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    d <- b$dims
    Ct[, d] <- if (b$family == "categorical") .gt_d_nominal_multiply(response$curvature[[j]], t[, d, drop = FALSE]) else
      C[, d, d] * t[, d]
  }
  r <- g + v - Ct
  mark("adjoint")
  gradient <- numeric(length(parameters))
  names(gradient) <- names(parameters)
  for (j in seq_along(prep$blocks)) {
    b <- prep$blocks[[j]]
    if (b$family == "ordinal") {
      d <- b$dims
      th <- third$blocks[[j]]
      for (k in seq_along(b$parameters))
        gradient[[b$parameters[[k]]]] <- sum(th$loss_theta[, k]) +
          (if (with_log_determinant) sum(0.5 * Q[, d, d] * th$curvature_theta[, k]) else 0) -
          (if (with_implicit) sum(t[, d] * th$score_theta[, k]) else 0)
    } else {
      for (k in seq_along(b$parameters)) gradient[[b$parameters[[k]]]] <- sum(r[, b$dims[[k]]])
    }
  }
  if (is.null(setup$fixed)) {
    width <- ncol(index)
    U <- matrix(u[index], n, width)
    A <- matrix(a[index], n, width)
    # d L / d L_s[a, b] for every source and factor position, columns ordered
    # by source then dimension as the local index is.
    factor_gradient <- crossprod(r, U) - crossprod(g, A) +
      (if (with_log_determinant) contraction$factor_trace else 0)
    offset <- fixed_length
    for (s in seq_along(setup$sources)) {
      block <- factor_gradient[, (s - 1L) * q + seq_len(q), drop = FALSE]
      L <- factors[[s]]
      for (k in seq_len(setup$per)) {
        at <- offset + (s - 1L) * setup$per + k
        if (identical(setup$parameterization, "exchangeable")) {
          shape <- setup$blocks[[k]]
          root_scale <- L[shape$dims[[1L]], shape$dims[[1L]]] / shape$root[1L, 1L]
          if (root_scale == 0)
            return(refusal("unsupported_coordinate_at_zero", names(parameters)[[at]]))
          gradient[[at]] <- sum(block[shape$dims, shape$dims] * shape$root) / (2 * root_scale)
        } else {
          position <- setup$positions[k, ]
          value <- block[position[[1L]], position[[2L]]]
          if (identical(setup$parameterization, "variance")) {
            if (L[position[[1L]], position[[2L]]] == 0)
              return(refusal("unsupported_coordinate_at_zero", names(parameters)[[at]]))
            value <- value / (2 * L[position[[1L]], position[[2L]]])
          } else if (identical(setup$parameterization, "log_cholesky") && setup$diagpos[[k]]) {
            value <- value * L[position[[1L]], position[[2L]]]
          }
          gradient[[at]] <- value
        }
      }
    }
  }
  mark("assembly")
  if (any(!is.finite(gradient)))
    return(refusal("nonfinite_gradient", "a gradient coordinate is not finite"))
  list(valid = TRUE, gradient = gradient, parts = parts,
       objective = record$nll,
       envelope = list(stored_entries = overlay$stored_entries, factor_entries = overlay$factor_entries,
                       hessian_entries = overlay$hessian_entries,
                       log_determinant_difference = overlay$log_determinant_difference),
       selected_inverse = list(factor_entries = selected$factor_entries, inner_products = selected$inner_products,
                               value_bytes = selected$value_bytes, platform = selected$platform),
       contractions = list(local_queries_upper_bound = contraction$local_queries_upper_bound,
                           scratch_bytes = contraction$scratch_bytes),
       regimes = lapply(third$blocks, function(block) if (is.null(block$regime)) NULL else table(block$regime)),
       timings = timings)
}

# Whether a design is within the compiled selected inverse's declared caps, as
# far as they can be read before a fit: the random dimension, the number of
# observations, the latent dimension, the local width of an observation (one
# coordinate per source and latent dimension), the contraction work, and the
# fill of the envelope factor when its count is known. The recurrence and
# query caps depend on the factor's column structure and are checked by the
# compiled routines at the first gradient, whose refusal ends that attempt.
.gt_d_gradient_feasibility <- function(sources, n, q, random_dimension, factor_entries = NA_real_) {
  caps <- tryCatch(.gt_selected_caps(), error = function(e) NULL)
  if (is.null(caps))
    return(list(passed = FALSE, measurements = NULL,
      detail = "The compiled selected-inverse routines are not available in this session."))
  width <- as.double(sources) * q
  measured <- c(dimension = random_dimension, observations = n, latent = q, local_width = width,
                contraction_work = as.double(n) * width^2, fill = factor_entries)
  limits <- caps[names(measured)]
  over <- names(measured)[is.finite(measured) & measured > limits]
  list(passed = !length(over), caps = caps,
       measurements = measured,
       detail = if (length(over)) paste0("Exceeds the selected inverse's declared ",
         paste(over, collapse = ", "), " cap", if (length(over) > 1L) "s" else "", ".") else
         if (is.finite(factor_entries)) "Within the selected inverse's declared caps; recurrence and query caps are checked at the first gradient." else
         "Within the declared dimension, observation, latent, width and contraction caps; fill, recurrence and query caps are checked when the envelope is built and at the first gradient.")
}

# The analytic route inside a fit's L-BFGS-B attempts.
#
# R's L-BFGS-B asks for the objective and then the gradient at the same point,
# so the gradient reuses the detailed record of that evaluation rather than
# solving for the mode again. The record is retained by the attempt objective,
# keyed by the parameters and the phase whose settings it ran under (coarse or
# tight; the geometry and the absence of a factor override are fixed within a
# fit), replaced by every later attempt evaluation, and cleared at the start of
# every attempt. A gradient request at a point without its record evaluates the
# objective there first, as a counted evaluation of the attempt.
#
# At a point whose objective evaluation was not usable the objective has
# already returned the sentinel value that makes the line search reject the
# point, and the gradient returned there is zero. That point can never be
# selected or accepted; the finite-difference route's probes around it are
# themselves unusable and give the same zero. It is counted.
#
# At a usable point a refused gradient ends the attempt: the callback raises
# an error naming the refusal, the optimizer stops, and the attempt record
# keeps the message. There is no finite-difference fallback inside an
# attempt, so an attempt's path is the analytic route's or it is a recorded
# failure. Refusals are counted and the first `limit` are retained with their
# parameters, phase and reason.
.gt_d_gradient_route <- function(prep, groups, setup, context, envelope, parameter_names,
                                 envelope_seconds = NA_real_, limit = 8L) {
  state <- new.env(parent = emptyenv())
  state$key <- NULL
  state$record <- NULL
  state$count <- 0L
  state$refusals <- 0L
  state$unusable <- 0L
  state$evaluated_first <- 0L
  state$retained <- list()
  state$seconds <- 0
  state$max_seconds <- 0
  state$stage_seconds <- numeric()
  state$structure <- NULL
  retain <- function(parameters, value, phase) {
    state$key <- list(parameters = as.numeric(parameters), phase = phase)
    state$record <- value
    value
  }
  clear <- function() {
    state$key <- NULL
    state$record <- NULL
    invisible(NULL)
  }
  account <- function(answer) {
    marks <- unlist(answer$timings)
    if (length(marks)) {
      steps <- diff(c(0, marks))
      for (stage in names(steps)) state$stage_seconds[[stage]] <-
        (if (is.na(state$stage_seconds[stage])) 0 else state$stage_seconds[[stage]]) + steps[[stage]]
      total <- marks[[length(marks)]]
      state$seconds <- state$seconds + total
      state$max_seconds <- max(state$max_seconds, total)
    }
  }
  at <- function(parameters, record, settings)
    .gt_d_gradient(stats::setNames(as.numeric(parameters), parameter_names), prep, groups, setup,
                   settings, context, envelope, record = record)
  callback <- function(phase, evaluate, settings) {
    force(phase); force(evaluate); force(settings)
    function(p) {
      p <- stats::setNames(as.numeric(p), parameter_names)
      key <- state$key
      if (is.null(key) || !identical(key$phase, phase) || !identical(key$parameters, unname(p))) {
        state$evaluated_first <- state$evaluated_first + 1L
        evaluate(p)
        key <- state$key
        if (is.null(key) || !identical(key$phase, phase) || !identical(key$parameters, unname(p)))
          .gt_d_stop("The attempt objective did not retain its evaluation for the analytic gradient.")
      }
      record <- state$record
      if (!.gt_d_evaluation_usable(record)) {
        state$unusable <- state$unusable + 1L
        return(numeric(length(p)))
      }
      answer <- .gt_d_gradient(p, prep, groups, setup, settings, context, envelope, record = record)
      state$count <- state$count + 1L
      account(answer)
      if (!isTRUE(answer$valid)) {
        state$refusals <- state$refusals + 1L
        if (length(state$retained) < limit)
          state$retained[[length(state$retained) + 1L]] <- list(gradient = state$count,
            phase = phase, reason = answer$reason, detail = answer$detail, parameters = p)
        stop(sprintf("Analytic gradient refused at gradient %d (%s)%s", state$count, answer$reason,
                     if (length(answer$detail) && nzchar(answer$detail[[1L]]))
                       paste0(": ", answer$detail[[1L]]) else ""), call. = FALSE)
      }
      if (is.null(state$structure))
        state$structure <- list(envelope = answer$envelope, selected_inverse = answer$selected_inverse,
                                contractions = answer$contractions)
      unname(answer$gradient)
    }
  }
  summary <- function() list(route = "analytic",
    gradient_evaluations = state$count, refusals = state$refusals,
    unusable_objective_points = state$unusable,
    evaluated_before_gradient = state$evaluated_first,
    retained_refusals = state$retained, retention_limit = limit,
    seconds_total = state$seconds, seconds_max = state$max_seconds,
    seconds_by_stage = state$stage_seconds, envelope_seconds = envelope_seconds,
    envelope = list(random_dimension = envelope$dimension, hessian_entries = envelope$hessian_entries,
                    factor_entries = envelope$factor_entries),
    selected_inverse = state$structure$selected_inverse[c("factor_entries", "inner_products", "value_bytes")],
    contractions = state$structure$contractions,
    platform = .gt_selected_platform(),
    scope = paste("Gradients requested by the L-BFGS-B attempts. The stationarity check and the",
                  "restart comparison keep their own finite differences; observed information, when",
                  "requested, differences this route's gradient and records its own count. A refused",
                  "gradient ended its attempt, and a gradient at an unusable objective point was zero",
                  "beside the sentinel value the objective returned."))
  list(retain = retain, clear = clear, callback = callback, at = at, summary = summary,
       context = context, envelope = envelope)
}
