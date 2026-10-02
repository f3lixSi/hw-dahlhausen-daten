# ============================================================================
# Ein Cloud-Lauf (GitHub Actions): Ruhrverband abrufen -> Log fortschreiben ->
# live.json exportieren -> status.json schreiben (Kontrolle + haelt Workflow aktiv).
# Pfade kommen aus den Umgebungsvariablen im Workflow (HW_*).
# ============================================================================
suppressMessages(library(jsonlite))
t0 <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

status <- tryCatch(source("skripte/3_logger.R", local = new.env())$value,
                   error = function(e) paste("fehler:", conditionMessage(e)))
export <- tryCatch({ source("skripte/5_export_web.R", local = new.env()); "ok" },
                   error = function(e) paste("fehler:", conditionMessage(e)))

log_file <- file.path(Sys.getenv("HW_LOG_DIR", "daten"), "live_log.csv")
letzter <- if (file.exists(log_file)) tail(read.csv(log_file, stringsAsFactors = FALSE)$rv_time, 1) else NA

write_json(list(lauf_utc = t0, logger = status, export = export,
                letzter_ruhrverband_stand_mez = letzter),
           "status.json", auto_unbox = TRUE, pretty = TRUE)
cat("Lauf", t0, "| Logger:", status, "| Export:", export, "| letzter RV-Stand:", letzter, "\n")
