#!/usr/bin/env python3
"""Run TSL-HRR backtest and print detailed results"""
import sys, os, pickle
sys.path.insert(0, 'C:/Users/Jamie/Documents')
from mate_scalper_pro import ScalperConfig, run_scalper_backtest

with open(os.path.expanduser('~/.computed_data.pkl'), 'rb') as f:
    d = pickle.load(f)

c = ScalperConfig()
c.adx_threshold = 22; c.min_pillars = 2; c.use_di_filter = True
c.fib_sl_mult = 0.4; c.fib_tp_mult = 2.0; c.rr_target = 2.0
c.risk_pct = 1.0; c.use_breakeven = True; c.use_news_filter = False
c.initial_capital = 500.0

print('Running TSL-HRR backtest...')
r = run_scalper_backtest(d['df5'], d['df15'], c, None)
t = r.trades
g = sum(x.net_pnl + x.partial_pnl for x in t)
cst = sum(x.broker_costs for x in t)
wn = [x for x in t if x.net_pnl + x.partial_pnl > 0]
ls = [x for x in t if x.net_pnl + x.partial_pnl <= 0]
pf = abs(sum(x.net_pnl + x.partial_pnl for x in wn)) / abs(sum(x.net_pnl + x.partial_pnl for x in ls))
cum, peak, dd = 0, 0, 0
for x in t:
    cum += x.net_pnl + x.partial_pnl
    peak = max(peak, cum)
    dd = max(dd, peak - cum)

avg_win = sum(x.net_pnl + x.partial_pnl for x in wn) / len(wn)
avg_loss = abs(sum(x.net_pnl + x.partial_pnl for x in ls) / len(ls))
sl_t = len([x for x in t if x.exit_reason == 'SL'])
tp_t = len([x for x in t if x.exit_reason == 'TP'])
be_t = len([x for x in t if x.exit_reason == 'BE'])

print()
print('='*60)
print('  MATE APEX SCALPER - TSL-HRR BACKTEST RESULTS')
print('  XAUUSD | Vantage RAW ECN | $500 Capital')
print('='*60)
print(f'  Period: Feb 2025 - Jul 2026 (100,000 M5 bars)')
print()
print(f'  TRADES:        {len(t)}')
print(f'  WIN RATE:      {len(wn)/len(t)*100:.1f}%  ({len(wn)}W / {len(ls)}L)')
print(f'  GROSS PNL:     +${g:.2f}')
print(f'  BROKER COSTS:  ${cst:.2f}')
print(f'  NET PNL:       +${g-cst:.2f}')
print(f'  RETURN:        {(g-cst)/500*100:.1f}%')
print(f'  PROFIT FACTOR: {pf:.2f}')
print(f'  MAX DD:        ${dd:.2f} ({dd/500*100:.1f}%)')
print(f'  AVG WIN:       +${avg_win:.2f}')
print(f'  AVG LOSS:      -${avg_loss:.2f}')
print(f'  REALIZED R:R:  {avg_win/avg_loss:.2f}:1')
print(f'  SL DIST SET:   {abs(t[0].entry_price - t[0].stop_loss)/0.01:.1f} pips (avg)')
print()
print(f'  EXITS:  SL={sl_t} ({sl_t/len(t)*100:.0f}%)')
print(f'          TP={tp_t} ({tp_t/len(t)*100:.0f}%)')
print(f'          BE={be_t} ({be_t/len(t)*100:.0f}%)')
print()

# Monthly breakdown
print(f'  MONTHLY PNL:')
monthly = {}
monthly_cnt = {}
for x in t:
    m = x.entry_time.strftime('%Y-%m')
    monthly.setdefault(m, 0)
    monthly[m] += x.net_pnl + x.partial_pnl
    monthly_cnt.setdefault(m, 0)
    monthly_cnt[m] += 1
print(f'  {"Month":<8} {"PnL":>10} {"Trades":>7}')
print(f'  {"-"*27}')
for m in sorted(monthly.keys()):
    print(f'  {m:<8} ${monthly[m]:>+7.2f}  {monthly_cnt[m]:>4}')
print(f'  {"-"*27}')
print(f'  {"TOTAL":<8} ${sum(monthly.values()):>+7.2f}  {len(t):>4}')
print()
print('='*60)

# Sample trades
print()
print('='*60)
print('  SAMPLE TRADES')
print('='*60)
print(f'  {"#":>3} {"Side":<5} {"Entry":>9} {"Exit":>9} {"PnL":>8} {"Reason":<8} {"Date":<16}')
print(f'  {"-"*60}')
winners = sorted(wn, key=lambda x: x.net_pnl + x.partial_pnl, reverse=True)[:3]
losers = sorted(ls, key=lambda x: x.net_pnl + x.partial_pnl)[:3]
for i, tr in enumerate(winners + losers, 1):
    pnl = tr.net_pnl + tr.partial_pnl
    print(f'  {i:>3} {tr.side:<5} {tr.entry_price:>8.2f}  {tr.exit_price:>8.2f}  ${pnl:>+6.2f}  {tr.exit_reason:<8} {tr.entry_time.strftime("%Y-%m-%d %H:%M"):<16}')
print()
