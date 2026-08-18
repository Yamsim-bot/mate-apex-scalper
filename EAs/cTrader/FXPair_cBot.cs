//+------------------------------------------------------------------+
//|                                      FXPair_cBot.cs                |
//|  FXPair EA v2.0 cBot — Forex Confluence Day Trader (Multi-Symbol)  |
//|  Port of FXPair_EA.mq5 v2.0 to cTrader C#                         |
//+------------------------------------------------------------------+
//| v2.0: Relaxed confluence (min 3), RSI relaxed, Engulfing + Star   |
//|       distinct patterns, multi-symbol, ATR-based SL/TP             |
//|       Partial TP at 75%, trailing stop, break-even                 |
//| v2.1: Trend-aligned entries (EMA20/50 veto), real BB touch (1%),  |
//|       rejection candles restored, 1 pos/pair                       |
//| v2.2: TP-hit counter ignores pre-bot history (bot used to lock    |
//|       itself out until midnight); signals evaluated on the last   |
//|       CLOSED bar instead of the forming bar; cooldown tracks      |
//|       actual closes                                                |
//| v2.3: Anti-bleed: SL is clamped to the broker's minimum stop      |
//|       distance (this account rewrites EURUSD stops to ~1.2 pips   |
//|       regardless of the request) and TP is stretched so the       |
//|       reward:risk floor (Min_RR, back to 1:1 default) always      |
//|       holds — filled RR now matches the plan, and below-1:1       |
//|       entries are impossible                                      |
//+------------------------------------------------------------------+

using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo.API;
using cAlgo.API.Indicators;
using cAlgo.API.Requests;

namespace cAlgo.Robots
{
    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.FullAccess)]
    public partial class FXPair_cBot : Robot
    {
        // ═══════════════════════════════════════════════════════════
        //  Input Parameters — match FXPair_EA.mq5 defaults
        // ═══════════════════════════════════════════════════════════

        // --- Multi-symbol ---
        // EURUSD default: EURJPY stops are clamped to ~1% of price (~185 pips) on this
        // account, making tight-stop scalping impossible. EURUSD stores tight stops.
        [Parameter("Symbols (comma-sep)", DefaultValue = "EURUSD")]
        public string SymbolList { get; set; }

        // --- Timeframes ---
        [Parameter("Entry TF", DefaultValue = "M5")]
        public TimeFrame EntryTF { get; set; }

        [Parameter("Structure TF", DefaultValue = "M15")]
        public TimeFrame StructureTF { get; set; }

        // --- EMA Settings (M15) ---
        [Parameter("EMA Fast", DefaultValue = 20, MinValue = 5, MaxValue = 100)]
        public int EMA_Fast { get; set; }

        [Parameter("EMA Slow", DefaultValue = 50, MinValue = 10, MaxValue = 200)]
        public int EMA_Slow { get; set; }

        [Parameter("EMA Trend", DefaultValue = 200, MinValue = 50, MaxValue = 500)]
        public int EMA_Trend { get; set; }

        // --- Bollinger Bands (M5) ---
        [Parameter("BB Period", DefaultValue = 20, MinValue = 5, MaxValue = 50)]
        public int BB_Period { get; set; }

        [Parameter("BB StdDev", DefaultValue = 2.0, MinValue = 0.5, MaxValue = 4.0, Step = 0.1)]
        public double BB_StdDev { get; set; }

        [Parameter("BB Touch Tol %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double BB_TouchTolPct { get; set; }

        // --- RSI (M5) — V2.0 relaxed defaults ---
        [Parameter("RSI Period", DefaultValue = 14, MinValue = 2, MaxValue = 50)]
        public int RSI_Period { get; set; }

        [Parameter("RSI Buy Max", DefaultValue = 80.0, MinValue = 10.0, MaxValue = 80.0)]
        public double RSI_Buy_Max { get; set; }

        [Parameter("RSI Sell Min", DefaultValue = 20.0, MinValue = 20.0, MaxValue = 90.0)]
        public double RSI_Sell_Min { get; set; }

        // --- Confluence ---
        [Parameter("Confluence Min Score", DefaultValue = 1, MinValue = 1, MaxValue = 12)]
        public int ConfluenceMinScore { get; set; }

        [Parameter("Swing Lookback", DefaultValue = 2, MinValue = 1, MaxValue = 5)]
        public int SwingLookback { get; set; }

        [Parameter("Swing Scan Bars", DefaultValue = 50, MinValue = 10, MaxValue = 200)]
        public int SwingScanBars { get; set; }

        [Parameter("Max Swing Levels", DefaultValue = 6, MinValue = 2, MaxValue = 20)]
        public int MaxSwingLevels { get; set; }

        // --- Break & Retest ---
        [Parameter("BreakRetest ATR", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 2.0, Step = 0.05)]
        public double BreakRetest_ATR { get; set; }

        // --- Rejection Candle ---
        [Parameter("Min Reject Wick (xATR)", DefaultValue = 0.10, MinValue = 0.01, Step = 0.01)]
        public double Min_RejectWickATR { get; set; }

        [Parameter("Min Wick/Body Ratio", DefaultValue = 0.20, MinValue = 0.05, Step = 0.05)]
        public double Min_WickBodyRatio { get; set; }

        [Parameter("Min Body (xATR)", DefaultValue = 0.18, MinValue = 0.01, Step = 0.01)]
        public double Min_BodyATR { get; set; }

        [Parameter("Reject Lookback", DefaultValue = 3, MinValue = 1, MaxValue = 5)]
        public int RejectLookback { get; set; }

        [Parameter("Use Rejection Candle", DefaultValue = true)]
        public bool UseRejectionCandle { get; set; }

        // --- Engulfing ---
        [Parameter("Engulf Body Min (xATR)", DefaultValue = 0.15, MinValue = 0.01, Step = 0.01)]
        public double EngulfBodyATR_Min { get; set; }

        // --- Risk Management ---
        [Parameter("Risk %", DefaultValue = 0.5, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPerTradePct { get; set; }

        [Parameter("SL ATR Mult", DefaultValue = 0.6, MinValue = 0.1, MaxValue = 3.0, Step = 0.1)]
        public double SL_ATR_Mult { get; set; }

        [Parameter("SL Max (xATR)", DefaultValue = 2.0, MinValue = 0.5, MaxValue = 5.0, Step = 0.1)]
        public double SL_Max_ATR { get; set; }

        [Parameter("SL Min (xATR)", DefaultValue = 1.0, MinValue = 0.05, MaxValue = 2.0, Step = 0.05)]
        public double SL_Min_ATR { get; set; }

        // --- TP Strategy ---
        [Parameter("TP Mode (0=BB, 1=ATR, 2=BBMid)", DefaultValue = 1, MinValue = 0, MaxValue = 2)]
        public int TP_Mode { get; set; }

        [Parameter("TP ATR Mult", DefaultValue = 1.5, MinValue = 0.3, MaxValue = 5.0, Step = 0.1)]
        public double TP_ATR_Mult { get; set; }

        [Parameter("Min R:R", DefaultValue = 1.0, MinValue = 0.5, MaxValue = 5.0, Step = 0.1)]
        public double Min_RR { get; set; }

        // --- Partial Take-Profit ---
        [Parameter("Use Partial TP", DefaultValue = false)]
        public bool UsePartialTP { get; set; }

        [Parameter("Partial TP At %", DefaultValue = 75.0, MinValue = 20.0, MaxValue = 95.0)]
        public double PartialTP_Pct { get; set; }

        [Parameter("Partial Close %", DefaultValue = 50.0, MinValue = 10.0, MaxValue = 90.0)]
        public double PartialClosePct { get; set; }

        // --- Trailing Stop ---
        [Parameter("Use Trailing", DefaultValue = true)]
        public bool UseTrailing { get; set; }

        [Parameter("Trailing Start (xATR)", DefaultValue = 1.5, MinValue = 0.2, MaxValue = 3.0, Step = 0.1)]
        public double TrailingStart_ATR { get; set; }

        [Parameter("Trailing Step (xATR)", DefaultValue = 0.5, MinValue = 0.05, MaxValue = 1.0, Step = 0.05)]
        public double TrailingStep_ATR { get; set; }

        // --- Break-Even ---
        [Parameter("Use Break-Even", DefaultValue = true)]
        public bool UseBreakEven { get; set; }

        [Parameter("Break-Even (xATR)", DefaultValue = 1.5, MinValue = 0.3, MaxValue = 3.0, Step = 0.1)]
        public double BreakEven_ATR { get; set; }

        // --- Lot Sizing ---
        [Parameter("Fixed Lot", DefaultValue = 0.01, MinValue = 0.01, MaxValue = 10.0, Step = 0.01)]
        public double FixedLot { get; set; }

        // --- Safety ---
        [Parameter("Max Positions / Pair", DefaultValue = 1, MinValue = 1, MaxValue = 5)]
        public int MaxPositionsPerPair { get; set; }

        [Parameter("Max Global Positions", DefaultValue = 6, MinValue = 1, MaxValue = 20)]
        public int MaxGlobalPositions { get; set; }

        [Parameter("Max Daily Trades", DefaultValue = 30, MinValue = 1)]
        public int MaxDailyTrades { get; set; }

        [Parameter("Max Daily Loss %", DefaultValue = 5.0, MinValue = 1.0, MaxValue = 20.0)]
        public double MaxDailyLossPct { get; set; }

        [Parameter("Max TP Hits (per session)", DefaultValue = 5, MinValue = 1, MaxValue = 20)]
        public int MaxTPHits { get; set; }

        [Parameter("Cooldown (min)", DefaultValue = 0, MinValue = 0, MaxValue = 120)]
        public int CooldownMin { get; set; }

        // --- General ---
        [Parameter("Magic Number", DefaultValue = 20260723)]
        public int MagicNumber { get; set; }

        [Parameter("Comment Prefix", DefaultValue = "PAIR_EA")]
        public string CommentPrefix { get; set; }

        [Parameter("Max Slippage (pts)", DefaultValue = 50, MinValue = 1)]
        public int MaxSlippagePts { get; set; }

        [Parameter("Max Spread (pts)", DefaultValue = 800, MinValue = 10)]
        public int MaxSpreadPts { get; set; }

        // --- Session filter (PH Time = UTC+8) ---
        [Parameter("Use Session Filter", DefaultValue = false)]
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

        // --- Debug ---
        [Parameter("Debug Mode", DefaultValue = true)]
        public bool DebugMode { get; set; }

        // ═══════════════════════════════════════════════════════════
        //  Symbol State — per-symbol indicator handles and data
        // ═══════════════════════════════════════════════════════════

        private class SymbolState
        {
            public string Name;
            // --- Bars references
            public Bars EntryBars;           // M5 bars
            public Bars StructureBars;       // M15 bars
            // --- Indicators
            public ExponentialMovingAverage EMA_Fast;
            public ExponentialMovingAverage EMA_Slow;
            public ExponentialMovingAverage EMA_Trend;
            public BollingerBands BB;
            public RelativeStrengthIndex RSI;
            public AverageTrueRange ATR_M5;
            public AverageTrueRange ATR_M15;
            // --- Swing data
            public List<double> SwingHighs = new List<double>();
            public List<double> SwingLows = new List<double>();
            public DateTime LastSwingScan = DateTime.MinValue;
            public DateTime LastBarTime = DateTime.MinValue;
            public Symbol SymbolObj;        // cTrader Symbol for ask/bid/point
        }

        private List<SymbolState> _states = new List<SymbolState>();

        // ═══════════════════════════════════════════════════════════
        //  Global Variables
        // ═══════════════════════════════════════════════════════════

        private double _dailyStartBalance = 0;
        private DateTime _dayStart = DateTime.MinValue;
        private int _tradesToday = 0;
        private bool _tradingPaused = false;
        private DateTime _lastTradeCloseTime = DateTime.MinValue;
        private DateTime _botStartTime = DateTime.MinValue;
        // --- Per-session TP tracking ---
        private int _tpHits = 0;
        private bool _tpPause = false;
        private int _currentSession = 0;
        private DateTime _lastTPReset = DateTime.MinValue;
        private int _heartbeatCount = 0;

        // ═══════════════════════════════════════════════════════════
        //  OnStart
        // ═══════════════════════════════════════════════════════════

        protected override void OnStart()
        {
            Print("FXPair EA v2.0 cBot initializing...");

            _dailyStartBalance = Account.Balance;
            _dayStart = GetDayStart();
            _tradesToday = 0;
            _tradingPaused = false;
            _lastTradeCloseTime = DateTime.MinValue;
            _botStartTime = Server.Time;
            // Start the TP-count window here so profitable trades that closed BEFORE
            // this bot instance started are never counted as "TP hits" — otherwise a
            // fresh attach could immediately trip MaxTPHits and lock the bot out
            // until the next daily reset.
            _lastTPReset = _botStartTime;

            // --- Parse symbols
            string[] parts = SymbolList.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length == 0)
            {
                Print("ERROR: No symbols specified");
                Stop();
                return;
            }

            // --- Create state for each symbol
            foreach (string raw in parts)
            {
                string sym = raw.Trim();
                if (string.IsNullOrEmpty(sym)) continue;

                var st = new SymbolState { Name = sym };

                // Get cTrader Symbol object
                st.SymbolObj = MarketData.GetSymbol(sym);
                if (st.SymbolObj == null)
                {
                    Print("WARNING: Cannot get symbol ", sym, " — may not be available");
                    continue;
                }

                // Load bars for the symbol
                st.EntryBars = MarketData.GetBars(EntryTF, sym);
                st.StructureBars = MarketData.GetBars(StructureTF, sym);

                if (st.EntryBars == null || st.StructureBars == null)
                {
                    Print("WARNING: Cannot load bars for ", sym);
                    continue;
                }

                // Create indicators on symbol data
                st.EMA_Fast = Indicators.ExponentialMovingAverage(st.StructureBars.ClosePrices, EMA_Fast);
                st.EMA_Slow = Indicators.ExponentialMovingAverage(st.StructureBars.ClosePrices, EMA_Slow);
                st.EMA_Trend = Indicators.ExponentialMovingAverage(st.StructureBars.ClosePrices, EMA_Trend);
                st.BB = Indicators.BollingerBands(st.EntryBars.ClosePrices, BB_Period, BB_StdDev, MovingAverageType.Simple);
                st.RSI = Indicators.RelativeStrengthIndex(st.EntryBars.ClosePrices, RSI_Period);
                st.ATR_M5 = Indicators.AverageTrueRange(st.EntryBars, 14, MovingAverageType.Simple);
                st.ATR_M15 = Indicators.AverageTrueRange(st.StructureBars, 14, MovingAverageType.Simple);

                _states.Add(st);
            }

            if (_states.Count == 0)
            {
                Print("ERROR: No valid symbols initialized");
                Stop();
                return;
            }

            string tpMode = (TP_Mode == 0) ? "BB_Band" : (TP_Mode == 1) ? "ATR_x" + TP_ATR_Mult.ToString("F1") : "BB_Mid";
            Print("================================================================");
            Print("FXPair cBot v2.0 initialized (", _states.Count, " symbols)");
            Print("  Time: ", Server.Time);
            Print("  Account: #", Account.Number);
            Print("  Balance: $", Account.Balance.ToString("F2"));
            Print("  Symbols: ", SymbolList);
            Print("  TF: ", EntryTF, " entry / ", StructureTF, " structure");
            Print("  Confluence min: ", ConfluenceMinScore, " (was 5)");
            Print("  RSI: BUY<=", RSI_Buy_Max, " SELL>=", RSI_Sell_Min, " (relaxed)");
            Print("  SL: ", SL_ATR_Mult, "x ATR | TP: ", tpMode, " | RR>=", Min_RR);
            Print("  Partial TP: ", UsePartialTP ? "ON" : "OFF", " | Trailing: ", UseTrailing ? "ON" : "OFF");
            Print("  Break-Even: ", UseBreakEven ? "ON" : "OFF");
            Print("  Max positions: ", MaxGlobalPositions, " total, ", MaxPositionsPerPair, " per pair");
            Print("  Debug: ", DebugMode ? "ON" : "OFF", " | Magic: ", MagicNumber);
            Print("================================================================");
        }

        // ═══════════════════════════════════════════════════════════
        //  OnStop
        // ═══════════════════════════════════════════════════════════

        protected override void OnStop()
        {
            _states.Clear();
        }

        // ═══════════════════════════════════════════════════════════
        //  OnTick — loops through all symbols
        // ═══════════════════════════════════════════════════════════

        protected override void OnTick()
        {
            // --- Daily reset + TP detection
            CheckDailyReset();
            DetectTPHits();

            // --- Heartbeat every ~12 bars
            _heartbeatCount++;
            if (_heartbeatCount >= 12)
            {
                _heartbeatCount = 0;
                int posCount = CountAllPositions();
                Print("FXPair HEARTBEAT | Bal=", Account.Balance.ToString("F2"),
                      " Eq=", Account.Equity.ToString("F2"),
                      " Pos=", posCount,
                      " TradesToday=", _tradesToday,
                      " Symbols=", _states.Count,
                      " Time=", Server.Time);
            }

            foreach (var st in _states)
            {
                // --- Only on new bar
                DateTime curBar = GetLastBarTime(st);
                if (curBar == st.LastBarTime) continue;
                st.LastBarTime = curBar;

                // --- Manage open positions (ALWAYS — even when paused)
                ManageOpenPositions(st);

                // --- Pauses gate ONLY new entries
                if (_tradingPaused) continue;
                if (_tpPause) continue;
                if (!CheckDayOfWeek()) continue;

                // --- Cooldown
                if (_lastTradeCloseTime != DateTime.MinValue)
                {
                    double elapsedMin = (curBar - _lastTradeCloseTime).TotalMinutes;
                    if (elapsedMin < CooldownMin) continue;
                }

                // --- Position/trade limits
                if (CountPositionsForSymbol(st.Name) >= MaxPositionsPerPair) continue;
                if (CountAllPositions() >= MaxGlobalPositions) continue;
                if (_tradesToday >= MaxDailyTrades) continue;

                // --- Session & spread
                if (UseSessionFilter && !IsInSession()) continue;

                double ask = st.SymbolObj.Ask;
                double bid = st.SymbolObj.Bid;
                double point = st.SymbolObj.PipSize / 10.0; // PipSize is in pips, point is pipette
                if (point <= 0) point = st.SymbolObj.PipSize;
                double sp = (ask - bid) / point;
                if (sp > MaxSpreadPts) continue;

                // --- ATR
                double atrM5Val = GetATR(st, true);
                double atrM15Val = GetATR(st, false);
                if (atrM5Val <= 0 || atrM15Val <= 0) continue;

                // --- Update swings
                UpdateSwingLevels(st, atrM15Val);

                // --- Confluence
                int confBuy = CalcConfluenceBuy(st, atrM5Val, atrM15Val);
                int confSell = CalcConfluenceSell(st, atrM5Val, atrM15Val);

                // --- Debug
                if (DebugMode)
                {
                    double rsiVal = GetRSI(st);
                    double bbU = GetBB(st, 1);
                    double bbM = GetBB(st, 0);
                    double bbL = GetBB(st, 2);
                    double maF = GetMA(st, 0);
                    double maS = GetMA(st, 1);
                    double maT = GetMA(st, 2);
                    int digits = st.SymbolObj.Digits;

                    Print("FXPair ", st.Name,
                          " | BID=", bid.ToString(digits > 0 ? "F" + digits : "F5"),
                          " ATR5=", atrM5Val.ToString("F5"),
                          " ATR15=", atrM15Val.ToString("F5"),
                          " RSI=", rsiVal.ToString("F1"),
                          " BB=[", bbL.ToString("F" + digits), " | ", bbM.ToString("F" + digits), " | ", bbU.ToString("F" + digits), "]",
                          " | EMA=", maF.ToString("F" + digits), "/", maS.ToString("F" + digits), "/", maT.ToString("F" + digits),
                          " | SH=", st.SwingHighs.Count, " SL=", st.SwingLows.Count,
                          " | SP=", sp.ToString("F0"), "pts",
                          " | CONF_BUY=", confBuy, " CONF_SELL=", confSell);
                }

                // --- Entry decision
                if (confBuy >= ConfluenceMinScore && confBuy > confSell)
                {
                    if (DebugMode) Print("FXPair ", st.Name, " ENTRY SIGNAL: BUY conf=", confBuy);
                    if (CheckBuyEntry(st, confBuy, confSell, atrM5Val))
                    {
                        _tradesToday++;
                    }
                }
                else if (confSell >= ConfluenceMinScore && confSell > confBuy)
                {
                    if (DebugMode) Print("FXPair ", st.Name, " ENTRY SIGNAL: SELL conf=", confSell);
                    if (CheckSellEntry(st, confBuy, confSell, atrM5Val))
                    {
                        _tradesToday++;
                    }
                }
                else if (DebugMode && (confBuy >= 3 || confSell >= 3))
                {
                    Print("FXPair ", st.Name, " NEAR-MISS: confBuy=", confBuy, " confSell=", confSell,
                          " (min=", ConfluenceMinScore, ")");
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  BUY Entry
        // ═══════════════════════════════════════════════════════════

        private bool CheckBuyEntry(SymbolState st, int confBuy, int confSell, double atr)
        {
            var ohlc = GetOHLC(st, 5);
            if (ohlc == null) return false;

            // --- Trend alignment (M15): never buy against the trend
            double maF = GetMA(st, 0);   // EMA20
            double maS = GetMA(st, 1);   // EMA50
            if (maF <= 0 || maS <= 0) return false;
            if (maF < maS)
            {
                if (DebugMode) Print("FXPair BUY REJECTED ", st.Name, ": M15 trend down (EMA20<EMA50)");
                return false;
            }

            // --- BB lower touch
            double bbLower = GetBB(st, 2);
            if (bbLower <= 0) return false;
            if (ohlc.low[0] > bbLower * (1.0 + BB_TouchTolPct / 100.0))
            {
                if (DebugMode) Print("FXPair BUY REJECTED ", st.Name, ": no BB lower touch");
                return false;
            }

            // --- RSI
            double rsiVal = GetRSI(st);
            if (rsiVal <= 0 || rsiVal > RSI_Buy_Max)
            {
                if (DebugMode) Print("FXPair BUY REJECTED ", st.Name, ": RSI=", rsiVal.ToString("F1"));
                return false;
            }

            // --- Rejection candle
            if (UseRejectionCandle && !HasBullishRejection(ohlc, atr))
            {
                if (DebugMode) Print("FXPair BUY REJECTED ", st.Name, ": no bullish rejection candle");
                return false;
            }

            // --- SL
            double ask = st.SymbolObj.Ask;
            double swingLow = GetNearestSwingLow(st);
            double slRaw = (swingLow > 0) ? Math.Min(ohlc.low[0], swingLow) : ohlc.low[0];
            double slPrice = slRaw - SL_ATR_Mult * atr;
            if (ask - slPrice > atr * SL_Max_ATR) slPrice = ask - atr * SL_Max_ATR;
            if (ask - slPrice < atr * SL_Min_ATR) slPrice = ask - atr * SL_Min_ATR;
            // Respect the broker/account minimum stop distance so the filled SL
            // matches the one we size the risk against.
            double minStop = GetMinStopDistance(st);
            if (minStop > 0 && ask - slPrice < minStop) slPrice = ask - minStop;
            if (slPrice >= ask) return false;

            // --- TP
            double tpPrice = CalcBuyTP(st, ask, atr);
            double slDist = ask - slPrice;
            if (tpPrice <= ask) return false;

            // --- RR: if the preferred TP doesn't reach Min_RR, stretch it so the
            //    reward:risk floor always holds. This kills the "RR=0.75 rejected
            //    for hours" deadlock WITHOUT weakening Min_RR below 1:1.
            double rr = (tpPrice - ask) / slDist;
            if (rr < Min_RR)
            {
                if (DebugMode)
                    Print("FXPair BUY ", st.Name, ": RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                tpPrice = ask + slDist * Min_RR;
                rr = Min_RR;
            }

            // --- Lot
            double lot = CalcLotSize(st, ask - slPrice);
            if (lot <= 0) return false;

            // --- Send order
            int digits = st.SymbolObj.Digits;
            var result = ExecuteMarketOrder(TradeType.Buy, st.Name, lot, CommentPrefix + "_BUY",
                                             Math.Round(slPrice, digits), Math.Round(tpPrice, digits));

            if (result.IsSuccessful)
            {
                Print("FXPair BUY ", st.Name, ": price=", ask.ToString("F" + digits),
                      " SL=", slPrice.ToString("F" + digits),
                      " TP=", tpPrice.ToString("F" + digits),
                      " lot=", lot.ToString("F2"), " RR=", rr.ToString("F2"),
                      " conf=", confBuy, "/", confSell);
                if (result.Position != null)
                    Print("FXPair BUY CONFIRMED ", result.Position.Id,
                          " entry=", result.Position.EntryPrice.ToString("F" + digits),
                          " SL=", (result.Position.StopLoss.HasValue ? result.Position.StopLoss.Value.ToString("F" + digits) : "null"),
                          " TP=", (result.Position.TakeProfit.HasValue ? result.Position.TakeProfit.Value.ToString("F" + digits) : "null"));
            }
            else
            {
                Print("FXPair BUY FAILED ", st.Name, ": ", result.Error);
            }
            return result.IsSuccessful;
        }

        // ═══════════════════════════════════════════════════════════
        //  SELL Entry
        // ═══════════════════════════════════════════════════════════

        private bool CheckSellEntry(SymbolState st, int confBuy, int confSell, double atr)
        {
            var ohlc = GetOHLC(st, 5);
            if (ohlc == null) return false;

            // --- Trend alignment (M15): never sell against the trend
            double maF = GetMA(st, 0);   // EMA20
            double maS = GetMA(st, 1);   // EMA50
            if (maF <= 0 || maS <= 0) return false;
            if (maF > maS)
            {
                if (DebugMode) Print("FXPair SELL REJECTED ", st.Name, ": M15 trend up (EMA20>EMA50)");
                return false;
            }

            // --- BB upper touch
            double bbUpper = GetBB(st, 1);
            if (bbUpper <= 0) return false;
            if (ohlc.high[0] < bbUpper * (1.0 - BB_TouchTolPct / 100.0))
            {
                if (DebugMode) Print("FXPair SELL REJECTED ", st.Name, ": no BB upper touch");
                return false;
            }

            // --- RSI
            double rsiVal = GetRSI(st);
            if (rsiVal <= 0 || rsiVal < RSI_Sell_Min)
            {
                if (DebugMode) Print("FXPair SELL REJECTED ", st.Name, ": RSI=", rsiVal.ToString("F1"));
                return false;
            }

            // --- Rejection candle
            if (UseRejectionCandle && !HasBearishRejection(ohlc, atr))
            {
                if (DebugMode) Print("FXPair SELL REJECTED ", st.Name, ": no bearish rejection candle");
                return false;
            }

            // --- SL
            double bid = st.SymbolObj.Bid;
            double swingHigh = GetNearestSwingHigh(st);
            double slRaw = (swingHigh > 0) ? Math.Max(ohlc.high[0], swingHigh) : ohlc.high[0];
            double slPrice = slRaw + SL_ATR_Mult * atr;
            if (slPrice - bid > atr * SL_Max_ATR) slPrice = bid + atr * SL_Max_ATR;
            if (slPrice - bid < atr * SL_Min_ATR) slPrice = bid + atr * SL_Min_ATR;
            // Respect the broker/account minimum stop distance so the filled SL
            // matches the one we size the risk against.
            double minStop = GetMinStopDistance(st);
            if (minStop > 0 && slPrice - bid < minStop) slPrice = bid + minStop;
            if (slPrice <= bid) return false;

            // --- TP
            double tpPrice = CalcSellTP(st, bid, atr);
            double slDist = slPrice - bid;
            if (tpPrice >= bid) return false;

            // --- RR: stretch TP to the actual SL distance so the reward:risk
            //    floor always holds (see BUY entry).
            double rr = (bid - tpPrice) / slDist;
            if (rr < Min_RR)
            {
                if (DebugMode)
                    Print("FXPair SELL ", st.Name, ": RR ", rr.ToString("F2"), " < Min_RR ", Min_RR.ToString("F1"), " — stretching TP");
                tpPrice = bid - slDist * Min_RR;
                rr = Min_RR;
            }

            // --- Lot
            double lot = CalcLotSize(st, slPrice - bid);
            if (lot <= 0) return false;

            // --- Send order
            int digits = st.SymbolObj.Digits;
            var result = ExecuteMarketOrder(TradeType.Sell, st.Name, lot, CommentPrefix + "_SELL",
                                             Math.Round(slPrice, digits), Math.Round(tpPrice, digits));

            if (result.IsSuccessful)
            {
                Print("FXPair SELL ", st.Name, ": price=", bid.ToString("F" + digits),
                      " SL=", slPrice.ToString("F" + digits),
                      " TP=", tpPrice.ToString("F" + digits),
                      " lot=", lot.ToString("F2"), " RR=", rr.ToString("F2"),
                      " conf=", confBuy, "/", confSell);
                if (result.Position != null)
                    Print("FXPair SELL CONFIRMED ", result.Position.Id,
                          " entry=", result.Position.EntryPrice.ToString("F" + digits),
                          " SL=", (result.Position.StopLoss.HasValue ? result.Position.StopLoss.Value.ToString("F" + digits) : "null"),
                          " TP=", (result.Position.TakeProfit.HasValue ? result.Position.TakeProfit.Value.ToString("F" + digits) : "null"));
            }
            else
            {
                Print("FXPair SELL FAILED ", st.Name, ": ", result.Error);
            }
            return result.IsSuccessful;
        }

        // ═══════════════════════════════════════════════════════════
        //  INDICATOR HELPERS (per-symbol)
        // ═══════════════════════════════════════════════════════════

        private double GetATR(SymbolState st, bool isEntry)
        {
            try
            {
                var indicator = isEntry ? st.ATR_M5 : st.ATR_M15;
                if (indicator == null) return 0;
                return indicator.Result.LastValue;
            }
            catch { return 0; }
        }

        private double GetBB(SymbolState st, int mode)
        {
            // mode: 0 = middle, 1 = upper, 2 = lower
            try
            {
                if (st.BB == null) return 0;
                if (mode == 0) return st.BB.Main.LastValue;
                if (mode == 1) return st.BB.Top.LastValue;
                return st.BB.Bottom.LastValue;
            }
            catch { return 0; }
        }

        private double GetRSI(SymbolState st)
        {
            try
            {
                if (st.RSI == null) return 0;
                var r = st.RSI.Result;
                // Signal RSI should match the last CLOSED bar used everywhere else;
                // the forming bar's RSI is live/noisy. Fall back to LastValue when
                // there is not enough history yet.
                if (r.Count <= 1) return r.LastValue;
                return r.Last(1);
            }
            catch { return 0; }
        }

        private double GetMA(SymbolState st, int idx)
        {
            // idx: 0 = fast, 1 = slow, 2 = trend
            try
            {
                if (idx == 0) return st.EMA_Fast.Result.LastValue;
                if (idx == 1) return st.EMA_Slow.Result.LastValue;
                return st.EMA_Trend.Result.LastValue;
            }
            catch { return 0; }
        }

        /// <summary>
        /// Broker/account minimum stop-loss distance in PRICE units (0 = no restriction).
        /// This demo account rewrites EURUSD stops to ~1.2 pips no matter what is
        /// requested — if the bot ignores that, the filled SL/TP (and real RR) never
        /// match the plan, positions get stopped by noise, and lot sizing is wrong.
        /// </summary>
        private double GetMinStopDistance(SymbolState st)
        {
            try
            {
                var sym = st.SymbolObj;
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

        // ═══════════════════════════════════════════════════════════
        //  OHLC DATA HELPER
        // ═══════════════════════════════════════════════════════════

        private class OHLCData
        {
            public double[] open;
            public double[] high;
            public double[] low;
            public double[] close;
        }

        /// <summary>
        /// Get last N bars OHLC from EntryBars (M5).
        /// Index [0] = most recent bar, [1] = previous, etc.
        /// </summary>
        private OHLCData GetOHLC(SymbolState st, int count)
        {
            try
            {
                var bars = st.EntryBars;
                // Need count CLOSED bars plus the still-forming bar we skip
                if (bars == null || bars.Count < count + 1) return null;

                var data = new OHLCData
                {
                    open = new double[count],
                    high = new double[count],
                    low = new double[count],
                    close = new double[count]
                };

                for (int i = 0; i < count; i++)
                {
                    // Index 0 = the LAST CLOSED bar (skip the forming bar, which has
                    // almost no data and would make signals flicker / read an empty
                    // candle at the moment a new bar opens). Matches MQL5 rates[1] style.
                    int idx = bars.Count - 2 - i;
                    data.open[i] = bars.OpenPrices[idx];
                    data.high[i] = bars.HighPrices[idx];
                    data.low[i] = bars.LowPrices[idx];
                    data.close[i] = bars.ClosePrices[idx];
                }

                return data;
            }
            catch { return null; }
        }

        /// <summary>
        /// Get the open/high/low/close of the structure (M15) bars
        /// </summary>
        private OHLCData GetStructureOHLC(SymbolState st, int count)
        {
            try
            {
                var bars = st.StructureBars;
                if (bars == null || bars.Count < count + 1) return null;

                var data = new OHLCData
                {
                    open = new double[count],
                    high = new double[count],
                    low = new double[count],
                    close = new double[count]
                };

                for (int i = 0; i < count; i++)
                {
                    // Index 0 = last CLOSED structure bar (skip the forming bar)
                    int idx = bars.Count - 2 - i;
                    data.open[i] = bars.OpenPrices[idx];
                    data.high[i] = bars.HighPrices[idx];
                    data.low[i] = bars.LowPrices[idx];
                    data.close[i] = bars.ClosePrices[idx];
                }

                return data;
            }
            catch { return null; }
        }

        /// <summary>
        /// Get last bar open time for entry TF (for new-bar detection)
        /// </summary>
        private DateTime GetLastBarTime(SymbolState st)
        {
            try
            {
                var bars = st.EntryBars;
                if (bars == null || bars.Count == 0) return DateTime.MinValue;
                return bars.OpenTimes[bars.Count - 1];
            }
            catch { return DateTime.MinValue; }
        }

        // ═══════════════════════════════════════════════════════════
        //  CONFLUENCE SCORING (0-12, V2.0 relaxed)
        // ═══════════════════════════════════════════════════════════

        private int CalcConfluenceBuy(SymbolState st, double atrM5, double atrM15)
        {
            int score = 0;
            string dbg = "";

            // 1. M15 EMA20 > EMA50 = +2
            double maF = GetMA(st, 0);
            double maS = GetMA(st, 1);
            if (maF > 0 && maS > 0)
            {
                if (maF > maS) { score += 2; dbg += "EMA20>50(+2) "; }
                else dbg += "EMA20<50(0) ";
            }

            // 2. M15 EMA50 > EMA200 = +1
            double maT = GetMA(st, 2);
            if (maS > 0 && maT > 0)
            {
                if (maS > maT) { score += 1; dbg += "EMA50>200(+1) "; }
                else dbg += "EMA50<200(0) ";
            }

            // 3. Market structure bullish (HH/HL) = +2
            if (IsBullMarketStructure(st)) { score += 2; dbg += "BullStruct(+2) "; }

            // 4. Break & retest bullish = +2
            if (CheckBullBreakRetest(st, atrM15)) { score += 2; dbg += "BullRetest(+2) "; }

            // 5. At S&R support level = +1
            if (AtSupportLevel(st, atrM15)) { score += 1; dbg += "Support(+1) "; }

            // 6. Bullish engulfing = +2
            if (DetectBullishEngulfing(st, atrM5)) { score += 2; dbg += "Engulf(+2) "; }

            // 7. Morning star reversal (3-bar) = +2
            if (DetectMorningStar(st, atrM5)) { score += 2; dbg += "MStar(+2) "; }

            if (DebugMode) Print("FXPair CONF_BUY ", st.Name, "=", score, " | ", dbg);
            return score;
        }

        private int CalcConfluenceSell(SymbolState st, double atrM5, double atrM15)
        {
            int score = 0;
            string dbg = "";

            // 1. M15 EMA20 < EMA50 = +2
            double maF = GetMA(st, 0);
            double maS = GetMA(st, 1);
            if (maF > 0 && maS > 0)
            {
                if (maF < maS) { score += 2; dbg += "EMA20<50(+2) "; }
                else dbg += "EMA20>50(0) ";
            }

            // 2. M15 EMA50 < EMA200 = +1
            double maT = GetMA(st, 2);
            if (maS > 0 && maT > 0)
            {
                if (maS < maT) { score += 1; dbg += "EMA50<200(+1) "; }
                else dbg += "EMA50>200(0) ";
            }

            // 3. Market structure bearish (LH/LL) = +2
            if (IsBearMarketStructure(st)) { score += 2; dbg += "BearStruct(+2) "; }

            // 4. Break & retest bearish = +2
            if (CheckBearBreakRetest(st, atrM15)) { score += 2; dbg += "BearRetest(+2) "; }

            // 5. At S&R resistance level = +1
            if (AtResistanceLevel(st, atrM15)) { score += 1; dbg += "Resist(+1) "; }

            // 6. Bearish engulfing = +2
            if (DetectBearishEngulfing(st, atrM5)) { score += 2; dbg += "Engulf(+2) "; }

            // 7. Evening star reversal (3-bar) = +2
            if (DetectEveningStar(st, atrM5)) { score += 2; dbg += "EStar(+2) "; }

            if (DebugMode) Print("FXPair CONF_SELL ", st.Name, "=", score, " | ", dbg);
            return score;
        }

        // ═══════════════════════════════════════════════════════════
        //  CANDLE PATTERN DETECTION
        // ═══════════════════════════════════════════════════════════

        /// <summary>
        /// Morning Star (bullish reversal): bearish bar -> small-body bar -> large bullish bar
        /// [2]=oldest, [1]=middle, [0]=newest
        /// </summary>
        private bool DetectMorningStar(SymbolState st, double atr)
        {
            var ohlc = GetOHLC(st, 3);
            if (ohlc == null) return false;

            // [2]=oldest, [1]=middle, [0]=newest
            double body2 = ohlc.open[2] - ohlc.close[2]; // First bar body (bearish if > 0)
            double body1 = Math.Abs(ohlc.close[1] - ohlc.open[1]); // Middle bar body (small)
            double body0 = ohlc.close[0] - ohlc.open[0]; // Last bar body (bullish if > 0)

            if (body2 < atr * Min_BodyATR) return false;        // First bar too small
            if (body1 > body2 * 0.5) return false;               // Middle body not small enough
            if (body0 < atr * Min_BodyATR) return false;         // Last bar too small
            if (ohlc.close[2] > ohlc.open[2]) return false;     // First not bearish
            if (ohlc.close[0] <= ohlc.open[0]) return false;     // Last not bullish
            if (ohlc.close[0] < (ohlc.open[2] + ohlc.close[2]) / 2.0) return false; // Last doesn't close above mid of first
            return true;
        }

        /// <summary>
        /// Evening Star (bearish reversal): bullish bar -> small-body bar -> large bearish bar
        /// </summary>
        private bool DetectEveningStar(SymbolState st, double atr)
        {
            var ohlc = GetOHLC(st, 3);
            if (ohlc == null) return false;

            double body2 = ohlc.close[2] - ohlc.open[2]; // First bar body (bullish if > 0)
            double body1 = Math.Abs(ohlc.close[1] - ohlc.open[1]); // Middle bar body (small)
            double body0 = ohlc.open[0] - ohlc.close[0]; // Last bar body (bearish if > 0)

            if (body2 < atr * Min_BodyATR) return false;
            if (body1 > body2 * 0.5) return false;
            if (body0 < atr * Min_BodyATR) return false;
            if (ohlc.close[2] < ohlc.open[2]) return false;     // First not bullish
            if (ohlc.close[0] >= ohlc.open[0]) return false;     // Last not bearish
            if (ohlc.close[0] > (ohlc.open[2] + ohlc.close[2]) / 2.0) return false;
            return true;
        }

        // ═══════════════════════════════════════════════════════════
        //  ENGULFING DETECTION
        // ═══════════════════════════════════════════════════════════

        private bool DetectBullishEngulfing(SymbolState st, double atr)
        {
            var ohlc = GetOHLC(st, 3);
            if (ohlc == null) return false;

            if (ohlc.open[1] <= ohlc.close[1]) return false; // prev not bearish
            if (ohlc.close[0] <= ohlc.open[0]) return false; // current not bullish
            double prevBody = ohlc.open[1] - ohlc.close[1];
            double currBody = ohlc.close[0] - ohlc.open[0];
            if (currBody <= prevBody) return false;
            if (currBody < atr * EngulfBodyATR_Min) return false;
            if (ohlc.open[0] >= ohlc.close[1]) return false;
            if (ohlc.close[0] <= ohlc.open[1]) return false;
            return true;
        }

        private bool DetectBearishEngulfing(SymbolState st, double atr)
        {
            var ohlc = GetOHLC(st, 3);
            if (ohlc == null) return false;

            if (ohlc.open[1] >= ohlc.close[1]) return false; // prev not bullish
            if (ohlc.close[0] >= ohlc.open[0]) return false; // current not bearish
            double prevBody = ohlc.close[1] - ohlc.open[1];
            double currBody = ohlc.open[0] - ohlc.close[0];
            if (currBody <= prevBody) return false;
            if (currBody < atr * EngulfBodyATR_Min) return false;
            if (ohlc.open[0] <= ohlc.close[1]) return false;
            if (ohlc.close[0] >= ohlc.open[1]) return false;
            return true;
        }

        // ═══════════════════════════════════════════════════════════
        //  MARKET STRUCTURE
        // ═══════════════════════════════════════════════════════════

        private void DetectSwingPoints(SymbolState st)
        {
            var ohlc = GetStructureOHLC(st, SwingScanBars);
            if (ohlc == null) return;

            st.SwingHighs.Clear();
            st.SwingLows.Clear();

            for (int i = SwingLookback; i < SwingScanBars - SwingLookback; i++)
            {
                bool isSwingHigh = true;
                for (int j = 1; j <= SwingLookback; j++)
                {
                    if (ohlc.high[i] <= ohlc.high[i - j] || ohlc.high[i] <= ohlc.high[i + j])
                    { isSwingHigh = false; break; }
                }
                if (isSwingHigh)
                    st.SwingHighs.Add(ohlc.high[i]);

                bool isSwingLow = true;
                for (int j = 1; j <= SwingLookback; j++)
                {
                    if (ohlc.low[i] >= ohlc.low[i - j] || ohlc.low[i] >= ohlc.low[i + j])
                    { isSwingLow = false; break; }
                }
                if (isSwingLow)
                    st.SwingLows.Add(ohlc.low[i]);
            }

            // Keep most recent
            if (st.SwingHighs.Count > MaxSwingLevels)
                st.SwingHighs.RemoveRange(0, st.SwingHighs.Count - MaxSwingLevels);
            if (st.SwingLows.Count > MaxSwingLevels)
                st.SwingLows.RemoveRange(0, st.SwingLows.Count - MaxSwingLevels);
        }

        private bool IsBullMarketStructure(SymbolState st)
        {
            if (st.SwingHighs.Count < 2 || st.SwingLows.Count < 2) return false;
            int last = st.SwingHighs.Count - 1;
            bool hh = st.SwingHighs[last] > st.SwingHighs[last - 1];
            last = st.SwingLows.Count - 1;
            bool hl = st.SwingLows[last] > st.SwingLows[last - 1];
            return hh && hl;
        }

        private bool IsBearMarketStructure(SymbolState st)
        {
            if (st.SwingHighs.Count < 2 || st.SwingLows.Count < 2) return false;
            int last = st.SwingHighs.Count - 1;
            bool lh = st.SwingHighs[last] < st.SwingHighs[last - 1];
            last = st.SwingLows.Count - 1;
            bool ll = st.SwingLows[last] < st.SwingLows[last - 1];
            return lh && ll;
        }

        private double GetNearestSwingLow(SymbolState st)
        {
            double bid = st.SymbolObj.Bid;
            double nearest = 0;
            double minDist = double.MaxValue;
            foreach (double level in st.SwingLows)
            {
                if (level < bid && (bid - level) < minDist)
                { minDist = bid - level; nearest = level; }
            }
            return nearest;
        }

        private double GetNearestSwingHigh(SymbolState st)
        {
            double ask = st.SymbolObj.Ask;
            double nearest = 0;
            double minDist = double.MaxValue;
            foreach (double level in st.SwingHighs)
            {
                if (level > ask && (level - ask) < minDist)
                { minDist = level - ask; nearest = level; }
            }
            return nearest;
        }

        // ═══════════════════════════════════════════════════════════
        //  BREAK & RETEST
        // ═══════════════════════════════════════════════════════════

        private bool CheckBullBreakRetest(SymbolState st, double atrM15)
        {
            if (st.SwingHighs.Count < 1) return false;
            double ask = st.SymbolObj.Ask;
            double bid = st.SymbolObj.Bid;
            foreach (double level in st.SwingHighs)
            {
                double retestZone = level + BreakRetest_ATR * atrM15;
                double breakZone = level + 0.1 * atrM15;
                if (bid > breakZone && ask <= retestZone) return true;
            }
            return false;
        }

        private bool CheckBearBreakRetest(SymbolState st, double atrM15)
        {
            if (st.SwingLows.Count < 1) return false;
            double ask = st.SymbolObj.Ask;
            double bid = st.SymbolObj.Bid;
            foreach (double level in st.SwingLows)
            {
                double retestZone = level - BreakRetest_ATR * atrM15;
                double breakZone = level - 0.1 * atrM15;
                if (ask < breakZone && bid >= retestZone) return true;
            }
            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  S&R LEVELS
        // ═══════════════════════════════════════════════════════════

        private bool AtSupportLevel(SymbolState st, double atrM15)
        {
            double bid = st.SymbolObj.Bid;
            double proximity = atrM15 * 0.3;
            foreach (double level in st.SwingLows)
            {
                if (Math.Abs(bid - level) <= proximity) return true;
            }
            return false;
        }

        private bool AtResistanceLevel(SymbolState st, double atrM15)
        {
            double ask = st.SymbolObj.Ask;
            double proximity = atrM15 * 0.3;
            foreach (double level in st.SwingHighs)
            {
                if (Math.Abs(ask - level) <= proximity) return true;
            }
            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  REJECTION CANDLES
        // ═══════════════════════════════════════════════════════════

        private bool HasBullishRejection(OHLCData ohlc, double atr)
        {
            int limit = Math.Min(RejectLookback, ohlc.close.Length);
            for (int i = 0; i < limit; i++)
            {
                if (ohlc.close[i] <= ohlc.open[i]) continue;
                double body = ohlc.close[i] - ohlc.open[i];
                double lowerWick = ohlc.open[i] - ohlc.low[i];
                if (lowerWick < atr * Min_RejectWickATR) continue;
                if (body > 0 && lowerWick / body < Min_WickBodyRatio) continue;
                if (body < atr * Min_BodyATR) continue;
                return true;
            }
            return false;
        }

        private bool HasBearishRejection(OHLCData ohlc, double atr)
        {
            int limit = Math.Min(RejectLookback, ohlc.close.Length);
            for (int i = 0; i < limit; i++)
            {
                if (ohlc.close[i] >= ohlc.open[i]) continue;
                double body = ohlc.open[i] - ohlc.close[i];
                double upperWick = ohlc.high[i] - ohlc.open[i];
                if (upperWick < atr * Min_RejectWickATR) continue;
                if (body > 0 && upperWick / body < Min_WickBodyRatio) continue;
                if (body < atr * Min_BodyATR) continue;
                return true;
            }
            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  TP / SL CALCULATIONS
        // ═══════════════════════════════════════════════════════════

        private double CalcBuyTP(SymbolState st, double ask, double atr)
        {
            if (TP_Mode == 0)
            {
                double bbUpper = GetBB(st, 1);
                if (bbUpper > 0) return bbUpper;
            }
            else if (TP_Mode == 2)
            {
                double bbMid = GetBB(st, 0);
                if (bbMid > ask) return bbMid;
            }
            return ask + atr * TP_ATR_Mult;
        }

        private double CalcSellTP(SymbolState st, double bid, double atr)
        {
            if (TP_Mode == 0)
            {
                double bbLower = GetBB(st, 2);
                if (bbLower > 0) return bbLower;
            }
            else if (TP_Mode == 2)
            {
                double bbMid = GetBB(st, 0);
                if (bbMid < bid) return bbMid;
            }
            return bid - atr * TP_ATR_Mult;
        }

        // ═══════════════════════════════════════════════════════════
        //  POSITION SIZING
        // ═══════════════════════════════════════════════════════════

        private double CalcLotSize(SymbolState st, double slDistPrice)
        {
            double balance = Account.Balance;
            double riskMoney = balance * RiskPerTradePct / 100.0;
            var sym = st.SymbolObj;

            double tickValue = sym.TickValue;
            double tickSize = sym.TickSize;

            if (tickValue <= 0 || tickSize <= 0 || slDistPrice <= 0)
                return FixedLot;

            double slInTicks = slDistPrice / tickSize;
            double lotByRisk = riskMoney / (slInTicks * tickValue);

            double lotStep = sym.VolumeInUnitsStep;
            double minLot = sym.VolumeInUnitsMin > 0 ? sym.VolumeInUnitsMin : sym.VolumeInUnitsStep;
            double maxLot = sym.VolumeInUnitsMax > 0 ? sym.VolumeInUnitsMax : 100;

            // Margin-protection cap: risk-based sizing on a tiny SL (small M5
            // ATR) produced 2+ lot positions that tripped backtest margin
            // stop-out (and would be dangerous live). Cap ~25k units (0.25
            // lots) per $10k of balance — scales with the account.
            // BUGFIX 8/6: notionalCap is DOLLARS but was assigned to maxLot as
            // if it were lots — a $25k cap looked like a 25k-lot cap, so it never
            // clamped. Convert dollars -> lots (notional / price / contract size)
            // before clamping, matching FXPair_EA.mq5. cTrader's Symbol has no
            // ContractSize property, so derive it from tickValue/tickSize
            // (contractSize = value of a 1-tick move for 1.0 volume / tickSize).
            double notionalCap = (balance / 10000.0) * 25000.0;
            double capPrice = sym.Ask > 0 ? sym.Ask : sym.Bid;
            double capContract = (tickValue / tickSize) > 0 ? (tickValue / tickSize) : 1;
            if (capPrice > 0 && capContract > 0) notionalCap = notionalCap / capPrice / capContract;
            if (notionalCap < minLot) notionalCap = minLot;
            if (maxLot <= 0 || notionalCap < maxLot) maxLot = notionalCap;
            if (lotStep > 0) maxLot = Math.Floor(maxLot / lotStep) * lotStep;

            lotByRisk = Math.Floor(lotByRisk / lotStep) * lotStep;
            lotByRisk = Math.Max(minLot, Math.Min(lotByRisk, maxLot));

            return lotByRisk;
        }

        private double NormalizeLot(SymbolState st, double lot)
        {
            var sym = st.SymbolObj;
            double lotStep = sym.VolumeInUnitsStep;
            double minLot = sym.VolumeInUnitsMin > 0 ? sym.VolumeInUnitsMin : sym.VolumeInUnitsStep;
            double maxLot = sym.VolumeInUnitsMax > 0 ? sym.VolumeInUnitsMax : 100;

            lot = Math.Floor(lot / lotStep) * lotStep;
            lot = Math.Max(minLot, Math.Min(lot, maxLot));
            return lot;
        }

        // ═══════════════════════════════════════════════════════════
        //  POSITION COUNTING & MANAGEMENT
        // ═══════════════════════════════════════════════════════════

        private int CountPositionsForSymbol(string symbol)
        {
            return Positions.Count(p => p.SymbolName == symbol && p.Label != null && p.Label.StartsWith(CommentPrefix));
        }

        private int CountAllPositions()
        {
            return Positions.Count(p => p.Label != null && p.Label.StartsWith(CommentPrefix));
        }

        private void ManageOpenPositions(SymbolState st)
        {
            if (!UsePartialTP && !UseTrailing && !UseBreakEven) return;

            double atr = GetATR(st, true);
            if (atr <= 0) return;

            foreach (var pos in Positions.Where(p => p.SymbolName == st.Name && p.Label != null && p.Label.StartsWith(CommentPrefix)))
            {
                double entry = pos.EntryPrice;
                double sl = pos.StopLoss.GetValueOrDefault();
                double tp = pos.TakeProfit.GetValueOrDefault();
                double volume = pos.VolumeInUnits;
                bool isBuy = pos.TradeType == TradeType.Buy;
                double currentPrice = isBuy ? st.SymbolObj.Bid : st.SymbolObj.Ask;
                int digits = st.SymbolObj.Digits;

                // --- Break-Even
                if (UseBreakEven)
                {
                    double beDist = BreakEven_ATR * atr;
                    if (isBuy)
                    {
                        double newSL = entry + st.SymbolObj.PipSize * 5;
                        if (currentPrice >= entry + beDist && sl < entry)
                        {
                            ModifyPosition(pos, Math.Round(newSL, digits), tp > 0 ? tp : (double?)null);
                        }
                    }
                    else
                    {
                        double newSL = entry - st.SymbolObj.PipSize * 5;
                        if (currentPrice <= entry - beDist && (sl > entry || sl == 0))
                        {
                            ModifyPosition(pos, Math.Round(newSL, digits), tp > 0 ? tp : (double?)null);
                        }
                    }
                }

                // --- Partial TP
                if (UsePartialTP && volume > st.SymbolObj.VolumeInUnitsMin)
                {
                    double tpDist = (tp > 0) ? Math.Abs(tp - entry) : atr * TP_ATR_Mult;
                    double partialPrice;

                    if (isBuy)
                    {
                        partialPrice = entry + tpDist * PartialTP_Pct / 100.0;
                        if (currentPrice >= partialPrice)
                        {
                            double closeLot = NormalizeLot(st, volume * PartialClosePct / 100.0);
                            if (closeLot >= st.SymbolObj.VolumeInUnitsMin)
                            {
                                ClosePosition(pos, (long)closeLot);
                            }
                        }
                    }
                    else
                    {
                        partialPrice = entry - tpDist * PartialTP_Pct / 100.0;
                        if (currentPrice <= partialPrice)
                        {
                            double closeLot = NormalizeLot(st, volume * PartialClosePct / 100.0);
                            if (closeLot >= st.SymbolObj.VolumeInUnitsMin)
                            {
                                ClosePosition(pos, (long)closeLot);
                            }
                        }
                    }
                }

                // --- Trailing Stop
                if (UseTrailing)
                {
                    double trailStart = TrailingStart_ATR * atr;
                    double trailStep = TrailingStep_ATR * atr;

                    if (isBuy)
                    {
                        double profitDist = currentPrice - entry;
                        if (profitDist >= trailStart)
                        {
                            double newSL = currentPrice - trailStep;
                            if (newSL > sl)
                            {
                                ModifyPosition(pos, Math.Round(newSL, digits), tp > 0 ? tp : (double?)null);
                            }
                        }
                    }
                    else
                    {
                        double profitDist = entry - currentPrice;
                        if (profitDist >= trailStart)
                        {
                            double newSL = currentPrice + trailStep;
                            if (newSL < sl || sl == 0)
                            {
                                ModifyPosition(pos, Math.Round(newSL, digits), tp > 0 ? tp : (double?)null);
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  SWING CACHE UPDATE
        // ═══════════════════════════════════════════════════════════

        private void UpdateSwingLevels(SymbolState st, double atrM15)
        {
            DateTime m15Time = DateTime.MinValue;
            try
            {
                var bars = st.StructureBars;
                if (bars != null && bars.Count > 0)
                    m15Time = bars.OpenTimes[bars.Count - 1];
            }
            catch { return; }

            if (m15Time == st.LastSwingScan) return;
            st.LastSwingScan = m15Time;
            DetectSwingPoints(st);
        }

        // ═══════════════════════════════════════════════════════════
        //  DAILY / SAFETY CHECKS
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

        private int GetPHHour()
        {
            var utc = Server.Time.ToUniversalTime();
            int phHour = utc.Hour + 8;
            if (phHour >= 24) phHour -= 24;
            return phHour;
        }

        private void CheckDailyReset()
        {
            DateTime dayStart = GetDayStart();
            if (dayStart != _dayStart)
            {
                _dayStart = dayStart;
                _tradesToday = 0;
                _dailyStartBalance = Account.Balance;
                _tradingPaused = false;
                _lastTradeCloseTime = DateTime.MinValue;
                _tpHits = 0;
                _tpPause = false;
                _currentSession = 0;
                _lastTPReset = dayStart;
            }

            // Detect session change -> reset TP counter for new session
            int newSession = GetCurrentSession();
            if (newSession != _currentSession)
            {
                _currentSession = newSession;
                _tpHits = 0;
                _tpPause = false;
                _lastTPReset = Server.Time;
                if (newSession > 0)
                    Print("SESSION CHANGE -> ", (newSession == 1 ? "LONDON" : "NY"),
                          " | TP counter reset. Fresh ", MaxTPHits, " TPs available.");
            }

            double currBalance = Account.Balance;
            if (_dailyStartBalance > 0)
            {
                double lossPct = (_dailyStartBalance - currBalance) / _dailyStartBalance * 100.0;
                if (lossPct >= MaxDailyLossPct)
                {
                    _tradingPaused = true;
                    Print("Max daily loss (", lossPct.ToString("F1"), "%) reached. Paused.");
                }
            }
        }

        private DateTime GetDayStart()
        {
            DateTime now = Server.Time;
            return new DateTime(now.Year, now.Month, now.Day, 0, 0, 0, DateTimeKind.Utc);
        }

        // ═══════════════════════════════════════════════════════════
        //  Detect TPs hit in current session
        // ═══════════════════════════════════════════════════════════

        private void DetectTPHits()
        {
            CheckDailyReset();

            // cTrader: History holds closed Trades (each = one closed position)
            var trades = History.Where(t => t.Label != null && t.Label.StartsWith(CommentPrefix));

            foreach (var trade in trades)
            {
                if (trade.ClosingTime <= _lastTPReset) continue;
                if (trade.ClosingTime < _botStartTime) continue;

                // Track the most recent close (win OR loss) so the Cooldown filter
                // measures from when a position actually closed, not when it opened.
                _lastTradeCloseTime = trade.ClosingTime;

                if (trade.NetProfit > 0)  // positive close ~ TP hit (or trailing win)
                {
                    _tpHits++;
                    string sessName = (_currentSession == 1) ? "LONDON" : "NY";
                    Print("TP HIT #", _tpHits, "/", MaxTPHits,
                          " (", sessName, " session) on ", trade.SymbolName,
                          " | Profit: $", trade.NetProfit.ToString("F2"));

                    if (_tpHits >= MaxTPHits)
                    {
                        _tpPause = true;
                        Print("TP PAUSE [", sessName, "]: ", _tpHits,
                              " TPs hit. No new entries.");
                    }
                }
            }

            // Advance cursor so each close is counted exactly once (was: re-counted every tick
            // -> counter exploded to thousands -> _tpPause locked the bot out of new entries
            // AND blocked ManageOpenPositions via the early return).
            _lastTPReset = Server.Time;
        }

        private bool CheckDayOfWeek()
        {
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

        private bool IsInSession()
        {
            // MQL5 version: always true (hour 0-23)
            // Full day session in UTC+8 (Manila) timezone
            return true;
        }
    }
}
