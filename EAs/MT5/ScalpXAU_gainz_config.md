# ScalpXAU — MT5 Gainz-Swing Deployment Config

Exact inputs applied to the attached ScalpXAU EA (chart inputs) on **both**
local and VPS MT5 terminals. Mirrors the cTrader `gainz_ft.cbotset` so the
MT5 version runs the **same trade logic as the ScalpXAU cBot**.

## Chart inputs (as written in the profile .chr `<inputs>` block)

```
EnableGainzSwing=true
Gainz_TP_Pips=159
Gainz_SL_Pips=322
Gainz_MaxHoldHours=11
Gainz_NoOvernight=true
Gainz_CutoffHour=22
Gainz_StartH=7
Gainz_EndH=21
Gainz_RiskPct=1.0
Gainz_EMA_Period=200
Gainz_CooldownHours=3

; legacy legs OFF
EnableAsian=false
EnableLondon=false
EnableNY=false
EnableTrend=false
```

## Shared guards (unchanged defaults)

```
MaxPositions=3
MaxTradesPerSess=40
MaxSessDDPct=5.0
MaxDailyRiskPct=5.0
RiskPerTradePct=1.0      ; Gainz uses Gainz_RiskPct (1.0)
MagicNumber=241107
```

## Gainz trade logic (identical in cBot and MT5)

- Signal on the last **closed H1** candle:
  - BUY: close > previous-day high **and** close > EMA200(H1)
  - SELL: close < previous-day low **and** close < EMA200(H1)
- SL 322 pips / TP 159 pips (hard SL/TP)
- Max hold 11h; no-overnight close at 22:00 GMT cutoff
- Entry window 07:00–21:00 GMT
- 3h cooldown after a Gainz exit; one swing position at a time;
  one entry attempt per H1 bar

## Deployment

| Terminal | Profile / chart | Status |
|---|---|---|
| VPS MT5 | Default `chart03.chr` (XAUUSD+ M5) | ✅ Gainz ON (since Aug 18) |
| Local MT5 | Euro `chart05.chr` (XAUUSD+ M5) | ✅ Gainz ON (since Aug 18) |
| cTrader (VPS) | `gainz_ft.cbotset` (demo #10096835) | config ready (bot attach pending) |
