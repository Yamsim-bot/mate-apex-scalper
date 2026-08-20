//+------------------------------------------------------------------+
//|                                              ScalpMaster.mq5     |
//|                          Scalp EA for XAU & XAG — RSI + S/R      |
//|                          Sessions: Asian, London, NY              |
//|                          Risk: 0.5% per trade, ATR-based TP/SL   |
//+------------------------------------------------------------------+
#property copyright "Yams Mate Scalper"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "=== General ==="
input string   InpSymbol       = "XAUUSD";       // Symbol (XAUUSD or XAGUSD)
input ENUM_TIMEFRAMES InpTF    = PERIOD_M5;       // Timeframe
input int      InpMagic        = 777777;          // Magic Number
input double   InpRiskPct      = 0.5;             // Risk per trade (%)
input int      InpMaxTrades    = 3;               // Max trades per session
input double   InpMaxDDPct     = 3.0;             // Max daily drawdown (%)
input bool     InpDebug        = true;             // Debug mode

input group "=== RSI ==="
input int      InpRSI_Period   = 14;              // RSI Period
input int      InpRSI_OB       = 70;              // RSI Overbought
input int      InpRSI_OS       = 30;              // RSI Oversold
input ENUM_TIMEFRAMES InpRSI_TF = PERIOD_M5;     // RSI Timeframe

input group "=== S/R ==="
input int      InpSR_Lookback  = 50;              // Swing Lookback bars
input int      InpSR_SwingLen  = 3;               // Swing length (bars each side)
input double   InpSR_ZoneATR   = 0.5;             // Zone tolerance (x ATR)
input int      InpSR_MinTouches = 2;              // Min touches for valid level

input group "=== TP / SL ==="
input double   InpSL_ATR       = 1.5;             // SL (x ATR)
input double   InpTP_ATR       = 2.5;             // TP (x ATR)
input double   InpRR_Min       = 1.5;             // Min Risk:Reward
input bool     InpUseTrail     = true;             // Use trailing stop
input double   InpTrail_ATR    = 1.0;             // Trailing (x ATR)

input group "=== Session (GMT) ==="
input int      InpAsianStart   = 0;               // Asian Start
input int      InpAsianEnd     = 8;               // Asian End
input int      InpLondonStart  = 8;               // London Start
input int      InpLondonEnd    = 13;              // London End
input int      InpNYStart      = 13;              // NY Start
input int      InpNYEnd        = 21;              // NY End
input int      InpGMTOffset    = 3;               // Broker GMT Offset

input group "=== Filters ==="
input bool     InpUseSpreadFilter = true;          // Max spread filter
input int      InpMaxSpread    = 30;              // Max spread (points)
input bool     InpUseATRFilter = true;             // Min ATR filter
input double   InpMinATR       = 0.5;             // Min ATR for entry

enum SessionType { SESS_NONE=-1, SESS_ASIAN=0, SESS_LONDON=1, SESS_NY=2 };

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
CTrade         trade;
int            handleRSI;
int            handleATR;
double         g_atr;
int            g_sessionTrades;
int            g_dailyTrades;
double         g_sessionStartEq;
double         g_dayStartEq;
datetime       g_lastBarTime;
datetime       g_lastEntryBar;
datetime       g_lastDay;
SessionType    g_currentSession;
SessionType    g_lastSession;

// S/R levels
struct SRLevel {
   double price;
   int    touches;
   bool   isSupport; // true=support, false=resistance
};

SRLevel g_srLevels[];


//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate symbol
   if(StringFind(InpSymbol, "XAU") < 0 && StringFind(InpSymbol, "XAG") < 0 &&
      StringFind(InpSymbol, "GOLD") < 0 && StringFind(InpSymbol, "SILVER") < 0)
   {
      Print("WARNING: ", InpSymbol, " is not XAU or XAG. Proceeding anyway.");
   }

   // Verify symbol exists
   if(SymbolSelect(InpSymbol, true) == 0)
   {
      Print("ERROR: Symbol ", InpSymbol, " not found");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(30);
   trade.SetTypeFilling(ORDER_FILLING_IOC);

   // Indicators
   handleRSI = iRSI(InpSymbol, InpRSI_TF, InpRSI_Period, PRICE_CLOSE);
   handleATR = iATR(InpSymbol, InpTF, 14);

   if(handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles");
      return INIT_FAILED;
   }

   g_lastBarTime   = 0;
   g_lastEntryBar  = 0;
   g_lastDay       = 0;
   g_sessionTrades = 0;
   g_dailyTrades   = 0;
   g_sessionStartEq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayStartEq    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_currentSession = SESS_NONE;
   g_lastSession   = SESS_NONE;

   Print("ScalpMaster initialized on ", InpSymbol, " ", EnumToString(InpTF),
         " | Risk=", InpRiskPct, "% | Magic=", InpMagic);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   ObjectDelete(0, "sm_status");
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Daily reset
   MqlDateTime dt;
   TimeGMT(dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(today != g_lastDay)
   {
      g_lastDay       = today;
      g_dailyTrades   = 0;
      g_dayStartEq    = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("=== NEW DAY | Balance=$", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2),
            " | Trades today=", g_dailyTrades);
   }

   // New bar check
   datetime barTime = iTime(InpSymbol, InpTF, 0);
   bool newBar = (barTime != g_lastBarTime);
   if(newBar) g_lastBarTime = barTime;

   // Get ATR
   double atrBuf[];
   if(CopyBuffer(handleATR, 0, 0, 1, atrBuf) < 1) return;
   g_atr = atrBuf[0];
   if(g_atr <= 0) return;

   // Daily drawdown check
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(g_dayStartEq > 0)
   {
      double ddPct = (g_dayStartEq - eq) / g_dayStartEq * 100.0;
      if(ddPct >= InpMaxDDPct)
      {
         UpdateComment("DD LIMIT REACHED");
         return;
      }
   }

   // Update session
   g_currentSession = GetSession();
   if(g_currentSession != g_lastSession)
   {
      g_sessionTrades = 0;
      g_sessionStartEq = eq;
      g_lastSession = g_currentSession;
   }

   // Scan S/R on new bar
   if(newBar)
   {
      ScanSR();
   }

   // Manage open positions (trailing)
   if(InpUseTrail) ManageTrailing();

   // Entry check
   if(g_dailyTrades >= InpMaxTrades) { UpdateComment("MAX TRADES"); return; }
   if(g_sessionTrades >= InpMaxTrades) { UpdateComment("SESSION LIMIT"); return; }
   if(CountPositions() >= 2) { UpdateComment("POSITION LIMIT"); return; }
   if(!newBar) return;

   CheckEntry();

   UpdateComment("");
}

//+------------------------------------------------------------------+
//| Get current session                                               |
//+------------------------------------------------------------------+
SessionType GetSession()
{
   MqlDateTime dt;
   TimeGMT(dt);
   int hour = dt.hour;

   if(hour >= InpAsianStart && hour < InpAsianEnd)  return SESS_ASIAN;
   if(hour >= InpLondonStart && hour < InpLondonEnd) return SESS_LONDON;
   if(hour >= InpNYStart && hour < InpNYEnd)         return SESS_NY;
   return SESS_NONE;
}

string SessionName(SessionType s)
{
   switch(s)
   {
      case SESS_ASIAN:  return "ASIAN";
      case SESS_LONDON: return "LONDON";
      case SESS_NY:     return "NY";
      default:          return "OFF";
   }
}

//+------------------------------------------------------------------+
//| Scan Support & Resistance levels                                  |
//+------------------------------------------------------------------+
void ScanSR()
{
   ArrayResize(g_srLevels, 0);

   double highs[], lows[];
   int bars = InpSR_Lookback + InpSR_SwingLen + 5;

   if(CopyHigh(InpSymbol, InpTF, 0, bars, highs) < bars) return;
   if(CopyLow(InpSymbol, InpTF, 0, bars, lows) < bars) return;

   // Find swing highs and lows
   for(int i = InpSR_SwingLen; i < bars - InpSR_SwingLen; i++)
   {
      // Swing high = resistance
      bool isSwingHigh = true;
      for(int j = 1; j <= InpSR_SwingLen; j++)
      {
         if(highs[i] <= highs[i-j] || highs[i] <= highs[i+j])
         { isSwingHigh = false; break; }
      }
      if(isSwingHigh) AddSRLevel(highs[i], false);

      // Swing low = support
      bool isSwingLow = true;
      for(int j = 1; j <= InpSR_SwingLen; j++)
      {
         if(lows[i] >= lows[i-j] || lows[i] >= lows[i+j])
         { isSwingLow = false; break; }
      }
      if(isSwingLow) AddSRLevel(lows[i], true);
   }

   // Cluster nearby levels
   ClusterLevels();

   if(InpDebug)
   {
      int sup=0, res=0;
      for(int i=0; i<ArraySize(g_srLevels); i++)
      {
         if(g_srLevels[i].isSupport) sup++; else res++;
      }
      Print("S/R: ", sup, " supports, ", res, " resistances");
   }
}

void AddSRLevel(double price, bool isSupport)
{
   int sz = ArraySize(g_srLevels);
   ArrayResize(g_srLevels, sz+1);
   g_srLevels[sz].price     = price;
   g_srLevels[sz].touches   = 1;
   g_srLevels[sz].isSupport = isSupport;
}

void ClusterLevels()
{
   double zoneTol = g_atr * InpSR_ZoneATR;

   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      for(int j = i+1; j < ArraySize(g_srLevels); j++)
      {
         if(g_srLevels[i].isSupport != g_srLevels[j].isSupport) continue;
         if(MathAbs(g_srLevels[i].price - g_srLevels[j].price) <= zoneTol)
         {
            // Merge: average price, sum touches
            g_srLevels[i].price   = (g_srLevels[i].price + g_srLevels[j].price) / 2.0;
            g_srLevels[i].touches += g_srLevels[j].touches;
            // Remove j
            ArrayRemove(g_srLevels, j, 1);
            j--;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Find nearest support below price                                  |
//+------------------------------------------------------------------+
double NearestSupport(double price)
{
   double best = 0;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(!g_srLevels[i].isSupport) continue;
      if(g_srLevels[i].price >= price) continue;
      if(g_srLevels[i].touches < InpSR_MinTouches) continue;
      double dist = price - g_srLevels[i].price;
      if(dist < bestDist) { bestDist = dist; best = g_srLevels[i].price; }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Find nearest resistance above price                               |
//+------------------------------------------------------------------+
double NearestResistance(double price)
{
   double best = 0;
   double bestDist = DBL_MAX;
   for(int i = 0; i < ArraySize(g_srLevels); i++)
   {
      if(g_srLevels[i].isSupport) continue;
      if(g_srLevels[i].price <= price) continue;
      if(g_srLevels[i].touches < InpSR_MinTouches) continue;
      double dist = g_srLevels[i].price - price;
      if(dist < bestDist) { bestDist = dist; best = g_srLevels[i].price; }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Check entry signals                                               |
//+------------------------------------------------------------------+
void CheckEntry()
{
   // One entry per bar
   if(g_lastEntryBar == iTime(InpSymbol, InpTF, 0)) return;

   // Session gate
   if(g_currentSession == SESS_NONE) return;

   // Spread filter
   if(InpUseSpreadFilter)
   {
      long spread = SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD);
      if(spread > InpMaxSpread) return;
   }

   // ATR filter
   if(InpUseATRFilter && g_atr < InpMinATR) return;

   // Get RSI
   double rsiBuf[];
   if(CopyBuffer(handleRSI, 0, 0, 3, rsiBuf) < 3) return;
   double rsi0 = rsiBuf[2]; // bar 1 (last closed)
   double rsi1 = rsiBuf[1]; // bar 2

   // Get price data
   double open1  = iOpen(InpSymbol, InpTF, 1);
   double close1 = iClose(InpSymbol, InpTF, 1);
   double high1  = iHigh(InpSymbol, InpTF, 1);
   double low1   = iLow(InpSymbol, InpTF, 1);
   double open0  = iOpen(InpSymbol, InpTF, 0);
   double close0 = iClose(InpSymbol, InpTF, 0);

   double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);

   bool isBull = close1 > open1;
   bool isBear = close1 < open1;

   // --- Pin bar detection ---
   double body  = MathAbs(close1 - open1);
   double lowerWick = MathMin(close1, open1) - low1;
   double upperWick = high1 - MathMax(close1, open1);

   bool bullPinBar = isBull && lowerWick > body * 2.0 && upperWick < body * 0.5;
   bool bearPinBar = isBear && upperWick > body * 2.0 && lowerWick < body * 0.5;

   // --- Engulfing detection ---
   double prevClose = iClose(InpSymbol, InpTF, 2);
   double prevOpen  = iOpen(InpSymbol, InpTF, 2);
   bool bullEngulf = isBull && prevClose < prevOpen && close1 > prevOpen && open1 < prevClose && body > MathAbs(prevClose - prevOpen);
   bool bearEngulf = isBear && prevClose > prevOpen && close1 < prevOpen && open1 > prevClose && body > MathAbs(prevClose - prevOpen);

   bool bullPA = bullPinBar || bullEngulf;
   bool bearPA = bearPinBar || bearEngulf;

   // --- BUY: RSI oversold + at support + PA confirmation ---
   if(rsi0 < InpRSI_OS && bullPA)
   {
      double support = NearestSupport(close1);
      if(support > 0 && MathAbs(close1 - support) <= g_atr * InpSR_ZoneATR)
      {
         double sl = support - g_atr * 0.3; // SL below support
         double slDist = ask - sl;
         if(slDist < g_atr * 0.5) slDist = g_atr * 0.5;
         if(slDist > g_atr * InpSL_ATR) slDist = g_atr * InpSL_ATR;
         sl = ask - slDist;

         double tp = ask + slDist * InpTP_ATR / InpSL_ATR;
         double tpDist = tp - ask;

         // Check RR
         if(tpDist / slDist < InpRR_Min) return;

         double lot = CalcLot(slDist);
         if(lot <= 0) return;

         if(trade.Buy(lot, InpSymbol, ask, sl, tp, "SM_BUY_RSI_SR"))
         {
            g_lastEntryBar = iTime(InpSymbol, InpTF, 0);
            g_sessionTrades++;
            g_dailyTrades++;
            Print("BUY ", InpSymbol, " @ ", ask, " SL=", sl, " TP=", tp,
                  " RSI=", rsi0, " Sup=", support, " Lot=", lot);
         }
      }
      // --- BUY at support without RSI but strong PA ---
      else if(support > 0 && MathAbs(close1 - support) <= g_atr * InpSR_ZoneATR && (bullPinBar && body > g_atr * 0.2))
      {
         double sl = support - g_atr * 0.3;
         double slDist = ask - sl;
         if(slDist < g_atr * 0.5) slDist = g_atr * 0.5;
         if(slDist > g_atr * InpSL_ATR) slDist = g_atr * InpSL_ATR;
         sl = ask - slDist;
         double tp = ask + slDist * InpTP_ATR / InpSL_ATR;
         if((tp - ask) / slDist < InpRR_Min) return;
         double lot = CalcLot(slDist);
         if(lot <= 0) return;

         if(trade.Buy(lot, InpSymbol, ask, sl, tp, "SM_BUY_PA_SUP"))
         {
            g_lastEntryBar = iTime(InpSymbol, InpTF, 0);
            g_sessionTrades++;
            g_dailyTrades++;
            Print("BUY ", InpSymbol, " PA@SUP | SL=", sl, " TP=", tp, " Lot=", lot);
         }
      }
   }

   // --- SELL: RSI overbought + at resistance + PA confirmation ---
   if(rsi0 > InpRSI_OB && bearPA)
   {
      double resistance = NearestResistance(close1);
      if(resistance > 0 && MathAbs(close1 - resistance) <= g_atr * InpSR_ZoneATR)
      {
         double sl = resistance + g_atr * 0.3;
         double slDist = sl - bid;
         if(slDist < g_atr * 0.5) slDist = g_atr * 0.5;
         if(slDist > g_atr * InpSL_ATR) slDist = g_atr * InpSL_ATR;
         sl = bid + slDist;

         double tp = bid - slDist * InpTP_ATR / InpSL_ATR;
         double tpDist = bid - tp;

         if(tpDist / slDist < InpRR_Min) return;

         double lot = CalcLot(slDist);
         if(lot <= 0) return;

         if(trade.Sell(lot, InpSymbol, bid, sl, tp, "SM_SELL_RSI_SR"))
         {
            g_lastEntryBar = iTime(InpSymbol, InpTF, 0);
            g_sessionTrades++;
            g_dailyTrades++;
            Print("SELL ", InpSymbol, " @ ", bid, " SL=", sl, " TP=", tp,
                  " RSI=", rsi0, " Res=", resistance, " Lot=", lot);
         }
      }
      // --- SELL at resistance with strong PA (pin bar only) ---
      else if(resistance > 0 && MathAbs(close1 - resistance) <= g_atr * InpSR_ZoneATR && (bearPinBar && body > g_atr * 0.2))
      {
         double sl = resistance + g_atr * 0.3;
         double slDist = sl - bid;
         if(slDist < g_atr * 0.5) slDist = g_atr * 0.5;
         if(slDist > g_atr * InpSL_ATR) slDist = g_atr * InpSL_ATR;
         sl = bid + slDist;
         double tp = bid - slDist * InpTP_ATR / InpSL_ATR;
         if((bid - tp) / slDist < InpRR_Min) return;
         double lot = CalcLot(slDist);
         if(lot <= 0) return;

         if(trade.Sell(lot, InpSymbol, bid, sl, tp, "SM_SELL_PA_RES"))
         {
            g_lastEntryBar = iTime(InpSymbol, InpTF, 0);
            g_sessionTrades++;
            g_dailyTrades++;
            Print("SELL ", InpSymbol, " PA@RES | SL=", sl, " TP=", tp, " Lot=", lot);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing stop management                                          |
//+------------------------------------------------------------------+
void ManageTrailing()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      long   type      = PositionGetInteger(POSITION_TYPE);

      double trailDist = g_atr * InpTrail_ATR;

      if(type == POSITION_TYPE_BUY)
      {
         double bid = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
         double newSL = bid - trailDist;
         if(newSL > sl + SymbolInfoDouble(InpSymbol, SYMBOL_POINT) && newSL < bid)
         {
            trade.PositionModify(ticket, newSL, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double ask = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
         double newSL = ask + trailDist;
         if(newSL < sl - SymbolInfoDouble(InpSymbol, SYMBOL_POINT) && newSL > ask)
         {
            trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count open positions                                              |
//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != InpSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                   |
//+------------------------------------------------------------------+
double CalcLot(double slDist)
{
   double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt  = balance * InpRiskPct / 100.0;
   double tickVal  = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickVal <= 0 || tickSize <= 0 || slDist <= 0) return 0;

   double lot = riskAmt / (slDist / tickSize * tickVal);

   // Normalize
   double minLot  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);

   if(lotStep > 0) lot = MathFloor(lot / lotStep) * lotStep;
   lot = MathMax(lot, minLot);
   lot = MathMin(lot, maxLot);

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Chart comment                                                     |
//+------------------------------------------------------------------+
void UpdateComment(string extra)
{
   string sep = "\n" + "------------------------------" + "\n";
   string info = "=== ScalpMaster ===" + sep;
   info += "Symbol: " + InpSymbol + " | TF: " + EnumToString(InpTF) + "\n";
   info += "Session: " + SessionName(g_currentSession) + " (GMT" + IntegerToString(InpGMTOffset) + ")\n";
   info += "ATR: " + DoubleToString(g_atr, 2) + "\n";

   // S/R info
   int sup=0, res=0;
   double nearestSup=0, nearestRes=DBL_MAX;
   for(int i=0; i<ArraySize(g_srLevels); i++)
   {
      if(g_srLevels[i].isSupport) { sup++; if(g_srLevels[i].price > nearestSup) nearestSup = g_srLevels[i].price; }
      else { res++; if(g_srLevels[i].price < nearestRes) nearestRes = g_srLevels[i].price; }
   }
   info += "S/R: " + IntegerToString(sup) + " supports, " + IntegerToString(res) + " resistances\n";
   if(nearestSup > 0) info += "Nearest Sup: " + DoubleToString(nearestSup, 2) + "\n";
   if(nearestRes < DBL_MAX) info += "Nearest Res: " + DoubleToString(nearestRes, 2) + "\n";

   info += "Positions: " + IntegerToString(CountPositions()) + "\n";
   info += "Trades today: " + IntegerToString(g_dailyTrades) + "/" + IntegerToString(InpMaxTrades) + "\n";
   info += "Session trades: " + IntegerToString(g_sessionTrades) + "/" + IntegerToString(InpMaxTrades) + "\n";

   if(extra != "") info += "\n" + extra;

   Comment(info);
}
//+------------------------------------------------------------------+
