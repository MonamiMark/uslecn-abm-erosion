# ---------------------------------------------------------------------------
# v1.2.0. Only the input/output path block differs from the script used for the
# manuscript; all analysis code is unchanged. Paths default to the repository
# layout when the script is run from analysis/R (see README.md).
# ---------------------------------------------------------------------------

# Table 1 of the manuscript: descriptive LM on the paired difference
# A_CN - A_LS, plus the descriptive GAM of the same response.

suppressPackageStartupMessages({ library(mgcv); library(dplyr) })

p <- read.csv(Sys.getenv("LSCN_PAIRS", unset = file.path("..", "..", "data", "outputs", "derived", "pairs.csv")),
              check.names = FALSE, encoding = "UTF-8", stringsAsFactors = FALSE)
q <- p[toupper(p$rain_ok) == "TRUE", ]

q$soil <- factor(q$soil)
if ("kambizem" %in% levels(q$soil)) q$soil <- relevel(q$soil, ref = "kambizem")
q$crop2 <- factor(q$crop2)
if ("kukuřice na zrno" %in% levels(q$crop2)) q$crop2 <- relevel(q$crop2, ref = "kukuřice na zrno")
q$morphology <- factor(q$morphology)
if ("concave" %in% levels(q$morphology)) q$morphology <- relevel(q$morphology, ref = "concave")
q$flow_direction <- factor(q$flow_direction)
if ("convergent" %in% levels(q$flow_direction)) q$flow_direction <- relevel(q$flow_direction, ref = "convergent")
q$stripe_len <- as.numeric(q[["stripe-length"]])
q$angle <- as.numeric(q$division_angle)
q$rain <- as.numeric(q[["srazky-mm"]])
q <- q[complete.cases(q[, c("diff", "stripe_len", "angle", "rain", "soil", "crop2",
                            "morphology", "flow_direction")]), ]

cat("n =", nrow(q), "\n")
cat("levels soil:", paste(levels(q$soil), collapse = " | "), "\n")
cat("levels crop2:", paste(levels(q$crop2), collapse = " | "), "\n")
cat("levels morphology:", paste(levels(q$morphology), collapse = " | "), "\n")
cat("levels flow:", paste(levels(q$flow_direction), collapse = " | "), "\n\n")

cat("========== TABLE 1: LM deskriptivni model paroveho rozdilu ==========\n")
m1 <- lm(diff ~ stripe_len + angle + soil + rain, data = q)
s1 <- summary(m1)
print(coef(s1))
cat(sprintf("Observations: %d\nR2: %.4f\nR2 adj: %.4f\nAIC: %.3f\n",
            nrow(q), s1$r.squared, s1$adj.r.squared, AIC(m1)))

cat("\n========== TABLE 2: GAM paroveho rozdilu ==========\n")
m2 <- gam(diff ~ s(stripe_len, k = 8) + s(angle, k = 4) + s(rain, k = 4) +
            crop2 + soil + morphology + flow_direction,
          data = q, method = "REML", family = gaussian())
s2 <- summary(m2)
print(s2$p.table, digits = 5)
cat("\n-- smooth terms --\n")
print(s2$s.table, digits = 5)
cat(sprintf("\nObservations: %d\nDeviance explained: %.4f\nAIC: %.3f\nR2 (obs vs fitted): %.4f\n",
            length(m2$residuals), s2$r.sq * 100, AIC(m2),
            cor(q$diff, fitted(m2))^2))

cat("\n-- parciální R2 jednotlivých prediktorů (GAM drop) --\n")
cat("(exploratory block, not used in the manuscript: update() with . ~ . - x\n",
    " does not remove s() terms, so the smooth rows below are artefacts, and\n",
    " the values are differences in percent deviance explained, not partial R2)\n")
for (v in c("stripe_len", "angle", "rain", "crop2", "soil", "morphology", "flow_direction")) {
  fml <- as.formula(paste(". ~ . -", v))
  cat(sprintf("  %-16s %.4f\n", v, s2$r.sq * 100 - summary(update(m2, fml))$r.sq * 100))
}
