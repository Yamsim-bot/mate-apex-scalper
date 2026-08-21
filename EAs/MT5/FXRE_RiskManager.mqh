//+------------------------------------------------------------------+
//|                                              FXRE_RiskManager.mqh|
//|               FXRE Ultimate AI Replication — Risk & Position Mgmt |
//+------------------------------------------------------------------+
//| FXRE Risk Manager — no #property (included from main EA)


//+------------------------------------------------------------------+
//| Structs for daily tracking                                       |
//+------------------------------------------------------------------+
struct DailyStats
{
   datetime date;
   int      tradeCount;
   double   totalPL;
   double   maxDrawdown;
   double   startingBalance;
   bool     tradingStopped;
};

DailyStats g_dailyStats;
datetime   g_lastResetDay = 0;

//+------------------------------------------------------------------+
//| Reset daily stats if new day                                     |
//+------------------------------------------------------------------+
void ResetDailyStats()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StructToTime(dt);
   today = today - (today % 86400);

   if(today != g_lastResetDay)
   {
      ZeroMemory(g_dailyStats);
      g_dailyStats.date = today;
      g_dailyStats.startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_dailyStats.tradingStopped = false;
      g_lastResetDay = today;
      Print("Daily stats reset. Balance: ", g_dailyStats.startingBalance);
   }
}

//+------------------------------------------------------------------+
//| Check if we can trade based on risk limits                       |
//+------------------------------------------------------------------+
bool CanTrade()
{
   ResetDailyStats();

   if(g_dailyStats.tradingStopped)
   {
      Comment("TRADING STOPPED: Max daily loss reached");
      return false;
   }

   if(g_dailyStats.tradeCount >= MaxDailyTrades)
   {
      Comment("TRADING STOPPED: Max daily trades (", MaxDailyTrades, ") reached");
      return false;
   }

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdownPct = 0;
   if(g_dailyStats.startingBalance > 0)
   {
      double loss = g_dailyStats.startingBalance - balance;
      drawdownPct = (loss / g_dailyStats.startingBalance) * 100.0;
   }

   if(drawdownPct >= MaxDailyLossPct)
   {
      g_dailyStats.tradingStopped = true;
      Print("STOPPED: Daily loss limit reached. Loss=", DoubleToString(drawdownPct, 2), "%");
      return false;
   }

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts)
   {
      Comment("SPREAD TOO HIGH: ", spread, " pts (max ", MaxSpreadPts, ")");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk % and SL distance               |
//+------------------------------------------------------------------+
double CalculateLotSize(double slDistance, bool useMoneyManagement = true)
{
   if(!useMoneyManagement)
      return 0.01;

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickValue <= 0 || tickSize <= 0 || slDistance <= 0)
      return minLot;

   double ticksAtRisk = slDistance / tickSize;
   double rawLot = riskMoney / (ticksAtRisk * tickValue);

   if(lotStep > 0)
      rawLot = MathFloor(rawLot / lotStep) * lotStep;

   rawLot = MathMax(MathMin(rawLot, maxLot), minLot);
   return rawLot;
}

//+------------------------------------------------------------------+
//| Verify trade before sending                                      |
//+------------------------------------------------------------------+
bool VerifyTrade(int type, double price, double sl, double tp, double lot)
{
   double margin = 0;
   if(!OrderCalcMargin((ENUM_ORDER_TYPE)type, _Symbol, lot, price, margin))
   {
      Print("Margin calculation failed");
      return false;
   }

   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(margin >= freeMargin)
   {
      Print("NOT ENOUGH MARGIN: Required ", margin, ", Free ", freeMargin);
      return false;
   }

   double slDistPoints = 0;
   if(type == ORDER_TYPE_BUY)
      slDistPoints = (price - sl) / _Point;
   else
      slDistPoints = (sl - price) / _Point;

   double minSLDist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(slDistPoints < minSLDist)
   {
      Print("SL too close: ", slDistPoints, " pts, minimum: ", minSLDist, " pts");
      return false;
   }

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts)
   {
      Print("Spread too high for execution: ", spread);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Calculate trailing stop level                                    |
//+------------------------------------------------------------------+
double CalcTrailingStop(int type, double entryPrice, double currentPrice,
                        double currentSL, double atrValue)
{
   if(!UseTrailingStop || atrValue <= 0)
      return currentSL;

   double activateDist = TrailingActivateATR * atrValue;
   double trailStep    = TrailingStepATR * atrValue;

   if(type == POSITION_TYPE_BUY)
   {
      double profitDist = currentPrice - entryPrice;
      if(profitDist < activateDist)
         return currentSL;

      double newSL = currentPrice - trailStep;
      if(newSL > currentSL)
         return newSL;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      double profitDist = entryPrice - currentPrice;
      if(profitDist < activateDist)
         return currentSL;

      double newSL = currentPrice + trailStep;
      if(newSL < currentSL)
         return newSL;
   }

   return currentSL;
}

//+------------------------------------------------------------------+
//| Update trailing stops for all open positions                     |
//+------------------------------------------------------------------+
void UpdateTrailingStops()
{
   if(!UseTrailingStop)
      return;

   double atrVal = CalcATR(14, PERIOD_CURRENT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      int type    = (int)PositionGetInteger(POSITION_TYPE);
      double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentPrice = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                                                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double newSL = CalcTrailingStop(type, entry, currentPrice, currentSL, atrVal);

      if(newSL != currentSL)
      {
         MqlTradeRequest request = {};
         MqlTradeResult  result  = {};
         request.action    = TRADE_ACTION_SLTP;
         request.position  = ticket;
         request.symbol    = _Symbol;
         request.sl        = newSL;
         request.tp        = PositionGetDouble(POSITION_TP);

         if(OrderSend(request, result))
            Print("Trailing SL updated for pos #", ticket, " -> ", newSL);
         else
            Print("Trailing SL update failed for pos #", ticket, ": ", result.comment);
      }
   }
}

//+------------------------------------------------------------------+
//| Close all trades (emergency stop)                                |
//+------------------------------------------------------------------+
int CloseAllTrades()
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      int type = (int)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);

      request.action    = TRADE_ACTION_DEAL;
      request.position  = ticket;
      request.symbol    = _Symbol;
      request.volume    = volume;
      request.deviation = MaxSlippagePts;

      if(type == POSITION_TYPE_BUY)
      {
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         request.type  = ORDER_TYPE_SELL;
      }
      else
      {
         request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         request.type  = ORDER_TYPE_BUY;
      }

      if(OrderSend(request, result))
      {
         Print("Force closed position #", ticket, " at ", request.price);
         closed++;
      }
      else
         Print("Failed to close #", ticket, ": ", result.comment);
   }
   return closed;
}

//+------------------------------------------------------------------+
//| Track trade after it opens                                       |
//+------------------------------------------------------------------+
void TrackTradeOpened(int type, double volume)
{
   ResetDailyStats();
   g_dailyStats.tradeCount++;
   Print("Trade #", g_dailyStats.tradeCount, " opened. Type: ", (type == 0 ? "BUY" : "SELL"),
         " Volume: ", volume);
}

//+------------------------------------------------------------------+
//| Track P&L on each tick for daily loss limit                      |
//+------------------------------------------------------------------+
void TrackDailyPL()
{
   ResetDailyStats();

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyStats.totalPL = currentEquity - balance;

   if(g_dailyStats.startingBalance > 0)
   {
      double currentDrawdown = (g_dailyStats.startingBalance - currentEquity) / g_dailyStats.startingBalance * 100.0;
      if(currentDrawdown > g_dailyStats.maxDrawdown)
         g_dailyStats.maxDrawdown = currentDrawdown;

      if(currentDrawdown >= MaxDailyLossPct && !g_dailyStats.tradingStopped)
      {
         g_dailyStats.tradingStopped = true;
         Print("MAX DAILY LOSS REACHED: ", DoubleToString(currentDrawdown, 2), "%");
         CloseAllTrades();
      }
   }
}

//+------------------------------------------------------------------+
//| ATR calculation — manual from MqlRates                           |
//+------------------------------------------------------------------+
double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, period + 2, rates);
   if(copied < period + 1) return 0;

   double sum = 0;
   for(int i = 0; i < period; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low,
                          MathMax(MathAbs(rates[i].high - rates[i+1].close),
                                  MathAbs(rates[i].low - rates[i+1].close)));
      sum += tr;
   }
   return sum / period;
}
//+------------------------------------------------------------------+
