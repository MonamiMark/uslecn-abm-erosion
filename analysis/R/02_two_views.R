# ---------------------------------------------------------------------------
# v1.2.0. Only the input/output path block differs from the script used for the
# manuscript; all analysis code is unchanged. Paths default to the repository
# layout when the script is run from analysis/R (see README.md).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(dplyr) })

outfile <- Sys.getenv("LSCN_TWO_VIEWS_OUT",
                       unset = file.path("..", "..", "docs", "console_logs",
                                        "two_views_console.txt"))
outcon <- file(outfile, open = "wt", encoding = "UTF-8")
sink(outcon)
sink(outcon, type = "message")

p <- read.csv(Sys.getenv("LSCN_PAIRS", unset = file.path("..", "..", "data", "outputs", "derived", "pairs.csv")),
              check.names = FALSE, encoding = "UTF-8")
q <- p[p[["srazky-mm"]] != 10 | is.na(p[["srazky-mm"]]), ]

pair_map <- list(
  "p288k" = "p288", "p288p" = "p288",
  "p400s1k" = "p400s1", "p400s1p" = "p400s1",
  "p500k" = "p500", "p500p" = "p500",
  "eKPnt" = "eKPnt", "ePKnt" = "eKPnt",
  "eKPntTwo" = "eKPntTwo", "eKPntTwo (copy)" = "eKPntTwo"
)
idx <- q$parent %in% names(pair_map)
q$pair <- NA_character_
q$pair[idx] <- unlist(pair_map[q$parent[idx]], use.names = FALSE)
q <- q[!is.na(q$pair), ]

q$crop_order <- ifelse(grepl("kukuřice", q$crop1), "maize_first", "wheat_first")
q$design <- ifelse(grepl("Two", q$pair), "two", "stripes")
for (v in c("pair", "crop_order", "design", "division_angle", "srazky-mm",
            "morphology", "flow_direction", "soil")) {
  q[[v]] <- factor(q[[v]])
}
q$stripe_len <- factor(q[["stripe-length"]])

cat("Párová data: n =", nrow(q), "(bez 10 mm, jen experimenty s protějškem)\n")
cat("  stripes:", sum(q$design == "stripes"), " two:", sum(q$design == "two"), "\n")

partial_r2 <- function(fit, f) {
  r2f <- summary(fit)$r.squared
  fml <- as.formula(paste(". ~ . -", sprintf("`%s`", f)))
  r2m <- summary(update(fit, fml))$r.squared
  r2f - r2m
}

report <- function(fit, factors, label) {
  cat(sprintf("\nR2 celkem = %.4f\n", summary(fit)$r.squared))
  tb <- data.frame(faktor = factors,
                   parcialni_R2 = sapply(factors, function(f) partial_r2(fit, f)))
  print(tb[order(-tb$parcialni_R2), ], row.names = FALSE, digits = 4)
  cat("-- jednotlive R2 --\n")
  for (v in factors) {
    r <- summary(lm(reformulate(sprintf("`%s`", v), as.character(fit$terms[[2]])),
                    data = fit$model))$r.squared
    cat(sprintf("  %-16s %.4f\n", v, r))
  }
}

base <- c("pair", "crop_order", "division_angle", "srazky-mm",
          "morphology", "flow_direction", "soil")
allf <- c(base, "stripe_len")

cat("\n==========================================================\n")
cat("NAHLED 1: prispivek parametru k ROZDILU A_CN - A_LS (pct)\n")
cat("==========================================================\n")
cat("\n-- vsechny parovane radky (bez stripe-length, aby zustaly i 'two') --\n")
f1 <- lm(pct ~ pair + crop_order + division_angle + `srazky-mm` +
         morphology + flow_direction + soil, data = q)
report(f1, base, "view1_all")

cat("\n-- jen stripes (pridana delka pasu) --\n")
s <- q[q$design == "stripes", ]
f1s <- lm(pct ~ pair + crop_order + stripe_len + division_angle + `srazky-mm` +
          morphology + flow_direction + soil, data = s)
report(f1s, allf, "view1_stripes")

cat("\n==========================================================\n")
cat("NAHLED 2: ABSOLUTNI EROZE PODLE LS_CN (A_CN)\n")
cat("==========================================================\n")
cat("\n-- vsechny parovane radky (bez stripe-length) --\n")
f2 <- lm(A_CN ~ pair + crop_order + division_angle + `srazky-mm` +
         morphology + flow_direction + soil, data = q)
report(f2, base, "view2_all")

cat("\n-- jen stripes (pridana delka pasu) --\n")
f2s <- lm(A_CN ~ pair + crop_order + stripe_len + division_angle + `srazky-mm` +
          morphology + flow_direction + soil, data = s)
report(f2s, allf, "view2_stripes")

cat("\n-- interakce poradi plodin x uhel pasu (vsechny radky) --\n")
f3 <- lm(A_CN ~ pair + crop_order * division_angle + `srazky-mm` +
         morphology + flow_direction + soil, data = q)
cat(sprintf("R2 s interakci = %.4f (prirustek %.4f)\n",
            summary(f3)$r.squared, summary(f3)$r.squared - summary(f2)$r.squared))

agg <- q %>% group_by(design, crop_order, division_angle) %>%
  summarise(n = n(), A_CN = round(mean(A_CN), 3), A_LS = round(mean(A_LS), 3),
            .groups = "drop")
cat("\n-- A_CN / A_LS podle designu, poradi a uhlu --\n")
print(as.data.frame(agg), row.names = FALSE)

cat("\n-- parovany kontrast poradi plodin, rozdeleny podle designu --\n")
keyvars <- c("pair", "morphology", "flow_direction", "soil",
             "division_angle", "srazky-mm", "stripe_len")
a <- q[q$crop_order == "maize_first", ]
b <- q[q$crop_order == "wheat_first", ]
a$key <- do.call(paste, c(a[keyvars], sep = "|"))
b$key <- do.call(paste, c(b[keyvars], sep = "|"))
m <- merge(a[, c("key", "A_CN", "A_LS", "design", "pair", "division_angle")],
           b[, c("key", "A_CN", "A_LS")], by = "key", suffixes = c("_k", "_p"))
m$dCN <- 100 * (m$A_CN_p - m$A_CN_k) / m$A_CN_k
m$dLS <- 100 * (m$A_LS_p - m$A_LS_k) / m$A_LS_k
cat("paru celkem:", nrow(m), "\n")
for (ds in c("two", "stripes")) {
  d <- m[m$design == ds, ]
  cat(sprintf("  %-8s n=%4d  A_CN %+7.1f %%  A_LS %+7.1f %%\n",
              ds, nrow(d), mean(d$dCN), mean(d$dLS)))
}
cat("\n  stripes podle uhlu:\n")
print(m[m$design == "stripes", ] %>% group_by(division_angle) %>%
        summarise(n = n(), dCN = round(mean(dCN), 1), dLS = round(mean(dLS), 1),
                  .groups = "drop") %>% as.data.frame(), row.names = FALSE)

sink(type = "message")
sink()
close(outcon)
