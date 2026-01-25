#' Fit mean and variance for 1-D predictors
#'
#' Convenience wrapper around `fit_mean_variance()` for one-dimensional x.
#'
#' @param y Numeric vector of length n.
#' @param x Numeric vector of length n.
#' @param ... Additional arguments passed to `fit_mean_variance()`.
#'
#' @return An object of class 'meanvarfit'.
#' @export
fit_meanvar_1d <- function(y, x, ...) {
  if (!is.numeric(x) || is.matrix(x) || is.data.frame(x)) {
    stop("x must be a numeric vector.")
  }
  if (!is.numeric(y) || is.matrix(y) || is.data.frame(y)) {
    stop("y must be a numeric vector.")
  }
  if (length(x) != length(y)) {
    stop("x must have the same length as y.")
  }

  args <- list(
    y = y,
    X = x,
    mean_backend = "gam",
    var_backend = "gamma_gam",
    projection = "none"
  )
  dots <- list(...)
  if (length(dots)) {
    args[names(dots)] <- dots
  }

  do.call(fit_mean_variance, args)
}
