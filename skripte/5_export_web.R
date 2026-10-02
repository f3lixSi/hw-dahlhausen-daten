# ============================================================================
# WEB-EXPORT - schreibt aus 07_Live/live_log.csv die Datei live.json fuer die Website.
# Wird am Ende jedes erfolgreichen Logger-Laufs aufgerufen (4_logger_dauerlauf.R),
# kann aber auch einzeln laufen:   source("06_Code/5_export_web.R")
# Aus dem R-Project-Stamm ausfuehren. Paket: jsonlite
#
# Datenweg: Im Betrieb laeuft dieses Skript per GitHub Actions im Daten-Repo (10_Webdaten);
# der Workflow committet live.json, die Website (Netlify) liest sie ueber die raw-URL.
# ============================================================================
suppressMessages(library(jsonlite))

# Pfade per Umgebungsvariable ueberschreibbar (GitHub Actions setzt sie), lokal Standard wie bisher
LOG        <- file.path(Sys.getenv("HW_LOG_DIR", "07_Live"), "live_log.csv")
RATING_F   <- Sys.getenv("HW_RATING", "03_Results/rating_Hattingen_pre_post.csv")
MODEL_DIR  <- Sys.getenv("HW_MODEL_DIR", "06_Code")
OUT_FILES  <- Sys.getenv("HW_OUT", "09_Website/data/live.json")   # lokal: nur Website-Testkopie
DAYS_KEEP  <- 14
Q_MIN_WARN <- 70

# Laufzeiten bis Hattingen (Median + IQR aus 23 Ereignissen, 03_Results/leadtime_events.csv)
LAUFZEIT <- data.frame(
  key   = c("Witten", "Wetter", "Froendenberg", "Hohenlimburg", "Herdecke", "Meschede"),
  label = c("Witten", "Wetter", "Fr\u00f6ndenberg", "Hohenlimburg (Lenne)", "Herdecke", "Meschede"),
  lead  = c(3, 5, 6, 6, 6.5, 6.5),
  p25   = c(2, 4, 2.5, 5.5, 5, 4),
  p75   = c(4, 5, 9.2, 10.5, 7.2, 10.8),
  stringsAsFactors = FALSE)

MEZ <- "Etc/GMT-1"   # Ruhrverband-Zeit = MEZ ganzjaehrig (R17)
iso <- function(t) format(t, "%Y-%m-%dT%H:%M:%S+01:00", tz = MEZ)

d <- read.csv(LOG, stringsAsFactors = FALSE)
d$t <- as.POSIXct(d$rv_time, tz = MEZ)
d <- d[order(d$t), ]
d <- d[d$t >= max(d$t) - DAYS_KEEP * 86400, ]
L <- d[nrow(d), ]

# Wert vor ~h Stunden (naechster Zeitpunkt im +-1h-Fenster), fuer Tendenzen
vor <- function(col, h = 3) {
  dt <- abs(as.numeric(difftime(d$t, L$t - h * 3600, units = "hours")))
  i <- which.min(dt); if (length(i) == 0 || dt[i] > 1) NA else d[[col]][i]
}

# Q -> W ueber Post-2021-Rating
Q_to_W <- function(q) {
  if (!file.exists(RATING_F)) return(rep(NA_real_, length(q)))
  r <- read.csv(RATING_F); ok <- !is.na(r$W_post)
  approx(r$Q_center[ok], r$W_post[ok], xout = q, rule = 2)$y
}
sigma <- sapply(c(3, 6, 12), function(h) {
  f <- file.path(MODEL_DIR, sprintf("korr_model_lead%dh.rds", h))
  if (file.exists(f)) tryCatch(readRDS(f)$sigma_hi, error = function(e) NA) else NA
})

qp  <- c(L$pred_Q_3h, L$pred_Q_6h, L$pred_Q_12h)

# Unsicherheitsband: 90 %, abflussabhaengig, relativ (korr_band.csv aus 1_kalibrierung.R).
# Fallback (Datei fehlt): altes +-sigma_hi.
BAND_F <- file.path(MODEL_DIR, "korr_band.csv")
band_fak <- function(q, lead) {
  if (!file.exists(BAND_F) || !is.finite(q)) return(c(NA, NA, ""))
  b <- read.csv(BAND_F, stringsAsFactors = FALSE); b <- b[b$lead == lead, ]
  bis <- ifelse(is.na(b$q_bis), Inf, b$q_bis)
  i <- which(q >= b$q_von & q < bis)[1]
  if (is.na(i)) return(c(NA, NA, ""))
  c(b$f_lo[i], b$f_hi[i], ifelse(is.na(b$hinweis[i]), "", b$hinweis[i]))
}
bf <- lapply(seq_along(qp), function(j) band_fak(qp[j], c(3, 6, 12)[j]))
f_lo <- as.numeric(sapply(bf, `[`, 1)); f_hi <- as.numeric(sapply(bf, `[`, 2))
if (all(is.finite(f_lo)) && all(is.finite(f_hi))) {
  qlo <- qp * f_lo; qhi <- qp * f_hi
  methode <- "Korrelationsmodell (Oberlaufpegel), 90-%-Band abflussabhaengig"
} else {
  sg  <- ifelse(is.na(sigma), 0, sigma)
  qlo <- pmax(qp - sg, 0); qhi <- qp + sg
  methode <- "Korrelationsmodell (Oberlaufpegel), +-1 sigma (Fallback)"
}
band_hinweis <- unique(Filter(nzchar, sapply(bf, `[`, 3)))
band_hinweis <- if (length(band_hinweis)) band_hinweis[1] else ""

# Regime-Begriffe vereinheitlichen (aeltere Logzeilen: niedrigwasser / hochwasser_relevant)
regime_neu <- function(x) ifelse(x == "niedrigwasser", "unter_MQ", ifelse(x == "hochwasser_relevant", "ab_MQ", x))

gauges <- c("Hattingen", LAUFZEIT$key)
series <- list(time = I(iso(d$t)), Hattingen_W = I(d$Hattingen_W))
for (g in gauges) series[[g]] <- I(d[[g]])

upstream <- lapply(seq_len(nrow(LAUFZEIT)), function(i) {
  k <- LAUFZEIT$key[i]
  list(key = k, label = LAUFZEIT$label[i], Q = L[[k]], dQ_3h = L[[k]] - vor(k),
       lead_h = LAUFZEIT$lead[i], lead_p25 = LAUFZEIT$p25[i], lead_p75 = LAUFZEIT$p75[i],
       eta = iso(L$t + LAUFZEIT$lead[i] * 3600))
})

out <- list(
  meta = list(generated = iso(Sys.time()), latest = iso(L$t), q_min_warn = Q_MIN_WARN,
              source = "Ruhrverband (Talsperrenleitzentrale Ruhr), eigenes Korrelationsmodell",
              hinweis = "Keine amtliche Warnung. Entscheidungshilfe fuer das DLRG-Wachteam."),
  latest = list(Q = L$Hattingen, W = L$Hattingen_W, regime = regime_neu(L$regime),
                dW_3h = L$Hattingen_W - vor("Hattingen_W"), dQ_3h = L$Hattingen - vor("Hattingen")),
  forecast = list(base = iso(L$t), valid = isTRUE(L$Hattingen >= Q_MIN_WARN),
                  leads = I(c(3, 6, 12)), time = I(iso(L$t + c(3, 6, 12) * 3600)),
                  Q = I(qp), Q_lo = I(qlo), Q_hi = I(qhi),
                  W = I(Q_to_W(qp)), W_lo = I(Q_to_W(qlo)), W_hi = I(Q_to_W(qhi)),
                  methode = methode, band_hinweis = band_hinweis),
  series = series,
  upstream = upstream
)

for (f in OUT_FILES) {
  if (!dir.exists(dirname(f))) dir.create(dirname(f), recursive = TRUE)
  write_json(out, f, auto_unbox = TRUE, digits = NA, na = "null")
}
cat("Web-Export geschrieben:", paste(OUT_FILES, collapse = ", "), "\n")
