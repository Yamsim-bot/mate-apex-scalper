//+------------------------------------------------------------------+
//|                                ScalpMaster_Pro_Compact.mq5       |
//|               VP + S/D + Order Flow - 2GB VPS Optimized          |
//|                                                                    |
//|  Strategy:                                                         |
//|  - Volume Profile (POC/VAH/VAL) - reduced lookback              |
//|  - Supply/Demand zones from price action                          |
//|  - Order flow confirmation (tick-based)                          |
//|  - Session gating (London/NY)                                    |
//|                                                                    |
//|  OPTIMIZED: Removed Delta Bubble, reduced memory footprint       |
//+------------------------------------------------------------------+
#property copyright "FXRE Compact v3.0"
#property version   "3.21"
#property description "XAUUSD VP Scalper - 2GB VPS Optimized"
#property strict

#include "..\Include\Trade\Trade.mqh"
#include "..\Include\Trade\PositionInfo.mqh"
#include "..\Include\Trade\AccountInfo.mqh"

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
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M5;
input int      VP_Lookback        = 50;            // VP lookback bars (50xM5 = 4h)
input double   VP_BucketPips      = 0.50;
input double   VP_ValueAreaPct    = 70.0;
input int      VP_RefreshBars     = 10;            // Recompute every N bars

//--- S/D Zones
input string   Inp_SD             = "===== S/D ZONES ======";
input int      SD_SwingLen        = 3;             // Swing bars each side
input double   SD_MinStrength     = 2.0;           // Min zone strength

//--- Order Flow
input string   Inp_Flow           = "===== ORDER FLOW ======";
input bool     EnableFlow         = true;
input int      FlowLookbackMin    = 15;            // Flow lookback (minutes)
input double   FlowThreshBuy      = 0.6;           // Min buy ratio for BUY
input double   FlowThreshSell     = 0.4;           // Max buy ratio for SELL

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
input int      MagicNumber        = 241108;
input string   CommentPrefix      = "SCALPM_C";

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

//--- VP state (minimal)
double         g_poc = 0;
double         g_vah = 0;
double         g_val = 0;
bool           g_vpValid = false;
datetime       g_lastCompute = 0;

//--- S/D zones (minimal - just store nearest)
double         g_nearestDemand = 0;
double         g_nearestSupply = 0;
bool           g_sdValid = false;

//--- Indicators
int            hMAFast = INVALID_HANDLE;
int            hMASlow = INVALID_HANDLE;

//--- Session
enum SessionType { SESS_NONE = -1, SESS_LONDON = 0, SESS_NY = 1 };
SessionType    g_currentSession = SESS_NONE;

//--- Daily stats
int            g_tradeCount = 0;
int            g_sessionTradeCount = 0;
SessionType    g_lastSession = SESS_NONE;
double         g_sessionStartEquity = 0;

//--- Order flow (ring buffer)
#define FLOW_BINS 30
double         g_flowBuy[FLOW_BINS];
double         g_flowSell[FLOW_BINS];
datetime       g_flowMinute[FLOW_BINS];
int            g_flowHead = -1;
double         g_lastFlowBid = 0;

//--- Misc
double         g_atrValue = 0;
datetime       g_lastBarTime = 0;
datetime       g_lastEntryBarTime = 0;
int            g_vpRefreshCounter = 0;
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

   //--- MA handles
   hMAFast = iMA(_Symbol, EntryTF, Trend_MA_Fast, 0, MODE_SMA, PRICE_CLOSE);
   hMASlow = iMA(_Symbol, EntryTF, Trend_MA_Slow, 0, MODE_SMA, PRICE_CLOSE);

   //--- GMT offset
   g_brokerGMTOffset = BrokerGMTOffset;
   if(g_brokerGMTOffset == -99)
   {
      g_brokerGMTOffset = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);
      if(g_brokerGMTOffset < -14) g_brokerGMTOffset = -14;
      if(g_brokerGMTOffset > 14)  g_brokerGMTOffset = 14;
   }

   g_vpRefreshCounter = VP_RefreshBars;

   Print("ScalpMaster_Pro Compact v3.0 initialized on ", _Symbol);
   Print("Memory-optimized: VP lookback=", VP_Lookback, " bars");
   
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
   ResetDaily();

   g_atrValue = CalcATR(14, EntryTF);
   if(g_atrValue <= 0) return;

   //--- Accumulate tick flow
   if(EnableFlow) AccumulateTickFlow();

   //--- New bar
   if(IsNewBar())
   {
      //--- Refresh VP
      g_vpRefreshCounter++;
      if(g_vpRefreshCounter >= VP_RefreshBars)
      {
         g_vpRefreshCounter = 0;
         ComputeVP();
         DetectSDZones();
      }
   }

   //--- Check entry
   if(CountOpenPositions() < MaxPositions)
      CheckEntry();

   //--- Manage
   ManagePositions();
}

//+------------------------------------------------------------------+
//| Compute Volume Profile (minimal)                                |
//+------------------------------------------------------------------+
void ComputeVP()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, VP_Lookback + 10, rates) < VP_Lookback)
   {
      g_vpValid = false;
      return;
   }

   double lo = 1e9, hi = 0;
   for(int i = 0; i < VP_Lookback; i++)
   {
      if(rates[i].low  < lo) lo = rates[i].low;
      if(rates[i].high > hi) hi = rates[i].high;
   }
   if(hi <= lo) { g_vpValid = false; return; }

   //--- Histogram
   double bucket = VP_BucketPips;
   int nb = (int)MathCeil((hi - lo) / bucket) + 1;
   if(nb > 300) nb = 300; // limit

   double volA[];
   ArrayResize(volA, nb);
   ArrayInitialize(volA, 0);

   for(int i = 0; i < VP_Lookback; i++)
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

   //--- POC
   int pocIdx = 0;
   double total = 0;
   for(int b = 0; b < nb; b++)
   {
      total += volA[b];
      if(volA[b] > volA[pocIdx]) pocIdx = b;
   }
   if(total <= 0) { g_vpValid = false; return; }

   //--- Value area
   double vaTarget = total * VP_ValueAreaPct / 100.0;
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
   g_vpValid = true;

   if(DebugMode)
      Print("VP | POC=", g_poc, " VAH=", g_vah, " VAL=", g_val);
}

//+------------------------------------------------------------------+
//| Detect S/D zones (minimal - just nearest levels)                |
//+------------------------------------------------------------------+
void DetectSDZones()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, EntryTF, 0, 100, rates) < 50)
   {
      g_sdValid = false;
      return;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;

   //--- Find recent swing lows (demand) and highs (supply)
   double demandLevels[];
   double supplyLevels[];
   ArrayResize(demandLevels, 0);
   ArrayResize(supplyLevels, 0);

   for(int i = SD_SwingLen + 1; i < 50 - SD_SwingLen; i++)
   {
      //--- Swing low (demand)
      bool isLow = true;
      for(int j = 1; j <= SD_SwingLen; j++)
      {
         if(rates[i-j].low < rates[i].low || rates[i+j].low < rates[i].low)
         {
            isLow = false;
            break;
         }
      }
      if(isLow)
      {
         int sz = ArraySize(demandLevels);
         ArrayResize(demandLevels, sz + 1);
         demandLevels[sz] = rates[i].low;
      }

      //--- Swing high (supply)
      bool isHigh = true;
      for(int j = 1; j <= SD_SwingLen; j++)
      {
         if(rates[i-j].high > rates[i].high || rates[i+j].high > rates[i].high)
         {
            isHigh = false;
            break;
         }
      }
      if(isHigh)
      {
         int sz = ArraySize(supplyLevels);
         ArrayResize(supplyLevels, sz + 1);
         supplyLevels[sz] = rates[i].high;
      }
   }

   //--- Find nearest demand below price
   g_nearestDemand = 0;
   for(int i = 0; i < ArraySize(demandLevels); i++)
   {
      if(demandLevels[i] < bid && demandLevels[i] > bid - atr * 3)
      {
         if(g_nearestDemand == 0 || demandLevels[i] > g_nearestDemand)
            g_nearestDemand = demandLevels[i];
      }
   }

   //--- Find nearest supply above price
   g_nearestSupply = 0;
   for(int i = 0; i < ArraySize(supplyLevels); i++)
   {
      if(supplyLevels[i] > ask && supplyLevels[i] < ask + atr * 3)
      {
         if(g_nearestSupply == 0 || supplyLevels[i] < g_nearestSupply)
            g_nearestSupply = supplyLevels[i];
      }
   }

   g_sdValid = (g_nearestDemand > 0 || g_nearestSupply > 0);
   
   if(DebugMode && g_sdValid)
      Print("S/D | Demand=", g_nearestDemand, " Supply=", g_nearestSupply);
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

   if(g_lastSession != g_currentSession)
   {
      g_sessionTradeCount = 0;
      g_sessionStartEquity = m_account.Equity();
      g_lastSession = g_currentSession;
   }

   if(g_sessionTradeCount >= MaxTradesPerSess) return;
   if(!g_vpValid) return;

   int trendDir = GetTrendDirection();

   if(g_currentSession == SESS_LONDON)
      CheckLondonEntry(trendDir);
   else if(g_currentSession == SESS_NY)
      CheckNYEntry(trendDir);
}

//+------------------------------------------------------------------+
//| LONDON: VP zone entry with S/D + flow                           |
//+------------------------------------------------------------------+
void CheckLondonEntry(int trendDir)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   double zoneTol = atr * 0.3;

   //--- Check if near VP zone
   bool atPOC = MathAbs(bid - g_poc) <= zoneTol;
   bool atVAL = MathAbs(bid - g_val) <= zoneTol;
   bool atVAH = MathAbs(ask - g_vah) <= zoneTol;

   //--- BUY at POC/VAL with demand zone + flow
   if(atPOC || atVAL)
   {
      bool demandNear = (g_nearestDemand > 0 && MathAbs(bid - g_nearestDemand) <= zoneTol * 2);
      bool flowOk = (!EnableFlow) || (TF_BuyRatio(FlowLookbackMin) >= FlowThreshBuy);
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      if((demandNear || atVAL) && flowOk && trendOk)
      {
         double sl = bid - atr * Min_SL_ATR;
         double tp = bid + atr * 2.0;
         ExecuteTrade(ORDER_TYPE_BUY, bid, sl, tp, "LONDON_BUY");
      }
   }

   //--- SELL at POC/VAH with supply zone + flow
   if(atPOC || atVAH)
   {
      bool supplyNear = (g_nearestSupply > 0 && MathAbs(ask - g_nearestSupply) <= zoneTol * 2);
      bool flowOk = (!EnableFlow) || (TF_BuyRatio(FlowLookbackMin) <= FlowThreshSell);
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      if((supplyNear || atVAH) && flowOk && trendOk)
      {
         double sl = ask + atr * Min_SL_ATR;
         double tp = ask - atr * 2.0;
         ExecuteTrade(ORDER_TYPE_SELL, ask, sl, tp, "LONDON_SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| NY: VP zone reversal                                            |
//+------------------------------------------------------------------+
void CheckNYEntry(int trendDir)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double atr = g_atrValue;
   double zoneTol = atr * 0.3;

   //--- Same logic as London but stricter flow requirement
   bool atPOC = MathAbs(bid - g_poc) <= zoneTol;
   bool atVAL = MathAbs(bid - g_val) <= zoneTol;
   bool atVAH = MathAbs(ask - g_vah) <= zoneTol;

   if(atPOC || atVAL)
   {
      bool demandNear = (g_nearestDemand > 0 && MathAbs(bid - g_nearestDemand) <= zoneTol * 2);
      bool flowOk = (!EnableFlow) || (TF_BuyRatio(FlowLookbackMin) >= 0.65);
      bool trendOk = (!PA_RequireTrend || trendDir >= 0);

      if((demandNear || atVAL) && flowOk && trendOk)
      {
         double sl = bid - atr * Min_SL_ATR;
         double tp = bid + atr * 2.0;
         ExecuteTrade(ORDER_TYPE_BUY, bid, sl, tp, "NY_BUY");
      }
   }

   if(atPOC || atVAH)
   {
      bool supplyNear = (g_nearestSupply > 0 && MathAbs(ask - g_nearestSupply) <= zoneTol * 2);
      bool flowOk = (!EnableFlow) || (TF_BuyRatio(FlowLookbackMin) <= 0.35);
      bool trendOk = (!PA_RequireTrend || trendDir <= 0);

      if((supplyNear || atVAH) && flowOk && trendOk)
      {
         double sl = ask + atr * Min_SL_ATR;
         double tp = ask - atr * 2.0;
         ExecuteTrade(ORDER_TYPE_SELL, ask, sl, tp, "NY_SELL");
      }
   }
}

//+------------------------------------------------------------------+
//| Tick flow functions                                              |
//+------------------------------------------------------------------+
void AccumulateTickFlow()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0) return;

   datetime now = TimeTradeServer();
   datetime nowMin = now - (now % 60);

   if(g_lastFlowBid <= 0) { g_lastFlowBid = bid; return; }
   int dir = (bid > g_lastFlowBid) ? +1 : (bid < g_lastFlowBid ? -1 : 0);
   g_lastFlowBid = bid;
   if(dir == 0) return;

   if(g_flowHead < 0 || g_flowMinute[g_flowHead] != nowMin)
   {
      g_flowHead = (g_flowHead + 1) % FLOW_BINS;
      g_flowMinute[g_flowHead] = nowMin;
      g_flowBuy[g_flowHead] = 0;
      g_flowSell[g_flowHead] = 0;
   }
   if(dir > 0) g_flowBuy[g_flowHead] += 1.0;
   else        g_flowSell[g_flowHead] += 1.0;
}

double TF_BuyRatio(int windowMinutes)
{
   if(g_flowHead < 0) return 0.5;
   datetime now = TimeTradeServer();
   datetime cutoff = now - (datetime)(windowMinutes * 60);
   double buy = 0, sell = 0;
   for(int i = 0; i < FLOW_BINS; i++)
   {
      if(g_flowMinute[i] == 0 || g_flowMinute[i] < cutoff) continue;
      buy  += g_flowBuy[i];
      sell += g_flowSell[i];
   }
   double tot = buy + sell;
   if(tot <= 0) return 0.5;
   return buy / tot;
}

//+------------------------------------------------------------------+
//| Execute trade                                                   |
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
//| Calc lot size                                                    |
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
//| Manage positions                                                |
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

         if(UseBreakEven && bid >= openPrice + atr * BE_ATR_Mult)
         {
            double beSL = openPrice + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
            if(beSL > currentSL) newSL = beSL;
         }

         if(UseTrailing && bid >= openPrice + atr * TrailStart_ATR)
         {
            double trailSL = bid - atr * TrailStep_ATR;
            if(trailSL > newSL) newSL = trailSL;
         }

         if(newSL > currentSL)
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
      }
      else if(m_position.PositionType() == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double newSL = currentSL;

         if(UseBreakEven && ask <= openPrice - atr * BE_ATR_Mult)
         {
            double beSL = openPrice - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;
            if(beSL < currentSL || currentSL == 0) newSL = beSL;
         }

         if(UseTrailing && ask <= openPrice - atr * TrailStart_ATR)
         {
            double trailSL = ask + atr * TrailStep_ATR;
            if(trailSL < newSL || newSL == 0) newSL = trailSL;
         }

         if(newSL < currentSL || currentSL == 0)
            m_trade.PositionModify(m_position.Ticket(), newSL, currentTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions                                                 |
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
//| Session functions                                               |
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

int GetGMTHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int hour = dt.hour - g_brokerGMTOffset;
   if(hour < 0) hour += 24;
   if(hour >= 24) hour -= 24;
   return hour;
}

int GetGMTMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

//+------------------------------------------------------------------+
//| Indicator functions                                             |
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

bool IsNewBar()
{
   datetime barTime = iTime(_Symbol, EntryTF, 0);
   if(barTime == g_lastBarTime) return false;
   g_lastBarTime = barTime;
   return true;
}

void ResetDaily()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   static int lastDay = -1;
   
   if(dt.day != lastDay)
   {
      lastDay = dt.day;
      g_tradeCount = 0;
   }
}
//+------------------------------------------------------------------+
