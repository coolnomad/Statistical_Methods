#' Plot method for meanvarfit
#'
#' @param x A meanvarfit object.
#' @param which Plot type.
#' @param ... Passed to base plotting functions.
#'
#' @export
plot.meanvarfit <- function(x, which = c("variance_curve", "std_resid", "r2_vs_index"), ...) {
  which <- match.arg(which)

  if (!inherits(x, "meanvarfit")) {
    stop("x must be of class 'meanvarfit'.")
  }

  diag <- x$diagnostics
  plot_df <- diag$plot_df
  index <- plot_df$index

  if (which == "variance_curve") {
    y_scatter <- if (!is.null(plot_df$r2_hat)) plot_df$r2_hat else plot_df$r2
    graphics::plot(index, y_scatter, pch = 16, col = "gray40",
                   xlab = "Index", ylab = "r2", main = "Variance curve", ...)
    ord <- order(index)
    graphics::lines(index[ord], plot_df$sigma2_hat[ord], col = "blue", lwd = 2)
    return(invisible(NULL))
  }

  if (which == "std_resid") {
    graphics::plot(index, plot_df$std_resid, pch = 16, col = "gray40",
                   xlab = "Index", ylab = "Std. residual", main = "Standardized residuals", ...)
    return(invisible(NULL))
  }

  if (which == "r2_vs_index") {
    graphics::plot(index, plot_df$r2, pch = 16, col = "gray40",
                   xlab = "Index", ylab = "r2", main = "r2 vs index", ...)
    return(invisible(NULL))
  }

  invisible(NULL)
}
