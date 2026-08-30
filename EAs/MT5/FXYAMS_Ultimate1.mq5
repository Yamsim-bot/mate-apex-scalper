//+------------------------------------------------------------------+
//|                                          FXYAMS_Ultimate1.mq5    |
//|           FXYAMS Ultimate Structure Scalper v2.0 — Fixed         |
//|           Multi-instrument | BB+Swing+RSI | Profit Protection     |
//+------------------------------------------------------------------+
//| v2.0 Fixes:                                                       |
//|  1. Session filter: proper London+NY (was broken 0-1440)          |
//|  2. Added partial TP + trailing stop + break-even                |
//|  3. Auto-detect broker fill mode (was hardcoded IOC)              |
//|  4. TP hit pause: pause after 5 TPs (wait next session)          |
//|  5. Full debug logging for signal tracking                        |
//|  6. Tighter risk: 3% max daily loss, 0.5% per trade              |
//| v2.10: TrendMode trend-following leg (pullback + breakout, no RSI)|
//+------------------------------------------------------------------+
#property copyright "FXYAMS Replication Project"
#property version   "2.10"
#property description "FXYAMS_Ultimate1 v2.10: Structure scalper + TrendMode trend-following leg"

//--- Trend Filter (M15)
input int      MA_Fast_Period      = 50;       // Fast MA Period (M15)
input int      MA_Slow_Period      = 200;      // Slow MA Period (M15)
input ENUM_MA_METHOD MA_Method     = MODE_SMA; // MA Type
input ENUM_APPLIED_PRICE MA_Price  = PRICE_CLOSE;

//--- Entry
input int      BB_Period           = 20;       // Bollinger Bands Period
input double   BB_StdDev           = 2.0;      // Bollinger Bands StdDev
input int      RSI_Period          = 14;       // RSI Period
input int      RSI_Buy_Max         = 78;       // RSI max for BUY
input int      RSI_Sell_Min        = 22;       // RSI min for SELL
input ENUM_TIMEFRAMES EntryTF      = PERIOD_M15; // Entry timeframe

//--- Swing Detection
input int      Swing_Lookback      = 7;        // Bars each side for swing
input double   Swing_Proximity_ATR = 1.00;     // Max ATR distance from swing

//--- Entry Filters
input double   Min_Body_ATR        = 0.05;     // Min candle body (xATR)
input double   Reject_Wick_ATR     = 0.04;     // Min rejection wick (xATR)
input bool     UseRejection        = false;    // Require rejection candle

//--- Trade Settings
input int      MaxPositions        = 1;        // Max concurrent positions (was 2)
input double   RiskPercent         = 0.5;      // % risk per trade
input int      MaxDailyTrades      = 30;       // Max trades per day
input double   MaxDailyLossPct     = 5.0;      // Max daily loss %
input int      MaxTPHits           = 8;        // Pause after X TPs hit PER SESSION
input bool     ResetOnNewSession  = true;     // Reset TP counter on new session

//--- SL/TP
input double   SL_ATR_Mult         = 0.5;      // SL beyond structure (xATR)
input double   Min_SL_ATR          = 1.0;      // Min SL distance (xATR, was 0.3 — sub-ATR stops got clipped in noise)
input double   Max_SL_ATR          = 1.2;      // Max SL distance (xATR, was 1.5)
input double   Min_RR              = 1.0;      // Minimum reward:risk (anti-bleed: >= 1:1)

//--- Partial Take-Profit
input bool     UsePartialTP        = true;     // Enable partial TP
input double   PartialTP_Pct       = 60.0;     // Partial TP at X% of full TP
input double   PartialClosePct     = 50.0;     // Close X% at partial TP

//--- Trailing Stop
input bool     UseTrailing         = true;     // Trail after partial TP
input double   TrailingStart_ATR   = 0.5;      // Start trailing after X*ATR
input double   TrailingStep_ATR    = 0.25;     // Trailing step (xATR)

//--- Break-Even
input bool     UseBreakEven        = true;     // Move SL to breakeven
input double   BreakEven_ATR       = 0.6;      // Move SL after X*ATR profit

//--- Trading Session (PH Time = UTC+8)
input bool     UseSessionFilter    = true;
// Window 1: London session (15:00-00:00 PH)
input int      SessionStartHour    = 15;       // London open (PH)
input int      SessionStartMin     = 0;
input int      SessionEndHour      = 0;        // Midnight PH
input int      SessionEndMin       = 0;
// Window 2: NY session (20:00-05:00 PH)
input int      Session2StartHour   = 20;       // NY open (PH)
input int      Session2StartMin    = 0;
input int      Session2EndHour     = 5;        // NY close (PH)
input int      Session2EndMin      = 0;
input bool     TradeMonday         = true;
input bool     TradeTuesday        = true;
input bool     TradeWednesday      = true;
input bool     TradeThursday       = true;
input bool     TradeFriday         = true;

//--- Scalp Mode (v3.0)
input bool     ScalpMode           = true;       // Enable scalp mode (relaxed filters)
input double   Scalp_BreakoutATR   = 0.25;       // Momentum breakout: min candle range (xATR)
input double   Scalp_VolatilityMin = 0.5;        // Min volatility as fraction of 20-bar avg ATR

//--- Trend Mode (v4.0)
input bool     TrendMode            = true;    // Enable trend-following leg
input double   Trend_MinSep_ATR     = 0.30;    // Min |MA50-MA200| / ATR for trend regime
input double   Trend_Pullback_ATR   = 0.50;    // Pullback must dip within this of fast MA (xATR)
input double   Trend_Breakout_ATR   = 0.40;    // Breakout bar must clear prior high by this (xATR)
input double   Trend_TP_ATR         = 1.50;    // Partial-TP trigger distance (xATR), closes 50%
input double   Trend_TrailStart_ATR = 1.00;    // Start wide trail after this profit (xATR)
input double   Trend_TrailStep_ATR  = 0.50;    // Wide-trail step (xATR)
input double   Trend_SL_Buffer_ATR  = 0.30;    // SL beyond pullback-low / breakout-low (xATR)

//--- General
input ulong    MagicNumber         = 20260716;
input string   CommentPrefix       = "ULTI_EA";
input int      MaxSpreadPts        = 500;
input int      MaxSlippagePts      = 50;
input bool     DebugMode           = true;

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int    hMA_Fast_M15      = INVALID_HANDLE;
int    hMA_Slow_M15      = INVALID_HANDLE;
int    hBB_Entry          = INVALID_HANDLE;
int    hRSI_Entry         = INVALID_HANDLE;

double g_atrValue         = 0;
double g_atrEntry         = 0;
int    g_signalBar         = 0;   // M15 bar time of last entry (one entry per bar)
int    g_swingHighIdx[];
int    g_swingLowIdx[];
double g_swingHighVal[];
double g_swingLowVal[];
bool   g_swingReady       = false;
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_IOC;
datetime g_eaStartTime   = 0;     // Attach time — pre-bot history must not count as TP hits
int    g_heartbeatCount   = 0;

// Daily tracking
struct DailyStats {
   datetime date;
   int      tradeCount;
   int      tpHits;        // Count of TPs hit in CURRENT session
   bool     tpPause;       // True after MaxTPHits reached in current session
   int      currentSession;  // 0=none, 1=session1 (London), 2=session2 (NY)
   datetime lastTPReset;     // When tpHits was last reset (for deal history filtering)
   double   startingBalance;
   bool     tradingStopped;
};
DailyStats g_dailyStats;
datetime   g_lastResetDay = 0;
datetime   g_lastBarTime  = 0;

//+------------------------------------------------------------------+
//| Auto-detect fill mode                                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillMode()
{
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(filling & SYMBOL_FILLING_FOK)  return ORDER_FILLING_FOK;
   if(filling & SYMBOL_FILLING_IOC)  return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Broker GMT offset + PH time helpers (auto-detect broker offset)  |
//| Assumption "broker = UTC" is wrong for most brokers (Vantage=+3, |
//| VPS=+2), so sessions were detected 2-3h late.                    |
//+------------------------------------------------------------------+
int YAMS_BrokerOffset()
{
   static int off = -99;
   if(off == -99)
   {
      off = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(off < -14) off = -14;
      if(off > 14)  off = 14;
   }
   return off;
}

int YAMS_PHHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int gmt = dt.hour - YAMS_BrokerOffset();
   if(gmt < 0) gmt += 24;
   int ph = gmt + 8;
   if(ph >= 24) ph -= 24;
   return ph;
}

int YAMS_PHMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

int YAMS_PHDow()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int gmt = dt.hour - YAMS_BrokerOffset();
   int dow = dt.day_of_week;
   if(gmt < 0) { dow--; if(dow < 0) dow = 6; }
   int ph = gmt + 8;
   if(ph >= 24) { dow++; if(dow > 6) dow = 0; }
   return dow;
}

//+------------------------------------------------------------------+
//| Session filter — dual window (PH Time UTC+8)                     |
//+------------------------------------------------------------------+
bool IsInHybridWindow()
{
   if(!UseSessionFilter) return true;

   int phHour = YAMS_PHHour();
   int phMin  = YAMS_PHMin();
   int nowMin = phHour * 60 + phMin;

   int w1Start = SessionStartHour * 60 + SessionStartMin;
   int w1End   = SessionEndHour   * 60 + SessionEndMin;
   int w2Start = Session2StartHour * 60 + Session2StartMin;
   int w2End   = Session2EndHour   * 60 + Session2EndMin;

   bool inW1 = (w1Start < w1End) ? (nowMin >= w1Start && nowMin < w1End)
                                  : (nowMin >= w1Start || nowMin < w1End);
   bool inW2 = (w2Start < w2End) ? (nowMin >= w2Start && nowMin < w2End)
                                  : (nowMin >= w2Start || nowMin < w2End);

   return inW1 || inW2;
}

bool IsTradingDay()
{
   if(!UseSessionFilter) return true;
   int dow = YAMS_PHDow();

   switch(dow)
   {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false;
   }
}

bool IsInSession()
{
   return IsTradingDay() && IsInHybridWindow();
}

string GetSessionStatus()
{
   if(!UseSessionFilter) return "No filter";

   int phHour = YAMS_PHHour();
   int phMin  = YAMS_PHMin();
   int adjDow = YAMS_PHDow();
   string dayNames[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   string status = dayNames[adjDow] + " " + IntegerToString(phHour) + ":" + StringFormat("%02d", phMin) + " PH | ";

   string w1 = StringFormat("W1:%02d:%02d-%02d:%02d", SessionStartHour, SessionStartMin, SessionEndHour, SessionEndMin);
   string w2 = StringFormat("W2:%02d:%02d-%02d:%02d", Session2StartHour, Session2StartMin, Session2EndHour, Session2EndMin);

   if(IsInSession())
      status += "ACTIVE " + w1 + " " + w2;
   else if(!IsTradingDay())
      status += "NOT A TRADING DAY";
   else
      status += "OUTSIDE (" + w1 + " " + w2 + ")";

   return status;
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_eaStartTime = TimeCurrent();
   g_fillMode = GetFillMode();
   string fillStr = (g_fillMode == ORDER_FILLING_FOK) ? "FOK" :
                    (g_fillMode == ORDER_FILLING_IOC) ? "IOC" : "RETURN";

   Print("================================================================");
   Print("FXYAMS_Ultimate1 v2.1 initializing");
   Print("  Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("  Account: ", AccountInfoInteger(ACCOUNT_LOGIN), " @ ", AccountInfoString(ACCOUNT_SERVER));
   Print("  Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("  Symbol=", _Symbol, " TF=", EnumToString(EntryTF));
   Print("  Fill mode: ", fillStr);
   Print("  Trend: MA", MA_Fast_Period, "/MA", MA_Slow_Period, " on M15");
   Print("  Entry: BB(", BB_Period, ",", DoubleToString(BB_StdDev, 1),
         ") RSI<", RSI_Buy_Max, "/>", RSI_Sell_Min,
         " Swing:", Swing_Lookback, " bars");
   Print("  SL: ", SL_ATR_Mult, "x ATR (min:", Min_SL_ATR, " max:", Max_SL_ATR, ")");
   Print("  Risk: ", RiskPercent, "% | Max DD: ", MaxDailyLossPct, "%");
   Print("  TrendMode: ", TrendMode ? "ON" : "OFF",
         " | gate sep>=", Trend_MinSep_ATR, "xATR",
         " | pullback<=", Trend_Pullback_ATR, " | breakout>=", Trend_Breakout_ATR);
   Print("  Trend exits: partial @", Trend_TP_ATR, "xATR (", PartialClosePct, "%) | trail ",
         Trend_TrailStart_ATR, "/", Trend_TrailStep_ATR, "xATR");
   Print("  Partial TP: ", UsePartialTP ? "ON" : "OFF",
         " | Trailing: ", UseTrailing ? "ON" : "OFF",
         " | Break-Even: ", UseBreakEven ? "ON" : "OFF");
   Print("  Max positions: ", MaxPositions, " | Max daily: ", MaxDailyTrades, " | TP Pause: ", MaxTPHits, " per session");
   Print("  Session: ", GetSessionStatus());

   // Validate params
   if(MA_Fast_Period >= MA_Slow_Period)
   {
      Print("ERROR: Fast MA (", MA_Fast_Period, ") must be < Slow MA (", MA_Slow_Period, ")");
      return INIT_PARAMETERS_INCORRECT;
   }

   hMA_Fast_M15 = iMA(_Symbol, PERIOD_M15, MA_Fast_Period, 0, MA_Method, MA_Price);
   hMA_Slow_M15 = iMA(_Symbol, PERIOD_M15, MA_Slow_Period, 0, MA_Method, MA_Price);
   hBB_Entry     = iBands(_Symbol, EntryTF, BB_Period, 0, BB_StdDev, MA_Price);
   hRSI_Entry    = iRSI(_Symbol, EntryTF, RSI_Period, PRICE_CLOSE);

   if(hMA_Fast_M15 == INVALID_HANDLE || hMA_Slow_M15 == INVALID_HANDLE ||
      hBB_Entry == INVALID_HANDLE || hRSI_Entry == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   g_dailyStats.startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyStats.date = 0;
   g_lastResetDay = 0;
   g_swingReady = false;

   ArrayResize(g_swingHighIdx, 0);
   ArrayResize(g_swingLowIdx, 0);

   Print("EA OK. Symbol: ", _Symbol, " Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
   Print("================================================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hMA_Fast_M15 != INVALID_HANDLE) IndicatorRelease(hMA_Fast_M15);
   if(hMA_Slow_M15 != INVALID_HANDLE) IndicatorRelease(hMA_Slow_M15);
   if(hBB_Entry != INVALID_HANDLE)    IndicatorRelease(hBB_Entry);
   if(hRSI_Entry != INVALID_HANDLE)   IndicatorRelease(hRSI_Entry);
   Comment("");
   Print("FXYAMS_Ultimate1 v2.0 deinit. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Detect which session we're currently in                           |
//+------------------------------------------------------------------+
int GetCurrentSession()
{
   if(!UseSessionFilter) return 0;

   int phHour = YAMS_PHHour();

   bool inS1 = (SessionStartHour < SessionEndHour)
       ? (phHour >= SessionStartHour && phHour < SessionEndHour)
       : (phHour >= SessionStartHour || phHour < SessionEndHour);

   bool inS2 = (Session2StartHour < Session2EndHour)
       ? (phHour >= Session2StartHour && phHour < Session2EndHour)
       : (phHour >= Session2StartHour || phHour < Session2EndHour);

   // During overlap (20:00-00:00), prefer session 2 (NY)
   if(inS2) return 2;
   if(inS1) return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| Daily stats                                                       |
//+------------------------------------------------------------------+
void ResetDaily()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StructToTime(dt);
   today = today - (today % 86400);

   if(today != g_lastResetDay)
   {
      ZeroMemory(g_dailyStats);
      g_dailyStats.date = today;
      g_dailyStats.startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyStats.tradingStopped = false;
      g_dailyStats.lastTPReset = today;
      g_lastResetDay = today;
   }

   //--- Detect session change -> reset TP counter for new session
   int newSession = GetCurrentSession();
   if(newSession != g_dailyStats.currentSession)
   {
      g_dailyStats.currentSession = newSession;
      g_dailyStats.tpHits = 0;
      g_dailyStats.tpPause = false;
      g_dailyStats.lastTPReset = TimeCurrent();
      if(newSession > 0)
         Print("SESSION CHANGE -> ", (newSession == 1 ? "LONDON" : "NY"),
               " | TP counter reset. Fresh ", MaxTPHits, " TPs available.");
   }
}

bool CanTrade()
{
   ResetDaily();
   if(g_dailyStats.tradingStopped) return false;
   if(g_dailyStats.tradeCount >= MaxDailyTrades) return false;

   //--- TP pause check (per session)
   if(g_dailyStats.tpPause)
   {
      static int lastTpWarn = 0;
      if(TimeCurrent() - lastTpWarn >= 300)
      {
         lastTpWarn = TimeCurrent();
         string sessName = (g_dailyStats.currentSession == 1) ? "LONDON" : "NY";
         Print("TP PAUSE: ", g_dailyStats.tpHits, "/", MaxTPHits,
               " TPs hit in ", sessName, " session. Waiting for next session.");
      }
      return false;
   }

   //--- Daily loss check
   double dd = (g_dailyStats.startingBalance - AccountInfoDouble(ACCOUNT_EQUITY))
               / MathMax(g_dailyStats.startingBalance, 1.0) * 100.0;
   if(dd >= MaxDailyLossPct)
   {
      g_dailyStats.tradingStopped = true;
      Print("STOPPED: Daily loss limit reached. DD=", DoubleToString(dd, 2), "%");
      CloseAllPositions("DD_CLOSE");
      return false;
   }

   //--- Spread check
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Detect TPs hit today (check deal history)                        |
//+------------------------------------------------------------------+
void DetectTPHits()
{
   ResetDaily();

   // Only count deals from current session start (not entire day)
   datetime sessionStart = g_dailyStats.lastTPReset;
   if(!HistorySelect(sessionStart, TimeCurrent())) return;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicNumber) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime < sessionStart) continue;
      if(dealTime < g_eaStartTime) continue;   // ignore pre-bot history (anti-lockout)

      long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
      if(reason == DEAL_REASON_TP)
      {
         static datetime lastTPDealTime = 0;
         static ulong lastTPDealTicket = 0;
         if(dealTime == lastTPDealTime && ticket == lastTPDealTicket) continue;
         lastTPDealTime = dealTime;
         lastTPDealTicket = ticket;

         g_dailyStats.tpHits++;
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         string sessName = (g_dailyStats.currentSession == 1) ? "LONDON" : "NY";
         Print("TP HIT #", g_dailyStats.tpHits, "/", MaxTPHits,
               " (", sessName, " session)",
               " | Profit: $", DoubleToString(profit, 2),
               " | ", TimeToString(dealTime));

         if(g_dailyStats.tpHits >= MaxTPHits)
         {
            g_dailyStats.tpPause = true;
            Print("TP PAUSE [", sessName, "]: ", g_dailyStats.tpHits,
                  " TPs hit. No new entries (open positions still managed).");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Swing point detection                                            |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   MqlRates rates[];
   int total = CopyRates(_Symbol, EntryTF, 0, 200, rates);
   if(total < Swing_Lookback * 2 + 5) return;

   ArraySetAsSeries(rates, true);

   ArrayResize(g_swingHighIdx, 0);
   ArrayResize(g_swingLowIdx, 0);
   ArrayResize(g_swingHighVal, 0);
   ArrayResize(g_swingLowVal, 0);

   int lookback = Swing_Lookback;

   for(int i = lookback; i < total - lookback; i++)
   {
      bool isHigh = true;
      bool isLow = true;

      for(int j = 1; j <= lookback; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
            isHigh = false;
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
            isLow = false;
      }

      if(isHigh)
      {
         int idx = ArraySize(g_swingHighIdx);
         ArrayResize(g_swingHighIdx, idx + 1);
         ArrayResize(g_swingHighVal, idx + 1);
         g_swingHighIdx[idx] = i;
         g_swingHighVal[idx] = rates[i].high;
      }
      if(isLow)
      {
         int idx = ArraySize(g_swingLowIdx);
         ArrayResize(g_swingLowIdx, idx + 1);
         ArrayResize(g_swingLowVal, idx + 1);
         g_swingLowIdx[idx] = i;
         g_swingLowVal[idx] = rates[i].low;
      }
   }

   g_swingReady = true;
}

bool FindRecentSwing(double &level, int &idx, int &swingIdx[], double &swingVal[], int lookbackBars = 30)
{
   int n = ArraySize(swingIdx);
   for(int i = n - 1; i >= 0; i--)
   {
      int barsAgo = swingIdx[i];
      if(barsAgo >= Swing_Lookback && barsAgo <= lookbackBars)
      {
         idx = swingIdx[i];
         level = swingVal[i];
         return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| ATR                                                               |
//+------------------------------------------------------------------+
double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   if(CopyRates(_Symbol, tf, 0, period + 1, rates) < period + 1) return 0;
   ArraySetAsSeries(rates, true);

   double sum = 0;
   for(int i = 1; i <= period; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low,
                 MathMax(MathAbs(rates[i].high - rates[i-1].close),
                         MathAbs(rates[i].low - rates[i-1].close)));
      sum += tr;
   }
   return sum / period;
}

//+------------------------------------------------------------------+
//| Broker minimum stop distance (in price units)                    |
//| The broker may reject stops closer than SYMBOL_TRADE_STOPS_LEVEL. |
//+------------------------------------------------------------------+
double GetMinStopDist()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double minDist = stopsLevel * point;
   return (minDist > 0) ? minDist : point;
}

//+------------------------------------------------------------------+
//| Lot sizing                                                        |
//+------------------------------------------------------------------+
double CalcLotSize(double slDist)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * RiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0 || tickSize <= 0 || slDist <= 0)
      return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

   double lotRaw = riskAmount / ((slDist / tickSize) * tickValue);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   double lot = MathFloor(lotRaw / lotStep) * lotStep;
   lot = MathMax(lot, lotMin);

   //--- Notional cap: ~$30k exposure per $10k balance (~7 oz at current gold).
   //--- Prevents risk-based sizing on a wide ATR stop from blowing margin.
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > 0)
   {
      double maxVol = (balance / 10000.0) * 30000.0 / price;
      if(lotStep > 0) maxVol = MathFloor(maxVol / lotStep) * lotStep;
      lot = MathMin(lot, maxVol);
   }
   lot = MathMin(lot, lotMax);
   return lot;
}

//+------------------------------------------------------------------+
//| Verify trade                                                     |
//+------------------------------------------------------------------+
bool VerifyTrade(int type, double price, double sl, double tp, double lot)
{
   int spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts)
   {
      Print("SPREAD TOO HIGH: ", spread, " > ", MaxSpreadPts);
      return false;
   }

   double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(lot < lotMin) return false;

   double margin = 0;
   if(!OrderCalcMargin(type == ORDER_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                       _Symbol, lot, price, margin))
      return false;

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin >= freeMargin)
   {
      Print("INSUFFICIENT MARGIN: need ", margin, " have ", freeMargin);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Send market order (auto fill mode)                                |
//+------------------------------------------------------------------+
bool OpenOrder(int type, double volume, double price,
               double sl, double tp, string comment)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = volume;
   request.type      = (ENUM_ORDER_TYPE)type;
   request.price     = price;
   request.deviation = MaxSlippagePts;
   request.sl        = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp        = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.comment   = comment;
   request.magic     = MagicNumber;
   request.type_filling = g_fillMode;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("ORDER: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               " Lot=", volume, " @ ", price,
               " SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               " TP=", DoubleToString(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)));
         return true;
      }
      else
      {
         Print("ORDER FAILED: retcode=", result.retcode, " comment=", result.comment);
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Close partial position                                            |
//+------------------------------------------------------------------+
bool ClosePartial(ulong ticket, double closeVol)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int type = (int)PositionGetInteger(POSITION_TYPE);
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = NormalizeDouble(closeVol, 2);
   req.deviation = MaxSlippagePts;
   req.type_filling = g_fillMode;
   if(type == POSITION_TYPE_BUY)
   { req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); req.type = ORDER_TYPE_SELL; }
   else
   { req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); req.type = ORDER_TYPE_BUY; }
   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Modify SL/TP                                                     |
//+------------------------------------------------------------------+
bool ModifySL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = NormalizeDouble(newSL, digits);
   req.tp = PositionGetDouble(POSITION_TP);
   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(string reason = "")
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      int type = (int)PositionGetInteger(POSITION_TYPE);
      int orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                 : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

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
      OrderSend(req, res);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions — partial TP, trailing, break-even         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UsePartialTP && !UseTrailing && !UseBreakEven) return;

   double atr = g_atrEntry;
   if(atr <= 0) atr = g_atrValue;
   if(atr <= 0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double minVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      long   type      = PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- Trend-tag detection (comment contains "_T_")
      string posComment = PositionGetString(POSITION_COMMENT);
      bool isTrend = (StringFind(posComment, "_T_") >= 0);

      //--- Break-Even
      if(UseBreakEven)
      {
         double beDist = (isTrend ? Trend_TrailStart_ATR : BreakEven_ATR) * atr;
         if(type == POSITION_TYPE_BUY)
         {
            double newSL = NormalizeDouble(entry + point * 5, digits);
            if(currentPrice >= entry + beDist && sl < entry)
               ModifySL(ticket, newSL);
         }
         else
         {
            double newSL = NormalizeDouble(entry - point * 5, digits);
            if(currentPrice <= entry - beDist && (sl > entry || sl == 0))
               ModifySL(ticket, newSL);
         }
      }

      //--- Partial Take-Profit
      if(UsePartialTP && volume > minVol)
      {
         double tpDist = MathAbs(tp - entry);
         if(tpDist <= 0) continue;
         double partialLevel = (type == POSITION_TYPE_BUY) ?
                               entry + tpDist * (PartialTP_Pct / 100.0) :
                               entry - tpDist * (PartialTP_Pct / 100.0);

         bool partialHit = false;
         if(type == POSITION_TYPE_BUY && currentPrice >= partialLevel)
            partialHit = true;
         else if(type == POSITION_TYPE_SELL && currentPrice <= partialLevel)
            partialHit = true;

         if(partialHit)
         {
            double closeVol = NormalizeDouble(volume * (PartialClosePct / 100.0), 2);
            closeVol = MathMax(closeVol, minVol);
            if(closeVol < volume)
            {
               if(ClosePartial(ticket, closeVol))
                  Print("PARTIAL TP: Closed ", closeVol, " lots at ", currentPrice);
            }
         }
      }

      //--- Trailing Stop
      if(UseTrailing)
      {
         double trailStart = (isTrend ? Trend_TrailStart_ATR : TrailingStart_ATR) * atr;
         double trailStep  = (isTrend ? Trend_TrailStep_ATR  : TrailingStep_ATR)  * atr;

         if(type == POSITION_TYPE_BUY)
         {
            double profitDist = currentPrice - entry;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(currentPrice - trailStep, digits);
               if(newSL > sl + point)
                  ModifySL(ticket, newSL);
            }
         }
         else
         {
            double profitDist = entry - currentPrice;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(currentPrice + trailStep, digits);
               if(newSL < sl - point || sl == 0)
                  ModifySL(ticket, newSL);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check entry signals                                              |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(!g_swingReady) return;
   if(!IsInSession()) return;

   MqlRates ratesEntry[];
   ArraySetAsSeries(ratesEntry, true);
   if(CopyRates(_Symbol, EntryTF, 0, 10, ratesEntry) < 5) return;

   //--- One entry per M15 bar (match cBot _signalBarTime dedup)
   if(g_signalBar == (int)ratesEntry[0].time) return;

   MqlRates ratesM15[];
   ArraySetAsSeries(ratesM15, true);
   if(CopyRates(_Symbol, PERIOD_M15, 0, 10, ratesM15) < 5) return;

   // Indicator buffers
   double maFast[], maSlow[], bbUp[], bbMid[], bbLow[], rsi[];
   ArraySetAsSeries(maFast, true); ArraySetAsSeries(maSlow, true);
   ArraySetAsSeries(bbUp, true); ArraySetAsSeries(bbMid, true); ArraySetAsSeries(bbLow, true);
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(hMA_Fast_M15, 0, 0, 5, maFast) < 3) return;
   if(CopyBuffer(hMA_Slow_M15, 0, 0, 5, maSlow) < 3) return;
   if(CopyBuffer(hBB_Entry, 1, 0, 8, bbUp) < 3) return;
   if(CopyBuffer(hBB_Entry, 0, 0, 8, bbMid) < 3) return;
   if(CopyBuffer(hBB_Entry, 2, 0, 8, bbLow) < 3) return;
   if(CopyBuffer(hRSI_Entry, 0, 0, 8, rsi) < 3) return;

   // ATR
   g_atrValue = CalcATR(14, PERIOD_M15);
   g_atrEntry = CalcATR(14, EntryTF);
   if(g_atrValue <= 0 || g_atrEntry <= 0) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // Trend
   double spread = maFast[0] - maSlow[0];
   bool trendUp = ratesM15[0].close > maFast[0] && spread > 0;
   bool trendDown = ratesM15[0].close < maFast[0] && spread < 0;

   // Last closed bar data
   double c5_close = ratesEntry[1].close;
   double c5_open = ratesEntry[1].open;
   double c5_high = ratesEntry[1].high;
   double c5_low = ratesEntry[1].low;
   double body = MathAbs(c5_close - c5_open);
   double lowerWick = MathMin(c5_close, c5_open) - c5_low;
   double upperWick = c5_high - MathMax(c5_close, c5_open);
   bool isBullish = c5_close > c5_open;
   bool isBearish = c5_close < c5_open;
   bool bodyOK = body >= Min_Body_ATR * g_atrEntry;

   // Rejection check
   bool rejBull = false;
   bool rejBear = false;
   if(UseRejection)
   {
      double minWick = Reject_Wick_ATR * g_atrEntry;
      for(int c = 1; c <= 3; c++)
      {
         if(c >= ArraySize(ratesEntry)) break;
         double rb = MathAbs(ratesEntry[c].close - ratesEntry[c].open);
         double lw = MathMin(ratesEntry[c].close, ratesEntry[c].open) - ratesEntry[c].low;
         double uw = ratesEntry[c].high - MathMax(ratesEntry[c].close, ratesEntry[c].open);
         if(lw >= minWick && lw >= rb * 0.2 && ratesEntry[c].close > ratesEntry[c].open) rejBull = true;
         if(uw >= minWick && uw >= rb * 0.2 && ratesEntry[c].close < ratesEntry[c].open) rejBear = true;
      }
   }
   else
   {
      rejBull = true;
      rejBear = true;
   }

   double bbL = bbLow[1];
   double bbU = bbUp[1];
   double bbM = bbMid[1];
   bool bbTouchLow = c5_low <= bbL * 1.04;
   bool bbTouchHigh = c5_high >= bbU * 0.96;

   //--- Debug: Log signal status periodically
   static int lastDebugTime = 0;
   if(DebugMode && TimeCurrent() - lastDebugTime >= 300)
   {
      lastDebugTime = TimeCurrent();
      Print("DEBUG: bid=", DoubleToString(bid, 2),
            " trend=", trendUp ? "UP" : (trendDown ? "DOWN" : "FLAT"),
            " sepATR=", DoubleToString((g_atrValue > 0 ? spread / g_atrValue : 0), 2),
            " RSI=", DoubleToString(rsi[1], 1),
            " BB_L=", DoubleToString(bbL, 2), " BB_U=", DoubleToString(bbU, 2),
            " bbLow=", bbTouchLow, " bbHigh=", bbTouchHigh,
            " rejB=", rejBull, " rejS=", rejBear,
            " bodyOK=", bodyOK,
            " swings: H=", ArraySize(g_swingHighIdx), " L=", ArraySize(g_swingLowIdx));
   }
   // ═══════════════════════════════════════
   // Scalp Mode: momentum breakout (v3.0)
   // ═══════════════════════════════════════
   if(ScalpMode)
   {
      double range0 = ratesEntry[0].high - ratesEntry[0].low;
      double atr20 = CalcATR(20, EntryTF);
      bool volOK = (atr20 > 0) && (g_atrEntry >= atr20 * Scalp_VolatilityMin);

      // Momentum BUY: break above prev bar high with range
      if(volOK && range0 >= Scalp_BreakoutATR * g_atrEntry
         && ratesEntry[0].close > ratesEntry[0].open
         && ratesEntry[0].high > ratesEntry[1].high
         && rsi[1] < RSI_Buy_Max)
      {
         double sl = c5_low - SL_ATR_Mult * g_atrEntry;
         if(ratesEntry[0].low < sl) sl = ratesEntry[0].low;
         double slDist = ratesEntry[0].close - sl;
         double minStop = GetMinStopDist();
         if(slDist < minStop) { sl = ratesEntry[0].close - minStop; slDist = minStop; }
         if(slDist >= Min_SL_ATR * g_atrEntry && slDist <= Max_SL_ATR * g_atrValue)
         {
            double tp = ratesEntry[0].close + slDist * 1.5;
            if((tp - ratesEntry[0].close) < slDist * Min_RR)
               tp = ratesEntry[0].close + slDist * Min_RR;
            double lot = CalcLotSize(slDist);
            if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_BUY, ask, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, tp, CommentPrefix + "_BUY"))
               {
                  g_dailyStats.tradeCount++;
                  Print("SCALP BUY: close=", DoubleToString(ratesEntry[0].close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                        " range=", DoubleToString(range0 / g_atrEntry, 2), "xATR");
                  g_signalBar = (int)ratesEntry[0].time;
                  return;
               }
            }
         }
      }

      // Momentum SELL: break below prev bar low with range
      if(volOK && range0 >= Scalp_BreakoutATR * g_atrEntry
         && ratesEntry[0].close < ratesEntry[0].open
         && ratesEntry[0].low < ratesEntry[1].low
         && rsi[1] > RSI_Sell_Min)
      {
         double sl = c5_high + SL_ATR_Mult * g_atrEntry;
         if(ratesEntry[0].high > sl) sl = ratesEntry[0].high;
         double slDist = sl - ratesEntry[0].close;
         double minStop = GetMinStopDist();
         if(slDist < minStop) { sl = ratesEntry[0].close + minStop; slDist = minStop; }
         if(slDist >= Min_SL_ATR * g_atrEntry && slDist <= Max_SL_ATR * g_atrValue)
         {
            double tp = ratesEntry[0].close - slDist * 1.5;
            if((ratesEntry[0].close - tp) < slDist * Min_RR)
               tp = ratesEntry[0].close - slDist * Min_RR;
            double lot = CalcLotSize(slDist);
            if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_SELL, bid, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, tp, CommentPrefix + "_SELL"))
               {
                  g_dailyStats.tradeCount++;
                  Print("SCALP SELL: close=", DoubleToString(ratesEntry[0].close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                        " range=", DoubleToString(range0 / g_atrEntry, 2), "xATR");
                  g_signalBar = (int)ratesEntry[0].time;
                  return;
               }
            }
         }
      }
   }

   // ═══════════════════════════════════════
   // Standard mode: structure entry
   // ═══════════════════════════════════════
   if(!ScalpMode)

   // ═══════════════════════════════════════
   // BUY signal
   // ═══════════════════════════════════════
   if(trendUp && rsi[1] < RSI_Buy_Max && bbTouchLow && rejBull && bodyOK && isBullish)
   {
      double swingLevel;
      int swingIdx;
      if(FindRecentSwing(swingLevel, swingIdx, g_swingLowIdx, g_swingLowVal))
      {
         if(c5_low <= swingLevel + Swing_Proximity_ATR * g_atrEntry)
         {
            double sl = MathMax(swingLevel - SL_ATR_Mult * g_atrValue,
                               c5_close - Max_SL_ATR * g_atrValue);
            if(sl < c5_close)
            {
               double slDist = c5_close - sl;
               double minStop = GetMinStopDist();
               if(slDist < minStop) { sl = c5_close - minStop; slDist = minStop; }
               if(slDist >= Min_SL_ATR * g_atrValue)
               {
                  double tp = bbM;
                  if(tp < c5_close + slDist * Min_RR)   // stretch TP so RR >= Min_RR
                     tp = c5_close + slDist * Min_RR;
                  if(tp > c5_close)
                  {
                     double lot = CalcLotSize(slDist);
                     if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_BUY, ask, sl, tp, lot))
                     {
                        if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, tp, CommentPrefix + "_BUY"))
                        {
                           g_dailyStats.tradeCount++;
                           Print("BUY SIGNAL: RSI=", DoubleToString(rsi[1], 0),
                                 " BB=", DoubleToString(bbL, 2),
                                 " Swing=", DoubleToString(swingLevel, 2),
                                 " SL=", DoubleToString(slDist / g_atrValue, 2), "xATR",
                                 " RR=", DoubleToString((tp - c5_close) / slDist, 2));
                           g_signalBar = (int)ratesEntry[0].time;
                           return;
                        }
                     }
                  }
                  else if(DebugMode) Print("BUY REJECTED: TP below entry (bbM=", DoubleToString(bbM, 2), " < close=", DoubleToString(c5_close, 2), ")");
               }
               else if(DebugMode) Print("BUY REJECTED: SL too tight (", DoubleToString(slDist / g_atrValue, 2), "xATR < ", Min_SL_ATR, ")");
            }
         }
         else if(DebugMode) Print("BUY REJECTED: Price too far from swing (", DoubleToString((c5_low - swingLevel) / g_atrEntry, 2), "xATR)");
      }
      else if(DebugMode) Print("BUY REJECTED: No recent swing low found");
   }

   // ═══════════════════════════════════════
   // SELL signal
   // ═══════════════════════════════════════
   if(trendDown && rsi[1] > RSI_Sell_Min && bbTouchHigh && rejBear && bodyOK && isBearish)
   {
      double swingLevel;
      int swingIdx;
      if(FindRecentSwing(swingLevel, swingIdx, g_swingHighIdx, g_swingHighVal))
      {
         if(c5_high >= swingLevel - Swing_Proximity_ATR * g_atrEntry)
         {
            double sl = MathMin(swingLevel + SL_ATR_Mult * g_atrValue,
                               c5_close + Max_SL_ATR * g_atrValue);
            if(sl > c5_close)
            {
               double slDist = sl - c5_close;
               double minStop = GetMinStopDist();
               if(slDist < minStop) { sl = c5_close + minStop; slDist = minStop; }
               if(slDist >= Min_SL_ATR * g_atrValue)
               {
                  double tp = bbM;
                  if(tp > c5_close - slDist * Min_RR)   // stretch TP so RR >= Min_RR
                     tp = c5_close - slDist * Min_RR;
                  if(tp < c5_close)
                  {
                     double lot = CalcLotSize(slDist);
                     if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_SELL, bid, sl, tp, lot))
                     {
                        if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, tp, CommentPrefix + "_SELL"))
                        {
                           g_dailyStats.tradeCount++;
                           Print("SELL SIGNAL: RSI=", DoubleToString(rsi[1], 0),
                                 " BB=", DoubleToString(bbU, 2),
                                 " Swing=", DoubleToString(swingLevel, 2),
                                 " SL=", DoubleToString(slDist / g_atrValue, 2), "xATR",
                                 " RR=", DoubleToString((c5_close - tp) / slDist, 2));
                           g_signalBar = (int)ratesEntry[0].time;
                           return;
                        }
                     }
                  }
                  else if(DebugMode) Print("SELL REJECTED: TP above entry (bbM=", DoubleToString(bbM, 2), " > close=", DoubleToString(c5_close, 2), ")");
               }
               else if(DebugMode) Print("SELL REJECTED: SL too tight (", DoubleToString(slDist / g_atrValue, 2), "xATR < ", Min_SL_ATR, ")");
            }
         }
         else if(DebugMode) Print("SELL REJECTED: Price too far from swing");
      }
      else if(DebugMode) Print("SELL REJECTED: No recent swing high found");
   }

   // ═══════════════════════════════════════
   // Trend Mode: trend-following leg (v4.0)
   // Buys strength / sells weakness — NO RSI cap.
   // ═══════════════════════════════════════
   if(TrendMode)
   {
      double sepATR = (g_atrValue > 0) ? (spread / g_atrValue) : 0;
      bool trendRegimeUp   = trendUp   && sepATR >=  Trend_MinSep_ATR;
      bool trendRegimeDown = trendDown && sepATR <= -Trend_MinSep_ATR;

      // TP distance chosen so the existing partial trigger (PartialTP_Pct % of TP)
      // lands at Trend_TP_ATR. Remainder rides the wide trail.
      double trendTPDist = (PartialTP_Pct > 0)
                           ? (Trend_TP_ATR / (PartialTP_Pct / 100.0)) * g_atrValue
                           : 2.5 * g_atrValue;
      double maxTrendSL = 2.5 * g_atrValue;

      //--- PULLBACK: prior M15 bar dipped to the fast-MA zone, current bar turns back
      bool pullbackUp = trendRegimeUp
         && ratesM15[1].close < ratesM15[1].open
         && ratesM15[1].low  <= maFast[1] + Trend_Pullback_ATR * g_atrValue
         && ratesEntry[0].close > ratesEntry[0].open
         && ratesEntry[0].high  > ratesEntry[1].high;

      bool pullbackDown = trendRegimeDown
         && ratesM15[1].close > ratesM15[1].open
         && ratesM15[1].high  >= maFast[1] - Trend_Pullback_ATR * g_atrValue
         && ratesEntry[0].close < ratesEntry[0].open
         && ratesEntry[0].low   < ratesEntry[1].low;

      //--- BREAKOUT: current bar extends beyond prior bar in the trend direction
      bool breakoutUp = trendRegimeUp
         && ratesEntry[0].close > ratesEntry[0].open
         && ratesEntry[0].high  > ratesEntry[1].high + Trend_Breakout_ATR * g_atrValue;

      bool breakoutDown = trendRegimeDown
         && ratesEntry[0].close < ratesEntry[0].open
         && ratesEntry[0].low   < ratesEntry[1].low - Trend_Breakout_ATR * g_atrValue;

      //--- Trend BUY (pullback preferred when both qualify on the same bar)
      if(pullbackUp || breakoutUp)
      {
         double sl = (pullbackUp
                      ? MathMin(ratesM15[1].low, ratesEntry[0].low)
                      : ratesEntry[0].low) - Trend_SL_Buffer_ATR * g_atrValue;
         double slDist = ask - sl;
         double minStop = GetMinStopDist();
         if(slDist < minStop) { sl = ask - minStop; slDist = minStop; }
         if(slDist >= Min_SL_ATR * g_atrValue && slDist <= maxTrendSL)
         {
            double tp  = ask + trendTPDist;
            if((tp - ask) < slDist * Min_RR)          // stretch TP so RR >= Min_RR
               tp = ask + slDist * Min_RR;
            double lot = CalcLotSize(slDist);
            if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_BUY, ask, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_BUY, lot, ask, sl, tp, CommentPrefix + "_T_BUY"))
               {
                  g_dailyStats.tradeCount++;
                  Print("TREND BUY (", pullbackUp ? "PULLBACK" : "BREAKOUT",
                        "): close=", DoubleToString(ratesEntry[0].close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                        " SL=", DoubleToString(slDist / g_atrValue, 2), "xATR");
                  g_signalBar = (int)ratesEntry[0].time;
                  return;
               }
            }
            else if(DebugMode) Print("TREND BUY REJECTED: SL ", DoubleToString(slDist / g_atrValue, 2), "xATR");
         }
      }

      //--- Trend SELL
      if(pullbackDown || breakoutDown)
      {
         double sl = (pullbackDown
                      ? MathMax(ratesM15[1].high, ratesEntry[0].high)
                      : ratesEntry[0].high) + Trend_SL_Buffer_ATR * g_atrValue;
         double slDist = sl - bid;
         double minStop = GetMinStopDist();
         if(slDist < minStop) { sl = bid + minStop; slDist = minStop; }
         if(slDist >= Min_SL_ATR * g_atrValue && slDist <= maxTrendSL)
         {
            double tp  = bid - trendTPDist;
            if((bid - tp) < slDist * Min_RR)          // stretch TP so RR >= Min_RR
               tp = bid - slDist * Min_RR;
            double lot = CalcLotSize(slDist);
            if(lot >= 0.01 && VerifyTrade(ORDER_TYPE_SELL, bid, sl, tp, lot))
            {
               if(OpenOrder(ORDER_TYPE_SELL, lot, bid, sl, tp, CommentPrefix + "_T_SELL"))
               {
                  g_dailyStats.tradeCount++;
                  Print("TREND SELL (", pullbackDown ? "PULLBACK" : "BREAKOUT",
                        "): close=", DoubleToString(ratesEntry[0].close, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
                        " SL=", DoubleToString(slDist / g_atrValue, 2), "xATR");
                  g_signalBar = (int)ratesEntry[0].time;
                  return;
               }
            }
            else if(DebugMode) Print("TREND SELL REJECTED: SL ", DoubleToString(slDist / g_atrValue, 2), "xATR");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| New bar check                                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   MqlRates rates[];
   if(CopyRates(_Symbol, EntryTF, 0, 1, rates) < 1) return false;

   if(rates[0].time != g_lastBarTime)
   {
      g_lastBarTime = rates[0].time;
      return true;
   }
   return false;
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
   string info = "=== FXYAMS_Ultimate1 v2.1 ===" + sep;
   info += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   info += " | Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
   info += " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";

   double dd = 0;
   if(g_dailyStats.startingBalance > 0)
      dd = (g_dailyStats.startingBalance - AccountInfoDouble(ACCOUNT_EQUITY))
           / g_dailyStats.startingBalance * 100.0;
   info += "Today: " + IntegerToString(g_dailyStats.tradeCount) + "/" + IntegerToString(MaxDailyTrades);
   string sessName = (g_dailyStats.currentSession == 1) ? "LON" : (g_dailyStats.currentSession == 2) ? "NY" : "---";
   info += " | TP: " + IntegerToString(g_dailyStats.tpHits) + "/" + IntegerToString(MaxTPHits) + " [" + sessName + "]";
   info += " | DD: " + DoubleToString(dd, 2) + "% (limit: " + DoubleToString(MaxDailyLossPct, 1) + "%)" + "\n";

   info += "Open: " + IntegerToString(CountOpenPositions()) + "/" + IntegerToString(MaxPositions) + sep;
   info += "ATR(14): M15=" + DoubleToString(g_atrValue, 1) + " Entry=" + DoubleToString(g_atrEntry, 1) + "\n";
   info += "Session: " + GetSessionStatus() + "\n";
   info += "PartialTP: " + (UsePartialTP ? "ON" : "OFF") + " | Trailing: " + (UseTrailing ? "ON" : "OFF") + " | BE: " + (UseBreakEven ? "ON" : "OFF") + "\n";

   if(g_swingReady)
      info += "Swings: " + IntegerToString(ArraySize(g_swingHighIdx)) + "H / " + IntegerToString(ArraySize(g_swingLowIdx)) + "L\n";

   if(g_dailyStats.tradingStopped)
      info += "*** TRADING STOPPED (daily loss limit) ***\n";
   if(g_dailyStats.tpPause)
      info += "*** TP PAUSE (waiting for next session) ***\n";

   Comment(info);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDaily();

   //--- Detect TPs hit today
   DetectTPHits();

   //--- Daily-loss stop: close everything and halt (intended behavior)
   if(g_dailyStats.tradingStopped)
   {
      CloseAllPositions("DD_CLOSE");
      UpdateComment();
      return;
   }

   //--- Manage open positions (ALWAYS — even on TP pause, so trailing/break-even
   //    keeps protecting open positions; the pause only gates new entries)
   ManageOpenPositions();

   //--- TP pause: no new entries this session, but open positions stay managed
   if(g_dailyStats.tpPause)
   { UpdateComment(); return; }

   //--- Position limit check
   int openPos = CountOpenPositions();
   if(openPos >= MaxPositions)
   { UpdateComment(); return; }

   //--- Heartbeat every ~5 min
   g_heartbeatCount++;
   if(g_heartbeatCount >= 60)
   {
      g_heartbeatCount = 0;
      Print("HEARTBEAT | Bal=$", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
            " Eq=$", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2),
            " Pos=", openPos, " Trades=", g_dailyStats.tradeCount,
            " TPs=", g_dailyStats.tpHits,
            " Swings: H=", ArraySize(g_swingHighIdx), " L=", ArraySize(g_swingLowIdx),
            " ATR: M15=", DoubleToString(g_atrValue, 1), " Entry=", DoubleToString(g_atrEntry, 1),
            " Session: ", GetSessionStatus());
   }

   //--- Refresh swing points once per new M15 bar
   if(IsNewBar())
      UpdateSwingPoints();

   //--- Check entry on every tick (dedup: max one entry per M15 bar)
   //    Required so trend/scalp legs can fire once the forming bar develops
   //    mid-bar (previously evaluated only at bar open -> those legs never fired).
   CheckForEntry();

   UpdateComment();
}
//+------------------------------------------------------------------+
