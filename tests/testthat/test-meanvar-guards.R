context("meanvar guards")

testthat::test_that("guards and predict lengths", {
  set.seed(789)
  n <- 300
  x <- runif(n, 0, 10)
  sigma2 <- 0.1 + 0.3 * (1 + sin(2 * pi * x / 10))
  y <- x + rnorm(n, sd = sqrt(sigma2))

  fit <- fit_mean_variance(y, x, var_floor = 1e-5)

  expect_true(all(fit$sigma2_hat >= fit$control$var_floor))

  x_new <- seq(0, 10, length.out = 50)
  mu_hat <- predict(fit, x_new, type = "mu")
  s2_hat <- predict(fit, x_new, type = "sigma2")
  all_hat <- predict(fit, x_new, type = "all")

  expect_length(mu_hat, length(x_new))
  expect_length(s2_hat, length(x_new))
  expect_length(all_hat$mu, length(x_new))
  expect_length(all_hat$sigma2, length(x_new))
  expect_length(all_hat$weights, length(x_new))
})
