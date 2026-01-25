# meanvar

Mean-variance modeling tools for estimating conditional mean and variance with GAM
and random forest backends.

## Usage

```r
fit <- fit_mean_variance(y, X)
mu <- predict(fit, X, type = "mu")
s2 <- predict(fit, X, type = "sigma2")
plot(fit, which = "variance_curve")
```

## Vignette

See `vignettes/meanvar-intro.Rmd` for a worked example, and use
`fit_meanvar_1d()` as a convenience wrapper for 1-D data.

## Examples

### 1-D variance curve

```r
set.seed(123)
x <- runif(1000, 0, 10)
sigma2 <- 0.05 + (0.5 + 0.5 * sin(2 * pi * x / 10))
y <- x + rnorm(length(x), sd = sqrt(sigma2))

fit <- fit_mean_variance(y, x)
plot(fit, which = "variance_curve")
```

### High-D with random forests

```r
set.seed(456)
n <- 2000
p <- 15
X <- matrix(rnorm(n * p), nrow = n)
mu <- X[, 1] + 0.5 * X[, 2]^2 - 0.75 * (X[, 3] > 0)
sigma2 <- exp(0.2 * X[, 4] - 0.3 * X[, 5] + 0.5 * X[, 4] * X[, 5]) + 0.1
y <- mu + rnorm(n, sd = sqrt(sigma2))

fit <- fit_mean_variance(
  y, X,
  mean_backend = "ranger",
  var_backend = "rf_smooth",
  projection = "var_pred"
)
pred <- predict(fit, X, type = "all")
```
