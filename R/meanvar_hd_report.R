#' Mean-variance high-dimensional diagnostics report
#'
#' @param fit A fitted meanvar model.
#' @param X Covariates for prediction.
#' @param y Response vector.
#' @param sigma2_true Optional true variance for simulation diagnostics.
#' @param bins Number of bins for calibration plots.
#' @param alpha_pts Alpha for scatter points.
#' @param cex_pts Point size for scatter points.
#' @param main_prefix Plot title prefix.
#' @param calibrate Whether to z-calibrate sigma2 predictions.
#' @param var_floor Lower bound for variances.
#' @param add_qq Whether to add QQ and histogram panels.
#'
#' @return Invisibly returns a list with metrics and plotting data.
#' @export
meanvar_hd_report <- function(
    fit, X, y,
    sigma2_true = NULL,
    bins = 20,
    alpha_pts = 0.15,
    cex_pts = 0.5,
    main_prefix = "meanvar hd report",
    calibrate = TRUE,
    var_floor = 1e-12,
    add_qq = TRUE
) {
  stopifnot(!is.null(fit), !is.null(X), !is.null(y))
  pred <- predict(fit, X, type = "all")

  # unify naming
  mu_hat <- pred$mu
  sigma2_hat_raw <- pmax(pred$sigma2, var_floor)

  r <- y - mu_hat
  r2 <- r^2

  # choose index for x-axis in plots (use projection index if available)
  if (!is.null(fit$projection) && !is.null(fit$projection$t_train)) {
    t_idx <- fit$projection$t_train
    t_lab <- "variance index (t)"
  } else {
    t_idx <- sigma2_hat_raw
    t_lab <- "predicted variance (sigma2_hat)"
  }

  # ---- calibrations ----
  # A) z-calibration: enforce mean(r^2 / (c*sigma2_hat_raw)) = 1  => mean(z^2)=1
  c_z <- 1
  sigma2_hat <- sigma2_hat_raw
  if (isTRUE(calibrate)) {
    c_z <- mean(r2 / sigma2_hat_raw)
    if (is.finite(c_z) && c_z > 0) {
      sigma2_hat <- pmax(c_z * sigma2_hat_raw, var_floor)
    } else {
      c_z <- 1
      sigma2_hat <- sigma2_hat_raw
    }
  }

  # B) truth-optimal scaling (simulation-only): minimize ISE to sigma2_true over multipliers
  c_truth <- NA_real_
  sigma2_hat_truthcal <- NULL
  if (!is.null(sigma2_true)) {
    sigma2_true <- pmax(sigma2_true, var_floor)
    c_truth <- sum(sigma2_true * sigma2_hat_raw) / sum(sigma2_hat_raw^2)
    if (is.finite(c_truth) && c_truth > 0) {
      sigma2_hat_truthcal <- pmax(c_truth * sigma2_hat_raw, var_floor)
    } else {
      c_truth <- NA_real_
      sigma2_hat_truthcal <- NULL
    }
  }

  # standardized residuals
  z_raw <- r / sqrt(sigma2_hat_raw)
  z <- r / sqrt(sigma2_hat)

  # constant variance baseline
  var_const <- mean(r2)
  sigma2_const <- rep(var_const, length(y))
  z_const <- r / sqrt(var_const)

  # calibration by bins of t_idx
  df_plot <- data.frame(
    t = t_idx,
    r2 = r2,
    sigma2_hat_raw = sigma2_hat_raw,
    sigma2_hat = sigma2_hat,
    z_raw = z_raw,
    z = z
  )

  rank_t <- rank(df_plot$t, ties.method = "first")
  bin <- floor((rank_t - 1) / length(rank_t) * bins) + 1
  bin <- pmin(pmax(bin, 1), bins)

  cal <- data.frame(
    bin = seq_len(bins),
    mean_r2 = tapply(df_plot$r2, bin, mean),
    mean_sigma2_raw = tapply(df_plot$sigma2_hat_raw, bin, mean),
    mean_sigma2 = tapply(df_plot$sigma2_hat, bin, mean),
    n = tapply(df_plot$r2, bin, length)
  )

  # ---- metrics ----
  metrics <- list(
    n = length(y),

    # calibration multipliers
    calibration_multiplier_z = c_z,
    calibration_multiplier_truth = c_truth,

    # raw z diagnostics
    mean_z2_raw = mean(z_raw^2),
    sd_z2_raw = stats::sd(z_raw^2),
    p_abs_z_gt_3_raw = mean(abs(z_raw) > 3),
    max_abs_z_raw = max(abs(z_raw)),
    q_abs_z_raw = unname(stats::quantile(abs(z_raw), c(.99, .995, .999))),

    # calibrated z diagnostics
    mean_z2 = mean(z^2),
    sd_z2 = stats::sd(z^2),
    p_abs_z_gt_3 = mean(abs(z) > 3),
    max_abs_z = max(abs(z)),
    q_abs_z = unname(stats::quantile(abs(z), c(.99, .995, .999))),

    # signal diagnostics
    cor_r2_sigma2hat_raw = stats::cor(r2, sigma2_hat_raw),
    cor_r2_sigma2hat = stats::cor(r2, sigma2_hat),

    # baseline
    baseline_var_const = var_const,

    # pointwise scoring (normalized, for "how well does sigma2 explain r^2")
    mse_r2_vs_sigma2hat_norm_raw = mean((r2 - sigma2_hat_raw)^2) / mean(r2^2),
    mse_r2_vs_sigma2hat_norm = mean((r2 - sigma2_hat)^2) / mean(r2^2)
  )

  if (!is.null(sigma2_true)) {
    metrics$ise_const_vs_truth <- mean((sigma2_const - sigma2_true)^2)
    metrics$ise_model_vs_truth_raw <- mean((sigma2_hat_raw - sigma2_true)^2)
    metrics$ise_model_vs_truth_zcal <- mean((sigma2_hat - sigma2_true)^2)
    metrics$improvement_over_const_raw <- 1 - metrics$ise_model_vs_truth_raw / metrics$ise_const_vs_truth
    metrics$improvement_over_const_zcal <- 1 - metrics$ise_model_vs_truth_zcal / metrics$ise_const_vs_truth

    metrics$cor_sigma2hat_truth_raw <- stats::cor(sigma2_hat_raw, sigma2_true)
    metrics$cor_sigma2hat_truth_zcal <- stats::cor(sigma2_hat, sigma2_true)

    if (!is.null(sigma2_hat_truthcal)) {
      metrics$ise_model_vs_truth_truthcal <- mean((sigma2_hat_truthcal - sigma2_true)^2)
      metrics$improvement_over_const_truthcal <- 1 - metrics$ise_model_vs_truth_truthcal / metrics$ise_const_vs_truth
      metrics$cor_sigma2hat_truth_truthcal <- stats::cor(sigma2_hat_truthcal, sigma2_true)
    } else {
      metrics$ise_model_vs_truth_truthcal <- NA_real_
      metrics$improvement_over_const_truthcal <- NA_real_
      metrics$cor_sigma2hat_truth_truthcal <- NA_real_
    }
  }

  # ---- plots ----
  op <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(op), add = TRUE)

  ord <- order(df_plot$t)

  if (isTRUE(add_qq)) {
    graphics::par(mfrow = c(2, 3), mar = c(4, 4, 2.2, 1))
  } else {
    graphics::par(mfrow = c(2, 2), mar = c(4, 4, 2.2, 1))
  }

  # A) r^2 scatter + sigma2 curves
  graphics::plot(df_plot$t, df_plot$r2,
       pch = 16, cex = cex_pts,
       col = grDevices::rgb(0, 0, 0, alpha_pts),
       xlab = t_lab, ylab = "squared residuals r^2",
       main = paste0(main_prefix, "\nA) r^2 scatter + sigma2 curves"))
  graphics::lines(df_plot$t[ord], df_plot$sigma2_hat_raw[ord], col = "gray40", lwd = 2)
  if (isTRUE(calibrate)) {
    graphics::lines(df_plot$t[ord], df_plot$sigma2_hat[ord], col = "blue", lwd = 2)
    graphics::legend("topleft",
           legend = c("raw sigma2_hat", "z-calibrated sigma2_hat"),
           col = c("gray40", "blue"), lwd = 2, bty = "n", cex = 0.9)
  } else {
    graphics::lines(df_plot$t[ord], df_plot$sigma2_hat_raw[ord], col = "blue", lwd = 2)
  }

  # B) z vs index (raw vs calibrated)
  graphics::plot(df_plot$t, df_plot$z_raw,
       pch = 16, cex = cex_pts,
       col = grDevices::rgb(0, 0, 0, alpha_pts),
       xlab = t_lab, ylab = "standardized residual z",
       main = "B) z vs index (raw vs z-cal)")
  if (isTRUE(calibrate)) {
    graphics::points(df_plot$t, df_plot$z,
           pch = 16, cex = cex_pts,
           col = grDevices::rgb(0, 0, 1, alpha_pts * 0.8))
    graphics::legend("topleft",
           legend = c("raw", "z-calibrated"),
           col = c("black", "blue"),
           pch = 16, bty = "n", cex = 0.9)
  }
  graphics::abline(h = 0, col = "red", lwd = 2)

  # C) variance calibration (binned): mean sigma2 vs mean r^2
  graphics::plot(cal$mean_sigma2_raw, cal$mean_r2,
       pch = 16,
       xlab = "mean predicted variance",
       ylab = "mean empirical r^2",
       main = "C) variance calibration (binned)")
  if (isTRUE(calibrate)) {
    graphics::points(cal$mean_sigma2, cal$mean_r2, pch = 16, col = "blue")
    graphics::legend("topleft",
           legend = c("raw", "z-calibrated"),
           col = c("black", "blue"),
           pch = 16, bty = "n", cex = 0.9)
  }
  graphics::abline(0, 1, col = "red", lwd = 2)

  # D) constant-variance baseline funnel (z_const vs sigma2_hat)
  graphics::plot(sigma2_hat, z_const,
       pch = 16, cex = cex_pts,
       col = grDevices::rgb(0, 0, 0, alpha_pts),
       xlab = "predicted variance (sigma2_hat)",
       ylab = "z under constant variance",
       main = "D) constant-variance baseline (should funnel)")
  graphics::abline(h = 0, col = "red", lwd = 2)

  if (isTRUE(add_qq)) {
    # E) QQ plot of z (z-calibrated)
    stats::qqnorm(z, pch = 16, cex = 0.6,
           main = "E) QQ plot of z (z-calibrated)")
    stats::qqline(z, col = "red", lwd = 2)

    # F) histogram of z
    graphics::hist(z, breaks = 40, main = "F) hist(z) (z-calibrated)",
         xlab = "z", border = "white")
  }

  # ---- report text ----
  cat("\n==============================\n")
  cat("MEANVAR HD REPORT\n")
  cat("==============================\n")
  cat("n =", metrics$n, "\n")

  if (isTRUE(calibrate)) {
    cat("\nCalibration\n")
    cat("  z-cal multiplier c_z =", signif(metrics$calibration_multiplier_z, 4),
        " (sigma2_zcal = c_z * sigma2_raw)\n")
  }

  cat("\nCore diagnostics (raw)\n")
  cat("  cor(r^2, sigma2_hat_raw) =", signif(metrics$cor_r2_sigma2hat_raw, 4), "\n")
  cat("  mean(z_raw^2)            =", signif(metrics$mean_z2_raw, 4), " (target ~1)\n")
  cat("  P(|z_raw|>3)             =", signif(metrics$p_abs_z_gt_3_raw, 4), "\n")
  cat("  max|z_raw|               =", signif(metrics$max_abs_z_raw, 4), "\n")
  cat("  q(|z_raw|) 99/99.5/99.9% =", paste(signif(metrics$q_abs_z_raw, 4), collapse = ", "), "\n")
  cat("  norm MSE(r^2 vs sigma2_raw) =", signif(metrics$mse_r2_vs_sigma2hat_norm_raw, 4), "\n")

  cat("\nCore diagnostics (z-calibrated)\n")
  cat("  cor(r^2, sigma2_hat)      =", signif(metrics$cor_r2_sigma2hat, 4), "\n")
  cat("  mean(z^2)                 =", signif(metrics$mean_z2, 4), " (target ~1)\n")
  cat("  P(|z|>3)                  =", signif(metrics$p_abs_z_gt_3, 4), "\n")
  cat("  max|z|                    =", signif(metrics$max_abs_z, 4), "\n")
  cat("  q(|z|) 99/99.5/99.9%      =", paste(signif(metrics$q_abs_z, 4), collapse = ", "), "\n")
  cat("  norm MSE(r^2 vs sigma2_hat) =", signif(metrics$mse_r2_vs_sigma2hat_norm, 4), "\n")

  cat("\nBaseline\n")
  cat("  constant variance estimate =", signif(metrics$baseline_var_const, 4), "\n")

  if (!is.null(sigma2_true)) {
    cat("\nAgainst truth (simulation only)\n")
    cat("  ISE const vs truth        =", signif(metrics$ise_const_vs_truth, 4), "\n")

    cat("  ISE model vs truth (raw)  =", signif(metrics$ise_model_vs_truth_raw, 4),
        "  improvement =", signif(metrics$improvement_over_const_raw, 4), "\n")
    cat("  cor(sigma2_raw, truth)    =", signif(metrics$cor_sigma2hat_truth_raw, 4), "\n")

    cat("  ISE model vs truth (zcal) =", signif(metrics$ise_model_vs_truth_zcal, 4),
        "  improvement =", signif(metrics$improvement_over_const_zcal, 4), "\n")
    cat("  cor(sigma2_zcal, truth)   =", signif(metrics$cor_sigma2hat_truth_zcal, 4), "\n")

    if (is.finite(metrics$calibration_multiplier_truth)) {
      cat("  truth-opt multiplier c*   =", signif(metrics$calibration_multiplier_truth, 4), "\n")
      cat("  ISE model vs truth (truthcal) =", signif(metrics$ise_model_vs_truth_truthcal, 4),
          "  improvement =", signif(metrics$improvement_over_const_truthcal, 4), "\n")
      cat("  cor(sigma2_truthcal, truth)   =", signif(metrics$cor_sigma2hat_truth_truthcal, 4), "\n")
    }
  }

  cat("==============================\n\n")

  invisible(list(
    metrics = metrics,
    cal = cal,
    df = df_plot,
    pred = pred,
    z = z,
    z_raw = z_raw,
    sigma2_hat = sigma2_hat,
    sigma2_hat_raw = sigma2_hat_raw,
    sigma2_hat_truthcal = sigma2_hat_truthcal
  ))
}
