.build_diagnostics <- function(r, r2, r2_hat, sigma2_hat, index) {
  std_resid <- r / sqrt(sigma2_hat)
  plot_df <- data.frame(
    index = index,
    r2 = r2,
    sigma2_hat = sigma2_hat,
    std_resid = std_resid
  )
  if (!is.null(r2_hat)) {
    plot_df$r2_hat <- r2_hat
  }

  list(
    standardized_residuals = std_resid,
    r2 = r2,
    r2_hat = r2_hat,
    plot_df = plot_df
  )
}
