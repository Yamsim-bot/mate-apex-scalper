# Freebuff Desktop — trading workspace

Algo-trading project for **MetaTrader 5 (MQL5)** and **cTrader (C#)**, with deployment tooling for a remote Windows VPS running MT5.

> ⚠️ This folder (`Documents/cTrader`) is **one part** of the setup. The **live MT5 production EAs live in `C:\Users\Jamie\Documents\EAs\MT5`** — every deploy/compile script in `scripts/` reads from that folder, not from here. Keep them in sync deliberately.

## Layout

```
cTrader/
├── EAs/
│   ├── MT5/            Archive/reference copy of MT5 EAs & indicators (.mq5)
│   │                   NOTE: not the live sources — those are in Documents\EAs\MT5
│   └── cTrader/        The 3 real cTrader bots (.cs):
│                       - PriceActionPatterns.cs        (candlestick pattern entries)
│                       - SupportResistance.cs          (level-based entries)
│                       - FixedRangeVolumeProfile.cs    (volume-profile entries)
├── Templates/          cTrader strategy templates (.tp): Range, Trend, Volatility
├── Journals/           Trading journals
│   └── Spotware/       e.g. Journal-2026-08.txt (live cTrader trade log)
├── FreightCourse/      Self-paced freight (shipping rates) course — new project:
│                       BDI/FFA learning path in 4 modules (lessons 01–07 +
│                       glossary + exercises). See FreightCourse/README.md
├── scripts/            Ops toolbox (150+ files):
│                       - compile_* / inline_*  → build self-contained EAs
│                       - deploy_* / upload_*   → push EAs + includes to the VPS via SFTP
│                       - vps_*                → probe/manage the remote MT5 terminal
│                       - mt5_keepalive*       → keep the terminal alive
│                       - send_*_tg.py         → Telegram notifications
├── logs/               Local run artifacts (keepalive, dedup logs)
├── .freebuff/          Internal tool state (project-id)
└── lern-deutsch/       Empty — placeholder, unrelated to trading
```

## How the pieces connect

1. **Strategy idea** → expressed as a cTrader `Template/*.tp` or an MT5 EA in `Documents\EAs\MT5`.
2. **Code** → cTrader bots in `EAs/cTrader/`; MT5 bots live in `Documents\EAs\MT5` (`.mq5` + shared `.mqh` includes).
3. **Results** → real trades land in `Journals/Spotware/`.
4. **Operations** → `scripts/` compiles, deploys to the VPS, and keeps the remote MT5 running.
5. **Learning** → `FreightCourse/` is a standalone self-paced course on the freight market (concepts → Baltic indices → FFA), reusing the same Templates and journaling habits as the trading side.

## Security warning

Several `scripts/*.py` contain **hard-coded live VPS credentials** (IP, SSH password) in plaintext. Nothing in this workspace is tracked by git (`git ls-files` is empty), which limits exposure — but moving credentials to environment variables or an untracked `.env` is strongly recommended before this is ever versioned or shared.

## Reorganizing? Check first

Before moving files, grep the scripts: they reference absolute paths such as
`C:\Users\Jamie\Documents\EAs\MT5` and the MT5 terminal data folder
`...\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts`.
Changing those paths requires updating every script that hard-codes them.
