#!/usr/bin/env python3
"""
MATE SCALPER PRO v2.0 — XAUUSD Stealth Scalper
================================================
Professional scalping system for Vantage RAW ECN with:
  - Stealth SL/TP Mode (fib-based hidden levels, anti-hunting)
  - Dynamic ATR (volatility regime adapts risk in real-time)
  - Live News Filter (ForexFactory calendar, pauses before/after high-impact events)
  - Circuit breakers, partial TP, breakeven trailing

Usage:
  python mate_scalper_pro.py                # Full backtest
  python mate_scalper_pro.py --quick        # Quick test
  python mate_scalper_pro.py --live         # Live signal check
  python mate_scalper_pro.py --deploy       # Run as 24/7 bot
  python mate_scalper_pro.py --csv log.csv  # Save trade log
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
import math, warnings, sys, os, time, json, threading
from datetime import datetime, timedelta, date
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Tuple, Any
from collections import deque
warnings.filterwarnings("ignore")

# ─────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────

@dataclass
class ScalperConfig:
    """MATE Scalper Pro configuration."""
    # Entry / Filter
    entry_tf: str = 'M5'
    trend_tf: str = 'M15'
    adx_threshold: float = 22.0
    min_pillars: int = 2
    use_di_filter: bool = True

    # ─── Stealth SL/TP ───────────────────────
    # Non-obvious fib multiples instead of round numbers
    fib_sl_mult: float = 0.618         # 0.618 × ATR (stealth stop)
    fib_tp_mult: float = 1.0           # 1.0 × ATR for TP
    fib_partial_at: float = 0.382      # 0.382 × ATR for partial (stealth partial)
    use_stealth_mode: bool = True      # Enable fib-based non-round levels

    # ─── Dynamic ATR ─────────────────────────
    base_sl_mult: float = 0.7          # Base multiplier when volatility normal
    high_vol_mult: float = 1.15        # Expand stop in high volatility
    low_vol_mult: float = 0.6          # Tighten stop in low volatility
    atr_regime_period: int = 20        # Compare ATR to its SMA over this period
    high_vol_threshold: float = 1.2    # ATR / ATR_SMA > this = high vol
    low_vol_threshold: float = 0.8     # ATR / ATR_SMA < this = low vol
    rr_target: float = 1.0            # Risk:Reward for full TP
    use_breakeven: bool = True
    be_at_fraction: float = 0.6        # Move to BE at this fraction of TP

    # ─── Trailing Stop ────────────────────────
    use_trailing_stop: bool = True          # Enable ATR-based trailing stop
    trail_activation: float = 0.5           # Activate trail after price moves 0.5x ATR in profit
    trail_distance: float = 0.8             # Trail SL at 0.8x ATR behind best price
    trail_step: float = 0.15                # Recalculate every 0.15x ATR move (avoid excessive mods)

    # ─── Market Regime Filter ────────────────
    use_regime_filter: bool = True          # Skip trades in low-vol / ranging markets
    min_atr_for_trade: float = 3.0          # Minimum M5 ATR to take a trade
    low_vol_pillars: int = 3                # Require more pillars when vol is low
    low_vol_adx: float = 25.0               # Require higher ADX in low vol

    # ─── News Filter ─────────────────────────
    use_news_filter: bool = True
    news_minutes_before: int = 30      # Pause trading X min before high-impact
    news_minutes_after: int = 30       # Pause trading X min after high-impact
    news_impact_levels: tuple = ('High',)  # Only pause for this impact level
    news_refresh_mins: int = 60        # Refresh calendar every N minutes

    # ─── Risk Management ─────────────────────
    risk_pct: float = 1.0              # % of capital per trade
    max_trades_per_day: int = 12
    max_consecutive_losses: int = 3
    max_daily_loss_pct: float = 8.0
    max_drawdown_pct: float = 25.0

    # ─── Broker (Vantage RAW ECN) ────────────
    commission_per_lot_rt: float = 6.00
    typical_spread_pips: float = 0.8
    slippage_pips: float = 0.5

    # ─── XAUUSD Specs ────────────────────────
    pip_value: float = 0.10
    usd_per_pip_per_lot: float = 10.0
    lot_step: float = 0.01
    min_lot: float = 0.01
    max_lot: float = 50.0

    initial_capital: float = 500.0


# ─────────────────────────────────────────────
# NEWS CALENDAR (ForexFactory Scraper)
# ─────────────────────────────────────────────

class NewsFilter:
    """Live economic calendar filter using ForexFactory data."""

    URL = "https://www.forexfactory.com/calendar"

    def __init__(self, config: ScalperConfig):
        self.config = config
        self.events: List[Dict] = []
        self.last_refresh: Optional[datetime] = None
        self.lock = threading.Lock()
        self._fetch_attempts = 0

    def get_high_impact_windows(self) -> List[Tuple[datetime, datetime]]:
        """Return list of (start, end) datetime windows to block trading."""
        self._ensure_fresh()
        windows = []
        now = datetime.now()
        with self.lock:
            for ev in self.events:
                if ev.get('impact', '').upper() not in ['HIGH', 'RED']:
                    continue
                ev_time = ev.get('datetime')
                if ev_time is None:
                    continue
                # Only care about events within the next 48 hours
                if ev_time < now - timedelta(hours=2):
                    continue
                start = ev_time - timedelta(minutes=self.config.news_minutes_before)
                end = ev_time + timedelta(minutes=self.config.news_minutes_after)
                windows.append((start, end))
        return windows

    def is_trading_blocked(self, ts: datetime = None) -> Tuple[bool, Optional[str]]:
        """Check if trading is blocked due to news. Returns (blocked, reason)."""
        if not self.config.use_news_filter:
            return False, None
        if ts is None:
            ts = datetime.now()
        windows = self.get_high_impact_windows()
        for start, end in windows:
            if start <= ts <= end:
                return True, f"News window: {start.strftime('%H:%M')}-{end.strftime('%H:%M')}"
        return False, None

    def _ensure_fresh(self):
        """Refresh calendar data if stale."""
        if self.last_refresh is None or \
           (datetime.now() - self.last_refresh).total_seconds() > self.config.news_refresh_mins * 60:
            self._fetch()

    def _fetch(self):
        """Fetch economic calendar from ForexFactory."""
        try:
            import requests
            from bs4 import BeautifulSoup
        except ImportError:
            self._use_fallback_calendar()
            return

        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Accept': 'text/html,application/xhtml+xml',
            }
            resp = requests.get(self.URL, headers=headers, timeout=15)
            if resp.status_code != 200:
                self._use_fallback_calendar()
                return

            soup = BeautifulSoup(resp.text, 'html.parser')
            rows = soup.select('tr.calendar_row')
            events = []
            for row in rows:
                try:
                    date_el = row.select_one('td.calendar__date')
                    time_el = row.select_one('td.calendar__time')
                    currency_el = row.select_one('td.calendar__currency')
                    event_el = row.select_one('td.calendar__event')
                    impact_el = row.select_one('td.calendar__impact span')

                    if not all([date_el, time_el, event_el, impact_el, currency_el]):
                        continue

                    # Parse date
                    date_str = date_el.get_text(strip=True)
                    time_str = time_el.get_text(strip=True)
                    event_name = event_el.get_text(strip=True)
                    impact = impact_el.get('title', impact_el.get_text(strip=True))
                    currency = currency_el.get_text(strip=True)

                    # Parse impact level
                    impact_level = 'Low'
                    if impact and 'high' in impact.lower():
                        impact_level = 'High'
                    elif impact and 'medium' in impact.lower():
                        impact_level = 'Medium'

                    # Parse time
                    ev_dt = None
                    if time_str and time_str != 'All Day':
                        try:
                            h, m = map(int, time_str.replace('am','').replace('pm','').strip().split(':'))
                            if 'pm' in time_str.lower() and h != 12: h += 12
                            if 'am' in time_str.lower() and h == 12: h = 0
                            ev_dt = datetime.now().replace(hour=h, minute=m, second=0, microsecond=0)
                        except:
                            continue

                    if ev_dt is None:
                        continue

                    events.append({
                        'datetime': ev_dt,
                        'event': event_name,
                        'currency': currency,
                        'impact': impact_level,
                    })
                except:
                    continue

            with self.lock:
                self.events = events
                self.last_refresh = datetime.now()
                self._fetch_attempts = 0

        except Exception as e:
            self._fetch_attempts += 1
            if self._fetch_attempts > 3:
                self._use_fallback_calendar()
            else:
                time.sleep(2)
                self._fetch()

    def _use_fallback_calendar(self):
        """Fallback: hard-coded major event dates (updated quarterly)."""
        # Known high-impact events for Q3 2026
        fallback = [
            # NFP days (first Friday of each month)
            {"date": "2026-07-10", "time": "12:30", "event": "Non-Farm Employment Change", "impact": "High"},
            {"date": "2026-08-07", "time": "12:30", "event": "Non-Farm Employment Change", "impact": "High"},
            {"date": "2026-09-04", "time": "12:30", "event": "Non-Farm Employment Change", "impact": "High"},
            {"date": "2026-10-02", "time": "12:30", "event": "Non-Farm Employment Change", "impact": "High"},
            # FOMC meetings (typically Wednesdays)
            {"date": "2026-07-29", "time": "18:00", "event": "FOMC Statement", "impact": "High"},
            {"date": "2026-09-16", "time": "18:00", "event": "FOMC Statement", "impact": "High"},
            {"date": "2026-11-04", "time": "18:00", "event": "FOMC Statement", "impact": "High"},
            # CPI (typically mid-month)
            {"date": "2026-07-15", "time": "12:30", "event": "CPI m/m", "impact": "High"},
            {"date": "2026-08-12", "time": "12:30", "event": "CPI m/m", "impact": "High"},
            {"date": "2026-09-16", "time": "12:30", "event": "CPI m/m", "impact": "High"},
            # GDP
            {"date": "2026-07-30", "time": "12:30", "event": "GDP q/q", "impact": "High"},
            {"date": "2026-08-27", "time": "12:30", "event": "GDP q/q", "impact": "High"},
            {"date": "2026-09-30", "time": "12:30", "event": "GDP q/q", "impact": "High"},
            # Retail Sales
            {"date": "2026-07-16", "time": "12:30", "event": "Retail Sales m/m", "impact": "High"},
            {"date": "2026-08-14", "time": "12:30", "event": "Retail Sales m/m", "impact": "High"},
            {"date": "2026-09-17", "time": "12:30", "event": "Retail Sales m/m", "impact": "High"},
        ]
        events = []
        for ev in fallback:
            try:
                ev_dt = datetime.strptime(f"{ev['date']} {ev['time']}", "%Y-%m-%d %H:%M")
                events.append({
                    'datetime': ev_dt,
                    'event': ev['event'],
                    'currency': 'USD',
                    'impact': 'High',
                })
            except:
                continue
        with self.lock:
            self.events = events
            self.last_refresh = datetime.now()
            self._fetch_attempts = 0


# ─────────────────────────────────────────────
# STEALTH / DYNAMIC ATR ENGINE
# ─────────────────────────────────────────────

class StealthEngine:
    """Calculates hidden-level SL/TP using fib-based ATR and volatility regime."""

    def __init__(self, config: ScalperConfig):
        self.config = config

    def get_atr_regime(self, bar: pd.Series) -> Tuple[float, str]:
        """Determine volatility regime: 'normal', 'high', or 'low'."""
        atr = bar.get('atr14', 0)
        atr_sma = bar.get('atr_sma', atr)  # from computed indicator
        if atr <= 0 or atr_sma <= 0:
            return self.config.base_sl_mult, 'normal'
        ratio = atr / atr_sma
        if ratio >= self.config.high_vol_threshold:
            return self.config.high_vol_mult, 'high'
        elif ratio <= self.config.low_vol_threshold:
            return self.config.low_vol_mult, 'low'
        return self.config.base_sl_mult, 'normal'

    def get_stealth_levels(self, entry: float, atr: float, side: str,
                           regime_mult: float = None) -> Dict[str, float]:
        """Calculate stealth SL/TP using fib-based non-obvious levels.

        Instead of SL = entry ± ATR × 1.0, we use ATR × (fib_mult × regime_mult).
        This places stops at non-round, non-obvious levels that brokers/hFTs
        are less likely to hunt.
        """
        cfg = self.config

        if regime_mult is None:
            regime_mult = cfg.base_sl_mult

        # Base distances using fib multiples
        if cfg.use_stealth_mode:
            sl_distance = atr * cfg.fib_sl_mult * regime_mult
            tp_distance = atr * cfg.fib_tp_mult * regime_mult
            partial_distance = atr * cfg.fib_partial_at * regime_mult
        else:
            sl_distance = atr * cfg.base_sl_mult * regime_mult
            tp_distance = atr * cfg.rr_target * regime_mult
            partial_distance = atr * 0.5 * regime_mult

        # Add small noise (±0.5%) to avoid exact levels
        if cfg.use_stealth_mode:
            noise = np.random.uniform(-0.005, 0.005) * sl_distance
            sl_distance += noise
            noise = np.random.uniform(-0.003, 0.003) * tp_distance
            tp_distance += noise

        if side == 'LONG':
            return {
                'stop_loss': entry - sl_distance,
                'take_profit': entry + tp_distance,
                'partial_price': entry + partial_distance,
                'breakeven_price': entry + 0.01,
                'sl_distance': sl_distance,
                'tp_distance': tp_distance,
            }
        else:
            return {
                'stop_loss': entry + sl_distance,
                'take_profit': entry - tp_distance,
                'partial_price': entry - partial_distance,
                'breakeven_price': entry - 0.01,
                'sl_distance': sl_distance,
                'tp_distance': tp_distance,
            }

    def recalculate_dynamic_sl(self, trade, current_bar: pd.Series,
                                regime_mult: float = None) -> float:
        """Recompute SL level dynamically as ATR changes (trailing adjustment)."""
        cfg = self.config
        atr = current_bar.get('atr14', 0)
        if atr <= 0:
            return trade.stop_loss

        if regime_mult is None:
            regime_mult = cfg.base_sl_mult

        if cfg.use_stealth_mode:
            new_dist = atr * cfg.fib_sl_mult * regime_mult
        else:
            new_dist = atr * cfg.base_sl_mult * regime_mult

        # Only move SL in favorable direction (trailing)
        if trade.side == 'LONG':
            proposed = current_bar['close'] - new_dist
            return max(proposed, trade.stop_loss)  # never move SL down
        else:
            proposed = current_bar['close'] + new_dist
            return min(proposed, trade.stop_loss)  # never move SL up


# ─────────────────────────────────────────────
# TRADE DATA
# ─────────────────────────────────────────────

@dataclass
class Trade:
    entry_time: datetime
    side: str
    entry_price: float
    stop_loss: float
    take_profit: float
    lots_at_open: float = 0.0
    lots_remaining: float = 0.0
    exit_time: Optional[datetime] = None
    exit_price: Optional[float] = None
    exit_reason: str = 'OPEN'
    net_pnl: float = 0.0
    broker_costs: float = 0.0
    partial_filled: bool = False
    partial_price: Optional[float] = None
    partial_pnl: float = 0.0
    adx_at_entry: float = 0.0
    atr_at_entry: float = 0.0
    regime_at_entry: str = 'normal'
    sl_adjustments: int = 0  # count of dynamic SL adjustments

    @property
    def total_pnl(self):
        return self.net_pnl + self.partial_pnl


@dataclass
class Result:
    total_trades: int = 0
    winning_trades: int = 0
    losing_trades: int = 0
    win_rate: float = 0.0
    total_pnl: float = 0.0
    total_costs: float = 0.0
    final_capital: float = 0.0
    max_drawdown_pct: float = 0.0
    avg_win: float = 0.0
    avg_loss: float = 0.0
    profit_factor: float = 0.0
    expectancy: float = 0.0
    sharpe: float = 0.0
    trades: List[Trade] = field(default_factory=list)
    monthly_pnl: Dict = field(default_factory=dict)


# ─────────────────────────────────────────────
# INDICATORS
# ─────────────────────────────────────────────

def compute_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Full indicator suite for scalping."""
    df = df.copy()

    # ATR (Wilder's)
    tr = pd.concat([
        df['high'] - df['low'],
        abs(df['high'] - df['close'].shift()),
        abs(df['low'] - df['close'].shift())
    ], axis=1).max(axis=1)
    df['atr14'] = tr.rolling(14).mean()

    # ATR SMA for regime detection
    df['atr_sma'] = df['atr14'].rolling(20).mean()

    # EMAs
    df['ema20'] = df['close'].ewm(span=20, adjust=False).mean()
    df['ema50'] = df['close'].ewm(span=50, adjust=False).mean()
    df['ema200'] = df['close'].ewm(span=200, adjust=False).mean()

    # ADX + DI (Wilder's method)
    h, l, c = df['high'].values, df['low'].values, df['close'].values
    up = np.diff(h); dn = np.diff(l)
    pdi = np.where((up > dn) & (up > 0), up, 0)
    mdi = np.where((dn > up) & (dn > 0), dn, 0)
    pdi = np.insert(pdi, 0, 0); mdi = np.insert(mdi, 0, 0)
    tr2 = np.maximum(h - l, np.maximum(abs(h - np.roll(c, 1)), abs(l - np.roll(c, 1))))
    tr2[0] = np.nan
    atrs = pd.Series(tr2).ewm(alpha=1/14, adjust=False).mean().values
    safe = pd.Series(atrs).replace(0, np.nan).values

    df['plus_di'] = (100 * pd.Series(pdi).ewm(alpha=1/14, adjust=False).mean() / pd.Series(safe)).values
    df['minus_di'] = (100 * pd.Series(mdi).ewm(alpha=1/14, adjust=False).mean() / pd.Series(safe)).values

    dx = 100 * abs(df['plus_di'] - df['minus_di']) / (df['plus_di'] + df['minus_di']).replace(0, np.nan)
    df['adx'] = dx.rolling(14).mean().values

    # EMA slope
    df['ema20_slope'] = df['ema20'].diff(3) / df['ema20'].shift(3) * 100

    return df


def check_ema_cross(df, i, lookback=3):
    e20 = df['ema20'].values; e50 = df['ema50'].values
    b = r = False
    for j in range(max(0, i - lookback), i + 1):
        if j > 0:
            if e20[j-1] <= e50[j-1] and e20[j] > e50[j]: b = True
            if e20[j-1] >= e50[j-1] and e20[j] < e50[j]: r = True
    return b, r


def is_impulse(df, i, body_atr=0.6):
    if i < 0: return False
    c = df.iloc[i]
    if np.isnan(c['atr14']) or c['atr14'] <= 0: return False
    body = abs(c['close'] - c['open'])
    rng = c['high'] - c['low']
    if rng <= 0: return False
    return body >= body_atr * c['atr14'] and body / rng >= 0.4


def calc_pnl(entry, exit_, side, lots, config):
    pc = exit_ - entry if side == 'LONG' else entry - exit_
    gross = (pc / config.pip_value) * lots * config.usd_per_pip_per_lot
    cost = (config.typical_spread_pips + config.slippage_pips) * lots * config.usd_per_pip_per_lot + lots * config.commission_per_lot_rt
    return gross - cost, cost, gross


def calc_lots(cap, risk_pct, sl_pips, config):
    if sl_pips <= 0: return 0.0
    raw = cap * (risk_pct / 100.0) / (sl_pips * config.usd_per_pip_per_lot)
    return max(config.min_lot, min(config.max_lot, math.floor(raw / config.lot_step) * config.lot_step))


# ─────────────────────────────────────────────
# SIGNAL DETECTION
# ─────────────────────────────────────────────

def detect_signal_scalp(df_entry: pd.DataFrame, df_trend: pd.DataFrame,
                        i: int, config: ScalperConfig, news_filter: NewsFilter = None) -> Optional[Dict]:
    """Check for scalping signal with news filter integration."""
    bar = df_entry.iloc[i]
    ts = df_entry.index[i]

    # News filter
    if news_filter is not None:
        blocked, reason = news_filter.is_trading_blocked(ts)
        if blocked:
            return None

    # ADX
    if np.isnan(bar['adx']) or bar['adx'] < config.adx_threshold:
        return None

    # ── Market Regime Filter ──────────────────────────────────
    if config.use_regime_filter:
        atr_val = bar.get('atr14', 0)
        if np.isnan(atr_val) or atr_val < config.min_atr_for_trade:
            return None  # Low volatility — skip, market likely ranging
    # Note: additional regime checks (pillar/ADX bump) applied below

    # Trend bias
    tf_bar = df_trend.reindex(index=df_trend.index[df_trend.index <= ts], method='pad')
    if tf_bar.empty:
        return None
    tf_row = tf_bar.iloc[-1]

    bias = None
    if not np.isnan(tf_row['ema200']):
        bias = 'BULL' if tf_row['close'] > tf_row['ema200'] else 'BEAR'
    if bias is None:
        return None

    # Pillars
    cross_bull, cross_bear = check_ema_cross(df_entry, i)
    impulse = is_impulse(df_entry, i)

    lo48 = df_entry['low'].iloc[max(0, i-48):i+1].min()
    hi48 = df_entry['high'].iloc[max(0, i-48):i+1].max()
    in_aov = abs(bar['close'] - (hi48 + lo48) / 2) < 1.5

    pillars = sum([cross_bull or cross_bear, impulse, in_aov, bias is not None])

    # Bump pillar/ADX requirements in low-to-moderate volatility
    if config.use_regime_filter:
        atr_val = bar.get('atr14', 0)
        moderate_vol_threshold = config.min_atr_for_trade * 1.5
        if not np.isnan(atr_val) and atr_val < moderate_vol_threshold:
            if pillars < config.low_vol_pillars:
                return None  # Need more confirmation in lower vol
            if bar['adx'] < config.low_vol_adx:
                return None  # Need stronger trend in lower vol

    if pillars < config.min_pillars:
        return None

    if bias == 'BULL' and cross_bull:
        side = 'LONG'
    elif bias == 'BEAR' and cross_bear:
        side = 'SHORT'
    else:
        return None

    # +DI alignment
    if config.use_di_filter:
        pdi = bar.get('plus_di', np.nan)
        mdi = bar.get('minus_di', np.nan)
        di_bull = not np.isnan(pdi) and not np.isnan(mdi) and pdi > mdi
        if side == 'LONG' and not di_bull:
            return None
        if side == 'SHORT' and di_bull:
            return None

    if np.isnan(bar['atr14']):
        return None

    return {
        'time': ts,
        'side': side,
        'entry': bar['close'],
        'atr': bar['atr14'],
        'adx': bar['adx'],
        'bias': bias,
        'pillars': pillars,
    }


# ─────────────────────────────────────────────
# BACKTEST ENGINE
# ─────────────────────────────────────────────

def run_scalper_backtest(df_entry: pd.DataFrame, df_trend: pd.DataFrame,
                         config: ScalperConfig = None,
                         news_filter: NewsFilter = None) -> Result:
    """Run the stealth scalper backtest."""
    if config is None:
        config = ScalperConfig()

    stealth = StealthEngine(config)
    capital = config.initial_capital
    peak = capital
    trades: List[Trade] = []
    dds = []
    cd = None; dt = 0; dl = 0; cl = 0
    start_capital = capital

    for i in range(60, len(df_entry) - 1):
        ts = df_entry.index[i]
        bar = df_entry.iloc[i]

        # Daily reset
        if cd is None or cd != ts.date():
            dt = 0; dl = 0; cl = 0
            start_capital = capital
            cd = ts.date()

        # Circuit breakers
        if dl >= 2: continue
        if dt >= config.max_trades_per_day: continue
        if cl >= config.max_consecutive_losses: continue
        dd = (peak - capital) / peak * 100 if peak > 0 else 0
        if dd > config.max_drawdown_pct: break
        daily_loss = (start_capital - capital) / start_capital * 100 if start_capital > 0 else 0
        if daily_loss > config.max_daily_loss_pct: continue

        # Detect signal
        sig = detect_signal_scalp(df_entry, df_trend, i, config, news_filter)
        if sig is None:
            continue

        # Dynamic ATR: determine volatility regime
        regime_mult, regime_label = stealth.get_atr_regime(bar)
        sl_pips = (sig['atr'] * regime_mult) / config.pip_value
        lots = calc_lots(capital, config.risk_pct, sl_pips, config)
        if lots < config.min_lot:
            continue

        # Stealth SL/TP levels
        levels = stealth.get_stealth_levels(sig['entry'], sig['atr'], sig['side'], regime_mult)

        trade = Trade(
            entry_time=ts,
            side=sig['side'],
            entry_price=sig['entry'],
            stop_loss=levels['stop_loss'],
            take_profit=levels['take_profit'],
            lots_at_open=lots,
            lots_remaining=lots,
            adx_at_entry=sig['adx'],
            atr_at_entry=sig['atr'],
            regime_at_entry=regime_label,
        )
        dt += 1

        # Resolve trade
        sl = trade.stop_loss
        tp = trade.take_profit
        partial_tp = levels['partial_price']
        be_active = False
        trail_active = False
        trail_trigger_price = sig['entry'] + (sig['atr'] * config.trail_activation) if sig['side'] == 'LONG' else sig['entry'] - (sig['atr'] * config.trail_activation)
        best_price = sig['entry']  # track best price for trailing
        last_trail_update = 0.0
        resolved = False

        for j in range(i + 1, min(i + 25, len(df_entry))):
            bj = df_entry.iloc[j]
            bj_bar = df_entry.iloc[j]

            # Track best price reached
            if sig['side'] == 'LONG':
                best_price = max(best_price, bj['high'])
            else:
                best_price = min(best_price, bj['low'])

            # Dynamic SL adjustment (re-evaluate ATR regime)
            if trade.sl_adjustments < 5:  # limit adjustments
                new_regime_mult, _ = stealth.get_atr_regime(bj_bar)
                if abs(new_regime_mult - regime_mult) > 0.1:
                    new_sl = stealth.recalculate_dynamic_sl(trade, bj_bar, new_regime_mult)
                    if new_sl != sl and (trade.side == 'LONG' and new_sl > sl) or \
                                         (trade.side == 'SHORT' and new_sl < sl):
                        sl = new_sl
                        trade.sl_adjustments += 1

            # ── Trailing Stop ────────────────────────────────────
            if config.use_trailing_stop:
                # Check if price has moved enough to activate trailing
                if not trail_active:
                    if sig['side'] == 'LONG' and bj['high'] >= trail_trigger_price:
                        trail_active = True
                        sl = max(sl, best_price - sig['atr'] * config.trail_distance)
                        last_trail_update = abs(best_price - sig['entry'])
                    elif sig['side'] == 'SHORT' and bj['low'] <= trail_trigger_price:
                        trail_active = True
                        sl = min(sl, best_price + sig['atr'] * config.trail_distance)
                        last_trail_update = abs(best_price - sig['entry'])
                # Update trailing SL when price moves another trail_step x ATR
                if trail_active:
                    mkt_move = abs(best_price - sig['entry'])
                    if mkt_move - last_trail_update >= sig['atr'] * config.trail_step:
                        if sig['side'] == 'LONG':
                            sl = max(sl, best_price - sig['atr'] * config.trail_distance)
                            # Never let trailing SL be worse than BE if BE was active
                            if be_active:
                                sl = max(sl, trade.entry_price + 0.01)
                        else:
                            sl = min(sl, best_price + sig['atr'] * config.trail_distance)
                            if be_active:
                                sl = min(sl, trade.entry_price - 0.01)
                        last_trail_update = mkt_move

            if sig['side'] == 'LONG':
                # Partial TP
                if not trade.partial_filled and bj['high'] >= partial_tp:
                    half_lots = trade.lots_remaining / 2
                    partial_pnl, partial_cost, _ = calc_pnl(
                        trade.entry_price, partial_tp, 'LONG', half_lots, config)
                    trade.partial_filled = True
                    trade.partial_price = partial_tp
                    trade.partial_pnl = partial_pnl
                    trade.broker_costs += partial_cost
                    trade.lots_remaining = half_lots
                    sl = max(sl, trade.entry_price + 0.01)  # BE on remainder
                    be_active = True
                    continue

                # Breakeven (only if trailing stop hasn't already moved past BE)
                if not be_active and not trail_active and config.use_breakeven:
                    if bj['high'] >= trade.entry_price + (tp - trade.entry_price) * config.be_at_fraction:
                        sl = max(sl, trade.entry_price + 0.01)
                        be_active = True

                if bj['high'] >= tp:
                    final_pnl, final_cost, _ = calc_pnl(
                        trade.entry_price, tp, 'LONG', trade.lots_remaining, config)
                    trade.net_pnl = final_pnl
                    trade.broker_costs += final_cost
                    trade.exit_time = df_entry.index[j]
                    trade.exit_price = tp
                    trade.exit_reason = 'TP'
                    resolved = True
                    break
                elif bj['low'] <= sl:
                    final_pnl, final_cost, _ = calc_pnl(
                        trade.entry_price, sl, 'LONG', trade.lots_remaining, config)
                    trade.net_pnl = final_pnl
                    trade.broker_costs += final_cost
                    trade.exit_time = df_entry.index[j]
                    trade.exit_price = sl
                    if be_active:
                        trade.exit_reason = 'BE'
                    elif trail_active:
                        trade.exit_reason = 'TRAIL'
                    else:
                        trade.exit_reason = 'SL'
                    resolved = True
                    break

            else:  # SHORT
                if not trade.partial_filled and bj['low'] <= partial_tp:
                    half_lots = trade.lots_remaining / 2
                    partial_pnl, partial_cost, _ = calc_pnl(
                        trade.entry_price, partial_tp, 'SHORT', half_lots, config)
                    trade.partial_filled = True
                    trade.partial_price = partial_tp
                    trade.partial_pnl = partial_pnl
                    trade.broker_costs += partial_cost
                    trade.lots_remaining = half_lots
                    sl = min(sl, trade.entry_price - 0.01)
                    be_active = True
                    continue

                if not be_active and not trail_active and config.use_breakeven:
                    if bj['low'] <= trade.entry_price - abs(tp - trade.entry_price) * config.be_at_fraction:
                        sl = min(sl, trade.entry_price - 0.01)
                        be_active = True

                if bj['low'] <= tp:
                    final_pnl, final_cost, _ = calc_pnl(
                        trade.entry_price, tp, 'SHORT', trade.lots_remaining, config)
                    trade.net_pnl = final_pnl
                    trade.broker_costs += final_cost
                    trade.exit_time = df_entry.index[j]
                    trade.exit_price = tp
                    trade.exit_reason = 'TP'
                    resolved = True
                    break
                elif bj['high'] >= sl:
                    final_pnl, final_cost, _ = calc_pnl(
                        trade.entry_price, sl, 'SHORT', trade.lots_remaining, config)
                    trade.net_pnl = final_pnl
                    trade.broker_costs += final_cost
                    trade.exit_time = df_entry.index[j]
                    trade.exit_price = sl
                    if be_active:
                        trade.exit_reason = 'BE'
                    elif trail_active:
                        trade.exit_reason = 'TRAIL'
                    else:
                        trade.exit_reason = 'SL'
                    resolved = True
                    break

        if not resolved:
            li = min(i + 24, len(df_entry) - 1)
            final_pnl, final_cost, _ = calc_pnl(
                trade.entry_price, df_entry.iloc[li]['close'],
                trade.side, trade.lots_remaining, config)
            trade.net_pnl = final_pnl
            trade.broker_costs += final_cost
            trade.exit_time = df_entry.index[li]
            trade.exit_price = df_entry.iloc[li]['close']
            trade.exit_reason = 'TIMEOUT'

        total = trade.total_pnl
        capital += total
        peak = max(peak, capital)
        dds.append((peak - capital) / peak * 100 if peak > 0 else 0)
        if total > 0: cl = 0
        else: dl += 1; cl += 1
        trades.append(trade)

    # Compile result
    result = Result(total_trades=len(trades), final_capital=capital)
    result.trades = trades
    if trades:
        wins = [t for t in trades if t.total_pnl > 0]
        losses = [t for t in trades if t.total_pnl <= 0]
        result.winning_trades = len(wins)
        result.losing_trades = len(losses)
        result.win_rate = len(wins) / len(trades) * 100
        result.total_pnl = sum(t.total_pnl for t in trades)
        result.total_costs = sum(t.broker_costs for t in trades)
        result.max_drawdown_pct = max(dds) if dds else 0
        result.avg_win = np.mean([t.total_pnl for t in wins]) if wins else 0
        result.avg_loss = abs(np.mean([t.total_pnl for t in losses])) if losses else 0
        gw = sum(t.total_pnl for t in wins)
        gl = abs(sum(t.total_pnl for t in losses))
        result.profit_factor = gw / gl if gl > 0 else (gw if gw > 0 else 0)
        wr = result.win_rate / 100
        result.expectancy = wr * result.avg_win - (1 - wr) * result.avg_loss if result.avg_win and result.avg_loss else 0
        rets = [t.total_pnl / config.initial_capital for t in trades]
        if len(rets) > 1 and np.std(rets) > 0:
            result.sharpe = np.mean(rets) / np.std(rets) * np.sqrt(252)
        for t in trades:
            m = t.entry_time.strftime('%Y-%m')
            if m not in result.monthly_pnl:
                result.monthly_pnl[m] = {'trades': 0, 'pnl': 0.0}
            result.monthly_pnl[m]['trades'] += 1
            result.monthly_pnl[m]['pnl'] += t.total_pnl
    return result


# ─────────────────────────────────────────────
# DATA FETCH
# ─────────────────────────────────────────────

def fetch_data(quick=False):
    if not mt5.initialize():
        print(f"  MT5 init failed: {mt5.last_error()}")
        return {}
    mt5.symbol_select("XAUUSD+", True)
    data = {}
    for nm, tf_id in [('M5',5),('M15',15),('M30',30),('H1',60),('H4',240)]:
        tf_map = {5:mt5.TIMEFRAME_M5,15:mt5.TIMEFRAME_M15,30:mt5.TIMEFRAME_M30,
                  60:mt5.TIMEFRAME_H1,240:mt5.TIMEFRAME_H4}
        ch = []; cur = datetime.now()
        for _ in range(5):
            if quick and _ > 0: break
            c = mt5.copy_rates_from("XAUUSD+", tf_map[tf_id], cur, 1000 if quick else 50000)
            if c is None or len(c) == 0: break
            ch.append(pd.DataFrame(c))
            cur = datetime.fromtimestamp(c[0][0]) - timedelta(seconds=1)
        if ch:
            df = pd.concat(ch).drop_duplicates(subset='time').sort_values('time')
            df['time'] = pd.to_datetime(df['time'], unit='s')
            df.set_index('time', inplace=True)
            data[nm] = df
            print(f"  {nm}: {len(df)} bars")
    mt5.shutdown()
    return data


# ─────────────────────────────────────────────
# LIVE TRADING ENGINE
# ─────────────────────────────────────────────

class LiveScalper:
    """24/7 live scalping engine with news integration."""

    def __init__(self, config: ScalperConfig = None):
        self.config = config or ScalperConfig()
        self.news_filter = NewsFilter(self.config) if self.config.use_news_filter else None
        self.stealth = StealthEngine(self.config)
        self.active_trades: List[Dict] = []
        self.daily_trades = 0
        self.daily_losses = 0
        self.consecutive_losses = 0
        self.current_day = date.today()
        self.capital = self.config.initial_capital
        self.peak = self.capital
        self.running = False
        self.last_bar_time = None

    def log(self, msg: str):
        print(f"  [{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}")

    def check_connection(self) -> bool:
        if not mt5.initialize():
            self.log(f"MT5 reconnecting... {mt5.last_error()}")
            time.sleep(5)
            return mt5.initialize()
        return True

    def get_signal(self) -> Optional[Dict]:
        """Check for a live signal on the latest bar."""
        if not self.check_connection():
            return None

        # Fetch fresh data
        rates_m5 = mt5.copy_rates_from("XAUUSD+", mt5.TIMEFRAME_M5, datetime.now(), 200)
        rates_m15 = mt5.copy_rates_from("XAUUSD+", mt5.TIMEFRAME_M15, datetime.now(), 200)
        if rates_m5 is None or rates_m15 is None:
            return None

        df5 = pd.DataFrame(rates_m5)
        df5['time'] = pd.to_datetime(df5['time'], unit='s')
        df5.set_index('time', inplace=True)
        df5 = compute_indicators(df5)

        df15 = pd.DataFrame(rates_m15)
        df15['time'] = pd.to_datetime(df15['time'], unit='s')
        df15.set_index('time', inplace=True)
        df15 = compute_indicators(df15)

        # Check news
        if self.news_filter:
            blocked, reason = self.news_filter.is_trading_blocked()
            if blocked:
                return None  # silently skip

        # Check daily limits
        today = date.today()
        if today != self.current_day:
            self.current_day = today
            self.daily_trades = 0
            self.daily_losses = 0
            self.consecutive_losses = 0

        if self.daily_trades >= self.config.max_trades_per_day:
            return None
        if self.daily_losses >= 2:
            return None
        if self.consecutive_losses >= self.config.max_consecutive_losses:
            return None

        # Check DD
        dd = (self.peak - self.capital) / self.peak * 100 if self.peak > 0 else 0
        if dd > self.config.max_drawdown_pct:
            self.log(f"Max DD ({dd:.1f}%) hit — stopping trading")
            return None

        # Detect signal on latest complete bar
        i = len(df5) - 2
        sig = detect_signal_scalp(df5, df15, i, self.config, self.news_filter)
        if sig is None:
            return None

        return {'signal': sig, 'df_entry': df5, 'df_trend': df15, 'bar_index': i}

    def execute_trade(self, signal_info: Dict) -> bool:
        """Execute trade on MT5 with stealth levels."""
        sig = signal_info['signal']
        bar = signal_info['df_entry'].iloc[signal_info['bar_index']]

        # Dynamic ATR regime
        regime_mult, regime_label = self.stealth.get_atr_regime(bar)
        sl_pips = (sig['atr'] * regime_mult) / self.config.pip_value
        lots = calc_lots(self.capital, self.config.risk_pct, sl_pips, self.config)
        if lots < self.config.min_lot:
            return False

        # Stealth levels
        levels = self.stealth.get_stealth_levels(
            sig['entry'], sig['atr'], sig['side'], regime_mult)

        # Place trade via MT5
        symbol = "XAUUSD+"
        order_type = mt5.ORDER_TYPE_BUY if sig['side'] == 'LONG' else mt5.ORDER_TYPE_SELL
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": lots,
            "type": order_type,
            "price": mt5.symbol_info_tick(symbol).ask if sig['side'] == 'LONG' else mt5.symbol_info_tick(symbol).bid,
            "sl": levels['stop_loss'],
            "tp": levels['take_profit'],
            "deviation": 20,
            "magic": 823777,
            "comment": f"MATE-Scalp {regime_label[:1]} {sig['adx']:.0f}",
            "type_time": mt5.ORDER_TIME_GTC,
            "type_filling": mt5.ORDER_FILLING_IOC,
        }

        result = mt5.order_send(request)
        if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
            self.log(f"Order failed: {mt5.last_error() if result is None else result.comment}")
            return False

        self.daily_trades += 1
        self.active_trades.append({
            'ticket': result.order,
            'side': sig['side'],
            'entry': result.price,
            'sl': levels['stop_loss'],
            'tp': levels['take_profit'],
            'lots': lots,
            'regime': regime_label,
            'adx': sig['adx'],
            'entry_time': datetime.now(),
        })
        self.log(f"{sig['side']} {lots:.2f} lot @ ${result.price:.2f} "
                 f"SL=${levels['stop_loss']:.2f} TP=${levels['take_profit']:.2f} "
                 f"[{regime_label}] ADX={sig['adx']:.1f}")
        return True

    def manage_active_trades(self):
        """Monitor and manage active positions (dynamic SL adjustment)."""
        if not self.active_trades:
            return
        if not self.check_connection():
            return

        positions = mt5.positions_get()
        if positions is None:
            return

        pos_dict = {p.ticket: p for p in positions}
        closed = []
        for t in self.active_trades:
            if t['ticket'] not in pos_dict:
                # Position closed — update PnL
                history = mt5.history_deals_get(t['entry_time'], datetime.now())
                if history:
                    for deal in history:
                        if deal.position_id == t['ticket'] and deal.profit != 0:
                            self.capital += deal.profit
                            if self.capital > self.peak:
                                self.peak = self.capital
                            if deal.profit > 0:
                                self.consecutive_losses = 0
                            else:
                                self.daily_losses += 1
                                self.consecutive_losses += 1
                            break
                closed.append(t)

        for t in closed:
            self.active_trades.remove(t)

        # Dynamic SL adjustment on open trades
        try:
            rates_m5 = mt5.copy_rates_from("XAUUSD+", mt5.TIMEFRAME_M5, datetime.now(), 10)
            if rates_m5 and len(rates_m5) > 0:
                df = pd.DataFrame(rates_m5)
                df['time'] = pd.to_datetime(df['time'], unit='s')
                df.set_index('time', inplace=True)
                df = compute_indicators(df)
                latest = df.iloc[-1]

                for p in positions:
                    if p.comment.startswith('MATE-Scalp'):
                        # Re-evaluate SL dynamically
                        regime_mult, _ = self.stealth.get_atr_regime(latest)
                        trade_side = 'LONG' if p.type == mt5.ORDER_TYPE_BUY else 'SHORT'

                        pseudo_trade = Trade(
                            entry_time=datetime.fromtimestamp(p.time),
                            side=trade_side,
                            entry_price=p.price_open,
                            stop_loss=p.sl,
                            take_profit=p.tp,
                            lots_at_open=p.volume,
                        )

                        new_sl = self.stealth.recalculate_dynamic_sl(
                            pseudo_trade, latest, regime_mult)

                        # Only move SL favorably
                        if (trade_side == 'LONG' and new_sl > p.sl) or \
                           (trade_side == 'SHORT' and new_sl < p.sl):
                            if abs(new_sl - p.sl) > 0.1:  # min 10 cent change
                                modify_req = {
                                    "action": mt5.TRADE_ACTION_SLTP,
                                    "symbol": "XAUUSD+",
                                    "position": p.ticket,
                                    "sl": new_sl,
                                    "tp": p.tp,
                                }
                                mr = mt5.order_send(modify_req)
                                if mr and mr.retcode == mt5.TRADE_RETCODE_DONE:
                                    self.log(f"  Adjusted SL on #{p.ticket}: ${new_sl:.2f}")
        except Exception as e:
            pass

    def run_cycle(self):
        """One trading cycle: check signal, manage positions, update news."""
        # Refresh news
        if self.news_filter:
            self.news_filter._ensure_fresh()

        # Manage existing trades
        self.manage_active_trades()

        # Check for new signal
        if len(self.active_trades) < 3:  # max 3 concurrent
            signal_info = self.get_signal()
            if signal_info:
                self.execute_trade(signal_info)

    def run_forever(self, interval_sec=30):
        """Main loop — run 24/7."""
        self.log("Starting MATE Scalper Pro — 24/7 mode")
        self.log(f"Capital: ${self.capital:.2f} | Risk: {self.config.risk_pct}%/trade")
        self.running = True

        while self.running:
            try:
                self.run_cycle()
            except KeyboardInterrupt:
                self.log("Stopping...")
                self.running = False
                break
            except Exception as e:
                self.log(f"Error: {e}")

            # Sleep until next bar
            now = datetime.now()
            next_second = (now + timedelta(seconds=interval_sec)).replace(microsecond=0)
            sleep_time = (next_second - now).total_seconds()
            if sleep_time > 0:
                time.sleep(sleep_time)

        mt5.shutdown()
        self.log("Stopped.")


# ─────────────────────────────────────────────
# DISPLAY
# ─────────────────────────────────────────────

def print_result(r: Result, config: ScalperConfig):
    print("\n" + "=" * 90)
    print("  MATE SCALPER PRO v2.0 — BACKTEST RESULTS")
    print("=" * 90)
    if r.total_trades == 0:
        print("  No trades."); return

    print(f"  Period:            {r.trades[0].entry_time.strftime('%Y-%m-%d')} to {r.trades[-1].entry_time.strftime('%Y-%m-%d')}")
    print(f"  Total Trades:      {r.total_trades}")
    print(f"  Avg trades/day:    {r.total_trades / max(len(r.monthly_pnl) * 22, 1):.1f}")
    print(f"  Win Rate:          {r.win_rate:.1f}%")
    print(f"  Winners/Losers:    {r.winning_trades}/{r.losing_trades}")
    print(f"  Total PnL:         ${r.total_pnl:.2f}")
    print(f"  Broker Costs:      ${r.total_costs:.2f} (${r.total_costs/max(r.total_trades,1):.2f}/trade)")
    print(f"  Final Capital:     ${r.final_capital:.2f}")
    total_return = (r.final_capital / config.initial_capital - 1) * 100
    months = len(r.monthly_pnl)
    print(f"  Total Return:      {total_return:+.2f}%")
    print(f"  Avg Monthly:       {total_return/max(months,1):+.2f}%")
    print(f"  Max Drawdown:      {r.max_drawdown_pct:.2f}%")
    print(f"  Profit Factor:     {r.profit_factor:.2f}")
    print(f"  Avg Win:           ${r.avg_win:.2f}")
    print(f"  Avg Loss:          ${r.avg_loss:.2f}")
    print(f"  Expectancy:        ${r.expectancy:.2f}/trade")

    full_tp = sum(1 for t in r.trades if t.exit_reason == 'TP')
    sl = sum(1 for t in r.trades if t.exit_reason in ('SL', 'BE'))
    trail_exits = sum(1 for t in r.trades if t.exit_reason == 'TRAIL')
    partials = sum(1 for t in r.trades if t.partial_filled)
    print(f"\n  TRADE BREAKDOWN:")
    print(f"    Full TP:     {full_tp} ({full_tp/max(r.total_trades,1)*100:.1f}%)")
    print(f"    Trailed:     {trail_exits} ({trail_exits/max(r.total_trades,1)*100:.1f}%)")
    print(f"    Partial:     {partials} ({partials/max(r.total_trades,1)*100:.1f}%)")
    print(f"    Stop Loss:   {sl} ({sl/max(r.total_trades,1)*100:.1f}%)")

    # Monthly
    print(f"\n  MONTHLY PnL ({len(r.monthly_pnl)} months):")
    print(f"    {'Month':<10} {'Trades':>6} {'PnL':>8} {'Cumul':>8} {'Return':>8}")
    cumul = 0; ups = 0
    for m in sorted(r.monthly_pnl.keys()):
        d = r.monthly_pnl[m]; cumul += d['pnl']
        ret = d['pnl'] / config.initial_capital * 100
        if d['pnl'] > 0: ups += 1
        print(f"    {m:<10} {d['trades']:>6} ${d['pnl']:>6.2f} ${cumul:>6.2f} {ret:>+6.2f}%")
    print(f"    Profitable: {ups}/{len(r.monthly_pnl)} ({ups/len(r.monthly_pnl)*100:.0f}%)")

    # Regime breakdown
    regimes = {}
    for t in r.trades:
        regimes[t.regime_at_entry] = regimes.get(t.regime_at_entry, 0) + 1
    print(f"\n  REGIME DISTRIBUTION:")
    for regime, count in sorted(regimes.items()):
        print(f"    {regime}: {count} trades ({count/len(r.trades)*100:.0f}%)")

    # Projection
    daily_avg = r.total_pnl / max(months * 22, 1)
    monthly_avg = daily_avg * 22
    print(f"\n  PROJECTION ($500):")
    print(f"    Daily avg:    ${daily_avg:.2f}")
    print(f"    Monthly avg:  ${monthly_avg:.2f} ({monthly_avg/config.initial_capital*100:.1f}%)")
    print(f"    Best month:   ${max(d['pnl'] for d in r.monthly_pnl.values()):.2f}")
    print(f"    Worst month:  ${min(d['pnl'] for d in r.monthly_pnl.values()):.2f}")

    # Risk of ruin estimate
    if r.avg_win > 0 and r.avg_loss > 0:
        edge = r.expectancy
        if edge > 0:
            wr = r.win_rate / 100
            avg_risk = r.avg_loss
            kelly_pct = wr - (1 - wr) / (r.avg_win / r.avg_loss)
            print(f"\n  RISK METRICS:")
            print(f"    Kelly optimal: {max(0, kelly_pct)*100:.1f}% of capital")
            print(f"    Current risk:  {config.risk_pct:.1f}%")
            print(f"    Max DD:        {r.max_drawdown_pct:.2f}%")


# ─────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────

def main():
    import argparse
    ap = argparse.ArgumentParser(description='MATE Scalper Pro v2.0')
    ap.add_argument('--quick', action='store_true', help='Quick test (less data)')
    ap.add_argument('--live', action='store_true', help='Live signal check')
    ap.add_argument('--deploy', action='store_true', help='Run as 24/7 bot')
    ap.add_argument('--csv', type=str, default=None, help='Save trade log')
    ap.add_argument('--capital', type=float, default=500.0, help='Starting capital')
    ap.add_argument('--risk', type=float, default=None, help='Risk % per trade')
    ap.add_argument('--no-news', action='store_true', help='Disable news filter')
    ap.add_argument('--no-stealth', action='store_true', help='Disable stealth levels')
    args = ap.parse_args()

    config = ScalperConfig()
    config.initial_capital = args.capital
    if args.risk is not None: config.risk_pct = args.risk
    if args.no_news: config.use_news_filter = False
    if args.no_stealth: config.use_stealth_mode = False

    print("=" * 90)
    print("  MATE SCALPER PRO v2.0 — XAUUSD Stealth Scalping System")
    print("=" * 90)
    print(f"  Entry: {config.entry_tf} | Trend: {config.trend_tf} | ADX>={config.adx_threshold}")
    if config.use_stealth_mode:
        print(f"  STEALTH SL/TP:  SL={config.fib_sl_mult}x ATR | TP={config.fib_tp_mult}x ATR | Partial={config.fib_partial_at}x ATR")
        print(f"  Dynamic ATR:    Base={config.base_sl_mult} | HighVol={config.high_vol_mult} | LowVol={config.low_vol_mult}")
    else:
        print(f"  STANDARD SL/TP: SL={config.base_sl_mult}x ATR | TP={config.rr_target}x ATR")
    if config.use_news_filter:
        print(f"  NEWS FILTER:    {config.news_minutes_before}min before / {config.news_minutes_after}min after HIGH impact")
    print(f"  Risk: {config.risk_pct}%/trade | Max {config.max_trades_per_day}/day | DD limit: {config.max_drawdown_pct}%")
    print(f"  Capital: ${config.initial_capital:.2f} | Costs: $6/RT, {config.typical_spread_pips}spread, {config.slippage_pips}slippage")
    print()

    if args.deploy:
        print("  Starting 24/7 live trading engine...")
        print("  Press Ctrl+C to stop.\n")
        engine = LiveScalper(config)
        engine.run_forever()
        return

    if args.live:
        print("  Live signal check...")
        if not mt5.initialize():
            print(f"  MT5: {mt5.last_error()}"); return
        mt5.symbol_select("XAUUSD+", True)

        em5 = mt5.copy_rates_from("XAUUSD+", mt5.TIMEFRAME_M5, datetime.now(), 200)
        em15 = mt5.copy_rates_from("XAUUSD+", mt5.TIMEFRAME_M15, datetime.now(), 200)
        if em5 is None: print("  No data."); mt5.shutdown(); return

        df5 = pd.DataFrame(em5); df5['time'] = pd.to_datetime(df5['time'],unit='s'); df5.set_index('time',inplace=True); df5 = compute_indicators(df5)
        df15 = pd.DataFrame(em15) if em15 is not None else pd.DataFrame()
        if not df15.empty:
            df15['time'] = pd.to_datetime(df15['time'],unit='s'); df15.set_index('time',inplace=True); df15 = compute_indicators(df15)
        mt5.shutdown()

        nf = NewsFilter(config) if config.use_news_filter else None
        li = len(df5)-2
        sig = detect_signal_scalp(df5, df15, li, config, nf)
        if sig:
            stealth = StealthEngine(config)
            bar = df5.iloc[li]
            regime_mult, regime_label = stealth.get_atr_regime(bar)
            levels = stealth.get_stealth_levels(sig['entry'], sig['atr'], sig['side'], regime_mult)
            print(f"\n  SIGNAL: {sig['side']} @ ${sig['entry']:.2f} [{regime_label} vol]")
            print(f"     SL: ${levels['stop_loss']:.2f} (fib {config.fib_sl_mult}x ATR)")
            print(f"     TP: ${levels['take_profit']:.2f} (fib {config.fib_tp_mult}x ATR)")
            print(f"     Partial: ${levels['partial_price']:.2f} (fib {config.fib_partial_at}x ATR)")
            print(f"     ADX: {sig['adx']:.1f} | ATR: ${sig['atr']:.2f} | ATR/SMA: {sig['atr']/max(bar.get('atr_sma',0), 0.001):.2f}")
        else:
            bar = df5.iloc[li]
            print(f"\n  No signal. ADX={bar['adx']:.1f} +DI={bar['plus_di']:.1f} -DI={bar['minus_di']:.1f}")
            print(f"     Price=${bar['close']:.2f} ATR=${bar['atr14']:.2f}")
        return

    # Backtest
    print("  Fetching data...")
    data = fetch_data(quick=args.quick)
    if 'M5' not in data or 'M15' not in data:
        print("  Need M5 and M15 data."); return

    print("  Computing indicators...")
    df5 = compute_indicators(data['M5'])
    df15 = compute_indicators(data['M15']) if 'M15' in data else compute_indicators(
        data['M5'].resample('15min').agg({'open':'first','high':'max','low':'min','close':'last'}).dropna())

    print(f"  M5 bars: {len(df5):,d} | M15 bars: {len(df15):,d}")
    print("  Initializing news filter...")

    nf = NewsFilter(config) if config.use_news_filter else None
    if nf:
        print(f"    Fetching economic calendar...")
        nf._ensure_fresh()
        windows = nf.get_high_impact_windows()
        print(f"    Found {len(windows)} high-impact windows in range")
        for w in windows[:5]:
            print(f"      {w[0].strftime('%m/%d %H:%M')} - {w[1].strftime('%H:%M')}")
        if len(windows) > 5:
            print(f"      ... and {len(windows)-5} more")

    print("  Running stealth scalper backtest...")
    t0 = time.time()
    result = run_scalper_backtest(df5, df15, config, nf)
    elapsed = time.time() - t0
    print(f"  Completed in {elapsed:.1f}s")

    print_result(result, config)

    if args.csv:
        rows = []
        for t in result.trades:
            rows.append({
                'entry': t.entry_time.strftime('%Y-%m-%d %H:%M'),
                'side': t.side,
                'entry_price': round(t.entry_price, 2),
                'exit_price': round(t.exit_price, 2) if t.exit_price else 0,
                'lots': t.lots_at_open,
                'partial': t.partial_filled,
                'reason': t.exit_reason,
                'pnl': round(t.net_pnl + t.partial_pnl, 2),
                'costs': round(t.broker_costs, 2),
                'adx': round(t.adx_at_entry, 1),
                'regime': t.regime_at_entry,
            })
        pd.DataFrame(rows).to_csv(args.csv, index=False)
        print(f"  CSV: {args.csv}")

    print("  Done.")


if __name__ == "__main__":
    main()
