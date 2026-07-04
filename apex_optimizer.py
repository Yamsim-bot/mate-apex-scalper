#!/usr/bin/env python3
"""
MATE APEX OPTIMIZER V3 — Parallel sweep using proven engine
Runs configs concurrently across multiple processes
"""
import sys, os, time, math, pickle, multiprocessing as mp
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from mate_scalper_pro import (
    ScalperConfig, compute_indicators, run_scalper_backtest,
    NewsFilter, fetch_data
)

# Focused config set
CONFIGS = [
    # (name, adx, pillars, di, sl_m, rr, risk, be)
    ("RR2.0-A25",  25,2,1, 0.618,2.0,1.0,1),
    ("P3-R15",     20,3,1, 0.618,1.5,1.0,1),
    ("P3-R20",     20,3,1, 0.618,2.0,1.0,1),
    ("P3-A25-R15", 25,3,1, 0.618,1.5,1.0,1),
    ("P3-A25-R20", 25,3,1, 0.618,2.0,1.0,1),
    ("SL05-R15",   22,2,1, 0.5,  1.5,1.0,1),
    ("SL05-R20",   22,2,1, 0.5,  2.0,1.0,1),
    ("SL07-R15",   22,2,1, 0.7,  1.5,1.0,1),
    ("ADX18-R15",  18,2,1, 0.618,1.5,1.0,1),
    ("ADX20-R15",  20,2,1, 0.618,1.5,1.0,1),
    ("R2",         22,2,1, 0.618,1.0,2.0,1),
    ("R2-R15",     22,2,1, 0.618,1.5,2.0,1),
    ("NOSLTH",     22,2,1, 0.7,  1.0,1.0,1),
    ("NOBE",       22,2,1, 0.618,1.0,1.0,0),
    ("TSL-HRR",    22,2,1, 0.4,  2.0,1.0,1),
    ("AGR-R2",     22,2,1, 0.618,1.5,2.0,1),
]

def run_config(args_tuple):
    """Run one config in a subprocess — returns result dict or None"""
    name, adx, pillars, di, sl_m, rr, risk, be = args_tuple
    data_path, idx, total = EXPORT_DATA

    try:
        with open(data_path, 'rb') as f:
            data = pickle.load(f)

        df5 = compute_indicators(data['M5'])
        df15 = compute_indicators(data['M15'])

        c = ScalperConfig()
        c.adx_threshold = adx
        c.min_pillars = pillars
        c.use_di_filter = bool(di)
        c.fib_sl_mult = sl_m
        c.fib_tp_mult = rr
        c.rr_target = rr
        c.risk_pct = risk
        c.use_breakeven = bool(be)
        c.use_news_filter = False
        c.initial_capital = 500.0

        t0 = time.time()
        r = run_scalper_backtest(df5, df15, c, None)
        elapsed = time.time() - t0

        result_str = f"  [{idx+1:02d}/{total}] {name:<12s} ADX>={adx} P={pillars} DI={di} SL={sl_m} R:R={rr} Risk={risk}%... {r.total_trades:>4d}tr WR={r.win_rate:.1f}% PnL=$"+f"{r.total_pnl:>+.2f} PF={r.profit_factor:.2f} DD={r.max_drawdown_pct:.1f}% Ret={((r.final_capital/500-1)*100):.1f}% [{elapsed:.0f}s]"
        return {
            'result_str': result_str, 'name': name,
            'trades': r.total_trades, 'wr': r.win_rate,
            'pnl': r.total_pnl, 'costs': r.total_costs,
            'final': r.final_capital, 'ret': (r.final_capital/500-1)*100,
            'dd': r.max_drawdown_pct, 'pf': r.profit_factor,
            'avgw': r.avg_win, 'avgl': r.avg_loss, 'exp': r.expectancy
        }
    except Exception as e:
        return {'result_str': f"  [{idx+1:02d}/{total}] {name:<12s} ERROR: {e}", 'name': name, 'error': str(e)}

# Global export for worker processes (pickled data)
EXPORT_DATA = None

if __name__ == '__main__':
    mp.freeze_support()

    print("=" * 100)
    print("MATE APEX OPTIMIZER V3 — Parallel sweep using proven engine")
    print(f"Vantage RAW ECN | $500 | $6/RT | 0.8spread | 0.5slippage")
    print("=" * 100)

    print("\nFetching data...")
    data = fetch_data(quick=False)
    df5 = compute_indicators(data['M5'])
    df15 = compute_indicators(data['M15'])
    print(f"M5: {len(df5):,d} bars | M15: {len(df15):,d} bars")

    # Save data for worker processes
    data_pkl = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.sweep_data.pkl')
    with open(data_pkl, 'wb') as f:
        pickle.dump(data, f)

    # Set global export for workers
    EXPORT_DATA = (data_pkl, 0, len(CONFIGS))
    from apex_optimizer import run_config
    # Can't do this — circular. Let me restructure.

    print(f"\nRunning {len(CONFIGS)} configs in parallel...")
    sys.stdout.flush()

    results = []
    with mp.Pool(processes=min(8, len(CONFIGS))) as pool:
        for res in pool.imap_unordered(run_config, [(n,a,p,d,s,r,rk,b) for (n,a,p,d,s,r,rk,b) in CONFIGS]):
            if res and 'result_str' in res:
                print(res['result_str'])
                sys.stdout.flush()
                if 'error' not in res:
                    results.append(res)

    print(f"\n{'='*100}")
    print(f"  FINAL RANKINGS ({len(results)} configs)")
    print(f"{'='*100}")
    print(f"  {'Rank':<4} {'Config':<12} {'Trades':>5} {'WR%':>5} {'PnL':>8} {'Return':>7} {'DD%':>5} {'PF':>5} {'Exp':>7} {'Final':>8}")
    print(f"  {'-'*78}")

    results.sort(key=lambda x: (x['ret'], x['pf']), reverse=True)
    for i, r in enumerate(results):
        m = " <<<" if i==0 else (" <<" if i==1 else " <" if i==2 else "")
        print(f"  {i+1:<4} {r['name']:<12} {r['trades']:>5} {r['wr']:>5.1f} ${r['pnl']:>+7.2f} {r['ret']:>7.2f}% {r['dd']:>5.1f}% {r['pf']:>5.2f} ${r['exp']:>6.2f} ${r['final']:>7.2f}{m}")

    if results:
        print(f"\n{'='*100}")
        print(f"  WINNER: {results[0]['name']} — {results[0]['trades']}tr WR={results[0]['wr']:.1f}% "
              f"PnL=${results[0]['pnl']:.2f} ({results[0]['ret']:.2f}%) DD={results[0]['dd']:.1f}% PF={results[0]['pf']:.2f}")
        print(f"{'='*100}")

    # Cleanup
    try: os.remove(data_pkl)
    except: pass

    print("\nDone.")
