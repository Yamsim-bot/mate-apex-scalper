//+------------------------------------------------------------------+
//|                                    VolumeProfile_Confluence_EA.mq5 |
//|                          Volume Profile + HTF S/D + Order Flow     |
//|                          Confluence-Based Trading System v1.0      |
//+------------------------------------------------------------------+
#property copyright "YAMSTUNNA Trading Systems"
#property link      ""
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input string   Inp_Gen            = "======== GENERAL SETTINGS ========";
input double   RiskPerTradePct    = 0.5;       // Risk per trade (% of balance)
input double   MaxDailyRiskPct    = 2.0;       // Max daily risk (% of balance)
input int      MaxPositions       = 1;          // Max simultaneous positions
input int      MagicNumber        = 789101;     // Magic number
input string   CommentPrefix      = "VP_CONF";  // Order comment prefix

input string   Inp_TF             = "======== TIMEFRAME SETTINGS ========";
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M15; // Entry timeframe
input ENUM_TIMEFRAMES HTF         = PERIOD_H4;  // High timeframe for S/D zones

input string   Inp_VP             = "======== VOLUME PROFILE ========";
input int      VP_Buckets         = 60;         // VP buckets
input double   VP_BucketPips     = 0.50;       // VP bucket size in price units
input double   VP_VAAPct         = 70.0;       // Value area percentage
input int      VP_RefreshBars    = 12;         // Refresh VP every N bars
input double   VP_ZoneTolATR    = 0.4;        // Zone entry tolerance (xATR)

input string   Inp_SD             = "======== S/D ZONE SETTINGS ========";
input int      SD_SwingLen       = 5;          // Swing lookback bars
input double   SD_ZoneATR        = 0.5;        // Zone thickness (xATR)
input int      SD_MaxZones       = 10;         // Max zones to track
input double   SD_MinStrength    = 3.0;        // Minimum zone strength (1-10)

input string   Inp_OF             = "======== ORDER FLOW ========";
input bool     OF_UseTicks       = true;       // Use tick data (more accurate)
input int      OF_LookbackBars   = 5;          // Bar lookback for flow
input int      OF_LookbackMinutes = 20;        // Tick lookback (minutes)
input double   OF_BuyThreshold   = 0.55;       // Min buy ratio for longs
input double   OF_SellThreshold  = 0.45;       // Min sell ratio for shorts

input string   Inp_Risk           = "======== RISK MANAGEMENT ========";
input double   SL_ATR_Mult       = 1.5;        // SL = ATR * multiplier
input double   TP_ATR_Mult       = 3.0;        // TP = ATR * multiplier
input double   MinRR             = 2.0;        // Minimum risk:reward ratio
input bool     UseBreakEven      = true;       // Move SL to breakeven
input double   BE_ATR_Mult       = 0.8;        // BE trigger (xATR profit)
input bool     UseTrailing       = true;       // Use trailing stop
input double   TrailStart_ATR    = 1.0;        // Trail start (xATR profit)
input double   TrailStep_ATR     = 0.3;        // Trail step (xATR)

input string   Inp_Session       = "======== SESSION SETTINGS ========";
input int      London_StartH     = 7;          // London open (GMT)
input int      London_EndH       = 10;         // London close (GMT)
input int      NY_StartH         = 13;         // NY open (GMT)
input int      NY_EndH           = 16;         // NY close (GMT)
input bool     SkipAsian         = true;       // Skip Asian session

//+------------------------------------------------------------------+
//| STRUCTURES                                                         |
//+------------------------------------------------------------------+
struct VPResult
{
   double poc;
   double vah;
   double val;
   double totalVolume;
   bool   valid;
};

struct SDZone
{
   double   top;
   double   bottom;
   double   midpoint;
   double   strength;
   int      retests;
   bool     isSupply;
   bool     mitigated;
};

struct FlowResult
{
   double buyPressure;
   double sellPressure;
   bool   valid;
};

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                   |
//+------------------------------------------------------------------+
double      g_currentATR;
double      g_dailyPnL;
datetime    g_lastDay;
int         g_todayTrades;
VPResult    g_weeklyVP;
SDZone      g_supplyZones[];
SDZone      g_demandZones[];
int         g_supplyCount;
int         g_demandCount;

//+------------------------------------------------------------------+
//| VOLUME PROFILE ENGINE                                              |
//+------------------------------------------------------------------+
VPResult ComputeVP(string symbol, ENUM_TIMEFRAMES tf, int startBar, int numBars)
{
   VPResult result;
   result.valid = false;
   
   double high[], low[], close[];
   long volume[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   if(CopyHigh(symbol, tf, startBar, numBars, high) < numBars) return result;
   CopyLow(symbol, tf, startBar, numBars, low);
   CopyClose(symbol, tf, startBar, numBars, close);
   CopyTickVolume(symbol, tf, startBar, numBars, volume);
   
   // Find price range
   double minPrice = high[0], maxPrice = low[0];
   for(int i = 1; i < numBars; i++)
   {
      if(high[i] > maxPrice) maxPrice = high[i];
      if(low[i] < minPrice) minPrice = low[i];
   }
   
   double priceRange = maxPrice - minPrice;
   if(priceRange < VP_BucketPips) return result;
   
   int numBuckets = MathMin((int)(priceRange / VP_BucketPips) + 1, 500);
   double bucketVol[];
   ArrayResize(bucketVol, numBuckets);
   ArrayInitialize(bucketVol, 0.0);
   
   for(int i = 0; i < numBars; i++)
   {
      double barVol = volume[i];
      if(barVol <= 0) continue;
      
      int startBucket = (int)((low[i] - minPrice) / VP_BucketPips);
      int endBucket = (int)((high[i] - minPrice) / VP_BucketPips);
      startBucket = MathMax(0, MathMin(startBucket, numBuckets - 1));
      endBucket = MathMax(0, MathMin(endBucket, numBuckets - 1));
      
      int spanned = endBucket - startBucket + 1;
      if(spanned < 1) spanned = 1;
      
      double volPerBucket = barVol / spanned;
      for(int b = startBucket; b <= endBucket; b++)
         if(b >= 0 && b < numBuckets) bucketVol[b] += volPerBucket;
   }
   
   // Find POC
   int pocIdx = 0;
   double maxVol = 0;
   for(int i = 0; i < numBuckets; i++)
   {
      if(bucketVol[i] > maxVol) { maxVol = bucketVol[i]; pocIdx = i; }
   }
   
   result.poc = minPrice + (pocIdx + 0.5) * VP_BucketPips;
   result.totalVolume = 0;
   for(int i = 0; i < numBuckets; i++) result.totalVolume += bucketVol[i];
   
   // Value Area
   double vaTarget = result.totalVolume * (VP_VAAPct / 100.0);
   double vaVol = bucketVol[pocIdx];
   int lowIdx = pocIdx, highIdx = pocIdx;
   
   while(vaVol < vaTarget && (lowIdx > 0 || highIdx < numBuckets - 1))
   {
      double downVol = (lowIdx > 0) ? bucketVol[lowIdx - 1] : 0;
      double upVol = (highIdx < numBuckets - 1) ? bucketVol[highIdx + 1] : 0;
      
      if(downVol >= upVol && lowIdx > 0) { lowIdx--; vaVol += bucketVol[lowIdx]; }
      else if(highIdx < numBuckets - 1) { highIdx++; vaVol += bucketVol[highIdx]; }
      else break;
   }
   
   result.val = minPrice + (lowIdx + 0.5) * VP_BucketPips;
   result.vah = minPrice + (highIdx + 0.5) * VP_BucketPips;
   result.valid = true;
   return result;
}

//+------------------------------------------------------------------+
//| S/D ZONE DETECTION                                                 |
//+------------------------------------------------------------------+
void DetectSDZones(string symbol, ENUM_TIMEFRAMES htf)
{
   g_supplyCount = 0;
   g_demandCount = 0;
   ArrayResize(g_supplyZones, SD_MaxZones);
   ArrayResize(g_demandZones, SD_MaxZones);
   
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   int bars = 500;
   if(CopyHigh(symbol, htf, 0, bars, high) < bars) return;
   CopyLow(symbol, htf, 0, bars, low);
   CopyClose(symbol, htf, 0, bars, close);
   
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(symbol, htf, 14);
   if(atrHandle == INVALID_HANDLE) return;
   CopyBuffer(atrHandle, 0, 0, 1, atr);
   IndicatorRelease(atrHandle);
   
   double zoneThickness = atr[0] * SD_ZoneATR;
   
   for(int i = SD_SwingLen; i < bars - SD_SwingLen; i++)
   {
      // Swing high = supply
      bool isHigh = true;
      for(int j = 1; j <= SD_SwingLen; j++)
      {
         if(high[i] <= high[i-j] || high[i] <= high[i+j]) { isHigh = false; break; }
      }
      
      if(isHigh && g_supplyCount < SD_MaxZones)
      {
         SDZone zone;
         zone.top = high[i] + zoneThickness * 0.5;
         zone.bottom = high[i] - zoneThickness * 0.5;
         zone.midpoint = high[i];
         zone.isSupply = true;
         zone.mitigated = false;
         zone.retests = 0;
         zone.strength = 1.0;
         
         for(int k = i + 1; k < bars; k++)
         {
            if(low[k] <= zone.top && high[k] >= zone.bottom) zone.retests++;
            if(close[k] > zone.top) { zone.mitigated = true; break; }
         }
         
         zone.strength = 1.0 + zone.retests * 0.5;
         if(zone.strength > 10.0) zone.strength = 10.0;
         
         if(zone.strength >= SD_MinStrength && !zone.mitigated)
         {
            g_supplyZones[g_supplyCount] = zone;
            g_supplyCount++;
         }
      }
      
      // Swing low = demand
      bool isLow = true;
      for(int j = 1; j <= SD_SwingLen; j++)
      {
         if(low[i] >= low[i-j] || low[i] >= low[i+j]) { isLow = false; break; }
      }
      
      if(isLow && g_demandCount < SD_MaxZones)
      {
         SDZone zone;
         zone.top = low[i] + zoneThickness * 0.5;
         zone.bottom = low[i] - zoneThickness * 0.5;
         zone.midpoint = low[i];
         zone.isSupply = false;
         zone.mitigated = false;
         zone.retests = 0;
         zone.strength = 1.0;
         
         for(int k = i + 1; k < bars; k++)
         {
            if(high[k] >= zone.bottom && low[k] <= zone.top) zone.retests++;
            if(close[k] < zone.bottom) { zone.mitigated = true; break; }
         }
         
         zone.strength = 1.0 + zone.retests * 0.5;
         if(zone.strength > 10.0) zone.strength = 10.0;
         
         if(zone.strength >= SD_MinStrength && !zone.mitigated)
         {
            g_demandZones[g_demandCount] = zone;
            g_demandCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| ORDER FLOW ANALYSIS                                                |
//+------------------------------------------------------------------+
FlowResult AnalyzeFlow(string symbol, ENUM_TIMEFRAMES tf)
{
   FlowResult result;
   result.valid = false;
   
   if(OF_UseTicks)
   {
      MqlTick ticks[];
      datetime from = TimeCurrent() - OF_LookbackMinutes * 60;
      int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, from, TimeCurrent());
      if(copied < 10) return result;
      
      int buys = 0, sells = 0;
      for(int i = 1; i < copied; i++)
      {
         if(ticks[i].ask > ticks[i-1].ask) buys++;
         else if(ticks[i].bid < ticks[i-1].bid) sells++;
      }
      
      double total = buys + sells;
      if(total == 0) return result;
      result.buyPressure = buys / total;
      result.sellPressure = sells / total;
      result.valid = true;
   }
   else
   {
      double open[], close[];
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(close, true);
      
      if(CopyOpen(symbol, tf, 0, OF_LookbackBars, open) < OF_LookbackBars) return result;
      if(CopyClose(symbol, tf, 0, OF_LookbackBars, close) < OF_LookbackBars) return result;
      
      int buys = 0, sells = 0;
      for(int i = 0; i < OF_LookbackBars; i++)
      {
         if(close[i] > open[i]) buys++;
         else if(close[i] < open[i]) sells++;
      }
      
      double total = buys + sells;
      if(total == 0) return result;
      result.buyPressure = buys / total;
      result.sellPressure = sells / total;
      result.valid = true;
   }
   
   return result;
}

//+------------------------------------------------------------------+
//| INITIALIZATION                                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   g_currentATR = 0;
   g_dailyPnL = 0;
   g_lastDay = 0;
   g_todayTrades = 0;
   g_supplyCount = 0;
   g_demandCount = 0;
   
   DetectSDZones(_Symbol, HTF);
   
   Print("=== VolumeProfile_Confluence EA v1.0 Initialized ===");
   PrintFormat("Entry: %s | HTF: %s | S/D Zones: %d supply, %d demand",
               EnumToString(EntryTF), EnumToString(HTF), g_supplyCount, g_demandCount);
   PrintFormat("Risk: %.1f%% per trade | Max Daily: %.1f%% | Max Positions: %d",
               RiskPerTradePct, MaxDailyRiskPct, MaxPositions);
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| DEINITIALIZATION                                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== VolumeProfile_Confluence EA Removed ===");
}

//+------------------------------------------------------------------+
//| MAIN TICK FUNCTION                                                 |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateATR();
   ResetDailyCounters();
   ManagePositions();
   
   if(CanTrade())
      CheckForEntry();
   
   UpdateChartComment();
}

//+------------------------------------------------------------------+
//| UPDATE ATR                                                         |
//+------------------------------------------------------------------+
void UpdateATR()
{
   int handle = iATR(_Symbol, EntryTF, 14);
   if(handle != INVALID_HANDLE)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(handle, 0, 0, 1, atr) > 0)
         g_currentATR = atr[0];
      IndicatorRelease(handle);
   }
}

//+------------------------------------------------------------------+
//| RESET DAILY COUNTERS                                               |
//+------------------------------------------------------------------+
void ResetDailyCounters()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   
   if(today != g_lastDay)
   {
      g_lastDay = today;
      g_dailyPnL = 0;
      g_todayTrades = 0;
      DetectSDZones(_Symbol, HTF);
      PrintFormat("New Day: %d supply, %d demand zones", g_supplyCount, g_demandCount);
   }
}

//+------------------------------------------------------------------+
//| CAN TRADE CHECK                                                    |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(CountPositions() >= MaxPositions) return false;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double maxLoss = balance * MaxDailyRiskPct / 100.0;
   if(g_dailyPnL <= -maxLoss) return false;
   
   if(!IsSessionActive()) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| COUNT POSITIONS                                                    |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| SESSION CHECK                                                      |
//+------------------------------------------------------------------+
bool IsSessionActive()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int h = dt.hour;
   
   if(SkipAsian && h >= 0 && h < 7) return false;
   if(h >= London_StartH && h < London_EndH) return true;
   if(h >= NY_StartH && h < NY_EndH) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| CHECK FOR ENTRY                                                    |
//+------------------------------------------------------------------+
void CheckForEntry()
{
   if(g_currentATR <= 0) return;
   
   // Refresh VP periodically
   static int lastVPRefresh = 0;
   int bars = iBars(_Symbol, EntryTF);
   if(bars - lastVPRefresh >= VP_RefreshBars)
   {
      lastVPRefresh = bars;
      g_weeklyVP = ComputeVP(_Symbol, EntryTF, 0, 250);
      if(g_weeklyVP.valid)
         PrintFormat("Weekly VP: POC=%.2f VAH=%.2f VAL=%.2f", g_weeklyVP.poc, g_weeklyVP.vah, g_weeklyVP.val);
   }
   
   if(!g_weeklyVP.valid) return;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tolerance = g_currentATR * VP_ZoneTolATR;
   
   FlowResult flow = AnalyzeFlow(_Symbol, EntryTF);
   
   // BUY SETUP: Price at POC or VAL + demand zone + buy flow
   bool atPOC = MathAbs(price - g_weeklyVP.poc) < tolerance;
   bool atVAL = MathAbs(price - g_weeklyVP.val) < tolerance;
   
   if((atPOC || atVAL) && flow.valid && flow.buyPressure >= OF_BuyThreshold)
   {
      for(int i = 0; i < g_demandCount; i++)
      {
         if(g_demandZones[i].mitigated) continue;
         if(price >= g_demandZones[i].bottom && price <= g_demandZones[i].top)
         {
            if(g_demandZones[i].strength >= SD_MinStrength)
            {
               PrintFormat("BUY SETUP: Price=%.2f %s + Demand(str=%.1f) + Flow(%.0f%%)",
                           price, atPOC ? "POC" : "VAL", g_demandZones[i].strength, flow.buyPressure * 100);
               ExecuteBuy(price);
               return;
            }
         }
      }
   }
   
   // SELL SETUP: Price at POC or VAH + supply zone + sell flow
   bool atVAH = MathAbs(price - g_weeklyVP.vah) < tolerance;
   
   if((atPOC || atVAH) && flow.valid && flow.sellPressure >= OF_SellThreshold)
   {
      for(int i = 0; i < g_supplyCount; i++)
      {
         if(g_supplyZones[i].mitigated) continue;
         if(price >= g_supplyZones[i].bottom && price <= g_supplyZones[i].top)
         {
            if(g_supplyZones[i].strength >= SD_MinStrength)
            {
               PrintFormat("SELL SETUP: Price=%.2f %s + Supply(str=%.1f) + Flow(%.0f%%)",
                           price, atVAH ? "VAH" : "POC", g_supplyZones[i].strength, flow.sellPressure * 100);
               ExecuteSell(price);
               return;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| EXECUTE BUY                                                        |
//+------------------------------------------------------------------+
void ExecuteBuy(double price)
{
   double sl = price - (g_currentATR * SL_ATR_Mult);
   double tp = price + (g_currentATR * TP_ATR_Mult);
   
   double rr = (tp - price) / (price - sl);
   if(rr < MinRR) { PrintFormat("SKIP BUY: RR=%.2f < %.2f", rr, MinRR); return; }
   
   double lots = CalcLots(price - sl);
   if(lots <= 0) return;
   
   MqlTradeRequest request = {};
   MqlTradeResult  result = {};
   
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lots;
   request.type      = ORDER_TYPE_BUY;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = 30;
   request.magic     = MagicNumber;
   request.comment   = CommentPrefix + "_BUY";
   
   if(!OrderSend(request, result))
      PrintFormat("BUY FAILED: %d - %s", result.retcode, result.comment);
   else
   {
      PrintFormat("BUY OK: %.2f lots @ %.2f SL=%.2f TP=%.2f", lots, request.price, sl, tp);
      g_todayTrades++;
   }
}

//+------------------------------------------------------------------+
//| EXECUTE SELL                                                       |
//+------------------------------------------------------------------+
void ExecuteSell(double price)
{
   double sl = price + (g_currentATR * SL_ATR_Mult);
   double tp = price - (g_currentATR * TP_ATR_Mult);
   
   double rr = (price - tp) / (sl - price);
   if(rr < MinRR) { PrintFormat("SKIP SELL: RR=%.2f < %.2f", rr, MinRR); return; }
   
   double lots = CalcLots(sl - price);
   if(lots <= 0) return;
   
   MqlTradeRequest request = {};
   MqlTradeResult  result = {};
   
   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = lots;
   request.type      = ORDER_TYPE_SELL;
   request.price     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   request.sl        = sl;
   request.tp        = tp;
   request.deviation = 30;
   request.magic     = MagicNumber;
   request.comment   = CommentPrefix + "_SELL";
   
   if(!OrderSend(request, result))
      PrintFormat("SELL FAILED: %d - %s", result.retcode, result.comment);
   else
   {
      PrintFormat("SELL OK: %.2f lots @ %.2f SL=%.2f TP=%.2f", lots, request.price, sl, tp);
      g_todayTrades++;
   }
}

//+------------------------------------------------------------------+
//| CALCULATE LOT SIZE                                                 |
//+------------------------------------------------------------------+
double CalcLots(double slDistance)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * RiskPerTradePct / 100.0;
   double tickVal = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tickVal <= 0 || tickSize <= 0 || slDistance <= 0) return 0;
   
   double lots = riskAmt / (slDistance / tickSize * tickVal);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / step) * step;
   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   
   return lots;
}

//+------------------------------------------------------------------+
//| MANAGE POSITIONS                                                   |
//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      long   posType = PositionGetInteger(POSITION_TYPE);
      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      
      double price = (posType == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Break Even
      if(UseBreakEven)
      {
         if(posType == POSITION_TYPE_BUY)
         {
            if(price >= openPrice + g_currentATR * BE_ATR_Mult && curSL < openPrice)
               ModPos(ticket, openPrice + g_currentATR * 0.1, curTP);
         }
         else
         {
            if(price <= openPrice - g_currentATR * BE_ATR_Mult && (curSL > openPrice || curSL == 0))
               ModPos(ticket, openPrice - g_currentATR * 0.1, curTP);
         }
      }
      
      // Trailing Stop
      if(UseTrailing)
      {
         double trailStart = g_currentATR * TrailStart_ATR;
         double trailStep = g_currentATR * TrailStep_ATR;
         
         if(posType == POSITION_TYPE_BUY)
         {
            if(price - openPrice >= trailStart)
            {
               double newSL = price - trailStep;
               if(newSL > curSL) ModPos(ticket, newSL, curTP);
            }
         }
         else
         {
            if(openPrice - price >= trailStart)
            {
               double newSL = price + trailStep;
               if(newSL < curSL || curSL == 0) ModPos(ticket, newSL, curTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFY POSITION                                                    |
//+------------------------------------------------------------------+
bool ModPos(ulong ticket, double sl, double tp)
{
   MqlTradeRequest request = {};
   MqlTradeResult  result = {};
   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = sl;
   request.tp       = tp;
   return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| CHART COMMENT                                                      |
//+------------------------------------------------------------------+
void UpdateChartComment()
{
   string c = "";
   c += "=== VolumeProfile_Confluence EA v1.0 ===\n";
   c += StringFormat("ATR: %.2f | Positions: %d/%d\n", g_currentATR, CountPositions(), MaxPositions);
   c += StringFormat("Today P/L: $%.2f | Trades: %d\n", g_dailyPnL, g_todayTrades);
   
   if(g_weeklyVP.valid)
      c += StringFormat("WeeklyVP: POC=%.2f VAH=%.2f VAL=%.2f\n", g_weeklyVP.poc, g_weeklyVP.vah, g_weeklyVP.val);
   
   c += StringFormat("S/D Zones: %d supply, %d demand\n", g_supplyCount, g_demandCount);
   
   Comment(c);
}
//+------------------------------------------------------------------+
