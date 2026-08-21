//+------------------------------------------------------------------+
//|                                            FXRE_SwingSD.mqh       |
//|               FXRE Hybrid — Swing-point Supply & Demand Zones     |
//+------------------------------------------------------------------+
//| Detects swing highs (supply) and swing lows (demand) on M15,
//| clusters nearby swings into zones, assigns strength based on
//| follow-through distance.
//+------------------------------------------------------------------+

//--- Swing-point S&D structure
struct SwingSDZone
{
   datetime   formationTime;
   double     priceHigh;
   double     priceLow;
   double     priceMid;
   bool       isDemand;      // true=demand(buy), false=supply(sell)
   double     strength;      // 1.0 to 5.0 (higher = stronger)
   int        ageCandles;    // candles since last swing in cluster
   int        swingCount;    // number of swings clustered
   double     zoneWidth;     // priceHigh - priceLow
};

//--- Module state
SwingSDZone g_swingBullish[];   // Demand zones
SwingSDZone g_swingBearish[];   // Supply zones
int   g_swingBullishTotal = 0;
int   g_swingBearishTotal = 0;

//+------------------------------------------------------------------+
//| Detect swing points & build zones                                |
//| Returns total zone count                                         |
//+------------------------------------------------------------------+
int DetectSwingZones(ENUM_TIMEFRAMES tf, int lookbackBars, int swingLookback,
                     double clusterPoints, int maxAge, double minStrength)
{
   ArrayFree(g_swingBullish);
   ArrayFree(g_swingBearish);
   g_swingBullishTotal = 0;
   g_swingBearishTotal = 0;

   if(lookbackBars < 20) return 0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, lookbackBars + swingLookback * 2 + 5, rates);
   if(copied < lookbackBars) return 0;

   int look = swingLookback;
   double clusterThresh = clusterPoints;

   //--- Collect raw swing points
   struct RawSwing { double price; int idx; int strength; bool isDemand; };
   RawSwing rawSwings[];
   int rawCount = 0;
   ArrayResize(rawSwings, 5000);

   for(int i = look; i < lookbackBars - look; i++)
   {
      //--- Swing high (supply potential)
      bool isHigh = true;
      for(int k = 1; k <= look; k++)
      {
         if(rates[i].high < rates[i - k].high ||
            rates[i].high < rates[i + k].high ||
            rates[i].high <= rates[i - 1].high)
         { isHigh = false; break; }
      }
      if(isHigh)
      {
         int str = 1;
         for(int k = 1; k <= look; k++)
            if(rates[i].close > rates[i + k].close) str++;
         rawSwings[rawCount].price   = rates[i].high;
         rawSwings[rawCount].idx     = i;
         rawSwings[rawCount].strength = MathMin(str, 5);
         rawSwings[rawCount].isDemand = false;
         rawCount++;
      }

      //--- Swing low (demand potential)
      bool isLow = true;
      for(int k = 1; k <= look; k++)
      {
         if(rates[i].low > rates[i - k].low ||
            rates[i].low > rates[i + k].low ||
            rates[i].low >= rates[i - 1].low)
         { isLow = false; break; }
      }
      if(isLow)
      {
         int str = 1;
         for(int k = 1; k <= look; k++)
            if(rates[i].close < rates[i + k].close) str++;
         rawSwings[rawCount].price   = rates[i].low;
         rawSwings[rawCount].idx     = i;
         rawSwings[rawCount].strength = MathMin(str, 5);
         rawSwings[rawCount].isDemand = true;
         rawCount++;
      }
   }

   if(rawCount == 0) return 0;

   //--- Sort raw swings by price
   bool swapped = true;
   while(swapped)
   {
      swapped = false;
      for(int i = 0; i < rawCount - 1; i++)
      {
         if(rawSwings[i].price > rawSwings[i + 1].price)
         {
            RawSwing t = rawSwings[i]; rawSwings[i] = rawSwings[i + 1]; rawSwings[i + 1] = t;
            swapped = true;
         }
      }
   }

   //--- Cluster nearby swings into zones (separate demand/supply)
   // Process demand swings
   SwingSDZone tempDZ[], tempSZ[];
   int dzCount = 0, szCount = 0;
   ArrayResize(tempDZ, rawCount);
   ArrayResize(tempSZ, rawCount);

   // Cluster demand
   int start = 0;
   for(int i = 0; i < rawCount; i++)
   {
      if(!rawSwings[i].isDemand) continue;
      if(dzCount == 0 || rawSwings[i].price - tempDZ[dzCount - 1].priceHigh > clusterThresh)
      {
         // New cluster
         tempDZ[dzCount].formationTime = rates[rawSwings[i].idx].time;
         tempDZ[dzCount].priceHigh = rawSwings[i].price;
         tempDZ[dzCount].priceLow  = rawSwings[i].price;
         tempDZ[dzCount].priceMid  = rawSwings[i].price;
         tempDZ[dzCount].isDemand  = true;
         tempDZ[dzCount].strength  = (double)rawSwings[i].strength;
         tempDZ[dzCount].ageCandles = rawSwings[i].idx;
         tempDZ[dzCount].swingCount = 1;
         tempDZ[dzCount].zoneWidth  = 0;
         dzCount++;
      }
      else
      {
         // Add to existing cluster
         int ci = dzCount - 1;
         if(rawSwings[i].price > tempDZ[ci].priceHigh) tempDZ[ci].priceHigh = rawSwings[i].price;
         if(rawSwings[i].price < tempDZ[ci].priceLow)  tempDZ[ci].priceLow  = rawSwings[i].price;
         tempDZ[ci].priceMid = (tempDZ[ci].priceHigh + tempDZ[ci].priceLow) / 2.0;
         tempDZ[ci].strength = (tempDZ[ci].strength * tempDZ[ci].swingCount + rawSwings[i].strength)
                              / (tempDZ[ci].swingCount + 1);
         tempDZ[ci].swingCount++;
         if(rawSwings[i].idx > tempDZ[ci].ageCandles)
            tempDZ[ci].ageCandles = rawSwings[i].idx;
         tempDZ[ci].zoneWidth = tempDZ[ci].priceHigh - tempDZ[ci].priceLow;
      }
   }

   // Cluster supply
   for(int i = 0; i < rawCount; i++)
   {
      if(rawSwings[i].isDemand) continue;
      if(szCount == 0 || rawSwings[i].price - tempSZ[szCount - 1].priceHigh > clusterThresh)
      {
         tempSZ[szCount].formationTime = rates[rawSwings[i].idx].time;
         tempSZ[szCount].priceHigh = rawSwings[i].price;
         tempSZ[szCount].priceLow  = rawSwings[i].price;
         tempSZ[szCount].priceMid  = rawSwings[i].price;
         tempSZ[szCount].isDemand  = false;
         tempSZ[szCount].strength  = (double)rawSwings[i].strength;
         tempSZ[szCount].ageCandles = rawSwings[i].idx;
         tempSZ[szCount].swingCount = 1;
         tempSZ[szCount].zoneWidth  = 0;
         szCount++;
      }
      else
      {
         int ci = szCount - 1;
         if(rawSwings[i].price > tempSZ[ci].priceHigh) tempSZ[ci].priceHigh = rawSwings[i].price;
         if(rawSwings[i].price < tempSZ[ci].priceLow)  tempSZ[ci].priceLow  = rawSwings[i].price;
         tempSZ[ci].priceMid = (tempSZ[ci].priceHigh + tempSZ[ci].priceLow) / 2.0;
         tempSZ[ci].strength = (tempSZ[ci].strength * tempSZ[ci].swingCount + rawSwings[i].strength)
                              / (tempSZ[ci].swingCount + 1);
         tempSZ[ci].swingCount++;
         if(rawSwings[i].idx > tempSZ[ci].ageCandles)
            tempSZ[ci].ageCandles = rawSwings[i].idx;
         tempSZ[ci].zoneWidth = tempSZ[ci].priceHigh - tempSZ[ci].priceLow;
      }
   }

   //--- Filter by age, strength — copy to global arrays
   for(int i = 0; i < dzCount; i++)
   {
      if(tempDZ[i].ageCandles <= maxAge &&
         tempDZ[i].strength >= minStrength)
      {
         ArrayResize(g_swingBullish, g_swingBullishTotal + 1, 20);
         g_swingBullish[g_swingBullishTotal] = tempDZ[i];
         g_swingBullishTotal++;
      }
   }
   for(int i = 0; i < szCount; i++)
   {
      if(tempSZ[i].ageCandles <= maxAge &&
         tempSZ[i].strength >= minStrength)
      {
         ArrayResize(g_swingBearish, g_swingBearishTotal + 1, 20);
         g_swingBearish[g_swingBearishTotal] = tempSZ[i];
         g_swingBearishTotal++;
      }
   }

   // Sort by strength descending
   SortSwingZones(g_swingBullish, g_swingBullishTotal, true);
   SortSwingZones(g_swingBearish, g_swingBearishTotal, true);

   return g_swingBullishTotal + g_swingBearishTotal;
}

//+------------------------------------------------------------------+
//| Find nearest demand zone below/at price                          |
//+------------------------------------------------------------------+
bool GetNearestDemandZone(double price, double proximityATR, double atrValue,
                          SwingSDZone &zone)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double thresh = atrValue * proximityATR;

   for(int i = 0; i < g_swingBullishTotal; i++)
   {
      // Price should be AT or ABOVE demand zone
      if(price < g_swingBullish[i].priceLow - thresh) continue;

      double dist = price - g_swingBullish[i].priceMid;
      if(dist >= -thresh && dist < nearestDist)
      {
         nearestDist = dist;
         nearestIdx = i;
      }
   }

   if(nearestIdx >= 0)
   {
      zone = g_swingBullish[nearestIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Find nearest supply zone above/at price                          |
//+------------------------------------------------------------------+
bool GetNearestSupplyZone(double price, double proximityATR, double atrValue,
                          SwingSDZone &zone)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double thresh = atrValue * proximityATR;

   for(int i = 0; i < g_swingBearishTotal; i++)
   {
      // Price should be AT or BELOW supply zone
      if(price > g_swingBearish[i].priceHigh + thresh) continue;

      double dist = g_swingBearish[i].priceMid - price;
      if(dist >= -thresh && dist < nearestDist)
      {
         nearestDist = dist;
         nearestIdx = i;
      }
   }

   if(nearestIdx >= 0)
   {
      zone = g_swingBearish[nearestIdx];
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sort zones by strength descending (true) or ascending            |
//+------------------------------------------------------------------+
void SortSwingZones(SwingSDZone &zones[], int count, bool descending)
{
   for(int i = 0; i < count - 1; i++)
      for(int j = i + 1; j < count; j++)
         if(descending ? (zones[j].strength > zones[i].strength)
                       : (zones[j].strength < zones[i].strength))
         { SwingSDZone t = zones[i]; zones[i] = zones[j]; zones[j] = t; }
}

//+------------------------------------------------------------------+
//| Print active zones                                               |
//+------------------------------------------------------------------+
void PrintSwingZones()
{
   Print("=== Demand Zones (BUY): ", g_swingBullishTotal, " ===");
   for(int i = 0; i < MathMin(g_swingBullishTotal, 5); i++)
      PrintFormat("DZ[%d] Time=%s Zone=[%.2f-%.2f] Str=%.1f Age=%d Swings=%d Width=%.2f",
         i, TimeToString(g_swingBullish[i].formationTime),
         g_swingBullish[i].priceLow, g_swingBullish[i].priceHigh,
         g_swingBullish[i].strength, g_swingBullish[i].ageCandles,
         g_swingBullish[i].swingCount, g_swingBullish[i].zoneWidth);

   Print("=== Supply Zones (SELL): ", g_swingBearishTotal, " ===");
   for(int i = 0; i < MathMin(g_swingBearishTotal, 5); i++)
      PrintFormat("SZ[%d] Time=%s Zone=[%.2f-%.2f] Str=%.1f Age=%d Swings=%d Width=%.2f",
         i, TimeToString(g_swingBearish[i].formationTime),
         g_swingBearish[i].priceLow, g_swingBearish[i].priceHigh,
         g_swingBearish[i].strength, g_swingBearish[i].ageCandles,
         g_swingBearish[i].swingCount, g_swingBearish[i].zoneWidth);
}
//+------------------------------------------------------------------+
