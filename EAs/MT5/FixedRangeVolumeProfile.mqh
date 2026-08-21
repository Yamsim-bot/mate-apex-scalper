//+------------------------------------------------------------------+
//|                                  FixedRangeVolumeProfile.mqh      |
//|                          Fixed Range Volume Profile Engine        |
//|                          Computes POC / VAH / VAL / LVN zones     |
//|                          from bar-level volume distribution        |
//+------------------------------------------------------------------+
#ifndef FIXED_RANGE_VOLUME_PROFILE_MQH
#define FIXED_RANGE_VOLUME_PROFILE_MQH

//--- Maximum number of volume profile zones
#define FRVP_MAX_ZONES 50

//+------------------------------------------------------------------+
//| Volume node (single price bucket)                                |
//+------------------------------------------------------------------+
struct FRVPNode
{
   double      priceLow;       // bucket lower boundary
   double      priceHigh;      // bucket upper boundary
   double      priceMid;       // bucket mid price
   long        volume;         // cumulative volume in this bucket
   bool        isPOC;          // point of control (highest volume)
   bool        isVAH;          // value area high boundary
   bool        isVAL;          // value area low boundary
   bool        isLVN;          // low volume node (thin area)
};

//+------------------------------------------------------------------+
//| FRVP zone (grouped levels for trading)                           |
//+------------------------------------------------------------------+
enum FRVPZoneType
{
   FRVP_POC,       // Point of Control — max volume
   FRVP_VAH,       // Value Area High — 70% volume upper
   FRVP_VAL,       // Value Area Low — 70% volume lower
   FRVP_HVN,       // High Volume Node — thick liquidity
   FRVP_LVN        // Low Volume Node — thin / rejection zone
};

struct FRVPZone
{
   FRVPZoneType  type;
   double        price;          // zone center price
   double        upper;          // zone upper boundary
   double        lower;          // zone lower boundary
   long          volume;         // volume at this zone
   double        strength;       // 0..1 relative strength vs POC
};

//+------------------------------------------------------------------+
//| FRVP computation result                                          |
//+------------------------------------------------------------------+
struct FRVPResult
{
   double        poc;            // point of control price
   double        vah;            // value area high
   double        val;            // value area low
   double        rangeHigh;      // profile range high
   double        rangeLow;       // profile range low
   long          totalVolume;    // total volume in range
   FRVPZone      zones[];        // tradeable zones
   int           zoneCount;      // number of zones
   bool          valid;          // computation succeeded
};

//+------------------------------------------------------------------+
//| Volume Profile State (persistent per EA instance)                |
//+------------------------------------------------------------------+
struct FRVPState
{
   FRVPResult    current;        // latest computed profile
   datetime      lastCompute;    // when profile was last updated
   int           computeBar;     // which bar index was the anchor
};

//+------------------------------------------------------------------+
//| FRVP: Compute volume profile from bar data                       |
//|                                                                  |
//| anchors  = number of recent bars to profile (the "fixed range") |
//| bucketPips = price range per bucket (in price units, e.g. 0.50  |
//|              for gold = 50 cents, or 0.00050 for EURUSD = 5 pips)|
//| valueAreaPct = volume % to include in value area (default 70)   |
//| hvnThreshold = % of POC volume to qualify as HVN (default 0.7) |
//| lvnThreshold = % of POC volume below which is LVN (default 0.2) |
//+------------------------------------------------------------------+
bool FRVP_Compute(FRVPState &state, string symbol, ENUM_TIMEFRAMES tf,
                  int anchors, double bucketPips, double valueAreaPct = 70.0,
                  double hvnThreshold = 0.7, double lvnThreshold = 0.2)
{
   //--- Fetch OHLCV data
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, anchors + 1, rates) < anchors + 1)
      return false;

   //--- Find range high/low over the anchor period
   double rangeHigh = -DBL_MAX;
   double rangeLow  =  DBL_MAX;
   long   totalVol  = 0;

   for(int i = 0; i < anchors; i++)
   {
      if(rates[i].high > rangeHigh) rangeHigh = rates[i].high;
      if(rates[i].low  < rangeLow)  rangeLow  = rates[i].low;
      totalVol += rates[i].tick_volume;
   }

   if(rangeHigh <= rangeLow || totalVol <= 0) return false;

   //--- Determine number of buckets
   double rangeSize = rangeHigh - rangeLow;
   int numBuckets = (int)MathCeil(rangeSize / bucketPips);
   if(numBuckets < 3)  numBuckets = 3;
   if(numBuckets > 100) numBuckets = 100;

   double bucketSize = rangeSize / numBuckets;

   //--- Build volume distribution
   long bucketVol[];
   ArrayResize(bucketVol, numBuckets);
   ArrayInitialize(bucketVol, 0);

   for(int i = 0; i < anchors; i++)
   {
      double barLow  = rates[i].low;
      double barHigh = rates[i].high;
      long   barVol  = rates[i].tick_volume;

      //--- Distribute volume across buckets this bar touches
      int loIdx = (int)((barLow - rangeLow) / bucketSize);
      int hiIdx = (int)((barHigh - rangeLow) / bucketSize);
      if(loIdx < 0) loIdx = 0;
      if(hiIdx >= numBuckets) hiIdx = numBuckets - 1;

      int touched = hiIdx - loIdx + 1;
      if(touched <= 0) touched = 1;
      long volPerBucket = barVol / touched;
      if(volPerBucket <= 0) volPerBucket = barVol; // at least 1 tick

      for(int b = loIdx; b <= hiIdx; b++)
         bucketVol[b] += volPerBucket;
   }

   //--- Find POC (highest volume bucket)
   int pocIdx = 0;
   long maxVol = 0;
   for(int b = 0; b < numBuckets; b++)
   {
      if(bucketVol[b] > maxVol)
      {
         maxVol = bucketVol[b];
         pocIdx = b;
      }
   }

   double pocPrice = rangeLow + (pocIdx + 0.5) * bucketSize;

   //--- Compute Value Area (expand outward from POC until ~70% of total volume)
   long   vaVolTarget = (long)(totalVol * valueAreaPct / 100.0);
   long   vaVolAccum  = bucketVol[pocIdx];
   int    vaLoIdx     = pocIdx;
   int    vaHiIdx     = pocIdx;

   while(vaVolAccum < vaVolTarget)
   {
      //--- Expand to the side with more volume
      long volBelow = (vaLoIdx > 0) ? bucketVol[vaLoIdx - 1] : 0;
      long volAbove = (vaHiIdx < numBuckets - 1) ? bucketVol[vaHiIdx + 1] : 0;

      if(volBelow == 0 && volAbove == 0) break;

      if(volBelow >= volAbove && vaLoIdx > 0)
      {
         vaLoIdx--;
         vaVolAccum += bucketVol[vaLoIdx];
      }
      else if(vaHiIdx < numBuckets - 1)
      {
         vaHiIdx++;
         vaVolAccum += bucketVol[vaHiIdx];
      }
      else if(vaLoIdx > 0)
      {
         vaLoIdx--;
         vaVolAccum += bucketVol[vaLoIdx];
      }
      else break;
   }

   double vahPrice = rangeLow + (vaHiIdx + 1) * bucketSize;
   double valPrice = rangeLow + vaLoIdx * bucketSize;

   //--- Fill result
   state.current.poc         = pocPrice;
   state.current.vah         = vahPrice;
   state.current.val         = valPrice;
   state.current.rangeHigh   = rangeHigh;
   state.current.rangeLow    = rangeLow;
   state.current.totalVolume = totalVol;
   state.current.valid       = true;
   state.current.zoneCount   = 0;

   //--- Build zones: POC, VAH, VAL, then scan for HVN and LVN
   ArrayResize(state.current.zones, FRVP_MAX_ZONES);

   // POC zone
   state.current.zones[0].type     = FRVP_POC;
   state.current.zones[0].price    = pocPrice;
   state.current.zones[0].upper    = pocPrice + bucketSize * 0.5;
   state.current.zones[0].lower    = pocPrice - bucketSize * 0.5;
   state.current.zones[0].volume   = maxVol;
   state.current.zones[0].strength = 1.0;

   // VAH zone
   state.current.zones[1].type     = FRVP_VAH;
   state.current.zones[1].price    = vahPrice;
   state.current.zones[1].upper    = vahPrice + bucketSize * 0.5;
   state.current.zones[1].lower    = vahPrice - bucketSize * 0.5;
   state.current.zones[1].volume   = (vaHiIdx >= 0 && vaHiIdx < numBuckets) ? bucketVol[vaHiIdx] : 0;
   state.current.zones[1].strength = (maxVol > 0) ? (double)state.current.zones[1].volume / maxVol : 0;

   // VAL zone
   state.current.zones[2].type     = FRVP_VAL;
   state.current.zones[2].price    = valPrice;
   state.current.zones[2].upper    = valPrice + bucketSize * 0.5;
   state.current.zones[2].lower    = valPrice - bucketSize * 0.5;
   state.current.zones[2].volume   = (vaLoIdx >= 0 && vaLoIdx < numBuckets) ? bucketVol[vaLoIdx] : 0;
   state.current.zones[2].strength = (maxVol > 0) ? (double)state.current.zones[2].volume / maxVol : 0;

   int zoneIdx = 3;

   //--- Scan for HVN and LVN nodes (excluding POC region)
   for(int b = 0; b < numBuckets && zoneIdx < FRVP_MAX_ZONES; b++)
   {
      // Skip POC bucket and VA interior
      if(b == pocIdx) continue;
      if(b >= vaLoIdx && b <= vaHiIdx) continue;

      double strength = (maxVol > 0) ? (double)bucketVol[b] / maxVol : 0;

      if(strength >= hvnThreshold)
      {
         // High Volume Node — strong support/resistance
         state.current.zones[zoneIdx].type     = FRVP_HVN;
         state.current.zones[zoneIdx].price    = rangeLow + (b + 0.5) * bucketSize;
         state.current.zones[zoneIdx].upper    = rangeLow + (b + 1) * bucketSize;
         state.current.zones[zoneIdx].lower    = rangeLow + b * bucketSize;
         state.current.zones[zoneIdx].volume   = bucketVol[b];
         state.current.zones[zoneIdx].strength = strength;
         zoneIdx++;
      }
      else if(strength <= lvnThreshold && bucketVol[b] > 0)
      {
         // Low Volume Node — price tends to reject / move through quickly
         state.current.zones[zoneIdx].type     = FRVP_LVN;
         state.current.zones[zoneIdx].price    = rangeLow + (b + 0.5) * bucketSize;
         state.current.zones[zoneIdx].upper    = rangeLow + (b + 1) * bucketSize;
         state.current.zones[zoneIdx].lower    = rangeLow + b * bucketSize;
         state.current.zones[zoneIdx].volume   = bucketVol[b];
         state.current.zones[zoneIdx].strength = strength;
         zoneIdx++;
      }
   }

   state.current.zoneCount = zoneIdx;
   state.lastCompute = rates[0].time;
   state.computeBar  = anchors;

   return true;
}

//+------------------------------------------------------------------+
//| FRVP: Check if price is at a specific zone type                  |
//| Returns the zone index if within tolerance, -1 otherwise         |
//+------------------------------------------------------------------+
int FRVP_AtZone(FRVPResult &profile, double price, FRVPZoneType type, double tolerance)
{
   for(int i = 0; i < profile.zoneCount; i++)
   {
      if(profile.zones[i].type != type) continue;
      if(MathAbs(price - profile.zones[i].price) <= tolerance)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| FRVP: Check if price is above/below value area                  |
//| Returns +1 if above VAH, -1 if below VAL, 0 if inside VA       |
//+------------------------------------------------------------------+
int FRVP_RelativeToVA(FRVPResult &profile, double price)
{
   if(!profile.valid) return 0;
   if(price > profile.vah) return +1;
   if(price < profile.val) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| FRVP: Distance from POC as fraction of profile range            |
//+------------------------------------------------------------------+
double FRVP_POCDistance(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.rangeHigh <= profile.rangeLow) return 0;
   return (price - profile.poc) / (profile.rangeHigh - profile.rangeLow);
}

//+------------------------------------------------------------------+
//| FRVP: Find nearest zone to price (any type)                     |
//| Returns distance in price units                                  |
//+------------------------------------------------------------------+
double FRVP_NearestZoneDistance(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.zoneCount == 0) return DBL_MAX;
   double minDist = DBL_MAX;
   for(int i = 0; i < profile.zoneCount; i++)
   {
      double dist = MathAbs(price - profile.zones[i].price);
      if(dist < minDist) minDist = dist;
   }
   return minDist;
}

//+------------------------------------------------------------------+
//| FRVP: Get nearest zone (any type) — returns zone index or -1    |
//+------------------------------------------------------------------+
int FRVP_NearestZone(FRVPResult &profile, double price)
{
   if(!profile.valid || profile.zoneCount == 0) return -1;
   double minDist = DBL_MAX;
   int    nearest = -1;
   for(int i = 0; i < profile.zoneCount; i++)
   {
      double dist = MathAbs(price - profile.zones[i].price);
      if(dist < minDist)
      {
         minDist = dist;
         nearest = i;
      }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at POC?                                           |
//+------------------------------------------------------------------+
bool FRVP_AtPOC(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_POC, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at VAH (resistance)?                              |
//+------------------------------------------------------------------+
bool FRVP_AtVAH(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_VAH, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is price at VAL (support)?                                 |
//+------------------------------------------------------------------+
bool FRVP_AtVAL(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_VAL, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| FRVP: Is there an HVN nearby?                                    |
//+------------------------------------------------------------------+
int FRVP_NearHVN(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_HVN, tolerance);
}

//+------------------------------------------------------------------+
//| FRVP: Is there an LVN nearby?                                    |
//+------------------------------------------------------------------+
int FRVP_NearLVN(FRVPResult &profile, double price, double tolerance)
{
   return FRVP_AtZone(profile, price, FRVP_LVN, tolerance);
}

//+------------------------------------------------------------------+
//| FRVP: Get zone name string for logging                           |
//+------------------------------------------------------------------+
string FRVP_ZoneName(FRVPZoneType type)
{
   switch(type)
   {
      case FRVP_POC: return "POC";
      case FRVP_VAH: return "VAH";
      case FRVP_VAL: return "VAL";
      case FRVP_HVN: return "HVN";
      case FRVP_LVN: return "LVN";
   }
   return "???";
}

//+------------------------------------------------------------------+
//| FRVP: Print profile summary for debugging                        |
//+------------------------------------------------------------------+
void FRVP_PrintProfile(FRVPResult &profile, string symbol)
{
   if(!profile.valid)
   {
      Print(symbol, " FRVP: no valid profile");
      return;
   }
   Print(symbol, " FRVP | POC=", DoubleToString(profile.poc, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " VAH=", DoubleToString(profile.vah, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " VAL=", DoubleToString(profile.val, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " Range=[", DoubleToString(profile.rangeLow, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " .. ", DoubleToString(profile.rangeHigh, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         "] Vol=", profile.totalVolume,
         " Zones=", profile.zoneCount);
}

#endif // FIXED_RANGE_VOLUME_PROFILE_MQH
