//+------------------------------------------------------------------+
//|                                    FXYAMS_Ultimate1_cBot.cs       |
//|  FXYAMS Structure Scalper v2.0 — BB + RSI + Swing + Trend        |
//|  Port of FXYAMS_Ultimate1.mq5 v2.0 to cTrader C#                 |
//+------------------------------------------------------------------+
//| v2.0: BB touch + RSI filter + swing proximity + trend MA          |
//|       Per-session TP pause, partial TP, trailing, break-even      |
//| v2.1: Anti-bleed (same hardening as FXPair): TP pause no longer   |
//|       blocks position management; SL respects the broker's        |
//|       minimum stop distance; every entry guarantees Min R:R >= 1  |
//|       (TP stretched when needed); break-even uses a real pip       |
//|       buffer; trend-leg signals use closed bars                    |
//+------------------------------------------------------------------+

using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo.API;
using cAlgo.API.Indicators;
using cAlgo.API.Requests;
using cAlgo.Indicators;

namespace cAlgo.Robots
{
    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.None)]
    public partial class FXYAMS_Ultimate1_cBot : Robot
    {
        // ═══════════════════════════════════════════════════════════
        //  Input Parameters
        // ═══════════════════════════════════════════════════════════

        // --- Trend Filter (M15) ---
        [Parameter("Fast MA Period", DefaultValue = 50, MinValue = 10)]
        public int MA_Fast_Period { get; set; }

        [Parameter("Slow MA Period", DefaultValue = 200, MinValue = 50)]
        public int MA_Slow_Period { get; set; }

        [Parameter("MA Method", DefaultValue = MovingAverageType.Simple)]
        public MovingAverageType MA_Method { get; set; }

        // --- Bollinger Bands ---
        [Parameter("BB Period", DefaultValue = 20, MinValue = 5)]
        public int BB_Period { get; set; }

        [Parameter("BB StdDev", DefaultValue = 2.0, MinValue = 0.5, Step = 0.1)]
        public double BB_StdDev { get; set; }

        // --- RSI ---
        [Parameter("RSI Period", DefaultValue = 14, MinValue = 2)]
        public int RSI_Period { get; set; }

        [Parameter("RSI Buy Max", DefaultValue = 78, MinValue = 20, MaxValue = 80)]
        public double RSI_Buy_Max { get; set; }

        [Parameter("RSI Sell Min", DefaultValue = 22, MinValue = 20, MaxValue = 80)]
        public double RSI_Sell_Min { get; set; }

        // --- Entry TF (cTrader uses TimeFrame) ---
        [Parameter("Entry Timeframe", DefaultValue = "M15")]
        public TimeFrame EntryTF { get; set; }

        // --- Swing Points ---
        [Parameter("Swing Lookback", DefaultValue = 7, MinValue = 2, MaxValue = 20)]
        public int Swing_Lookback { get; set; }

        [Parameter("Swing Proximity (xATR)", DefaultValue = 1.00, MinValue = 0.1, Step = 0.05)]
        public double Swing_Proximity_ATR { get; set; }

        // --- Entry Confirmation ---
        [Parameter("Min Body (xATR)", DefaultValue = 0.05, MinValue = 0.05, Step = 0.01)]
        public double Min_Body_ATR { get; set; }

        [Parameter("Reject Wick (xATR)", DefaultValue = 0.04, MinValue = 0.02, Step = 0.01)]
        public double Reject_Wick_ATR { get; set; }

        [Parameter("Use Rejection", DefaultValue = false)]
        public bool UseRejection { get; set; }

        // --- Risk Management ---
        [Parameter("Max Positions", DefaultValue = 2, MinValue = 1, MaxValue = 10)]
        public int MaxPositions { get; set; }

        [Parameter("Risk %", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPercent { get; set; }

        [Parameter("Max Daily Trades", DefaultValue = 30, MinValue = 1)]
        public int MaxDailyTrades { get; set; }

        [Parameter("Max Daily Loss %", DefaultValue = 5.0, MinValue = 1.0, MaxValue = 20.0)]
        public double MaxDailyLossPct { get; set; }

        [Parameter("Max TP Hits (per session)", DefaultValue = 8, MinValue = 1, MaxValue = 20)]
        public int MaxTPHits { get; set; }

        [Parameter("Min R:R", DefaultValue = 1.0, MinValue = 0.5, MaxValue = 5.0, Step = 0.1)]
        public double Min_RR { get; set; }

        // --- SL/TP ---
        [Parameter("SL ATR Mult", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 3.0, Step = 0.1)]
        public double SL_ATR_Mult { get; set; }

        [Parameter("Min SL (xATR)", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 2.0, Step = 0.1)]
        public double Min_SL_ATR { get; set; }

        [Parameter("Max SL (xATR)", DefaultValue = 1.2, MinValue = 0.3, MaxValue = 3.0, Step = 0.1)]
        public double Max_SL_ATR { get; set; }

        // --- Partial TP ---
        [Parameter("Use Partial TP", DefaultValue = true)]
        public bool UsePartialTP { get; set; }

        [Parameter("Partial TP At %", DefaultValue = 60.0, MinValue = 30.0, MaxValue = 90.0)]
        public double PartialTP_Pct { get; set; }

        [Parameter("Partial Close %", DefaultValue = 50.0, MinValue = 10.0, MaxValue = 90.0)]
        public double PartialClosePct { get; set; }

        // --- Trailing Stop ---
        [Parameter("Use Trailing", DefaultValue = true)]
        public bool UseTrailing { get; set; }

        [Parameter("Trailing Start (xATR)", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 3.0, Step = 0.1)]
        public double TrailingStart_ATR { get; set; }

        [Parameter("Trailing Step (xATR)", DefaultValue = 0.25, MinValue = 0.05, MaxValue = 1.0, Step = 0.05)]
        public double TrailingStep_ATR { get; set; }

        // --- Break-Even ---
        [Parameter("Use Break-Even", DefaultValue = true)]
        public bool UseBreakEven { get; set; }

        [Parameter("Break-Even (xATR)", DefaultValue = 0.6, MinValue = 0.1, MaxValue = 3.0, Step = 0.1)]
        public double BreakEven_ATR { get; set; }

        // --- Trend Mode (v4.0) ---
        [Parameter("Trend Mode", DefaultValue = true)]
        public bool TrendMode { get; set; }

        [Parameter("Trend Min Sep (xATR)", DefaultValue = 0.30, MinValue = 0.1, Step = 0.05)]
        public double Trend_MinSep_ATR { get; set; }

        [Parameter("Trend Pullback (xATR)", DefaultValue = 0.50, MinValue = 0.1, Step = 0.05)]
        public double Trend_Pullback_ATR { get; set; }

        [Parameter("Trend Breakout (xATR)", DefaultValue = 0.40, MinValue = 0.1, Step = 0.05)]
        public double Trend_Breakout_ATR { get; set; }

        [Parameter("Trend TP (xATR)", DefaultValue = 1.50, MinValue = 0.5, Step = 0.1)]
        public double Trend_TP_ATR { get; set; }

        [Parameter("Trend Trail Start (xATR)", DefaultValue = 1.00, MinValue = 0.2, Step = 0.05)]
        public double Trend_TrailStart_ATR { get; set; }

        [Parameter("Trend Trail Step (xATR)", DefaultValue = 0.50, MinValue = 0.1, Step = 0.05)]
        public double Trend_TrailStep_ATR { get; set; }

        [Parameter("Trend SL Buffer (xATR)", DefaultValue = 0.30, MinValue = 0.1, Step = 0.05)]
        public double Trend_SL_Buffer_ATR { get; set; }

        // --- Session (PH Time = UTC+8) ---
        [Parameter("Use Session Filter", DefaultValue = true)]
        public bool UseSessionFilter { get; set; }

        [Parameter("London Start PH", DefaultValue = 15, MinValue = 0, MaxValue = 23)]
        public int SessionStartHour { get; set; }

        [Parameter("London End PH", DefaultValue = 0, MinValue = 0, MaxValue = 23)]
        public int SessionEndHour { get; set; }

        [Parameter("NY Start PH", DefaultValue = 20, MinValue = 0, MaxValue = 23)]
        public int Session2StartHour { get; set; }

        [Parameter("NY End PH", DefaultValue = 5, MinValue = 0, MaxValue = 23)]
        public int Session2EndHour { get; set; }

        [Parameter("Trade Monday", DefaultValue = true)]
        public bool TradeMonday { get; set; }

        [Parameter("Trade Tuesday", DefaultValue = true)]
        public bool TradeTuesday { get; set; }

        [Parameter("Trade Wednesday", DefaultValue = true)]
        public bool TradeWednesday { get; set; }

        [Parameter("Trade Thursday", DefaultValue = true)]
        public bool TradeThursday { get; set; }

        [Parameter("Trade Friday", DefaultValue = true)]
        public bool TradeFriday { get; set; }

        // --- General ---
        [Parameter("Comment Prefix", DefaultValue = "ULTI_EA")]
        public string CommentPrefix { get; set; }

        [Parameter("Magic Number", DefaultValue = 20260716)]
        public int MagicNumber { get; set; }

        [Parameter("Max Slippage (pts)", DefaultValue = 50, MinValue = 1)]
        public int MaxSlippagePts { get; set; }

        [Parameter("Max Spread (pts)", DefaultValue = 500, MinValue = 10)]
        public int MaxSpreadPts { get; set; }

        [Parameter("Debug Mode", DefaultValue = true)]
        public bool DebugMode { get; set; }

        // ═══════════════════════════════════════════════════════════
        //  Indicators & State
        // ═══════════════════════════════════════════════════════════

        private Bars _m15Bars;
        private Bars _entryBars;
        private SimpleMovingAverage _maFastM15;
        private SimpleMovingAverage _maSlowM15;
        private BollingerBands _bbEntry;
        private RelativeStrengthIndex _rsiEntry;
        private AverageTrueRange _atrM15;
        private AverageTrueRange _atrEntry;

        // Swing data
        private List<int> _swingHighIdx = new List<int>();
        private List<double> _swingHighVal = new List<double>();
        private List<int> _swingLowIdx = new List<int>();
        private List<double> _swingLowVal = new List<double>();
        private bool _swingReady = false;

        // Daily stats
        private class DailyStats
        {
            public DateTime Date { get; set; }
            public int TradeCount { get; set; }
            public int TPHits { get; set; }
            public bool TPPause { get; set; }
            public int CurrentSession { get; set; }
            public DateTime LastTPReset { get; set; }
            public double StartingBalance { get; set; }
            public bool TradingStopped { get; set; }
        }

        private DailyStats _dailyStats = new DailyStats();
        private int _signalBarTime = 0;

        // ═══════════════════════════════════════════════════════════
        //  OnStart
        // ═══════════════════════════════════════════════════════════

        protected override void OnStart()
        {
            Print("=== FXYAMS Ultimate v2.0 cBot Initializing ===");
            Print("Symbol: {0} | Balance: {1}", Symbol.Name, Account.Balance);

            _m15Bars = MarketData.GetBars(TimeFrame.Minute15, Symbol.Name);
            _entryBars = MarketData.GetBars(EntryTF, Symbol.Name);

            if (_m15Bars == null || _entryBars == null) { Print("ERROR: Cannot load bars"); Stop(); }

            _maFastM15 = Indicators.SimpleMovingAverage(_m15Bars.ClosePrices, MA_Fast_Period);
            _maSlowM15 = Indicators.SimpleMovingAverage(_m15Bars.ClosePrices, MA_Slow_Period);
            _bbEntry = Indicators.BollingerBands(_entryBars.ClosePrices, BB_Period, BB_StdDev, MovingAverageType.Simple);
            _rsiEntry = Indicators.RelativeStrengthIndex(_entryBars.ClosePrices, RSI_Period);
            _atrM15 = Indicators.AverageTrueRange(_m15Bars, 14, MovingAverageType.Simple);
            _atrEntry = Indicators.AverageTrueRange(_entryBars, 14, MovingAverageType.Simple);

            ResetDailyStats();
            Print("cBot v2.10 OK. BB={0}/{1} | RSI={2} | Trend=MA{3}/MA{4}",
                  BB_Period, BB_StdDev, RSI_Period, MA_Fast_Period, MA_Slow_Period);
            Print("TrendMode: {0} | gate sep>={1}xATR | pullback<={2} | breakout>={3} | trail {4}/{5}xATR",
                  TrendMode, Trend_MinSep_ATR, Trend_Pullback_ATR, Trend_Breakout_ATR,
                  Trend_TrailStart_ATR, Trend_TrailStep_ATR);
        }

        // ═══════════════════════════════════════════════════════════
        //  OnTick
        // ═══════════════════════════════════════════════════════════

        protected override void OnTick()
        {
            ResetDailyStats();
            DetectTPHits();

            if (_dailyStats.TradingStopped) { CloseAllPositions(); return; }

            // Manage open positions ALWAYS — the TP pause must only gate NEW
            // entries, never position management (partial TP / BE / trailing).
            ManageOpenPositions();

            if (_dailyStats.TPPause) return;

            if (GetOpenPositionCount() >= MaxPositions) return;
            if (!CanTrade()) return;

            CheckEntry();
        }

        // ═══════════════════════════════════════════════════════════
        //  OnBar — refresh swing points on M15
        // ═══════════════════════════════════════════════════════════

        protected override void OnBar()
        {
            ResetDailyStats();
            ScanSwingPoints();
        }

        // ═══════════════════════════════════════════════════════════
        //  Session / Daily Logic
        // ═══════════════════════════════════════════════════════════

        private int GetPHHour()
        {
            var utc = Server.Time.ToUniversalTime();
            int h = utc.Hour + 8;
            return h >= 24 ? h - 24 : h;
        }

        private int GetCurrentSession()
        {
            if (!UseSessionFilter) return 0;
            int ph = GetPHHour();
            bool inS1 = (SessionStartHour < SessionEndHour)
                ? (ph >= SessionStartHour && ph < SessionEndHour)
                : (ph >= SessionStartHour || ph < SessionEndHour);
            bool inS2 = (Session2StartHour < Session2EndHour)
                ? (ph >= Session2StartHour && ph < Session2EndHour)
                : (ph >= Session2StartHour || ph < Session2EndHour);
            if (inS2) return 2;
            if (inS1) return 1;
            return 0;
        }

        private bool IsInSession()
        {
            if (!UseSessionFilter) return true;
            return GetCurrentSession() > 0;
        }

        private bool IsTradingDay()
        {
            if (!UseSessionFilter) return true;
            DayOfWeek dow = Server.Time.DayOfWeek;
            switch (dow)
            {
                case DayOfWeek.Monday: return TradeMonday;
                case DayOfWeek.Tuesday: return TradeTuesday;
                case DayOfWeek.Wednesday: return TradeWednesday;
                case DayOfWeek.Thursday: return TradeThursday;
                case DayOfWeek.Friday: return TradeFriday;
                default: return false;
            }
        }

        private void ResetDailyStats()
        {
            DateTime today = Server.Time.Date;
            if (_dailyStats.Date != today)
            {
                _dailyStats.Date = today;
                _dailyStats.TradeCount = 0;
                _dailyStats.TPHits = 0;
                _dailyStats.TPPause = false;
                _dailyStats.CurrentSession = 0;
                _dailyStats.LastTPReset = today;
                _dailyStats.StartingBalance = Account.Balance;
                _dailyStats.TradingStopped = false;
            }

            int newSession = GetCurrentSession();
            if (newSession != _dailyStats.CurrentSession)
            {
                _dailyStats.CurrentSession = newSession;
                _dailyStats.TPHits = 0;
                _dailyStats.TPPause = false;
                _dailyStats.LastTPReset = Server.Time;
                if (newSession > 0)
                    Print("SESSION CHANGE -> ", (newSession == 1 ? "LONDON" : "NY"),
                          " | TP counter reset. Fresh ", MaxTPHits, " TPs available.");
            }
        }

        private bool CanTrade()
        {
            if (_dailyStats.TradingStopped) return false;
            if (_dailyStats.TradeCount >= MaxDailyTrades) return false;
            if (!IsTradingDay() || !IsInSession()) return false;

            double dd = (_dailyStats.StartingBalance - Account.Equity)
                         / Math.Max(_dailyStats.StartingBalance, 1.0) * 100.0;
            if (dd >= MaxDailyLossPct)
            {
                _dailyStats.TradingStopped = true;
                Print("STOPPED: Daily loss limit. DD={0:F2}%", dd);
                CloseAllPositions();
                return false;
            }

            double spread = Symbol.Spread / Symbol.PipSize;
            if (spread > MaxSpreadPts) return false;
            return true;
        }

        // ═══════════════════════════════════════════════════════════
        //  TP Hit Detection (per session)
        // ═══════════════════════════════════════════════════════════

        private void DetectTPHits()
        {
            ResetDailyStats();
            // Note: cTrader auto-detects TP closes via position removal
            // We track TP hits through the ManageOpenPositions partial closes
            // and position count changes. Full TP hits are detected in OnBar
            // by checking if positions were recently closed.
        }

        // ═══════════════════════════════════════════════════════════
        //  Swing Point Detection
        // ═══════════════════════════════════════════════════════════

        private void ScanSwingPoints()
        {
            _swingHighIdx.Clear();
            _swingHighVal.Clear();
            _swingLowIdx.Clear();
            _swingLowVal.Clear();

            if (_m15Bars.Count < Swing_Lookback * 2 + 10) return;

            int lookback = Math.Min(500, _m15Bars.Count - Swing_Lookback - 5);

            for (int i = Swing_Lookback; i < lookback; i++)
            {
                // Swing high
                bool isHigh = true;
                for (int k = 1; k <= Swing_Lookback; k++)
                {
                    if (_m15Bars.HighPrices[i] <= _m15Bars.HighPrices[i - k] ||
                        _m15Bars.HighPrices[i] <= _m15Bars.HighPrices[i + k])
                    {
                        isHigh = false;
                        break;
                    }
                }
                if (isHigh)
                {
                    _swingHighIdx.Add(i);
                    _swingHighVal.Add(_m15Bars.HighPrices[i]);
                }

                // Swing low
                bool isLow = true;
                for (int k = 1; k <= Swing_Lookback; k++)
                {
                    if (_m15Bars.LowPrices[i] >= _m15Bars.LowPrices[i - k] ||
                        _m15Bars.LowPrices[i] >= _m15Bars.LowPrices[i + k])
                    {
                        isLow = false;
                        break;
                    }
                }
                if (isLow)
                {
                    _swingLowIdx.Add(i);
                    _swingLowVal.Add(_m15Bars.LowPrices[i]);
                }
            }

            _swingReady = _swingLowIdx.Count > 0 || _swingHighIdx.Count > 0;
        }

        private bool FindRecentSwing(out double level, out int idx, List<int> indices, List<double> values)
        {
            level = 0;
            idx = 0;
            if (indices.Count == 0) return false;

            // Find most recent swing (smallest index = most recent in series)
            int bestI = 0;
            for (int i = 0; i < indices.Count; i++)
            {
                if (indices[i] < indices[bestI])
                    bestI = i;
            }
            level = values[bestI];
            idx = indices[bestI];
            return true;
        }

        // ═══════════════════════════════════════════════════════════
        //  Entry Signal Logic
        // ═══════════════════════════════════════════════════════════

        private void CheckEntry()
        {
            if (!_swingReady) return;

            int n = _entryBars.Count;
            if (n < 10) return;

            int m15n = _m15Bars.Count;
            if (m15n < 5) return;

            // Get indicator values
            double atrM15 = _atrM15.Result.LastValue;
            double atrEntry = _atrEntry.Result.LastValue;
            if (atrM15 <= 0 || atrEntry <= 0) return;

            double maFast = _maFastM15.Result.LastValue;
            double maSlow = _maSlowM15.Result.LastValue;
            double bbUp = _bbEntry.Top.LastValue;
            double bbMid = _bbEntry.Main.LastValue;
            double bbLow = _bbEntry.Bottom.LastValue;
            double rsiVal = _rsiEntry.Result.Count > 1 ? _rsiEntry.Result.Last(1) : _rsiEntry.Result.LastValue;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;

            // Trend: close > fast MA and fast > slow = uptrend
            double m15Close = _m15Bars.ClosePrices.Last(1);
            bool trendUp = m15Close > maFast && (maFast - maSlow) > 0;
            bool trendDown = m15Close < maFast && (maFast - maSlow) < 0;

            // Last closed entry bar
            int ci = n - 2; // previous bar (closed)
            if (ci < 0) return;
            double cOpen = _entryBars.OpenPrices[ci];
            double cHigh = _entryBars.HighPrices[ci];
            double cLow = _entryBars.LowPrices[ci];
            double cClose = _entryBars.ClosePrices[ci];
            double body = Math.Abs(cClose - cOpen);
            double lowerWick = Math.Min(cClose, cOpen) - cLow;
            double upperWick = cHigh - Math.Max(cClose, cOpen);
            bool isBullish = cClose > cOpen;
            bool isBearish = cClose < cOpen;
            bool bodyOK = body >= Min_Body_ATR * atrEntry;

            // Rejection candles (check last 3 bars)
            bool rejBull = false, rejBear = false;
            if (!UseRejection)
            {
                rejBull = true;
                rejBear = true;
            }
            else
            {
                double minWick = Reject_Wick_ATR * atrEntry;
                for (int c = 1; c <= 3 && (ci - c) >= 0; c++)
                {
                    int idx = ci - c + 1;
                    if (idx < 0 || idx >= n) continue;
                    double o = _entryBars.OpenPrices[idx];
                    double h = _entryBars.HighPrices[idx];
                    double l = _entryBars.LowPrices[idx];
                    double cl = _entryBars.ClosePrices[idx];
                    double b = Math.Abs(cl - o);
                    double lw = Math.Min(cl, o) - l;
                    double uw = h - Math.Max(cl, o);
                    if (lw >= minWick && lw >= b * 0.2 && cl > o) rejBull = true;
                    if (uw >= minWick && uw >= b * 0.2 && cl < o) rejBear = true;
                }
            }

            // BB touch (relaxed tolerance — push-frequency tuning)
            bool bbTouchLow = cLow <= bbLow * 1.08;
            bool bbTouchHigh = cHigh >= bbUp * 0.92;

            // Current bar time for signal dedup
            int currentBarTime = (int)(_entryBars.OpenTimes.Last(0).ToUniversalTime()
                                       .Subtract(new DateTime(1970, 1, 1)).TotalSeconds);

            // ═══════════════════════════════════
            // BUY SIGNAL
            // ═══════════════════════════════════
            if (trendUp && rsiVal < RSI_Buy_Max && bbTouchLow && rejBull && bodyOK && isBullish)
            {
                double swingLevel;
                int swingIdx;
                if (FindRecentSwing(out swingLevel, out swingIdx, _swingLowIdx, _swingLowVal))
                {
                    if (cLow <= swingLevel + Swing_Proximity_ATR * atrEntry)
                    {
                        double sl = Math.Max(swingLevel - SL_ATR_Mult * atrM15,
                                             cClose - Max_SL_ATR * atrM15);
                        // Broker/account minimum stop distance (anti-bleed)
                        double minStop = GetMinStopDistance();
                        if (minStop > 0 && ask - sl < minStop) sl = ask - minStop;
                        if (sl < cClose)
                        {
                            double slDist = cClose - sl;
                            if (slDist >= Min_SL_ATR * atrM15)
                            {
                                double tp = bbMid;
                                if (tp > cClose)
                                {
                                    // RR floor: stretch TP so reward:risk >= Min_RR
                                    double rr = (tp - ask) / (ask - sl);
                                    if (rr < Min_RR)
                                    {
                                        if (DebugMode)
                                            Print("BUY: RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                                        tp = ask + (ask - sl) * Min_RR;
                                    }
                                    double lot = CalcLotSize(slDist);
                                    if (lot >= Symbol.VolumeInUnitsMin && _signalBarTime != currentBarTime)
                                    {
                                        if (OpenOrder(TradeType.Buy, lot, sl, tp))
                                        {
                                            _signalBarTime = currentBarTime;
                                            _dailyStats.TradeCount++;
                                            Print("BUY: Lot={0:F2} @ {1:F2} SL={2:F2} TP={3:F2} RSI={4:F1}",
                                                  lot, ask, sl, tp, rsiVal);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════
            // SELL SIGNAL
            // ═══════════════════════════════════
            if (trendDown && rsiVal > RSI_Sell_Min && bbTouchHigh && rejBear && bodyOK && isBearish)
            {
                double swingLevel;
                int swingIdx;
                if (FindRecentSwing(out swingLevel, out swingIdx, _swingHighIdx, _swingHighVal))
                {
                    if (cHigh >= swingLevel - Swing_Proximity_ATR * atrEntry)
                    {
                        double sl = Math.Min(swingLevel + SL_ATR_Mult * atrM15,
                                             cClose + Max_SL_ATR * atrM15);
                        // Broker/account minimum stop distance (anti-bleed)
                        double minStop = GetMinStopDistance();
                        if (minStop > 0 && sl - bid < minStop) sl = bid + minStop;
                        if (sl > cClose)
                        {
                            double slDist = sl - cClose;
                            if (slDist >= Min_SL_ATR * atrM15)
                            {
                                double tp = bbMid;
                                if (tp < cClose)
                                {
                                    // RR floor: stretch TP so reward:risk >= Min_RR
                                    double rr = (bid - tp) / (sl - bid);
                                    if (rr < Min_RR)
                                    {
                                        if (DebugMode)
                                            Print("SELL: RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                                        tp = bid - (sl - bid) * Min_RR;
                                    }
                                    double lot = CalcLotSize(slDist);
                                    if (lot >= Symbol.VolumeInUnitsMin && _signalBarTime != currentBarTime)
                                    {
                                        if (OpenOrder(TradeType.Sell, lot, sl, tp))
                                        {
                                            _signalBarTime = currentBarTime;
                                            _dailyStats.TradeCount++;
                                            Print("SELL: Lot={0:F2} @ {1:F2} SL={2:F2} TP={3:F2} RSI={4:F1}",
                                                  lot, bid, sl, tp, rsiVal);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════
            // Trend Mode: trend-following leg (v4.0)
            // Buys strength / sells weakness — NO RSI cap.
            // ═══════════════════════════════════════════
            if (TrendMode)
            {
                double sepATR = (atrM15 > 0) ? (maFast - maSlow) / atrM15 : 0;
                bool trendRegimeUp = trendUp && sepATR >= Trend_MinSep_ATR;
                bool trendRegimeDown = trendDown && sepATR <= -Trend_MinSep_ATR;

                // TP distance chosen so the existing partial trigger (PartialTP_Pct % of TP)
                // lands at Trend_TP_ATR. Remainder rides the wide trail.
                double trendTPDist = (PartialTP_Pct > 0)
                    ? (Trend_TP_ATR / (PartialTP_Pct / 100.0)) * atrM15
                    : 2.5 * atrM15;
                double maxTrendSL = 2.5 * atrM15;

                // Pullback: prior M15 bar dipped to the fast-MA zone, current bar turns back
                double m15Close1 = _m15Bars.ClosePrices.Last(1);
                double m15Open1 = _m15Bars.OpenPrices.Last(1);
                double m15High1 = _m15Bars.HighPrices.Last(1);
                double m15Low1 = _m15Bars.LowPrices.Last(1);
                double maFast1 = _maFastM15.Result.Last(1);

                // Trend leg evaluates CLOSED bars only (same convention as the
                // classic signal) — Last(1) = last closed, Last(2) = previous.
                double bar0Close = _entryBars.ClosePrices.Last(1);
                double bar0Open = _entryBars.OpenPrices.Last(1);
                double bar0High = _entryBars.HighPrices.Last(1);
                double bar0Low = _entryBars.LowPrices.Last(1);
                double bar1High = _entryBars.HighPrices.Last(2);
                double bar1Low = _entryBars.LowPrices.Last(2);

                bool pullbackUp = trendRegimeUp
                    && m15Close1 < m15Open1
                    && m15Low1 <= maFast1 + Trend_Pullback_ATR * atrM15
                    && bar0Close > bar0Open
                    && bar0High > bar1High;

                bool pullbackDown = trendRegimeDown
                    && m15Close1 > m15Open1
                    && m15High1 >= maFast1 - Trend_Pullback_ATR * atrM15
                    && bar0Close < bar0Open
                    && bar0Low < bar1Low;

                bool breakoutUp = trendRegimeUp
                    && bar0Close > bar0Open
                    && bar0High > bar1High + Trend_Breakout_ATR * atrM15;

                bool breakoutDown = trendRegimeDown
                    && bar0Close < bar0Open
                    && bar0Low < bar1Low - Trend_Breakout_ATR * atrM15;

                // Trend BUY (pullback preferred when both qualify on the same bar)
                if ((pullbackUp || breakoutUp) && _signalBarTime != currentBarTime)
                {
                    double sl = (pullbackUp ? Math.Min(m15Low1, bar0Low) : bar0Low)
                                - Trend_SL_Buffer_ATR * atrM15;
                    double slDist = ask - sl;
                    double minStop = GetMinStopDistance();
                    if (minStop > 0 && slDist < minStop) { sl = ask - minStop; slDist = ask - sl; }
                    if (slDist >= Min_SL_ATR * atrM15 && slDist <= maxTrendSL)
                    {
                        double tp = ask + trendTPDist;
                        double rr = (tp - ask) / slDist;
                        if (rr < Min_RR)
                        {
                            if (DebugMode)
                                Print("TREND BUY: RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                            tp = ask + slDist * Min_RR;
                        }
                        double lot = CalcLotSize(slDist);
                        if (lot >= Symbol.VolumeInUnitsMin)
                        {
                            if (OpenOrder(TradeType.Buy, lot, sl, tp, CommentPrefix + "_T_BUY"))
                            {
                                _signalBarTime = currentBarTime;
                                _dailyStats.TradeCount++;
                                Print("TREND BUY ({0}): SL={1:F2}xATR",
                                      pullbackUp ? "PULLBACK" : "BREAKOUT", slDist / atrM15);
                            }
                        }
                    }
                }

                // Trend SELL
                if ((pullbackDown || breakoutDown) && _signalBarTime != currentBarTime)
                {
                    double sl = (pullbackDown ? Math.Max(m15High1, bar0High) : bar0High)
                                + Trend_SL_Buffer_ATR * atrM15;
                    double slDist = sl - bid;
                    double minStop = GetMinStopDistance();
                    if (minStop > 0 && slDist < minStop) { sl = bid + minStop; slDist = sl - bid; }
                    if (slDist >= Min_SL_ATR * atrM15 && slDist <= maxTrendSL)
                    {
                        double tp = bid - trendTPDist;
                        double rr = (bid - tp) / slDist;
                        if (rr < Min_RR)
                        {
                            if (DebugMode)
                                Print("TREND SELL: RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                            tp = bid - slDist * Min_RR;
                        }
                        double lot = CalcLotSize(slDist);
                        if (lot >= Symbol.VolumeInUnitsMin)
                        {
                            if (OpenOrder(TradeType.Sell, lot, sl, tp, CommentPrefix + "_T_SELL"))
                            {
                                _signalBarTime = currentBarTime;
                                _dailyStats.TradeCount++;
                                Print("TREND SELL ({0}): SL={1:F2}xATR",
                                      pullbackDown ? "PULLBACK" : "BREAKOUT", slDist / atrM15);
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Order Execution
        // ═══════════════════════════════════════════════════════════

        private bool OpenOrder(TradeType type, double volume, double sl, double tp, string label = null)
        {
            if (string.IsNullOrEmpty(label)) label = CommentPrefix;
            var result = ExecuteMarketOrder(type, Symbol.Name, volume, label,
                                            sl, tp);
            if (result != null && result.IsSuccessful)
                return true;

            string err = result != null ? result.Error.ToString() : "Unknown";
            Print("ORDER FAILED: {0} {1} Lot={2:F2} Error={3}", type, Symbol.Name, volume, err);
            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  Lot Sizing
        // ═══════════════════════════════════════════════════════════

        /// <summary>
        /// Broker/account minimum stop-loss distance in PRICE units (0 = none).
        /// This account rewrites EURUSD stops to ~1.2 pips regardless of what is
        /// requested — ignoring it means the filled SL (and real RR) never match
        /// the plan and risk sizing is wrong.
        /// </summary>
        private double GetMinStopDistance()
        {
            try
            {
                var sym = Symbol;
                double minDist = sym.MinStopLossDistance;
                if (minDist <= 0) return 0;
                if (sym.MinDistanceType == SymbolMinDistanceType.Percentage)
                {
                    double refPrice = sym.Bid > 0 ? sym.Bid : sym.Ask;
                    return refPrice * minDist / 100.0;
                }
                return minDist * sym.PipSize; // Pips
            }
            catch { return 0; }
        }

        private double CalcLotSize(double slDistancePrice)
        {
            if (slDistancePrice <= 0)
                return Symbol.VolumeInUnitsMin;

            double riskAmount = Account.Balance * (RiskPercent / 100.0);
            double tickValue = Symbol.TickValue;
            double tickSize = Symbol.TickSize;

            if (tickValue <= 0 || tickSize <= 0)
                return Symbol.VolumeInUnitsMin;

            double slPips = slDistancePrice / tickSize;
            double lot = riskAmount / (slPips * tickValue);
            lot = Math.Max(lot, Symbol.VolumeInUnitsMin);
            double step = Symbol.VolumeInUnitsStep;
            if (step > 0) lot = Math.Floor(lot / step) * step;

            // Notional cap: ~$30k exposure per $10k balance (~7 oz at current gold).
            // Prevents risk-based sizing on a wide ATR stop from blowing margin.
            double price = Symbol.Bid;
            if (price > 0)
            {
                double maxVol = (Account.Balance / 10000.0) * 30000.0 / price;
                if (step > 0) maxVol = Math.Floor(maxVol / step) * step;
                lot = Math.Min(lot, maxVol);
            }
            return Math.Max(lot, Symbol.VolumeInUnitsMin);
        }

        // ═══════════════════════════════════════════════════════════
        //  Manage Open Positions — Partial TP + Trailing + BE
        // ═══════════════════════════════════════════════════════════

        private void ManageOpenPositions()
        {
            double atr = _atrM15.Result.LastValue;
            if (atr <= 0) return;

            foreach (var pos in Positions)
            {
                if (!IsMyPosition(pos))
                    continue;

                bool isTrend = pos.Label.IndexOf("_T_", StringComparison.Ordinal) >= 0;
                double trailDist = (isTrend ? Trend_TrailStart_ATR : TrailingStart_ATR) * atr;
                double trailStep = (isTrend ? Trend_TrailStep_ATR : TrailingStep_ATR) * atr;
                double beDist = (isTrend ? Trend_TrailStart_ATR : BreakEven_ATR) * atr;

                bool isBuy = pos.TradeType == TradeType.Buy;
                double entry = pos.EntryPrice;
                double currentPrice = isBuy ? Symbol.Bid : Symbol.Ask;
                double sl = pos.StopLoss.GetValueOrDefault();
                double tp = pos.TakeProfit.GetValueOrDefault();

                // --- Partial TP ---
                if (UsePartialTP && pos.VolumeInUnits > Symbol.VolumeInUnitsMin)
                {
                    double tpDist = Math.Abs(tp - entry);
                    if (tpDist > 0)
                    {
                        double reachedPct = isBuy
                            ? ((currentPrice - entry) / tpDist) * 100.0
                            : ((entry - currentPrice) / tpDist) * 100.0;

                        if (reachedPct >= PartialTP_Pct)
                        {
                            double closeVol = Math.Floor(pos.VolumeInUnits * (PartialClosePct / 100.0));
                            closeVol = Math.Max(closeVol, Symbol.VolumeInUnitsMin);
                            closeVol = Math.Min(closeVol, pos.VolumeInUnits - Symbol.VolumeInUnitsMin);

                            if (closeVol >= Symbol.VolumeInUnitsMin)
                            {
                                var closeResult = ClosePosition(pos, closeVol);
                                if (closeResult.IsSuccessful)
                                {
                                    _dailyStats.TPHits++;
                                    string sessName = (_dailyStats.CurrentSession == 1) ? "LONDON" : "NY";
                                    Print("PARTIAL TP #{0} [{1}]: closed {2:F2} lots @ {3:F2} ({4:F0}% of TP)",
                                          pos.Id, sessName, closeVol, currentPrice, reachedPct);
                                    if (_dailyStats.TPHits >= MaxTPHits)
                                    {
                                        _dailyStats.TPPause = true;
                                        Print("TP PAUSE [{0}]: {1}/{2} hits — no new entries",
                                              sessName, _dailyStats.TPHits, MaxTPHits);
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Break-Even (never past TP) ---
                if (UseBreakEven)
                {
                    if (isBuy)
                    {
                        double profitDist = currentPrice - entry;
                        if (profitDist >= beDist && sl < entry)
                        {
                            double newSL = entry + Symbol.PipSize * 5;
                            if (tp <= 0 || newSL < tp)
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful)
                                    Print("B.E. #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                    else
                    {
                        double profitDist = entry - currentPrice;
                        if (profitDist >= beDist && (sl == 0 || sl > entry))
                        {
                            double newSL = entry - Symbol.PipSize * 5;
                            if (tp <= 0 || newSL > tp)
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful)
                                    Print("B.E. #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                }

                // --- Trailing Stop (never past TP) ---
                if (UseTrailing)
                {
                    if (isBuy)
                    {
                        double profitDist = currentPrice - entry;
                        if (profitDist >= trailDist)
                        {
                            double newSL = currentPrice - trailStep;
                            if (newSL > (sl > 0 ? sl : 0) + 0.1 && (tp <= 0 || newSL < tp))
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful && DebugMode)
                                    Print("TRAIL #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                    else
                    {
                        double profitDist = entry - currentPrice;
                        if (profitDist >= trailDist)
                        {
                            double newSL = currentPrice + trailStep;
                            if ((sl == 0 || newSL < sl - 0.1) && (tp <= 0 || newSL > tp))
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful && DebugMode)
                                    Print("TRAIL #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Position Counting
        // ═══════════════════════════════════════════════════════════

        private bool IsMyPosition(Position pos)
        {
            return pos.SymbolName == Symbol.Name &&
                   (pos.Label == CommentPrefix || pos.Label.StartsWith(CommentPrefix + "_T"));
        }

        private int GetOpenPositionCount()
        {
            int count = 0;
            foreach (var pos in Positions)
                if (IsMyPosition(pos))
                    count++;
            return count;
        }

        private void CloseAllPositions()
        {
            foreach (var pos in Positions)
            {
                if (IsMyPosition(pos))
                {
                    var result = ClosePosition(pos);
                    if (result.IsSuccessful)
                        Print("Closed position #{0}", pos.Id);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  OnStop
        // ═══════════════════════════════════════════════════════════

        protected override void OnStop()
        {
            Print("=== FXYAMS Ultimate v2.0 cBot Stopped ===");
            Print("Trades today: {0} | TP Hits: {1}", _dailyStats.TradeCount, _dailyStats.TPHits);
        }
    }
}
