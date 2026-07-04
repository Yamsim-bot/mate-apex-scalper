#!/usr/bin/env python3
"""Validate audit findings against TSL-HRR backtest"""
import os, pickle, sys
sys.path.insert(0, 'C:/Users/Jamie/Documents')
from mate_scalper_pro import ScalperConfig, run_scalper_backtest

out = open('C:/Users/Jamie/Documents/audit_results.txt', 'w', buffering=1)
def log(msg):
    out.write(str(msg) + '\n')
    out.flush()

# Load data
with open(os.path.expanduser('~/.computed_data.pkl'), 'rb') as f:
    d = pickle.load(f)
df5, df15 = d['df5'], d['df15']

# TSL-HRR config
c = ScalperConfig()
c.adx_threshold = 22; c.min_pillars = 2; c.use_di_filter = True
c.fib_sl_mult = 0.4; c.fib_tp_mult = 2.0; c.rr_target = 2.0
c.risk_pct = 1.0; c.use_breakeven = True; c.use_news_filter = False
c.initial_capital = 500.0

r = run_scalper_backtest(df5, df15, c, None)
trades = r.trades
PIP = 0.01

# === SL DISTANCE ANALYSIS ===
loss_trades = [t for t in trades if t.exit_reason == 'SL']
win_trades = [t for t in trades if t.exit_reason == 'TP']
be_trades = [t for t in trades if t.exit_reason == 'BE']

log("=== SL DISTANCE VERIFICATION ===")
log(f"Total trades: {len(trades)}")
log(f"SL'd out: {len(loss_trades)}")
log(f"TP'd out: {len(win_trades)}")
log(f"BE'd out: {len(be_trades)}")
log("")

# For SL trades: actual exit vs entry distance
sl_distances = []
for t in loss_trades:
    dist = abs(t.entry_price - t.exit_price) / PIP
    sl_distances.append(dist)

avg_sl_dist = sum(sl_distances)/len(sl_distances)
log(f"SL TRADES - actual exit distance from entry:")
log(f"  avg: {avg_sl_dist:.1f} pips")
log(f"  min: {min(sl_distances):.1f} pips")
log(f"  max: {max(sl_distances):.1f} pips")
log(f"  dollar at 0.01 lots: ${avg_sl_dist*0.1:.2f}")
log("")

# For TP trades
tp_distances = []
for t in win_trades:
    dist = abs(t.entry_price - t.exit_price) / PIP
    tp_distances.append(dist)
avg_tp_dist = sum(tp_distances)/len(tp_distances)
log(f"TP TRADES - actual exit distance from entry:")
log(f"  avg: {avg_tp_dist:.1f} pips")
log("")

# SET SL vs actual SL
sl_set = []
for t in trades[:min(200, len(trades))]:
    sl_set.append(abs(t.entry_price - t.stop_loss) / PIP)
avg_sl_set = sum(sl_set)/len(sl_set)
log(f"SET SL (from stop_loss field):")
log(f"  avg: {avg_sl_set:.1f} pips")
log(f"  RATIO: actual_exit_dist / set_sl = {avg_sl_dist/avg_sl_set:.2f}x")
log("")

# Avg loss dollar
loss_pnls = [t.net_pnl + t.partial_pnl for t in loss_trades]
avg_loss_dollar = abs(sum(loss_pnls)/len(loss_pnls))
win_pnls = [t.net_pnl + t.partial_pnl for t in win_trades]
avg_win_dollar = sum(win_pnls)/len(win_pnls)
log(f"Avg loss (dollar): ${avg_loss_dollar:.2f}")
log(f"Avg win (dollar): ${avg_win_dollar:.2f}")
log(f"Realized R:R: {avg_win_dollar/avg_loss_dollar:.2f}")
log("")

# ATR check
atr14 = df5['atr14'].dropna()
log(f"M5 ATR(14) median: ${atr14.median():.2f}")
log(f"0.4x ATR median: ${atr14.median()*0.4:.2f}")
log(f"0.4x ATR in pips: {atr14.median()*0.4/PIP:.1f}")
log("")

# === PROFIT CONCENTRATION ===
monthly = {}
for t in trades:
    m = t.entry_time.strftime('%Y-%m')
    if m not in monthly:
        monthly[m] = {'trades': 0, 'pnl': 0.0}
    monthly[m]['trades'] += 1
    pnl = t.net_pnl + t.partial_pnl
    monthly[m]['pnl'] += pnl

total_pnl = sum(v['pnl'] for v in monthly.values())
sorted_m = sorted(monthly.values(), key=lambda x: x['pnl'], reverse=True)
top2 = sorted_m[:2]
top2_pnl = sum(v['pnl'] for v in top2)
log("=== PROFIT CONCENTRATION ===")
log(f"Total gross PnL: ${total_pnl:.2f}")
log(f"Top 2 months: ${top2_pnl:.2f} ({top2_pnl/total_pnl*100:.1f}%)")
log("")

# All months
log(f"{'Month':<8} {'Trades':>6} {'PnL':>10}")
for m in sorted(monthly.keys()):
    d = monthly[m]
    log(f"{m:<8} {d['trades']:>6} ${d['pnl']:>+7.2f}")
log(f"{'TOTAL':<8} {sum(v['trades'] for v in monthly.values()):>6} ${total_pnl:>+7.2f}")
log("")

# === LOT SIZING CHECK ===
avg_lots = sum(t.lots_at_open for t in trades) / len(trades)
log("=== LOT SIZING ===")
log(f"Avg lots: {avg_lots:.4f}")
log(f"Avg lots / 0.01: {avg_lots/0.01:.0f}x micro lots")
log(f"Commission/trade at avg lots: ${avg_lots*6:.2f} (6/RT)")
log(f"Total commission est: ${sum(t.lots_at_open for t in trades)*6:.2f}")
total_costs = sum(t.broker_costs for t in trades)
log(f"Total broker costs: ${total_costs:.2f}")
log(f"Costs as % of gross PnL: {total_costs/total_pnl*100:.1f}%")
log("")

# Final summary
log("=== AUDIT SUMMARY ===")
log(f"1. SL dist (set):  {avg_sl_set:.1f} pips vs 0.4x ATR = {atr14.median()*0.4/PIP:.1f} pips")
log(f"2. SL dist (exec): {avg_sl_dist:.1f} pips vs 0.4x ATR = {atr14.median()*0.4/PIP:.1f} pips")
log(f"3. Realized R:R:   {avg_win_dollar/avg_loss_dollar:.2f}:1 vs expected 2:1")
log(f"4. Profit conc:    {top2_pnl/total_pnl*100:.1f}% in 2 months")
log(f"5. Avg lots:       {avg_lots:.4f}")
log(f"6. Broker cost %:  {total_costs/total_pnl*100:.1f}% of gross")
log(f"7. Win rate:       {len([t for t in trades if t.net_pnl+t.partial_pnl>0])/len(trades)*100:.1f}%")
log("")
log("=== END OF AUDIT ===")
out.close()
