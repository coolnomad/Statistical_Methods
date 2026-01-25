.compute_projection <- function(type, X, mu_hat, r2_hat, proj_fn) {
  n <- length(mu_hat)

  if (type == "none") {
    return(list(type = "none", t_train = NULL, proj_object = NULL, proj_fn = NULL))
  }

  if (type == "mean_pred") {
    return(list(type = "mean_pred", t_train = mu_hat, proj_object = NULL, proj_fn = NULL))
  }

  if (type == "var_pred") {
    if (is.null(r2_hat)) {
      stop("r2_hat is required for var_pred projection.")
    }
    return(list(type = "var_pred", t_train = r2_hat, proj_object = NULL, proj_fn = NULL))
  }

  if (type == "pca1") {
    X_mat <- as.matrix(X)
    if (!is.numeric(X_mat)) {
      stop("X must be numeric for pca1 projection.")
    }
    pca <- stats::prcomp(X_mat, center = TRUE, scale. = TRUE)
    t_train <- pca$x[, 1]
    return(list(type = "pca1", t_train = as.numeric(t_train), proj_object = pca, proj_fn = NULL))
  }

  if (type == "custom") {
    if (!is.function(proj_fn)) {
      stop("proj_fn must be a function when projection = 'custom'.")
    }
    t_train <- proj_fn(X, mu_hat, r2_hat)
    if (!is.numeric(t_train) || length(t_train) != n) {
      stop("proj_fn must return a numeric vector of length n.")
    }
    return(list(type = "custom", t_train = as.numeric(t_train), proj_object = NULL, proj_fn = proj_fn))
  }

  stop("Unknown projection type.")
}

.predict_projection <- function(projection, X_new, mu_hat_new, r2_hat_new) {
  type <- projection$type

  if (type == "none") {
    return(NULL)
  }
  if (type == "mean_pred") {
    return(mu_hat_new)
  }
  if (type == "var_pred") {
    if (is.null(r2_hat_new)) {
      stop("r2_hat_new is required for var_pred projection.")
    }
    return(r2_hat_new)
  }
  if (type == "pca1") {
    pca <- projection$proj_object
    if (is.null(pca)) {
      stop("Missing PCA object for projection.")
    }
    scores <- stats::predict(pca, newdata = as.matrix(X_new))
    return(as.numeric(scores[, 1]))
  }
  if (type == "custom") {
    proj_fn <- projection$proj_fn
    if (!is.function(proj_fn)) {
      stop("Missing proj_fn for custom projection.")
    }
    t_new <- proj_fn(X_new, mu_hat_new, r2_hat_new)
    if (!is.numeric(t_new) || length(t_new) != length(mu_hat_new)) {
      stop("proj_fn must return numeric vector of length n.")
    }
    return(as.numeric(t_new))
  }

  stop("Unknown projection type.")
}
