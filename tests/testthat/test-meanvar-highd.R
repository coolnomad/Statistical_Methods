context("meanvar highd")

testthat::test_that("high-D variance improvement over constant", {
  set.seed(456)
  n <- 5000
  p <- 20
  X <- matrix(rnorm(n * p), nrow = n, ncol = p)

  mu <- X[, 1] + 0.5 * X[, 2]^2 - 0.75 * (X[, 3] > 0)
  sigma2 <- exp(0.2 * X[, 4] - 0.3 * X[, 5] + 0.5 * X[, 4] * X[, 5]) + 0.1
  y <- mu + rnorm(n, sd = sqrt(sigma2))

  fit <- fit_mean_variance(
    y, X,
    mean_backend = "ranger",
    var_backend = "rf_smooth",
    projection = "var_pred",
    seed = 456
  )

  sigma2_hat <- fit$sigma2_hat
  ise <- mean((sigma2_hat - sigma2)^2)
  r2_fit <- (y - fit$mu_hat)^2
  ise_const <- mean((mean(r2_fit) - sigma2)^2)

  expect_lt(ise, ise_const)
})
