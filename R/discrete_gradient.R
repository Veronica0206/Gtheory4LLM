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
# stands in for a failure. No fit calls this yet.

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
  out <- p * w - p * rowSums(p * w)
  for (a in seq_len(ncol(p)))
    out[, a] <- out[, a] + (.gt_d_nominal_diagonal(curvature, a) - (p[, a] - p[, a]^2)) * w[, a]
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
  if (!is.character(parts) || !all(parts %in% c("explicit", "log_determinant", "implicit")))
    .gt_d_stop("parts must name a subset of explicit, log_determinant and implicit.")
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
