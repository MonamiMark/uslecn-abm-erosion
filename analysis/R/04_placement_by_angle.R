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

for (pr in pairs) {
  a <- q[q$parent == pr[1], ]; b <- q[q$parent == pr[2], ]
  a$key <- do.call(paste, c(a[factors], sep = "|"))
  b$key <- do.call(paste, c(b[factors], sep = "|"))
  m <- merge(a[, c("key", "A_LS", "A_CN", "division_angle", "morphology",
                   "flow_direction", "soil", "srazky-mm", "stripe-length")],
             b[, c("key", "A_LS", "A_CN")], by = "key", suffixes = c("_k", "_p"))
  m$pct_LS <- 100 * (m$A_LS_p - m$A_LS_k) / m$A_LS_k
  cat("\n===", pr[1], "vs", pr[2], " (n =", nrow(m), ") ===\n")
  cat("-- podle uhlu pasu --\n")
  print(m %>% group_by(division_angle) %>%
          summarise(n = n(), A_LS_k = round(mean(A_LS_k), 2),
                    A_LS_p = round(mean(A_LS_p), 2),
                    pct = round(mean(pct_LS), 1), .groups = "drop") %>%
          as.data.frame(), row.names = FALSE)
  if (length(unique(m$`srazky-mm`)) > 1) {
    cat("-- podle srazek --\n")
    print(m %>% group_by(`srazky-mm`) %>%
            summarise(n = n(), A_LS_k = round(mean(A_LS_k), 2),
                      A_LS_p = round(mean(A_LS_p), 2),
                      pct = round(mean(pct_LS), 1), .groups = "drop") %>%
            as.data.frame(), row.names = FALSE)
  }
}
