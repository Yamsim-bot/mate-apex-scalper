//+------------------------------------------------------------------+
//|                                              FXRE_OrderBlocks.mqh|
//|               FXRE Ultimate AI Replication — Order Block Detector |
//+------------------------------------------------------------------+
//| FXRE Order Block Detector — no #property (included from main EA)


//+------------------------------------------------------------------+
//| Order Block structure                                            |
//+------------------------------------------------------------------+
struct OrderBlock
{
   datetime   formationTime;
   double     zoneHigh;
   double     zoneLow;
   bool       isBullish;
   double     strength;
   int        ageCandles;
   int        touchedCount;
};

//+------------------------------------------------------------------+
//| Module state                                                     |
//+------------------------------------------------------------------+
OrderBlock g_obBullish[];
OrderBlock g_obBearish[];
int        g_obBullishTotal  = 0;
int        g_obBearishTotal  = 0;
datetime   g_obLastScanTime  = 0;

//+------------------------------------------------------------------+
//| Detect Order Blocks on the given timeframe                       |
//+------------------------------------------------------------------+
int DetectOrderBlocks(ENUM_TIMEFRAMES tf, double atrValue)
{
   ArrayFree(g_obBullish);
   ArrayFree(g_obBearish);
   g_obBullishTotal = 0;
   g_obBearishTotal = 0;

   if(g_obLastScanTime > 0 && TimeCurrent() - g_obLastScanTime < 60)
      return g_obBullishTotal + g_obBearishTotal;

   int barsAvailable = Bars(_Symbol, tf);
   int lookback = MathMin(OB_LookbackCandles, barsAvailable - 10);
   if(lookback < 20) return 0;

   // Load all candle data at once (MQL5 style)
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, lookback + 5, rates);
   if(copied < lookback) return 0;

   OrderBlock tempBullish[];
   OrderBlock tempBearish[];
   int bullCount = 0, bearCount = 0;

   for(int i = 3; i < lookback - 3; i++)
   {
      // --- Bullish OB: last bearish candle before upward move ---
      if(rates[i].close < rates[i].open)
      {
         double moveUp = 0;
         double avgBody = 0;
         int count = 0;
         for(int j = i - 1; j >= MathMax(i - 3, 1); j--)
         {
            moveUp += (rates[j].close - rates[j].open);
            avgBody += MathAbs(rates[j].close - rates[j].open);
            count++;
         }
         if(count > 0) avgBody /= count;

         double minMove = OB_MinMovePips * _Point * 10;
         if(avgBody > 1e-10) minMove = MathMax(minMove, avgBody * 1.5);

         if(moveUp >= minMove)
         {
            ArrayResize(tempBullish, bullCount + 1, 10);
            tempBullish[bullCount].formationTime = rates[i].time;
            tempBullish[bullCount].zoneHigh = rates[i].high;
            tempBullish[bullCount].zoneLow  = rates[i].low;
            tempBullish[bullCount].isBullish = true;
            tempBullish[bullCount].ageCandles = i;
            tempBullish[bullCount].touchedCount = 0;
            tempBullish[bullCount].strength = CalcOBStrength(_Symbol, tf, i, true, atrValue);
            bullCount++;
         }
      }

      // --- Bearish OB: last bullish candle before downward move ---
      if(rates[i].close > rates[i].open)
      {
         double moveDown = 0;
         double avgBody = 0;
         int count = 0;
         for(int j = i - 1; j >= MathMax(i - 3, 1); j--)
         {
            moveDown += (rates[j].open - rates[j].close);
            avgBody += MathAbs(rates[j].close - rates[j].open);
            count++;
         }
         if(count > 0) avgBody /= count;

         double minMove = OB_MinMovePips * _Point * 10;
         if(avgBody > 1e-10) minMove = MathMax(minMove, avgBody * 1.5);

         if(moveDown >= minMove)
         {
            ArrayResize(tempBearish, bearCount + 1, 10);
            tempBearish[bearCount].formationTime = rates[i].time;
            tempBearish[bearCount].zoneHigh = rates[i].high;
            tempBearish[bearCount].zoneLow  = rates[i].low;
            tempBearish[bearCount].isBullish = false;
            tempBearish[bearCount].ageCandles = i;
            tempBearish[bearCount].touchedCount = 0;
            tempBearish[bearCount].strength = CalcOBStrength(_Symbol, tf, i, false, atrValue);
            bearCount++;
         }
      }
   }

   // Filter by freshness (age)
   for(int i = 0; i < bullCount; i++)
   {
      if(tempBullish[i].ageCandles <= OB_MaxAgeCandles)
      {
         ArrayResize(g_obBullish, g_obBullishTotal + 1, 10);
         g_obBullish[g_obBullishTotal] = tempBullish[i];
         g_obBullishTotal++;
      }
   }
   for(int i = 0; i < bearCount; i++)
   {
      if(tempBearish[i].ageCandles <= OB_MaxAgeCandles)
      {
         ArrayResize(g_obBearish, g_obBearishTotal + 1, 10);
         g_obBearish[g_obBearishTotal] = tempBearish[i];
         g_obBearishTotal++;
      }
   }

   g_obLastScanTime = TimeCurrent();
   SortOBs(g_obBullish, g_obBullishTotal, true);
   SortOBs(g_obBearish, g_obBearishTotal, true);
   return g_obBullishTotal + g_obBearishTotal;
}

//+------------------------------------------------------------------+
//| Calculate Order Block strength                                   |
//+------------------------------------------------------------------+
double CalcOBStrength(string symbol, ENUM_TIMEFRAMES tf, int obIndex, bool isBullish, double atrValue)
{
   double strength = 0.5;

   int lookback = MathMin(OB_StrengthCandles, obIndex - 5);
   if(lookback < 3) return strength;

   // Load rates for analysis
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, obIndex - lookback, lookback + 2, rates) < 3)
      return strength;

   int obLocal = ArraySize(rates) - 2;
   if(obLocal < 2) return strength;

   double obHigh = rates[obLocal].high;
   double obLow  = rates[obLocal].low;

   int respects = 0, touches = 0;
   double zoneWidth = MathMax(obHigh - obLow, atrValue * 0.1);

   for(int i = obLocal - 1; i >= MathMax(obLocal - lookback, 0); i--)
   {
      if(isBullish)
      {
         if(rates[i].low <= obHigh + zoneWidth * 0.5 && rates[i].low >= obLow - zoneWidth * 0.5)
         {
            touches++;
            if(i > 0 && rates[i-1].close > rates[i-1].open && rates[i-1].close > rates[i].high)
               respects++;
         }
      }
      else
      {
         if(rates[i].high >= obLow - zoneWidth * 0.5 && rates[i].high <= obHigh + zoneWidth * 0.5)
         {
            touches++;
            if(i > 0 && rates[i-1].close < rates[i-1].open && rates[i-1].close < rates[i].low)
               respects++;
         }
      }
   }

   if(touches > 0)
   {
      strength = (double)respects / MathMax(touches, 1);
      strength = MathMin(MathMax(strength, 0.0), 1.0);
   }
   return strength;
}

//+------------------------------------------------------------------+
//| Check if price is near a valid Order Block                       |
//+------------------------------------------------------------------+
bool IsNearOrderBlock(double price, bool isBullish, double atrValue, int& obIndex)
{
   double threshold = atrValue * OB_ProximityATR;

   if(isBullish)
   {
      for(int i = 0; i < g_obBullishTotal; i++)
      {
         double dist = MathAbs(price - g_obBullish[i].zoneLow);
         if(dist <= threshold || (price >= g_obBullish[i].zoneLow && price <= g_obBullish[i].zoneHigh + threshold * 0.5))
         {
            obIndex = i;
            return true;
         }
      }
   }
   else
   {
      for(int i = 0; i < g_obBearishTotal; i++)
      {
         double dist = MathAbs(price - g_obBearish[i].zoneHigh);
         if(dist <= threshold || (price >= g_obBearish[i].zoneLow - threshold * 0.5 && price <= g_obBearish[i].zoneHigh))
         {
            obIndex = i;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get the nearest Order Block of given type                        |
//+------------------------------------------------------------------+
bool GetNearestOB(double price, bool isBullish, double atrValue, OrderBlock& ob)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double threshold = atrValue * OB_ProximityATR;

   if(isBullish)
   {
      for(int i = 0; i < g_obBullishTotal; i++)
      {
         double dist = MathAbs(price - g_obBullish[i].zoneLow);
         if(dist <= threshold && dist < nearestDist)
         { nearestDist = dist; nearestIdx = i; }
      }
      if(nearestIdx >= 0) { ob = g_obBullish[nearestIdx]; return true; }
   }
   else
   {
      for(int i = 0; i < g_obBearishTotal; i++)
      {
         double dist = MathAbs(price - g_obBearish[i].zoneHigh);
         if(dist <= threshold && dist < nearestDist)
         { nearestDist = dist; nearestIdx = i; }
      }
      if(nearestIdx >= 0) { ob = g_obBearish[nearestIdx]; return true; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sort Order Blocks by strength                                    |
//+------------------------------------------------------------------+
void SortOBs(OrderBlock& obs[], int count, bool descending)
{
   for(int i = 0; i < count - 1; i++)
      for(int j = i + 1; j < count; j++)
         if(descending ? (obs[j].strength > obs[i].strength) : (obs[j].strength < obs[i].strength))
         { OrderBlock tmp = obs[i]; obs[i] = obs[j]; obs[j] = tmp; }
}

//+------------------------------------------------------------------+
//| Get SL and TP levels from the nearest order block                |
//+------------------------------------------------------------------+
bool GetOBStopLevels(double entryPrice, bool isBuy, double atrValue,
                     double& stopLoss, double& takeProfit)
{
   OrderBlock ob;
   if(!GetNearestOB(entryPrice, isBuy, atrValue, ob))
      return false;

   double slDistance;
   if(isBuy)
      slDistance = MathAbs(entryPrice - ob.zoneLow) + 50 * _Point * 10;
   else
      slDistance = MathAbs(ob.zoneHigh - entryPrice) + 50 * _Point * 10;

   slDistance = MathMax(slDistance, 1.5 * atrValue);

   if(isBuy)
   { stopLoss = entryPrice - slDistance; takeProfit = entryPrice + slDistance * 3.0; }
   else
   { stopLoss = entryPrice + slDistance; takeProfit = entryPrice - slDistance * 3.0; }

   return true;
}

//+------------------------------------------------------------------+
//| Debug print                                                      |
//+------------------------------------------------------------------+
void PrintOrderBlocks()
{
   Print("=== Bullish OBs: ", g_obBullishTotal, " ===");
   for(int i = 0; i < MathMin(g_obBullishTotal, 5); i++)
      PrintFormat("OB[%d] Time=%s Zone=[%.5f-%.5f] Strength=%.2f Age=%d",
         i, TimeToString(g_obBullish[i].formationTime),
         g_obBullish[i].zoneLow, g_obBullish[i].zoneHigh,
         g_obBullish[i].strength, g_obBullish[i].ageCandles);

   Print("=== Bearish OBs: ", g_obBearishTotal, " ===");
   for(int i = 0; i < MathMin(g_obBearishTotal, 5); i++)
      PrintFormat("OB[%d] Time=%s Zone=[%.5f-%.5f] Strength=%.2f Age=%d",
         i, TimeToString(g_obBearish[i].formationTime),
         g_obBearish[i].zoneLow, g_obBearish[i].zoneHigh,
         g_obBearish[i].strength, g_obBearish[i].ageCandles);
}
//+------------------------------------------------------------------+
