//+------------------------------------------------------------------+
//|                                      FXRE_Hybrid_cBot.cs           |
//|  FXRE Hybrid v2.0 cBot — S&D Zones + Trailing + Partial TP + BE   |
//|  Port of FXRE_Hybrid_EA.mq5 v2.0 to cTrader C#                   |
//+------------------------------------------------------------------+
//| v2.0: ATR clustering, London+NY sessions, partial TP, trailing,   |
//|       break-even, TP pause, proper EMA200                          |
//| v2.1: Anti-bleed (same hardening as FXPair): the Min R:R parameter|
//|       is now actually enforced (TP stretched when needed), SL     |
//|       respects the broker's minimum stop distance, break-even     |
//|       uses a real pip buffer, trend filter uses closed bars,      |
//|       lot sizing capped by notional (~$30k per $10k balance)       |
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
    public partial class FXRE_Hybrid_cBot : Robot
    {
        // ═══════════════════════════════════════════════════════════
        //  Input Parameters — match FXRE_Hybrid_EA.mq5 defaults
        // ═══════════════════════════════════════════════════════════

        // --- Swing S&D ---
        [Parameter("Swing Lookback Bars", DefaultValue = 3, MinValue = 1, MaxValue = 10)]
        public int SwingLookbackBars { get; set; }

        [Parameter("Cluster ATR Mult", DefaultValue = 0.6, MinValue = 0.5, MaxValue = 5.0, Step = 0.1)]
        public double SwingClusterATR { get; set; }

        [Parameter("Max Zone Age (M15)", DefaultValue = 240, MinValue = 10)]
        public int SwingMaxAge { get; set; }

        [Parameter("Min Zone Strength", DefaultValue = 0.3, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double SwingMinStrength { get; set; }

        // --- Entry Confirmation ---
        [Parameter("Require Zone Reject", DefaultValue = true)]
        public bool RequireZoneReject { get; set; }

        [Parameter("Min Reject Wick (xATR)", DefaultValue = 0.05, MinValue = 0.05, Step = 0.01)]
        public double MinRejectWickATR { get; set; }

        [Parameter("Zone Proximity (xATR)", DefaultValue = 2.0, MinValue = 0.1, Step = 0.05)]
        public double ZoneProximityATR { get; set; }

        // --- Trend Filter ---
        [Parameter("Use Trend Filter", DefaultValue = true)]
        public bool UseTrendFilter { get; set; }

        [Parameter("EMA Period", DefaultValue = 200, MinValue = 50)]
        public int TrendFilterEMAPeriod { get; set; }

        // --- Risk Management ---
        [Parameter("Risk %", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPerTradePct { get; set; }

        [Parameter("SL Buffer (xATR)", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 2.0, Step = 0.1)]
        public double SLBufferATR { get; set; }

        [Parameter("TP Multiplier", DefaultValue = 1.5, MinValue = 0.5, MaxValue = 5.0, Step = 0.1)]
        public double TPMultiplier { get; set; }

        [Parameter("Min TP (xATR)", DefaultValue = 1.2, MinValue = 0.3, MaxValue = 3.0, Step = 0.1)]
        public double TPMinATR { get; set; }

        [Parameter("Min R:R", DefaultValue = 1.5, MinValue = 1.0, MaxValue = 5.0, Step = 0.1)]
        public double MinRR { get; set; }

        // --- Partial TP (NEW v2.0) ---
        [Parameter("Use Partial TP", DefaultValue = true)]
        public bool UsePartialTP { get; set; }

        [Parameter("Partial TP At %", DefaultValue = 60.0, MinValue = 30.0, MaxValue = 90.0)]
        public double PartialTPPct { get; set; }

        [Parameter("Partial Close %", DefaultValue = 50.0, MinValue = 10.0, MaxValue = 90.0)]
        public double PartialClosePct { get; set; }

        // --- Trailing Stop (NEW v2.0) ---
        [Parameter("Use Trailing", DefaultValue = true)]
        public bool UseTrailing { get; set; }

        [Parameter("Trailing Start (xATR)", DefaultValue = 0.6, MinValue = 0.2, MaxValue = 3.0, Step = 0.1)]
        public double TrailingStartATR { get; set; }

        [Parameter("Trailing Step (xATR)", DefaultValue = 0.25, MinValue = 0.1, MaxValue = 1.0, Step = 0.05)]
        public double TrailingStepATR { get; set; }

        // --- Break-Even (NEW v2.0) ---
        [Parameter("Use Break-Even", DefaultValue = true)]
        public bool UseBreakEven { get; set; }

        [Parameter("Break-Even (xATR)", DefaultValue = 0.8, MinValue = 0.3, MaxValue = 3.0, Step = 0.1)]
        public double BreakEvenATR { get; set; }

        // --- Safety Limits ---
        [Parameter("Max Positions", DefaultValue = 2, MinValue = 1, MaxValue = 10)]
        public int MaxPositions { get; set; }

        [Parameter("Max Daily Trades", DefaultValue = 8, MinValue = 1)]
        public int MaxDailyTrades { get; set; }

        [Parameter("Max Daily Loss %", DefaultValue = 5.0, MinValue = 1.0, MaxValue = 20.0)]
        public double MaxDailyLossPct { get; set; }

        [Parameter("Max TP Hits (per session)", DefaultValue = 8, MinValue = 1, MaxValue = 20)]
        public int MaxTPHits { get; set; }

        // --- Session (PH Time = UTC+8) ---
        [Parameter("Use Session Filter", DefaultValue = true)]
        public bool UseSessionFilter { get; set; }

        [Parameter("London Start PH", DefaultValue = 15, MinValue = 0, MaxValue = 23)]
        public int Session1StartHour { get; set; }

        [Parameter("London End PH", DefaultValue = 0, MinValue = 0, MaxValue = 23)]
        public int Session1EndHour { get; set; }

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
        [Parameter("Magic Number", DefaultValue = 20241201)]
        public int MagicNumber { get; set; }

        [Parameter("Comment Prefix", DefaultValue = "HYBRID_EA")]
        public string CommentPrefix { get; set; }

        [Parameter("Max Slippage (pts)", DefaultValue = 50, MinValue = 1)]
        public int MaxSlippagePts { get; set; }

        [Parameter("Max Spread (pts)", DefaultValue = 800, MinValue = 10)]
        public int MaxSpreadPts { get; set; }

        [Parameter("Debug Mode", DefaultValue = true)]
        public bool DebugMode { get; set; }

        // ═══════════════════════════════════════════════════════════
        //  SwingSDZone — matches MQL5 struct
        // ═══════════════════════════════════════════════════════════

        private struct SwingSDZone
        {
            public DateTime FormationTime;
            public double PriceHigh;
            public double PriceLow;
            public double PriceMid;
            public bool IsDemand;
            public double Strength;    // 1.0 – 5.0
            public int AgeCandles;     // candles since last swing
            public int SwingCount;
            public double ZoneWidth;
        }

        // ═══════════════════════════════════════════════════════════
        //  Daily Stats
        // ═══════════════════════════════════════════════════════════

        private class DailyStats
        {
            public DateTime Date { get; set; }
            public int TradeCount { get; set; }
            public int TPHits { get; set; }          // TPs hit in CURRENT session
            public bool TPPause { get; set; }         // TP pause for current session
            public int CurrentSession { get; set; }   // 0=none, 1=session1, 2=session2
            public DateTime LastTPReset { get; set; } // When tpHits was last reset
            public double StartingBalance { get; set; }
            public bool TradingStopped { get; set; }
        }

        // ═══════════════════════════════════════════════════════════
        //  State
        // ═══════════════════════════════════════════════════════════

        private List<SwingSDZone> _demandZones = new List<SwingSDZone>();
        private List<SwingSDZone> _supplyZones = new List<SwingSDZone>();
        private DailyStats _dailyStats = new DailyStats();
        private int _signalBarTime = 0;
        private DateTime _lastZoneScan = DateTime.MinValue;
        private double _atrValue = 0.0;
        private double _atrValueM5 = 0.0;
        private Bars _m15Bars;
        private ExponentialMovingAverage _ema200;
        private AverageTrueRange _atrIndicator;
        private AverageTrueRange _atrIndicatorM5;

        // ═══════════════════════════════════════════════════════════
        //  OnStart
        // ═══════════════════════════════════════════════════════════

        protected override void OnStart()
        {
            Print("=== FXRE Hybrid v2.0 cBot Initializing ===");
            Print("Symbol: {0} | Balance: {1}", Symbol.Name, Account.Balance);

            if (SwingLookbackBars < 1) { Print("ERROR: SwingLookbackBars must be >= 1"); Stop(); }
            if (SwingMinStrength < 0.1) { Print("ERROR: SwingMinStrength must be >= 0.1"); Stop(); }

            _m15Bars = MarketData.GetBars(TimeFrame.Minute15, Symbol.Name);
            if (_m15Bars == null) { Print("ERROR: Cannot load M15 bars"); Stop(); }

            _atrIndicator = Indicators.AverageTrueRange(_m15Bars, 14, MovingAverageType.Simple);
            _atrIndicatorM5 = Indicators.AverageTrueRange(Bars, 14, MovingAverageType.Simple);

            if (UseTrendFilter)
                _ema200 = Indicators.ExponentialMovingAverage(_m15Bars.ClosePrices, TrendFilterEMAPeriod);

            ResetDailyStats();
            Print("cBot v2.0 OK. SL={0}xATR | TP={1}x | Partial={2} | Trailing={3} | BE={4} | TP Pause={5}",
                  SLBufferATR, TPMultiplier, UsePartialTP, UseTrailing, UseBreakEven, MaxTPHits);
        }

        // ═══════════════════════════════════════════════════════════
        //  OnTick
        // ═══════════════════════════════════════════════════════════

        protected override void OnTick()
        {
            ResetDailyStats();

            if (_dailyStats.TradingStopped) { CloseAllPositions(); UpdateChart(); return; }

            // Manage open positions (partial TP, trailing, BE)
            ManageOpenPositions();

            if (GetOpenPositionCount() >= MaxPositions) { UpdateChart(); return; }
            if (!CanTrade() || !ShouldTradeNow()) { UpdateChart(); return; }

            // Update ATR from indicators
            if (_atrIndicator != null)
                _atrValue = _atrIndicator.Result.LastValue;
            if (_atrIndicatorM5 != null)
                _atrValueM5 = _atrIndicatorM5.Result.LastValue;

            if (_atrValue <= 0) { UpdateChart(); return; }
            if (_atrValueM5 <= 0) { UpdateChart(); return; }

            CheckSDEntry();
            UpdateChart();
        }

        // ═══════════════════════════════════════════════════════════
        //  OnBar — refresh zones on M15 close
        // ═══════════════════════════════════════════════════════════

        protected override void OnBar()
        {
            ResetDailyStats();
            if (_m15Bars != null && _m15Bars.Count > SwingLookbackBars * 2 + 10)
            {
                ScanSwingZones();
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  SWING-POINT S&D ZONE DETECTION (FXRE_SwingSD.mqh port)
        // ═══════════════════════════════════════════════════════════

        /// <summary>
        /// Port of FXRE_SwingSD.mqh :: DetectSwingZones()
        /// Detects swing highs (supply) and swing lows (demand),
        /// clusters nearby swings by price, filters by age/strength.
        /// </summary>
        private void ScanSwingZones()
        {
            _demandZones.Clear();
            _supplyZones.Clear();

            int n = _m15Bars.Count;
            if (n < SwingLookbackBars * 2 + 10) return;

            int lookback = Math.Min(1000, n - SwingLookbackBars - 5);
            int look = SwingLookbackBars;
            double atr = _atrIndicator != null ? _atrIndicator.Result.LastValue : 0;
            double clusterThresh = SwingClusterATR * atr;

            // --- Phase 1: Collect raw swing points ---
            var rawSwings = new List<(double price, int idx, int strength, bool isDemand)>();

            for (int i = look; i < lookback - look; i++)
            {
                // Swing high (supply potential)
                bool isHigh = true;
                for (int k = 1; k <= look; k++)
                {
                    if (_m15Bars.HighPrices[i] < _m15Bars.HighPrices[i - k] ||
                        _m15Bars.HighPrices[i] < _m15Bars.HighPrices[i + k] ||
                        _m15Bars.HighPrices[i] <= _m15Bars.HighPrices[i - 1])
                    {
                        isHigh = false;
                        break;
                    }
                }
                if (isHigh)
                {
                    int str = 1;
                    for (int k = 1; k <= look; k++)
                        if (_m15Bars.ClosePrices[i] > _m15Bars.ClosePrices[i + k])
                            str++;
                    str = Math.Min(str, 5);
                    rawSwings.Add((_m15Bars.HighPrices[i], i, str, false));
                }

                // Swing low (demand potential)
                bool isLow = true;
                for (int k = 1; k <= look; k++)
                {
                    if (_m15Bars.LowPrices[i] > _m15Bars.LowPrices[i - k] ||
                        _m15Bars.LowPrices[i] > _m15Bars.LowPrices[i + k] ||
                        _m15Bars.LowPrices[i] >= _m15Bars.LowPrices[i - 1])
                    {
                        isLow = false;
                        break;
                    }
                }
                if (isLow)
                {
                    int str = 1;
                    for (int k = 1; k <= look; k++)
                        if (_m15Bars.ClosePrices[i] < _m15Bars.ClosePrices[i + k])
                            str++;
                    str = Math.Min(str, 5);
                    rawSwings.Add((_m15Bars.LowPrices[i], i, str, true));
                }
            }

            if (rawSwings.Count == 0) return;

            // --- Phase 2: Sort by price ---
            rawSwings.Sort((a, b) => a.price.CompareTo(b.price));

            // --- Phase 3: Cluster nearby swings ---
            var tempDZ = new List<SwingSDZone>();
            var tempSZ = new List<SwingSDZone>();

            // Cluster demand swings
            foreach (var r in rawSwings)
            {
                if (!r.isDemand) continue;

                if (tempDZ.Count == 0 ||
                    r.price - tempDZ[tempDZ.Count - 1].PriceHigh > clusterThresh)
                {
                    tempDZ.Add(new SwingSDZone
                    {
                        FormationTime = _m15Bars.OpenTimes[r.idx],
                        PriceHigh = r.price,
                        PriceLow = r.price,
                        PriceMid = r.price,
                        IsDemand = true,
                        Strength = r.strength,
                        AgeCandles = r.idx,
                        SwingCount = 1,
                        ZoneWidth = 0.0
                    });
                }
                else
                {
                    var ci = tempDZ[tempDZ.Count - 1];
                    if (r.price > ci.PriceHigh) ci.PriceHigh = r.price;
                    if (r.price < ci.PriceLow) ci.PriceLow = r.price;
                    ci.PriceMid = (ci.PriceHigh + ci.PriceLow) / 2.0;
                    ci.Strength = (ci.Strength * ci.SwingCount + r.strength) / (ci.SwingCount + 1);
                    ci.SwingCount++;
                    if (r.idx > ci.AgeCandles) ci.AgeCandles = r.idx;
                    ci.ZoneWidth = ci.PriceHigh - ci.PriceLow;
                    tempDZ[tempDZ.Count - 1] = ci;
                }
            }

            // Cluster supply swings
            foreach (var r in rawSwings)
            {
                if (r.isDemand) continue;

                if (tempSZ.Count == 0 ||
                    r.price - tempSZ[tempSZ.Count - 1].PriceHigh > clusterThresh)
                {
                    tempSZ.Add(new SwingSDZone
                    {
                        FormationTime = _m15Bars.OpenTimes[r.idx],
                        PriceHigh = r.price,
                        PriceLow = r.price,
                        PriceMid = r.price,
                        IsDemand = false,
                        Strength = r.strength,
                        AgeCandles = r.idx,
                        SwingCount = 1,
                        ZoneWidth = 0.0
                    });
                }
                else
                {
                    var ci = tempSZ[tempSZ.Count - 1];
                    if (r.price > ci.PriceHigh) ci.PriceHigh = r.price;
                    if (r.price < ci.PriceLow) ci.PriceLow = r.price;
                    ci.PriceMid = (ci.PriceHigh + ci.PriceLow) / 2.0;
                    ci.Strength = (ci.Strength * ci.SwingCount + r.strength) / (ci.SwingCount + 1);
                    ci.SwingCount++;
                    if (r.idx > ci.AgeCandles) ci.AgeCandles = r.idx;
                    ci.ZoneWidth = ci.PriceHigh - ci.PriceLow;
                    tempSZ[tempSZ.Count - 1] = ci;
                }
            }

            // --- Phase 4: Filter by age & strength ---
            foreach (var z in tempDZ)
            {
                if (z.AgeCandles <= SwingMaxAge && z.Strength >= SwingMinStrength)
                    _demandZones.Add(z);
            }
            foreach (var z in tempSZ)
            {
                if (z.AgeCandles <= SwingMaxAge && z.Strength >= SwingMinStrength)
                    _supplyZones.Add(z);
            }

            // Sort by strength descending
            _demandZones = _demandZones.OrderByDescending(z => z.Strength).ToList();
            _supplyZones = _supplyZones.OrderByDescending(z => z.Strength).ToList();

            _lastZoneScan = Server.Time;
        }

        // ═══════════════════════════════════════════════════════════
        //  Zone Proximity (port of GetNearestDemandZone / GetNearestSupplyZone)
        // ═══════════════════════════════════════════════════════════

        private SwingSDZone? GetNearestDemandZone(double price)
        {
            if (_demandZones.Count == 0) return null;
            double thresh = _atrValue * ZoneProximityATR;
            double nearestDist = double.MaxValue;
            SwingSDZone? nearest = null;

            foreach (var z in _demandZones)
            {
                if (price < z.PriceLow - thresh) continue;
                double dist = price - z.PriceMid;
                if (dist >= -thresh && dist < nearestDist)
                {
                    nearestDist = dist;
                    nearest = z;
                }
            }
            return nearest;
        }

        private SwingSDZone? GetNearestSupplyZone(double price)
        {
            if (_supplyZones.Count == 0) return null;
            double thresh = _atrValue * ZoneProximityATR;
            double nearestDist = double.MaxValue;
            SwingSDZone? nearest = null;

            foreach (var z in _supplyZones)
            {
                if (price > z.PriceHigh + thresh) continue;
                double dist = z.PriceMid - price;
                if (dist >= -thresh && dist < nearestDist)
                {
                    nearestDist = dist;
                    nearest = z;
                }
            }
            return nearest;
        }

        // ═══════════════════════════════════════════════════════════
        //  Entry Signal Logic (matches FXRE_Hybrid_EA.mq5 CheckHybridEntry)
        // ═══════════════════════════════════════════════════════════

        private void CheckSDEntry()
        {
            var m5Bars = Bars;
            if (m5Bars.Count < 5) return;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            int currentBarTime = (int)(m5Bars.OpenTimes[m5Bars.Count - 1].ToUniversalTime()
                                         .Subtract(new DateTime(1970, 1, 1)).TotalSeconds);

            // --- Trend filter ---
            bool trendBull = true, trendBear = true;
            if (UseTrendFilter && _ema200 != null && Bars.ClosePrices.Count > TrendFilterEMAPeriod + 2)
            {
                trendBull = Bars.ClosePrices.Last(1) > _ema200.Result.Last(1);
                trendBear = Bars.ClosePrices.Last(1) < _ema200.Result.Last(1);
            }

            // --- Find nearest zones ---
            var nearDemand = GetNearestDemandZone(bid);
            var nearSupply = GetNearestSupplyZone(bid);

            // --- M5 rejection candle check ---
            bool rejectionBull = false, rejectionBear = false;

            if (!RequireZoneReject)
            {
                rejectionBull = true;
                rejectionBear = true;
            }
            else
            {
                double minWick = MinRejectWickATR * _atrValueM5;

                for (int c = 1; c <= 3; c++)
                {
                    int idx = m5Bars.Count - 1 - c;
                    if (idx < 0) continue;

                    double open = m5Bars.OpenPrices[idx];
                    double high = m5Bars.HighPrices[idx];
                    double low = m5Bars.LowPrices[idx];
                    double close = m5Bars.ClosePrices[idx];
                    double body = Math.Abs(close - open);

                    // Bullish rejection: long lower wick, bullish close
                    double lowerWick = Math.Min(close, open) - low;
                    if (lowerWick >= minWick && lowerWick >= body * 0.3 && close > open)
                        rejectionBull = true;

                    // Bearish rejection: long upper wick, bearish close
                    double upperWick = high - Math.Max(close, open);
                    if (upperWick >= minWick && upperWick >= body * 0.3 && close < open)
                        rejectionBear = true;
                }
            }

            // --- BUY SIGNAL ---
            if (nearDemand.HasValue && rejectionBull && trendBull &&
                _signalBarTime != currentBarTime)
            {
                double zoneWidth = Math.Max(nearDemand.Value.ZoneWidth, _atrValue * 0.15);
                double sl = nearDemand.Value.PriceLow - SLBufferATR * _atrValue;
                // Broker/account minimum stop distance (anti-bleed)
                double minStop = GetMinStopDistance();
                if (minStop > 0 && bid - sl < minStop) sl = bid - minStop;
                double tp = bid + Math.Max(zoneWidth * TPMultiplier, _atrValue * TPMinATR);

                // RR floor: stretch TP so reward:risk >= MinRR. The MinRR parameter
                // was declared but never enforced — this makes it real.
                double slDistBuy = bid - sl;
                double rrBuy = slDistBuy > 0 ? (tp - bid) / slDistBuy : 0;
                if (rrBuy < MinRR)
                {
                    if (DebugMode)
                        Print("BUY: RR ", rrBuy.ToString("F2"), " < MinRR ", MinRR.ToString("F1"), " — stretching TP");
                    tp = bid + slDistBuy * MinRR;
                }

                double lot = CalcRiskLot((bid - sl));

                // SL floor: never let a stop sit inside normal noise (mirrors FXRE_Hybrid_EA.mq5)
                if ((bid - sl) >= _atrValue && OpenOrderHybrid(TradeType.Buy, lot, sl, tp))
                {
                    _signalBarTime = currentBarTime;
                    _dailyStats.TradeCount++;
                    Print("BUY: Lot={0:F2} @ {1:F2} SL={2:F2} TP={3:F2} DZ=[{4:F2}-{5:F2}] str={6:F1}",
                          lot, ask, sl, tp,
                          nearDemand.Value.PriceLow, nearDemand.Value.PriceHigh,
                          nearDemand.Value.Strength);
                }
            }

            // --- SELL SIGNAL ---
            if (nearSupply.HasValue && rejectionBear && trendBear &&
                _signalBarTime != currentBarTime)
            {
                double zoneWidth = Math.Max(nearSupply.Value.ZoneWidth, _atrValue * 0.15);
                double sl = nearSupply.Value.PriceHigh + SLBufferATR * _atrValue;
                // Broker/account minimum stop distance (anti-bleed)
                double minStop = GetMinStopDistance();
                if (minStop > 0 && sl - bid < minStop) sl = bid + minStop;
                double tp = bid - Math.Max(zoneWidth * TPMultiplier, _atrValue * TPMinATR);

                // RR floor: stretch TP so reward:risk >= MinRR
                double slDistSell = sl - bid;
                double rrSell = slDistSell > 0 ? (bid - tp) / slDistSell : 0;
                if (rrSell < MinRR)
                {
                    if (DebugMode)
                        Print("SELL: RR ", rrSell.ToString("F2"), " < MinRR ", MinRR.ToString("F1"), " — stretching TP");
                    tp = bid - slDistSell * MinRR;
                }

                double lot = CalcRiskLot((sl - bid));

                if ((sl - bid) >= _atrValue && OpenOrderHybrid(TradeType.Sell, lot, sl, tp))
                {
                    _signalBarTime = currentBarTime;
                    _dailyStats.TradeCount++;
                    Print("SELL: Lot={0:F2} @ {1:F2} SL={2:F2} TP={3:F2} SZ=[{4:F2}-{5:F2}] str={6:F1}",
                          lot, bid, sl, tp,
                          nearSupply.Value.PriceLow, nearSupply.Value.PriceHigh,
                          nearSupply.Value.Strength);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Order Execution
        // ═══════════════════════════════════════════════════════════

        private bool OpenOrderHybrid(TradeType type, double volume, double sl, double tp)
        {
            var result = ExecuteMarketOrder(type, Symbol.Name, volume, CommentPrefix,
                                            sl, tp);
            if (result != null && result.IsSuccessful)
                return true;

            string err = result != null ? result.Error.ToString() : "Unknown";
            Print("ORDER FAILED: {0} {1} Lot={2:F2} Error={3}",
                  type, Symbol.Name, volume, err);
            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  Manage Open Positions — Partial TP + Trailing + BE (v2.0)
        // ═══════════════════════════════════════════════════════════

        private void ManageOpenPositions()
        {
            double atr = _atrValue;
            if (atr <= 0) return;

            double trailDist = TrailingStartATR * atr;
            double trailStep = TrailingStepATR * atr;
            double beDist = BreakEvenATR * atr;

            foreach (var pos in Positions)
            {
                if (pos.SymbolName != Symbol.Name || pos.Label != CommentPrefix)
                    continue;

                bool isBuy = pos.TradeType == TradeType.Buy;
                double entry = pos.EntryPrice;
                double currentPrice = isBuy ? Symbol.Bid : Symbol.Ask;
                double sl = pos.StopLoss.GetValueOrDefault();
                double tp = pos.TakeProfit.GetValueOrDefault();
                double openPrice = pos.EntryPrice;

                // --- Partial TP ---
                if (UsePartialTP && pos.VolumeInUnits > Symbol.VolumeInUnitsMin)
                {
                    double tpDist = Math.Abs(tp - entry);
                    if (tpDist > 0)
                    {
                        double reachedPct = 0;
                        if (isBuy)
                            reachedPct = ((currentPrice - entry) / tpDist) * 100.0;
                        else
                            reachedPct = ((entry - currentPrice) / tpDist) * 100.0;

                        if (reachedPct >= PartialTPPct)
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

                // --- Break-Even (NEVER past TP) ---
                if (UseBreakEven)
                {
                    if (isBuy)
                    {
                        double profitDist = currentPrice - entry;
                        if (profitDist >= beDist && sl < entry)
                        {
                            double newSL = entry + Symbol.PipSize * 5;
                            if (tp <= 0 || newSL < tp)  // Guard: never past TP
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful)
                                    Print("B.E. #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                    else // Sell
                    {
                        double profitDist = entry - currentPrice;
                        if (profitDist >= beDist && (sl == 0 || sl > entry))
                        {
                            double newSL = entry - Symbol.PipSize * 5;
                            if (tp <= 0 || newSL > tp)  // Guard: never past TP
                            {
                                var res = ModifyPosition(pos, newSL, tp);
                                if (res.IsSuccessful)
                                    Print("B.E. #{0}: SL {1:F2} -> {2:F2}", pos.Id, sl, newSL);
                            }
                        }
                    }
                }

                // --- Trailing Stop (NEVER past TP, only move up for buys / down for sells) ---
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
                    else // Sell
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
        //  Risk-Based Lot Sizing (matches MQL5 CalcRiskLot)
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

        private double CalcRiskLot(double slDistancePrice)
        {
            if (slDistancePrice <= 0)
            {
                // Fallback: risk 0.5% with estimated SL = 1 ATR
                slDistancePrice = _atrValue > 0 ? _atrValue : Symbol.Ask * 0.01;
            }

            double riskAmount = Account.Balance * (RiskPerTradePct / 100.0);
            // For standard forex: P&L = change * lot * contractSize
            // Symbol.TickValue gives value per 1.0 lot per 1 pip
            double tickValue = Symbol.TickValue;
            double tickSize = Symbol.TickSize;

            if (tickValue <= 0 || tickSize <= 0)
                return Symbol.VolumeInUnitsMin;

            // Convert price distance to pips, then use tickValue
            double slPips = slDistancePrice / tickSize;
            double lot = riskAmount / (slPips * tickValue);
            lot = Math.Max(lot, Symbol.VolumeInUnitsMin);
            double step = Symbol.VolumeInUnitsStep;
            if (step > 0) lot = Math.Floor(lot / step) * step;

            // Notional cap: ~$30k exposure per $10k balance (~7 oz at current gold).
            // Prevents risk-based sizing on a wide ATR stop from blowing margin
            // (same cap as FXYAMS_Ultimate1_cBot).
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
        //  Position Counting
        // ═══════════════════════════════════════════════════════════

        private int GetOpenPositionCount()
        {
            int count = 0;
            foreach (var pos in Positions)
                if (pos.SymbolName == Symbol.Name && pos.Label == CommentPrefix)
                    count++;
            return count;
        }

        // ═══════════════════════════════════════════════════════════
        //  Daily Safety Checks
        // ═══════════════════════════════════════════════════════════

        private int GetCurrentSession()
        {
            if (!UseSessionFilter) return 0;
            int phHour = GetPHHour();

            bool inS1 = (Session1StartHour < Session1EndHour)
                ? (phHour >= Session1StartHour && phHour < Session1EndHour)
                : (phHour >= Session1StartHour || phHour < Session1EndHour);

            bool inS2 = (Session2StartHour < Session2EndHour)
                ? (phHour >= Session2StartHour && phHour < Session2EndHour)
                : (phHour >= Session2StartHour || phHour < Session2EndHour);

            if (inS2) return 2;
            if (inS1) return 1;
            return 0;
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

            // Detect session change -> reset TP counter for new session
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
            ResetDailyStats();
            if (_dailyStats.TradingStopped) return false;
            if (_dailyStats.TradeCount >= MaxDailyTrades) return false;

            // TP pause - wait for next session
            if (_dailyStats.TPPause)
            {
                if (DebugMode && Server.Time.Second % 60 == 0)
                {
                    string sessName = (_dailyStats.CurrentSession == 1) ? "LONDON" : "NY";
                    Print("TP PAUSE [", sessName, "]: ", _dailyStats.TPHits, "/", MaxTPHits, " TPs hit.");
                }
                return false;
            }

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

        private void CloseAllPositions()
        {
            foreach (var pos in Positions)
            {
                if (pos.SymbolName == Symbol.Name && pos.Label == CommentPrefix)
                {
                    var result = ClosePosition(pos);
                    if (result.IsSuccessful)
                        Print("Closed position #{0}", pos.Id);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Session Filter (PH Time = UTC+8)
        // ═══════════════════════════════════════════════════════════

        private int GetPHHour()
        {
            var utc = Server.Time.ToUniversalTime();
            int phHour = utc.Hour + 8;
            if (phHour >= 24) phHour -= 24;
            return phHour;
        }

        private int GetPHMin()
        {
            return Server.Time.ToUniversalTime().Minute;
        }

        private int GetPHDayOfWeek()
        {
            var utc = Server.Time.ToUniversalTime();
            int phHour = utc.Hour + 8;
            int phDow = (int)utc.DayOfWeek;
            if (phHour >= 24) phDow = (phDow + 1) % 7;
            return phDow;
        }

        private bool IsInHybridWindow()
        {
            if (!UseSessionFilter) return true;
            int phHour = GetPHHour();

            // Session 1: London (15-00 PH) — wraps midnight
            bool inS1;
            if (Session1StartHour < Session1EndHour)
                inS1 = (phHour >= Session1StartHour && phHour < Session1EndHour);
            else
                inS1 = (phHour >= Session1StartHour || phHour < Session1EndHour);

            // Session 2: NY (20-05 PH) — wraps midnight
            bool inS2;
            if (Session2StartHour < Session2EndHour)
                inS2 = (phHour >= Session2StartHour && phHour < Session2EndHour);
            else
                inS2 = (phHour >= Session2StartHour || phHour < Session2EndHour);

            return inS1 || inS2;
        }

        private bool IsTradingDay()
        {
            if (!UseSessionFilter) return true;
            int phDow = GetPHDayOfWeek();
            switch (phDow)
            {
                case 1: return TradeMonday;
                case 2: return TradeTuesday;
                case 3: return TradeWednesday;
                case 4: return TradeThursday;
                case 5: return TradeFriday;
                default: return false;
            }
        }

        private bool ShouldTradeNow()
        {
            if (!UseSessionFilter) return true;
            return IsTradingDay() && IsInHybridWindow();
        }

        // ═══════════════════════════════════════════════════════════
        //  Chart Display
        // ═══════════════════════════════════════════════════════════

        private void UpdateChart()
        {
            string info = "=== FXRE Hybrid (Swing S&D) ===\n";
            info += string.Format("Balance: ${0:F2} | Equity: ${1:F2} | Spread: {2:F0}\n",
                                  Account.Balance, Account.Equity,
                                  Symbol.Spread / Symbol.PipSize);

            if (_dailyStats.StartingBalance > 0)
            {
                double dd = (_dailyStats.StartingBalance - Account.Equity)
                             / _dailyStats.StartingBalance * 100.0;
                string sessName = (_dailyStats.CurrentSession == 1) ? "LON" : (_dailyStats.CurrentSession == 2) ? "NY" : "---";
                info += string.Format("Today: {0}/{1} | TP: {2}/{3} [{4}] | DD: {5:F2}%\n",
                                      _dailyStats.TradeCount, MaxDailyTrades,
                                      _dailyStats.TPHits, MaxTPHits, sessName,
                                      dd);
            }

            info += string.Format("Open: {0}/{1} | ATR(14): {2:F0} pts (M15)\n",
                                  GetOpenPositionCount(), MaxPositions, _atrValue);
            info += string.Format("Demand Z: {0} | Supply Z: {1}\n",
                                  _demandZones.Count, _supplyZones.Count);

            if (UseSessionFilter)
            {
                info += string.Format("PH: {0:D2}:{1:D2} | {2}\n",
                                      GetPHHour(), GetPHMin(),
                                      IsTradingDay() && IsInHybridWindow() ?
                                        "SESSION" : "OUTSIDE");
            }

            if (_dailyStats.TradingStopped)
                info += "⚠ STOPPED (daily loss limit)\n";

            Chart.DrawStaticText("hybrid_status", info, VerticalAlignment.Top, HorizontalAlignment.Right, Color.Gray);
        }

        // ═══════════════════════════════════════════════════════════
        //  OnStop
        // ═══════════════════════════════════════════════════════════

        protected override void OnStop()
        {
            Print("=== FXRE Hybrid cBot (Swing S&D) Stopped ===");
            Print("Trades today: {0}", _dailyStats.TradeCount);
        }
    }
}
