# Externer Taktgeber – Logger zuverlässig alle 30 Minuten starten

**Warum:** GitHubs eigener Zeitplan (`schedule`) wird bei kleinen öffentlichen Repos stark verzögert
oder ausgelassen (bei uns: 6 h bis zum ersten Lauf). Ein externer Cron-Dienst startet den Workflow
stattdessen über die GitHub-Schnittstelle – genau wie der Knopf „Run workflow“. Der GitHub-Zeitplan
bleibt als Reserve aktiv; doppelte Läufe sind harmlos (Logger verwirft doppelte Zeitstempel).

## 1. Zugangstoken (nur für dieses Repo, nur zum Starten von Workflows)
GitHub → Profilbild → **Settings** → **Developer settings** → **Personal access tokens** →
**Fine-grained tokens** → **Generate new token**
- Name: `hw-logger-taktgeber`
- Expiration: max. 1 Jahr (Ablaufdatum notieren!)
- Repository access: **Only select repositories** → `hw-dahlhausen-daten`
- Permissions → Repository permissions → **Actions: Read and write** (sonst nichts)
- **Generate token** → Token kopieren (wird nur einmal angezeigt)

Das Token kann nur Workflows in diesem einen Repo starten – keinen Code ändern, keine anderen Repos.

## 2. Einmal im Terminal testen
`DEIN-TOKEN` ersetzen:
```
curl -i -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer DEIN-TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/f3lixSi/hw-dahlhausen-daten/actions/workflows/logger.yml/dispatches \
  -d '{"ref":"main"}'
```
Erwartet: **`HTTP/2 204`** und unter *Actions* ein neuer Lauf „Pegel-Logger … Manually run“.
`401/403` = Token/Rechte falsch, `404` = Repo- oder Dateiname falsch.

## 3. cron-job.org einrichten (kostenlos)
Konto anlegen → **Cronjobs** → **Create cronjob**
- Title: `HW Pegel-Logger`
- URL: `https://api.github.com/repos/f3lixSi/hw-dahlhausen-daten/actions/workflows/logger.yml/dispatches`
- Ausführung: benutzerdefiniert → Minuten **17 und 47**, jede Stunde, jeden Tag
- Reiter **Advanced**:
  - Request method: **POST**
  - Headers (vier Einträge):
    - `Accept` = `application/vnd.github+json`
    - `Authorization` = `Bearer DEIN-TOKEN`
    - `X-GitHub-Api-Version` = `2022-11-28`
    - `Content-Type` = `application/json` (schlägt cron-job.org selbst vor)
  - Request body: `{"ref":"main"}`
- Benachrichtigung bei Fehlschlag einschalten → **Create**
- Mit **Test run** prüfen: Antwort **204** = richtig.

## Kontrolle danach
- *Actions*: alle 30 min ein Lauf „workflow_dispatch“.
- Website: Datenalter-Kachel grün (< 2 h).
- **Token läuft ab am 01.10.2027** (Test 02.10.2026: HTTP 204 ok) → vorher neues erzeugen und bei cron-job.org ersetzen.
- **API-Version `2022-11-28` ist abgekündigt, Abschaltung 10.03.2028** → beim Token-Wechsel den Header `X-GitHub-Api-Version` auf die dann aktuelle Version setzen (siehe docs.github.com, REST API versions).
