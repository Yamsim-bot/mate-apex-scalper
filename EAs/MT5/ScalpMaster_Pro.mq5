//+------------------------------------------------------------------+
//|                                            ScalpMaster_Pro.mq5     |
//|                          Professional Scalping EA v3.0             |
//|                          VP + S/D + Order Flow + Delta Bubble      |
//+------------------------------------------------------------------+
#property copyright "YAMSTUNNA Trading Systems"
#property link      ""
#property version   "3.00"
#property strict

#include <DeltaBubble.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                   |
//+------------------------------------------------------------------+
input string   Inp_Gen            = "======== GENERAL ========";
input double   RiskPerTradePct    = 0.5;       // Risk per trade (%)
input double   MaxDailyLossPct    = 2.0;       // Max daily loss (%)
input int      MaxPositions       = 1;          // Max positions
input int      MaxTradesPerDay    = 5;          // Max trades per day
input int      MagicNumber        = 334455;     // Magic number
input string   CommentPrefix      = "SCALP";    // Order comment

input string   Inp_TF             = "======== TIMEFRAMES ========";
input ENUM_TIMEFRAMES EntryTF     = PERIOD_M5;  // Entry TF
input ENUM_TIMEFRAMES HTF         = PERIOD_H1;  // HTF for zones

input string   Inp_VP             = "======== VOLUME PROFILE ========";
input int      VP_Bars            = 100;        // VP lookback bars
input double   VP_BucketPips     = 0.25;       // VP bucket size
input double   VP_VAAPct         = 70.0;       // Value area %
input double   VP_TolATR         = 0.3;        // Zone tolerance (xATR)

input string   Inp_SD             = "======== SUPPLY/DEMAND ========";
input int      SD_SwingLen       = 3;          // Swing lookback
input double   SD_MinStrength    = 2.0;        // Min zone strength
input double   SD_MaxDistATR     = 2.0;        // Max zone distance (xATR)

input string   Inp_OF             = "======== ORDER FLOW ========";
input double   OF_BuyMin         = 0.60;       // Min buy ratio for longs
input double   OF_SellMin        = 0.40;       // Min sell ratio for shorts
input int      OF_Bars           = 3;          // Flow lookback bars

input string   Inp_Delta          = "======== DELTA BUBBLE ========";
input bool     EnableDeltaBubble = true;       // Enable Delta Bubble confluence
input double   Delta_MinBubble    = 100.0;     // Min bubble size for significance
input double   Delta_AbsorbThresh = 2.5;       // Absorption threshold multiplier
input double   Delta_ShiftThresh  = 0.5;       // Delta shift sensitivity
input int      Delta_Lookback     = 5;         // Lookback bars for delta calc
input int      Delta_MinStrength  = 4;         // Min bubble strength for entry

input string   Inp_Risk           = "======== RISK ========";
input double   SL_ATR            = 1.2;        // SL (xATR)
input double   TP_ATR            = 2.0;        // TP (xATR)
input double   MinRR             = 1.5;        // Min R:R
input bool     UseBE             = true;       // Break-even
input double   BE_TriggerATR     = 0.8;        // BE trigger (xATR)
input bool     UseTrail          = true;       // Trailing stop
input double   TrailStartATR     = 1.0;        // Trail start (xATR)
input double   TrailStepATR      = 0.3;        // Trail step (xATR)

input string   Inp_Session       = "======== SESSIONS ========";
input int      LondonStart       = 7;          // London open (GMT)
input int      LondonEnd         = 10;         // London close (GMT)
input int      NYStart           = 13;         // NY open (GMT)
input int      NYEnd             = 16;         // NY close (GMT)

//+------------------------------------------------------------------+
//| GLOBALS                                                            |
//+------------------------------------------------------------------+
double gATR;
double gDailyPnL;
int    gDayTrades;
datetime gLastDay;

// VP levels
double gPOC, gVAH, gVAL;
bool   gVPValid;

// S/D zones
struct Zone { double top; double bottom; double mid; double str; bool supply; bool active; };
Zone gSupply[], gDemand[];
int gSupplyCnt, gDemandCnt;

// Delta Bubble
DeltaBubbleEngine *gDeltaEngine = NULL;
DeltaBubbleData gDeltaData;
string gDeltaDesc = "";

//+------------------------------------------------------------------+
//| INIT                                                               |
//+------------------------------------------------------------------+
int OnInit()
{
   gATR = 0;
   gDailyPnL = 0;
   gDayTrades = 0;
   gLastDay = 0;
   gVPValid = false;
   gSupplyCnt = 0;
   gDemandCnt = 0;
   
   // Initialize Delta Bubble engine
   if(EnableDeltaBubble)
   {
      gDeltaEngine = new DeltaBubbleEngine(Delta_MinBubble, Delta_AbsorbThresh, 
                                            Delta_ShiftThresh, Delta_Lookback);
      Print("Delta Bubble: ON minBubble=", Delta_MinBubble, 
            " absorbThresh=", Delta_AbsorbThresh, 
            " minStr=", Delta_MinStrength);
   }
   
   Print("=== ScalpMaster Pro v3.0 | Magic:", MagicNumber, " ===");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| DEINIT                                                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(gDeltaEngine != NULL) delete gDeltaEngine;
   Comment("");
}

//+------------------------------------------------------------------+
//| TICK                                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   UpdateATR();
   ResetDaily();
   ManageOpen();
   
   if(CanTrade() && IsSession())
      CheckEntry();
   
   ShowComment();
}

//+------------------------------------------------------------------+
//| ATR                                                                |
//+------------------------------------------------------------------+
void UpdateATR()
{
   int h = iATR(_Symbol, EntryTF, 14);
   if(h != INVALID_HANDLE)
   {
      double a[];
      ArraySetAsSeries(a, true);
      if(CopyBuffer(h, 0, 0, 1, a) > 0) gATR = a[0];
      IndicatorRelease(h);
   }
}

//+------------------------------------------------------------------+
//| DAILY RESET                                                        |
//+------------------------------------------------------------------+
void ResetDaily()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != gLastDay)
   {
      gLastDay = today;
      gDailyPnL = 0;
      gDayTrades = 0;
      ScanSDZones();
   }
}

//+------------------------------------------------------------------+
//| CAN TRADE                                                          |
//+------------------------------------------------------------------+
bool CanTrade()
{
   if(CountPos() >= MaxPositions) return false;
   if(gDayTrades >= MaxTradesPerDay) return false;
   
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   if(gDailyPnL <= -(bal * MaxDailyLossPct / 100.0)) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| SESSION CHECK                                                      |
//+------------------------------------------------------------------+
bool IsSession()
{
   int h = TimeHour();
   return (h >= LondonStart && h < LondonEnd) || (h >= NYStart && h < NYEnd);
}

int TimeHour()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   return dt.hour;
}

//+------------------------------------------------------------------+
//| COUNT POSITIONS                                                    |
//+------------------------------------------------------------------+
int CountPos()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         c++;
   return c;
}

//+------------------------------------------------------------------+
//| SCAN S/D ZONES                                                     |
//+------------------------------------------------------------------+
void ScanSDZones()
{
   gSupplyCnt = 0;
   gDemandCnt = 0;
   ArrayResize(gSupply, 20);
   ArrayResize(gDemand, 20);
   
   double hi[], lo[], cl[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(cl, true);
   
   int bars = 200;
   if(CopyHigh(_Symbol, HTF, 0, bars, hi) < bars) return;
   CopyLow(_Symbol, HTF, 0, bars, lo);
   CopyClose(_Symbol, HTF, 0, bars, cl);
   
   double atr[];
   ArraySetAsSeries(atr, true);
   int ah = iATR(_Symbol, HTF, 14);
   if(ah == INVALID_HANDLE) return;
   CopyBuffer(ah, 0, 0, 1, atr);
   IndicatorRelease(ah);
   
   double thick = atr[0] * 0.5;
   
   for(int i = SD_SwingLen; i < bars - SD_SwingLen; i++)
   {
      // Swing high
      bool isHi = true;
      for(int j = 1; j <= SD_SwingLen; j++)
         if(hi[i] <= hi[i-j] || hi[i] <= hi[i+j]) { isHi = false; break; }
      
      if(isHi && gSupplyCnt < 20)
      {
         Zone z;
         z.top = hi[i] + thick * 0.5;
         z.bottom = hi[i] - thick * 0.5;
         z.mid = hi[i];
         z.supply = true;
         z.active = true;
         z.str = 1.0;
         
         int ret = 0;
         bool broken = false;
         for(int k = i+1; k < bars; k++)
         {
            if(lo[k] <= z.top && hi[k] >= z.bottom) ret++;
            if(cl[k] > z.top) { broken = true; break; }
         }
         z.str = 1.0 + ret * 0.5;
         if(z.str > 10) z.str = 10;
         
         if(z.str >= SD_MinStrength && !broken)
         { gSupply[gSupplyCnt] = z; gSupplyCnt++; }
      }
      
      // Swing low
      bool isLo = true;
      for(int j = 1; j <= SD_SwingLen; j++)
         if(lo[i] >= lo[i-j] || lo[i] >= lo[i+j]) { isLo = false; break; }
      
      if(isLo && gDemandCnt < 20)
      {
         Zone z;
         z.top = lo[i] + thick * 0.5;
         z.bottom = lo[i] - thick * 0.5;
         z.mid = lo[i];
         z.supply = false;
         z.active = true;
         z.str = 1.0;
         
         int ret = 0;
         bool broken = false;
         for(int k = i+1; k < bars; k++)
         {
            if(hi[k] >= z.bottom && lo[k] <= z.top) ret++;
            if(cl[k] < z.bottom) { broken = true; break; }
         }
         z.str = 1.0 + ret * 0.5;
         if(z.str > 10) z.str = 10;
         
         if(z.str >= SD_MinStrength && !broken)
         { gDemand[gDemandCnt] = z; gDemandCnt++; }
      }
   }
}

//+------------------------------------------------------------------+
//| CHECK ENTRY                                                        |
//+------------------------------------------------------------------+
void CheckEntry()
{
   if(gATR <= 0) return;
   
   // Compute VP
   static int lastVP = 0;
   int bars = iBars(_Symbol, EntryTF);
   if(bars - lastVP >= 6)
   {
      lastVP = bars;
      ComputeVP();
   }
   
   if(!gVPValid) return;
   
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double tol = gATR * VP_TolATR;
   
   // Basic order flow
   double buyP = 0, sellP = 0;
   GetFlow(buyP, sellP);
   
   // Delta Bubble confluence
   bool deltaBuy = true, deltaSell = true;
   int deltaStr = 5;
   gDeltaDesc = "";
   
   if(EnableDeltaBubble && gDeltaEngine != NULL)
   {
      gDeltaData = gDeltaEngine.Calculate(_Symbol, EntryTF);
      deltaBuy = gDeltaEngine.ConfirmsBuy(gDeltaData);
      deltaSell = gDeltaEngine.ConfirmsSell(gDeltaData);
      deltaStr = gDeltaEngine.GetBubbleStrength(gDeltaData);
      gDeltaDesc = gDeltaEngine.GetDescription(gDeltaData);
      
      // If Delta Bubble enabled, require it for entry
      if(deltaStr < Delta_MinStrength)
      {
         deltaBuy = false;
         deltaSell = false;
      }
   }
   
   // BUY: at POC/VAL + demand zone + buy flow + delta confirm
   bool atPOC = MathAbs(price - gPOC) < tol;
   bool atVAL = MathAbs(price - gVAL) < tol;
   
   if((atPOC || atVAL) && buyP >= OF_BuyMin && deltaBuy)
   {
      for(int i = 0; i < gDemandCnt; i++)
      {
         if(!gDemand[i].active) continue;
         if(price >= gDemand[i].bottom && price <= gDemand[i].top && gDemand[i].str >= SD_MinStrength)
         {
            string reason = StringFormat("%s str=%.0f", atPOC ? "POC" : "VAL", gDemand[i].str);
            if(EnableDeltaBubble) reason += StringFormat(" DStr=%d %s", deltaStr, gDeltaDesc);
            SendBuy(price, reason, gDemand[i].str + deltaStr * 0.1, buyP);
            return;
         }
      }
   }
   
   // SELL: at POC/VAH + supply zone + sell flow + delta confirm
   bool atVAH = MathAbs(price - gVAH) < tol;
   
   if((atPOC || atVAH) && sellP >= (1.0 - OF_SellMin) && deltaSell)
   {
      for(int i = 0; i < gSupplyCnt; i++)
      {
         if(!gSupply[i].active) continue;
         if(price >= gSupply[i].bottom && price <= gSupply[i].top && gSupply[i].str >= SD_MinStrength)
         {
            string reason = StringFormat("%s str=%.0f", atVAH ? "VAH" : "POC", gSupply[i].str);
            if(EnableDeltaBubble) reason += StringFormat(" DStr=%d %s", deltaStr, gDeltaDesc);
            SendSell(price, reason, gSupply[i].str + deltaStr * 0.1, sellP);
            return;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| COMPUTE VP                                                         |
//+------------------------------------------------------------------+
void ComputeVP()
{
   gVPValid = false;
   
   double hi[], lo[], cl[];
   long vol[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);
   ArraySetAsSeries(cl, true);
   ArraySetAsSeries(vol, true);
   
   if(CopyHigh(_Symbol, EntryTF, 0, VP_Bars, hi) < VP_Bars) return;
   CopyLow(_Symbol, EntryTF, 0, VP_Bars, lo);
   CopyClose(_Symbol, EntryTF, 0, VP_Bars, cl);
   CopyTickVolume(_Symbol, EntryTF, 0, VP_Bars, vol);
   
   double minP = hi[0], maxP = lo[0];
   for(int i = 1; i < VP_Bars; i++)
   {
      if(hi[i] > maxP) maxP = hi[i];
      if(lo[i] < minP) minP = lo[i];
   }
   
   double range = maxP - minP;
   if(range < VP_BucketPips) return;
   
   int nBuckets = MathMin((int)(range / VP_BucketPips) + 1, 300);
   double bv[];
   ArrayResize(bv, nBuckets);
   ArrayInitialize(bv, 0);
   
   for(int i = 0; i < VP_Bars; i++)
   {
      if(vol[i] <= 0) continue;
      int s = MathMax(0, MathMin((int)((lo[i] - minP) / VP_BucketPips), nBuckets - 1));
      int e = MathMax(0, MathMin((int)((hi[i] - minP) / VP_BucketPips), nBuckets - 1));
      int span = e - s + 1;
      if(span < 1) span = 1;
      double vpb = vol[i] / span;
      for(int b = s; b <= e; b++)
         if(b >= 0 && b < nBuckets) bv[b] += vpb;
   }
   
   // POC
   int pocI = 0;
   double maxV = 0;
   for(int i = 0; i < nBuckets; i++)
      if(bv[i] > maxV) { maxV = bv[i]; pocI = i; }
   
   gPOC = minP + (pocI + 0.5) * VP_BucketPips;
   
   // Value area
   double totalV = 0;
   for(int i = 0; i < nBuckets; i++) totalV += bv[i];
   double vaTarget = totalV * VP_VAAPct / 100.0;
   double vaV = bv[pocI];
   int li = pocI, hi2 = pocI;
   
   while(vaV < vaTarget && (li > 0 || hi2 < nBuckets - 1))
   {
      double dv = (li > 0) ? bv[li-1] : 0;
      double uv = (hi2 < nBuckets - 1) ? bv[hi2+1] : 0;
      if(dv >= uv && li > 0) { li--; vaV += bv[li]; }
      else if(hi2 < nBuckets - 1) { hi2++; vaV += bv[hi2]; }
      else break;
   }
   
   gVAL = minP + (li + 0.5) * VP_BucketPips;
   gVAH = minP + (hi2 + 0.5) * VP_BucketPips;
   gVPValid = true;
}

//+------------------------------------------------------------------+
//| ORDER FLOW                                                         |
//+------------------------------------------------------------------+
void GetFlow(double &buyP, double &sellP)
{
   double op[], cl[];
   ArraySetAsSeries(op, true);
   ArraySetAsSeries(cl, true);
   
   if(CopyOpen(_Symbol, EntryTF, 0, OF_Bars, op) < OF_Bars) return;
   if(CopyClose(_Symbol, EntryTF, 0, OF_Bars, cl) < OF_Bars) return;
   
   int buys = 0, sells = 0;
   for(int i = 0; i < OF_Bars; i++)
   {
      if(cl[i] > op[i]) buys++;
      else if(cl[i] < op[i]) sells++;
   }
   
   double total = buys + sells;
   if(total > 0)
   {
      buyP = buys / total;
      sellP = sells / total;
   }
}

//+------------------------------------------------------------------+
//| SEND BUY                                                           |
//+------------------------------------------------------------------+
void SendBuy(double price, string vpLevel, double str, double flow)
{
   double sl = price - gATR * SL_ATR;
   double tp = price + gATR * TP_ATR;
   
   double rr = (tp - price) / (price - sl);
   if(rr < MinRR) return;
   
   double lots = CalcLots(price - sl);
   if(lots <= 0) return;
   
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lots;
   req.type = ORDER_TYPE_BUY;
   req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   req.sl = sl;
   req.tp = tp;
   req.deviation = 30;
   req.magic = MagicNumber;
   req.comment = CommentPrefix + "_BUY";
   
   if(OrderSend(req, res))
   {
      PrintFormat("BUY: %.2f lots @ %.2f | %s str=%.1f flow=%.0f%% | SL=%.2f TP=%.2f",
                  lots, req.price, vpLevel, str, flow*100, sl, tp);
      gDayTrades++;
   }
}

//+------------------------------------------------------------------+
//| SEND SELL                                                          |
//+------------------------------------------------------------------+
void SendSell(double price, string vpLevel, double str, double flow)
{
   double sl = price + gATR * SL_ATR;
   double tp = price - gATR * TP_ATR;
   
   double rr = (price - tp) / (sl - price);
   if(rr < MinRR) return;
   
   double lots = CalcLots(sl - price);
   if(lots <= 0) return;
   
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_DEAL;
   req.symbol = _Symbol;
   req.volume = lots;
   req.type = ORDER_TYPE_SELL;
   req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   req.sl = sl;
   req.tp = tp;
   req.deviation = 30;
   req.magic = MagicNumber;
   req.comment = CommentPrefix + "_SELL";
   
   if(OrderSend(req, res))
   {
      PrintFormat("SELL: %.2f lots @ %.2f | %s str=%.1f flow=%.0f%% | SL=%.2f TP=%.2f",
                  lots, req.price, vpLevel, str, flow*100, sl, tp);
      gDayTrades++;
   }
}

//+------------------------------------------------------------------+
//| CALC LOTS                                                          |
//+------------------------------------------------------------------+
double CalcLots(double slDist)
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk = bal * RiskPerTradePct / 100.0;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   
   if(tv <= 0 || ts <= 0 || slDist <= 0) return 0;
   
   double lots = risk / (slDist / ts * tv);
   
   double minL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxL = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lots = MathFloor(lots / step) * step;
   lots = MathMax(lots, minL);
   lots = MathMin(lots, maxL);
   
   return lots;
}

//+------------------------------------------------------------------+
//| MANAGE OPEN                                                        |
//+------------------------------------------------------------------+
void ManageOpen()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      
      double price = (type == POSITION_TYPE_BUY) ?
                     SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                     SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      
      // Break-even
      if(UseBE)
      {
         if(type == POSITION_TYPE_BUY && price >= op + gATR * BE_TriggerATR && sl < op)
            ModTicket(ticket, op + gATR * 0.1, tp);
         else if(type == POSITION_TYPE_SELL && price <= op - gATR * BE_TriggerATR && (sl > op || sl == 0))
            ModTicket(ticket, op - gATR * 0.1, tp);
      }
      
      // Trailing
      if(UseTrail)
      {
         double start = gATR * TrailStartATR;
         double step = gATR * TrailStepATR;
         
         if(type == POSITION_TYPE_BUY && price - op >= start)
         {
            double newSL = price - step;
            if(newSL > sl) ModTicket(ticket, newSL, tp);
         }
         else if(type == POSITION_TYPE_SELL && op - price >= start)
         {
            double newSL = price + step;
            if(newSL < sl || sl == 0) ModTicket(ticket, newSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MODIFY                                                             |
//+------------------------------------------------------------------+
bool ModTicket(ulong ticket, double sl, double tp)
{
   MqlTradeRequest req = {};
   MqlTradeResult res = {};
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = sl;
   req.tp = tp;
   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| COMMENT                                                            |
//+------------------------------------------------------------------+
void ShowComment()
{
   string c = "=== ScalpMaster Pro v3.0 ===\n";
   c += StringFormat("ATR: %.2f | Pos: %d/%d | Trades: %d/%d\n",
                     gATR, CountPos(), MaxPositions, gDayTrades, MaxTradesPerDay);
   c += StringFormat("Daily P/L: $%.2f\n", gDailyPnL);
   if(gVPValid)
      c += StringFormat("VP: POC=%.2f VAH=%.2f VAL=%.2f\n", gPOC, gVAH, gVAL);
   c += StringFormat("S/D: %d supply, %d demand\n", gSupplyCnt, gDemandCnt);
   
   if(EnableDeltaBubble && gDeltaEngine != NULL)
   {
      c += StringFormat("Delta: %.0f | Ratio: %.2f | Bubbles: %d\n",
                        gDeltaData.delta, gDeltaData.deltaRatio, gDeltaData.bubbleCount);
      if(gDeltaData.absorption) c += ">> ABSORPTION DETECTED <<\n";
      if(gDeltaData.deltaShift) c += ">> DELTA SHIFT <<\n";
      if(gDeltaData.strongBuy) c += ">> STRONG BUY PRESSURE <<\n";
      if(gDeltaData.strongSell) c += ">> STRONG SELL PRESSURE <<\n";
   }
   
   Comment(c);
}
//+------------------------------------------------------------------+
