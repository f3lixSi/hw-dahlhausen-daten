# ============================================================================
# LOGGER — Herzstück des Live-Betriebs. Ein Aufruf = ein Abruf-Versuch.
# Schreibt EINE Zeile pro NEUEM Ruhrverband-Zeitstempel:
#   (a) beobachtete Pegel  -> baut die Zeitreihen-Historie auf (Dashboard)
#   (b) Vorhersagen +3/+6/+12 h -> ermöglicht später den Gegentest
#
# ZEITZONE (bestätigt 2026-07-15): `rv_time` läuft beim Ruhrverband DURCHGEHEND in
# MEZ (= UTC+1, ganzjährig, keine Sommerzeit-Umstellung). `run_time` ist dagegen
# lokale Rechnerzeit (im Sommer MESZ). Damit später nichts durcheinandergerät,
# schreiben wir zusätzlich `rv_time_utc` mit -> eindeutig für die Kopplung mit
# ICON-D2/Open-Meteo (die in UTC laufen).
# Hinweis: In R ist "Etc/GMT-1" (Vorzeichen invertiert!) die Zone UTC+1 = MEZ.
#
# Hattingen erhält stündlich neue Werte -> stündlich abrufen reicht; nur bei
# Fehlschlag/noch-keine-neuen-Daten kurz nachfassen (siehe 4_logger_dauerlauf.R).
# Wiederholte Zeitstempel werden automatisch verworfen.
#
# Aus dem R-Project-Stamm ausführen. Paket: jsonlite
# ============================================================================
suppressMessages(library(jsonlite))

# Pfade per Umgebungsvariable ueberschreibbar (GitHub Actions), lokal Standard wie bisher
model_dir <- Sys.getenv("HW_MODEL_DIR", "06_Code")

# --- Betriebsschwelle: unter diesem Hattingen-Abfluss taugt das Korrelationsmodell
#     NICHT (der Bereich unter Mittelwasser ist durch Talsperren/Entnahmen gesteuert;
#     Persistenz ist dort besser, R16). Datenbasiert = 75.-Perzentil, faellt praktisch mit
#     dem amtlichen MQ (70,8 m3/s) zusammen. Begriffe seit 2026-10-02: unter_MQ / ab_MQ.
Q_MIN_WARN <- 70   # m3/s (~ MQ)
log_dir   <- Sys.getenv("HW_LOG_DIR", "07_Live")
log_file  <- file.path(log_dir, "live_log.csv")
if (!dir.exists(log_dir)) dir.create(log_dir)

url <- paste0("https://www.talsperrenleitzentrale-ruhr.de/online-daten/gewaesserpegel/",
              "?tx_onlinedata_gauges%5Baction%5D=json",
              "&tx_onlinedata_gauges%5Bcontroller%5D=Gauges&type=863")

# zr_id der Prädiktor-Pegel (Durchfluss) + Hattingen-Wasserstand
zr_Q <- c(Hattingen = 8345042, Wetter = 4277042, Herdecke = 8174042, Witten = 16334042,
          Froendenberg = 8796042, Meschede = 7363042, Hohenlimburg = 8461042)
zr_W_hattingen <- 8317042

predict_korr <- function(m, akt) {
  if (is.null(m$coef))
    stop("Altes Modellformat. Bitte 06_Code/1_kalibrierung.R einmal neu ausführen.")
  miss <- setdiff(m$features, names(akt))
  if (length(miss)) stop("Fehlende Pegel-Spalten: ", paste(miss, collapse = ", "))
  x <- as.numeric(unlist(akt[1, m$features]))
  as.numeric(m$coef[["(Intercept)"]] + sum(as.numeric(m$coef[m$features]) * x))
}

# Rückgabe: "ok" (geschrieben) | "keine_neuen" (RV noch nicht aktualisiert) | "fehler" (Abruf)
log_once <- function() {
  d <- tryCatch(fromJSON(url), error = function(e) NULL)
  if (is.null(d)) { cat("Abruf fehlgeschlagen (Internet?) — übersprungen.\n"); return(invisible("fehler")) }

  val <- function(id) { v <- d$value[match(id, d$zr_id)]; if (length(v) == 0) NA else v }
  obs <- as.data.frame(as.list(sapply(zr_Q, val)))
  obs$Hattingen_W <- val(zr_W_hattingen)
  rv_time <- d$datetime[match(zr_Q[["Hattingen"]], d$zr_id)]

  # --- schon geloggt? dann nichts tun (verhindert Doppelte) ---
  if (file.exists(log_file)) {
    bisher <- read.csv(log_file, stringsAsFactors = FALSE)
    if (nrow(bisher) > 0 && rv_time %in% bisher$rv_time) {
      cat("Keine neuen Daten (RV-Stand", rv_time, ") — übersprungen.\n"); return(invisible("keine_neuen"))
    }
  }

  # --- Vorhersagen ---
  preds <- list()
  for (L in c(3, 6, 12)) {
    f <- file.path(model_dir, sprintf("korr_model_lead%dh.rds", L))
    preds[[paste0("pred_Q_", L, "h")]] <-
      if (file.exists(f) && !any(is.na(obs[names(zr_Q)]))) round(predict_korr(readRDS(f), obs), 2) else NA
  }

  # rv_time ist MEZ (UTC+1) -> zusätzlich eindeutig als UTC ablegen
  rv_utc <- format(as.POSIXct(rv_time, tz = "Etc/GMT-1"), "%Y-%m-%d %H:%M:%S", tz = "UTC")

  # Regime-Flag: ist der aktuelle Abfluss im Gültigkeitsbereich des Modells?
  # Begriffe an amtliche Hauptwerte angelehnt (frueher: niedrigwasser / hochwasser_relevant)
  regime <- if (is.na(obs$Hattingen)) "unbekannt" else if (obs$Hattingen >= Q_MIN_WARN) "ab_MQ" else "unter_MQ"

  row <- cbind(data.frame(run_time    = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),  # lokale Zeit
                          rv_time     = rv_time,                                  # MEZ, wie geliefert
                          rv_time_utc = rv_utc,                                   # eindeutig
                          regime      = regime,                                   # Betriebsregime
                          stringsAsFactors = FALSE),
               round(obs, 2), as.data.frame(preds))
  # Falls eine ältere Log-Datei mit anderer Spaltenstruktur existiert: wegsichern
  # und neu beginnen (verhindert eine zerschossene CSV).
  if (file.exists(log_file)) {
    alt <- read.csv(log_file, nrows = 1, stringsAsFactors = FALSE)
    if (!identical(names(alt), names(row))) {
      backup <- file.path(log_dir, format(Sys.time(), "live_log_alt_%Y%m%d_%H%M.csv"))
      file.rename(log_file, backup)
      cat("Hinweis: Log-Struktur geändert -> alte Datei gesichert als", basename(backup), "\n")
    }
  }
  write.table(row, log_file, sep = ",", row.names = FALSE,
              col.names = !file.exists(log_file), append = file.exists(log_file))

  cat("Geloggt | Regime:", regime, "| RV-Stand:", rv_time, "| Hattingen Q =", row$Hattingen, "m³/s, W =", row$Hattingen_W,
      "cm | Vorhersage +6h:", row$pred_Q_6h, "m³/s\n")
  invisible("ok")
}

# Ein Lauf beim Ausführen/Sourcen dieser Datei:
log_once()
