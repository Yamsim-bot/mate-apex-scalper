//+------------------------------------------------------------------+
//|                                            FXRE_SupplyDemand.mqh |
//|               FXRE AGV AI Replication — Supply & Demand Zones     |
//+------------------------------------------------------------------+
//| FXRE AGV Supply & Demand detection engine
//| Detects consolidation zones followed by strong impulse moves.
//| Demand zone = consolidation before bullish breakout
//| Supply zone = consolidation before bearish breakout
//+------------------------------------------------------------------+

//--- Supply/Demand structure
struct SupplyDemandZone
{
   datetime   formationTime;
   double     zoneHigh;
   double     zoneLow;
   double     zoneMid;
   bool       isDemand;      // true=demand(buy), false=supply(sell)
   double     strength;      // 0.0 to 1.0
   int        ageCandles;    // candles since formation
   int        touchCount;    // times price touched zone
   double     impulseSize;   // size of the impulse candle
   int        zoneWidthPts;  // zone width in points
};

//--- Module state
SupplyDemandZone g_sdBullish[];   // Demand zones (buy)
SupplyDemandZone g_sdBearish[];   // Supply zones (sell)
int    g_sdBullishTotal  = 0;
int    g_sdBearishTotal  = 0;
datetime g_sdLastScanTime = 0;

//+------------------------------------------------------------------+
//| Detect consolidation (ranging) candles                           |
//| Returns number of consecutive ranging candles starting from idx  |
//+------------------------------------------------------------------+
int CountConsolidationCandles(const MqlRates &rates[], int startIdx,
                              double avgATR, double maxRangeATR)
{
   int count = 0;
   int maxCheck = 12;  // Max consolidation length to check

   for(int i = startIdx; i < startIdx + maxCheck && i < ArraySize(rates) - 3; i++)
   {
      double range = rates[i].high - rates[i].low;
      double body  = MathAbs(rates[i].close - rates[i].open);
      double upperWick = rates[i].high - MathMax(rates[i].close, rates[i].open);
      double lowerWick = MathMin(rates[i].close, rates[i].open) - rates[i].low;

      // Consolidation criteria:
      // 1. Total range < maxRangeATR * ATR
      // 2. Body is not too large (not an impulse)
      if(range > avgATR * maxRangeATR) break;
      if(body > avgATR * maxRangeATR * 0.8) break;

      count++;
   }

   return count;
}

//+------------------------------------------------------------------+
//| Detect Supply & Demand zones on the given timeframe              |
//+------------------------------------------------------------------+
int DetectSupplyDemandZones(ENUM_TIMEFRAMES tf, double atrValue)
{
   ArrayFree(g_sdBullish);
   ArrayFree(g_sdBearish);
   g_sdBullishTotal = 0;
   g_sdBearishTotal = 0;

   if(atrValue <= 0) return 0;

   int lookback = SD_LookbackCandles;
   if(lookback < 20) return 0;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, lookback + 5, rates);
   if(copied < lookback) return 0;

   double maxZoneRangeATR = 0.25;  // Max zone range as fraction of ATR
   double impulseMinATR   = 0.4;   // Min impulse move as fraction of ATR

   SupplyDemandZone tempDZ[];
   SupplyDemandZone tempSZ[];
   int dzCount = 0, szCount = 0;

   for(int i = 5; i < lookback - 3; i++)
   {
      // Check if we're at the start of a consolidation
      int consCount = CountConsolidationCandles(rates, i, atrValue, maxZoneRangeATR);
      if(consCount < SD_MinZoneCandles) continue;   // not enough ranging candles
      if(consCount > SD_MaxZoneCandles)
         consCount = SD_MaxZoneCandles;  // cap it

      // Calculate zone boundaries
      double zoneHigh = 0, zoneLow = DBL_MAX;
      double avgBody = 0;
      for(int j = 0; j < consCount; j++)
      {
         if(rates[i + j].high > zoneHigh) zoneHigh = rates[i + j].high;
         if(rates[i + j].low  < zoneLow)  zoneLow  = rates[i + j].low;
         avgBody += MathAbs(rates[i + j].close - rates[i + j].open);
      }
      avgBody /= consCount;

      double zoneWidth = zoneHigh - zoneLow;
      if(zoneWidth < atrValue * 0.05) continue;  // zone too tight

      // Look for impulse candle after consolidation
      int impulseIdx = i + consCount;
      if(impulseIdx >= lookback - 1) continue;

      double impulseBody = MathAbs(rates[impulseIdx].close - rates[impulseIdx].open);
      double impulseRange = rates[impulseIdx].high - rates[impulseIdx].low;
      bool isBullishImpulse = (rates[impulseIdx].close > rates[impulseIdx].open);

      // Check if impulse is strong enough
      if(impulseBody < avgBody * 1.5 && impulseRange < zoneWidth * 1.2) continue;

      // Check that impulse candle closes beyond zone boundary
      if(isBullishImpulse && rates[impulseIdx].close <= zoneHigh) continue;
      if(!isBullishImpulse && rates[impulseIdx].close >= zoneLow) continue;

      // This is a valid zone — classify as supply or demand
      if(isBullishImpulse)
      {
         // Demand zone: price broke UP from consolidation
         ArrayResize(tempDZ, dzCount + 1, 20);
         tempDZ[dzCount].formationTime = rates[i].time;
         tempDZ[dzCount].zoneHigh = zoneHigh;
         tempDZ[dzCount].zoneLow  = zoneLow;
         tempDZ[dzCount].zoneMid  = (zoneHigh + zoneLow) / 2.0;
         tempDZ[dzCount].isDemand = true;
         tempDZ[dzCount].ageCandles = i;
         tempDZ[dzCount].touchCount = 0;
         tempDZ[dzCount].impulseSize = impulseRange;
         tempDZ[dzCount].zoneWidthPts = (int)(zoneWidth / _Point);
         tempDZ[dzCount].strength = CalcSDStrength(rates, i, consCount, isBullishImpulse, atrValue);
         dzCount++;
      }
      else
      {
         // Supply zone: price broke DOWN from consolidation
         ArrayResize(tempSZ, szCount + 1, 20);
         tempSZ[szCount].formationTime = rates[i].time;
         tempSZ[szCount].zoneHigh = zoneHigh;
         tempSZ[szCount].zoneLow  = zoneLow;
         tempSZ[szCount].zoneMid  = (zoneHigh + zoneLow) / 2.0;
         tempSZ[szCount].isDemand = false;
         tempSZ[szCount].ageCandles = i;
         tempSZ[szCount].touchCount = 0;
         tempSZ[szCount].impulseSize = impulseRange;
         tempSZ[szCount].zoneWidthPts = (int)(zoneWidth / _Point);
         tempSZ[szCount].strength = CalcSDStrength(rates, i, consCount, isBullishImpulse, atrValue);
         szCount++;
      }

      // Skip ahead to avoid overlapping zones
      i += consCount + 1;
   }

   // Filter by freshness and copy to global arrays
   for(int i = 0; i < dzCount; i++)
   {
      if(tempDZ[i].ageCandles <= SD_MaxAgeCandles)
      {
         ArrayResize(g_sdBullish, g_sdBullishTotal + 1, 20);
         g_sdBullish[g_sdBullishTotal] = tempDZ[i];
         g_sdBullishTotal++;
      }
   }
   for(int i = 0; i < szCount; i++)
   {
      if(tempSZ[i].ageCandles <= SD_MaxAgeCandles)
      {
         ArrayResize(g_sdBearish, g_sdBearishTotal + 1, 20);
         g_sdBearish[g_sdBearishTotal] = tempSZ[i];
         g_sdBearishTotal++;
      }
   }

   g_sdLastScanTime = TimeCurrent();
   SortSDZones(g_sdBullish, g_sdBullishTotal, true);
   SortSDZones(g_sdBearish, g_sdBearishTotal, true);
   return g_sdBullishTotal + g_sdBearishTotal;
}

//+------------------------------------------------------------------+
//| Calculate Supply/Demand zone strength                            |
//+------------------------------------------------------------------+
double CalcSDStrength(const MqlRates &rates[], int zoneStart, int consCount,
                      bool isBullish, double atrValue)
{
   double strength = 0.5;

   // Factors that increase strength:
   // 1. Tight consolidation (small range relative to ATR) = stronger
   // 2. Large impulse move = stronger
   // 3. Many touches without breaking = stronger

   double zoneRange = 0;
   double zoneHigh = 0, zoneLow = DBL_MAX;
   for(int j = 0; j < consCount; j++)
   {
      if(rates[zoneStart + j].high > zoneHigh) zoneHigh = rates[zoneStart + j].high;
      if(rates[zoneStart + j].low  < zoneLow)  zoneLow  = rates[zoneStart + j].low;
   }
   zoneRange = zoneHigh - zoneLow;

   // Tight range = stronger zone
   double rangeRatio = (atrValue > 0) ? zoneRange / atrValue : 0.3;
   if(rangeRatio < 0.15) strength += 0.3;
   else if(rangeRatio < 0.25) strength += 0.15;

   // Count touches (price returning to zone without breaking it)
   int impulseIdx = zoneStart + consCount;
   int touches = 0;
   for(int j = impulseIdx + 1; j < MathMin(impulseIdx + SD_StrengthCandles, ArraySize(rates) - 1); j++)
   {
      if(isBullish)
      {
         // Demand zone: price dips into zone
         if(rates[j].low <= zoneHigh && rates[j].close > zoneHigh - atrValue * 0.1)
            touches++;
      }
      else
      {
         // Supply zone: price rallies into zone
         if(rates[j].high >= zoneLow && rates[j].close < zoneLow + atrValue * 0.1)
            touches++;
      }
   }
   if(touches >= 3) strength += 0.2;
   else if(touches >= 1) strength += 0.1;

   // Impulse size factor
   double impulseBody = MathAbs(rates[impulseIdx].close - rates[impulseIdx].open);
   if(impulseBody > atrValue * 0.8) strength += 0.15;

   return MathMin(MathMax(strength, 0.0), 1.0);
}

//+------------------------------------------------------------------+
//| Check if price is near a valid Supply/Demand zone                |
//+------------------------------------------------------------------+
bool IsNearSDZone(double price, bool lookForDemand, double atrValue, int &zoneIndex)
{
   double threshold = atrValue * SD_ZoneProximityATR;

   if(lookForDemand)
   {
      // Look for demand zones below current price
      for(int i = 0; i < g_sdBullishTotal; i++)
      {
         // Price should be ABOVE the zone, approaching from above
         if(price >= g_sdBullish[i].zoneLow && price <= g_sdBullish[i].zoneHigh + threshold)
         {
            zoneIndex = i;
            return true;
         }
         // Price slightly above zone
         double dist = price - g_sdBullish[i].zoneHigh;
         if(dist >= 0 && dist <= threshold)
         {
            zoneIndex = i;
            return true;
         }
      }
   }
   else
   {
      // Look for supply zones above current price
      for(int i = 0; i < g_sdBearishTotal; i++)
      {
         // Price should be BELOW the zone, approaching from below
         if(price <= g_sdBearish[i].zoneHigh && price >= g_sdBearish[i].zoneLow - threshold)
         {
            zoneIndex = i;
            return true;
         }
         // Price slightly below zone
         double dist = g_sdBearish[i].zoneLow - price;
         if(dist >= 0 && dist <= threshold)
         {
            zoneIndex = i;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Get nearest Supply/Demand zone                                   |
//+------------------------------------------------------------------+
bool GetNearestSDZone(double price, bool lookForDemand, double atrValue,
                      SupplyDemandZone &zone)
{
   double nearestDist = DBL_MAX;
   int nearestIdx = -1;
   double threshold = atrValue * SD_ZoneProximityATR * 2.0;

   if(lookForDemand)
   {
      for(int i = 0; i < g_sdBullishTotal; i++)
      {
         double dist = price - g_sdBullish[i].zoneHigh;
         if(dist >= 0 && dist <= threshold && dist < nearestDist)
         {
            nearestDist = dist;
            nearestIdx = i;
         }
      }
      if(nearestIdx >= 0) { zone = g_sdBullish[nearestIdx]; return true; }
   }
   else
   {
      for(int i = 0; i < g_sdBearishTotal; i++)
      {
         double dist = g_sdBearish[i].zoneLow - price;
         if(dist >= 0 && dist <= threshold && dist < nearestDist)
         {
            nearestDist = dist;
            nearestIdx = i;
         }
      }
      if(nearestIdx >= 0) { zone = g_sdBearish[nearestIdx]; return true; }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Sort zones by strength                                           |
//+------------------------------------------------------------------+
void SortSDZones(SupplyDemandZone &zones[], int count, bool descending)
{
   for(int i = 0; i < count - 1; i++)
      for(int j = i + 1; j < count; j++)
         if(descending ? (zones[j].strength > zones[i].strength)
                       : (zones[j].strength < zones[i].strength))
         { SupplyDemandZone tmp = zones[i]; zones[i] = zones[j]; zones[j] = tmp; }
}

//+------------------------------------------------------------------+
//| Debug print zones                                                |
//+------------------------------------------------------------------+
void PrintSDZones()
{
   Print("=== Demand Zones (BUY): ", g_sdBullishTotal, " ===");
   for(int i = 0; i < MathMin(g_sdBullishTotal, 5); i++)
      PrintFormat("DZ[%d] Time=%s Zone=[%.5f-%.5f] Str=%.2f Age=%d Touch=%d",
         i, TimeToString(g_sdBullish[i].formationTime),
         g_sdBullish[i].zoneLow, g_sdBullish[i].zoneHigh,
         g_sdBullish[i].strength, g_sdBullish[i].ageCandles,
         g_sdBullish[i].touchCount);

   Print("=== Supply Zones (SELL): ", g_sdBearishTotal, " ===");
   for(int i = 0; i < MathMin(g_sdBearishTotal, 5); i++)
      PrintFormat("SZ[%d] Time=%s Zone=[%.5f-%.5f] Str=%.2f Age=%d Touch=%d",
         i, TimeToString(g_sdBearish[i].formationTime),
         g_sdBearish[i].zoneLow, g_sdBearish[i].zoneHigh,
         g_sdBearish[i].strength, g_sdBearish[i].ageCandles,
         g_sdBearish[i].touchCount);
}
//+------------------------------------------------------------------+
