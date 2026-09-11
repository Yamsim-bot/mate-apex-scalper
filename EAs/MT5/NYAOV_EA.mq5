//+------------------------------------------------------------------+
//| NYAOV_EA.mq5 — XAUUSD NY 9:30 opening-range (AOV) breakout        |
//| Ported from Pine "XAUUSD NY 9:30 AOV Strategy v3".                |
//| Logic: capture 9:30 NY bar high/low; trade the first close-cross  |
//| breakout (buffered) with EMA200 filter; one trade/day; RR 2.0;    |
//| flat 16:00 NY. SaneTrade guards: movement, news, holiday, day    |
//| locks, smart exit. No martingale/grid/hedge — prop-firm clean.    |
//+------------------------------------------------------------------+
#property copyright "NY AOV port v1.0"
#property version   "1.10"
#property description "XAUUSD NY 9:30 AOV breakout, one trade/day, RR 2.0"

#include "SaneTrade.mqh"

//--- Entry
input ENUM_TIMEFRAMES EntryTF      = PERIOD_M5;  // Entry timeframe (M1/M5/M15)
input double   AOVBuffer           = 0.50;       // Breakout buffer beyond zone ($)
input double   SLBuffer            = 3.00;       // SL buffer beyond opposite edge ($)
input bool     UseEMAFilter        = true;       // Require close on correct side of EMA200
input int      EMAPeriod           = 200;        // EMA period (entry TF)
//--- Risk
input double   RiskPerTradePct     = 0.5;        // % risk per trade (fleet standard)
input double   RRTarget            = 2.0;        // Risk:reward target
input double   MaxDailyLossPct     = 2.0;        // Halt new entries at this daily loss %
input int      MaxSlippagePts      = 50;
//--- SaneTrade guards
input bool     SaneMovement        = true;
input int      SaneMinMovePts      = 200;        // Min M15 bar range, points ($2 gold)
input bool     SaneNews            = true;
input bool     SaneHoliday         = true;
input double   SaneProfitLockPct   = 5.0;
input bool     SaneSmartExit       = true;
input double   SaneDeadExitATR     = 0.8;
input double   SaneDeadExitMinH    = 2.0;
input double   SaneMaxHoldHours    = 8.0;
//--- Friday/weekend lockdown (never trade closed markets or weekends)
input bool     WeekendBlock        = true;         // No new entries Sat/Sun (NY calendar)
input bool     FridayCutoff        = true;         // No new entries late Friday (avoid weekend gap risk)
input int      FridayCutHourNY     = 15;           // Friday entries stop at this NY hour
//--- General
input ulong    MagicNumber         = 20260911;
input string   CommentPrefix       = "NYAOV";
input bool     DebugMode           = true;

//--- State
double   g_aovHigh = 0, g_aovLow = 0;
int      g_aovDayKey = 0;
bool     g_tradeToday = false;
datetime g_lastBar = 0;
int      g_hEMA = INVALID_HANDLE, g_hATR = INVALID_HANDLE;
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_IOC;
double   g_dayStartBal = 0;
int      g_dayKey = 0;
bool     g_paused = false;

//--- US DST: EDT (UTC-4) from 2nd Sun Mar to 1st Sun Nov, else EST (UTC-5)
int NYOffsetHours()
{
   MqlDateTime g;
   TimeGMT(g);
   if(g.mon > 3 && g.mon < 11) return -4;
   if(g.mon < 3 || g.mon > 11) return -5;
   // March: DST from 2nd Sunday; November: to 1st Sunday
   int firstDow = (8 - g.day) % 7; // not exact — compute 1st Sunday:
   // weekday of the 1st: backtrack from today
   int dowFirst = (g.day_of_week - ((g.day - 1) % 7) + 14) % 7;
   int firstSun = 1 + ((7 - dowFirst) % 7);
   if(g.mon == 3) return (g.day >= firstSun + 7) ? -4 : -5;
   return (g.day < firstSun) ? -4 : -5; // November
}

void NYTime(int &dayKey, int &hh, int &mm)
{
   MqlDateTime d;
   TimeToStruct(TimeGMT() + NYOffsetHours() * 3600, d);
   dayKey = d.year * 10000 + d.mon * 100 + d.day;
   hh = d.hour; mm = d.min;
}

int NYDow()
{
   MqlDateTime d;
   TimeToStruct(TimeGMT() + NYOffsetHours() * 3600, d);
   return d.day_of_week; // 0=Sun .. 6=Sat
}

bool MarketOpenForEntries()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return false;
   ResetLastError();
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(GetLastError() != 0) return false;
   return (mode == SYMBOL_TRADE_MODE_FULL);
}

double CalcLot(double slDist)
{
   if(slDist <= 0) return 0;
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskCash = bal * RiskPerTradePct / 100.0;
   double tickV = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickS = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickV <= 0 || tickS <= 0) return 0;
   double lots = riskCash / (slDist / tickS * tickV);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / st) * st;
   return MathMin(MathMax(lots, mn), mx);
}

int OnInit()
{
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) != 0) g_fillMode = ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC) != 0) g_fillMode = ORDER_FILLING_IOC;
   else g_fillMode = ORDER_FILLING_RETURN;
   g_hEMA = iMA(_Symbol, EntryTF, EMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hATR = iATR(_Symbol, PERIOD_M15, 14);
   if(g_hEMA == INVALID_HANDLE || g_hATR == INVALID_HANDLE) return INIT_FAILED;
   int dk, hh, mm;
   NYTime(dk, hh, mm);
   g_dayKey = dk;
   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   Print("NYAOV v1.10 lockdown initialized on ", _Symbol, " ", EnumToString(EntryTF),
         " | 9:30 NY = 21:30 PH (EDT) | RR=", RRTarget);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_hEMA != INVALID_HANDLE) IndicatorRelease(g_hEMA);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   Comment("");
}

bool HasOpen()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      return true;
   }
   return false;
}

void TryCloseFlat(string tag)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest r; ZeroMemory(r);
      MqlTradeResult z; ZeroMemory(z);
      r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol;
      r.volume = PositionGetDouble(POSITION_VOLUME);
      r.type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      r.price = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK));
      r.position = t; r.deviation = MaxSlippagePts; r.magic = MagicNumber;
      r.comment = tag; r.type_filling = g_fillMode;
      if(OrderSend(r, z) && z.retcode == TRADE_RETCODE_DONE)
         Print("NYAOV FLAT #", t, " (", tag, ")");
   }
}

bool SendEntry(bool isBuy, double sl, double tp)
{
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double px = isBuy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double slDist = isBuy ? (px - sl) : (sl - px);
   double lots = CalcLot(slDist);
   if(lots <= 0) return false;
   MqlTradeRequest r; ZeroMemory(r);
   MqlTradeResult z; ZeroMemory(z);
   r.action = TRADE_ACTION_DEAL; r.symbol = _Symbol; r.volume = lots;
   r.type = (isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   r.price = px; r.sl = NormalizeDouble(sl, dg); r.tp = NormalizeDouble(tp, dg);
   r.deviation = MaxSlippagePts; r.magic = MagicNumber;
   r.comment = CommentPrefix + (isBuy ? "_BUY" : "_SELL");
   r.type_filling = g_fillMode;
   if(!OrderSend(r, z) || z.retcode != TRADE_RETCODE_DONE)
   {
      Print("NYAOV ENTRY FAILED: ", z.retcode, " ", z.comment);
      return false;
   }
   Print("NYAOV ", (isBuy ? "BUY " : "SELL "), _Symbol, " ", lots, " lots SL=", sl, " TP=", tp);
   return true;
}

void OnTick()
{
   //--- Day reset on NY calendar
   int dk, hh, mm;
   NYTime(dk, hh, mm);
   if(dk != g_dayKey)
   {
      g_dayKey = dk;
      g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
      g_tradeToday = false;
      g_aovDayKey = 0;
      g_paused = false;
   }

   //--- Day locks (realized, balance-based)
   if(g_dayStartBal > 0 && !g_paused)
   {
      double bal = AccountInfoDouble(ACCOUNT_BALANCE);
      double pct = (bal - g_dayStartBal) / g_dayStartBal * 100.0;
      if(-pct >= MaxDailyLossPct || pct >= SaneProfitLockPct)
      {
         g_paused = true;
         Print("NYAOV day lock: ", DoubleToString(pct, 2), "%. No new entries.");
      }
   }

   //--- Manage + smart exit every tick
   double ab[], ae[];
   ArraySetAsSeries(ab, true); ArraySetAsSeries(ae, true);
   double atr = 0;
   if(CopyBuffer(g_hATR, 0, 1, 1, ab) > 0) atr = ab[0];
   if(SaneSmartExit && atr > 0)
      SANE_SmartExit(_Symbol, (long)MagicNumber, atr, SaneDeadExitATR, SaneDeadExitMinH,
                     SaneMaxHoldHours, MaxSlippagePts, g_fillMode, "NYAOV_EXIT");

   //--- 16:00 NY flat (day-trade role)
   if(hh == 16 && mm == 0) TryCloseFlat("NYCLOSE");

   if(g_paused || g_tradeToday || HasOpen()) return;

   //--- Weekend lockdown: never fire entries Sat/Sun (NY calendar)
   int dow = NYDow();
   if(WeekendBlock && (dow == 0 || dow == 6))
   {
      if(DebugMode) Print("NYAOV skip: weekend (no entries)");
      return;
   }
   //--- Friday cutoff: no late entries into weekend gap risk
   if(FridayCutoff && dow == 5 && hh >= FridayCutHourNY)
   {
      if(DebugMode) Print("NYAOV skip: Friday cutoff");
      return;
   }
   //--- Market actually open for trading?
   if(!MarketOpenForEntries()) return;

   //--- New bar only (close-cross entries like Pine)
   datetime bt = iTime(_Symbol, EntryTF, 0);
   if(bt == g_lastBar) return;
   g_lastBar = bt;
   MqlDateTime bd;
   TimeToStruct(bt + NYOffsetHours() * 3600, bd);

   //--- Capture 9:30 NY bar as AOV zone
   if(bd.hour == 9 && bd.min == 30 && g_aovDayKey != dk)
   {
      g_aovHigh = iHigh(_Symbol, EntryTF, 1);
      g_aovLow = iLow(_Symbol, EntryTF, 1);
      // bar 1 may still be forming at :30 edge — use the completed 9:25 bar on M5
      if(g_aovHigh <= 0 || g_aovLow <= 0 || g_aovHigh <= g_aovLow) return;
      g_aovDayKey = dk;
      g_tradeToday = false;
      Print("NYAOV zone set: ", DoubleToString(g_aovLow, 2), " - ", DoubleToString(g_aovHigh, 2));
      return;
   }
   if(g_aovDayKey != dk || g_aovHigh <= g_aovLow) return; // no zone yet

   //--- SaneTrade entry gates
   if(SaneHoliday && SANE_IsHoliday()) return;
   if(SaneNews && SANE_IsNewsBlocked(_Symbol)) return;
   if(SaneMovement && !SANE_HasMovement(_Symbol, PERIOD_M15, SaneMinMovePts))
   {
      if(DebugMode) Print("NYAOV skip: flat market");
      return;
   }

   //--- EMA200 filter (entry TF, closed bar)
   double eb[];
   ArraySetAsSeries(eb, true);
   double ema = 0;
   if(CopyBuffer(g_hEMA, 0, 1, 1, eb) > 0) ema = eb[0];
   double c1 = iClose(_Symbol, EntryTF, 1);
   double c2 = iClose(_Symbol, EntryTF, 2);
   if(c1 <= 0 || c2 <= 0 || ema <= 0) return;
   bool longOK = !UseEMAFilter || c1 > ema;
   bool shortOK = !UseEMAFilter || c1 < ema;

   //--- Breakout cross (Pine-faithful close-cross + buffer)
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(longOK && c1 > g_aovHigh + AOVBuffer && c2 <= g_aovHigh + AOVBuffer)
   {
      double sl = NormalizeDouble(g_aovLow - SLBuffer, dg);
      double tp = NormalizeDouble(c1 + (c1 - sl) * RRTarget, dg);
      if(SendEntry(true, sl, tp)) g_tradeToday = true;
   }
   else if(shortOK && c1 < g_aovLow - AOVBuffer && c2 >= g_aovLow - AOVBuffer)
   {
      double sl = NormalizeDouble(g_aovHigh + SLBuffer, dg);
      double tp = NormalizeDouble(c1 - (sl - c1) * RRTarget, dg);
      if(SendEntry(false, sl, tp)) g_tradeToday = true;
   }
}
//+------------------------------------------------------------------+
