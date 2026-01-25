context("meanvar 1d")

testthat::test_that("1-D variance recovery", {
  set.seed(123)
  n <- 1500
  x <- runif(n, 0, 10)
  sigma2 <- 0.05 + (0.5 + 0.5 * sin(2 * pi * x / 10))
  y <- x + rnorm(n, sd = sqrt(sigma2))

  fit <- fit_mean_variance(y, x)

  xg <- seq(0, 10, length.out = 200)
  sigma2_true <- 0.05 + (0.5 + 0.5 * sin(2 * pi * xg / 10))
  sigma2_hat <- predict(fit, xg, type = "sigma2")

  expect_gt(stats::cor(sigma2_hat, sigma2_true), 0.85)
})
