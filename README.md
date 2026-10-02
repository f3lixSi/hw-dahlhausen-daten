# hw-dahlhausen-daten

Daten-Repo der Hochwasser-Frühwarnung DLRG-Wache Bochum-Dahlhausen. **Keine amtliche Warnung.**

Ein GitHub-Actions-Workflow ruft zweimal pro Stunde die Ruhrverband-Pegel ab, schreibt
`daten/live_log.csv` fort, berechnet die Korrelations-Vorhersage und exportiert `live.json`
für die Website. `status.json` zeigt den letzten Lauf.

| Pfad | Inhalt |
|---|---|
| `.github/workflows/logger.yml` | Zeitplan + Ablauf |
| `skripte/` | `run.R` (ein Lauf), `3_logger.R`, `5_export_web.R` (identisch zu `06_Code/` im Projekt) |
| `modelle/` | Korrelationsmodelle (+3/6/12 h), Abflusskurve Hattingen |
| `daten/live_log.csv` | fortlaufendes Log |
| `live.json` | Datei, die die Website liest |
| `status.json` | letzter Lauf: Zeit, Ergebnis, letzter Ruhrverband-Stand |

Quelle Pegeldaten: Ruhrverband / Talsperrenleitzentrale Ruhr (Angaben ohne Gewähr).
