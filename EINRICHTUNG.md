# Einrichtung – Pegel-Logger in der Cloud (GitHub Actions)

Danach läuft der Logger **ohne eigenen Rechner**: zweimal pro Stunde (:17/:47) Ruhrverband abrufen,
Log fortschreiben, `live.json` für die Website erzeugen, committen.

## 1. Repo auf GitHub anlegen
1. Auf github.com einloggen → **New repository**.
2. Name: `hw-dahlhausen-daten` · **Public** (sonst kann die Website die Daten nicht ohne Passwort lesen,
   und Actions-Minuten wären begrenzt) · **ohne** README/.gitignore anlegen (leer lassen).

## 2. Anmeldung für den Push (einmalig)
Workflow-Dateien dürfen nur mit **workflow-Berechtigung** hochgeladen werden. Einfachster Weg:
- **GitHub CLI**: im Terminal `brew install gh`, dann `gh auth login` (GitHub.com → HTTPS → im Browser bestätigen).
  Die nötigen Rechte inkl. *workflow* werden dabei vergeben.
- Alternativ ein *Personal Access Token (classic)* mit den Häkchen **repo** und **workflow**; beim Push als Passwort eingeben.

## 3. Ordner hochladen
Terminal öffnen, `cd ` tippen und den Ordner **10_Webdaten** aus dem Finder ins Fenster ziehen, Enter. Dann:
```
git init -b main
git add .
git commit -m "Start: Logger-Workflow und bisherige Daten"
git remote add origin https://github.com/<DEIN-NAME>/hw-dahlhausen-daten.git
git push -u origin main
```
(`git add .` nimmt auch den versteckten Ordner `.github` mit – der ist im Finder unsichtbar, aber da.)

## 4. Ersten Lauf von Hand starten und prüfen
1. Im Repo auf **Actions** → links **Pegel-Logger** → **Run workflow**.
2. Nach ~1–2 min den Lauf öffnen → Schritt *Logger + Web-Export*. Erwartet:
   - `Geloggt | Regime: ...` **oder** `Keine neuen Daten` → alles gut.
   - `Abruf fehlgeschlagen` → der Ruhrverband lässt Abrufe von GitHub-Servern evtl. nicht zu → **melden**, dann Plan B.
3. Schlägt *Daten committen* mit `403` fehl: Repo → **Settings → Actions → General → Workflow permissions →
   Read and write permissions** → Save, Lauf wiederholen.
4. Kontrolle im Browser: `https://raw.githubusercontent.com/<DEIN-NAME>/hw-dahlhausen-daten/main/status.json`

## 5. Website umstellen
In `09_Website/config.js`:
```
DATA_URL: "https://raw.githubusercontent.com/<DEIN-NAME>/hw-dahlhausen-daten/main/live.json",
```
→ `09_Website` einmal neu auf Netlify ziehen. Fertig.

## 6. Betriebsregeln
- **Nur EIN Logger**: lokalen Dauerlauf (`4_logger_dauerlauf.R`) stoppen, sonst zwei Quellen.
- Lokale Kopie der Cloud-Daten holen: im Ordner `10_Webdaten` → `git pull`.
- Änderungen an `06_Code/3_logger.R` / `5_export_web.R` oder an den Modellen: nach `10_Webdaten/skripte`
  bzw. `modelle/` kopieren, committen, pushen (die Dateien sind identisch, nur die Pfade kommen aus dem Workflow).
- `run_time` im Log ist in der Cloud **UTC** (GitHub-Rechner); maßgeblich ist ohnehin `rv_time` (MEZ).

## Ehrliche Grenzen
- GitHub garantiert die Startzeit nicht: Verzögerungen, selten ausgelassene Läufe. Für Anzeige/Testphase ok,
  **nicht** als alleinige Grundlage für zeitkritische Alarmierung → später eigener Server (Projektdoku, Architektur B).
- Öffentliche Repos: zeitgesteuerte Workflows werden nach 60 Tagen ohne Commit abgeschaltet. Unser Workflow
  committet jedes Mal `status.json` → bleibt aktiv. Läuft er trotzdem nicht: Website zeigt rotes Datenalter.
- Repo öffentlich → Ruhrverband-Daten + eigene Vorhersage öffentlich abrufbar (R19).
