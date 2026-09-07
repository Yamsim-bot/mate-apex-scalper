# Forward-Test Monitoring — 4 Fixed EAs, Demo #25518022

Account: **25518022 (VantageMarkets-Demo)** · Telegram: chat `457995870`, tag reports `📱 MT5`.
Scope: READ-ONLY monitoring. Do not modify EAs, sets, schedules, or terminal config.

## 1. The 4 EAs under test (Conservative sets = live)

| EA | Magic | Pair / TF | Daily kill-switch (Conservative .set) |
|---|---|---|---|
| FXYAMS_Ultimate1 | `20260716` | XAUUSD+ M5 | `MaxDailyLossPct=2.5`, `MaxDailyTrades=10`, `MaxTPHits=3` |
| FXRE_Hybrid_EA v2.01 | `20241201` | XAUUSD+ M5 | `MaxDailyLossPct=1.5`, `MaxDailyTrades=5`, `MaxTPHits=2` |
| FXPair_EA | `20260723` | EURUSD+ M5 | `MaxDailyLossPct=2.5`, `MaxDailyTrades=10`, `MaxTPHits=2` |
| ScalpXAU | `241107` | XAUUSD+ M5 | `MaxDailyRiskPct=1.0`, `MaxSessDDPct=0.75`, `MaxTradesPerSess=2` |

Risk per trade 0.25% on all four. Sets: `EAs/MT5/Profiles/*_Conservative.set`.
Session split (same account on both terminals): Local = London 07:00–16:00 UTC,
VPS = NY 16:00–21:00 UTC; ScalpXAU Gainz Local 07:00–14:00 / VPS 14:00–21:00 GMT.

## 2. Daily watch checklist

1. **Per-EA P/L** — run `check_local_performance.py` (command below). Compare each
   magic's `Total P/L` vs prior day. Any EA past its daily loss % above = kill-switch
   breach → disable that EA (manual, in terminal).
2. **TP-pause log check** — each EA pauses entries after N TPs per session
   (`TP HIT #x/y`, then `TP PAUSE`). If an EA keeps trading after `TP PAUSE` in the
   Experts log, the pause logic is broken → disable and report.
3. **.ex5 timestamps** — VPS `...\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\`
   must show all 4 `.ex5` newer than their `.mq5`. Stale/missing `.ex5` after a
   terminal auto-update = EAs silently detached (see §5).
4. **Report tasks** — VPS `EA_*_Report` Next Run in future + Last Result `0` +
   fresh file in `C:\Users\Administrator\Documents\ea_reports\`. Anything else = broken (§4).

## 3. Exact commands (run from local PC)

```powershell
# Per-magic P/L, last 30 days, account 25518022 (needs local MT5 running)
python "C:\Users\Jamie\Documents\cTrader\scripts\check_local_performance.py"

# VPS status: MT5 process? .ex5 present? journal/expert-log tail?
# NOTE: currently FALSE-NEGATIVES on .ex5/journal (see §4) — verify via raw probe:
python "C:\Users\Jamie\Documents\cTrader\scripts\check_vps_ea_perf.py"

# Local scheduled tasks (expect MT5KeepAlivePeriodic only — NO local EA report tasks exist)
schtasks /query /tn MT5KeepAlivePeriodic /v /fo LIST

# VPS report tasks health (Last Result must be 0; check ea_reports\ non-empty)
# via SSH to 77.111.104.7:  schtasks /query /tn EA_Daily_Report /v /fo LIST
# (repeat for EA_Asian_Report, EA_London_Report, EA_NY_Report, EA_Weekly_Report)

# One-shot Telegram snapshot (hardcoded text — EDIT message body before sending)
python "C:\Users\Jamie\Documents\cTrader\scripts\send_ea_performance_tg.py"
```

## 4. Known-broken reporting (2026-09-06, do NOT trust blindly)

- **VPS `EA_*_Report` tasks fire but fail**: `EA_Daily/London/Weekly_Report` show
  `Last Result: 1`, and `C:\Users\Administrator\Documents\ea_reports\` is **empty**
  (no logs ever written). Reports are likely NOT reaching Telegram. Needs fix
  (not in monitoring scope).
- **`check_vps_ea_perf.py` false negatives**: prints `NO .ex5 files found!` and empty
  journal/logs, yet all 4 `.ex5` exist on VPS (FXPair 9/5 17:38, FXYAMS 9/5 17:37,
  ScalpXAU 9/5 17:47, FXRE 9/5 18:00). Its `dir /b ... 2>nul` quoting fails over SSH,
  and it reports **no per-magic P/L at all**.
- **`check_local_performance.py` stale MAGIC_MAP**: live magics `20241201/20260716/`
  `20260723/241107` are unmapped, so EAs print as `Magic:xxx` instead of names.
  Numbers are correct, labels are not.
- **Local `MT5KeepAlivePeriodic` broken**: points to
  `Documents\cTrader\mt5_keepalive_periodic.ps1` (does not exist; real file is under
  `scripts\`), Last Result `-196608`, keep-alive log stale since 2026-08-20
  (`MT5 FAILED to start`). The periodic script itself references
  `Documents\cTrader\mt5_keepalive.ps1` (also wrong path). Local MT5 watchdog is
  effectively dead.
- **`send_ea_performance_tg.py` is a hardcoded Sep-5 snapshot**, scheduled nowhere.
  Manual use only.
- **Local canonical dir**: only `FXRE_Hybrid_EA.ex5` + `FXYAMS_Ultimate1.ex5` present
  (2026-09-06 00:2x); `FXPair_EA.ex5` / `ScalpXAU.ex5` compile artifacts absent locally.

## 5. Manual reattach checklist (fresh MT5 build wipes chart EAs)

1. RDP/SSH to terminal, confirm `terminal64.exe` running.
2. In MetaEditor: open each of the 4 `.mq5` from canonical `EAs/MT5/`, press **F7**;
   confirm 0 errors and fresh `.ex5` timestamp > `.mq5`.
3. Re-apply chart profile / drag each EA onto its chart + timeframe; check RS
   smiley-face + **Algo Trading** toolbar button ON.
4. Verify inputs match `*_Conservative.set` (magic, risk %, session hours).
5. Experts log must show `Risk: ... | Max DD: ...` init lines and no `TP PAUSE`
   anomalies; run `check_local_performance.py` next day to confirm new deals per magic.
