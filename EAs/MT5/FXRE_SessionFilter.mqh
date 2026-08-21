//+------------------------------------------------------------------+
//|                                            FXRE_SessionFilter.mqh|
//|               FXRE Ultimate AI Replication — Session & Time Filter|
//+------------------------------------------------------------------+
//| FXRE Session Filter — no #property (included from main EA)


//+------------------------------------------------------------------+
//| Get current hour in PH Time (UTC+8)                              |
//+------------------------------------------------------------------+
int PHTimeHour()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int phHour = dt.hour + 8;
   if(phHour >= 24) phHour -= 24;
   if(phHour < 0)   phHour += 24;
   return phHour;
}

int PHTimeMin()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   return dt.min;
}

int PHTimeDayOfWeek()
{
   MqlDateTime dt;
   TimeTradeServer(dt);
   int phHour = dt.hour + 8;
   int phDow  = dt.day_of_week;
   if(phHour >= 24) { phDow++; if(phDow > 6) phDow = 0; }
   return phDow;
}

//+------------------------------------------------------------------+
//| Check if current PH time is within trading session               |
//+------------------------------------------------------------------+
bool IsInSession()
{
   if(!UseSessionFilter) return true;

   int phHour = PHTimeHour();
   int phMin  = PHTimeMin();
   int sessionStartMinutes = SessionStartHour * 60 + SessionStartMin;
   int sessionEndMinutes   = SessionEndHour   * 60 + SessionEndMin;
   int currentMinutes      = phHour * 60 + phMin;

   if(sessionStartMinutes < sessionEndMinutes)
      return (currentMinutes >= sessionStartMinutes && currentMinutes < sessionEndMinutes);
   else
      return (currentMinutes >= sessionStartMinutes || currentMinutes < sessionEndMinutes);
}

//+------------------------------------------------------------------+
//| Check if current day is valid for trading                        |
//+------------------------------------------------------------------+
bool IsTradingDay()
{
   if(!UseSessionFilter) return true;
   int phDow = PHTimeDayOfWeek();
   switch(phDow)
   {
      case 1: return TradeMonday;
      case 2: return TradeTuesday;
      case 3: return TradeWednesday;
      case 4: return TradeThursday;
      case 5: return TradeFriday;
      default: return false;
   }
}

//+------------------------------------------------------------------+
//| Combined check                                                   |
//+------------------------------------------------------------------+
bool ShouldTradeNow()
{
   if(!UseSessionFilter) return true;
   return IsTradingDay() && IsInSession();
}

//+------------------------------------------------------------------+
//| Status string                                                    |
//+------------------------------------------------------------------+
string GetSessionStatus()
{
   if(!UseSessionFilter) return "No filter";

   int phHour = PHTimeHour();
   int phMin  = PHTimeMin();
   int phDow  = PHTimeDayOfWeek();
   string dayNames[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   string status = dayNames[phDow] + " " + IntegerToString(phHour) + ":" + StringFormat("%02d", phMin) + " PH | ";

   if(IsTradingDay() && IsInSession())
      status += "SESSION ACTIVE";
   else if(!IsTradingDay())
      status += "NOT A TRADING DAY";
   else
      status += "OUTSIDE SESSION HOURS";

   return status;
}
//+------------------------------------------------------------------+
