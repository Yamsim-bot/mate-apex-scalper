//+------------------------------------------------------------------+
//|                                        ScalpXAU_cBot.cs           |
//|  ScalpXAU — XAUUSD Session Scalper                               |
//|  Asian: Range | London: Breakout | NY: Sweep                     |
//|  Port of ScalpXAU.mq5 to cTrader C#                              |
//+------------------------------------------------------------------+
//| NOTE: cTrader Server.Time (TimeZone=UTC) is already GMT, so the  |
//|       MQL5's broker-GMT-offset auto-detect is not needed. Keep   |
//|       "Broker GMT Offset" at 0 (only set if server is non-UTC).  |
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
    // NOTE: .NET 6+ cTrader grants HTTP access to all cBots by default; the
    //       legacy AccessRights.Internet flag is obsolete (compile error) there.
    public partial class ScalpXAU_cBot : Robot
    {
        // ═══════════════════════════════════════════════════════════
        //  Input Parameters — match ScalpXAU.mq5 defaults
        // ═══════════════════════════════════════════════════════════

        // --- General ---
        [Parameter("Risk %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double RiskPerTradePct { get; set; }

        [Parameter("Max Daily Risk %", DefaultValue = 5.0, MinValue = 0.5, MaxValue = 20.0, Step = 0.1)]
        public double MaxDailyRiskPct { get; set; }

        [Parameter("Max Session DD %", DefaultValue = 5.0, MinValue = 1.0, MaxValue = 30.0, Step = 0.1)]
        public double MaxSessDDPct { get; set; }

        [Parameter("Max Trades / Session", DefaultValue = 40, MinValue = 1)]
        public int MaxTradesPerSess { get; set; }

        [Parameter("Max Positions", DefaultValue = 3, MinValue = 1, MaxValue = 10)]
        public int MaxPositions { get; set; }

        [Parameter("Broker GMT Offset (0=UTC)", DefaultValue = 0, MinValue = -14, MaxValue = 14)]
        public int BrokerGMTOffset { get; set; }

        [Parameter("Debug Mode", DefaultValue = false)]
        public bool DebugMode { get; set; }

        // --- Timeframes ---
        [Parameter("Entry Timeframe", DefaultValue = "M15")]
        public TimeFrame EntryTF { get; set; }

        [Parameter("Swing Lookback Bars", DefaultValue = 100, MinValue = 50)]
        public int SwingLookback { get; set; }

        // --- Asian Session (Range Scalp) ---
        [Parameter("Enable Asian", DefaultValue = true)]
        public bool EnableAsian { get; set; }

        [Parameter("Asian TP (pips)", DefaultValue = 10, MinValue = 5)]
        public int Asian_TP_Pips { get; set; }

        [Parameter("Asian SL Buffer (xATR)", DefaultValue = 0.4, MinValue = 0.1, Step = 0.1)]
        public double Asian_SL_BufferATR { get; set; }

        [Parameter("Min SL (xATR)", DefaultValue = 1.0, MinValue = 0.2, MaxValue = 3.0, Step = 0.1)]
        public double Min_SL_ATR { get; set; }

        [Parameter("RSI Period", DefaultValue = 14, MinValue = 2)]
        public int RSI_Period { get; set; }

        [Parameter("RSI Overbought", DefaultValue = 72.0, MinValue = 50.0, MaxValue = 90.0)]
        public double RSI_OB { get; set; }

        [Parameter("RSI Oversold", DefaultValue = 28.0, MinValue = 10.0, MaxValue = 50.0)]
        public double RSI_OS { get; set; }

        // --- London Session (Breakout + Retest) ---
        [Parameter("Enable London", DefaultValue = true)]
        public bool EnableLondon { get; set; }

        [Parameter("London R:R", DefaultValue = 1.7, MinValue = 1.0, MaxValue = 5.0, Step = 0.1)]
        public double London_RR { get; set; }

        [Parameter("London Risk %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double London_RiskPct { get; set; }

        // --- NY Session (Liquidity Sweep) ---
        [Parameter("Enable NY", DefaultValue = true)]
        public bool EnableNY { get; set; }

        [Parameter("NY R:R", DefaultValue = 1.7, MinValue = 1.0, MaxValue = 5.0, Step = 0.1)]
        public double NY_RR { get; set; }

        [Parameter("NY Risk %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double NY_RiskPct { get; set; }

        [Parameter("Sweep Lookback", DefaultValue = 50, MinValue = 20)]
        public int SweepLookback { get; set; }

        // --- Risk Management ---
        [Parameter("Use Break-Even", DefaultValue = true)]
        public bool UseBreakEven { get; set; }

        [Parameter("Break-Even (xATR)", DefaultValue = 0.8, MinValue = 0.1, MaxValue = 3.0, Step = 0.1)]
        public double BE_ATR_Mult { get; set; }

        [Parameter("Use Trailing", DefaultValue = true)]
        public bool UseTrailing { get; set; }

        [Parameter("Trailing Start (xATR)", DefaultValue = 1.0, MinValue = 0.2, MaxValue = 3.0, Step = 0.1)]
        public double TrailStart_ATR { get; set; }

        [Parameter("Trailing Step (xATR)", DefaultValue = 0.25, MinValue = 0.1, MaxValue = 1.0, Step = 0.05)]
        public double TrailStep_ATR { get; set; }

        [Parameter("Max Slippage (pts)", DefaultValue = 30, MinValue = 1)]
        public int MaxSlippagePts { get; set; }

        [Parameter("Magic Number", DefaultValue = 241107)]
        public int MagicNumber { get; set; }

        [Parameter("Comment Prefix", DefaultValue = "SCALPX_EA")]
        public string CommentPrefix { get; set; }

        // --- Session Times (GMT = UTC) ---
        [Parameter("Asian Start Hour", DefaultValue = 0, MinValue = 0, MaxValue = 23)]
        public int Asian_StartH { get; set; }

        [Parameter("Asian Start Min", DefaultValue = 30, MinValue = 0, MaxValue = 59)]
        public int Asian_StartM { get; set; }

        [Parameter("Asian End Hour", DefaultValue = 3, MinValue = 0, MaxValue = 23)]
        public int Asian_EndH { get; set; }

        [Parameter("Asian End Min", DefaultValue = 30, MinValue = 0, MaxValue = 59)]
        public int Asian_EndM { get; set; }

        [Parameter("London Start Hour", DefaultValue = 7, MinValue = 0, MaxValue = 23)]
        public int London_StartH { get; set; }

        [Parameter("London Start Min", DefaultValue = 0, MinValue = 0, MaxValue = 59)]
        public int London_StartM { get; set; }

        [Parameter("London End Hour", DefaultValue = 10, MinValue = 0, MaxValue = 23)]
        public int London_EndH { get; set; }

        [Parameter("London End Min", DefaultValue = 0, MinValue = 0, MaxValue = 59)]
        public int London_EndM { get; set; }

        [Parameter("NY Start Hour", DefaultValue = 13, MinValue = 0, MaxValue = 23)]
        public int NY_StartH { get; set; }

        [Parameter("NY Start Min", DefaultValue = 30, MinValue = 0, MaxValue = 59)]
        public int NY_StartM { get; set; }

        [Parameter("NY End Hour", DefaultValue = 16, MinValue = 0, MaxValue = 23)]
        public int NY_EndH { get; set; }

        [Parameter("NY End Min", DefaultValue = 30, MinValue = 0, MaxValue = 59)]
        public int NY_EndM { get; set; }

        // --- Trend Following Leg (MA50/200 regime, pullback + breakout) ---
        [Parameter("Enable Trend", DefaultValue = true)]
        public bool EnableTrend { get; set; }

        [Parameter("Trend Fast MA Period", DefaultValue = 50, MinValue = 10)]
        public int Trend_MA_Fast { get; set; }

        [Parameter("Trend Slow MA Period", DefaultValue = 200, MinValue = 50)]
        public int Trend_MA_Slow { get; set; }

        [Parameter("Trend Min Sep (xATR)", DefaultValue = 0.50, MinValue = 0.0, Step = 0.05)]
        public double Trend_MinSep_ATR { get; set; }

        [Parameter("Trend Slope Filter", DefaultValue = true)]
        public bool Trend_SlopeFilter { get; set; }

        [Parameter("Trend Pullback (xATR)", DefaultValue = 0.50, MinValue = 0.1, Step = 0.1)]
        public double Trend_Pullback_ATR { get; set; }

        [Parameter("Trend Breakout (xATR)", DefaultValue = 0.60, MinValue = 0.1, Step = 0.1)]
        public double Trend_Breakout_ATR { get; set; }

        [Parameter("Trend SL Buffer (xATR)", DefaultValue = 0.30, MinValue = 0.1, Step = 0.1)]
        public double Trend_SL_Buffer_ATR { get; set; }

        [Parameter("Trend Trail Start (xATR)", DefaultValue = 1.00, MinValue = 0.2, Step = 0.1)]
        public double Trend_TrailStart_ATR { get; set; }

        [Parameter("Trend Trail Step (xATR)", DefaultValue = 0.50, MinValue = 0.1, Step = 0.1)]
        public double Trend_TrailStep_ATR { get; set; }

        [Parameter("Trend Risk %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double Trend_RiskPct { get; set; }

        // --- Gainz-Swing Mode (port of the Gainz Algo V2 EA profile) ---
        //  Swing profile validated by backtest on XAUUSD H1 2020-10 -> 2023-10
        //  (gainz_backtest.py): TP +159p / SL -322p, session-gated breakout of
        //  the previous day's range with EMA trend bias, max 11h hold, hard SL,
        //  no overnight. 65-72% win rate, PF > 1 ONLY with these guards on.
        [Parameter("Enable Gainz-Swing", DefaultValue = false)]
        public bool EnableGainzSwing { get; set; }

        [Parameter("Gainz TP (pips)", DefaultValue = 159, MinValue = 50)]
        public int Gainz_TP_Pips { get; set; }

        [Parameter("Gainz SL (pips)", DefaultValue = 322, MinValue = 50)]
        public int Gainz_SL_Pips { get; set; }

        [Parameter("Gainz Max Hold (hours)", DefaultValue = 11, MinValue = 1)]
        public int Gainz_MaxHoldHours { get; set; }

        [Parameter("Gainz No Overnight", DefaultValue = true)]
        public bool Gainz_NoOvernight { get; set; }

        [Parameter("Gainz Cutoff Hour (GMT)", DefaultValue = 22, MinValue = 0, MaxValue = 23)]
        public int Gainz_CutoffHour { get; set; }

        [Parameter("Gainz Session Start (GMT)", DefaultValue = 7, MinValue = 0, MaxValue = 23)]
        public int Gainz_StartH { get; set; }

        [Parameter("Gainz Session End (GMT)", DefaultValue = 21, MinValue = 0, MaxValue = 23)]
        public int Gainz_EndH { get; set; }

        [Parameter("Gainz Risk %", DefaultValue = 1.0, MinValue = 0.1, MaxValue = 5.0, Step = 0.1)]
        public double Gainz_RiskPct { get; set; }

        [Parameter("Gainz EMA Period", DefaultValue = 200, MinValue = 50)]
        public int Gainz_EMA_Period { get; set; }

        [Parameter("Gainz Cooldown (hours)", DefaultValue = 3, MinValue = 0)]
        public int Gainz_CooldownHours { get; set; }

        // --- Telegram Alerts (trade notifications) ---
        [Parameter("Telegram Alerts", DefaultValue = true)]
        public bool EnableTelegramAlerts { get; set; }

        [Parameter("Telegram Bot Token", DefaultValue = "")]
        public string TelegramToken { get; set; }

        [Parameter("Telegram Chat ID", DefaultValue = "")]
        public string TelegramChatId { get; set; }

        // ═══════════════════════════════════════════════════════════
        //  Data Structures
        // ═══════════════════════════════════════════════════════════

        private enum SessionType { None = -1, Asian = 0, London = 1, NY = 2 }

        private struct FVG
        {
            public double Upper;
            public double Lower;
            public DateTime Time;
            public bool Bullish;   // true = bullish FVG (gap up)
        }

        private struct LiqLevel
        {
            public double Price;
            public DateTime Time;
            public bool IsHigh;    // true = high, false = low
            public bool Swept;
        }

        private class DailyStats
        {
            public DateTime LastResetTime = DateTime.MinValue;
            public double StartingBalance;
            public int TradeCount;
            public int SessionTradeCount;
            public SessionType LastSession = SessionType.None;
            public bool TradingStopped;
            public bool SessTradingStopped;
            public double SessionStartEquity;
        }

        // ═══════════════════════════════════════════════════════════
        //  State
        // ═══════════════════════════════════════════════════════════

        private Bars _entryBars;
        private RelativeStrengthIndex _rsi;
        private MovingAverage _maFast;
        private MovingAverage _maSlow;

        private SessionType _currentSession = SessionType.None;
        private double _asianHigh = 0;
        private double _asianLow = 0;
        private DateTime _asianSessionStart = DateTime.MinValue;
        private bool _asianRangeReady = false;

        // --- Gainz-Swing state ---
        private Bars _gainzBars;                       // H1 series
        private double _gainzEMA = 0;                  // EMA of H1 closes
        private int _gainzLastEmaIndex = -1;           // last H1 close folded in
        private bool _gainzEMASeeded = false;
        private double _gainzPrevDayHigh = 0;
        private double _gainzPrevDayLow = double.MaxValue;
        private DateTime _lastGainzEntryBarTime = DateTime.MinValue;
        private DateTime _gainzNextEntryAllowed = DateTime.MinValue;   // cooldown
        private readonly Dictionary<long, DateTime> _gainzOpenSince = new Dictionary<long, DateTime>();

        private readonly List<double> _swingHighVal = new List<double>();
        private readonly List<double> _swingLowVal = new List<double>();
        private bool _swingReady = false;

        private readonly List<FVG> _fvgList = new List<FVG>();
        private readonly List<LiqLevel> _liqLevels = new List<LiqLevel>();

        private readonly DailyStats _stats = new DailyStats();
        private double _atrValue = 0;
        private DateTime _lastBarTime = DateTime.MinValue;
        private DateTime _lastEntryBarTime = DateTime.MinValue;
        private DateTime _lastTrendEntryBarTime = DateTime.MinValue;
        private int _tickCount = 0;

        // ═══════════════════════════════════════════════════════════
        //  OnStart
        // ═══════════════════════════════════════════════════════════

        protected override void OnStart()
        {
            if (!Symbol.Name.Contains("XAU") && !Symbol.Name.ToUpper().Contains("GOLD"))
                Print("WARNING: ScalpXAU is designed for XAUUSD. Current symbol: ", Symbol.Name);

            _entryBars = MarketData.GetBars(EntryTF, Symbol.Name);
            if (_entryBars == null) { Print("ERROR: Cannot load bars"); Stop(); return; }

            _rsi = Indicators.RelativeStrengthIndex(_entryBars.ClosePrices, RSI_Period);

            _maFast = Indicators.MovingAverage(_entryBars.ClosePrices, Trend_MA_Fast, MovingAverageType.Simple);
            _maSlow = Indicators.MovingAverage(_entryBars.ClosePrices, Trend_MA_Slow, MovingAverageType.Simple);

            _stats.StartingBalance = Account.Balance;
            _stats.SessionStartEquity = Account.Equity;

            UpdateSwingPoints();
            Print("ScalpXAU cBot initialized on ", Symbol.Name, " ", EntryTF);
            Print("Magic: ", MagicNumber, " | Risk: ", RiskPerTradePct, "% per trade, max ", MaxDailyRiskPct, "% daily");
            Print("Trend leg: ", EnableTrend ? "ON" : "OFF",
                  " MA", Trend_MA_Fast, "/", Trend_MA_Slow,
                  " sep>=", Trend_MinSep_ATR, "xATR", Trend_SlopeFilter ? " +slope" : "",
                  " pull<=", Trend_Pullback_ATR,
                  " brk>", Trend_Breakout_ATR, "xATR");

            // --- Gainz-Swing mode init (H1 series + EMA seed)
            if (EnableGainzSwing)
            {
                _gainzBars = MarketData.GetBars(TimeFrame.Hour, Symbol.Name);
                if (_gainzBars == null)
                {
                    Print("ERROR: Cannot load H1 bars for Gainz-Swing mode");
                }
                else
                {
                    int n = Math.Min(Gainz_EMA_Period, _gainzBars.ClosePrices.Count);
                    if (n > 0)
                    {
                        double sum = 0;
                        for (int i = 0; i < n; i++) sum += _gainzBars.ClosePrices[i];
                        _gainzEMA = sum / n;
                        _gainzLastEmaIndex = n - 1;
                        _gainzEMASeeded = true;
                    }
                    Print("Gainz-Swing: ON | TP=", Gainz_TP_Pips, "p SL=", Gainz_SL_Pips,
                          "p | hold<=", Gainz_MaxHoldHours, "h | no-overnight=",
                          Gainz_NoOvernight ? "ON" : "OFF",
                          " (cutoff ", Gainz_CutoffHour, ":00 GMT)",
                          " | window ", Gainz_StartH, "-", Gainz_EndH, " GMT",
                          " | risk ", Gainz_RiskPct, "% | EMA", Gainz_EMA_Period);
                }
            }

            // --- Telegram trade alerts (only if configured)
            if (EnableTelegramAlerts
                && !string.IsNullOrWhiteSpace(TelegramToken)
                && !string.IsNullOrWhiteSpace(TelegramChatId))
            {
                Positions.Opened += Positions_Opened;
                Positions.Closed += Positions_Closed;
                SendTelegram("ScalpXAU cBot started | " + Symbol.Name + " " + EntryTF
                    + " | Gainz-Swing " + (EnableGainzSwing ? "ON" : "OFF")
                    + " | Bal $" + Account.Balance.ToString("F2"));
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  OnTick
        // ═══════════════════════════════════════════════════════════

        protected override void OnTick()
        {
            ResetDaily();

            if (_stats.TradingStopped)
            {
                CloseAllPositions("DD_LIMIT");
                UpdateComment();
                return;
            }

            _atrValue = CalcATR(14);
            _tickCount++;

            // --- New-bar work (swing update + session levels)
            if (IsNewBar())
            {
                UpdateSwingPoints();
                DetectSessionLevels();
                if (EnableGainzSwing) UpdateGainzLevels();
                Print("NEWBAR | Sess=", GetSessionName(GetCurrentSession()),
                      " GMT=", GetGMTHour(), ":", GetGMTMin().ToString("D2"),
                      " ATR=", _atrValue.ToString("F1"),
                      " Range=", (_asianRangeReady ? "Y" : "N"),
                      " FVG=", _fvgList.Count,
                      " Liq=", _liqLevels.Count,
                      " Swings=", _swingHighVal.Count, "H ", _swingLowVal.Count, "L");
            }

            // --- Heartbeat every 100 ticks
            if (_tickCount >= 100)
            {
                _tickCount = 0;
                Print("HB | Bal=$", Account.Balance.ToString("F2"),
                      " Eq=$", Account.Equity.ToString("F2"),
                      " Pos=", CountOpenPositions(),
                      " Trades=", _stats.TradeCount,
                      " Sess=", GetSessionName(_currentSession),
                      " ATR=", _atrValue.ToString("F1"));
            }

            ManagePositions();
            if (EnableGainzSwing) ManageGainzPositions();

            if (CountOpenPositions() >= MaxPositions)
            {
                UpdateComment();
                return;
            }

            CheckEntry();

            // --- Trend leg: evaluated EVERY tick (not bar-gated like the session
            //     strategies) so a mid-bar breakout is caught; dedups to one fill
            //     per M15 bar via _lastTrendEntryBarTime (set AFTER open).
            if (EnableTrend) CheckTrendEntry();

            // --- Gainz-Swing leg: one attempt per closed H1 bar.
            if (EnableGainzSwing) CheckGainzEntry();

            UpdateComment();
        }

        // ═══════════════════════════════════════════════════════════
        //  Check entry signals per session
        // ═══════════════════════════════════════════════════════════

        private void CheckEntry()
        {
            // One entry attempt per bar. Without this, a signal that stays true for
            // several ticks re-fires every tick: the NY-open flip-flop loop and the
            // 100+/hr market-close retry storm seen live on 8/6. (mirrors ScalpXAU.mq5)
            DateTime entryBar = _entryBars.OpenTimes.Last(0);
            if (entryBar == _lastEntryBarTime) return;
            _lastEntryBarTime = entryBar;

            _currentSession = GetCurrentSession();
            if (_currentSession == SessionType.None) return;

            // --- Reset session trade counter on session change
            if (_stats.LastSession != _currentSession)
            {
                _stats.SessionTradeCount = 0;
                _stats.SessionStartEquity = Account.Equity;
                _stats.SessTradingStopped = false;
                _stats.LastSession = _currentSession;
                Print("SESS START | ", GetSessionName(_currentSession),
                      " Eq=$", _stats.SessionStartEquity.ToString("F2"));
            }

            // --- Session drawdown limit
            if (!_stats.SessTradingStopped && _stats.SessionStartEquity > 0 && _currentSession != SessionType.None)
            {
                double ddPct = (_stats.SessionStartEquity - Account.Equity) / _stats.SessionStartEquity * 100.0;
                if (ddPct >= MaxSessDDPct)
                {
                    _stats.SessTradingStopped = true;
                    Print("*** SESSION DD LIMIT REACHED: ", ddPct.ToString("F2"),
                          "% at ", GetSessionName(_currentSession), " ***");
                }
            }
            if (_stats.SessTradingStopped) return;
            if (_stats.SessionTradeCount >= MaxTradesPerSess) return;

            switch (_currentSession)
            {
                case SessionType.Asian:
                    if (EnableAsian) AsianRangeScalp();
                    break;
                case SessionType.London:
                    if (EnableLondon) LondonBreakoutRetest();
                    break;
                case SessionType.NY:
                    if (EnableNY) NYLiquiditySweep();
                    break;
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  TREND LEG: MA50/200 regime + pullback/breakout continuation
        //  Evaluated every tick (not bar-gated like the session strategies)
        //  so a mid-bar breakout is caught; dedups to one fill per M15 bar
        //  via _lastTrendEntryBarTime (set AFTER a successful fill). Shares
        //  session guards & lot sizing. Mirrors FXYAMS TrendMode.
        // ═══════════════════════════════════════════════════════════

        private bool CheckTrendEntry()
        {
            if (!EnableTrend) return false;
            if (_maFast == null || _maSlow == null) return false;
            if (_entryBars.Count < Trend_MA_Slow + 2) return false;

            // --- Session + guard gates (shared with session strategies)
            SessionType sess = GetCurrentSession();
            if (sess == SessionType.None) return false;
            if (_stats.SessTradingStopped) return false;
            if (_stats.SessionTradeCount >= MaxTradesPerSess) return false;
            if (CountOpenPositions() >= MaxPositions) return false;

            // --- One fill per M15 bar (set AFTER open, so the forming bar is
            //     evaluated every tick)
            DateTime barTime = _entryBars.OpenTimes.Last(0);
            if (barTime == _lastTrendEntryBarTime) return false;

            // --- Trend regime (M15 MAs). .Last(i) = as-series: 0 = forming bar.
            double maFast0 = _maFast.Result.Last(0);
            double maSlow0 = _maSlow.Result.Last(0);
            double maFast1 = _maFast.Result.Last(1);
            double maFast2 = _maFast.Result.Last(2);
            double maSlow1 = _maSlow.Result.Last(1);
            double maSlow2 = _maSlow.Result.Last(2);

            double atr = _atrValue;
            if (atr <= 0) return false;

            // --- Trend-quality gate: BOTH MAs must slope with the trend (kills chop whipsaws)
            bool fastRising  = (maFast1 > maFast2);
            bool fastFalling = (maFast1 < maFast2);
            bool slowRising  = (maSlow1 > maSlow2);
            bool slowFalling = (maSlow1 < maSlow2);
            double sepATR = (maFast0 - maSlow0) / atr;
            bool trendUp   = (Oclose(0) > maFast0 && maFast0 > maSlow0 && sepATR >=  Trend_MinSep_ATR
                              && (!Trend_SlopeFilter || (fastRising && slowRising)));
            bool trendDown = (Oclose(0) < maFast0 && maFast0 < maSlow0 && sepATR <= -Trend_MinSep_ATR
                              && (!Trend_SlopeFilter || (fastFalling && slowFalling)));

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            double maxTrendSL = 2.5 * atr;

            // --- PULLBACK: prior M15 bar dipped to the fast-MA zone, current bar turns back
            bool pullbackUp = trendUp
                && Oclose(1) < Oopen(1)
                && Olow(1)  <= maFast1 + Trend_Pullback_ATR * atr
                && Oclose(0) > Oopen(0)
                && Ohigh(0)  > Ohigh(1);

            bool pullbackDown = trendDown
                && Oclose(1) > Oopen(1)
                && Ohigh(1)  >= maFast1 - Trend_Pullback_ATR * atr
                && Oclose(0) < Oopen(0)
                && Olow(0)   < Olow(1);

            // --- BREAKOUT: current bar extends beyond prior bar in the trend direction
            bool breakoutUp = trendUp
                && Oclose(0) > Oopen(0)
                && Ohigh(0)  > Ohigh(1) + Trend_Breakout_ATR * atr;

            bool breakoutDown = trendDown
                && Oclose(0) < Oopen(0)
                && Olow(0)   < Olow(1) - Trend_Breakout_ATR * atr;

            // --- Trend BUY (pullback preferred when both qualify on the same bar)
            if (pullbackUp || breakoutUp)
            {
                double sl = (pullbackUp
                    ? Math.Min(Olow(1), Olow(0))
                    : Olow(0)) - Trend_SL_Buffer_ATR * atr;
                double slDist = ask - sl;
                if (slDist >= Min_SL_ATR * atr && slDist <= maxTrendSL)
                {
                    double lot = CalcLotSizeRisk(slDist, Trend_RiskPct);
                    if (lot > 0 && VerifyTrade(TradeType.Buy, ask, sl, 0.0, lot))
                    {
                        if (OpenOrder(TradeType.Buy, lot, ask, sl, 0.0, CommentPrefix + "_T_BUY"))
                        {
                            _stats.TradeCount++;
                            _stats.SessionTradeCount++;
                            _lastTrendEntryBarTime = barTime;
                            Print("TREND BUY (", pullbackUp ? "PULLBACK" : "BREAKOUT",
                                  "): close=", Oclose(0).ToString("F2"),
                                  " SL=", (slDist / atr).ToString("F2"), "xATR");
                            return true;
                        }
                    }
                }
            }

            // --- Trend SELL
            if (pullbackDown || breakoutDown)
            {
                double sl = (pullbackDown
                    ? Math.Max(Ohigh(1), Ohigh(0))
                    : Ohigh(0)) + Trend_SL_Buffer_ATR * atr;
                double slDist = sl - bid;
                if (slDist >= Min_SL_ATR * atr && slDist <= maxTrendSL)
                {
                    double lot = CalcLotSizeRisk(slDist, Trend_RiskPct);
                    if (lot > 0 && VerifyTrade(TradeType.Sell, bid, sl, 0.0, lot))
                    {
                        if (OpenOrder(TradeType.Sell, lot, bid, sl, 0.0, CommentPrefix + "_T_SELL"))
                        {
                            _stats.TradeCount++;
                            _stats.SessionTradeCount++;
                            _lastTrendEntryBarTime = barTime;
                            Print("TREND SELL (", pullbackDown ? "PULLBACK" : "BREAKOUT",
                                  "): close=", Oclose(0).ToString("F2"),
                                  " SL=", (slDist / atr).ToString("F2"), "xATR");
                            return true;
                        }
                    }
                }
            }

            return false;
        }

        // ═══════════════════════════════════════════════════════════
        //  Bar helpers — i follows MQL5 as-series indexing
        //  (i=0 current forming bar, i=1 last closed, i=2 ...)
        // ═══════════════════════════════════════════════════════════

        private double Ohigh(int i) { return _entryBars.HighPrices[_entryBars.Count - 1 - i]; }
        private double Olow(int i) { return _entryBars.LowPrices[_entryBars.Count - 1 - i]; }
        private double Oopen(int i) { return _entryBars.OpenPrices[_entryBars.Count - 1 - i]; }
        private double Oclose(int i) { return _entryBars.ClosePrices[_entryBars.Count - 1 - i]; }
        private DateTime Otime(int i) { return _entryBars.OpenTimes[_entryBars.Count - 1 - i]; }

        // ═══════════════════════════════════════════════════════════
        //  ASIAN SESSION: Range-bound scalping
        //  S/R zones on M15, RSI OB/OS, pin bar/engulfing entry.
        //  TP at least 1:1 with SL.
        // ═══════════════════════════════════════════════════════════

        private void AsianRangeScalp()
        {
            if (!_swingReady) return;
            if (_entryBars.Count < 6) return;

            int bar = 1; // last closed bar
            double open = Oopen(bar);
            double high = Ohigh(bar);
            double low = Olow(bar);
            double close = Oclose(bar);
            double body = Math.Abs(close - open);
            double lowerWick = Math.Min(close, open) - low;
            double upperWick = high - Math.Max(close, open);
            bool isBull = close > open;
            bool isBear = close < open;

            // --- Pin bar detection
            bool isPinBar = false;
            double wickThreshold = body * 0.5;
            if (isBull && lowerWick >= wickThreshold && upperWick <= body * 0.3)
                isPinBar = true;
            if (isBear && upperWick >= wickThreshold && lowerWick <= body * 0.3)
                isPinBar = true;

            // --- Engulfing detection
            bool isEngulfBull = false;
            bool isEngulfBear = false;
            if (bar + 1 <= _entryBars.Count - 1)
            {
                double prevBody = Math.Abs(Oclose(bar + 1) - Oopen(bar + 1));
                bool prevBear = Oclose(bar + 1) < Oopen(bar + 1);
                bool prevBull = Oclose(bar + 1) > Oopen(bar + 1);
                if (isBull && prevBear && body > prevBody * 1.1 && close > Oopen(bar + 1) && open < Oclose(bar + 1))
                    isEngulfBull = true;
                if (isBear && prevBull && body > prevBody * 1.1 && close < Oopen(bar + 1) && open > Oclose(bar + 1))
                    isEngulfBear = true;
            }

            bool rejectionCandle = isPinBar || isEngulfBull || isEngulfBear;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            double atr = _atrValue;
            if (atr <= 0) return;

            double rsi1 = GetRSI(1);
            if (double.IsNaN(rsi1)) return;

            // --- Resistance zones (swing highs)
            int nHigh = Math.Min(_swingHighVal.Count, 10);
            for (int i = 0; i < nHigh; i++)
            {
                double zoneLevel = _swingHighVal[i];
                double zoneRange = atr * 0.6;

                if (Math.Abs(high - zoneLevel) <= zoneRange && isBear && rejectionCandle)
                {
                    if (rsi1 >= RSI_OB)
                    {
                        double sl = zoneLevel + Asian_SL_BufferATR * atr;
                        double slDist = Math.Abs(sl - close);
                        if (slDist <= 0) continue;
                        // SL floor: never let a stop sit inside normal noise (mirrors ScalpXAU.mq5)
                        if (slDist < Min_SL_ATR * atr) { slDist = Min_SL_ATR * atr; sl = close + slDist; }
                        double tp = close - Math.Max(Asian_TP_Pips * Symbol.PipSize, slDist * 1.5);

                        double lot = CalcLotSizeRisk(slDist, RiskPerTradePct);
                        if (lot >= Symbol.VolumeInUnitsMin && VerifyTrade(TradeType.Sell, bid, sl, tp, lot))
                        {
                            if (OpenOrder(TradeType.Sell, lot, bid, sl, tp, CommentPrefix + "_ASIAN_SELL"))
                            {
                                _stats.TradeCount++;
                                _stats.SessionTradeCount++;
                                if (DebugMode) Print("ASIAN SELL: zone=", zoneLevel, " RSI=", rsi1);
                            }
                        }
                    }
                }
            }

            // --- Support zones (swing lows)
            int nLow = Math.Min(_swingLowVal.Count, 10);
            for (int i = 0; i < nLow; i++)
            {
                double zoneLevel = _swingLowVal[i];
                double zoneRange = atr * 0.6;

                if (Math.Abs(low - zoneLevel) <= zoneRange && isBull && rejectionCandle)
                {
                    if (rsi1 <= RSI_OS)
                    {
                        double sl = zoneLevel - Asian_SL_BufferATR * atr;
                        double slDist = Math.Abs(close - sl);
                        if (slDist <= 0) continue;
                        // SL floor: never let a stop sit inside normal noise (mirrors ScalpXAU.mq5)
                        if (slDist < Min_SL_ATR * atr) { slDist = Min_SL_ATR * atr; sl = close - slDist; }
                        double tp = close + Math.Max(Asian_TP_Pips * Symbol.PipSize, slDist * 1.5);

                        double lot = CalcLotSizeRisk(slDist, RiskPerTradePct);
                        if (lot >= Symbol.VolumeInUnitsMin && VerifyTrade(TradeType.Buy, ask, sl, tp, lot))
                        {
                            if (OpenOrder(TradeType.Buy, lot, ask, sl, tp, CommentPrefix + "_ASIAN_BUY"))
                            {
                                _stats.TradeCount++;
                                _stats.SessionTradeCount++;
                                if (DebugMode) Print("ASIAN BUY: zone=", zoneLevel, " RSI=", rsi1);
                            }
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  LONDON SESSION: Breakout + Retest
        //  Mark Asian range, breakout close, retest entry, FVG confluence.
        //  TP 2x SL, London_RiskPct risk.
        // ═══════════════════════════════════════════════════════════

        private void LondonBreakoutRetest()
        {
            if (!_asianRangeReady || _asianHigh <= 0 || _asianLow <= 0) return;
            if (_entryBars.Count < 11) return;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            double atr = _atrValue;
            if (atr <= 0) return;

            // --- Check for breakouts
            int breakDir = 0;   // 1 = bull breakout, -1 = bear breakout
            int breakBar = -1;

            for (int c = 1; c <= 8; c++)
            {
                if (c > _entryBars.Count - 1) break;
                if (Oclose(c) > _asianHigh && Oclose(c) > Oopen(c)) { breakDir = 1; breakBar = c; }
                else if (Oclose(c) < _asianLow && Oclose(c) < Oopen(c)) { breakDir = -1; breakBar = c; }
                if (breakDir != 0) break;
            }

            if (breakDir == 0) return;

            // --- Look for retest after breakout
            bool retestHit = false;
            int retestBar = -1;
            double entryPrice = 0;
            double retestSL = 0;
            double retestTP = 0;
            bool fvgFound = false;
            DetectFVG();

            for (int c = breakBar - 1; c >= 1 && c > breakBar - 5; c--)
            {
                if (c <= 0 || c > _entryBars.Count - 1) continue;

                if (breakDir == 1) // Bull breakout: retest of Asian high as support
                {
                    if (Olow(c) <= _asianHigh * 1.002 && Olow(c) >= _asianHigh * 0.995)
                    {
                        if (Oclose(c) > Oopen(c) && Oclose(c) > _asianHigh)
                        {
                            bool fvgOk = true;
                            foreach (var f in _fvgList)
                            {
                                if (f.Bullish && f.Lower <= _asianHigh * 1.005 && f.Upper >= _asianHigh * 0.995)
                                {
                                    fvgOk = true;
                                    fvgFound = true;
                                    break;
                                }
                            }
                            if (fvgOk)
                            {
                                retestHit = true;
                                retestBar = c;
                                entryPrice = ask;
                                double slDist = atr * 0.5; // tighter stop for breakout
                                if (slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                                retestSL = _asianHigh - slDist;
                                retestTP = entryPrice + slDist * London_RR;
                                break;
                            }
                        }
                    }
                }
                else if (breakDir == -1) // Bear breakout: retest of Asian low as resistance
                {
                    if (Ohigh(c) >= _asianLow * 0.998 && Ohigh(c) <= _asianLow * 1.005)
                    {
                        if (Oclose(c) < Oopen(c) && Oclose(c) < _asianLow)
                        {
                            bool fvgOk = true;
                            foreach (var f in _fvgList)
                            {
                                if (!f.Bullish && f.Lower <= _asianLow * 1.005 && f.Upper >= _asianLow * 0.995)
                                {
                                    fvgOk = true;
                                    fvgFound = true;
                                    break;
                                }
                            }
                            if (fvgOk)
                            {
                                retestHit = true;
                                retestBar = c;
                                entryPrice = bid;
                                double slDist = atr * 0.5;
                                if (slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                                retestSL = _asianLow + slDist;
                                retestTP = entryPrice - slDist * London_RR;
                                break;
                            }
                        }
                    }
                }
            }

            // --- Execute trade on retest
            if (retestHit && entryPrice > 0 && retestSL > 0 && retestTP > 0)
            {
                double lot = CalcLotSizeRisk(Math.Abs(entryPrice - retestSL), London_RiskPct);
                double minVol = Symbol.VolumeInUnitsMin;
                if (lot < minVol) lot = minVol;

                TradeType orderType = (breakDir == 1) ? TradeType.Buy : TradeType.Sell;
                double price = (orderType == TradeType.Buy) ? ask : bid;

                if (VerifyTrade(orderType, price, retestSL, retestTP, lot))
                {
                    if (OpenOrder(orderType, lot, price, retestSL, retestTP,
                                  CommentPrefix + "_LONDON_" + (orderType == TradeType.Buy ? "BUY" : "SELL")))
                    {
                        _stats.TradeCount++;
                        _stats.SessionTradeCount++;
                        if (DebugMode) Print("LONDON ", (orderType == TradeType.Buy ? "BUY" : "SELL"),
                              " AsianRange: ", _asianHigh, "/", _asianLow,
                              " Retest@", retestBar, " FVG=", fvgFound);
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  NY SESSION: Liquidity Sweep + Reversal
        //  Equal highs/lows, wick sweep, BOS, retest entry.
        // ═══════════════════════════════════════════════════════════

        private void NYLiquiditySweep()
        {
            if (!_swingReady) return;
            if (_entryBars.Count < SweepLookback + 1) return;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            double atr = _atrValue;
            if (atr <= 0) return;

            // --- STEP 1: Identify liquidity levels
            DetectLiquidityLevels();

            // --- STEP 2: Check for sweep of a liquidity level
            int sweptLevel = -1;
            int sweepBar = -1;

            for (int i = 0; i < _liqLevels.Count; i++)
            {
                if (_liqLevels[i].Swept) continue;

                for (int c = 1; c <= 3; c++)
                {
                    if (c > _entryBars.Count - 1) break;

                    if (_liqLevels[i].IsHigh)
                    {
                        if (Ohigh(c) > _liqLevels[i].Price * 1.0005)
                        {
                            double wick = Ohigh(c) - Math.Max(Oclose(c), Oopen(c));
                            double body = Math.Abs(Oclose(c) - Oopen(c));
                            if (wick >= body * 0.5 && Oclose(c) < Oopen(c))
                            {
                                sweptLevel = i;
                                sweepBar = c;
                                var lvl = _liqLevels[i]; lvl.Swept = true; _liqLevels[i] = lvl;
                                break;
                            }
                        }
                    }
                    else
                    {
                        if (Olow(c) < _liqLevels[i].Price * 0.9995)
                        {
                            double wick = Math.Min(Oclose(c), Oopen(c)) - Olow(c);
                            double body = Math.Abs(Oclose(c) - Oopen(c));
                            if (wick >= body * 0.5 && Oclose(c) > Oopen(c))
                            {
                                sweptLevel = i;
                                sweepBar = c;
                                var lvl = _liqLevels[i]; lvl.Swept = true; _liqLevels[i] = lvl;
                                break;
                            }
                        }
                    }
                }
                if (sweptLevel >= 0) break;
            }

            if (sweptLevel < 0) return;

            // --- STEP 3: Confirm BOS (Break of Structure)
            bool bosConfirmed = false;

            if (_liqLevels[sweptLevel].IsHigh)
            {
                // Swept high → sell. BOS = broke a recent swing low
                for (int c = sweepBar + 1; c <= sweepBar + 3 && c < _entryBars.Count; c++)
                {
                    if (c < 1) continue;
                    double recentLow = Olow(c);
                    foreach (double sv in _swingLowVal)
                    {
                        if (sv > recentLow && sv < _liqLevels[sweptLevel].Price * 0.999)
                        {
                            bosConfirmed = true;
                            break;
                        }
                    }
                    if (bosConfirmed) break;
                }
            }
            else
            {
                // Swept low → buy. BOS = broke a recent swing high
                for (int c = sweepBar + 1; c <= sweepBar + 3 && c < _entryBars.Count; c++)
                {
                    if (c < 1) continue;
                    double recentHigh = Ohigh(c);
                    foreach (double sv in _swingHighVal)
                    {
                        if (sv < recentHigh && sv > _liqLevels[sweptLevel].Price * 1.001)
                        {
                            bosConfirmed = true;
                            break;
                        }
                    }
                    if (bosConfirmed) break;
                }
            }

            if (!bosConfirmed) return;

            // --- STEP 4: Enter on retest of the swept level
            int bar = 1; // last closed bar
            double entryPrice = 0;
            double sl = 0;
            double tp = 0;
            TradeType orderType = TradeType.Buy;

            if (_liqLevels[sweptLevel].IsHigh)
            {
                // Sell: swept high, BOS down, retesting swept area
                if (Ohigh(bar) >= _liqLevels[sweptLevel].Price * 0.998 && Oclose(bar) < Oopen(bar))
                {
                    orderType = TradeType.Sell;
                    entryPrice = bid;
                    double slDist = atr * 0.6;
                    if (slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                    sl = _liqLevels[sweptLevel].Price + slDist;
                    tp = entryPrice - slDist * NY_RR;

                    foreach (var f in _fvgList)
                    {
                        if (!f.Bullish && f.Lower < entryPrice && f.Lower > entryPrice - slDist * NY_RR * 0.5)
                        {
                            tp = f.Lower;
                            if (DebugMode) Print("NY TP set to FVG fill: ", tp);
                            break;
                        }
                    }
                }
                else return;
            }
            else
            {
                // Buy: swept low, BOS up, retesting swept area
                if (Olow(bar) <= _liqLevels[sweptLevel].Price * 1.002 && Oclose(bar) > Oopen(bar))
                {
                    orderType = TradeType.Buy;
                    entryPrice = ask;
                    double slDist = atr * 0.6;
                    if (slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                    sl = _liqLevels[sweptLevel].Price - slDist;
                    tp = entryPrice + slDist * NY_RR;

                    foreach (var f in _fvgList)
                    {
                        if (f.Bullish && f.Upper > entryPrice && f.Upper < entryPrice + slDist * NY_RR * 0.5)
                        {
                            tp = f.Upper;
                            if (DebugMode) Print("NY TP set to FVG fill: ", tp);
                            break;
                        }
                    }
                }
                else return;
            }

            if (entryPrice <= 0 || sl <= 0 || tp <= 0) return;

            double lot = CalcLotSizeRisk(Math.Abs(entryPrice - sl), NY_RiskPct);
            double minVol = Symbol.VolumeInUnitsMin;
            if (lot < minVol) lot = minVol;

            double price = (orderType == TradeType.Buy) ? ask : bid;

            if (VerifyTrade(orderType, price, sl, tp, lot))
            {
                if (OpenOrder(orderType, lot, price, sl, tp,
                              CommentPrefix + "_NY_" + (orderType == TradeType.Buy ? "BUY" : "SELL")))
                {
                    _stats.TradeCount++;
                    _stats.SessionTradeCount++;
                    if (DebugMode) Print("NY ", (orderType == TradeType.Buy ? "BUY" : "SELL"),
                          " Swept: ", (_liqLevels[sweptLevel].IsHigh ? "High" : "Low"),
                          "@", _liqLevels[sweptLevel].Price, " RR=", NY_RR);
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Detect Fair Value Gap (FVG) from recent candles
        // ═══════════════════════════════════════════════════════════

        private void DetectFVG()
        {
            _fvgList.Clear();
            if (_entryBars.Count < 11) return;

            for (int i = 1; i < 25; i++)
            {
                if (i + 2 > _entryBars.Count - 1) break;

                // Bullish FVG: older bar (i+1) low > newer bar (i) high (gap up)
                if (Olow(i + 1) > Ohigh(i))
                {
                    _fvgList.Add(new FVG { Bullish = true, Upper = Olow(i + 1), Lower = Ohigh(i), Time = Otime(i + 1) });
                }
                // Bearish FVG: older bar (i+1) high < newer bar (i) low (gap down)
                else if (Ohigh(i + 1) < Olow(i))
                {
                    _fvgList.Add(new FVG { Bullish = false, Upper = Olow(i), Lower = Ohigh(i + 1), Time = Otime(i + 1) });
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Detect liquidity levels (equal highs/lows) for NY
        // ═══════════════════════════════════════════════════════════

        private void DetectLiquidityLevels()
        {
            _liqLevels.Clear();

            int lookback = Math.Min(SweepLookback, _entryBars.Count - 3);
            if (lookback < 8) return;

            // --- Equal highs (within 0.2 ATR)
            for (int i = 1; i < lookback - 5; i++)
            {
                for (int j = i + 3; j < lookback - 2; j++)
                {
                    double diff = Math.Abs(Ohigh(i) - Ohigh(j));
                    if (diff <= _atrValue * 0.2 && diff > 0)
                    {
                        if (i >= 2 && Ohigh(i) > Ohigh(i - 1) && Ohigh(i) > Ohigh(i + 1))
                        {
                            bool dup = false;
                            foreach (var lvl in _liqLevels)
                            {
                                if (lvl.IsHigh && Math.Abs(lvl.Price - Ohigh(i)) < _atrValue * 0.1)
                                { dup = true; break; }
                            }
                            if (!dup)
                            {
                                _liqLevels.Add(new LiqLevel
                                {
                                    Price = Math.Max(Ohigh(i), Ohigh(j)),
                                    Time = Otime(i),
                                    IsHigh = true,
                                    Swept = false
                                });
                            }
                            break;
                        }
                    }
                }
            }

            // --- Equal lows (within 0.2 ATR)
            for (int i = 1; i < lookback - 5; i++)
            {
                for (int j = i + 3; j < lookback - 2; j++)
                {
                    double diff = Math.Abs(Olow(i) - Olow(j));
                    if (diff <= _atrValue * 0.2 && diff > 0)
                    {
                        if (i >= 2 && Olow(i) < Olow(i - 1) && Olow(i) < Olow(i + 1))
                        {
                            bool dup = false;
                            foreach (var lvl in _liqLevels)
                            {
                                if (!lvl.IsHigh && Math.Abs(lvl.Price - Olow(i)) < _atrValue * 0.1)
                                { dup = true; break; }
                            }
                            if (!dup)
                            {
                                _liqLevels.Add(new LiqLevel
                                {
                                    Price = Math.Min(Olow(i), Olow(j)),
                                    Time = Otime(i),
                                    IsHigh = false,
                                    Swept = false
                                });
                            }
                            break;
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Track Asian session range for London breakout
        // ═══════════════════════════════════════════════════════════

        private void TrackAsianRange()
        {
            if (_entryBars.Count < 20) return;

            _asianHigh = 0;
            _asianLow = double.MaxValue;
            _asianRangeReady = false;
            int barsInSession = 0;

            int maxBars = Math.Min(_entryBars.Count, 100);
            for (int i = 0; i < maxBars; i++)
            {
                DateTime t = Otime(i);
                int hourGMT = t.Hour - BrokerGMTOffset;
                if (hourGMT < 0) hourGMT += 24;
                int minuteGMT = t.Minute;

                bool inAsian = ((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
                               (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
                               (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM));

                if (inAsian)
                {
                    if (Ohigh(i) > _asianHigh) _asianHigh = Ohigh(i);
                    if (Olow(i) < _asianLow) _asianLow = Olow(i);
                    barsInSession++;
                }
                else if (barsInSession > 0)
                {
                    // Session ended — stop scanning
                    break;
                }
            }

            if (_asianHigh > 0 && _asianLow < 1e8 && barsInSession >= 3)
            {
                _asianRangeReady = true;
                if (DebugMode) Print("Asian range: H=", _asianHigh, " L=", _asianLow, " bars=", barsInSession);
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Detect session-specific levels (Asian range / FVG / liquidity)
        // ═══════════════════════════════════════════════════════════

        private void DetectSessionLevels()
        {
            SessionType sess = GetCurrentSession();

            // --- Track Asian range for London breakout.
            //    Driven by the Asian time-window (not the session enum): the range
            //    finalizes even when the session flips to None right after Asian,
            //    and a reload after Asian ended rebuilds it straight from history —
            //    so every session can fire trades once the window has completed.
            int hourGMT = GetGMTHour();
            int minuteGMT = GetGMTMin();
            int nowMin = hourGMT * 60 + minuteGMT;
            int asianStart = Asian_StartH * 60 + Asian_StartM;
            int asianEnd = Asian_EndH * 60 + Asian_EndM;
            bool wrap = (asianEnd < asianStart);
            int t = nowMin;
            if (wrap && t < asianStart) t += 1440;
            bool inAsian = wrap ? (t >= asianStart && t <= asianEnd)
                                : (nowMin >= asianStart && nowMin <= asianEnd);
            bool afterAsian = wrap ? (t > asianEnd) : (nowMin > asianEnd);

            if (inAsian)
            {
                // (Re)arm the tracker when entering the window
                if (_asianSessionStart == DateTime.MinValue)
                {
                    _asianSessionStart = Server.Time.ToUniversalTime();
                    _asianHigh = 0;
                    _asianLow = double.MaxValue;
                    _asianRangeReady = false;
                }
            }
            else if (afterAsian && !_asianRangeReady)
            {
                // Window over: finalize the range from the completed Asian bars.
                // Retried on every new bar until it succeeds (reload-safe).
                TrackAsianRange();
                _asianSessionStart = DateTime.MinValue;
            }

            // --- Detect FVGs for NY/London sessions
            if (sess == SessionType.NY || sess == SessionType.London)
            {
                DetectFVG();
            }

            // --- Detect liquidity levels for NY session
            if (sess == SessionType.NY)
            {
                DetectLiquidityLevels();
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Time / Session helpers (Server.Time is UTC = GMT)
        // ═══════════════════════════════════════════════════════════

        private int GetGMTHour()
        {
            int h = Server.Time.ToUniversalTime().Hour - BrokerGMTOffset;
            if (h < 0) h += 24;
            return h;
        }

        private int GetGMTMin()
        {
            return Server.Time.ToUniversalTime().Minute;
        }

        private SessionType GetCurrentSession()
        {
            int hourGMT = GetGMTHour();
            int minuteGMT = GetGMTMin();
            int t = hourGMT * 60 + minuteGMT;

            int asianStart = Asian_StartH * 60 + Asian_StartM;
            int asianEnd = Asian_EndH * 60 + Asian_EndM;
            int londonStart = London_StartH * 60 + London_StartM;
            int londonEnd = London_EndH * 60 + London_EndM;
            int nyStart = NY_StartH * 60 + NY_StartM;
            int nyEnd = NY_EndH * 60 + NY_EndM;

            if (asianEnd < asianStart) asianEnd += 1440;
            if (nyEnd < nyStart) nyEnd += 1440;

            int tt = t;
            if (asianEnd < asianStart && tt < asianStart) tt += 1440;
            if (tt >= asianStart && tt <= asianEnd) return SessionType.Asian;

            tt = t;
            if (londonEnd < londonStart && tt < londonStart) tt += 1440;
            if (tt >= londonStart && tt <= londonEnd) return SessionType.London;

            tt = t;
            if (nyEnd < nyStart && tt < nyStart) tt += 1440;
            if (tt >= nyStart && tt <= nyEnd) return SessionType.NY;

            return SessionType.None;
        }

        private string GetSessionName(SessionType s)
        {
            switch (s)
            {
                case SessionType.Asian: return "ASIAN";
                case SessionType.London: return "LONDON";
                case SessionType.NY: return "NY";
                default: return "OUTSIDE";
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Update swing points from price action
        // ═══════════════════════════════════════════════════════════

        private void UpdateSwingPoints()
        {
            _swingHighVal.Clear();
            _swingLowVal.Clear();
            if (_entryBars.Count < 50) return;

            int lookback = Math.Min(SwingLookback, _entryBars.Count - 2);

            for (int i = 2; i < lookback; i++)
            {
                if (Ohigh(i) > Ohigh(i - 1) && Ohigh(i) > Ohigh(i + 1))
                    _swingHighVal.Add(Ohigh(i));
                if (Olow(i) < Olow(i - 1) && Olow(i) < Olow(i + 1))
                    _swingLowVal.Add(Olow(i));
            }

            _swingReady = (_swingHighVal.Count > 0 && _swingLowVal.Count > 0);
        }

        // ═══════════════════════════════════════════════════════════
        //  Calculate ATR (manual, matches ScalpXAU.mq5 CalcATR)
        // ═══════════════════════════════════════════════════════════

        private double CalcATR(int period)
        {
            if (_entryBars.Count < period + 2) return 0;

            double sum = 0;
            for (int i = 1; i <= period; i++)
            {
                double h = Ohigh(i);
                double l = Olow(i);
                double pc = Oclose(i - 1);
                double tr = Math.Max(h - l, Math.Max(Math.Abs(h - pc), Math.Abs(l - pc)));
                sum += tr;
            }
            return sum / period;
        }

        private bool IsNewBar()
        {
            DateTime t = _entryBars.OpenTimes[_entryBars.Count - 1];
            if (t != _lastBarTime)
            {
                _lastBarTime = t;
                return true;
            }
            return false;
        }

        private double GetRSI(int back)
        {
            try
            {
                if (_rsi == null || _rsi.Result.Count <= back) return double.NaN;
                return _rsi.Result.Last(back);
            }
            catch { return double.NaN; }
        }

        // ═══════════════════════════════════════════════════════════
        //  Daily reset
        // ═══════════════════════════════════════════════════════════

        private void ResetDaily()
        {
            DateTime today = Server.Time.ToUniversalTime().Date;

            if (_stats.LastResetTime.Date != today)
            {
                _stats.LastResetTime = today;
                _stats.StartingBalance = Account.Balance;
                _stats.TradeCount = 0;
                _stats.SessionTradeCount = 0;
                _stats.TradingStopped = false;
                _stats.LastSession = SessionType.None;
                _asianSessionStart = DateTime.MinValue;
                _asianRangeReady = false;
                Print("--- Daily reset. Balance: ", _stats.StartingBalance, " ---");
            }

            if (!_stats.TradingStopped && _stats.StartingBalance > 0)
            {
                double ddPct = (_stats.StartingBalance - Account.Equity) / _stats.StartingBalance * 100.0;
                if (ddPct >= MaxDailyRiskPct)
                {
                    _stats.TradingStopped = true;
                    Print("*** MAX DAILY LOSS REACHED: ", ddPct.ToString("F2"), "% ***");
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Manage open positions (break-even + trailing)
        // ═══════════════════════════════════════════════════════════

        private void ManagePositions()
        {
            if (!UseBreakEven && !UseTrailing) return;
            if (_atrValue <= 0) return;

            double point = Symbol.TickSize;

            foreach (var pos in Positions)
            {
                if (pos.SymbolName != Symbol.Name || !pos.Label.StartsWith(CommentPrefix)) continue;
                // Gainz-Swing positions keep their hard SL/TP: managed by
                // ManageGainzPositions() (max-hold + no-overnight), not the
                // scalp break-even/trailing.
                if (pos.Label.StartsWith(CommentPrefix + "_G_")) continue;

                double entry = pos.EntryPrice;
                double sl = pos.StopLoss ?? 0;
                bool isBuy = pos.TradeType == TradeType.Buy;
                double curPrice = isBuy ? Symbol.Bid : Symbol.Ask;
                bool isTrend = pos.Label.Contains("_T_");

                // --- Break-even (trend trades wait for the wide-trail start instead of the tight scalp BE)
                if (UseBreakEven)
                {
                    double beDist = (isTrend ? Trend_TrailStart_ATR : BE_ATR_Mult) * _atrValue;
                    if (isBuy)
                    {
                        if (curPrice >= entry + beDist && sl < entry)
                            ModifySL(pos, entry + point * 5);
                    }
                    else
                    {
                        if (curPrice <= entry - beDist && (sl > entry || sl == 0))
                            ModifySL(pos, entry - point * 5);
                    }
                }

                // --- Trailing stop (trend trades get the wide trail; scalps keep the tight one)
                if (UseTrailing)
                {
                    double trailStart = (isTrend ? Trend_TrailStart_ATR : TrailStart_ATR) * _atrValue;
                    double trailStep = (isTrend ? Trend_TrailStep_ATR : TrailStep_ATR) * _atrValue;

                    if (isBuy)
                    {
                        double profitDist = curPrice - entry;
                        if (profitDist >= trailStart)
                        {
                            double newSL = curPrice - trailStep;
                            if (newSL > sl + point)
                                ModifySL(pos, newSL);
                        }
                    }
                    else
                    {
                        double profitDist = entry - curPrice;
                        if (profitDist >= trailStart)
                        {
                            double newSL = curPrice + trailStep;
                            if (newSL < sl - point || sl == 0)
                                ModifySL(pos, newSL);
                        }
                    }
                }
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  GAINZ-SWING MODE
        //  Swing profile: TP +159p / SL -322p, breakout of the previous day's
        //  range with EMA trend bias, session-gated (default London+NY 07-21
        //  GMT), max hold 11h, hard SL, no overnight. One position at a time.
        // ═══════════════════════════════════════════════════════════

        private void UpdateGainzLevels()
        {
            if (_gainzBars == null) return;

            // --- previous completed day's high/low (server-day = UTC here)
            var daily = MarketData.GetBars(TimeFrame.Daily, Symbol.Name);
            if (daily != null && daily.ClosePrices.Count >= 2)
            {
                _gainzPrevDayHigh = daily.HighPrices.Last(1);
                _gainzPrevDayLow = daily.LowPrices.Last(1);
            }

            // --- advance the EMA over newly closed H1 bars (forming bar excluded)
            if (_gainzEMASeeded && _gainzBars.ClosePrices.Count >= 2)
            {
                int lastClosed = _gainzBars.ClosePrices.Count - 2;
                if (lastClosed > _gainzLastEmaIndex)
                {
                    double k = 2.0 / (Gainz_EMA_Period + 1);
                    for (int i = _gainzLastEmaIndex + 1; i <= lastClosed; i++)
                    {
                        _gainzEMA += k * (_gainzBars.ClosePrices[i] - _gainzEMA);
                    }
                    _gainzLastEmaIndex = lastClosed;
                }
            }
        }

        private bool InGainzSessionWindow()
        {
            int t = GetGMTHour() * 60 + GetGMTMin();
            int start = Gainz_StartH * 60;
            int end = Gainz_EndH * 60;
            if (end < start) end += 1440;
            if (t < start) t += 1440;
            return t >= start && t <= end;
        }

        private int CountGainzPositions()
        {
            int c = 0;
            foreach (var pos in Positions)
                if (pos.SymbolName == Symbol.Name && pos.Label.StartsWith(CommentPrefix + "_G_"))
                    c++;
            return c;
        }

        private void CheckGainzEntry()
        {
            if (_gainzBars == null || !_gainzEMASeeded) return;
            if (_gainzBars.ClosePrices.Count < Gainz_EMA_Period + 2) return;

            // --- one attempt per closed H1 bar
            DateTime barTime = _gainzBars.OpenTimes.Last(0);
            if (barTime == _lastGainzEntryBarTime) return;
            _lastGainzEntryBarTime = barTime;

            // --- cooldown after a Gainz exit
            if (Server.Time.ToUniversalTime() < _gainzNextEntryAllowed) return;

            // --- shared guards
            if (_stats.TradingStopped || _stats.SessTradingStopped) return;
            if (_stats.SessionTradeCount >= MaxTradesPerSess) return;
            if (CountOpenPositions() >= MaxPositions) return;
            if (CountGainzPositions() > 0) return;   // one swing position at a time

            // --- session window
            if (!InGainzSessionWindow()) return;

            // --- signal on the last CLOSED H1 bar:
            //     long  = close > prev-day high AND close > EMA
            //     short = close < prev-day low  AND close < EMA
            UpdateGainzLevels();
            int lastClosed = _gainzBars.ClosePrices.Count - 2;
            if (lastClosed < 1) return;
            double close = _gainzBars.ClosePrices[lastClosed];
            double ema = _gainzEMA;
            if (ema <= 0 || _gainzPrevDayHigh <= 0 || _gainzPrevDayLow >= 1e8) return;

            bool longSig = close > _gainzPrevDayHigh && close > ema;
            bool shortSig = close < _gainzPrevDayLow && close < ema;
            if (!longSig && !shortSig) return;

            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            double tpPips = Gainz_TP_Pips * Symbol.PipSize;
            double slPips = Gainz_SL_Pips * Symbol.PipSize;
            double lot;
            TradeResult res;

            if (longSig)
            {
                double sl = ask - slPips;
                double tp = ask + tpPips;
                lot = CalcLotSizeRisk(slPips, Gainz_RiskPct);
                if (lot <= 0) return;
                if (!VerifyTrade(TradeType.Buy, ask, sl, tp, lot)) return;
                res = OpenOrderResult(TradeType.Buy, lot, CommentPrefix + "_G_BUY", sl, tp);
                if (res != null && res.IsSuccessful)
                {
                    RegisterGainzEntry(res, "BUY", close, _gainzPrevDayHigh, ema);
                }
            }
            else
            {
                double sl = bid + slPips;
                double tp = bid - tpPips;
                lot = CalcLotSizeRisk(slPips, Gainz_RiskPct);
                if (lot <= 0) return;
                if (!VerifyTrade(TradeType.Sell, bid, sl, tp, lot)) return;
                res = OpenOrderResult(TradeType.Sell, lot, CommentPrefix + "_G_SELL", sl, tp);
                if (res != null && res.IsSuccessful)
                {
                    RegisterGainzEntry(res, "SELL", close, _gainzPrevDayLow, ema);
                }
            }
        }

        private void RegisterGainzEntry(TradeResult res, string side, double close,
                                        double level, double ema)
        {
            _stats.TradeCount++;
            _stats.SessionTradeCount++;
            if (res.Position != null)
                _gainzOpenSince[res.Position.Id] = Server.Time.ToUniversalTime();
            if (DebugMode) Print("GAINZ ", side, ": close=", close.ToString("F2"),
                  " lvl=", level.ToString("F2"), " EMA=", ema.ToString("F2"));
        }

        private void ManageGainzPositions()
        {
            if (!EnableGainzSwing) return;
            DateTime now = Server.Time.ToUniversalTime();
            int hourGMT = GetGMTHour();
            bool pastCutoff = Gainz_NoOvernight && hourGMT >= Gainz_CutoffHour;

            var toClose = new List<Position>();
            foreach (var pos in Positions)
            {
                if (pos.SymbolName != Symbol.Name || !pos.Label.StartsWith(CommentPrefix + "_G_")) continue;

                string reason = null;
                if (_gainzOpenSince.TryGetValue(pos.Id, out var opened))
                {
                    if ((now - opened).TotalHours >= Gainz_MaxHoldHours)
                        reason = "MAX_HOLD";
                }
                if (reason == null && pastCutoff)
                    reason = "CUTOFF_NO_OVERNIGHT";
                if (reason != null)
                {
                    toClose.Add(pos);
                    if (DebugMode)
                        Print("GAINZ CLOSE (", reason, ") id=", pos.Id,
                              " pnl~$", ((pos.TradeType == TradeType.Buy ? Symbol.Bid - pos.EntryPrice
                                                                          : pos.EntryPrice - Symbol.Ask)).ToString("F2"));
                }
            }

            foreach (var pos in toClose)
            {
                var r = ClosePosition(pos);
                if (!r.IsSuccessful && DebugMode)
                    Print("GAINZ CLOSE FAILED: ", r.Error);
            }

            // --- detect positions that vanished on their own (TP/SL hit): set cooldown
            var liveIds = new HashSet<long>();
            foreach (var pos in Positions)
                if (pos.SymbolName == Symbol.Name && pos.Label.StartsWith(CommentPrefix + "_G_"))
                    liveIds.Add(pos.Id);

            var gone = new List<long>();
            foreach (var kv in _gainzOpenSince)
                if (!liveIds.Contains(kv.Key))
                    gone.Add(kv.Key);
            foreach (var id in gone)
            {
                _gainzOpenSince.Remove(id);
                if (Gainz_CooldownHours > 0 && now >= _gainzNextEntryAllowed)
                    _gainzNextEntryAllowed = now.AddHours(Gainz_CooldownHours);
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  Position helpers
        // ═══════════════════════════════════════════════════════════

        private int CountOpenPositions()
        {
            int count = 0;
            foreach (var pos in Positions)
                if (pos.SymbolName == Symbol.Name && pos.Label.StartsWith(CommentPrefix))
                    count++;
            return count;
        }

        private void CloseAllPositions(string reason)
        {
            foreach (var pos in Positions)
            {
                if (pos.SymbolName == Symbol.Name && pos.Label.StartsWith(CommentPrefix))
                {
                    var res = ClosePosition(pos);
                    if (DebugMode && !res.IsSuccessful)
                        Print("CloseAll: close failed, err=", res.Error);
                }
            }
        }

        private void ModifySL(Position pos, double newSL)
        {
            double currentSL = pos.StopLoss ?? 0;
            if (Math.Abs(newSL - currentSL) < Symbol.TickSize * 2) return;
            ModifyPosition(pos, newSL, pos.TakeProfit);
        }

        // ═══════════════════════════════════════════════════════════
        //  Lot sizing, validation, order execution
        // ═══════════════════════════════════════════════════════════

        private double CalcLotSizeRisk(double slDist, double riskPct)
        {
            if (slDist <= 0) return 0;

            // Floor pathologically tiny SL distances (e.g. a sweep entry whose liquidity
            // level sits right at price) so risk-based sizing can't explode into 1000+ oz.
            if (_atrValue > 0 && slDist < Min_SL_ATR * _atrValue) slDist = Min_SL_ATR * _atrValue;

            double tickVal = Symbol.TickValue;
            double tickSize = Symbol.TickSize;
            if (tickVal <= 0 || tickSize <= 0) return 0;

            double riskAmount = Account.Balance * riskPct / 100.0;
            double slTicks = slDist / tickSize;
            double lot = riskAmount / (slTicks * tickVal);

            // Round DOWN to the symbol's volume step (XAUUSD step=1 unit → integer volumes).
            // Math.Round(lot,2) produced off-step volumes (e.g. 10.19) → BadVolume rejections.
            double step = Symbol.VolumeInUnitsStep > 0 ? Symbol.VolumeInUnitsStep : 1;
            lot = Math.Floor(lot / step) * step;

            double minVol = Symbol.VolumeInUnitsMin;
            double maxVol = Symbol.VolumeInUnitsMax > 0 ? Symbol.VolumeInUnitsMax : 100;

            // Notional cap: ~$30k exposure per $10k balance (~7 oz at current gold).
            // Stops margin blow-ups from oversized positions (e.g. the 2465-oz NoMoney order).
            double price = Symbol.Bid;
            if (price > 0)
            {
                double volCap = (Account.Balance / 10000.0) * 30000.0 / price;
                if (volCap < maxVol) maxVol = volCap;
            }
            if (step > 0) maxVol = Math.Floor(maxVol / step) * step;

            return Math.Max(minVol, Math.Min(lot, maxVol));
        }

        private bool VerifyTrade(TradeType type, double price, double sl, double tp, double lot)
        {
            double bid = Symbol.Bid;
            double ask = Symbol.Ask;
            int digits = Symbol.Digits;

            price = Math.Round(price, digits);
            sl = Math.Round(sl, digits);
            tp = Math.Round(tp, digits);

            if (lot <= 0) return false;
            if (type == TradeType.Buy && price < bid * 0.99) return false;
            if (type == TradeType.Sell && price > ask * 1.01) return false;

            // tp==0 allowed: trend-leg trades ride the trend with a wide trail, no fixed TP.
            if (type == TradeType.Buy) { if (sl >= price || (tp > 0 && tp <= price)) return false; }
            if (type == TradeType.Sell) { if (sl <= price || (tp > 0 && tp >= price)) return false; }

            double slDist = Math.Abs(price - sl);
            double tpDist = Math.Abs(tp - price);
            double minDist = Symbol.MinStopLossDistance * Symbol.TickSize;

            if (slDist < minDist && slDist > 0) return false;
            if (tpDist < minDist && tpDist > 0) return false;

            return true;
        }

        private bool OpenOrder(TradeType type, double volume, double price, double sl, double tp, string comment)
        {
            int digits = Symbol.Digits;
            price = Math.Round(price, digits);
            sl = Math.Round(sl, digits);
            tp = Math.Round(tp, digits);

            var result = ExecuteMarketOrder(type, Symbol.Name, volume, comment, sl, tp);
            if (result != null && result.IsSuccessful)
            {
                if (DebugMode) Print("ORDER OK: ", comment, " vol=", volume, " price=", price, " sl=", sl, " tp=", tp);
                return true;
            }

            string err = result != null ? result.Error.ToString() : "Unknown";
            Print("ORDER FAILED: ", comment, " err=", err, " vol=", volume,
                  " price=", price, " sl=", sl, " tp=", tp);
            return false;
        }

        // Gainz-Swing variant: returns the TradeResult so the opened Position id
        // can be tracked for max-hold / no-overnight management.
        private TradeResult OpenOrderResult(TradeType type, double volume, string comment, double sl, double tp)
        {
            int digits = Symbol.Digits;
            sl = Math.Round(sl, digits);
            tp = Math.Round(tp, digits);

            var result = ExecuteMarketOrder(type, Symbol.Name, volume, comment, sl, tp);
            if (result != null && result.IsSuccessful)
            {
                if (DebugMode) Print("ORDER OK: ", comment, " vol=", volume, " sl=", sl, " tp=", tp);
                return result;
            }

            string err = result != null ? result.Error.ToString() : "Unknown";
            Print("ORDER FAILED: ", comment, " err=", err, " vol=", volume,
                  " sl=", sl, " tp=", tp);
            return result;
        }

        // ═══════════════════════════════════════════════════════════
        //  Chart display
        // ═══════════════════════════════════════════════════════════

        private void UpdateComment()
        {
            string sep = "\n" + new string('-', 30) + "\n";
            string info = "=== ScalpXAU cBot ===" + sep;
            info += "Symbol: " + Symbol.Name + " | TF: " + EntryTF + "\n";
            info += "Balance: $" + Account.Balance.ToString("F2");
            info += " | Equity: $" + Account.Equity.ToString("F2");
            info += " | Spread: " + Symbol.Spread + "\n";

            double dd = 0;
            if (_stats.StartingBalance > 0)
                dd = (_stats.StartingBalance - Account.Equity) / _stats.StartingBalance * 100.0;
            info += "Today: " + _stats.TradeCount;
            info += " | Session: " + _stats.SessionTradeCount + "/" + MaxTradesPerSess;
            info += " | DD: " + dd.ToString("F2") + "% (limit: " + MaxDailyRiskPct.ToString("F1") + "%)" + sep;

            info += "Session: " + GetSessionName(_currentSession) + " (GMT";
            if (BrokerGMTOffset != 0) info += (BrokerGMTOffset > 0 ? "+" : "") + BrokerGMTOffset;
            info += ")" + "\n";

            if (_asianRangeReady)
                info += "Asian Range: H=" + _asianHigh.ToString("F2") + " L=" + _asianLow.ToString("F2") + "\n";

            info += "FVG: " + _fvgList.Count + " | LiqLevels: " + _liqLevels.Count + "\n";
            info += "ATR(14): " + _atrValue.ToString("F1") + " | Swings: " + _swingHighVal.Count + "H/" + _swingLowVal.Count + "L" + "\n";
            info += "Open: " + CountOpenPositions() + sep;

            info += "Asian " + (EnableAsian ? "ON" : "OFF");
            info += " | London " + (EnableLondon ? "ON" : "OFF");
            info += " | NY " + (EnableNY ? "ON" : "OFF");
            info += " | Gainz " + (EnableGainzSwing ? "ON" : "OFF") + "\n";
            info += "Trailing: " + (UseTrailing ? "ON" : "OFF") + " | BE: " + (UseBreakEven ? "ON" : "OFF") + "\n";

            if (_stats.TradingStopped)
                info += "*** TRADING STOPPED (daily loss limit) ***\n";
            if (_stats.SessTradingStopped)
                info += "*** SESSION STOPPED (session DD limit) ***\n";

            Chart.DrawStaticText("scalpx_status", info, VerticalAlignment.Top, HorizontalAlignment.Right, Color.Gray);
        }

        // ═══════════════════════════════════════════════════════════
        //  Telegram Alerts
        // ═══════════════════════════════════════════════════════════

        private void Positions_Opened(PositionOpenedEventArgs args)
        {
            var p = args.Position;
            if (p.SymbolName != Symbol.Name) return;

            bool gainz = p.Label.StartsWith(CommentPrefix + "_G_");
            string side = p.TradeType == TradeType.Buy ? "BUY" : "SELL";
            string mode = gainz ? "GAINZ" : (p.Label.Contains("_T_") ? "TREND" : "SESSION");

            string msg = side + " " + p.SymbolName + " OPEN | " + mode
                + "\nPrice: " + p.EntryPrice.ToString("F2")
                + " | Lots: " + p.Quantity.ToString("F2")
                + "\nSL: " + FmtPrice(p.StopLoss) + " | TP: " + FmtPrice(p.TakeProfit)
                + "\nTime: " + p.EntryTime.ToString("yyyy-MM-dd HH:mm") + " GMT";

            SendTelegram(msg);
        }

        private void Positions_Closed(PositionClosedEventArgs args)
        {
            var p = args.Position;
            if (p.SymbolName != Symbol.Name) return;

            bool gainz = p.Label.StartsWith(CommentPrefix + "_G_");
            string side = p.TradeType == TradeType.Buy ? "BUY" : "SELL";
            string reason;
            switch (args.Reason)
            {
                case PositionCloseReason.TakeProfit: reason = "TP HIT"; break;
                case PositionCloseReason.StopLoss:   reason = "SL HIT"; break;
                case PositionCloseReason.StopOut:    reason = "STOP-OUT"; break;
                default:                             reason = "CLOSED"; break;
            }

            string msg = (gainz ? "GAINZ " : "") + side + " " + p.SymbolName
                + " CLOSED | " + reason
                + "\nP/L: " + (p.NetProfit >= 0 ? "+" : "") + p.NetProfit.ToString("F2") + " USD"
                + " | " + p.Pips.ToString("F1") + " pips"
                + "\nHold: " + (Server.Time - p.EntryTime).TotalHours.ToString("F1") + "h";

            SendTelegram(msg);
        }

        private string FmtPrice(double? price)
        {
            return price.HasValue ? price.Value.ToString("F2") : "none";
        }

        private void SendTelegram(string message)
        {
            if (!EnableTelegramAlerts
                || string.IsNullOrWhiteSpace(TelegramToken)
                || string.IsNullOrWhiteSpace(TelegramChatId))
                return;

            try
            {
                string url = "https://api.telegram.org/bot" + TelegramToken + "/sendMessage"
                    + "?chat_id=" + TelegramChatId
                    + "&disable_web_page_preview=true"
                    + "&text=" + Uri.EscapeDataString(message);

                var request = new HttpRequest(new Uri(url));
                request.Timeout = TimeSpan.FromSeconds(15);

                Http.SendAsync(request, response =>
                {
                    if (response.IsSuccessful)
                        LogAlert("SENT OK | " + message.Replace("\n", " | "));
                    else
                        LogAlert("SEND FAIL " + response.StatusCode + " | " + response.Body);
                });
            }
            catch (Exception ex)
            {
                LogAlert("SEND ERROR | " + ex.Message);
                Print("TELEGRAM ERROR: ", ex.Message);
            }
        }

        private void LogAlert(string detail)
        {
            try
            {
                string path = System.IO.Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
                    "scalpxau_alerts.log");
                System.IO.File.AppendAllText(path,
                    Server.Time.ToString("yyyy-MM-dd HH:mm:ss") + " GMT | " + detail + Environment.NewLine);
            }
            catch
            {
                // logging is best-effort only
            }
        }

        // ═══════════════════════════════════════════════════════════
        //  OnStop
        // ═══════════════════════════════════════════════════════════

        protected override void OnStop()
        {
            Print("=== ScalpXAU cBot Stopped ===");
            Print("Trades today: ", _stats.TradeCount);
        }
    }
}
