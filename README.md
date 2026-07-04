# MATE Apex Scalper

Stealth scalping system for XAUUSD (Gold) on Vantage RAW ECN broker.

**Winning Config: TSL-HRR** — 0.4x ATR SL, 2:1 R:R, ADX >= 22

## Backtest Results (18 months, Feb 2025 - Jul 2026)

| Metric | Value |
|---|---|
| Return | +39.8% net ($199 on $500) |
| Profit Factor | 1.72 |
| Win Rate | 61.5% |
| Max DD | 5.6% |
| Trades | 475 |

## Files

| File | Description |
|---|---|
| `mate_scalper_pro.py` | Main backtest engine (~1300 lines) |
| `MATE_Apex_Scalper_Strategy_Development.pdf` | Full strategy document (16 sections) |
| `audit_comprehensive_report.txt` | Audit validation & optimization results |
| `audit_results.txt` | SL distance verification |
| `apex_optimizer.py` | Multi-config optimization script |
| `run_backtest.py` | Quick backtest runner |

## Quick Start

```bash
python mate_scalper_pro.py --quick
```

## Requirements

- Python 3.10+
- Dependencies: `pip install -r requirements.txt`
- MT5 account (Vantage RAW ECN or equivalent)
