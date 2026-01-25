#' Predict method for meanvarfit
#'
#' @param object A meanvarfit object.
#' @param X_new New covariates.
#' @param type Output type.
#' @param ... Unused.
#'
#' @return A vector or list of predictions.
#' @export
predict.meanvarfit <- function(object, X_new, type = c("mu", "sigma2", "weights", "all"), ...) {
  type <- match.arg(type)

  if (!inherits(object, "meanvarfit")) {
    stop("object must be of class 'meanvarfit'.")
  }
  if (is.null(object$fits)) {
    stop("This meanvarfit object does not contain fitted models.")
  }

  fits <- object$fits
  var_floor <- object$control$var_floor

  if (object$p == 1) {
    if (is.numeric(X_new) && is.vector(X_new)) {
      x_new <- as.numeric(X_new)
    } else if (is.matrix(X_new) && ncol(X_new) == 1) {
      x_new <- as.numeric(X_new[, 1])
    } else if (is.data.frame(X_new) && ncol(X_new) == 1) {
      x_new <- as.numeric(X_new[[1]])
    } else {
      stop("X_new must be a numeric vector or single-column data for 1-D models.")
    }

    mu_hat_new <- as.numeric(stats::predict(
      fits$mean_fit,
      newdata = data.frame(x = x_new),
      type = "response"
    ))

    sigma2_hat_new <- as.numeric(stats::predict(
      fits$var_fit,
      newdata = data.frame(x = x_new),
      type = "response"
    ))
    sigma2_hat_new <- pmax(sigma2_hat_new, var_floor)

  } else {
    if (is.numeric(X_new) && is.vector(X_new)) {
      stop("X_new must be a matrix or data.frame for high-D models.")
    }
    if (is.matrix(X_new)) {
      if (!is.numeric(X_new)) {
        stop("X_new matrix must be numeric.")
      }
      X_df <- as.data.frame(X_new)
      if (is.null(names(X_df))) {
        names(X_df) <- paste0("x", seq_len(ncol(X_df)))
      }
    } else if (is.data.frame(X_new)) {
      numeric_cols <- vapply(X_new, is.numeric, logical(1))
      if (!all(numeric_cols)) {
        stop("All columns of X_new data.frame must be numeric.")
      }
      X_df <- X_new
      if (is.null(names(X_df))) {
        names(X_df) <- paste0("x", seq_len(ncol(X_df)))
      }
    } else {
      stop("X_new must be a matrix or data.frame for high-D models.")
    }

    if (object$mean_backend == "gam_additive") {
      mu_hat_new <- as.numeric(stats::predict(
        fits$mean_fit,
        newdata = X_df,
        type = "response"
      ))
    } else if (object$mean_backend == "ranger") {
      mu_hat_new <- as.numeric(stats::predict(fits$mean_fit, data = X_df)$predictions)
    } else {
      stop("Unknown mean_backend in object.")
    }

    r2_hat_new <- NULL
    if (object$var_backend %in% c("rf_smooth", "rf_only")) {
      r2_hat_new <- as.numeric(stats::predict(fits$detector_fit, data = X_df)$predictions)
    }

    if (object$projection$type == "none") {
      sigma2_hat_new <- pmax(r2_hat_new, var_floor)
    } else {
      t_new <- .predict_projection(object$projection, X_df, mu_hat_new, r2_hat_new)
      log_sigma2 <- as.numeric(stats::predict(
        fits$var_fit,
        newdata = data.frame(t = t_new),
        type = "response"
      ))
      sigma2_hat_new <- pmax(exp(log_sigma2), var_floor)
    }
  }

  if (type == "mu") {
    return(mu_hat_new)
  }
  if (type == "sigma2") {
    return(sigma2_hat_new)
  }
  if (type == "weights") {
    return(1 / sigma2_hat_new)
  }

  list(mu = mu_hat_new, sigma2 = sigma2_hat_new, weights = 1 / sigma2_hat_new)
}
