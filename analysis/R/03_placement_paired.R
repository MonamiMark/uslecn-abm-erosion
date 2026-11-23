# ---------------------------------------------------------------------------
# v1.2.0. Only the input/output path block differs from the script used for the
# manuscript; all analysis code is unchanged. Paths default to the repository
# layout when the script is run from analysis/R (see README.md).
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({ library(dplyr) })
p <- read.csv(Sys.getenv("LSCN_PAIRS", unset = file.path("..", "..", "data", "outputs", "derived", "pairs.csv")),
              check.names = FALSE)
q <- p[p[["srazky-mm"]] != 10 | is.na(p[["srazky-mm"]]), ]

factors <- c("morphology", "flow_direction", "soil", "division_angle",
             "srazky-mm", "stripe-length", "par-minfrac")
factors <- factors[factors %in% names(q)]

pairs <- list(c("p288k", "p288p"), c("p400s1k", "p400s1p"),
              c("p500k", "p500p"), c("eKPnt", "ePKnt"),
              c("eKPntTwo", "eKPntTwo (copy)"))

cat("=== overeni shodnosti faktoru v paru experimentu ===\n")
for (pr in pairs) {
  a <- q[q$parent == pr[1], ]; b <- q[q$parent == pr[2], ]
  cat("\n", pr[1], " vs ", pr[2], " (radku ", nrow(a), "/", nrow(b), ")\n", sep = "")
  for (f in factors) {
    la <- sort(unique(as.character(a[[f]]))); lb <- sort(unique(as.character(b[[f]])))
    if (!identical(la, lb)) cat("  ROZDIL ", f, ": ", paste(la, collapse = ","),
                                "  vs  ", paste(lb, collapse = ","), "\n", sep = "")
  }
}

cat("\n=== parovany rozdil absolutni eroze podle poradi plodin ===\n")
res <- list()
for (pr in pairs) {
  a <- q[q$parent == pr[1], ]; b <- q[q$parent == pr[2], ]
  a$key <- do.call(paste, c(a[factors], sep = "|"))
  b$key <- do.call(paste, c(b[factors], sep = "|"))
  m <- merge(a[, c("key", "A_LS", "A_CN")], b[, c("key", "A_LS", "A_CN")],
             by = "key", suffixes = c("_k", "_p"))
  if (!nrow(m)) next
  m$dLS <- m$A_LS_p - m$A_LS_k
  m$dCN <- m$A_CN_p - m$A_CN_k
  res[[length(res) + 1]] <- data.frame(
    par = paste(pr, collapse = " vs "), n = nrow(m),
    A_LS_k = round(mean(m$A_LS_k), 2), A_LS_p = round(mean(m$A_LS_p), 2),
    rozdil_LS = round(mean(m$dLS), 3), pct_LS = round(100 * mean(m$dLS / m$A_LS_k), 1),
    A_CN_k = round(mean(m$A_CN_k), 2), A_CN_p = round(mean(m$A_CN_p), 2),
    rozdil_CN = round(mean(m$dCN), 3), pct_CN = round(100 * mean(m$dCN / m$A_CN_k), 1),
    podil_kladsich = round(100 * mean(m$dLS > 0), 1))
}
print(bind_rows(res), row.names = FALSE)

cat("\n=== efekt delky pasu uvnitr jednotlivych experimentu (A_LS) ===\n")
for (parent in unique(q$parent)) {
  d <- q[q$parent == parent, ]
  if (length(unique(d$`stripe-length`)) < 2) next
  gm <- d %>% group_by(`stripe-length`) %>% summarise(m = mean(A_LS), .groups = "drop")
  cat(sprintf("%-22s n=%5d  min=%6.2f  max=%6.2f  rozpeti=%6.2f (%.1f %%)\n",
              parent, nrow(d), min(gm$m), max(gm$m), max(gm$m) - min(gm$m),
              100 * (max(gm$m) - min(gm$m)) / mean(gm$m)))
}
