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
//+------------------------------------------------------------------+
