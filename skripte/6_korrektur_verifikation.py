#!/usr/bin/env python3
# ============================================================================
# Fehlerfortschreibung + Trefferpruefung fuer die Korrelationsvorhersage.
# Laeuft NACH 5_export_web.R (lokal oder im GitHub-Workflow) und ergaenzt live.json.
# Nur Python-Standardbibliothek (keine Zusatzpakete). Faellt dieser Schritt aus,
# bleibt die unkorrigierte live.json aus dem R-Export unveraendert stehen.
#
# Fehlerfortschreibung: zur Zeit t ist der Fehler der +3-h-Vorhersage von t-3h bekannt:
#   e3 = Q_beob(t) - Vorhersage_3h(t-3h)
# Er wird auf die neuen Vorhersagen angerechnet:  Q_korr(L) = Q_roh(L) + beta_L * e3,
# begrenzt auf +-kappung_rel * Q_roh. beta aus korr_fehler.csv (1_kalibrierung.R),
# historisch geprueft 2019-2024 ab MQ: Fehler -28 % (+3 h), -20 % (+6 h), -11 % (+12 h).
#
# Pfade wie im Export per Umgebungsvariablen (HW_LOG_DIR, HW_MODEL_DIR, HW_RATING, HW_OUT).
# ============================================================================
import csv, json, os, sys
from datetime import datetime, timedelta

LOG = os.path.join(os.environ.get("HW_LOG_DIR", "07_Live"), "live_log.csv")
MODEL_DIR = os.environ.get("HW_MODEL_DIR", "06_Code")
RATING = os.environ.get("HW_RATING", "03_Results/rating_Hattingen_pre_post.csv")
OUT = os.environ.get("HW_OUT", "09_Website/data/live.json")
Q_MIN_WARN = 70.0
LEADS = (3, 6, 12)
VERIF_TAGE = 30


def zahl(x):
    try:
        v = float(x)
        return v if v == v else None          # NaN -> None
    except (TypeError, ValueError):
        return None


def lies_csv(pfad):
    with open(pfad, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


# --- Abflusskurve Q -> W (Post-2021), linear, an den Raendern konstant ---
rk = [(zahl(r["Q_center"]), zahl(r["W_post"])) for r in lies_csv(RATING)]
rk = sorted((q, w) for q, w in rk if q is not None and w is not None)


def q_zu_w(q):
    if q is None:
        return None
    if q <= rk[0][0]:
        return rk[0][1]
    for (q0, w0), (q1, w1) in zip(rk, rk[1:]):
        if q <= q1:
            return w0 + (w1 - w0) * (q - q0) / (q1 - q0)
    return rk[-1][1]


# --- Band (korr_band.csv) und Korrekturfaktoren (korr_fehler.csv) ---
band = lies_csv(os.path.join(MODEL_DIR, "korr_band.csv"))


def band_fak(q, lead):
    if q is None:
        return None, None
    for b in band:
        if int(float(b["lead"])) != lead:
            continue
        von = zahl(b["q_von"]); bis = zahl(b["q_bis"])
        if q >= von and (bis is None or q < bis):
            return zahl(b["f_lo"]), zahl(b["f_hi"])
    return None, None


kf = {int(float(r["lead"])): (zahl(r["beta"]), zahl(r.get("kappung_rel")) or 0.2)
      for r in lies_csv(os.path.join(MODEL_DIR, "korr_fehler.csv"))}


def korrektur(q, lead, e):
    if q is None or e is None or lead not in kf or kf[lead][0] is None:
        return 0.0
    beta, kapp = kf[lead]
    lim = kapp * abs(q)
    return max(-lim, min(lim, beta * e))


# --- Log einlesen (Zeitstempel MEZ, stuendlich) ---
zeilen = []
for r in lies_csv(LOG):
    try:
        t = datetime.strptime(r["rv_time"], "%Y-%m-%d %H:%M:%S")
    except (KeyError, ValueError):
        continue
    zeilen.append(dict(t=t, Q=zahl(r.get("Hattingen")), W=zahl(r.get("Hattingen_W")),
                       p={L: zahl(r.get(f"pred_Q_{L}h")) for L in LEADS}))
zeilen.sort(key=lambda z: z["t"])
nach_t = {z["t"]: z for z in zeilen}


def fehler3(t):
    jetzt, vor = nach_t.get(t), nach_t.get(t - timedelta(hours=3))
    if not jetzt or not vor or jetzt["Q"] is None or vor["p"][3] is None:
        return None
    return jetzt["Q"] - vor["p"][3]


if not zeilen:
    sys.exit("Log leer - nichts zu tun.")

# --- 1) Aktuelle Vorhersage korrigieren ---
with open(OUT, encoding="utf-8") as f:
    live = json.load(f)
F = live.get("forecast", {})
letzte = zeilen[-1]
e3 = fehler3(letzte["t"])
q_roh = [letzte["p"][L] for L in LEADS]
korr = [korrektur(q, L, e3) for q, L in zip(q_roh, LEADS)]
q_k = [None if q is None else q + k for q, k in zip(q_roh, korr)]
lo, hi = [], []
for q, L in zip(q_k, LEADS):
    a, b = band_fak(q, L)
    lo.append(None if a is None or q is None else max(0.0, q * a))
    hi.append(None if b is None or q is None else q * b)
F.update(Q_roh=q_roh, W_roh=[q_zu_w(q) for q in q_roh], korrektur=korr, fehler3=e3,
         Q=q_k, Q_lo=lo, Q_hi=hi, W=[q_zu_w(q) for q in q_k],
         W_lo=[q_zu_w(q) for q in lo], W_hi=[q_zu_w(q) for q in hi],
         methode="Korrelationsmodell + Fehlerfortschreibung (3-h-Fehler), 90-%-Band abflussabhaengig")
live["forecast"] = F

# --- 2) Trefferpruefung der letzten Tage (roh vs. korrigiert) ---
grenze = letzte["t"] - timedelta(days=VERIF_TAGE)
verif = []
for L in LEADS:
    paare = {"alle": [], "ab_MQ": []}
    for z in zeilen:
        if z["t"] < grenze or z["p"][L] is None:
            continue
        ziel = nach_t.get(z["t"] + timedelta(hours=L))
        if not ziel or ziel["Q"] is None:
            continue
        roh = z["p"][L]
        kor = roh + korrektur(roh, L, fehler3(z["t"]))
        a, b = band_fak(kor, L)
        drin = None if a is None else (kor * a <= ziel["Q"] <= kor * b)
        eintrag = (roh, kor, ziel["Q"], ziel["W"], drin)
        paare["alle"].append(eintrag)
        if z["Q"] is not None and z["Q"] >= Q_MIN_WARN:
            paare["ab_MQ"].append(eintrag)
    for bereich, p in paare.items():
        n = len(p)
        if n == 0:
            verif.append(dict(lead=L, bereich=bereich, n=0)); continue
        def mittel(xs):
            xs = [x for x in xs if x is not None]
            return sum(xs) / len(xs) if xs else None
        cm = lambda q, w: None if w is None else abs(q_zu_w(q) - w)
        treffer = [d for *_, d in p if d is not None]
        verif.append(dict(
            lead=L, bereich=bereich, n=n,
            mae_roh_q=mittel([abs(r - o) for r, k, o, w, d in p]),
            mae_korr_q=mittel([abs(k - o) for r, k, o, w, d in p]),
            mae_roh_cm=mittel([cm(r, w) for r, k, o, w, d in p]),
            mae_korr_cm=mittel([cm(k, w) for r, k, o, w, d in p]),
            bias_korr_cm=mittel([None if w is None else q_zu_w(k) - w for r, k, o, w, d in p]),
            band_treffer_pct=(100.0 * sum(treffer) / len(treffer)) if treffer else None))
live["verifikation"] = dict(tage=VERIF_TAGE, stand=letzte["t"].strftime("%Y-%m-%dT%H:%M:%S+01:00"), zeilen=verif)

with open(OUT, "w", encoding="utf-8") as f:
    json.dump(live, f, ensure_ascii=False, separators=(",", ":"))
print(f"Korrektur: e3={e3} -> {[round(k, 2) for k in korr]} m3/s | Trefferpruefung: "
      + ", ".join(f"+{v['lead']}h/{v['bereich']} n={v['n']}" for v in verif))
