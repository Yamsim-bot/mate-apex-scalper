//+------------------------------------------------------------------+
//|                                    ScalpXAU_Compact.mq5          |
//|               FRVP + Price Action Scalper - 2GB VPS Optimized    |
//|                                                                    |
//|  Strategy:                                                         |
//|  - FRVP zones (POC/VAH/VAL) - reduced lookback (25 bars)        |
//|  - Price Action patterns (pin bars, engulfing)                   |
//|  - Session gating (London/NY only)                               |
//|  - ATR-based SL + TP with break-even + trailing                  |
//|                                                                    |
//|  OPTIMIZED: Removed VP-Pro, AsiaVP, reduced memory footprint     |
//+------------------------------------------------------------------+
#property copyright "FXRE Compact v3.0"
#property version   "3.21"
#property description "XAUUSD FRVP Scalper - 2GB VPS Optimized"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/AccountInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                 |
//+------------------------------------------------------------------+
input string   Inp_Gen            = "======== GENERAL ========";
input double   RiskPerTradePct    = 0.5;
input double   MaxDailyRiskPct    = 2.0;
input int      MaxTradesPerSess   = 3;
input int      MaxPositions       = 1;
input int      BrokerGMTOffset    = 2;
input bool     DebugMode          = false;

//--- Timeframes
input string   Inp_TF             = "======= TIMEFRAMES =======";
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M15;
input int      FRVP_Anchors       = 25;            // FRVP lookback bars (25xM15 = 6h)
input double   FRVP_BucketPips    = 0.50;
input double   FRVP_ValueAreaPct  = 70.0;
input int      FRVP_RefreshBars   = 6;             // Recompute every N bars

//--- Price Action
input string   Inp_PA             = "===== PRICE ACTION ======";
input double   PA_MinWickATR      = 0.5;
input double   PA_WickBodyRatio   = 2.0;
input double   PA_MinBodyATR      = 0.15;
input bool     PA_RequireTrend    = true;

//--- Trend Filter
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
input string   CommentPrefix      = "SCALPX_C";

//--- Session Times (GMT)
input string   Inp_Time           = "====== SESSION GMT TIMES ====";
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

//--- FRVP state (minimal memory)
double         g_poc = 0;
double         g_vah = 0;
double         g_val = 0;
bool           g_frvpValid = false;
datetime       g_lastCompute = 0;

//--- Indicators
int            hMAFast = INVALID_HANDLE;
int            hMASlow = INVALID_HANDLE;

//--- Session tracking
enum SessionType { SESS_NONE = -1, SESS_LONDON = 0, SESS_NY = 1 };
SessionType    g_currentSession = SESS_NONE;

//--- Daily stats
int            g_tradeCount = 0;
int            g_sessionTradeCount = 0;
SessionType    g_lastSession = SESS_NONE;
double         g_sessionStartEquity = 0;

//--- Misc
double         g_atrValue = 0;
datetime       g_lastBarTime = 0;
datetime       g_lastEntryBarTime = 0;
int            g_frvpRefreshCounter = 0;
int            g_brokerGMTOffset = 0;
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_FOK;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
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

   //--- Trend MA handles
   hMAFast = iMA(_Symbol, EntryTF, Trend_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, EntryTF, Trend_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);

   //--- Broker GMT offset
   g_brokerGMTOffset = BrokerGMTOffset;
   if(g_brokerGMTOffset == -99)
   {
      g_brokerGMTOffset = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(g_brokerGMTOffset < -14) g_brokerGMTOffset = -14;
      if(g_brokerGMTOffset > 14)  g_brokerGMTOffset = 14;
   }

   g_frvpRefreshCounter = FRVP_RefreshBars; // force first compute
   g_stats.startingBalance = m_account.Balance();

   Print("ScalpXAU Compact v3.0 initialized on ", _Symbol);
   Print("Memory-optimized: FRVP lookback=", FRVP_Anchors, " bars");
   
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
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Reset daily stats
   ResetDaily();

   //--- Get ATR
   g_atrValue = CalcATR(14, EntryTF);
   if(g_atrValue <= 0) return;

   //--- New bar logic
   if(IsNewBar())
   {
      //--- Refresh FRVP
      g_frvpRefreshCounter++;
      if(g_frvpRefreshCounter >= FRVP_RefreshBars)
      {
         g_frvpRefreshCounter = 0;
         ComputeFRVP();
      }
   }

   //--- Check entry
   if(CountOpenPositions() < MaxPositions)
      CheckEntry();

   //--- Manage positions
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Compute FRVP (minimal memory version)                           |
//+------------------------------------------------------------------+
void ComputeFRVP()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, FRVP_Anchors + 10, rates) < FRVP_Anchors)
   {
      g_frvpValid = false;
      return;
   }

   double lo = 1e9, hi = 0;
   for(int i = 0; i < FRVP_Anchors; i++)
   {
      if(rates[i].low  < lo) lo = rates[i].low;
      if(rates[i].high > hi) hi = rates[i].high;
   }
   if(hi <= lo) { g_frvpValid = false; return; }

   //--- Build histogram
   double bucket = FRVP_BucketPips;
   int nb = (int)MathCeil((hi - lo) / bucket) + 1;
   if(nb > 500) nb = 500; // limit memory
   
   double volA[];
   ArrayResize(volA, nb);
   ArrayInitialize(volA, 0);

   for(int i = 0; i < FRVP_Anchors; i++)
   {
      double vol = (rates[i].tick_volume > 0) ? rates[i].tick_volume : 1;
      int b0 = (int)MathFloor((rates[i].low - lo) / bucket);
      int b1 = (int)MathFloor((rates[i].high - lo) / bucket);
      if(b0 < 0) b0 = 0;
      if(b1 >= nb) b1 = nb - 1;
      int span = b1 - b0 + 1;
      double per = vol / span;
      for(int b = b0; b <= b1; b++) volA[b] += per;
   }

   //--- Find POC
   int pocIdx = 0;
   double total = 0;
   for(int b = 0; b < nb; b++)
   {
      total += volA[b];
      if(volA[b] > volA[pocIdx]) pocIdx = b;
   }
   if(total <= 0) { g_frvpValid = false; return; }

   //--- Value area (70%)
   double vaTarget = total * FRVP_ValueAreaPct / 100.0;
   double vaVol = volA[pocIdx];
   int loIdx = pocIdx, hiIdx = pocIdx;
   while(vaVol < vaTarget && (loIdx > 0 || hiIdx < nb - 1))
   {
      double dn = (loIdx > 0)      ? volA[loIdx - 1] : -1;
      double up = (hiIdx < nb - 1) ? volA[hiIdx + 1] : -1;
      if(up >= dn) { hiIdx++; vaVol += volA[hiIdx]; }
      else         { loIdx--; vaVol += volA[loIdx]; }
   }

   g_poc = NormalizeDouble(lo + (pocIdx + 0.5) * bucket, _Digits);
   g_vah = NormalizeDouble(lo + (hiIdx + 1.0) * bucket, _Digits);
   g_val = NormalizeDouble(lo + loIdx * bucket, _Digits);
   g_frvpValid = true;

   if(DebugMode)
      Print("FRVP | POC=", g_poc, " VAH=", g_vah, " VAL=", g_val);
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
   if(g_lastSession != g_currentSession)
   {
      g_sessionTradeCount = 0;
      g_sessionStartEquity = m_account.Equity();
      g_lastSession = g_currentSession;
   }

   //--- Session trade limit
   if(g_sessionTradeCount >= MaxTradesPerSess) return;

   //--- Need FRVP valid
   if(!g_frvpValid) return;

   //--- Get trend
   int trendDir = GetTrendDirection();

   //--- Session logic
   if(g_currentSession == SESS_LONDON)
      CheckLondonEntry(trendDir);
   else if(g_currentSession == SESS_NY)
      CheckNYEntry(trendDir);
}

//+------------------------------------------------------------------+
//| LONDON: Breakout with FRVP confirmation                         |
//+------------------------------------------------------------------+
void CheckLondonEntry(int trendDir)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 10, rates) < 5) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   double zoneTol = atr * 0.3;

   //--- Look for PA at FRVP zones
   PASignal pa = DetectPASignal(rates, atr);
   if(pa.strength < 2) return;

   //--- BUY at VAL with bullish PA
   if(pa.direction == +1)
   {
      bool atZone = MathAbs(bid - g_val) <= zoneTol || 
                    MathAbs(bid - g_poc) <= zoneTol;
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      if(atZone && trendOk)
      {
         double sl = bid - atr * Min_SL_ATR;
         double tp = bid + atr * 2.0;
         ExecuteTrade(ORDER_TYPE_BUY, bid, sl, tp, "LONDON_VAL");
      }
   }

   //--- SELL at VAH with bearish PA
   if(pa.direction == -1)
   {
      bool atZone = MathAbs(ask - g_vah) <= zoneTol || 
                    MathAbs(ask - g_poc) <= zoneTol;
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      if(atZone && trendOk)
      {
         double sl = ask + atr * Min_SL_ATR;
         double tp = ask - atr * 2.0;
         ExecuteTrade(ORDER_TYPE_SELL, ask, sl, tp, "LONDON_VAH");
      }
   }
}

//+------------------------------------------------------------------+
//| NY: Sweep + FRVP reversal                                        |
//+------------------------------------------------------------------+
void CheckNYEntry(int trendDir)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 8, rates) < 4) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   double zoneTol = atr * 0.3;

   int bar = 1;
   if(bar >= ArraySize(rates)) return;

   double barHigh = rates[bar].high;
   double barLow = rates[bar].low;
   double barClose = rates[bar].close;
   double barOpen = rates[bar].open;
   double wickUp = barHigh - MathMax(barClose, barOpen);
   double wickDown = MathMin(barClose, barOpen) - barLow;
   double body = MathAbs(barClose - barOpen);

   //--- Bullish sweep
   bool bullSweep = (wickDown >= atr * 0.3 && wickDown >= body * 1.5 && barClose > barOpen);
   if(bullSweep)
   {
      bool atPOC = MathAbs(bid - g_poc) <= zoneTol * 2;
      bool atVAL = MathAbs(bid - g_val) <= zoneTol * 2;
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      if((atPOC || atVAL) && trendOk)
      {
         double sl = bid - atr * Min_SL_ATR;
         double tp = bid + atr * 2.0;
         ExecuteTrade(ORDER_TYPE_BUY, bid, sl, tp, "NY_SWEEP_BUY");
      }
   }

   //--- Bearish sweep
   bool bearSweep = (wickUp >= atr * 0.3 && wickUp >= body * 1.5 && barClose < barOpen);
   if(bearSweep)
   {
      bool atPOC = MathAbs(ask - g_poc) <= zoneTol * 2;
      bool atVAH = MathAbs(ask - g_vah) <= zoneTol * 2;
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      if((atPOC || atVAH) && trendOk)
      {
         double sl = ask + atr * Min_SL_ATR;
         double tp = ask - atr * 2.0;
         ExecuteTrade(ORDER_TYPE_SELL, ask, sl, tp, "NY_SWEEP_SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| Detect PA signal (minimal version)                              |
//+------------------------------------------------------------------+
struct PASignal
{
   int direction;    // +1 buy, -1 sell, 0 none
   int strength;     // 1-5
   string patternName;
};

PASignal DetectPASignal(MqlRates &rates[], double atr)
{
   PASignal sig = {0, 0, ""};
   if(ArraySize(rates) < 3) return sig;

   double wickUp = rates[1].high - MathMax(rates[1].close, rates[1].open);
   double wickDown = MathMin(rates[1].close, rates[1].open) - rates[1].low;
   double body = MathAbs(rates[1].close - rates[1].open);
   double range = rates[1].high - rates[1].low;

   if(range <= 0) return sig;

   //--- Pin bar
   if(wickDown >= atr * PA_MinWickATR && wickDown >= body * PA_WickBodyRatio)
   {
      sig.direction = +1;
      sig.strength = 3;
      sig.patternName = "PinBar_BUY";
   }
   else if(wickUp >= atr * PA_MinWickATR && wickUp >= body * PA_WickBodyRatio)
   {
      sig.direction = -1;
      sig.strength = 3;
      sig.patternName = "PinBar_SELL";
   }

   //--- Engulfing
   if(sig.strength == 0 && body >= atr * PA_MinBodyATR)
   {
      double prevBody = MathAbs(rates[2].close - rates[2].open);
      if(rates[1].close > rates[1].open && rates[2].close < rates[2].open && body > prevBody)
      {
         sig.direction = +1;
         sig.strength = 2;
         sig.patternName = "Engulf_BUY";
      }
      else if(rates[1].close < rates[1].open && rates[2].close > rates[2].open && body > prevBody)
      {
         sig.direction = -1;
         sig.strength = 2;
         sig.patternName = "Engulf_SELL";
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Execute trade with risk sizing                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int orderType, double entryPrice, double sl, double tp, string tag)
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double slDist = MathAbs(entryPrice - sl);
   if(slDist <= 0) return;

   double lot = CalcLotSize(slDist, RiskPerTradePct);
   if(lot <= 0) return;

   string comment = CommentPrefix + "_" + tag;
   bool result = false;

   if(orderType == ORDER_TYPE_BUY)
      result = m_trade.Buy(lot, _Symbol, 0, sl, tp, comment);
   else
      result = m_trade.Sell(lot, _Symbol, 0, sl, tp, comment);

   if(result)
   {
      g_tradeCount++;
      g_sessionTradeCount++;
      Print("TRADE ", tag, " | Lot=", lot, " SL=", sl, " TP=", tp);
   }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalcLotSize(double slDist, double riskPct)
{
   double balance = m_account.Balance();
   double riskAmount = balance * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickValue <= 0 || tickSize <= 0) return 0;
   
   double lot = riskAmount / (slDist / tickSize * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lot = MathFloor(lot / lotStep) * lotStep;
   if(lot < minLot) lot = minLot;
   if(lot > maxLot) lot = maxLot;
   
   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Manage open positions (BE + Trailing)                           |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      if(m_position.Magic() != MagicNumber) continue;

      double openPrice = m_position.PriceOpen();
      double currentSL = m_position.StopLoss();
      double currentTP = m_position.TakeProfit();
      double atr = g_atrValue;

      if(m_position.PositionType() == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         double newSL = currentSL;

         //--- Break-even
         if(UseBreakEven && bid >= openPrice + atr * BE_ATR_Mult)
         {
            double beSL = openPrice + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
            if(beSL > currentSL) newSL = beSL;
         }

         //--- Trailing
         if(UseTrailing && bid >= openPrice + atr * TrailStart_ATR)
         {
            double trailSL = bid - atr * TrailStep_ATR;
            if(trailSL > newSL) newSL = trailSL;
         }

         if(newSL > currentSL)
         {
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
         }
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = currentSL;

         //--- Break-even
         if(UseBreakEven && ask <= openPrice - atr * BE_ATR_Mult)
         {
            double beSL = openPrice - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
            if(beSL < currentSL || currentSL == 0) newSL = beSL;
         }

         //--- Trailing
         if(UseTrailing && ask <= openPrice - atr * TrailStart_ATR)
         {
            double trailSL = ask + atr * TrailStep_ATR;
            if(trailSL < newSL || newSL == 0) newSL = trailSL;
         }

         if(newSL < currentSL || currentSL == 0)
         {
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
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
      if(!m_position.SelectByIndex(i)) continue;
      if(m_position.Symbol() != _Symbol) continue;
      if(m_position.Magic() != MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get current session                                              |
//+------------------------------------------------------------------+
SessionType GetCurrentSession()
{
   int hourGMT = GetGMTHour();
   int minGMT = GetGMTMin();
   int timeVal = hourGMT * 60 + minGMT;

   int londonStart = London_StartH * 60 + London_StartM;
   int londonEnd = London_EndH * 60 + London_EndM;
   int nyStart = NY_StartH * 60 + NY_StartM;
   int nyEnd = NY_EndH * 60 + NY_EndM;

   if(timeVal >= londonStart && timeVal < londonEnd) return SESS_LONDON;
   if(timeVal >= nyStart && timeVal < nyEnd) return SESS_NY;
   return SESS_NONE;
}

//+------------------------------------------------------------------+
//| Get GMT hour                                                     |
//+------------------------------------------------------------------+
int GetGMTHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int hour = dt.hour - g_brokerGMTOffset;
   if(hour < 0) hour += 24;
   if(hour >= 24) hour -= 24;
   return hour;
}

//+------------------------------------------------------------------+
//| Get GMT minute                                                   |
//+------------------------------------------------------------------+
int GetGMTMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

//+------------------------------------------------------------------+
//| Calculate ATR                                                    |
//+------------------------------------------------------------------+
double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   int h = iATR(_Symbol, tf, period);
   if(h == INVALID_HANDLE) return 0;
   
   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(h, 0, 0, 1, buf) < 1) { IndicatorRelease(h); return 0; }
   
   double atr = buf[0];
   IndicatorRelease(h);
   return atr;
}

//+------------------------------------------------------------------+
//| Get trend direction                                              |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
   if(!EnableTrendFilter) return 0;

   double maF[], maSlow[];
   ArraySetAsSeries(maF, true);
   ArraySetAsSeries(maSlow, true);
   if(CopyBuffer(hMAFast, 0, 0, 2, maF) < 2) return 0;
   if(CopyBuffer(hMASlow, 0, 0, 2, maSlow) < 2) return 0;

   if(maF[0] > maSlow[0]) return +1;
   if(maF[0] < maSlow[0]) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Is new bar                                                       |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, EntryTF, 0);
   if(barTime == g_lastBarTime) return false;
   g_lastBarTime = barTime;
   return true;
}

//+------------------------------------------------------------------+
//| Reset daily stats                                                |
//+------------------------------------------------------------------+
void ResetDaily()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   static int lastDay = -1;
   
   if(dt.day != lastDay)
   {
      lastDay = dt.day;
      g_tradeCount = 0;
      Print("DAILY RESET | Trades today: ", g_tradeCount);
   }
}

//+------------------------------------------------------------------+
//| Get session name                                                 |
//+------------------------------------------------------------------+
string GetSessionName(SessionType sess)
{
   switch(sess)
   {
      case SESS_LONDON: return "LONDON";
      case SESS_NY: return "NY";
      default: return "NONE";
   }
}
//+------------------------------------------------------------------+
