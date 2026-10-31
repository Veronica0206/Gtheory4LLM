list(formula = cbind(stress, anxiety_depression, bipolar_personality_suicidal) ~ 
    item * evaluator * prompt + evaluator:prompt:temp + evaluator:prompt:temp:seed + 
        item:evaluator:prompt:temp, measured = "item", covariance = "unstructured", 
    family = list(stress = structure(list(family = "binary", 
        link = "probit", levels = NULL, reference = NULL, ordered = FALSE), class = "gt_family"), 
        anxiety_depression = structure(list(family = "binary", 
            link = "probit", levels = NULL, reference = NULL, 
            ordered = FALSE), class = "gt_family"), bipolar_personality_suicidal = structure(list(
            family = "binary", link = "probit", levels = NULL, 
            reference = NULL, ordered = FALSE), class = "gt_family")), 
    control = structure(list(gaussian = list(), discrete = list(
        engine = "sparse", covariance_parameterization = "cholesky", 
        optimizer = "L-BFGS-B", optimizer_scaling = "start", 
        max_observations = 21600L, max_random_dimension = 60000L, 
        max_parameters = 240L, max_sparse_bytes = 8589934592, 
        max_dense_bytes = 536870912, maxit = 2000L, check_hessian = TRUE, 
        trace = 1L, boundary_escape = "projected", gradient = "analytic", 
        hessian_step = 0.001, hessian_tolerance = 0.05, inner_maxit = 60L, 
        inner_tol = 1e-07, reltol = 1e-07, start_sd = 0.4, fixed_covariance = NULL, 
        stationarity_tol = 0.001, validation_reltol = 1e-10, 
        validation_inner_tol = 1e-09, alternative_starts = 1L, 
        stability_objective_tol = 1e-06, stability_parameter_tol = 0.02, 
        bound_tol = 1e-04, start = NULL), retain = c(data = TRUE, 
    model = TRUE, retry_log = TRUE, session = TRUE)), class = "gt_control"), 
    single_counts = c(evaluator = 1L, prompt = 1L, temp = 1L, 
    seed = 1L), dstudy_allocations = structure(list(evaluator = c(1L, 
    4L), prompt = c(1L, 3L), temp = c(1L, 6L), seed = c(1L, 3L
    )), class = "data.frame", row.names = c(NA, -2L)), scope = "Complete 21,600-row native panel; ten random sources; 3 outcomes; unstructured source covariance; probit links; automatic starts.")
