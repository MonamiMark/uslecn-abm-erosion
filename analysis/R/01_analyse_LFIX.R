# ---------------------------------------------------------------------------
# v1.2.0. Only the input/output path block differs from the script used for the
# manuscript; all analysis code is unchanged. Paths default to the repository
# layout when the script is run from analysis/R (see README.md).
# ---------------------------------------------------------------------------

# analyse_LFIX.R - parove vyhodnoceni LFIX behu (WF? = false vs true)
#
# Cte CSV z out/ (BehaviorSpace, 7 radku hlavicky, CP1250). Kazdy experiment ma
# jine poradi i sadu sloupcu, takze se sloupce cteji podle jmen a paruje se
# podle vsech faktoru daneho experimentu (klic = vsechny sloupce krome vystupu
# a WF?).
#
# Podporuje CHUNKOVANE experimenty: soubor "<parent>_sl<cislo>.csv" se pocita
# jako cast experimentu <parent> (sloupec parent). Chunk je jen zpusob, jak
# rozdelit praci mezi procesy; designove jde o jeden experiment.
#
# DULEZITE - srazky 10 mm: SCS-CN s Ia = 0.2S da pri 10 mm Q = 0, takze A_CN
# vychazi presne 0 a divergence -100 %. Neni to vysledek, je to degenerovany
# pripad (vsechna voda se infiltruje). Statistiky divergence se proto pocitaji
# bez 10 mm a 10 mm se reportuje separatne.
#
# Vystup: out/analysis/pairs.csv (parova data) + konzolovy souhrn.

suppressPackageStartupMessages({ library(dplyr) })

RAW   <- Sys.getenv("LSCN_RAW", unset = file.path("..", "..", "data", "outputs", "raw"))
DERIV <- Sys.getenv("LSCN_DERIV", unset = file.path("..", "..", "data", "outputs", "derived"))
dir.create(DERIV, showWarnings = FALSE, recursive = TRUE)

# jadro designu; 4 experimenty s chybejicimi rastry a 7 s realnymi DEM tu nejsou.
# eKPnt288_2 a ePKnt288 jsou vynechane: jejich kombinace jsou podmnozinou
# eKPnt/ePKnt (stripe-length 36/72/144 vs 36/72/108/144/180) a na sdilenych
# klicich dveji identicke hodnoty (korelace 1.0000, median rozdilu 0.00 %).
active <- c("pasy_srazky", "eKPnt", "ePKnt", "p400s1p", "p400s1k", "p500p", "p500k",
            "p288p", "p288k", "eKPntTwo", "eKPntTwo (copy)",
            "ex_pasy_obracene", "ex_pasy_obracene_25", "experiment2")

read_bs <- function(path) {
  raw <- tryCatch(readLines(path, encoding = "CP1250", warn = FALSE), error = function(e) NULL)
  if (is.null(raw) || length(raw) < 8) return(NULL)
  cols <- strsplit(gsub('^"|"$', '', raw[7]), '","', fixed = TRUE)[[1]]
  body <- raw[-(1:7)]
  body <- body[nzchar(body)]
  if (!length(body)) return(NULL)
  sp <- strsplit(gsub('^"|"$', '', body), '","', fixed = TRUE)
  ok <- sp[lengths(sp) == length(cols)]
  if (!length(ok)) return(NULL)
  df <- as.data.frame(do.call(rbind, ok), stringsAsFactors = FALSE)
  names(df) <- cols
  df$A <- suppressWarnings(as.numeric(df$`total-erosion`))
  df[!is.na(df$A), , drop = FALSE]
}

# --- sestaveni seznamu souboru: aktivni + chunkovane casti --------------------
files <- character(0)
for (e in active) {
  f <- file.path(RAW, paste0(e, ".csv"))
  if (file.exists(f)) files <- c(files, f)
}
chunk_files <- list.files(RAW, pattern = "_sl[0-9]+\\.csv$", full.names = TRUE)
chunk_files <- chunk_files[grepl(
  paste0("^(", paste(gsub("([()])", "\\\\\\1", active), collapse = "|"), ")_sl[0-9]+\\.csv$"),
  basename(chunk_files))]
files <- unique(c(files, chunk_files))

pairs_all <- list(); skipped <- character(0); coverage <- list()

for (f in files) {
  name <- sub("\\.csv$", "", basename(f))
  parent <- sub("_sl[0-9]+$", "", name)
  d <- read_bs(f)
  if (is.null(d) || !("WF?" %in% names(d))) { skipped <- c(skipped, name); next }

  keycols <- setdiff(names(d), c("[run number]", "[step]", "total-erosion", "A", "WF?"))
  d$key <- do.call(paste, c(d[keycols], sep = "|"))

  lsr <- d[d$`WF?` == "false", c("key", "A")]; lsr <- lsr[!duplicated(lsr$key), ]
  cnr <- d[d$`WF?` == "true",  c("key", "A")]; cnr <- cnr[!duplicated(cnr$key), ]
  if (!nrow(lsr) || !nrow(cnr)) { skipped <- c(skipped, name); next }

  p <- merge(lsr, cnr, by = "key", suffixes = c("_LS", "_CN"))
  if (!nrow(p)) { skipped <- c(skipped, name); next }

  fac <- d[d$`WF?` == "false", c("key", keycols), drop = FALSE]
  fac <- fac[!duplicated(fac$key), ]
  p <- merge(p, fac, by = "key")
  p$experiment <- name
  p$parent <- parent
  pairs_all[[name]] <- p

  # bilance hladin - pro odhaleni zkreslenych (nedokoncenych) souboru
  bal <- sapply(intersect(c("morphology", "flow_direction", "soil", "division_angle",
                            "srazky-mm", "stripe-length"), names(p)), function(v) {
    tb <- table(p[[v]])
    if (length(tb) < 2) return(NA_real_)
    max(abs(as.numeric(tb) / sum(tb) - 1 / length(tb))) / (1 - 1 / length(tb))
  })
  coverage[[name]] <- data.frame(experiment = name, parent = parent, pairs = nrow(p),
                                 max_dev = round(max(bal, na.rm = TRUE), 3))
}

if (!length(pairs_all)) stop("zadna parova data")
P <- bind_rows(pairs_all)
for (cc in intersect(c("stripe-length", "division_angle", "srazky-mm", "par-minfrac"), names(P)))
  P[[cc]] <- suppressWarnings(as.numeric(P[[cc]]))

P <- P %>% mutate(diff = A_CN - A_LS, ratio = A_CN / A_LS, pct = 100 * (ratio - 1))
for (nm in c("soil", "srazky-mm", "stripe-length", "division_angle"))
  if (!nm %in% names(P)) P[[nm]] <- NA
P$crop_combo <- paste(P$crop1, P$crop2, sep = " / ")
P$rain_ok <- is.na(P$`srazky-mm`) | P$`srazky-mm` != 10   # 10 mm -> A_CN == 0 konstrukci

write.csv(P, file.path(DERIV, "pairs.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cov <- bind_rows(coverage)
write.csv(cov, file.path(DERIV, "coverage.csv"), row.names = FALSE, fileEncoding = "UTF-8")

fmt <- function(x, d = 1) formatC(x, format = "f", digits = d)

cat("\n================ POKRYTI SOUBORU ================\n")
print(as.data.frame(cov %>% arrange(desc(pairs))), row.names = FALSE)
cat("\nmax_dev = nejvetsi relativni odchylka zastoupeni hladiny od rovnomerneho (0 = vyvazene,\n")
cat("1 = vsechny pary v jedne hladine). Hodnoty > 0.35 znamenaji nedokonceny (zkresleny) soubor.\n")

Q <- P %>% filter(rain_ok)
cat("\n================ CELKEM (bez 10 mm) ================\n")
cat("paru:", nrow(Q), " (z", nrow(P), ")\n")
cat(sprintf("mean A_LS = %.3f   mean A_CN = %.3f   (pomer %+.1f %%)\n",
            mean(Q$A_LS), mean(Q$A_CN), 100 * (mean(Q$A_CN) / mean(Q$A_LS) - 1)))
cat(sprintf("pct: mean %+.1f %%  median %+.1f %%  sd %.1f  IQR %+.1f az %+.1f\n",
            mean(Q$pct), median(Q$pct), sd(Q$pct),
            quantile(Q$pct, .25), quantile(Q$pct, .75)))
cat(sprintf("dA:  mean %+.3f  median %+.3f t/ha/rok\n", mean(Q$diff), median(Q$diff)))
cat(sprintf("podil paru s A_CN > A_LS: %.1f %%\n", 100 * mean(Q$pct > 0)))
cat(sprintf("sd(A_CN)/sd(A_LS) = %.3f  (mene variabilni = < 1)\n", sd(Q$A_CN) / sd(Q$A_LS)))

cat("\n================ 10 mm (degenerovane, mimo statistiky) ================\n")
D <- P %>% filter(!rain_ok)
cat("paru:", nrow(D), "  A_CN == 0 ve vsech:", all(D$A_CN < 1e-9), "\n")
cat("Ia = 0.2S > P, takze SCS-CN nedava zadny odtok; divergence je -100 % konstrukci.\n")

cat("\n================ PO EXPERIMENTECH (bez 10 mm) ================\n")
print(as.data.frame(Q %>% group_by(parent) %>%
  summarise(soubory = n_distinct(experiment), n = n(),
            A_LS = round(mean(A_LS), 2), A_CN = round(mean(A_CN), 2),
            mean_pct = round(mean(pct), 1), med_pct = round(median(pct), 1),
            sd_pct = round(sd(pct), 1), pozitivni = round(100 * mean(pct > 0), 1),
            .groups = "drop")), row.names = FALSE)

cat("\n================ PO SRAZkach (bez 10 mm) ================\n")
print(as.data.frame(P %>% filter(!is.na(`srazky-mm`)) %>% group_by(`srazky-mm`) %>%
  summarise(n = n(), nulovych_A_CN = sum(A_CN < 1e-9),
            A_LS = round(mean(A_LS), 2), mean_pct = round(mean(pct), 1),
            med_pct = round(median(pct), 1), .groups = "drop")), row.names = FALSE)

for (v in c("soil", "morphology", "flow_direction", "stripe-length", "division_angle")) {
  if (!v %in% names(Q) || all(is.na(Q[[v]]))) next
  cat("\n---", v, "---\n")
  print(as.data.frame(Q %>% filter(!is.na(.data[[v]])) %>% group_by(lvl = .data[[v]]) %>%
    summarise(n = n(), A_LS = round(mean(A_LS), 2), mean_pct = round(mean(pct), 1),
              med_pct = round(median(pct), 1), .groups = "drop")), row.names = FALSE)
}

cat("\n================ PODIL ROZPTYLU divergence (bez 10 mm) ================\n")
r2 <- function(f, d = Q) summary(lm(f, data = d))$r.squared
for (v in c("srazky-mm", "soil", "morphology", "flow_direction", "stripe-length",
            "division_angle", "crop_combo")) {
  if (v %in% names(Q) && sum(!is.na(Q[[v]])) > 10 && length(unique(na.omit(Q[[v]]))) > 1)
    cat(sprintf("%-16s R2 = %.4f\n", v, r2(reformulate(sprintf("`%s`", v), "pct"))))
}
if (sum(!is.na(Q$`srazky-mm`)) > 10 && sum(!is.na(Q$soil)) > 10) {
  a <- r2(pct ~ `srazky-mm` * soil)
  b <- r2(pct ~ `srazky-mm` * soil + morphology + flow_direction)
  cat(sprintf("%-16s R2 = %.4f\n", "srazky*puda", a))
  cat(sprintf("%-16s R2 = %.4f   (prirustek topografie = %+.5f)\n", "srazky*puda+topo", b, b - a))
  ca <- r2(A_LS ~ `srazky-mm` * soil); cb <- r2(A_LS ~ `srazky-mm` * soil + morphology + flow_direction)
  cat(sprintf("%-16s R2 = %.4f   (kontrola: absolutni A_LS)\n", "A_LS ~ srazky*puda", ca))
  cat(sprintf("%-16s R2 = %.4f   (prirustek topografie = %+.4f)\n", "A_LS ~ +topo", cb, cb - ca))
}

cat("\n================ ROZDELENI pct (5% pasma, bez 10 mm) ================\n")
br <- c(-Inf, seq(-60, 40, by = 5), Inf)
tb <- as.data.frame(table(pas = cut(Q$pct, breaks = br)))
tb$podil <- round(100 * tb$Freq / sum(tb$Freq), 2)
print(tb[tb$Freq > 0, ], row.names = FALSE)
cat(sprintf("\npct == 0 presne: %.1f %%   |pct| < 0.01: %.1f %%\n",
            100 * mean(abs(Q$pct) < 1e-9), 100 * mean(abs(Q$pct) < 0.01)))

if (length(skipped)) { cat("\n--- preskoceno (bez paru) ---\n"); cat(" ", paste(skipped, collapse = ", "), "\n") }
cat("\nUlozeno:", file.path(DERIV, "pairs.csv"), "\n")
