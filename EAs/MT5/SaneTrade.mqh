//+------------------------------------------------------------------+
//| SaneTrade.mqh — shared protection layer (metals + forex)          |
//| Movement filter, news blackout, holiday skip, PH time, day locks  |
//| All symbols prefixed SANE_ to avoid clashes with EA code.         |
//+------------------------------------------------------------------+
#property copyright "SaneTrade shared guards v1.0"

int SANE_PHHour()
{
   MqlDateTime d;
   TimeToStruct(TimeGMT() + 8 * 3600, d);
   return d.hour;
}

int SANE_PHMinutes()
{
   MqlDateTime d;
   TimeToStruct(TimeGMT() + 8 * 3600, d);
   return d.hour * 60 + d.min;
}

void SANE_PHDate(int &Y, int &M, int &D)
{
   MqlDateTime d;
   TimeToStruct(TimeGMT() + 8 * 3600, d);
   Y = d.year; M = d.mon; D = d.day;
}

string SANE_TodayPH()
{
   int Y, M, D;
   SANE_PHDate(Y, M, D);
   return StringFormat("%04d.%02d.%02d", Y, M, D);
}

bool SANE_InHourWindow(int h, int s, int e)
{
   if(s <= e) return (h >= s && h < e);
   return (h >= s || h < e);
}

//--- Movement: last closed bar on tf must range >= minPts (dead market = no trade)
bool SANE_HasMovement(string sym, ENUM_TIMEFRAMES tf, int minPts)
{
   double hi = iHigh(sym, tf, 1);
   double lo = iLow(sym, tf, 1);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(hi <= 0 || lo <= 0 || pt <= 0) return false;
   return ((hi - lo) / pt >= (double)minPts);
}

//--- News/holiday file: "YYYY.MM.DD HH:MM-HH:MM CCY" + "HOLIDAY:YYYY.MM.DD" (PH time)
string SANE_NewsDate[]; int SANE_NewsStart[]; int SANE_NewsEnd[]; string SANE_NewsCcy[];
string SANE_HoliDates[]; datetime SANE_NewsLoaded = 0;

void SANE_ReloadNewsFile()
{
   ArrayResize(SANE_NewsDate, 0); ArrayResize(SANE_NewsStart, 0);
   ArrayResize(SANE_NewsEnd, 0); ArrayResize(SANE_NewsCcy, 0);
   ArrayResize(SANE_HoliDates, 0);
   SANE_NewsLoaded = TimeCurrent();
   int h = FileOpen("FXPair_NewsBlackout.txt", FILE_READ | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(StringLen(line) < 10 || StringGetCharacter(line, 0) == '#') continue;
      if(StringFind(line, "HOLIDAY:") == 0)
      {
         int n = ArraySize(SANE_HoliDates);
         ArrayResize(SANE_HoliDates, n + 1);
         SANE_HoliDates[n] = StringSubstr(line, 8, 10);
         continue;
      }
      string p[];
      if(StringSplit(line, ' ', p) < 3) continue;
      string t[];
      if(StringSplit(p[1], '-', t) < 2) continue;
      int n2 = ArraySize(SANE_NewsDate);
      ArrayResize(SANE_NewsDate, n2 + 1); ArrayResize(SANE_NewsStart, n2 + 1);
      ArrayResize(SANE_NewsEnd, n2 + 1); ArrayResize(SANE_NewsCcy, n2 + 1);
      SANE_NewsDate[n2] = p[0];
      SANE_NewsStart[n2] = (int)StringToInteger(StringSubstr(t[0], 0, 2)) * 60 + (int)StringToInteger(StringSubstr(t[0], 3, 2));
      SANE_NewsEnd[n2] = (int)StringToInteger(StringSubstr(t[1], 0, 2)) * 60 + (int)StringToInteger(StringSubstr(t[1], 3, 2));
      string cc = p[2]; StringToUpper(cc);
      SANE_NewsCcy[n2] = cc;
   }
   FileClose(h);
}

bool SANE_IsHoliday()
{
   int Y, M, D;
   SANE_PHDate(Y, M, D);
   if((M == 12 && D == 25) || (M == 1 && D == 1)) return true;
   string today = SANE_TodayPH();
   for(int i = 0; i < ArraySize(SANE_HoliDates); i++)
      if(SANE_HoliDates[i] == today) return true;
   return false;
}

bool SANE_IsNewsBlocked(string sym)
{
   if(TimeCurrent() - SANE_NewsLoaded >= 3600) SANE_ReloadNewsFile();
   if(ArraySize(SANE_NewsDate) == 0) return false;
   string u = sym;
   StringToUpper(u);
   string today = SANE_TodayPH();
   int nowMin = SANE_PHMinutes();
   for(int i = 0; i < ArraySize(SANE_NewsDate); i++)
   {
      if(SANE_NewsDate[i] != today) continue;
      if(nowMin < SANE_NewsStart[i] || nowMin >= SANE_NewsEnd[i]) continue;
      if(SANE_NewsCcy[i] == "ALL" || StringFind(u, SANE_NewsCcy[i]) >= 0) return true;
   }
   return false;
}

//--- Day lock: returns -1 = loss halt, +1 = profit lock, 0 = ok (balance-based, realized)
int SANE_DayLock(double dayStartBal, double curBal, double lossPct, double lockPct)
{
   if(dayStartBal <= 0) return 0;
   double pct = (curBal - dayStartBal) / dayStartBal * 100.0;
   if(-pct >= lossPct) return -1;
   if(pct >= lockPct) return 1;
   return 0;
}

//--- Fresh ATR snapshot (self-contained handle, released immediately)
double SANE_ATR(string sym, ENUM_TIMEFRAMES tf, int period)
{
   int h = iATR(sym, tf, period);
   if(h == INVALID_HANDLE) return 0;
   double b[];
   ArraySetAsSeries(b, true);
   double v = 0;
   if(CopyBuffer(h, 0, 1, 1, b) > 0) v = b[0];
   IndicatorRelease(h);
   return v;
}

//--- Direction clarity: |fastMA-slowMA| must span minSep x ATR (else chop — no trade)
bool SANE_MASeparationOK(string sym, ENUM_TIMEFRAMES tf, int fastP, int slowP, double atr, double minSep)
{
   if(atr <= 0) return false;
   int hf = iMA(sym, tf, fastP, 0, MODE_EMA, PRICE_CLOSE);
   int hs = iMA(sym, tf, slowP, 0, MODE_EMA, PRICE_CLOSE);
   if(hf == INVALID_HANDLE || hs == INVALID_HANDLE)
   {
      if(hf != INVALID_HANDLE) IndicatorRelease(hf);
      if(hs != INVALID_HANDLE) IndicatorRelease(hs);
      return false;
   }
   double bf[], bs[];
   ArraySetAsSeries(bf, true); ArraySetAsSeries(bs, true);
   bool ok = false;
   if(CopyBuffer(hf, 0, 1, 1, bf) > 0 && CopyBuffer(hs, 0, 1, 1, bs) > 0)
      ok = (MathAbs(bf[0] - bs[0]) / atr >= minSep);
   IndicatorRelease(hf); IndicatorRelease(hs);
   return ok;
}

//--- Smart exit: euthanize bled-out (>deadATR after deadH) + stale (<=0 after maxH) trades
int SANE_SmartExit(string sym, long magic, double atr, double deadATR, double deadH, double maxH,
                   int slippage, ENUM_ORDER_TYPE_FILLING fill, string tag)
{
   if(atr <= 0) return 0;
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   if(pt <= 0) return 0;
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double px = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK));
      double ageH = (double)(TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME)) / 3600.0;
      double ppts = (type == POSITION_TYPE_BUY ? (px - entry) : (entry - px)) / pt;
      bool dead = (ppts < 0 && (-ppts * pt) / atr >= deadATR && ageH >= deadH);
      bool stale = (ppts <= 0 && ageH >= maxH);
      if(!dead && !stale) continue;
      MqlTradeRequest r; ZeroMemory(r);
      MqlTradeResult z; ZeroMemory(z);
      r.action = TRADE_ACTION_DEAL; r.symbol = sym; r.volume = vol;
      r.type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      r.price = px; r.position = ticket; r.deviation = slippage; r.magic = (ulong)magic;
      r.comment = tag; r.type_filling = fill;
      if(OrderSend(r, z) && z.retcode == TRADE_RETCODE_DONE)
      {
         closed++;
         Print("SANE EXIT ", sym, " #", ticket, (dead ? " bled " : " stale "), DoubleToString(ageH, 1), "h");
      }
   }
   return closed;
}

//--- Flatten: close ALL positions for (sym, magic) at market (day-trade flat, Friday-style)
int SANE_FlattenAll(string sym, long magic, int slippage, ENUM_ORDER_TYPE_FILLING fill, string tag)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != sym) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      long type = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double px = (type == POSITION_TYPE_BUY ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK));
      MqlTradeRequest r; ZeroMemory(r);
      MqlTradeResult z; ZeroMemory(z);
      r.action = TRADE_ACTION_DEAL; r.symbol = sym; r.volume = vol;
      r.type = (type == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
      r.price = px; r.position = ticket; r.deviation = slippage; r.magic = (ulong)magic;
      r.comment = tag; r.type_filling = fill;
      if(OrderSend(r, z) && z.retcode == TRADE_RETCODE_DONE) closed++;
   }
   if(closed > 0) Print("SANE FLAT ", sym, " closed=", closed, " (", tag, ")");
   return closed;
}

//--- Volume: last closed bar tick-volume vs average (dead tape = no trade)
bool SANE_RelVolumeOK(string sym, ENUM_TIMEFRAMES tf, int lookback, double minRel)
{
   if(lookback < 2) return true;
   long vols[];
   ArraySetAsSeries(vols, true);
   if(CopyTickVolume(sym, tf, 1, lookback + 1, vols) < lookback + 1) return false;
   double avg = 0;
   for(int i = 1; i <= lookback; i++) avg += (double)vols[i];
   avg /= (double)lookback;
   if(avg <= 0) return false;
   return ((double)vols[0] >= avg * minRel);
}

//--- Detect broker fill mode for a symbol
ENUM_ORDER_TYPE_FILLING SANE_DetectFill(string sym)
{
   long f = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((f & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((f & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}
//+------------------------------------------------------------------+
