# ---------------------------------------------------------------------------
# v1.2.0. Only the input/output path block differs from the script used for the
# manuscript; all analysis code is unchanged. Paths default to the repository
# layout when the script is run from analysis/R (see README.md).
# ---------------------------------------------------------------------------

# Table 2 of the manuscript: descriptive GAM on absolute soil loss in
# long format, with method as a fixed factor.

suppressPackageStartupMessages({ library(mgcv) })

p <- read.csv(Sys.getenv("LSCN_PAIRS", unset = file.path("..", "..", "data", "outputs", "derived", "pairs.csv")),
              check.names = FALSE, encoding = "UTF-8", stringsAsFactors = FALSE)
q <- p[toupper(p$rain_ok) == "TRUE", ]

# long format: two rows per pair, method factor
long <- rbind(
  data.frame(key = q$key, A = q$A_LS, method = "LS",
             crop2 = q$crop2, soil = q$soil, morphology = q$morphology,
             flow_direction = q$flow_direction,
             stripe_len = as.numeric(q[["stripe-length"]]),
             angle = as.numeric(q$division_angle),
             rain = as.numeric(q[["srazky-mm"]]),
             stringsAsFactors = FALSE),
  data.frame(key = q$key, A = q$A_CN, method = "LS_CN",
             crop2 = q$crop2, soil = q$soil, morphology = q$morphology,
             flow_direction = q$flow_direction,
             stripe_len = as.numeric(q[["stripe-length"]]),
             angle = as.numeric(q$division_angle),
             rain = as.numeric(q[["srazky-mm"]]),
             stringsAsFactors = FALSE)
)
long <- long[complete.cases(long), ]
long$key <- factor(long$key)
long$method <- factor(long$method, levels = c("LS", "LS_CN"))
long$soil <- relevel(factor(long$soil), ref = "kambizem")
long$crop2 <- relevel(factor(long$crop2), ref = "kukuřice na zrno")
long$morphology <- relevel(factor(long$morphology), ref = "concave")
long$flow_direction <- relevel(factor(long$flow_direction), ref = "convergent")

cat("n rows =", nrow(long), " pairs =", nlevels(long$key), "\n\n")
cat("=== GAM absolute A, method as a fixed factor ===\n")
cat("NB: the two rows of a pair are not independent and no pair-level\n",
    "random effect is included, so this model is descriptive only\n",
    "(see Section 2.8 of the manuscript).\n")
m <- gam(A ~ s(stripe_len, k = 8) + s(angle, k = 4) + s(rain, k = 4) +
           crop2 + soil + morphology + flow_direction + method,
         data = long, method = "REML", family = gaussian())
s <- summary(m)
print(s$p.table, digits = 5)
cat("\n-- smooth terms --\n")
print(s$s.table, digits = 5)
cat(sprintf("\nObservations: %d\nDeviance explained: %.4f%%\nAIC: %.3f\nR2(obs vs fitted): %.4f\n",
            length(m$residuals), s$r.sq * 100, AIC(m), cor(long$A, fitted(m))^2))
