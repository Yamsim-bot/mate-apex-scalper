//+------------------------------------------------------------------+
//|                                           ScalpXAU.mq5           |
//|                                      XAUUSD Session Scalper      |
//|                   Asian: Range | London: Breakout | NY: Sweep     |
//+------------------------------------------------------------------+
#property copyright "FXRE"
#property version   "1.00"
#property description "XAUUSD Scalper — 3 Session-Specific Strategies"
#property description "Asian (12:30-3:30 GMT): S/R zones + RSI + pin/engulf"
#property description "London (7:00-10:00 GMT): Asian breakout + retest"
#property description "NY (13:30-16:30 GMT): Liq sweep + BOS + reversal"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- General
input string   Inp_Gen            = "======== GENERAL ========";   // ─────────
input double   RiskPerTradePct    = 1.0;                            // Risk per trade (%)
input double   MaxDailyRiskPct    = 5.0;                            // Max daily risk (%)
input double   MaxSessDDPct       = 5.0;                            // Max drawdown per session (%)
input int      MaxTradesPerSess   = 40;                             // Max trades per session
input int      MaxPositions       = 3;                              // Max concurrent positions
input int      BrokerGMTOffset    = -99;                             // Broker GMT offset (-99=auto-detect)
input bool     DebugMode          = false;                          // Debug logging

//--- Timeframes
input string   Inp_TF             = "======= TIMEFRAMES =======";   // ─────────
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M15;                     // Entry timeframe
input int      SwingLookback      = 100;                            // Swing lookback bars

//--- Asian Session (Range Scalp)
input string   Inp_Asian          = "===== ASIAN SESSION ======";   // ─────────
input bool     EnableAsian        = true;                           // Enable Asian strategy
input int      Asian_TP_Pips      = 10;                             // TP (pips) — 10-15 recommended
input double   Asian_SL_BufferATR = 0.4;                            // SL buffer beyond range (xATR)
input int      RSI_Period         = 14;                             // RSI period
input double   RSI_OB             = 72.0;                           // RSI overbought (sell)
input double   RSI_OS             = 28.0;                           // RSI oversold (buy)

//--- London Session (Breakout+Retest)
input string   Inp_London         = "===== LONDON SESSION ======";  // ─────────
input bool     EnableLondon       = true;                           // Enable London strategy
input double   London_RR          = 1.5;                            // Risk:Reward (1:2 default)
input double   London_RiskPct     = 1.0;                            // Risk per trade (%) for London

//--- NY Session (Liquidity Sweep)
input string   Inp_NY             = "===== NY SESSION ==========";  // ─────────
input bool     EnableNY           = true;                           // Enable NY strategy
input double   NY_RR              = 1.5;                            // Risk:Reward (1:2 default)
input double   NY_RiskPct         = 1.0;                            // Risk per trade (%) for NY
input int      SweepLookback      = 50;                             // Bars to look for equal highs/lows

//--- Trend Following Leg (MA50/200 regime, pullback + breakout)
input string   Inp_Trend          = "===== TREND LEG ============="; // ─────────
input bool     EnableTrend        = true;                           // Enable trend-following leg
input int      Trend_MA_Fast      = 50;                             // Trend fast MA period (M15)
input int      Trend_MA_Slow      = 200;                            // Trend slow MA period (M15)
input double   Trend_MinSep_ATR   = 0.50;                           // Min |MAfast-MAslow| / ATR (regime gate)
input bool     Trend_SlopeFilter  = true;                           // Both MAs must slope with trend (kills chop whipsaws)
input double   Trend_Pullback_ATR = 0.50;                           // Pullback must dip within this of fast MA (xATR)
input double   Trend_Breakout_ATR = 0.60;                           // Breakout bar clears prior high/low by this (xATR)
input double   Trend_SL_Buffer_ATR= 0.30;                           // SL beyond pullback-low / breakout-bar low (xATR)
input double   Trend_TrailStart_ATR = 1.00;                         // Wide trail start after profit (xATR)
input double   Trend_TrailStep_ATR  = 0.50;                         // Wide trail step (xATR)
input double   Trend_RiskPct     = 1.0;                             // Risk per trend trade (%)

//--- Gainz-Swing Mode (port of the Gainz Algo V2 EA profile; validated by
//--- backtest on XAUUSD H1 2020-10 -> 2023-10 in gainz_backtest.py: with
//--- hard SL, session gating, 11h max hold and no overnight the TP159/SL322
//--- profile turned +11% on real data vs the real EA's -11% (no stop, swap,
//--- averaging). NOTE: Gainz pips = point (0.01 for gold), unlike the session
//--- strategies which use 10-point pips.)
input string   Inp_Gainz          = "===== GAINZ-SWING =========";  // ─────────
input bool     EnableGainzSwing   = false;                           // Enable Gainz-Swing mode
input int      Gainz_TP_Pips      = 159;                             // Gainz TP (point-pips)
input int      Gainz_SL_Pips      = 322;                             // Gainz SL (point-pips)
input int      Gainz_MaxHoldHours = 11;                              // Max hold (hours)
input bool     Gainz_NoOvernight  = true;                            // Close before overnight
input int      Gainz_CutoffHour   = 22;                              // No-overnight cutoff hour (GMT)
input int      Gainz_StartH       = 7;                               // Session start (GMT)
input int      Gainz_EndH         = 21;                              // Session end (GMT)
input double   Gainz_RiskPct      = 1.0;                             // Risk per trade (%)
input int      Gainz_EMA_Period   = 200;                             // Trend EMA period (H1)
input int      Gainz_CooldownHours = 3;                              // Cooldown after exit (hours)

//--- Risk Management
input string   Inp_RM             = "===== RISK MGMT ==========";   // ─────────
input bool     UseBreakEven       = true;                           // Break-even after profit
input double   BE_ATR_Mult        = 0.6;                            // Break-even trigger (xATR)
input bool     UseTrailing        = true;                           // Trailing stop
input double   TrailStart_ATR     = 0.8;                            // Trailing start (xATR)
input double   TrailStep_ATR      = 0.3;                            // Trailing step (xATR)
input int      MaxSlippagePts     = 30;                             // Max slippage (points)
input double   Min_SL_ATR         = 1.0;                            // Min SL distance (xATR, stops inside noise get clipped)
input int      MagicNumber        = 241107;                         // Magic number
input string   CommentPrefix      = "SCALPX_EA";                    // Order comment tag

//--- Session Times in GMT
input string   Inp_Time           = "====== SESSION GMT TIMES ===="; // ─────────
// Asian: 12:30-3:30 GMT
input int      Asian_StartH       = 0;                              // Asian start hour (GMT)
input int      Asian_StartM       = 30;                             // Asian start minute
input int      Asian_EndH         = 3;                              // Asian end hour (GMT)
input int      Asian_EndM         = 30;                             // Asian end minute
// London: 7:00-10:00 GMT
input int      London_StartH      = 7;                              // London start hour (GMT)
input int      London_StartM      = 0;                              // London start minute
input int      London_EndH        = 10;                             // London end hour (GMT)
input int      London_EndM        = 0;                              // London end minute
// NY: 13:30-16:30 GMT
input int      NY_StartH          = 13;                             // NY start hour (GMT)
input int      NY_StartM          = 30;                             // NY start minute
input int      NY_EndH            = 16;                             // NY end hour (GMT)
input int      NY_EndM            = 30;                             // NY end minute

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
CAccountInfo   m_account;

//--- Indicators
int            hRSI;
int            hMAFast = INVALID_HANDLE;
int            hMASlow = INVALID_HANDLE;

//--- Last bar the trend leg filled (1 entry per M15 bar — set AFTER open only)
datetime       g_trendEntryBarTime = 0;

//--- Session tracking
enum SessionType { SESS_NONE = -1, SESS_ASIAN = 0, SESS_LONDON = 1, SESS_NY = 2 };
SessionType    g_currentSession = SESS_NONE;

//--- Asian range (for London breakout)
double         g_asianHigh = 0;
double         g_asianLow  = 0;
datetime       g_asianSessionStart = 0;
bool           g_asianRangeReady = false;

//--- Swing points
double         g_swingHighVal[];
int            g_swingHighIdx[];
double         g_swingLowVal[];
int            g_swingLowIdx[];
bool           g_swingReady = false;

//--- Daily stats
struct DailyStats
{
   double      startingBalance;
   int         tradeCount;
   int         sessionTradeCount;
   SessionType lastSession;
   bool        tradingStopped;
   bool        sessionActive;
   datetime    lastResetTime;
   double      sessionStartEquity;
   bool        sessTradingStopped;
};
DailyStats     g_stats;

//--- ATR value
double         g_atrValue = 0;

//--- Last bar time (for new bar detection)
datetime       g_lastBarTime = 0;

//--- Last bar an entry attempt was made (1 entry attempt per bar —
//--- stops the per-tick flip-flop loop and the market-close retry storm)
datetime       g_lastEntryBarTime = 0;

//--- FVG detection buffer
struct FVG
{
   double      upper;
   double      lower;
   datetime    time;
   bool        bullish; // true=bullish FVG (gap up), false=bearish FVG (gap down)
};
FVG            g_fvgList[];
int            g_fvgCount;

//--- Liquidiy levels (equal highs/lows for NY)
struct LiqLevel
{
   double      price;
   datetime    time;
   bool        isHigh; // true=high, false=low
   bool        swept;
};
LiqLevel       g_liqLevels[];
int            g_liqCount;

//--- Heartbeat
int            g_tickCount = 0;

//--- Trade prefix
string         g_commentPrefix = "XAU";

//--- Gainz-Swing state
int            hGainzEMA = INVALID_HANDLE;      // H1 EMA trend filter
ulong          g_gainzTickets[];                // snapshot of open Gainz tickets
int            g_gainzTicketCount = 0;
datetime       g_lastGainzEntryBarTime = 0;     // one entry attempt per H1 bar
datetime       g_gainzNextEntryAllowed = 0;     // cooldown after a Gainz exit

//--- Fill mode
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_FOK;

//--- Broker GMT offset (auto-detected from TimeTradeServer vs TimeGMT)
int            g_brokerGMTOffset = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Symbol check
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
   {
      Print("WARNING: ScalpXAU is designed for XAUUSD. Current symbol: ", _Symbol);
   }

   //--- Initialize trade
   m_trade.SetExpertMagicNumber(MagicNumber);
   m_trade.SetDeviationInPoints(MaxSlippagePts);
   m_trade.SetAsyncMode(false);

   //--- Detect fill mode WITHOUT placing a real order (fix: no FILL_TEST trade)
   g_fillMode = ORDER_FILLING_FOK;
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(filling & SYMBOL_FILLING_FOK)      g_fillMode = ORDER_FILLING_FOK;
   else if(filling & SYMBOL_FILLING_IOC) g_fillMode = ORDER_FILLING_IOC;
   else                                  g_fillMode = ORDER_FILLING_RETURN;
   m_trade.SetTypeFilling(g_fillMode);
   Print("Fill mode: ", EnumToString(g_fillMode));

   //--- Initialize indicators
   hRSI = iRSI(_Symbol, EntryTF, RSI_Period, PRICE_CLOSE);
   if(hRSI == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create RSI handle");
      return INIT_FAILED;
   }

   //--- Trend-leg MA handles (M15)
   hMAFast = iMA(_Symbol, EntryTF, Trend_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, EntryTF, Trend_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
   if(hMAFast == INVALID_HANDLE || hMASlow == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create trend MA handles");
      return INIT_FAILED;
   }
   Print("Trend leg: ", EnableTrend ? "ON" : "OFF",
         " MA", Trend_MA_Fast, "/", Trend_MA_Slow,
         " gate sep>=", Trend_MinSep_ATR, "xATR", Trend_SlopeFilter ? " +slope" : "",
         " | pullback<=", Trend_Pullback_ATR,
         " breakout>=", Trend_Breakout_ATR, " trail ", Trend_TrailStart_ATR, "/", Trend_TrailStep_ATR, "xATR");

   //--- Gainz-Swing mode init
   if(EnableGainzSwing)
   {
      hGainzEMA = iMA(_Symbol, PERIOD_H1, Gainz_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
      if(hGainzEMA == INVALID_HANDLE)
      {
         Print("ERROR: Failed to create Gainz EMA handle");
         return INIT_FAILED;
      }
      Print("Gainz-Swing: ON | TP=", Gainz_TP_Pips, "p SL=", Gainz_SL_Pips,
            "p | hold<=", Gainz_MaxHoldHours, "h | no-overnight=", Gainz_NoOvernight ? "ON" : "OFF",
            " (cutoff ", Gainz_CutoffHour, ":00 GMT) | window ", Gainz_StartH, "-", Gainz_EndH,
            " GMT | risk ", Gainz_RiskPct, "% | EMA", Gainz_EMA_Period);
   }

   //--- Initialize stats
   g_stats.startingBalance = m_account.Balance();
   g_stats.tradeCount = 0;
   g_stats.sessionTradeCount = 0;
   g_stats.lastSession = SESS_NONE;
   g_stats.tradingStopped = false;
   g_stats.sessionActive = false;
   g_stats.lastResetTime = 0;
   g_stats.sessionStartEquity = m_account.Equity();
   g_stats.sessTradingStopped = false;

   //--- Broker GMT offset: auto-detect unless user set a manual value
   g_brokerGMTOffset = BrokerGMTOffset;
   if(g_brokerGMTOffset == -99)
   {
      g_brokerGMTOffset = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(g_brokerGMTOffset < -14) g_brokerGMTOffset = -14;
      if(g_brokerGMTOffset > 14)  g_brokerGMTOffset = 14;
      Print("Broker GMT offset: AUTO-DETECTED = +", g_brokerGMTOffset,
            " (server=", TimeToString(TimeTradeServer()), " GMT=", TimeToString(TimeGMT()), ")");
   }
   else
   {
      Print("Broker GMT offset: MANUAL = ", g_brokerGMTOffset);
   }

   //--- Initial swing detection
   UpdateSwingPoints();

   Print("ScalpXAU initialized on ", _Symbol, " ", EnumToString(EntryTF));
   Print("Magic: ", MagicNumber, " | Risk: ", RiskPerTradePct, "% per trade, max ", MaxDailyRiskPct, "% daily");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hRSI);
   if(hMAFast != INVALID_HANDLE) IndicatorRelease(hMAFast);
   if(hMASlow != INVALID_HANDLE) IndicatorRelease(hMASlow);
   if(hGainzEMA != INVALID_HANDLE) IndicatorRelease(hGainzEMA);
   Comment("");
   Print("ScalpXAU deinitialized (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Daily reset at midnight
   ResetDaily();

   //--- Emergency stop check
   if(g_stats.tradingStopped)
   {
      CloseAllPositions("DD_LIMIT");
      UpdateComment();
      return;
   }

   //--- Update ATR
   g_atrValue = CalcATR(14, EntryTF);

   //--- Tick counter for heartbeat
   g_tickCount++;

   //--- Update swing points on new bar
   if(IsNewBar())
   {
      SessionType prevSession = GetCurrentSession();
      UpdateSwingPoints();
      DetectSessionLevels();

      //--- Log session info on every new bar (always visible)
      Print("NEWBAR | Sess=", GetSessionName(GetCurrentSession()),
            " GMT=", GetGMTHour(), ":", StringFormat("%02d", GetGMTMin()),
            " ATR=", DoubleToString(g_atrValue, 1),
            " Range=", (g_asianRangeReady ? "Y" : "N"),
            " FVG=", g_fvgCount,
            " Liq=", g_liqCount,
            " Swings=", ArraySize(g_swingHighIdx), "H ", ArraySize(g_swingLowIdx), "L");
   }

   //--- Heartbeat every 100 ticks
   if(g_tickCount >= 100)
   {
      g_tickCount = 0;
      Print("HB | Bal=$", DoubleToString(m_account.Balance(), 2),
            " Eq=$", DoubleToString(m_account.Equity(), 2),
            " Pos=", CountOpenPositions(),
            " Trades=", g_stats.tradeCount,
            " Sess=", GetSessionName(g_currentSession),
            " ATR=", DoubleToString(g_atrValue, 1));
   }

   //--- Manage open positions
   ManagePositions();
   if(EnableGainzSwing) ManageGainzPositions();

   //--- Check max concurrent positions (fix: was MaxTradesPerSess=15)
   if(CountOpenPositions() >= MaxPositions)
   {
      UpdateComment();
      return;
   }

   //--- Check for entry signals
   CheckEntry();

   //--- Trend leg: evaluated on every tick (forming M15 bar develops over the
   //--- bar, so a breakout/pullback can trigger mid-bar). Self-dedups to one
   //--- fill per bar via g_trendEntryBarTime.
   if(EnableTrend) CheckTrendEntry();

   //--- Gainz-Swing leg: one attempt per closed H1 bar.
   if(EnableGainzSwing) CheckGainzEntry();

   //--- Update chart
   UpdateComment();
}

//+------------------------------------------------------------------+
//| Check for entry signals per session                              |
//+------------------------------------------------------------------+
void CheckEntry()
{
   //--- One entry attempt per bar. Without this, a signal that stays true
   //--- for several ticks re-fires every tick: the NY-open flip-flop loop
   //--- and the 100+/hr market-close retry storm seen live on 8/6.
   datetime entryBar = iTime(_Symbol, EntryTF, 0);
   if(entryBar == g_lastEntryBarTime) return;
   g_lastEntryBarTime = entryBar;

   //--- Determine current session
   g_currentSession = GetCurrentSession();
   if(g_currentSession == SESS_NONE) return;

   //--- Reset session trade counter on session change
   if(g_stats.lastSession != g_currentSession)
   {
      g_stats.sessionTradeCount = 0;
      g_stats.sessionStartEquity = m_account.Equity();
      g_stats.sessTradingStopped = false;
      g_stats.lastSession = g_currentSession;
      Print("SESS START | ", GetSessionName(g_currentSession),
            " Eq=$", DoubleToString(g_stats.sessionStartEquity, 2));
   }

   //--- Check session drawdown limit
   if(!g_stats.sessTradingStopped && g_stats.sessionStartEquity > 0 && g_currentSession != SESS_NONE)
   {
      double ddPct = (g_stats.sessionStartEquity - m_account.Equity()) / g_stats.sessionStartEquity * 100.0;
      if(ddPct >= MaxSessDDPct)
      {
         g_stats.sessTradingStopped = true;
         Print("*** SESSION DD LIMIT REACHED: ", DoubleToString(ddPct, 2),
               "% at ", GetSessionName(g_currentSession), " ***");
      }
   }
   if(g_stats.sessTradingStopped) return;

   //--- Check session trade limit
   if(g_stats.sessionTradeCount >= MaxTradesPerSess) return;

   switch(g_currentSession)
   {
      case SESS_ASIAN:
         if(EnableAsian) AsianRangeScalp();
         break;
      case SESS_LONDON:
         if(EnableLondon) LondonBreakoutRetest();
         break;
      case SESS_NY:
         if(EnableNY) NYLiquiditySweep();
         break;
   }
}

//+------------------------------------------------------------------+
//| TREND LEG: MA50/200 regime gate + pullback/breakout entries      |
//| Buys strength / sells weakness (no RSI cap). Evaluated on every  |
//| tick so a breakout mid-bar is caught; dedups to one fill per M15 |
//| bar via g_trendEntryBarTime. Shares session guards & lot sizing. |
//+------------------------------------------------------------------+
bool CheckTrendEntry()
{
   if(!EnableTrend) return false;

   //--- Session + guard gates (shared with session strategies)
   SessionType sess = GetCurrentSession();
   if(sess == SESS_NONE) return false;
   if(g_stats.sessTradingStopped) return false;
   if(g_stats.sessionTradeCount >= MaxTradesPerSess) return false;
   if(CountOpenPositions() >= MaxPositions) return false;

   //--- One fill per M15 bar (set AFTER open, so the forming bar is evaluated every tick)
   datetime barTime = iTime(_Symbol, EntryTF, 0);
   if(barTime == g_trendEntryBarTime) return false;

   //--- Trend regime (M15 MAs)
   double maFast[], maSlow[];
   ArraySetAsSeries(maFast, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(hMAFast, 0, 0, 3, maFast) < 3) return false;
   if(CopyBuffer(hMASlow, 0, 0, 3, maSlow) < 3) return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 3, rates) < 3) return false;

   double atr = g_atrValue;
   if(atr <= 0) return false;

   double sepATR = (maFast[0] - maSlow[0]) / atr;
   //--- Trend-quality gate: BOTH MAs must slope with the trend (kills chop whipsaws)
   bool fastRising  = (maFast[1] > maFast[2]);
   bool fastFalling = (maFast[1] < maFast[2]);
   bool slowRising  = (maSlow[1] > maSlow[2]);
   bool slowFalling = (maSlow[1] < maSlow[2]);
   bool trendUp   = (rates[0].close > maFast[0] && maFast[0] > maSlow[0] && sepATR >=  Trend_MinSep_ATR
                     && (!Trend_SlopeFilter || (fastRising && slowRising)));
   bool trendDown = (rates[0].close < maFast[0] && maFast[0] < maSlow[0] && sepATR <= -Trend_MinSep_ATR
                     && (!Trend_SlopeFilter || (fastFalling && slowFalling)));

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double maxTrendSL = 2.5 * atr;

   //--- PULLBACK: prior M15 bar dipped to the fast-MA zone, current bar turns back
   bool pullbackUp = trendUp
      && rates[1].close < rates[1].open
      && rates[1].low  <= maFast[1] + Trend_Pullback_ATR * atr
      && rates[0].close > rates[0].open
      && rates[0].high  > rates[1].high;

   bool pullbackDown = trendDown
      && rates[1].close > rates[1].open
      && rates[1].high  >= maFast[1] - Trend_Pullback_ATR * atr
      && rates[0].close < rates[0].open
      && rates[0].low   < rates[1].low;

   //--- BREAKOUT: current bar extends beyond prior bar in the trend direction
   bool breakoutUp = trendUp
      && rates[0].close > rates[0].open
      && rates[0].high  > rates[1].high + Trend_Breakout_ATR * atr;

   bool breakoutDown = trendDown
      && rates[0].close < rates[0].open
      && rates[0].low   < rates[1].low - Trend_Breakout_ATR * atr;

   //--- Trend BUY (pullback preferred when both qualify on the same bar)
   if(pullbackUp || breakoutUp)
   {
      double sl = (pullbackUp
                   ? MathMin(rates[1].low, rates[0].low)
                   : rates[0].low) - Trend_SL_Buffer_ATR * atr;
      double slDist = ask - sl;
      if(slDist >= Min_SL_ATR * atr && slDist <= maxTrendSL)
      {
         double lot = CalcLotSizeRisk(slDist, Trend_RiskPct);
         if(lot > 0 && VerifyTrade(ORDER_TYPE_BUY, ask, sl, 0.0, lot))
         {
            if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, 0.0, CommentPrefix + "_T_BUY"))
            {
               g_stats.tradeCount++;
               g_stats.sessionTradeCount++;
               g_trendEntryBarTime = barTime;
               Print("TREND BUY (", pullbackUp ? "PULLBACK" : "BREAKOUT",
                     "): close=", DoubleToString(rates[0].close, digits),
                     " SL=", DoubleToString(slDist / atr, 2), "xATR");
               return true;
            }
         }
         else if(DebugMode) Print("TREND BUY REJECTED: SL ", DoubleToString(slDist / atr, 2), "xATR");
      }
   }

   //--- Trend SELL
   if(pullbackDown || breakoutDown)
   {
      double sl = (pullbackDown
                   ? MathMax(rates[1].high, rates[0].high)
                   : rates[0].high) + Trend_SL_Buffer_ATR * atr;
      double slDist = sl - bid;
      if(slDist >= Min_SL_ATR * atr && slDist <= maxTrendSL)
      {
         double lot = CalcLotSizeRisk(slDist, Trend_RiskPct);
         if(lot > 0 && VerifyTrade(ORDER_TYPE_SELL, bid, sl, 0.0, lot))
         {
            if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, 0.0, CommentPrefix + "_T_SELL"))
            {
               g_stats.tradeCount++;
               g_stats.sessionTradeCount++;
               g_trendEntryBarTime = barTime;
               Print("TREND SELL (", pullbackDown ? "PULLBACK" : "BREAKOUT",
                     "): close=", DoubleToString(rates[0].close, digits),
                     " SL=", DoubleToString(slDist / atr, 2), "xATR");
               return true;
            }
         }
         else if(DebugMode) Print("TREND SELL REJECTED: SL ", DoubleToString(slDist / atr, 2), "xATR");
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| ASIAN SESSION: Range-bound scalping                              |
//| S/R zones on M15, RSI OB/OS, pin bar/engulfing entry            |
//| TP 10-15 pips, SL outside range                                 |
//+------------------------------------------------------------------+
void AsianRangeScalp()
{
   //--- Need swings for S/R zones
   if(!g_swingReady) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 10, rates) < 5) return;

   //--- RSI buffer
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRSI, 0, 0, 5, rsi) < 3) return;

   //--- Price data for last closed bar
   int bar = 1; // last closed bar
   double open  = rates[bar].open;
   double high  = rates[bar].high;
   double low   = rates[bar].low;
   double close = rates[bar].close;
   double body  = MathAbs(close - open);
   double totalRange = high - low;
   double lowerWick = MathMin(close, open) - low;
   double upperWick = high - MathMax(close, open);
   bool isBull = close > open;
   bool isBear = close < open;

   //--- Detect pin bar
   bool isPinBar = false;
   double wickThreshold = body * 0.5;
   if(isBull && lowerWick >= wickThreshold && upperWick <= body * 0.3)
      isPinBar = true;  // bullish pin bar (long lower wick)
   if(isBear && upperWick >= wickThreshold && lowerWick <= body * 0.3)
      isPinBar = true;  // bearish pin bar (long upper wick)

   //--- Detect engulfing
   bool isEngulfBull = false;
   bool isEngulfBear = false;
   if(bar + 1 < ArraySize(rates))
   {
      double prevBody = MathAbs(rates[bar+1].close - rates[bar+1].open);
      bool prevBear = rates[bar+1].close < rates[bar+1].open;
      bool prevBull = rates[bar+1].close > rates[bar+1].open;
      // Bullish engulfing: prev bearish, current bullish, body covers prev body
      if(isBull && prevBear && body > prevBody * 1.1 && close > rates[bar+1].open && open < rates[bar+1].close)
         isEngulfBull = true;
      // Bearish engulfing: prev bullish, current bearish, body covers prev body
      if(isBear && prevBull && body > prevBody * 1.1 && close < rates[bar+1].open && open > rates[bar+1].close)
         isEngulfBear = true;
   }

   bool rejectionCandle = isPinBar || isEngulfBull || isEngulfBear;

   //--- Scan for S/R zones from swing points
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   //--- Check each swing high as resistance zone
   for(int i = 0; i < ArraySize(g_swingHighIdx) && i < 10; i++)
   {
      double zoneLevel = g_swingHighVal[i];
      double zoneRange = atr * 0.6; // zone thickness

      //--- Price near resistance zone (from below)
      if(MathAbs(high - zoneLevel) <= zoneRange && isBear && rejectionCandle)
      {
         //--- RSI overbought confirmation
         if(rsi[1] >= RSI_OB)
         {
            //--- SELL entry
            double sl = zoneLevel + Asian_SL_BufferATR * atr;
            double slDist = MathAbs(sl - close);
            if(slDist <= 0) continue;
            //--- Floor: never let a stop sit inside normal noise (live: sub-ATR stops clipped every tick)
            if(slDist < Min_SL_ATR * atr) { slDist = Min_SL_ATR * atr; sl = close + slDist; }
            //--- Fix: TP at least 1.5:1 with SL (was fixed 12 pips — often smaller than SL)
            double tp = close - MathMax(Asian_TP_Pips * 10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT), slDist * 1.5);

            double lot = CalcLotSizeRisk(slDist, RiskPerTradePct);
            if(lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) && VerifyTrade(ORDER_TYPE_SELL, bid, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, tp, CommentPrefix + "_ASIAN_SELL"))
               {
                  g_stats.tradeCount++;
                  g_stats.sessionTradeCount++;
                  if(DebugMode) Print("ASIAN SELL: zone=", zoneLevel, " RSI=", rsi[1]);
               }
            }
         }
      }
   }

   //--- Check each swing low as support zone
   for(int i = 0; i < ArraySize(g_swingLowIdx) && i < 10; i++)
   {
      double zoneLevel = g_swingLowVal[i];
      double zoneRange = atr * 0.6;

      //--- Price near support zone (from above)
      if(MathAbs(low - zoneLevel) <= zoneRange && isBull && rejectionCandle)
      {
         //--- RSI oversold confirmation
         if(rsi[1] <= RSI_OS)
         {
            //--- BUY entry
            double sl = zoneLevel - Asian_SL_BufferATR * atr;
            double slDist = MathAbs(close - sl);
            if(slDist <= 0) continue;
            //--- Floor: never let a stop sit inside normal noise (live: sub-ATR stops clipped every tick)
            if(slDist < Min_SL_ATR * atr) { slDist = Min_SL_ATR * atr; sl = close - slDist; }
            //--- Fix: TP at least 1.5:1 with SL (was fixed 12 pips — often smaller than SL)
            double tp = close + MathMax(Asian_TP_Pips * 10 * SymbolInfoDouble(_Symbol, SYMBOL_POINT), slDist * 1.5);

            double lot = CalcLotSizeRisk(slDist, RiskPerTradePct);
            if(lot >= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN) && VerifyTrade(ORDER_TYPE_BUY, ask, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, tp, CommentPrefix + "_ASIAN_BUY"))
               {
                  g_stats.tradeCount++;
                  g_stats.sessionTradeCount++;
                  if(DebugMode) Print("ASIAN BUY: zone=", zoneLevel, " RSI=", rsi[1]);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| LONDON SESSION: Breakout+Retest                                  |
//| Mark Asian range, breakout close, retest entry, FVG/OB confluence|
//| TP 2x SL, 1% risk                                               |
//+------------------------------------------------------------------+
void LondonBreakoutRetest()
{
   //--- Need Asian range
   if(!g_asianRangeReady || g_asianHigh <= 0 || g_asianLow <= 0) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 15, rates) < 10) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   //--- Check for breakouts
   int breakDir = 0; // 1=bull breakout, -1=bear breakout
   int breakBar = -1;

   for(int c = 1; c <= 8; c++)
   {
      if(c >= ArraySize(rates)) break;
      //--- Bull breakout: close above Asian high
      if(rates[c].close > g_asianHigh && rates[c].close > rates[c].open)
      {
         breakDir = 1;
         breakBar = c;
      }
      //--- Bear breakout: close below Asian low
      else if(rates[c].close < g_asianLow && rates[c].close < rates[c].open)
      {
         breakDir = -1;
         breakBar = c;
      }
      if(breakDir != 0) break;
   }

   //--- No breakout found
   if(breakDir == 0) return;

   //--- Look for retest after breakout
   bool retestHit = false;
   double entryPrice = 0;
   double retestSL = 0;
   double retestTP = 0;

   //--- FVG check
   bool fvgFound = false;
   DetectFVG();

   int retestBar = -1;
   for(int c = breakBar - 1; c >= 1 && c > breakBar - 5; c--)
   {
      if(c <= 0 || c >= ArraySize(rates)) continue;

      if(breakDir == 1) // Bull breakout: retest of Asian high as support
      {
         // Price pulls back to near Asian high
         if(rates[c].low <= g_asianHigh * 1.002 && rates[c].low >= g_asianHigh * 0.995)
         {
            // Rejection candle (bullish) at retest
            if(rates[c].close > rates[c].open && rates[c].close > g_asianHigh)
            {
               // Check FVG confluence if available
               bool fvgOk = true;
               for(int f = 0; f < g_fvgCount; f++)
               {
                  if(g_fvgList[f].bullish && g_fvgList[f].lower <= g_asianHigh * 1.005
                     && g_fvgList[f].upper >= g_asianHigh * 0.995)
                  {
                     fvgOk = true;
                     fvgFound = true;
                     break;
                  }
               }

               if(fvgOk)
               {
                  retestHit = true;
                  retestBar = c;
                  entryPrice = ask;
                  double slDist = atr * 0.5; // tighter stop for breakout
                  if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                  retestSL = g_asianHigh - slDist;
                  retestTP = entryPrice + slDist * London_RR;
                  break;
               }
            }
         }
      }
      else if(breakDir == -1) // Bear breakout: retest of Asian low as resistance
      {
         if(rates[c].high >= g_asianLow * 0.998 && rates[c].high <= g_asianLow * 1.005)
         {
            if(rates[c].close < rates[c].open && rates[c].close < g_asianLow)
            {
               bool fvgOk = true;
               for(int f = 0; f < g_fvgCount; f++)
               {
                  if(!g_fvgList[f].bullish && g_fvgList[f].lower <= g_asianLow * 1.005
                     && g_fvgList[f].upper >= g_asianLow * 0.995)
                  {
                     fvgOk = true;
                     fvgFound = true;
                     break;
                  }
               }

               if(fvgOk)
               {
                  retestHit = true;
                  retestBar = c;
                  entryPrice = bid;
                  double slDist = atr * 0.5;
                  if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
                  retestSL = g_asianLow + slDist;
                  retestTP = entryPrice - slDist * London_RR;
                  break;
               }
            }
         }
      }
   }

   //--- Execute trade on retest
   if(retestHit && entryPrice > 0 && retestSL > 0 && retestTP > 0)
   {
      double lot = CalcLotSizeRisk(MathAbs(entryPrice - retestSL), London_RiskPct);
      double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(lot < minVol) lot = minVol;

      int orderType = (breakDir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double price  = (orderType == ORDER_TYPE_BUY) ? ask : bid;

      if(VerifyTrade(orderType, price, retestSL, retestTP, lot))
      {
         if(OpenOrder(orderType, lot, price, retestSL, retestTP, CommentPrefix + "_LONDON_" + (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL")))
         {
            g_stats.tradeCount++;
            g_stats.sessionTradeCount++;
            if(DebugMode) Print("LONDON ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
                  " AsianRange: ", g_asianHigh, "/", g_asianLow,
                  " Retest@", retestBar, " FVG=", fvgFound);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| NY SESSION: Liquidity Sweep + Reversal                           |
//| Identify equal highs/lows, sweep with wick, BOS, retest entry   |
//+------------------------------------------------------------------+
void NYLiquiditySweep()
{
   //--- Need swing points
   if(!g_swingReady) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, SweepLookback + 5, rates) < SweepLookback) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   //--- STEP 1: Identify liquidity levels (equal highs/lows or clear session highs/lows)
   DetectLiquidityLevels(rates);

   //--- STEP 2: Check for sweep of a liquidity level
   int sweptLevel = -1;
   int sweepBar = -1;

   for(int i = 0; i < g_liqCount; i++)
   {
      if(g_liqLevels[i].swept) continue;

      //--- Check recent bars for sweep
      for(int c = 1; c <= 3; c++)
      {
         if(c >= ArraySize(rates)) break;

         if(g_liqLevels[i].isHigh)
         {
            // Price spiked above with wick (not close above)
            if(rates[c].high > g_liqLevels[i].price * 1.0005)
            {
               double wick = rates[c].high - MathMax(rates[c].close, rates[c].open);
               double body = MathAbs(rates[c].close - rates[c].open);
               // Strong wick = rejection (liquidity sweep)
               if(wick >= body * 0.5 && rates[c].close < rates[c].open)
               {
                  sweptLevel = i;
                  sweepBar = c;
                  g_liqLevels[i].swept = true;
                  break;
               }
            }
         }
         else
         {
            // Price spiked below with wick
            if(rates[c].low < g_liqLevels[i].price * 0.9995)
            {
               double wick = MathMin(rates[c].close, rates[c].open) - rates[c].low;
               double body = MathAbs(rates[c].close - rates[c].open);
               if(wick >= body * 0.5 && rates[c].close > rates[c].open)
               {
                  sweptLevel = i;
                  sweepBar = c;
                  g_liqLevels[i].swept = true;
                  break;
               }
            }
         }
      }
      if(sweptLevel >= 0) break;
   }

   if(sweptLevel < 0) return;

   //--- STEP 3: Confirm BOS (Break of Structure)
   // For sell reversal: price broke a swing low after sweeping liquidity
   // For buy reversal: price broke a swing high after sweeping liquidity
   bool bosConfirmed = false;

   if(g_liqLevels[sweptLevel].isHigh)
   {
      // Swept high → looking for sell. BOS = broke a recent swing low
      for(int c = sweepBar + 1; c <= sweepBar + 3 && c < ArraySize(rates); c++)
      {
         if(c < 1) continue;
         double recentLow = rates[c].low;
         // Check if price broke below a recent swing low
         for(int s = 0; s < ArraySize(g_swingLowIdx); s++)
         {
            if(g_swingLowVal[s] > recentLow && g_swingLowVal[s] < g_liqLevels[sweptLevel].price * 0.999)
            {
               bosConfirmed = true;
               break;
            }
         }
         if(bosConfirmed) break;
      }
   }
   else
   {
      // Swept low → looking for buy. BOS = broke a recent swing high
      for(int c = sweepBar + 1; c <= sweepBar + 3 && c < ArraySize(rates); c++)
      {
         if(c < 1) continue;
         double recentHigh = rates[c].high;
         for(int s = 0; s < ArraySize(g_swingHighIdx); s++)
         {
            if(g_swingHighVal[s] < recentHigh && g_swingHighVal[s] > g_liqLevels[sweptLevel].price * 1.001)
            {
               bosConfirmed = true;
               break;
            }
         }
         if(bosConfirmed) break;
      }
   }

   if(!bosConfirmed) return;

   //--- STEP 4: Enter on retest or confirmation candle
   // Check last closed bar for retest of the swept level
   int bar = 1; // last closed bar
   double entryPrice = 0;
   double sl = 0;
   double tp = 0;
   int orderType = -1;

   if(g_liqLevels[sweptLevel].isHigh)
   {
      // Sell: price swept high, BOS down, now retesting the swept area
      if(rates[bar].high >= g_liqLevels[sweptLevel].price * 0.998
         && rates[bar].close < rates[bar].open)
      {
         orderType = ORDER_TYPE_SELL;
         entryPrice = bid;
         double slDist = atr * 0.6;
         if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
         sl = g_liqLevels[sweptLevel].price + slDist;
         tp = entryPrice - slDist * NY_RR;

         // Prefer FVG or previous structure as TP
         for(int f = 0; f < g_fvgCount; f++)
         {
            if(!g_fvgList[f].bullish && g_fvgList[f].lower < entryPrice
               && g_fvgList[f].lower > entryPrice - slDist * NY_RR * 0.5)
            {
               tp = g_fvgList[f].lower;
               if(DebugMode) Print("NY TP set to FVG fill: ", tp);
               break;
            }
         }
      }
   }
   else
   {
      // Buy: price swept low, BOS up, now retesting the swept area
      if(rates[bar].low <= g_liqLevels[sweptLevel].price * 1.002
         && rates[bar].close > rates[bar].open)
      {
         orderType = ORDER_TYPE_BUY;
         entryPrice = ask;
         double slDist = atr * 0.6;
         if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;
         sl = g_liqLevels[sweptLevel].price - slDist;
         tp = entryPrice + slDist * NY_RR;

         for(int f = 0; f < g_fvgCount; f++)
         {
            if(g_fvgList[f].bullish && g_fvgList[f].upper > entryPrice
               && g_fvgList[f].upper < entryPrice + slDist * NY_RR * 0.5)
            {
               tp = g_fvgList[f].upper;
               if(DebugMode) Print("NY TP set to FVG fill: ", tp);
               break;
            }
         }
      }
   }

   if(orderType < 0 || entryPrice <= 0 || sl <= 0 || tp <= 0) return;

   double lot = CalcLotSizeRisk(MathAbs(entryPrice - sl), NY_RiskPct);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < minVol) lot = minVol;

   double price = (orderType == ORDER_TYPE_BUY) ? ask : bid;

   if(VerifyTrade(orderType, price, sl, tp, lot))
   {
      if(OpenOrder(orderType, lot, price, sl, tp, CommentPrefix + "_NY_" + (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL")))
      {
         g_stats.tradeCount++;
         g_stats.sessionTradeCount++;
         if(DebugMode) Print("NY ", (orderType == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               " Swept: ", g_liqLevels[sweptLevel].isHigh ? "High" : "Low",
               "@", g_liqLevels[sweptLevel].price,
               " RR=", NY_RR);
      }
   }
}

//+------------------------------------------------------------------+
//| Detect Fair Value Gap (FVG) from recent candles                  |
//+------------------------------------------------------------------+
void DetectFVG()
{
   g_fvgCount = 0;
   ArrayResize(g_fvgList, 10);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 30, rates) < 10) return;

   for(int i = 1; i < 25; i++)
   {
      if(i + 2 >= ArraySize(rates)) break;

      // Bullish FVG: candle i+1 low > candle i high (gap up)
      if(rates[i+1].low > rates[i].high)
      {
         g_fvgList[g_fvgCount].bullish = true;
         g_fvgList[g_fvgCount].upper = rates[i+1].low;
         g_fvgList[g_fvgCount].lower = rates[i].high;
         g_fvgList[g_fvgCount].time = rates[i+1].time;
         g_fvgCount++;
      }
      // Bearish FVG: candle i+1 high < candle i low (gap down)
      else if(rates[i+1].high < rates[i].low)
      {
         g_fvgList[g_fvgCount].bullish = false;
         g_fvgList[g_fvgCount].upper = rates[i].low;
         g_fvgList[g_fvgCount].lower = rates[i+1].high;
         g_fvgList[g_fvgCount].time = rates[i+1].time;
         g_fvgCount++;
      }

      if(g_fvgCount >= ArraySize(g_fvgList)) break;
   }
}

//+------------------------------------------------------------------+
//| Detect liquidity levels (equal highs/lows) for NY strategy       |
//+------------------------------------------------------------------+
void DetectLiquidityLevels(MqlRates &rates[])
{
   g_liqCount = 0;
   ArrayResize(g_liqLevels, 20);

   int lookback = MathMin(SweepLookback, ArraySize(rates) - 3);

   //--- Find equal highs (within 0.5 ATR)
   for(int i = 1; i < lookback - 5; i++)
   {
      for(int j = i + 3; j < lookback - 2; j++)
      {
         double diff = MathAbs(rates[i].high - rates[j].high);
         if(diff <= g_atrValue * 0.2 && diff > 0) // nearly equal highs
         {
            // Check if this is a local high (bar before and after are lower)
            if(i >= 2 && rates[i].high > rates[i-1].high
               && rates[i].high > rates[i+1].high)
            {
               bool dup = false;
               for(int d = 0; d < g_liqCount; d++)
               {
                  if(g_liqLevels[d].isHigh && MathAbs(g_liqLevels[d].price - rates[i].high) < g_atrValue * 0.1)
                  { dup = true; break; }
               }
               if(!dup)
               {
                  g_liqLevels[g_liqCount].price = MathMax(rates[i].high, rates[j].high);
                  g_liqLevels[g_liqCount].time = rates[i].time;
                  g_liqLevels[g_liqCount].isHigh = true;
                  g_liqLevels[g_liqCount].swept = false;
                  g_liqCount++;
               }
               break;
            }
         }
      }
      if(g_liqCount >= ArraySize(g_liqLevels)) break;
   }

   //--- Find equal lows (within 0.5 ATR)
   for(int i = 1; i < lookback - 5; i++)
   {
      for(int j = i + 3; j < lookback - 2; j++)
      {
         double diff = MathAbs(rates[i].low - rates[j].low);
         if(diff <= g_atrValue * 0.2 && diff > 0)
         {
            if(i >= 2 && rates[i].low < rates[i-1].low
               && rates[i].low < rates[i+1].low)
            {
               bool dup = false;
               for(int d = 0; d < g_liqCount; d++)
               {
                  if(!g_liqLevels[d].isHigh && MathAbs(g_liqLevels[d].price - rates[i].low) < g_atrValue * 0.1)
                  { dup = true; break; }
               }
               if(!dup)
               {
                  g_liqLevels[g_liqCount].price = MathMin(rates[i].low, rates[j].low);
                  g_liqLevels[g_liqCount].time = rates[i].time;
                  g_liqLevels[g_liqCount].isHigh = false;
                  g_liqLevels[g_liqCount].swept = false;
                  g_liqCount++;
               }
               break;
            }
         }
      }
      if(g_liqCount >= ArraySize(g_liqLevels)) break;
   }
}

//+------------------------------------------------------------------+
//| Track Asian session range for London breakout                    |
//+------------------------------------------------------------------+
void TrackAsianRange()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 100, rates) < 20) return;

   //--- Find bars within Asian session time (12:30-3:30 GMT)
   g_asianHigh = 0;
   g_asianLow  = 1e9;
   g_asianRangeReady = false;
   int barsInSession = 0;

   for(int i = 0; i < ArraySize(rates); i++)
   {
      datetime t = rates[i].time;
      MqlDateTime dt;
      TimeToStruct(t, dt);

      //--- Convert bar time to GMT hour
      int hourGMT   = dt.hour - g_brokerGMTOffset;
      if(hourGMT < 0) hourGMT += 24;
      int minuteGMT = dt.min;

      //--- Asian session: 0:30 - 3:30 GMT
      bool inAsian = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         inAsian = true;

      if(inAsian)
      {
         if(rates[i].high > g_asianHigh) g_asianHigh = rates[i].high;
         if(rates[i].low < g_asianLow)   g_asianLow  = rates[i].low;
         barsInSession++;
      }
      else if(barsInSession > 0)
      {
         //--- Session ended — stop scanning
         break;
      }
   }

   if(g_asianHigh > 0 && g_asianLow < 1e8 && barsInSession >= 3)
   {
      g_asianRangeReady = true;
      if(DebugMode) Print("Asian range: H=", g_asianHigh, " L=", g_asianLow, " bars=", barsInSession);
   }
}

//+------------------------------------------------------------------+
//| Detect session-specific levels                                   |
//+------------------------------------------------------------------+
void DetectSessionLevels()
{
   SessionType sess = GetCurrentSession();

   //--- Track Asian range if we're in or near Asian session
   if(sess == SESS_ASIAN || sess == SESS_LONDON)
   {
      // Check if we just entered a new Asian session window
      int hourGMT   = GetGMTHour();
      int minuteGMT = GetGMTMin();

      bool asianOngoing = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         asianOngoing = true;

      // Track once at end of Asian session
      if(!asianOngoing && g_asianSessionStart > 0)
      {
         TrackAsianRange();
         g_asianSessionStart = 0;
      }

      if(asianOngoing && g_asianSessionStart == 0)
      {
         MqlDateTime asianDt; TimeTradeServer(asianDt); g_asianSessionStart = StructToTime(asianDt);
         g_asianHigh = 0;
         g_asianLow = 1e9;
         g_asianRangeReady = false;
      }
   }

   //--- Detect FVGs for NY session
   if(sess == SESS_NY || sess == SESS_LONDON)
   {
      DetectFVG();
   }

   //--- Detect liquidity levels for NY session
   if(sess == SESS_NY)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(_Symbol, EntryTF, 0, SweepLookback + 5, rates) >= SweepLookback)
         DetectLiquidityLevels(rates);
   }
}

//+------------------------------------------------------------------+
//| Get current GMT hour from trade server time                      |
//+------------------------------------------------------------------+
int GetGMTHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int gmtHour = dt.hour - g_brokerGMTOffset;
   if(gmtHour < 0) gmtHour += 24;
   return gmtHour;
}

int GetGMTMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

//+------------------------------------------------------------------+
//| Get current session based on GMT time                            |
//+------------------------------------------------------------------+
SessionType GetCurrentSession()
{
   int hourGMT   = GetGMTHour();
   int minuteGMT = GetGMTMin();

   int timeMinutes = hourGMT * 60 + minuteGMT;

   int asianStart = Asian_StartH * 60 + Asian_StartM;
   int asianEnd   = Asian_EndH   * 60 + Asian_EndM;
   int londonStart = London_StartH * 60 + London_StartM;
   int londonEnd   = London_EndH   * 60 + London_EndM;
   int nyStart    = NY_StartH    * 60 + NY_StartM;
   int nyEnd      = NY_EndH      * 60 + NY_EndM;

   //--- Handle overnight sessions
   if(asianEnd < asianStart) asianEnd += 1440;
   if(nyEnd < nyStart) nyEnd += 1440;

   int t = timeMinutes;
   if(asianEnd < asianStart && t < asianStart) t += 1440;
   if(t >= asianStart && t <= asianEnd) return SESS_ASIAN;

   t = timeMinutes;
   if(londonEnd < londonStart && t < londonStart) t += 1440;
   if(t >= londonStart && t <= londonEnd) return SESS_LONDON;

   t = timeMinutes;
   if(nyEnd < nyStart && t < nyStart) t += 1440;
   if(t >= nyStart && t <= nyEnd) return SESS_NY;

   return SESS_NONE;
}

//+------------------------------------------------------------------+
//| Get session name string                                          |
//+------------------------------------------------------------------+
string GetSessionName(SessionType s)
{
   switch(s)
   {
      case SESS_ASIAN:  return "ASIAN";
      case SESS_LONDON: return "LONDON";
      case SESS_NY:     return "NY";
      default:          return "OUTSIDE";
   }
}

//+------------------------------------------------------------------+
//| Update swing points from price action                            |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, SwingLookback, rates) < 50) return;

   ArrayResize(g_swingHighIdx, 0);
   ArrayResize(g_swingHighVal, 0);
   ArrayResize(g_swingLowIdx, 0);
   ArrayResize(g_swingLowVal, 0);

   int lookback = MathMin(SwingLookback, ArraySize(rates) - 2);

   for(int i = 2; i < lookback; i++)
   {
      //--- Swing high: bar i is higher than i-1 and i+1
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high)
      {
         int idx = ArraySize(g_swingHighIdx);
         ArrayResize(g_swingHighIdx, idx + 1);
         ArrayResize(g_swingHighVal, idx + 1);
         g_swingHighIdx[idx] = i;
         g_swingHighVal[idx] = rates[i].high;
      }

      //--- Swing low: bar i is lower than i-1 and i+1
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low)
      {
         int idx = ArraySize(g_swingLowIdx);
         ArrayResize(g_swingLowIdx, idx + 1);
         ArrayResize(g_swingLowVal, idx + 1);
         g_swingLowIdx[idx] = i;
         g_swingLowVal[idx] = rates[i].low;
      }
   }

   g_swingReady = (ArraySize(g_swingHighIdx) > 0 && ArraySize(g_swingLowIdx) > 0);
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                     |
//+------------------------------------------------------------------+
double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 0, period + 1, rates) < period + 1) return 0;

   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      if(i >= ArraySize(rates)) break;
      double tr = MathMax(rates[i].high - rates[i].low,
                  MathMax(MathAbs(rates[i].high - rates[i-1].close),
                           MathAbs(rates[i].low - rates[i-1].close)));
      sum += tr;
   }
   return sum / period;
}

//+------------------------------------------------------------------+
//| Is new bar?                                                      |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 1, rates) < 1) return false;

   if(rates[0].time != g_lastBarTime)
   {
      g_lastBarTime = rates[0].time;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Daily reset                                                      |
//+------------------------------------------------------------------+
void ResetDaily()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   datetime today = dt.year * 10000 + dt.mon * 100 + dt.day;

   if(g_stats.lastResetTime != today)
   {
      g_stats.lastResetTime = today;
      g_stats.startingBalance = m_account.Balance();
      g_stats.tradeCount = 0;
      g_stats.sessionTradeCount = 0;
      g_stats.tradingStopped = false;
      g_stats.lastSession = SESS_NONE;
      g_asianSessionStart = 0;
      g_asianRangeReady = false;
      Print("--- Daily reset. Balance: ", g_stats.startingBalance, " ---");
   }

   //--- Check daily loss limit
   if(!g_stats.tradingStopped && g_stats.startingBalance > 0)
   {
      double ddPct = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
      if(ddPct >= MaxDailyRiskPct)
      {
         g_stats.tradingStopped = true;
         Print("*** MAX DAILY LOSS REACHED: ", DoubleToString(ddPct, 2), "% ***");
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (partial TP, trailing, break-even)         |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(!UseBreakEven && !UseTrailing) return;
   if(g_atrValue <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      //--- Gainz-Swing positions keep their hard SL/TP: managed by
      //--- ManageGainzPositions() (max-hold + no-overnight), not the scalp
      //--- break-even/trailing.
      if(StringFind(PositionGetString(POSITION_COMMENT), "_G_") >= 0) continue;

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      long type    = PositionGetInteger(POSITION_TYPE);
      double curPrice = (type == POSITION_TYPE_BUY) ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- Trend-leg trades (_T_ tag) ride wider: BE later + wide trail
      bool isTrend = (StringFind(PositionGetString(POSITION_COMMENT), "_T_") >= 0);

      //--- Break-even
      if(UseBreakEven)
      {
         double beDist = isTrend ? Trend_TrailStart_ATR * g_atrValue
                                 : BE_ATR_Mult * g_atrValue;
         if(type == POSITION_TYPE_BUY)
         {
            if(curPrice >= entry + beDist && sl < entry)
               ModifySL(ticket, NormalizeDouble(entry + point * 5, digits));
         }
         else
         {
            if(curPrice <= entry - beDist && (sl > entry || sl == 0))
               ModifySL(ticket, NormalizeDouble(entry - point * 5, digits));
         }
      }

      //--- Trailing stop
      if(UseTrailing)
      {
         double trailStart = isTrend ? Trend_TrailStart_ATR * g_atrValue
                                     : TrailStart_ATR * g_atrValue;
         double trailStep  = isTrend ? Trend_TrailStep_ATR * g_atrValue
                                     : TrailStep_ATR * g_atrValue;

         if(type == POSITION_TYPE_BUY)
         {
            double profitDist = curPrice - entry;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice - trailStep, digits);
               if(newSL > sl + point)
                  ModifySL(ticket, newSL);
            }
         }
         else
         {
            double profitDist = entry - curPrice;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice + trailStep, digits);
               if(newSL < sl - point || sl == 0)
                  ModifySL(ticket, newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this symbol/magic                       |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Close all positions for this symbol/magic                        |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      int orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double price = (type == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = _Symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.type = (ENUM_ORDER_TYPE)orderType;
      req.price = price;
      req.deviation = MaxSlippagePts;
      req.comment = reason;
      req.magic = MagicNumber;
      req.type_filling = g_fillMode;
      if(!OrderSend(req, res))
      {
         if(DebugMode) Print("CloseAll: OrderSend failed, err=", GetLastError());
      }
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk % and SL distance               |
//+------------------------------------------------------------------+
double CalcLotSizeRisk(double slDist, double riskPct)
{
   if(slDist <= 0) return 0;

   //--- Floor pathologically tiny SL distances (sweep entry at the level) so
   //--- risk-based sizing can't explode into 1000+ oz positions.
   if(g_atrValue > 0 && slDist < Min_SL_ATR * g_atrValue) slDist = Min_SL_ATR * g_atrValue;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return 0;

   double riskAmount = m_account.Balance() * riskPct / 100.0;
   double slTicks = slDist / tickSize;
   double lot = riskAmount / (slTicks * tickVal);
   lot = NormalizeDouble(lot, 2);

   //--- Round down to broker volume step (keeps lot on valid grid)
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep > 0) lot = MathFloor(lot / vstep + 1e-9) * vstep;

   //--- Notional cap: ~$30k exposure per $10k balance (~7 oz at current gold).
   //--- Stops margin blow-ups from oversized positions (e.g. the 2465-oz NoMoney order).
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > 0)
   {
      double volCap = (m_account.Balance() / 10000.0) * 30000.0 / price;
      if(volCap < maxVol) maxVol = volCap;
   }
   if(vstep > 0) maxVol = MathFloor(maxVol / vstep) * vstep;

   //--- Clamp
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return MathMax(minVol, MathMin(lot, maxVol));
}

//+------------------------------------------------------------------+
//| Verify trade before sending                                      |
//+------------------------------------------------------------------+
bool VerifyTrade(int type, double price, double sl, double tp, double lot)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   //--- Normalize prices
   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   //--- Basic validation
   if(lot <= 0) return false;
   if(type == ORDER_TYPE_BUY && price < bid * 0.99) return false;
   if(type == ORDER_TYPE_SELL && price > ask * 1.01) return false;

   //--- SL/TP must be on correct side (tp==0 = no take-profit, allowed for the trend leg)
   if(type == ORDER_TYPE_BUY) { if(sl >= price) return false; if(tp > 0 && tp <= price) return false; }
   if(type == ORDER_TYPE_SELL) { if(sl <= price) return false; if(tp > 0 && tp >= price) return false; }

   //--- SL/TP distance checks
   double slPips = MathAbs(price - sl);
   double tpPips = MathAbs(tp - price);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(slPips < minDist && slPips > 0) return false;
   if(tpPips < minDist && tpPips > 0) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Open a market order                                              |
//+------------------------------------------------------------------+
bool OpenOrder(int type, double volume, double price, double sl, double tp,
               string comment)
{
   //--- Normalize to symbol digits (prevents "Invalid request" errors)
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   if(!m_trade.PositionOpen(_Symbol, (ENUM_ORDER_TYPE)type, volume, price, sl, tp, comment))
   {
      int err = GetLastError();
      Print("ORDER FAILED: ", comment, " err=", err, " vol=", volume,
            " price=", price, " sl=", sl, " tp=", tp);
      return false;
   }
   Print("ORDER OK: ", comment, " vol=", volume, " price=", price,
         " sl=", sl, " tp=", tp);
   return true;
}

//+------------------------------------------------------------------+
//| Modify SL                                                        |
//+------------------------------------------------------------------+
void ModifySL(ulong ticket, double newSL)
{
   if(PositionSelectByTicket(ticket))
   {
      double currentSL = PositionGetDouble(POSITION_SL);
      if(MathAbs(newSL - currentSL) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2)
         return;

      double tp = PositionGetDouble(POSITION_TP);
      m_trade.PositionModify(ticket, newSL, tp);
   }
}

//+------------------------------------------------------------------+
//| GAINZ-SWING MODE                                                 |
//| Swing profile: TP +159p / SL -322p (pips = point, 0.01 for gold),|
//| breakout of the previous day's range with EMA trend bias,        |
//| session-gated (default London+NY 07-21 GMT), max 11h hold, hard  |
//| SL, no overnight. One position at a time. Port of ScalpXAU_cBot.|
//+------------------------------------------------------------------+
bool InGainzSessionWindow()
{
   int t = GetGMTHour() * 60 + GetGMTMin();
   int start = Gainz_StartH * 60;
   int end   = Gainz_EndH * 60;
   if(end < start) end += 1440;
   if(t < start) t += 1440;
   return (t >= start && t <= end);
}

//+------------------------------------------------------------------+
//| Count open Gainz positions (this symbol/magic, _G_ tag)          |
//+------------------------------------------------------------------+
int CountGainzPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "_G_") < 0) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Gainz trend filter: EMA on H1 at the last CLOSED bar             |
//+------------------------------------------------------------------+
double GetGainzEMA()
{
   if(hGainzEMA == INVALID_HANDLE) return 0;
   if(BarsCalculated(hGainzEMA) < Gainz_EMA_Period + 2) return 0;
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(hGainzEMA, 0, 0, 3, buf) < 3) return 0;
   return buf[1]; // 0 = forming bar, 1 = last closed
}

//+------------------------------------------------------------------+
//| Gainz-Swing entry: previous-day range breakout + EMA bias        |
//+------------------------------------------------------------------+
void CheckGainzEntry()
{
   if(!EnableGainzSwing) return;
   if(hGainzEMA == INVALID_HANDLE) return;

   //--- One attempt per H1 bar
   datetime barTime = iTime(_Symbol, PERIOD_H1, 0);
   if(barTime == g_lastGainzEntryBarTime) return;
   g_lastGainzEntryBarTime = barTime;

   //--- Cooldown after a Gainz exit
   if(TimeCurrent() < g_gainzNextEntryAllowed) return;

   //--- Shared guards
   if(g_stats.tradingStopped || g_stats.sessTradingStopped) return;
   if(g_stats.sessionTradeCount >= MaxTradesPerSess) return;
   if(CountOpenPositions() >= MaxPositions) return;
   if(CountGainzPositions() > 0) return; // one swing position at a time

   //--- Session window
   if(!InGainzSessionWindow()) return;

   //--- Signal on the last CLOSED H1 bar:
   //    long  = close > prev-day high AND close > EMA
   //    short = close < prev-day low  AND close < EMA
   double ema = GetGainzEMA();
   if(ema <= 0) return;
   double prevHigh = iHigh(_Symbol, PERIOD_D1, 1);
   double prevLow  = iLow(_Symbol, PERIOD_D1, 1);
   if(prevHigh <= 0 || prevLow >= 1e8) return;
   double close = iClose(_Symbol, PERIOD_H1, 1);
   if(close <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double pip = SymbolInfoDouble(_Symbol, SYMBOL_POINT); // gold: 0.01
   double tpPips = Gainz_TP_Pips * pip;
   double slPips = Gainz_SL_Pips * pip;

   if(close > prevHigh && close > ema)
   {
      double sl = ask - slPips;
      double tp = ask + tpPips;
      double lot = CalcLotSizeRisk(slPips, Gainz_RiskPct);
      if(lot <= 0) return;
      if(!VerifyTrade(ORDER_TYPE_BUY, ask, sl, tp, lot)) return;
      if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, tp, CommentPrefix + "_G_BUY"))
      {
         g_stats.tradeCount++;
         g_stats.sessionTradeCount++;
         if(DebugMode) Print("GAINZ BUY: close=", close, " prevHigh=", prevHigh, " EMA=", ema);
      }
   }
   else if(close < prevLow && close < ema)
   {
      double sl = bid + slPips;
      double tp = bid - tpPips;
      double lot = CalcLotSizeRisk(slPips, Gainz_RiskPct);
      if(lot <= 0) return;
      if(!VerifyTrade(ORDER_TYPE_SELL, bid, sl, tp, lot)) return;
      if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, tp, CommentPrefix + "_G_SELL"))
      {
         g_stats.tradeCount++;
         g_stats.sessionTradeCount++;
         if(DebugMode) Print("GAINZ SELL: close=", close, " prevLow=", prevLow, " EMA=", ema);
      }
   }
}

//+------------------------------------------------------------------+
//| Gainz-Swing position management: max hold + no-overnight close   |
//+------------------------------------------------------------------+
bool CloseGainzPosition(ulong ticket, string reason)
{
   if(!PositionSelectByTicket(ticket)) return false;
   int type = (int)PositionGetInteger(POSITION_TYPE);
   int orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double price = (type == POSITION_TYPE_BUY) ?
                  SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                  SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = PositionGetDouble(POSITION_VOLUME);
   req.type = (ENUM_ORDER_TYPE)orderType;
   req.price = price;
   req.deviation = MaxSlippagePts;
   req.comment = reason;
   req.magic = MagicNumber;
   req.type_filling = g_fillMode;
   if(OrderSend(req, res))
   {
      if(DebugMode) Print("GAINZ CLOSE (", reason, ") ticket=", ticket);
      return true;
   }
   if(DebugMode) Print("GAINZ CLOSE FAILED: ", GetLastError());
   return false;
}

void ManageGainzPositions()
{
   if(!EnableGainzSwing) return;
   bool pastCutoff = Gainz_NoOvernight && (GetGMTHour() >= Gainz_CutoffHour);

   ulong live[];
   int liveCount = 0;

   //--- Pass 1: close on max-hold / no-overnight cutoff; snapshot survivors
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "_G_") < 0) continue;

      string reason = "";
      datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
      if(opened > 0 && TimeCurrent() - opened >= Gainz_MaxHoldHours * 3600)
         reason = "MAX_HOLD";
      if(reason == "" && pastCutoff)
         reason = "CUTOFF_NO_OVERNIGHT";

      if(reason != "")
      {
         if(CloseGainzPosition(ticket, reason))
            g_gainzNextEntryAllowed = TimeCurrent() + Gainz_CooldownHours * 3600;
      }
      else
      {
         int n = ArraySize(live);
         ArrayResize(live, n + 1);
         live[n] = ticket;
         liveCount++;
      }
   }

   //--- Pass 2: tickets that vanished on their own (TP/SL hit) -> cooldown
   for(int i = 0; i < g_gainzTicketCount; i++)
   {
      bool stillOpen = false;
      for(int j = 0; j < liveCount; j++)
         if(live[j] == g_gainzTickets[i]) { stillOpen = true; break; }
      if(!stillOpen)
         g_gainzNextEntryAllowed = TimeCurrent() + Gainz_CooldownHours * 3600;
   }

   //--- Pass 3: snapshot live list
   ArrayResize(g_gainzTickets, liveCount);
   for(int i = 0; i < liveCount; i++) g_gainzTickets[i] = live[i];
   g_gainzTicketCount = liveCount;
}

//+------------------------------------------------------------------+
//| Chart comment                                                    |
//+------------------------------------------------------------------+
string RepeatStr(string s, int n)
{
   string r = "";
   for(int i = 0; i < n; i++) r += s;
   return r;
}

void UpdateComment()
{
   string sep = "\n" + RepeatStr("-", 30) + "\n";
   string info = "=== ScalpXAU v1.0 ===" + sep;
   info += "Symbol: " + _Symbol + " | TF: " + EnumToString(EntryTF) + "\n";
   info += "Balance: $" + DoubleToString(m_account.Balance(), 2);
   info += " | Equity: $" + DoubleToString(m_account.Equity(), 2);
   info += " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";

   double dd = 0;
   if(g_stats.startingBalance > 0)
      dd = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
   info += "Today: " + IntegerToString(g_stats.tradeCount);
   info += " | Session: " + IntegerToString(g_stats.sessionTradeCount) + "/" + IntegerToString(MaxTradesPerSess);
   info += " | DD: " + DoubleToString(dd, 2) + "% (limit: " + DoubleToString(MaxDailyRiskPct, 1) + "%)" + sep;

   info += "Session: " + GetSessionName(g_currentSession) + " (GMT";
   if(g_brokerGMTOffset != 0) info += (g_brokerGMTOffset > 0 ? "+" : "") + IntegerToString(g_brokerGMTOffset);
   info += ")" + "\n";

   if(g_asianRangeReady)
      info += "Asian Range: H=" + DoubleToString(g_asianHigh, 2) + " L=" + DoubleToString(g_asianLow, 2) + "\n";

   info += "FVG: " + IntegerToString(g_fvgCount) + " | LiqLevels: " + IntegerToString(g_liqCount) + "\n";
   info += "ATR(14): " + DoubleToString(g_atrValue, 1) + " | Swings: " + IntegerToString(ArraySize(g_swingHighIdx)) + "H/" + IntegerToString(ArraySize(g_swingLowIdx)) + "L" + "\n";
   info += "Open: " + IntegerToString(CountOpenPositions()) + sep;

   info += "Asian " + (EnableAsian ? "ON" : "OFF");
   info += " | London " + (EnableLondon ? "ON" : "OFF");
   info += " | NY " + (EnableNY ? "ON" : "OFF");
   info += " | Gainz " + (EnableGainzSwing ? "ON" : "OFF") + "\n";
   info += "Trailing: " + (UseTrailing ? "ON" : "OFF") + " | BE: " + (UseBreakEven ? "ON" : "OFF") + "\n";

   if(g_stats.tradingStopped)
      info += "*** TRADING STOPPED (daily loss limit) ***\n";
   if(g_stats.sessTradingStopped)
      info += "*** SESSION STOPPED (session DD limit) ***\n";

   Comment(info);
}
//+------------------------------------------------------------------+
