#' Fit mean and variance functions
#'
#' Fits a mean model for y given X, then estimates a heteroskedastic variance
#' function by modeling squared residuals. Supports 1-D and high-dimensional
#' predictors, with optional detector + projection smoothing for variance.
#'
#' @param y Numeric vector of length n.
#' @param X Numeric vector, matrix, or data.frame with n rows.
#' @param mean_backend Character. Mean model backend.
#' @param var_backend Character. Variance backend.
#' @param detector_backend Character. Detector backend for high-D variance.
#' @param projection Character. Projection type for high-D variance smoothing.
#' @param proj_fn Optional function for custom projection.
#' @param k_mean Integer. Basis size for mean GAM smooth.
#' @param k_var Integer. Basis size for variance smoother.
#' @param eps Numeric. Small constant added inside log transforms.
#' @param var_floor Numeric. Minimum allowed variance.
#' @param seed Optional integer seed.
#' @param return_fits Logical. Whether to store fitted model objects.
#'
#' @return An object of class 'meanvarfit' containing fitted mean, variance,
#' weights, diagnostics, and optional fitted models.
#'
#' @export
fit_mean_variance <- function(
  y, X,
  mean_backend = "gam",
  var_backend = c("auto", "gamma_gam", "rf_smooth", "rf_only"),
  detector_backend = c("ranger"),
  projection = c("auto", "mean_pred", "var_pred", "pca1", "custom", "none"),
  proj_fn = NULL,
  k_mean = 40,
  k_var = 20,
  eps = 1e-8,
  var_floor = 1e-6,
  seed = NULL,
  return_fits = TRUE
) {
  call <- match.call()

  if (!is.numeric(y) || is.matrix(y) || is.data.frame(y)) {
    stop("y must be a numeric vector.")
  }
  if (anyNA(y)) {
    stop("y must not contain NA values.")
  }

  var_backend <- match.arg(var_backend)
  detector_backend <- match.arg(detector_backend)
  projection <- match.arg(projection)

  x_info <- .validate_X(X, length(y))
  x_type <- x_info$type
  n <- x_info$n
  p <- x_info$p

  if (!is.null(seed)) {
    set.seed(seed)
  }
  control <- list(eps = eps, var_floor = var_floor, k_mean = k_mean, k_var = k_var)

  if (x_type == "1d") {
    x <- x_info$x

    if (mean_backend != "gam") {
      stop("mean_backend must be 'gam' for 1-D X.")
    }

    mean_fit <- mgcv::gam(y ~ s(x, k = k_mean), method = "REML")
    mu_hat <- as.numeric(stats::predict(mean_fit, type = "response"))

    r <- y - mu_hat
    r2 <- r^2

    if (var_backend == "auto") {
      var_backend <- "gamma_gam"
    }
    if (var_backend != "gamma_gam") {
      stop("var_backend must be 'gamma_gam' for 1-D X.")
    }

    var_fit <- mgcv::gam(
      r2 ~ s(x, k = k_var),
      family = Gamma(link = "log"),
      method = "REML"
    )
    sigma2_hat <- as.numeric(stats::predict(var_fit, type = "response"))
    sigma2_hat <- pmax(sigma2_hat, var_floor)

    projection_info <- list(type = "x", t_train = x, proj_object = NULL)
    diagnostics <- .build_diagnostics(
      r = r,
      r2 = r2,
      r2_hat = NULL,
      sigma2_hat = sigma2_hat,
      index = x
    )

    fits <- NULL
    if (return_fits) {
      fits <- list(mean_fit = mean_fit, detector_fit = NULL, var_fit = var_fit)
    }

    out <- list(
      call = call,
      n = n,
      p = p,
      mean_backend = "gam",
      var_backend = var_backend,
      detector_backend = NULL,
      projection = projection_info,
      mu_hat = mu_hat,
      sigma2_hat = sigma2_hat,
      weights = 1 / sigma2_hat,
      fits = fits,
      diagnostics = diagnostics,
      control = control
    )

    class(out) <- "meanvarfit"
    return(out)
  }

  # High-dimensional path
  X_df <- x_info$X_df

  if (mean_backend == "gam") {
    mean_backend <- if (p > 10) "ranger" else "gam_additive"
  }

  if (mean_backend == "gam_additive" && p > 10) {
    stop("mean_backend 'gam_additive' is only allowed when p <= 10.")
  }

  if (mean_backend == "gam_additive") {
    form <- .build_additive_formula("y", names(X_df), k_mean)
    mean_fit <- mgcv::gam(form, data = data.frame(y = y, X_df), method = "REML")
    mu_hat <- as.numeric(stats::predict(mean_fit, newdata = X_df, type = "response"))
  } else if (mean_backend == "ranger") {
    mean_fit <- ranger::ranger(y ~ ., data = data.frame(y = y, X_df))
    mu_hat <- as.numeric(stats::predict(mean_fit, data = X_df)$predictions)
  } else {
    stop("Unknown mean_backend for high-D X.")
  }

  r <- y - mu_hat
  r2 <- r^2

  if (var_backend == "auto") {
    var_backend <- "rf_smooth"
  }

  detector_fit <- NULL
  r2_hat <- NULL
  if (var_backend %in% c("rf_smooth", "rf_only")) {
    if (detector_backend != "ranger") {
      stop("Only 'ranger' detector_backend is supported.")
    }
    detector_fit <- ranger::ranger(r2 ~ ., data = data.frame(r2 = r2, X_df))
    r2_hat <- as.numeric(stats::predict(detector_fit, data = X_df)$predictions)
  } else {
    stop("Unknown var_backend for high-D X.")
  }
  r2_hat_pos <- pmax(r2_hat, var_floor)

  if (var_backend == "rf_only") {
    projection <- "none"
  }

  if (projection == "auto") {
    projection <- "mean_pred"
  }

  projection_info <- .compute_projection(
    type = projection,
    X = X_df,
    mu_hat = mu_hat,
    r2_hat = r2_hat,
    proj_fn = proj_fn
  )

  var_fit <- NULL
  if (projection == "none") {
    sigma2_hat <- r2_hat_pos
  } else {
    df_var <- data.frame(t = projection_info$t_train, r2_hat_pos = r2_hat_pos)
    var_fit <- mgcv::gam(
      log(r2_hat_pos + eps) ~ s(t, k = k_var),
      data = df_var,
      method = "REML"
    )
    log_sigma2 <- as.numeric(stats::predict(var_fit, type = "response"))
    sigma2_hat <- pmax(exp(log_sigma2), var_floor)
  }

  diagnostics <- .build_diagnostics(
    r = r,
    r2 = r2,
    r2_hat = r2_hat,
    sigma2_hat = sigma2_hat,
    index = if (projection == "none") mu_hat else projection_info$t_train
  )

  fits <- NULL
  if (return_fits) {
    fits <- list(mean_fit = mean_fit, detector_fit = detector_fit, var_fit = var_fit)
  }

  out <- list(
    call = call,
    n = n,
    p = p,
    mean_backend = mean_backend,
    var_backend = var_backend,
    detector_backend = detector_backend,
    projection = projection_info,
    mu_hat = mu_hat,
    sigma2_hat = sigma2_hat,
    weights = 1 / sigma2_hat,
    fits = fits,
    diagnostics = diagnostics,
    control = control
  )

  class(out) <- "meanvarfit"
  out
}

.validate_X <- function(X, n) {
  if (is.numeric(X) && is.vector(X)) {
    if (length(X) != n) {
      stop("X must have length n.")
    }
    return(list(type = "1d", x = as.numeric(X), n = n, p = 1))
  }

  if (is.matrix(X)) {
    if (nrow(X) != n) {
      stop("X must have n rows.")
    }
    if (!is.numeric(X)) {
      stop("X matrix must be numeric.")
    }
    X_df <- as.data.frame(X)
    if (is.null(names(X_df))) {
      names(X_df) <- paste0("x", seq_len(ncol(X_df)))
    }
    return(list(type = "highd", X_df = X_df, n = n, p = ncol(X_df)))
  }

  if (is.data.frame(X)) {
    if (nrow(X) != n) {
      stop("X must have n rows.")
    }
    numeric_cols <- vapply(X, is.numeric, logical(1))
    if (!all(numeric_cols)) {
      stop("All columns of X data.frame must be numeric.")
    }
    X_df <- X
    if (is.null(names(X_df))) {
      names(X_df) <- paste0("x", seq_len(ncol(X_df)))
    }
    return(list(type = "highd", X_df = X_df, n = n, p = ncol(X_df)))
  }

  stop("X must be a numeric vector, matrix, or data.frame.")
}

.build_additive_formula <- function(response, predictors, k_mean) {
  k_term <- min(10, k_mean)
  smooths <- paste0("s(", predictors, ", k = ", k_term, ")")
  stats::as.formula(paste(response, "~", paste(smooths, collapse = " + ")))
}
