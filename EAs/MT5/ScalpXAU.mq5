//+------------------------------------------------------------------+
//|                                           ScalpXAU.mq5           |
//|                  FRVP + Price Action XAUUSD Scalper v3.0          |
//|                                                                    |
//|  Strategy:                                                         |
//|  - Fixed Range Volume Profile zones (POC/VAH/VAL/HVN/LVN)       |
//|  - Price Action patterns at FRVP zones (pin, engulf, combo)      |
//|  - Session gating: Asian range, London breakout, NY sweep         |
//|  - MA50/200 trend bias for direction filter                      |
//|  - ATR-based SL + TP with break-even + trailing                  |
//+------------------------------------------------------------------+
#property copyright "FXRE v3.0"
#property version   "3.00"
#property description "XAUUSD FRVP + Price Action Scalper"
#property description "Session-gated entries at Volume Profile zones"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>
#include <FixedRangeVolumeProfile.mqh>
#include <PriceActionPatterns.mqh>
#include <SupportResistance.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
//--- General
input string   Inp_Gen            = "======== GENERAL ========";
input double   RiskPerTradePct    = 1.0;
input double   MaxDailyRiskPct    = 5.0;
input double   MaxSessDDPct       = 5.0;
input int      MaxTradesPerSess   = 40;
input int      MaxPositions       = 3;
input int      BrokerGMTOffset    = -99;
input bool     DebugMode          = false;

//--- Timeframes
input string   Inp_TF             = "======= TIMEFRAMES =======";
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M15;
input ENUM_TIMEFRAMES ProfileTF   = PERIOD_M15;
input int      SwingLookback      = 100;

//--- FRVP Settings
input string   Inp_FRVP           = "===== FRVP SETTINGS ======";
input int      FRVP_Anchors       = 48;            // FRVP lookback bars (48xM15 = 12h)
input double   FRVP_BucketPips    = 0.50;           // FRVP bucket size (price units)
input double   FRVP_ValueAreaPct  = 70.0;           // Value area % (default 70)
input double   FRVP_HVNThreshold  = 0.70;           // HVN = vol >= 70% of POC
input double   FRVP_LVNThreshold  = 0.20;           // LVN = vol <= 20% of POC
input double   FRVP_ZoneTolATR    = 0.30;           // Zone entry tolerance (xATR)
input int      FRVP_RefreshBars   = 6;              // Recompute every N bars

//--- Price Action Settings
input string   Inp_PA             = "===== PRICE ACTION ======";
input double   PA_MinWickATR      = 0.5;            // Pin bar min wick (xATR)
input double   PA_WickBodyRatio   = 2.0;            // Pin bar wick/body ratio
input double   PA_MinBodyATR      = 0.15;           // Engulfing min body (xATR)
input double   PA_MinMoveATR      = 1.0;            // OB flip min move (xATR)
input bool     PA_RequireTrend    = true;            // PA must agree with MA trend

//--- Trend Filter (MA50/200)
input string   Inp_Trend          = "===== TREND FILTER ======";
input bool     EnableTrendFilter  = true;
input int      Trend_MA_Fast      = 50;
input int      Trend_MA_Slow      = 200;

//--- Risk Management
input string   Inp_RM             = "===== RISK MGMT ======";
input bool     UseBreakEven       = true;
input double   BE_ATR_Mult        = 0.6;
input bool     UseTrailing        = true;
input double   TrailStart_ATR     = 0.8;
input double   TrailStep_ATR      = 0.3;
input int      MaxSlippagePts     = 30;
input double   Min_SL_ATR         = 1.0;
input int      MagicNumber        = 241107;
input string   CommentPrefix      = "SCALPX_EA";

//--- Support & Resistance
input string   Inp_SR             = "===== S/R SETTINGS ======";
input bool     EnableSR           = true;           // Use S/R confluence
input double   SR_ZoneATR         = 0.5;            // S/R zone thickness (xATR)
input int      SR_SwingLen        = 2;              // Swing bars each side
input double   SR_ScoreSupport    = 2;              // Confluence score: at support
input double   SR_ScoreResistance = 2;              // Confluence score: at resistance
input double   SR_ScoreMTF        = 1;              // Extra score: multi-TF confirmation

//--- Session Times in GMT
input string   Inp_Time           = "====== SESSION GMT TIMES ====";
input int      Asian_StartH       = 0;
input int      Asian_StartM       = 30;
input int      Asian_EndH         = 3;
input int      Asian_EndM         = 30;
input int      London_StartH      = 7;
input int      London_StartM      = 0;
input int      London_EndH        = 10;
input int      London_EndM        = 0;
input int      NY_StartH          = 13;
input int      NY_StartM          = 30;
input int      NY_EndH            = 16;
input int      NY_EndM            = 30;

//+------------------------------------------------------------------+
//| GLOBALS                                                          |
//+------------------------------------------------------------------+
CTrade         m_trade;
CPositionInfo  m_position;
CAccountInfo   m_account;

//--- FRVP state
FRVPState      g_frvp;

//--- S/R state
SRState        g_sr;

//--- Indicators
int            hMAFast = INVALID_HANDLE;
int            hMASlow = INVALID_HANDLE;

//--- Session tracking
enum SessionType { SESS_NONE = -1, SESS_ASIAN = 0, SESS_LONDON = 1, SESS_NY = 2 };
SessionType    g_currentSession = SESS_NONE;

//--- Asian range
double         g_asianHigh = 0;
double         g_asianLow  = 0;
datetime       g_asianSessionStart = 0;
bool           g_asianRangeReady = false;

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

//--- Misc
double         g_atrValue = 0;
datetime       g_lastBarTime = 0;
datetime       g_lastEntryBarTime = 0;
int            g_tickCount = 0;
string         g_commentPrefix = "XAU";
int            g_frvpRefreshCounter = 0;

//--- Broker GMT offset
int            g_brokerGMTOffset = 0;

//--- Fill mode
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_FOK;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0)
      Print("WARNING: ScalpXAU is designed for XAUUSD. Current symbol: ", _Symbol);

   m_trade.SetExpertMagicNumber(MagicNumber);
   m_trade.SetDeviationInPoints(MaxSlippagePts);
   m_trade.SetAsyncMode(false);

   //--- Fill mode
   g_fillMode = ORDER_FILLING_FOK;
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(filling & SYMBOL_FILLING_FOK)      g_fillMode = ORDER_FILLING_FOK;
   else if(filling & SYMBOL_FILLING_IOC) g_fillMode = ORDER_FILLING_IOC;
   else                                  g_fillMode = ORDER_FILLING_RETURN;
   m_trade.SetTypeFilling(g_fillMode);
   Print("Fill mode: ", EnumToString(g_fillMode));

   //--- Trend MA handles
   hMAFast = iMA(_Symbol, EntryTF, Trend_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, EntryTF, Trend_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);
   if(hMAFast == INVALID_HANDLE || hMASlow == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create trend MA handles");
      return INIT_FAILED;
   }

   //--- Initialize FRVP
   g_frvp.lastCompute = 0;
   g_frvp.current.valid = false;
   g_frvpRefreshCounter = FRVP_RefreshBars; // force first compute

   //--- Initialize S/R
   g_sr.lastScan = 0;
   g_sr.current.valid = false;

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

   //--- Broker GMT offset
   g_brokerGMTOffset = BrokerGMTOffset;
   if(g_brokerGMTOffset == -99)
   {
      g_brokerGMTOffset = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(g_brokerGMTOffset < -14) g_brokerGMTOffset = -14;
      if(g_brokerGMTOffset > 14)  g_brokerGMTOffset = 14;
      Print("Broker GMT offset: AUTO = +", g_brokerGMTOffset);
   }

   Print("ScalpXAU v3.0 initialized on ", _Symbol, " ", EnumToString(EntryTF));
   Print("FRVP: anchors=", FRVP_Anchors, " bucket=", FRVP_BucketPips,
         " VA%=", FRVP_ValueAreaPct, " refresh every ", FRVP_RefreshBars, " bars");
   Print("PA: pin_wick=", PA_MinWickATR, "xATR wick/body>=", PA_WickBodyRatio,
         " engulf_body>=", PA_MinBodyATR, "xATR trend_gate=", PA_RequireTrend ? "ON" : "OFF");
   Print("Magic: ", MagicNumber, " | Risk: ", RiskPerTradePct, "% per trade, max ", MaxDailyRiskPct, "% daily");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(hMAFast != INVALID_HANDLE) IndicatorRelease(hMAFast);
   if(hMASlow != INVALID_HANDLE) IndicatorRelease(hMASlow);
   Comment("");
   Print("ScalpXAU deinitialized (reason: ", reason, ")");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDaily();

   if(g_stats.tradingStopped)
   {
      CloseAllPositions("DD_LIMIT");
      UpdateComment();
      return;
   }

   g_atrValue = CalcATR(14, EntryTF);
   g_tickCount++;

   if(IsNewBar())
   {
      UpdateSwingPoints();
      DetectSessionLevels();

      //--- Refresh FRVP periodically
      g_frvpRefreshCounter++;
      if(g_frvpRefreshCounter >= FRVP_RefreshBars)
      {
         g_frvpRefreshCounter = 0;
         if(RefreshFRVP())
            FRVP_PrintProfile(g_frvp.current, _Symbol);
      }

      //--- Refresh S/R every 12 bars (~3h on M15)
      if(EnableSR && g_frvpRefreshCounter % 2 == 0)
      {
         if(SR_Scan(g_sr, _Symbol, EntryTF, PERIOD_M15, g_atrValue, SR_ZoneATR, SR_SwingLen))
         {
            if(DebugMode) SR_PrintLevels(g_sr.current, _Symbol);
         }
      }

      Print("NEWBAR | Sess=", GetSessionName(GetCurrentSession()),
            " GMT=", GetGMTHour(), ":", StringFormat("%02d", GetGMTMin()),
            " ATR=", DoubleToString(g_atrValue, 1),
            " FRVP=", g_frvp.current.valid ? "OK" : "N/A",
            " POC=", g_frvp.current.valid ? DoubleToString(g_frvp.current.poc, 2) : "---");
   }

   if(g_tickCount >= 100)
   {
      g_tickCount = 0;
      Print("HB | Bal=$", DoubleToString(m_account.Balance(), 2),
            " Eq=$", DoubleToString(m_account.Equity(), 2),
            " Pos=", CountOpenPositions(),
            " Trades=", g_stats.tradeCount,
            " Sess=", GetSessionName(g_currentSession));
   }

   ManagePositions();

   if(CountOpenPositions() >= MaxPositions) { UpdateComment(); return; }

   CheckEntry();

   UpdateComment();
}

//+------------------------------------------------------------------+
//| Refresh FRVP computation                                         |
//+------------------------------------------------------------------+
bool RefreshFRVP()
{
   double bucketPips = FRVP_BucketPips;
   if(bucketPips <= 0) bucketPips = 0.50; // default for gold

   bool ok = FRVP_Compute(g_frvp, _Symbol, ProfileTF, FRVP_Anchors,
                           bucketPips, FRVP_ValueAreaPct,
                           FRVP_HVNThreshold, FRVP_LVNThreshold);
   if(!ok && DebugMode) Print("FRVP compute failed");
   return ok;
}

//+------------------------------------------------------------------+
//| Check for entry signals                                          |
//+------------------------------------------------------------------+
void CheckEntry()
{
   datetime entryBar = iTime(_Symbol, EntryTF, 0);
   if(entryBar == g_lastEntryBarTime) return;
   g_lastEntryBarTime = entryBar;

   g_currentSession = GetCurrentSession();
   if(g_currentSession == SESS_NONE) return;

   //--- Reset session counter on change
   if(g_stats.lastSession != g_currentSession)
   {
      g_stats.sessionTradeCount = 0;
      g_stats.sessionStartEquity = m_account.Equity();
      g_stats.sessTradingStopped = false;
      g_stats.lastSession = g_currentSession;
      Print("SESS START | ", GetSessionName(g_currentSession),
            " Eq=$", DoubleToString(g_stats.sessionStartEquity, 2));
   }

   //--- Session DD limit
   if(!g_stats.sessTradingStopped && g_stats.sessionStartEquity > 0)
   {
      double ddPct = (g_stats.sessionStartEquity - m_account.Equity()) / g_stats.sessionStartEquity * 100.0;
      if(ddPct >= MaxSessDDPct)
      {
         g_stats.sessTradingStopped = true;
         Print("*** SESSION DD LIMIT: ", DoubleToString(ddPct, 2), "% ***");
      }
   }
   if(g_stats.sessTradingStopped) return;
   if(g_stats.sessionTradeCount >= MaxTradesPerSess) return;

   //--- Need FRVP valid for entries
   if(!g_frvp.current.valid)
   {
      if(DebugMode) Print("FRVP not ready — skipping entry");
      return;
   }

   //--- Get trend direction
   int trendDir = GetTrendDirection();

   //--- Session-specific logic
   switch(g_currentSession)
   {
      case SESS_ASIAN:
         CheckAsianEntry(trendDir);
         break;
      case SESS_LONDON:
         CheckLondonEntry(trendDir);
         break;
      case SESS_NY:
         CheckNYEntry(trendDir);
         break;
   }
}

//+------------------------------------------------------------------+
//| Get trend direction from MA50/200                                |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   if(!EnableTrendFilter) return 0; // no filter = both directions OK

   double maF[], maSlow[];
   ArraySetAsSeries(maF, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(hMAFast, 0, 0, 3, maF) < 3) return 0;
   if(CopyBuffer(hMASlow, 0, 0, 3, maSlow) < 3) return 0;

   if(maF[0] > maSlow[0] && maF[1] > maSlow[1]) return +1;
   if(maF[0] < maSlow[0] && maF[1] < maSlow[1]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| ASIAN SESSION: Range at FRVP zones                               |
//| Trade pin bars at VAL (buy) or VAH (sell) during ranging Asian   |
//+------------------------------------------------------------------+
void CheckAsianEntry(int trendDir)
{
   if(!g_asianRangeReady || g_asianHigh <= 0 || g_asianLow <= 0) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 5, rates) < 3) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   double zoneTol = atr * FRVP_ZoneTolATR;
   FRVPResult prof = g_frvp.current;

   //--- Get price action on last 2 closed bars
   PASignal pa = PA_AggregateScore(rates, 5, atr,
                                    prof.vah, prof.val,
                                    PA_MinWickATR, PA_WickBodyRatio,
                                    PA_MinBodyATR, PA_MinMoveATR);

   //--- BUY: price at VAL + bullish PA + not in downtrend + support nearby
   if(pa.direction == +1)
   {
      bool atVAL = FRVP_AtVAL(prof, bid, zoneTol);
      bool atLVN = FRVP_NearLVN(prof, bid, zoneTol) >= 0;
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);
      bool atSupp = EnableSR ? SR_AtSupport(g_sr.current, bid, zoneTol) : true;
      bool atAsianLow = MathAbs(bid - g_asianLow) <= zoneTol;

      if((atVAL || atLVN || atSupp || atAsianLow) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportBelow(g_sr.current, bid);
            srTP = SR_NearestResistanceAbove(g_sr.current, bid);
         }
         ExecuteTrade(ORDER_TYPE_BUY, bid, atr, "ASIAN", pa.patternName, srSL, srTP);
      }
   }

   //--- SELL: price at VAH + bearish PA + not in uptrend + resistance nearby
   if(pa.direction == -1)
   {
      bool atVAH = FRVP_AtVAH(prof, ask, zoneTol);
      bool atLVN = FRVP_NearLVN(prof, ask, zoneTol) >= 0;
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);
      bool atRes = EnableSR ? SR_AtResistance(g_sr.current, ask, zoneTol) : true;
      bool atAsianHigh = MathAbs(ask - g_asianHigh) <= zoneTol;

      if((atVAH || atLVN || atRes || atAsianHigh) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportAbove(g_sr.current, ask);
            srTP = SR_NearestResistanceBelow(g_sr.current, ask);
         }
         ExecuteTrade(ORDER_TYPE_SELL, ask, atr, "ASIAN", pa.patternName, srSL, srTP);
      }
   }
}

//+------------------------------------------------------------------+
//| LONDON SESSION: Breakout with FRVP confirmation                  |
//| Trade breakouts from Asian range with BOS at FRVP levels         |
//+------------------------------------------------------------------+
void CheckLondonEntry(int trendDir)
{
   if(!g_asianRangeReady || g_asianHigh <= 0 || g_asianLow <= 0) return;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 15, rates) < 10) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   FRVPResult prof = g_frvp.current;
   double zoneTol = atr * FRVP_ZoneTolATR;

   //--- Detect breakout from Asian range
   int breakDir = 0;
   int breakBar = -1;

   for(int c = 1; c <= 8; c++)
   {
      if(c >= ArraySize(rates)) break;
      if(rates[c].close > g_asianHigh && rates[c].close > rates[c].open)
      { breakDir = 1; breakBar = c; break; }
      if(rates[c].close < g_asianLow && rates[c].close < rates[c].open)
      { breakDir = -1; breakBar = c; break; }
   }
   if(breakDir == 0) return;

   //--- Look for retest after breakout
   for(int c = breakBar - 1; c >= 1 && c > breakBar - 5; c--)
   {
      if(c <= 0 || c >= ArraySize(rates)) continue;

      PASignal pa = PA_DetectPinBar(rates[c], rates[c + 1], atr, PA_MinWickATR, PA_WickBodyRatio);
      if(pa.direction == 0)
         pa = PA_DetectEngulfing(rates[c], rates[c + 1], atr, PA_MinBodyATR);

      if(breakDir == 1) // Bull breakout
      {
         if(pa.direction == +1 && rates[c].close > g_asianHigh)
         {
            //--- Bonus: price is at a FRVP zone (VAL support or HVN)
            bool frvpConfirm = FRVP_AtVAL(prof, bid, zoneTol * 2) ||
                               FRVP_NearHVN(prof, bid, zoneTol * 2) >= 0 ||
                               bid <= prof.vah; // inside VA = acceptable

            bool trendOk = (!PA_RequireTrend || trendDir >= 0);

            if(frvpConfirm && trendOk)
            {
               double srSL = 0, srTP = 0;
               if(EnableSR && g_sr.current.valid)
               {
                  srSL = SR_NearestSupportBelow(g_sr.current, bid);
                  srTP = SR_NearestResistanceAbove(g_sr.current, bid);
               }
               ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "LONDON", pa.patternName, srSL, srTP);
               return;
            }
         }
      }
      else if(breakDir == -1) // Bear breakout
      {
         if(pa.direction == -1 && rates[c].close < g_asianLow)
         {
            bool frvpConfirm = FRVP_AtVAH(prof, ask, zoneTol * 2) ||
                               FRVP_NearHVN(prof, ask, zoneTol * 2) >= 0 ||
                               ask >= prof.val;

            bool trendOk = (!PA_RequireTrend || trendDir <= 0);

            if(frvpConfirm && trendOk)
            {
               double srSL = 0, srTP = 0;
               if(EnableSR && g_sr.current.valid)
               {
                  srSL = SR_NearestSupportAbove(g_sr.current, ask);
                  srTP = SR_NearestResistanceBelow(g_sr.current, ask);
               }
               ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "LONDON", pa.patternName, srSL, srTP);
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| NY SESSION: Liquidity sweep + FRVP zone reversal                 |
//| Sweep highs/lows, then reverse at FRVP POC/VAH/VAL with PA      |
//+------------------------------------------------------------------+
void CheckNYEntry(int trendDir)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 20, rates) < 10) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   if(atr <= 0) return;

   FRVPResult prof = g_frvp.current;
   double zoneTol = atr * FRVP_ZoneTolATR;

   //--- Detect sweep: wick above/below recent high/low with rejection
   int bar = 1; // last closed
   if(bar >= ArraySize(rates)) return;

   double barHigh = rates[bar].high;
   double barLow  = rates[bar].low;
   double barClose = rates[bar].close;
   double barOpen  = rates[bar].open;
   double wickUp   = barHigh - MathMax(barClose, barOpen);
   double wickDown = MathMin(barClose, barOpen) - barLow;
   double body     = MathAbs(barClose - barOpen);
   double range    = barHigh - barLow;

   if(range <= 0) return;

   //--- Bullish sweep: long lower wick (swept lows) + rejection
   bool bullSweep = (wickDown >= atr * 0.3 && wickDown >= body * 1.5 && barClose > barOpen);

   //--- Bearish sweep: long upper wick + rejection
   bool bearSweep = (wickUp >= atr * 0.3 && wickUp >= body * 1.5 && barClose < barOpen);

   //--- Check if sweep targets FRVP zone
   if(bullSweep)
   {
      //--- Price swept below and is now at/below VAL or POC
      bool atPOC  = FRVP_AtPOC(prof, bid, zoneTol * 2);
      bool atVAL  = FRVP_AtVAL(prof, bid, zoneTol * 2);
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      //--- Also: PA confirmation from the bar itself
      PASignal pa = PA_DetectPinBar(rates[bar], rates[bar + 1], atr, PA_MinWickATR, PA_WickBodyRatio);

      if((atPOC || atVAL || pa.direction == +1) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportBelow(g_sr.current, bid);
            srTP = SR_NearestResistanceAbove(g_sr.current, bid);
         }
         ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "NY", "Sweep_BULL+" + (atPOC ? "POC" : atVAL ? "VAL" : pa.patternName), srSL, srTP);
         return;
      }
   }

   if(bearSweep)
   {
      bool atPOC  = FRVP_AtPOC(prof, ask, zoneTol * 2);
      bool atVAH  = FRVP_AtVAH(prof, ask, zoneTol * 2);
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      PASignal pa = PA_DetectPinBar(rates[bar], rates[bar + 1], atr, PA_MinWickATR, PA_WickBodyRatio);

      if((atPOC || atVAH || pa.direction == -1) && trendOk)
      {
         double srSL = 0, srTP = 0;
         if(EnableSR && g_sr.current.valid)
         {
            srSL = SR_NearestSupportAbove(g_sr.current, ask);
            srTP = SR_NearestResistanceBelow(g_sr.current, ask);
         }
         ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "NY", "Sweep_BEAR+" + (atPOC ? "POC" : atVAH ? "VAH" : pa.patternName), srSL, srTP);
         return;
      }
   }

   //--- Also: direct FRVP zone reaction (no sweep required for POC)
   PASignal pa = PA_AggregateScore(rates, 20, atr,
                                    prof.vah, prof.val,
                                    PA_MinWickATR, PA_WickBodyRatio,
                                    PA_MinBodyATR, PA_MinMoveATR);

   if(pa.strength >= 3) // at least medium-strength PA
   {
      if(pa.direction == +1 && (FRVP_AtPOC(prof, bid, zoneTol) || SR_AtSupport(g_sr.current, bid, zoneTol)))
      {
         bool trendOk = (!PA_RequireTrend || trendDir >= 0);
         if(trendOk)
         {
            double srSL = 0, srTP = 0;
            if(EnableSR && g_sr.current.valid)
            {
               srSL = SR_NearestSupportBelow(g_sr.current, bid);
               srTP = SR_NearestResistanceAbove(g_sr.current, bid);
            }
            ExecuteTrade(ORDER_TYPE_BUY, ask, atr, "NY_POC", pa.patternName, srSL, srTP);
         }
      }
      else if(pa.direction == -1 && (FRVP_AtPOC(prof, ask, zoneTol) || SR_AtResistance(g_sr.current, ask, zoneTol)))
      {
         bool trendOk = (!PA_RequireTrend || trendDir <= 0);
         if(trendOk)
         {
            double srSL = 0, srTP = 0;
            if(EnableSR && g_sr.current.valid)
            {
               srSL = SR_NearestSupportAbove(g_sr.current, ask);
               srTP = SR_NearestResistanceBelow(g_sr.current, ask);
            }
            ExecuteTrade(ORDER_TYPE_SELL, bid, atr, "NY_POC", pa.patternName, srSL, srTP);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Execute a trade with risk-based sizing                           |
//| srSL/srTP = S/R-derived levels (0 = use ATR-based defaults)      |
//+------------------------------------------------------------------+
void ExecuteTrade(int orderType, double entryPrice, double atr,
                  string sessionTag, string paTag,
                  double srSL = 0, double srTP = 0)
{
   if(atr <= 0) return;

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double slDist = atr * Min_SL_ATR;
   if(slDist < Min_SL_ATR * atr) slDist = Min_SL_ATR * atr;

   double tpDist = atr * 2.0;
   FRVPResult prof = g_frvp.current;

   if(orderType == ORDER_TYPE_BUY)
   {
      double sl = entryPrice - slDist;
      double tp = entryPrice + tpDist;

      //--- S/R SL: place below nearest support
      if(srSL > 0 && srSL < entryPrice)
      {
         double srDist = entryPrice - srSL;
         if(srDist >= Min_SL_ATR * atr && srDist <= atr * 3.0)
            sl = srSL - atr * 0.2; // buffer below support
      }

      //--- S/R TP: target nearest resistance above
      if(srTP > 0 && srTP > entryPrice)
      {
         double srTDDist = srTP - entryPrice;
         if(srTDDist >= slDist * 1.2 && srTDDist <= atr * 5.0)
            tp = srTP;
      }

      //--- Fallback: FRVP zone as TP
      if(tp == entryPrice + tpDist && prof.valid)
      {
         double nearestZone = prof.vah;
         if(prof.poc > entryPrice + slDist * 1.5)
            nearestZone = prof.poc;
         if(nearestZone > entryPrice + slDist * 0.5 && nearestZone < entryPrice + atr * 4.0)
            tp = nearestZone;
      }

      //--- Ensure min 1.5:1 RR
      slDist = entryPrice - sl;
      if(tp - entryPrice < slDist * 1.5) tp = entryPrice + slDist * 1.5;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lot = CalcLotSizeRisk(entryPrice - sl, RiskPerTradePct);
      if(lot <= 0) return;

      if(VerifyTrade(ORDER_TYPE_BUY, entryPrice, sl, tp, lot))
      {
         string comment = CommentPrefix + "_FRVP_BUY_" + sessionTag;
         if(OpenOrder(ORDER_TYPE_BUY, lot, entryPrice, sl, tp, comment))
         {
            g_stats.tradeCount++;
            g_stats.sessionTradeCount++;
            Print("FRVP BUY ", sessionTag, ": ", paTag,
                  " price=", DoubleToString(entryPrice, digits),
                  " SL=", DoubleToString(sl, digits),
                  " TP=", DoubleToString(tp, digits),
                  " POC=", DoubleToString(prof.poc, digits),
                  " SR_SL=", DoubleToString(srSL, digits),
                  " SR_TP=", DoubleToString(srTP, digits));
         }
      }
   }
   else if(orderType == ORDER_TYPE_SELL)
   {
      double sl = entryPrice + slDist;
      double tp = entryPrice - tpDist;

      //--- S/R SL: place above nearest resistance
      if(srSL > 0 && srSL > entryPrice)
      {
         double srDist = srSL - entryPrice;
         if(srDist >= Min_SL_ATR * atr && srDist <= atr * 3.0)
            sl = srSL + atr * 0.2; // buffer above resistance
      }

      //--- S/R TP: target nearest support below
      if(srTP > 0 && srTP < entryPrice)
      {
         double srTDDist = entryPrice - srTP;
         if(srTDDist >= slDist * 1.2 && srTDDist <= atr * 5.0)
            tp = srTP;
      }

      //--- Fallback: FRVP zone as TP
      if(tp == entryPrice - tpDist && prof.valid)
      {
         double nearestZone = prof.val;
         if(prof.poc < entryPrice - slDist * 1.5)
            nearestZone = prof.poc;
         if(nearestZone < entryPrice - slDist * 0.5 && nearestZone > entryPrice - atr * 4.0)
            tp = nearestZone;
      }

      slDist = sl - entryPrice;
      if(entryPrice - tp < slDist * 1.5) tp = entryPrice - slDist * 1.5;

      sl = NormalizeDouble(sl, digits);
      tp = NormalizeDouble(tp, digits);

      double lot = CalcLotSizeRisk(sl - entryPrice, RiskPerTradePct);
      if(lot <= 0) return;

      if(VerifyTrade(ORDER_TYPE_SELL, entryPrice, sl, tp, lot))
      {
         string comment = CommentPrefix + "_FRVP_SELL_" + sessionTag;
         if(OpenOrder(ORDER_TYPE_SELL, lot, entryPrice, sl, tp, comment))
         {
            g_stats.tradeCount++;
            g_stats.sessionTradeCount++;
            Print("FRVP SELL ", sessionTag, ": ", paTag,
                  " price=", DoubleToString(entryPrice, digits),
                  " SL=", DoubleToString(sl, digits),
                  " TP=", DoubleToString(tp, digits),
                  " POC=", DoubleToString(prof.poc, digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Track Asian range                                                |
//+------------------------------------------------------------------+
void TrackAsianRange()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 100, rates) < 20) return;

   g_asianHigh = 0;
   g_asianLow  = 1e9;
   g_asianRangeReady = false;
   int barsInSession = 0;

   for(int i = 0; i < ArraySize(rates); i++)
   {
      MqlDateTime dt;
      TimeToStruct(rates[i].time, dt);
      int hourGMT = dt.hour - g_brokerGMTOffset;
      if(hourGMT < 0) hourGMT += 24;
      int minuteGMT = dt.min;

      bool inAsian = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         inAsian = true;

      if(inAsian)
      {
         if(rates[i].high > g_asianHigh) g_asianHigh = rates[i].high;
         if(rates[i].low  < g_asianLow)  g_asianLow  = rates[i].low;
         barsInSession++;
      }
      else if(barsInSession > 0) break;
   }

   if(g_asianHigh > 0 && g_asianLow < 1e8 && barsInSession >= 3)
      g_asianRangeReady = true;
}

//+------------------------------------------------------------------+
//| Detect session levels                                            |
//+------------------------------------------------------------------+
void DetectSessionLevels()
{
   SessionType sess = GetCurrentSession();

   if(sess == SESS_ASIAN || sess == SESS_LONDON)
   {
      int hourGMT = GetGMTHour();
      int minuteGMT = GetGMTMin();
      bool asianOngoing = false;
      if((hourGMT == Asian_StartH && minuteGMT >= Asian_StartM) ||
         (hourGMT > Asian_StartH && hourGMT < Asian_EndH) ||
         (hourGMT == Asian_EndH && minuteGMT <= Asian_EndM))
         asianOngoing = true;

      if(!asianOngoing && g_asianSessionStart > 0)
      {
         TrackAsianRange();
         g_asianSessionStart = 0;
      }
      if(asianOngoing && g_asianSessionStart == 0)
      {
         MqlDateTime asianDt;
         TimeTradeServer(asianDt);
         g_asianSessionStart = StructToTime(asianDt);
         g_asianHigh = 0;
         g_asianLow  = 1e9;
         g_asianRangeReady = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Update swing points                                              |
//+------------------------------------------------------------------+
void UpdateSwingPoints()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, SwingLookback, rates) < 50) return;
   // Swing points are used for Asian range detection only now
}

//+------------------------------------------------------------------+
//| Utility functions                                                |
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

SessionType GetCurrentSession()
{
   int hourGMT = GetGMTHour();
   int minuteGMT = GetGMTMin();
   int timeMinutes = hourGMT * 60 + minuteGMT;

   int asianStart  = Asian_StartH  * 60 + Asian_StartM;
   int asianEnd    = Asian_EndH    * 60 + Asian_EndM;
   int londonStart = London_StartH * 60 + London_StartM;
   int londonEnd   = London_EndH   * 60 + London_EndM;
   int nyStart     = NY_StartH     * 60 + NY_StartM;
   int nyEnd       = NY_EndH       * 60 + NY_EndM;

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
      g_frvpRefreshCounter = FRVP_RefreshBars; // force recompute
      Print("--- Daily reset. Balance: ", g_stats.startingBalance, " ---");
   }

   if(!g_stats.tradingStopped && g_stats.startingBalance > 0)
   {
      double ddPct = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
      if(ddPct >= MaxDailyRiskPct)
      {
         g_stats.tradingStopped = true;
         Print("*** MAX DAILY LOSS: ", DoubleToString(ddPct, 2), "% ***");
      }
   }
}

//+------------------------------------------------------------------+
//| Position management                                              |
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

      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double tp    = PositionGetDouble(POSITION_TP);
      long type    = PositionGetInteger(POSITION_TYPE);
      double curPrice = (type == POSITION_TYPE_BUY) ?
                        SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                        SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      if(UseBreakEven)
      {
         double beDist = BE_ATR_Mult * g_atrValue;
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

      if(UseTrailing)
      {
         double trailStart = TrailStart_ATR * g_atrValue;
         double trailStep  = TrailStep_ATR * g_atrValue;

         if(type == POSITION_TYPE_BUY)
         {
            double profitDist = curPrice - entry;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice - trailStep, digits);
               if(newSL > sl + point) ModifySL(ticket, newSL);
            }
         }
         else
         {
            double profitDist = entry - curPrice;
            if(profitDist >= trailStart)
            {
               double newSL = NormalizeDouble(curPrice + trailStep, digits);
               if(newSL < sl - point || sl == 0) ModifySL(ticket, newSL);
            }
         }
      }
   }
}

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
         if(DebugMode) Print("CloseAll: failed, err=", GetLastError());
   }
}

double CalcLotSizeRisk(double slDist, double riskPct)
{
   if(slDist <= 0) return 0;
   if(g_atrValue > 0 && slDist < Min_SL_ATR * g_atrValue) slDist = Min_SL_ATR * g_atrValue;

   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickVal <= 0 || tickSize <= 0) return 0;

   double riskAmount = m_account.Balance() * riskPct / 100.0;
   double slTicks = slDist / tickSize;
   double lot = riskAmount / (slTicks * tickVal);
   lot = NormalizeDouble(lot, 2);

   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep > 0) lot = MathFloor(lot / vstep + 1e-9) * vstep;

   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > 0)
   {
      double volCap = (m_account.Balance() / 10000.0) * 30000.0 / price;
      if(volCap < maxVol) maxVol = volCap;
   }
   if(vstep > 0) maxVol = MathFloor(maxVol / vstep) * vstep;

   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   return MathMax(minVol, MathMin(lot, maxVol));
}

bool VerifyTrade(int type, double price, double sl, double tp, double lot)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   if(lot <= 0) return false;
   if(type == ORDER_TYPE_BUY && price < bid * 0.99) return false;
   if(type == ORDER_TYPE_SELL && price > ask * 1.01) return false;

   if(type == ORDER_TYPE_BUY) { if(sl >= price) return false; if(tp > 0 && tp <= price) return false; }
   if(type == ORDER_TYPE_SELL) { if(sl <= price) return false; if(tp > 0 && tp >= price) return false; }

   double slPips = MathAbs(price - sl);
   double tpPips = MathAbs(tp - price);
   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(slPips < minDist && slPips > 0) return false;
   if(tpPips < minDist && tpPips > 0) return false;

   return true;
}

bool OpenOrder(int type, double volume, double price, double sl, double tp, string comment)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   price = NormalizeDouble(price, digits);
   sl    = NormalizeDouble(sl, digits);
   tp    = NormalizeDouble(tp, digits);

   if(!m_trade.PositionOpen(_Symbol, (ENUM_ORDER_TYPE)type, volume, price, sl, tp, comment))
   {
      Print("ORDER FAILED: ", comment, " err=", GetLastError(), " vol=", volume,
            " price=", price, " sl=", sl, " tp=", tp);
      return false;
   }
   Print("ORDER OK: ", comment, " vol=", volume, " price=", price, " sl=", sl, " tp=", tp);
   return true;
}

void ModifySL(ulong ticket, double newSL)
{
   if(PositionSelectByTicket(ticket))
   {
      double currentSL = PositionGetDouble(POSITION_SL);
      if(MathAbs(newSL - currentSL) < SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 2) return;
      double tp = PositionGetDouble(POSITION_TP);
      m_trade.PositionModify(ticket, newSL, tp);
   }
}

//+------------------------------------------------------------------+
//| Chart comment                                                    |
//+------------------------------------------------------------------+
string RepeatStr(string s, int n) { string r = ""; for(int i = 0; i < n; i++) r += s; return r; }

void UpdateComment()
{
   string sep = "\n" + RepeatStr("-", 30) + "\n";
   string info = "=== ScalpXAU v3.0 FRVP ===" + sep;
   info += "Symbol: " + _Symbol + " | TF: " + EnumToString(EntryTF) + "\n";
   info += "Balance: $" + DoubleToString(m_account.Balance(), 2);
   info += " | Equity: $" + DoubleToString(m_account.Equity(), 2);
   info += " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";

   double dd = 0;
   if(g_stats.startingBalance > 0)
      dd = (g_stats.startingBalance - m_account.Equity()) / g_stats.startingBalance * 100.0;
   info += "Today: " + IntegerToString(g_stats.tradeCount);
   info += " | Session: " + IntegerToString(g_stats.sessionTradeCount) + "/" + IntegerToString(MaxTradesPerSess);
   info += " | DD: " + DoubleToString(dd, 2) + "%" + sep;

   info += "Session: " + GetSessionName(g_currentSession) + "\n";
   if(g_asianRangeReady)
      info += "Asian Range: H=" + DoubleToString(g_asianHigh, 2) + " L=" + DoubleToString(g_asianLow, 2) + "\n";

   //--- FRVP info
   if(g_frvp.current.valid)
   {
      info += "FRVP: POC=" + DoubleToString(g_frvp.current.poc, 2);
      info += " VAH=" + DoubleToString(g_frvp.current.vah, 2);
      info += " VAL=" + DoubleToString(g_frvp.current.val, 2);
      info += " Zones=" + IntegerToString(g_frvp.current.zoneCount) + "\n";
   }
   else
   {
      info += "FRVP: computing...\n";
   }

   //--- S/R info
   if(EnableSR && g_sr.current.valid)
   {
      info += "S/R: S=" + IntegerToString(g_sr.current.supportCount);
      info += " R=" + IntegerToString(g_sr.current.resistanceCount);
      if(g_sr.current.supportCount > 0)
         info += " nearestS=" + DoubleToString(g_sr.current.supports[0].price, 2);
      if(g_sr.current.resistanceCount > 0)
         info += " nearestR=" + DoubleToString(g_sr.current.resistances[0].price, 2);
      info += "\n";
   }

   info += "ATR(14): " + DoubleToString(g_atrValue, 1) + "\n";
   info += "Open: " + IntegerToString(CountOpenPositions()) + sep;
   info += "Trailing: " + (UseTrailing ? "ON" : "OFF") + " | BE: " + (UseBreakEven ? "ON" : "OFF") + "\n";

   if(g_stats.tradingStopped) info += "*** TRADING STOPPED (daily loss limit) ***\n";
   if(g_stats.sessTradingStopped) info += "*** SESSION STOPPED (session DD limit) ***\n";

   Comment(info);
}
//+------------------------------------------------------------------+
