//+------------------------------------------------------------------+

//|                                                 FXPair_EA.mq5     |

//|  FXPair EA v2.0 — Forex Confluence Day Trader (Multi-Symbol)      |

//|  Optimized for EURUSD, USDJPY, USDCAD, AUDUSD on M5/M15          |

//|                                                                    |

//|  Strategy: V2.0 Relaxed confluence with multi-symbol support       |

//|  - M15 EMA20/50/200 alignment                                     |

//|  - M15 swing structure (HH/HL/LH/LL)                              |

//|  - Break & retest at S/R levels                                   |

//|  - Rejection candles at BB bands                                  |

//|  - RSI extremes (relaxed for forex)                               |

//|  - ATR-based TP (1.5x ATR) for achievable targets                 |

//|  - Partial TP at 75% with trailing                                |

//|                                                                    |

//|  V2.0 Changes:                                                     |

//|  - ConfluenceMinScore: 5 → 3 (was impossible to reach)            |

//|  - RSI relaxed: BUY≤40 / SELL≥60 (was 35/65)                     |

//|  - Engulfing+Reversal now distinct patterns (was duplicate)       |

//|  - Auto-detect broker fill mode (was hardcoded FOK)               |

//|  - Multi-symbol: monitors 4 pairs from one chart                  |

//+------------------------------------------------------------------+

#property copyright "FXPair EA v2.0"

#property version   "2.00"

#property description "Forex Confluence Day Trader — Multi-Symbol, Relaxed Filters"



//--- INLINE: FixedRangeVolumeProfile.mqh ---
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

//--- END INLINE: FixedRangeVolumeProfile.mqh ---

//--- INLINE: PriceActionPatterns.mqh ---
//+------------------------------------------------------------------+
//|                                        PriceActionPatterns.mqh    |
//|                          Enhanced Price Action Pattern Detection  |
//|                          Pin bar, Engulfing, Engulf, Inside Bar,  |
//|                          Pin+Engulf combo, OB flip, BOS/CHoCH    |
//+------------------------------------------------------------------+
#ifndef PRICE_ACTION_PATTERNS_MQH
#define PRICE_ACTION_PATTERNS_MQH

//+------------------------------------------------------------------+
//| Price action signal result                                       |
//+------------------------------------------------------------------+
struct PASignal
{
   int    direction;    // +1 = bullish, -1 = bearish, 0 = none
   int    strength;     // 0..4 quality score
   string patternName;  // human-readable
};

//+------------------------------------------------------------------+
//| Pin Bar Detection                                                |
//| Long wick = rejection. Bullish pin = long lower wick.            |
//| Bearish pin = long upper wick.                                   |
//+------------------------------------------------------------------+
PASignal PA_DetectPinBar(MqlRates &r1, MqlRates &r2, double atr,
                         double minWickATR = 0.5, double wickBodyRatio = 2.0)
{
   PASignal sig = {0, 0, ""};

   double body1   = MathAbs(r1.close - r1.open);
   double range1  = r1.high - r1.low;
   double lowerW  = MathMin(r1.close, r1.open) - r1.low;
   double upperW  = r1.high - MathMax(r1.close, r1.open);
   double body2   = MathAbs(r2.close - r2.open); // context bar

   if(atr <= 0 || range1 <= 0) return sig;

   //--- Bullish pin bar: long lower wick, small upper wick, close in upper third
   if(lowerW >= atr * minWickATR && lowerW >= body1 * wickBodyRatio
      && upperW < body1 * 0.5 && body1 > 0)
   {
      sig.direction = +1;
      sig.strength  = 3;
      sig.patternName = "PinBar_BULL";

      //--- Boost: pin at prior bar's low or lower (extra rejection)
      if(r1.low <= r2.low) { sig.strength = 4; sig.patternName = "PinBar_BULL+Low"; }
   }

   //--- Bearish pin bar: long upper wick, close in lower third
   if(upperW >= atr * minWickATR && upperW >= body1 * wickBodyRatio
      && lowerW < body1 * 0.5 && body1 > 0)
   {
      sig.direction = -1;
      sig.strength  = 3;
      sig.patternName = "PinBar_BEAR";

      if(r1.high >= r2.high) { sig.strength = 4; sig.patternName = "PinBar_BEAR+High"; }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Engulfing Pattern Detection                                      |
//| Bullish: prev bearish bar fully engulfed by current bullish bar. |
//| Bearish: prev bullish bar fully engulfed by current bearish bar. |
//+------------------------------------------------------------------+
PASignal PA_DetectEngulfing(MqlRates &r1, MqlRates &r2, double atr,
                            double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};

   double body1 = MathAbs(r1.close - r1.open);
   double body2 = MathAbs(r2.close - r2.open);
   bool   r1Bull = r1.close > r1.open;
   bool   r1Bear = r1.close < r1.open;
   bool   r2Bull = r2.close > r2.open;
   bool   r2Bear = r2.close < r2.open;

   if(atr <= 0) return sig;

   //--- Bullish engulfing: r2 bearish, r1 bullish, r1 body wraps r2 body
   if(r2Bear && r1Bull && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
   {
      if(r1.close > r2.open && r1.open < r2.close)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "Engulf_BULL";

         //--- Boost: r1 also closes above r2 high (stronger conviction)
         if(r1.close > r2.high) { sig.strength = 4; sig.patternName = "Engulf_BULL+CloseAbove"; }
      }
   }

   //--- Bearish engulfing: r2 bullish, r1 bearish, r1 body wraps r2 body
   if(r2Bull && r1Bear && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
   {
      if(r1.close < r2.open && r1.open > r2.close)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "Engulf_BEAR";

         if(r1.close < r2.low) { sig.strength = 4; sig.patternName = "Engulf_BEAR+CloseBelow"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Inside Bar Detection                                             |
//| Current bar range fully inside previous bar range. Often a       |
//| consolidation before breakout.                                   |
//+------------------------------------------------------------------+
PASignal PA_DetectInsideBar(MqlRates &r1, MqlRates &r2, double atr)
{
   PASignal sig = {0, 0, ""};
   if(atr <= 0) return sig;

   //--- Inside bar: r1 high <= r2 high AND r1 low >= r2 low
   if(r1.high <= r2.high && r1.low >= r2.low)
   {
      //--- Direction determined by breakout context
      //--- Bullish inside bar: preceding trend was down, expecting reversal up
      if(r2.close < r2.open) // prev bar was bearish → potential bullish breakout
      {
         sig.direction = +1;
         sig.strength  = 2;
         sig.patternName = "InsideBar_BULL";
      }
      else
      {
         sig.direction = -1;
         sig.strength  = 2;
         sig.patternName = "InsideBar_BEAR";
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Pin + Engulf Combo                                               |
//| Pin bar followed by engulfing in same direction = strongest PA   |
//+------------------------------------------------------------------+
PASignal PA_DetectPinEngulfCombo(MqlRates &rates[], int count, double atr,
                                  double minWickATR = 0.5, double wickBodyRatio = 2.0,
                                  double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};
   if(count < 3 || atr <= 0) return sig;

   //--- rates[0]=newest (forming), [1]=last closed, [2]=older
   //--- Check: bar[2] = pin bar, bar[1] = engulfing confirmation
   PASignal pin = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
   PASignal eng = PA_DetectEngulfing(rates[1], rates[2], atr, minBodyATR);

   //--- Wait: pin is on [1] (older), engulf on [0] (newer)
   //--- Actually: r1=bar1 (last closed), r2=bar2 (one before)
   //--- So pin on bar2 + engulf from bar1→bar2
   //--- Better: check pin on bar[1] using bar[2] as context, then engulf on bar[0] using bar[1]
   PASignal pin1 = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
   PASignal eng0 = PA_DetectEngulfing(rates[0], rates[1], atr, minBodyATR);

   if(pin1.direction == +1 && eng0.direction == +1)
   {
      sig.direction = +1;
      sig.strength  = 4; // max strength
      sig.patternName = "PinEngulf_BULL";
   }
   else if(pin1.direction == -1 && eng0.direction == -1)
   {
      sig.direction = -1;
      sig.strength  = 4;
      sig.patternName = "PinEngulf_BEAR";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Three-Bar Reversal (Morning Star / Evening Star)                |
//| Bar1: large candle in trend direction                            |
//| Bar2: small body (indecision)                                   |
//| Bar3: large candle in reversal direction                         |
//+------------------------------------------------------------------+
PASignal PA_DetectThreeBarReversal(MqlRates &rates[], int count, double atr,
                                    double minBodyATR = 0.15)
{
   PASignal sig = {0, 0, ""};
   if(count < 3 || atr <= 0) return sig;

   //--- [2]=oldest, [1]=middle, [0]=newest (but we use last 3 closed: rates[1],rates[2],rates[3])
   //--- We'll use rates[1]=newest closed, [2]=middle, [3]=oldest
   //--- Actually: let's use [0]=forming (skip), [1]=newest closed, [2]=middle, [3]=oldest
   if(count < 4) return sig;

   double o0 = rates[1].open,  c0 = rates[1].close;  // newest closed
   double o1 = rates[2].open,  c1 = rates[2].close;  // middle
   double o2 = rates[3].open,  c2 = rates[3].close;  // oldest

   double body0 = MathAbs(c0 - o0);
   double body1 = MathAbs(c1 - o1);
   double body2 = MathAbs(c2 - o2);

   //--- Morning Star (bullish): bar2=big bearish, bar1=small body, bar0=big bullish
   if(c2 < o2 && c0 > o0) // bar2 bearish, bar0 bullish
   {
      if(body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "MorningStar";
         //--- Boost: bar0 closes above midpoint of bar2
         if(c0 > (o2 + c2) / 2.0) { sig.strength = 4; sig.patternName = "MorningStar+"; }
      }
   }

   //--- Evening Star (bearish): bar2=big bullish, bar1=small body, bar0=big bearish
   if(c2 > o2 && c0 < o0)
   {
      if(body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "EveningStar";
         if(c0 < (o2 + c2) / 2.0) { sig.strength = 4; sig.patternName = "EveningStar+"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| OB Flip (Order Block)                                            |
//| Last opposing candle before a strong move = institutional zone   |
//+------------------------------------------------------------------+
PASignal PA_DetectOBFlip(MqlRates &rates[], int count, double atr,
                          double minMoveATR = 1.0)
{
   PASignal sig = {0, 0, ""};
   if(count < 4 || atr <= 0) return sig;

   //--- Bullish OB flip: bar[3]=bearish (last bear bar before big up move)
   //--- bar[2] and bar[1] should show strong bullish movement
   double move_up   = rates[1].close - rates[3].low;
   double move_down = rates[3].high - rates[1].close;

   //--- Bullish OB: prev bearish bar + strong bullish follow-through
   if(rates[3].close < rates[3].open) // bar3 bearish
   {
      if(move_up > atr * minMoveATR)
      {
         sig.direction = +1;
         sig.strength  = 3;
         sig.patternName = "OB_BullFlip";
         //--- Boost: bar[0] (forming) pulls back to bar[3] body
         double obHigh = MathMax(rates[3].open, rates[3].close);
         double obLow  = MathMin(rates[3].open, rates[3].close);
         if(rates[0].low <= obHigh && rates[0].low >= obLow)
         { sig.strength = 4; sig.patternName = "OB_BullFlip+Retest"; }
      }
   }

   //--- Bearish OB flip
   if(rates[3].close > rates[3].open) // bar3 bullish
   {
      if(move_down > atr * minMoveATR)
      {
         sig.direction = -1;
         sig.strength  = 3;
         sig.patternName = "OB_BearFlip";
         double obHigh = MathMax(rates[3].open, rates[3].close);
         double obLow  = MathMin(rates[3].open, rates[3].close);
         if(rates[0].high >= obLow && rates[0].high <= obHigh)
         { sig.strength = 4; sig.patternName = "OB_BearFlip+Retest"; }
      }
   }

   return sig;
}

//+------------------------------------------------------------------+
//| BOS / CHoCH Detection                                            |
//| Break of Structure: price breaks a recent swing in trend dir.    |
//| Change of Character: price breaks a recent swing AGAINST trend.  |
//+------------------------------------------------------------------+
PASignal PA_DetectBOS(MqlRates &rates[], int count, double swingHigh, double swingLow, double atr)
{
   PASignal sig = {0, 0, ""};
   if(count < 2 || atr <= 0) return sig;

   double close = rates[1].close; // last closed bar

   //--- Bullish BOS: close breaks above recent swing high
   if(swingHigh > 0 && close > swingHigh + atr * 0.1)
   {
      sig.direction = +1;
      sig.strength  = 3;
      sig.patternName = "BOS_Bull";
   }

   //--- Bearish BOS: close breaks below recent swing low
   if(swingLow > 0 && close < swingLow - atr * 0.1)
   {
      sig.direction = -1;
      sig.strength  = 3;
      sig.patternName = "BOS_Bear";
   }

   return sig;
}

//+------------------------------------------------------------------+
//| Aggregate Price Action Score                                     |
//| Scans multiple patterns and returns the strongest direction      |
//| with cumulative score.                                           |
//+------------------------------------------------------------------+
PASignal PA_AggregateScore(MqlRates &rates[], int count, double atr,
                            double swingHigh, double swingLow,
                            double minWickATR = 0.5, double wickBodyRatio = 2.0,
                            double minBodyATR = 0.15, double minMoveATR = 1.0)
{
   PASignal best = {0, 0, ""};

   //--- Pin bar (on bar[1] using bar[2] as context)
   if(count >= 2)
   {
      PASignal pin = PA_DetectPinBar(rates[1], rates[2], atr, minWickATR, wickBodyRatio);
      if(pin.direction != 0 && pin.strength > best.strength)
         best = pin;
   }

   //--- Engulfing (bar[0] vs bar[1])  — but bar[0] may be forming, so use bar[1] vs bar[2]
   if(count >= 3)
   {
      PASignal eng = PA_DetectEngulfing(rates[1], rates[2], atr, minBodyATR);
      if(eng.direction != 0 && eng.strength > best.strength)
         best = eng;
   }

   //--- Pin+Engulf combo
   if(count >= 4)
   {
      PASignal combo = PA_DetectPinEngulfCombo(rates, count, atr, minWickATR, wickBodyRatio, minBodyATR);
      if(combo.direction != 0 && combo.strength > best.strength)
         best = combo;
   }

   //--- Three-bar reversal
   if(count >= 4)
   {
      PASignal tbr = PA_DetectThreeBarReversal(rates, count, atr, minBodyATR);
      if(tbr.direction != 0 && tbr.strength > best.strength)
         best = tbr;
   }

   //--- OB flip
   if(count >= 4)
   {
      PASignal ob = PA_DetectOBFlip(rates, count, atr, minMoveATR);
      if(ob.direction != 0 && ob.strength > best.strength)
         best = ob;
   }

   //--- BOS
   if(count >= 2)
   {
      PASignal bos = PA_DetectBOS(rates, count, swingHigh, swingLow, atr);
      if(bos.direction != 0 && bos.strength > best.strength)
         best = bos;
   }

   //--- Inside bar (lower priority)
   if(count >= 3)
   {
      PASignal ib = PA_DetectInsideBar(rates[1], rates[2], atr);
      if(ib.direction != 0 && best.direction == 0)
         best = ib;
   }

   return best;
}

#endif // PRICE_ACTION_PATTERNS_MQH

//--- END INLINE: PriceActionPatterns.mqh ---
//--- INLINE: SupportResistance.mqh ---
//+------------------------------------------------------------------+
//|                                        SupportResistance.mqh     |
//|                      Multi-TF Support & Resistance Detection     |
//|                      Swing-based with zone clustering             |
//|                                                                  |
//|  Features:                                                       |
//|  - Swing high/low detection across multiple timeframes           |
//|  - Zone clustering (merge nearby swing levels)                   |
//|  - Touch counting (more touches = stronger level)                |
//|  - Freshness scoring (untested levels are strongest)             |
//|  - HTF (H4/D1) structural S/R as major levels                   |
//|  - MTF confluence: level present on 2+ TFs = stronger           |
//+------------------------------------------------------------------+
#ifndef SUPPORT_RESISTANCE_MQH
#define SUPPORT_RESISTANCE_MQH

#define SR_MAX_LEVELS 20
#define SR_MAX_TOUCHES 10

//+------------------------------------------------------------------+
//| S/R level                                                        |
//+------------------------------------------------------------------+
enum SRLevelType
{
   SR_SUPPORT,      // Support level
   SR_RESISTANCE    // Resistance level
};

struct SRLevel
{
   SRLevelType  type;
   double       price;          // level center price
   double       upper;          // zone upper boundary
   double       lower;          // zone lower boundary
   int          touches;        // number of times price tested this level
   int          timeframes;     // bitmask: which TFs this level exists on (1=M1,2=M5,4=M15,8=M30,16=H1,32=H4,64=D1)
   double       strength;       // 0..1 composite score (touches + MTF confluence + freshness)
   datetime     firstSeen;      // when level was first detected
   datetime     lastTest;       // when price last touched this level
   bool         tested;         // has price bounced from this level at least once
};

//+------------------------------------------------------------------+
//| S/R scan result                                                  |
//+------------------------------------------------------------------+
struct SRResult
{
   SRLevel     supports[];     // support levels (sorted nearest-first)
   SRLevel     resistances[];  // resistance levels (sorted nearest-first)
   int         supportCount;
   int         resistanceCount;
   bool        valid;
};

//+------------------------------------------------------------------+
//| S/R scan state (persistent per EA instance)                     |
//+------------------------------------------------------------------+
struct SRState
{
   SRResult    current;
   datetime    lastScan;
};

//+------------------------------------------------------------------+
//| Get timeframe bitmask                                             |
//+------------------------------------------------------------------+
int SR_TFBitmask(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 1;
      case PERIOD_M5:  return 2;
      case PERIOD_M15: return 4;
      case PERIOD_M30: return 8;
      case PERIOD_H1:  return 16;
      case PERIOD_H4:  return 32;
      case PERIOD_D1:  return 64;
      default:         return 0;
   }
}

//+------------------------------------------------------------------+
//| Detect swing points from a single timeframe                      |
//| Returns swing highs and lows as price arrays                    |
//+------------------------------------------------------------------+
void SR_DetectSwings(string symbol, ENUM_TIMEFRAMES tf, int lookback,
                     int swingLen, double &highs[], double &lows[])
{
   ArrayResize(highs, 0);
   ArrayResize(lows, 0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, lookback, rates) < lookback) return;

   for(int i = swingLen; i < lookback - swingLen; i++)
   {
      //--- Swing high
      bool isHigh = true;
      for(int j = 1; j <= swingLen; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
         { isHigh = false; break; }
      }
      if(isHigh)
      {
         int sz = ArraySize(highs);
         ArrayResize(highs, sz + 1);
         highs[sz] = rates[i].high;
      }

      //--- Swing low
      bool isLow = true;
      for(int j = 1; j <= swingLen; j++)
      {
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
         { isLow = false; break; }
      }
      if(isLow)
      {
         int sz = ArraySize(lows);
         ArrayResize(lows, sz + 1);
         lows[sz] = rates[i].low;
      }
   }
}

//+------------------------------------------------------------------+
//| Merge nearby levels into zones (cluster within tolerance)        |
//+------------------------------------------------------------------+
void SR_MergeLevels(double &levels[], int count, double tolerance, double &merged[], int &mergedCount)
{
   if(count == 0) { mergedCount = 0; return; }

   //--- Sort ascending
   ArraySort(levels);

   ArrayResize(merged, count);
   mergedCount = 0;
   merged[0] = levels[0];
   double clusterSum = levels[0];
   int clusterCount = 1;

   for(int i = 1; i < count; i++)
   {
      if(levels[i] - merged[mergedCount] <= tolerance)
      {
         //--- Same cluster — average them
         clusterSum += levels[i];
         clusterCount++;
         merged[mergedCount] = clusterSum / clusterCount;
      }
      else
      {
         //--- New cluster
         mergedCount++;
         merged[mergedCount] = levels[i];
         clusterSum = levels[i];
         clusterCount = 1;
      }
   }
   mergedCount++;
}

//+------------------------------------------------------------------+
//| Count touches for a level (how many times price bounced)         |
//+------------------------------------------------------------------+
int SR_CountTouches(string symbol, ENUM_TIMEFRAMES tf, int lookback,
                    double level, double tolerance)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, tf, 0, lookback, rates) < 5) return 0;

   int touches = 0;
   for(int i = 0; i < lookback; i++)
   {
      //--- Price touched the level (wick into the zone)
      if(MathAbs(rates[i].high - level) <= tolerance ||
         MathAbs(rates[i].low - level) <= tolerance)
      {
         touches++;
      }
      //--- Also count if price opened or closed near the level
      if(MathAbs(rates[i].open - level) <= tolerance * 0.5 ||
         MathAbs(rates[i].close - level) <= tolerance * 0.5)
      {
         touches++;
      }
   }
   return touches;
}

//+------------------------------------------------------------------+
//| Check if level is on multiple timeframes                         |
//+------------------------------------------------------------------+
int SR_MultiTFScore(string symbol, double level, double tolerance)
{
   ENUM_TIMEFRAMES tfs[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   int tfBits[] = {4, 8, 16, 32, 64};
   int score = 0;

   for(int t = 0; t < 5; t++)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int cnt = CopyRates(symbol, tfs[t], 0, 200, rates);
      if(cnt < 20) continue;

      for(int i = 2; i < cnt - 2; i++)
      {
         //--- Swing high at level?
         bool isHigh = true;
         for(int j = 1; j <= 2; j++)
         {
            if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
            { isHigh = false; break; }
         }
         if(isHigh && MathAbs(rates[i].high - level) <= tolerance)
         { score |= tfBits[t]; break; }

         //--- Swing low at level?
         bool isLow = true;
         for(int j = 1; j <= 2; j++)
         {
            if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
            { isLow = false; break; }
         }
         if(isLow && MathAbs(rates[i].low - level) <= tolerance)
         { score |= tfBits[t]; break; }
      }
   }
   return score;
}

//+------------------------------------------------------------------+
//| Main S/R scan: detect levels from multiple TFs                  |
//|                                                                  |
//| entryTF   = entry timeframe (M5 or M15)                         |
//| structTF  = structure timeframe (M15 or H1)                     |
//| majorTFs  = higher TFs for major levels (H4, D1)               |
//| zoneATR   = zone thickness in ATR multiples                     |
//+------------------------------------------------------------------+
bool SR_Scan(SRState &state, string symbol,
             ENUM_TIMEFRAMES entryTF, ENUM_TIMEFRAMES structTF,
             double atr, double zoneATR = 0.5, int swingLen = 2)
{
   double tolerance = atr * zoneATR;
   if(tolerance <= 0) tolerance = atr * 0.5;

   //--- Collect swing levels from entry TF + structure TF + H4 + D1
   double allHighs[];
   double allLows[];
   int highCount = 0;
   int lowCount = 0;
   ArrayResize(allHighs, 0);
   ArrayResize(allLows, 0);

   ENUM_TIMEFRAMES scanTFs[] = {entryTF, structTF, PERIOD_H4, PERIOD_D1};
   int scanLookbacks[] = {100, 200, 300, 500};
   int scanSwingLens[] = {swingLen, swingLen, 3, 3}; // wider swings on HTF

   for(int t = 0; t < 4; t++)
   {
      double h[];
      double l[];
      SR_DetectSwings(symbol, scanTFs[t], scanLookbacks[t], scanSwingLens[t], h, l);

      //--- Append to master list
      for(int i = 0; i < ArraySize(h); i++)
      {
         int sz = ArraySize(allHighs);
         ArrayResize(allHighs, sz + 1);
         allHighs[sz] = h[i];
      }
      for(int i = 0; i < ArraySize(l); i++)
      {
         int sz = ArraySize(allLows);
         ArrayResize(allLows, sz + 1);
         allLows[sz] = l[i];
      }
   }

   //--- Merge nearby swing highs → resistance levels
   double mergedH[];
   int mergedHCount = 0;
   SR_MergeLevels(allHighs, ArraySize(allHighs), tolerance, mergedH, mergedHCount);

   //--- Merge nearby swing lows → support levels
   double mergedL[];
   int mergedLCount = 0;
   SR_MergeLevels(allLows, ArraySize(allLows), tolerance, mergedL, mergedLCount);

   //--- Build resistance levels
   ArrayResize(state.current.resistances, SR_MAX_LEVELS);
   state.current.resistanceCount = 0;

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   for(int i = 0; i < mergedHCount && state.current.resistanceCount < SR_MAX_LEVELS; i++)
   {
      double level = mergedH[i];
      //--- Only keep levels above current price (resistance)
      if(level <= bid + atr * 0.2) continue;

      SRLevel sl;
      sl.type = SR_RESISTANCE;
      sl.price = level;
      sl.upper = level + tolerance * 0.5;
      sl.lower = level - tolerance * 0.5;
      sl.touches = SR_CountTouches(symbol, entryTF, 200, level, tolerance);
      sl.timeframes = SR_MultiTFScore(symbol, level, tolerance);
      //--- MTF score: count number of TF bits set
      int mtfCount = 0;
      { int tfmask = sl.timeframes; while(tfmask > 0) { mtfCount += (tfmask & 1); tfmask >>= 1; } }
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)mtfCount / 5.0 * 0.5);
      sl.firstSeen = 0;
      sl.lastTest = 0;
      sl.tested = (sl.touches >= 2);

      state.current.resistances[state.current.resistanceCount] = sl;
      state.current.resistanceCount++;
   }

   //--- Build support levels
   ArrayResize(state.current.supports, SR_MAX_LEVELS);
   state.current.supportCount = 0;

   for(int i = 0; i < mergedLCount && state.current.supportCount < SR_MAX_LEVELS; i++)
   {
      double level = mergedL[i];
      if(level >= bid - atr * 0.2) continue;

      SRLevel sl;
      sl.type = SR_SUPPORT;
      sl.price = level;
      sl.upper = level + tolerance * 0.5;
      sl.lower = level - tolerance * 0.5;
      sl.touches = SR_CountTouches(symbol, entryTF, 200, level, tolerance);
      sl.timeframes = SR_MultiTFScore(symbol, level, tolerance);
      int mtfCount = 0;
      { int tfmask = sl.timeframes; while(tfmask > 0) { mtfCount += (tfmask & 1); tfmask >>= 1; } }
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)mtfCount / 5.0 * 0.5);
      sl.firstSeen = 0;
      sl.lastTest = 0;
      sl.tested = (sl.touches >= 2);

      state.current.supports[state.current.supportCount] = sl;
      state.current.supportCount++;
   }

   state.current.valid = (state.current.supportCount > 0 || state.current.resistanceCount > 0);
   state.lastScan = TimeCurrent();

   return state.current.valid;
}

//+------------------------------------------------------------------+
//| Is price near a support level?                                   |
//| Returns the support index or -1                                  |
//+------------------------------------------------------------------+
int SR_NearSupport(SRResult &result, double price, double tolerance)
{
   double minDist = DBL_MAX;
   int nearest = -1;
   for(int i = 0; i < result.supportCount; i++)
   {
      double dist = MathAbs(price - result.supports[i].price);
      if(dist <= tolerance && dist < minDist)
      { minDist = dist; nearest = i; }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| Is price near a resistance level?                                |
//| Returns the resistance index or -1                               |
//+------------------------------------------------------------------+
int SR_NearResistance(SRResult &result, double price, double tolerance)
{
   double minDist = DBL_MAX;
   int nearest = -1;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      double dist = MathAbs(price - result.resistances[i].price);
      if(dist <= tolerance && dist < minDist)
      { minDist = dist; nearest = i; }
   }
   return nearest;
}

//+------------------------------------------------------------------+
//| Get nearest support below price (for SL placement)              |
//+------------------------------------------------------------------+
double SR_NearestSupportBelow(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.supportCount; i++)
   {
      if(result.supports[i].price < price)
      {
         double dist = price - result.supports[i].price;
         if(dist < minDist) { minDist = dist; best = result.supports[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest resistance above price (for TP target)              |
//+------------------------------------------------------------------+
double SR_NearestResistanceAbove(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      if(result.resistances[i].price > price)
      {
         double dist = result.resistances[i].price - price;
         if(dist < minDist) { minDist = dist; best = result.resistances[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest support above price (for sell SL placement)         |
//+------------------------------------------------------------------+
double SR_NearestSupportAbove(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.supportCount; i++)
   {
      if(result.supports[i].price > price)
      {
         double dist = result.supports[i].price - price;
         if(dist < minDist) { minDist = dist; best = result.supports[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Get nearest resistance below price (for sell TP target)         |
//+------------------------------------------------------------------+
double SR_NearestResistanceBelow(SRResult &result, double price)
{
   double best = 0;
   double minDist = DBL_MAX;
   for(int i = 0; i < result.resistanceCount; i++)
   {
      if(result.resistances[i].price < price)
      {
         double dist = price - result.resistances[i].price;
         if(dist < minDist) { minDist = dist; best = result.resistances[i].price; }
      }
   }
   return best;
}

//+------------------------------------------------------------------+
//| Is price at support (buy zone)?                                  |
//+------------------------------------------------------------------+
bool SR_AtSupport(SRResult &result, double price, double tolerance)
{
   return SR_NearSupport(result, price, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| Is price at resistance (sell zone)?                              |
//+------------------------------------------------------------------+
bool SR_AtResistance(SRResult &result, double price, double tolerance)
{
   return SR_NearResistance(result, price, tolerance) >= 0;
}

//+------------------------------------------------------------------+
//| Print S/R summary for debugging                                  |
//+------------------------------------------------------------------+
void SR_PrintLevels(SRResult &result, string symbol)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   Print(symbol, " S/R | Supports=", result.supportCount,
         " Resistances=", result.resistanceCount);
   for(int i = 0; i < result.supportCount; i++)
   {
      Print("  S#", i, " price=", DoubleToString(result.supports[i].price, digits),
            " touches=", result.supports[i].touches,
            " tfBit=", result.supports[i].timeframes,
            " str=", DoubleToString(result.supports[i].strength, 2));
   }
   for(int i = 0; i < result.resistanceCount; i++)
   {
      Print("  R#", i, " price=", DoubleToString(result.resistances[i].price, digits),
            " touches=", result.resistances[i].touches,
            " tfBit=", result.resistances[i].timeframes,
            " str=", DoubleToString(result.resistances[i].strength, 2));
   }
}

#endif // SUPPORT_RESISTANCE_MQH

//--- END INLINE: SupportResistance.mqh ---
//--- INLINE: MarketRegime.mqh ---
//+------------------------------------------------------------------+
//|                                            MarketRegime.mqh       |
//|               Market Regime Filter — Avoid Ranging Markets         |
//|               Uses ADX + ATR Compression + Session Volume          |
//+------------------------------------------------------------------+
#property copyright "XAU MATE Trading"
#property version   "1.00"
#property description "Market regime detection: Trending vs Ranging"

//--- Market Regime Enum
enum ENUM_MARKET_REGIME
{
   REGIME_TRENDING_UP,     // Trending Up (ADX > threshold, +DI > -DI)
   REGIME_TRENDING_DOWN,   // Trending Down (ADX > threshold, -DI > +DI)
   REGIME_RANGING,         // Ranging (ADX < threshold)
   REGIME_VOLATILE,        // High Volatility (ATR spike)
   REGIME_QUIET            // Low Volatility (ATR compression)
};

//+------------------------------------------------------------------+
//| Market Regime Detector Class                                      |
//+------------------------------------------------------------------+
class CMarketRegime
{
private:
   int      m_adxPeriod;
   int      m_atrPeriod;
   double   m_adxTrendThreshold;    // Above this = trending (default 25)
   double   m_adxStrongThreshold;   // Above this = strong trend (default 40)
   double   m_atrCompressionRatio;  // ATR/MA_ATR below this = compression
   double   m_atrExpansionRatio;    // ATR/MA_ATR above this = expansion
   int      m_maPeriod;             // MA period for ATR smoothing
   
   ENUM_MARKET_REGIME m_currentRegime;
   double   m_currentADX;
   double   m_currentPlusDI;
   double   m_currentMinusDI;
   double   m_currentATR;
   double   m_atrMA;
   double   m_atrRatio;
   bool     m_isRanging;
   bool     m_isTrending;
   bool     m_isVolatile;
   bool     m_isQuiet;
   
public:
   //--- Constructor
   CMarketRegime(int adxPeriod = 14, int atrPeriod = 14, int maPeriod = 50)
   {
      m_adxPeriod = adxPeriod;
      m_atrPeriod = atrPeriod;
      m_maPeriod = maPeriod;
      m_adxTrendThreshold = 25.0;
      m_adxStrongThreshold = 40.0;
      m_atrCompressionRatio = 0.7;
      m_atrExpansionRatio = 1.3;
      m_currentRegime = REGIME_RANGING;
      m_currentADX = 0;
      m_currentPlusDI = 0;
      m_currentMinusDI = 0;
      m_currentATR = 0;
      m_atrMA = 0;
      m_atrRatio = 1.0;
      m_isRanging = true;
      m_isTrending = false;
      m_isVolatile = false;
      m_isQuiet = false;
   }
   
   //--- Set thresholds
   void SetThresholds(double adxTrend = 25.0, double adxStrong = 40.0, 
                      double atrComp = 0.7, double atrExp = 1.3)
   {
      m_adxTrendThreshold = adxTrend;
      m_adxStrongThreshold = adxStrong;
      m_atrCompressionRatio = atrComp;
      m_atrExpansionRatio = atrExp;
   }
   
   //--- Calculate ADX and DI values
   bool CalcADX(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      double plusDI[], minusDI[], adx[];
      ArraySetAsSeries(plusDI, true);
      ArraySetAsSeries(minusDI, true);
      ArraySetAsSeries(adx, true);
      
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 0, 0, m_adxPeriod + 5, adx) < m_adxPeriod)
         return false;
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 1, 0, m_adxPeriod + 5, plusDI) < m_adxPeriod)
         return false;
      if(CopyBuffer(iADX(_Symbol, tf, m_adxPeriod, PRICE_CLOSE), 2, 0, m_adxPeriod + 5, minusDI) < m_adxPeriod)
         return false;
      
      m_currentADX = adx[0];
      m_currentPlusDI = plusDI[0];
      m_currentMinusDI = minusDI[0];
      
      return true;
   }
   
   //--- Calculate ATR and its moving average
   bool CalcATRRegime(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      double atr[];
      ArraySetAsSeries(atr, true);
      
      int atrHandle = iATR(_Symbol, tf, m_atrPeriod);
      if(atrHandle == INVALID_HANDLE) return false;
      
      if(CopyBuffer(atrHandle, 0, 0, m_maPeriod + 5, atr) < m_maPeriod)
         return false;
      
      m_currentATR = atr[0];
      
      // Calculate MA of ATR
      double sum = 0;
      for(int i = 0; i < m_maPeriod; i++)
         sum += atr[i];
      m_atrMA = sum / m_maPeriod;
      
      // ATR ratio (current / MA)
      m_atrRatio = (m_atrMA > 0) ? m_currentATR / m_atrMA : 1.0;
      
      return true;
   }
   
   //--- Detect market regime
   ENUM_MARKET_REGIME DetectRegime(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
   {
      if(!CalcADX(tf)) return REGIME_RANGING;
      if(!CalcATRRegime(tf)) return REGIME_RANGING;
      
      // Determine regime
      bool adxTrending = (m_currentADX >= m_adxTrendThreshold);
      bool adxStrong = (m_currentADX >= m_adxStrongThreshold);
      bool plusDIDominant = (m_currentPlusDI > m_currentMinusDI);
      bool minusDIDominant = (m_currentMinusDI > m_currentPlusDI);
      bool atrCompressed = (m_atrRatio < m_atrCompressionRatio);
      bool atrExpanded = (m_atrRatio > m_atrExpansionRatio);
      
      // Set boolean flags
      m_isRanging = !adxTrending || atrCompressed;
      m_isTrending = adxTrending && !atrCompressed;
      m_isVolatile = atrExpanded && adxTrending;
      m_isQuiet = atrCompressed && !adxTrending;
      
      // Determine regime
      if(adxStrong && plusDIDominant)
         m_currentRegime = REGIME_TRENDING_UP;
      else if(adxStrong && minusDIDominant)
         m_currentRegime = REGIME_TRENDING_DOWN;
      else if(adxTrending && plusDIDominant)
         m_currentRegime = REGIME_TRENDING_UP;
      else if(adxTrending && minusDIDominant)
         m_currentRegIME = REGIME_TRENDING_DOWN;
      else if(atrExpanded)
         m_currentRegime = REGIME_VOLATILE;
      else if(atrCompressed)
         m_currentRegime = REGIME_QUIET;
      else
         m_currentRegime = REGIME_RANGING;
      
      return m_currentRegime;
   }
   
   //--- Check if market is tradeable (not ranging)
   bool IsTradeable()
   {
      // Don't trade if:
      // 1. Market is ranging (ADX < 25)
      // 2. ATR is compressed (low volatility)
      // 3. ADX is falling (weakening trend)
      
      if(m_isRanging)
         return false;
      
      if(m_isQuiet)
         return false;
      
      // Check if ADX is rising (trend strengthening)
      // We use a simple check: ADX > 20 and not falling sharply
      if(m_currentADX < 20)
         return false;
      
      return true;
   }
   
   //--- Check if market is trending UP
   bool IsTrendingUp()
   {
      return (m_currentRegime == REGIME_TRENDING_UP && m_currentPlusDI > m_currentMinusDI);
   }
   
   //--- Check if market is trending DOWN
   bool IsTrendingDown()
   {
      return (m_currentRegime == REGIME_TRENDING_DOWN && m_currentMinusDI > m_currentPlusDI);
   }
   
   //--- Get regime name as string
   string GetRegimeName()
   {
      switch(m_currentRegime)
      {
         case REGIME_TRENDING_UP:    return "TRENDING UP";
         case REGIME_TRENDING_DOWN:  return "TRENDING DOWN";
         case REGIME_RANGING:        return "RANGING";
         case REGIME_VOLATILE:       return "VOLATILE";
         case REGIME_QUIET:          return "QUIET";
         default:                    return "UNKNOWN";
      }
   }
   
   //--- Get detailed status
   string GetStatusString()
   {
      string status = "Regime: " + GetRegimeName() + "\n";
      status += "ADX: " + DoubleToString(m_currentADX, 1) + " (+" + DoubleToString(m_currentPlusDI, 1) + "/-" + DoubleToString(m_currentMinusDI, 1) + ")\n";
      status += "ATR: " + DoubleToString(m_currentATR, 2) + " (MA: " + DoubleToString(m_atrMA, 2) + ")\n";
      status += "ATR Ratio: " + DoubleToString(m_atrRatio, 2) + "\n";
      status += "Tradeable: " + (IsTradeable() ? "YES" : "NO") + "\n";
      
      if(m_isRanging) status += "⚠️ Market is RANGING — avoid trading\n";
      if(m_isQuiet) status += "⚠️ Market is QUIET — low volatility\n";
      if(m_isVolatile) status += "⚡ Market is VOLATILE — use smaller lots\n";
      
      return status;
   }
   
   //--- Getters
   double GetADX() { return m_currentADX; }
   double GetPlusDI() { return m_currentPlusDI; }
   double GetMinusDI() { return m_currentMinusDI; }
   double GetATR() { return m_currentATR; }
   double GetATRMA() { return m_atrMA; }
   double GetATRRatio() { return m_atrRatio; }
   bool IsRanging() { return m_isRanging; }
   bool IsTrending() { return m_isTrending; }
   bool IsVolatile() { return m_isVolatile; }
   bool IsQuiet() { return m_isQuiet; }
};

//+------------------------------------------------------------------+
//| Global instance for quick access                                  |
//+------------------------------------------------------------------+
CMarketRegime g_marketRegime;

//+------------------------------------------------------------------+
//| Quick check function — returns true if market is tradeable        |
//+------------------------------------------------------------------+
bool IsMarketTradeable(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
{
   g_marketRegime.DetectRegime(tf);
   return g_marketRegime.IsTradeable();
}

//+------------------------------------------------------------------+
//| Get market direction bias (+1 = up, -1 = down, 0 = neutral)      |
//+------------------------------------------------------------------+
int GetMarketBias(ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
{
   g_marketRegime.DetectRegime(tf);
   if(g_marketRegime.IsTrendingUp()) return 1;
   if(g_marketRegime.IsTrendingDown()) return -1;
   return 0;
}
//+------------------------------------------------------------------+

//--- END INLINE: MarketRegime.mqh ---


//+------------------------------------------------------------------+

//| INPUT PARAMETERS                                                   |

//+------------------------------------------------------------------+



//--- Multi-symbol

input string   SymbolList          = "EURUSD+"; // Symbols to trade (comma-sep). Was EURJPY+ — but the account clamps

                                               // EURJPY stops to ~1% of price (~185 pips), making tight-stop scalping

                                               // impossible. EURUSD+ stores tight stops, so it is now the default.

                                               // '+' suffix is REQUIRED on Vantage demo (plain EURUSD = trade-disabled 10017).



//--- Timeframes

input ENUM_TIMEFRAMES TF_Entry     = PERIOD_M5;    // Entry timeframe

input ENUM_TIMEFRAMES TF_Structure = PERIOD_M15;   // Structure timeframe



//--- EMA Settings (M15)

input int      EMA_Fast            = 20;           // Fast EMA

input int      EMA_Slow            = 50;           // Slow EMA

input int      EMA_Trend           = 200;          // Trend EMA



//--- Bollinger Bands (M5)

input int      BB_Period           = 20;           // BB period

input double   BB_StdDev           = 2.0;          // BB std dev

input double   BB_TouchTolPct      = 5.0;          // BB touch tolerance (%) (was 1.0)



//--- RSI (M5) — V2.1 scalper: wider range for more entries

input int      RSI_Period          = 14;           // RSI period

input double   RSI_Buy_Max         = 80.0;         // RSI must be <= this for BUY (was 40)

input double   RSI_Sell_Min        = 20.0;         // RSI must be >= this for SELL (was 60)



//--- Confluence

input int      ConfluenceMinScore  = 1;            // Minimum confluence to enter (was 3)

input int      SwingLookback       = 2;            // Bars each side for swing detection

input int      SwingScanBars       = 50;           // Bars to scan for swings

input int      MaxSwingLevels      = 6;            // Max S/R levels to track



//--- Break & Retest

input double   BreakRetest_ATR     = 0.5;          // Max distance for retest (x ATR)



//--- Rejection Candle

input bool     UseRejectionCandle  = false;        // Require rejection candle at BB (false=off, was blocking all trades)

input double   Min_RejectWickATR   = 0.02;         // Min wick (xATR) (was 0.10)

input double   Min_WickBodyRatio   = 0.05;         // Min wick/body ratio (was 0.20)

input double   Min_BodyATR         = 0.02;         // Min body (xATR) (was 0.18)

input int      RejectLookback      = 5;            // Check last N bars (was 3)



//--- Engulfing

input double   EngulfBodyATR_Min   = 0.15;         // Min engulfing body (xATR)



//--- Risk Management

input double   RiskPerTradePct     = 0.5;          // % risk per trade

input double   SL_ATR_Mult         = 0.6;          // SL buffer (x ATR)

input double   SL_Max_ATR          = 2.0;          // SL cap (xATR)

input double   SL_Min_ATR          = 0.25;         // SL floor (xATR)



//--- TP Strategy — ATR-based for forex

input int      TP_Mode             = 1;            // TP: 0=BB band, 1=ATR x mult, 2=BB mid

input double   TP_ATR_Mult         = 1.5;          // TP as multiple of ATR (mode=1)

input double   Min_RR              = 1.0;          // Minimum reward:risk ratio (anti-bleed: >= 1:1)



//--- Partial Take-Profit

input bool     UsePartialTP        = false;        // Enable partial take profit

input double   PartialTP_Pct       = 75.0;         // Partial TP at X% of full TP distance

input double   PartialClosePct     = 50.0;         // Close X% of position at partial TP



//--- Trailing Stop

input bool     UseTrailing         = true;         // Trail after partial TP

input double   TrailingStart_ATR   = 1.5;          // Start trailing after X*ATR profit

input double   TrailingStep_ATR    = 0.5;          // Trailing step distance (xATR)



//--- Break-Even

input bool     UseBreakEven        = true;         // Move SL to breakeven

input double   BreakEven_ATR       = 1.5;          // Move SL after X*ATR profit



//--- Lot Sizing

input double   FixedLot            = 0.01;         // Fixed lot fallback



//--- Safety

input int      MaxPositionsPerPair = 1;            // Max positions per symbol (was 2)

input int      MaxGlobalPositions  = 6;            // Max total open positions (was 4)

input int      MaxDailyTrades      = 30;           // Max trades per day (all symbols) (was 20)

input double   MaxDailyLossPct     = 2.0;          // HARD STOP: close all positions at 2% daily loss

input int      MaxTPHits           = 5;            // Pause after X TPs hit PER SESSION

input int      CooldownMin         = 0;            // Minutes after trade closes (was 15)



//--- General

input ulong    MagicNumber         = 20260723;

input string   CommentPrefix       = "PAIR_EA";

input int      MaxSlippagePts      = 50;

input int      MaxSpreadPts        = 800;



//--- Session filter (PH Time = UTC+8)

input bool     UseSessionFilter    = false;

input int      SessionStartHour    = 15;           // London open (PH time)

input int      SessionStartMin     = 0;

input int      SessionEndHour      = 0;            // Midnight PH (end of London)

input int      SessionEndMin       = 0;

input int      Session2StartHour   = 20;           // NY open (PH time)

input int      Session2StartMin    = 0;

input int      Session2EndHour     = 5;            // NY close (PH time)

input int      Session2EndMin      = 0;

input bool     TradeMonday         = true;

input bool     TradeTuesday        = true;

input bool     TradeWednesday      = true;

input bool     TradeThursday       = true;

input bool     TradeFriday         = true;



//--- Debug

input bool     DebugMode           = true;

//--- Market Regime Filter (NEW — avoid ranging markets)
input string   Inp_Regime         = "=== MARKET REGIME =====";
input bool     UseMarketRegime    = true;   // Enable market regime filter
input double   RegimeADXThreshold = 25.0;   // ADX above this = trending
input double   RegimeADXStrong    = 40.0;   // ADX above this = strong trend
input double   RegimeATRCompRatio = 0.7;    // ATR/MA below this = compression
input double   RegimeATRExpRatio  = 1.3;    // ATR/MA above this = expansion


//--- FRVP Settings

input string   Inp_FRVP           = "===== FRVP ======";

input int      FRVP_Anchors       = 48;            // FRVP lookback bars

input double   FRVP_BucketPips    = 0.00050;       // FRVP bucket size (price units)

double         FRVP_BucketAuto    = 0.0;            // auto-detected per symbol

input double   FRVP_ValueAreaPct  = 70.0;           // Value area %

input double   FRVP_HVNThreshold  = 0.70;           // HVN threshold

input double   FRVP_LVNThreshold  = 0.20;           // LVN threshold

input double   FRVP_ZoneTolATR    = 0.30;           // Zone tolerance (xATR)

input int      FRVP_RefreshBars   = 6;              // Recompute every N bars

input bool     FRVP_UseAsConfluence = true;          // Use FRVP in confluence scoring

input int      FRVP_ScorePOC      = 2;              // Score: at POC

input int      FRVP_ScoreVAHVAL   = 2;              // Score: at VAH/VAL

input int      FRVP_ScoreHVN      = 1;              // Score: at HVN

//--- Support & Resistance Settings
input string   Inp_SR             = "===== S/R SETTINGS ======";
input bool     EnableSR           = true;           // Use S/R confluence
input double   SR_ZoneATR         = 0.5;            // S/R zone thickness (xATR)
input int      SR_SwingLen        = 2;              // Swing bars each side
input int      SR_ScoreLevel      = 2;              // Score: at S/R level
input int      SR_ScoreMTF        = 1;              // Extra score: multi-TF confirmation



//+------------------------------------------------------------------+

//| SYMBOL STATE — per-symbol indicator handles and data              |

//+------------------------------------------------------------------+

struct SymbolState

{

   string name;

   //--- Indicator handles

   int maFast, maSlow, maTrend;

   int bb, bbUpper, bbLower;

   int rsi, atrM5, atrM15;

   //--- Swing data

   double swingHighs[];

   double swingLows[];

   datetime lastSwingScan;

   //--- Fill mode (auto-detected)

   ENUM_ORDER_TYPE_FILLING fillMode;

   //--- Last bar time for new-bar detection

   datetime lastBarTime;

};



SymbolState g_states[];

int g_symbolCount = 0;



//--- Per-symbol FRVP state

FRVPState    g_frvpStates[];

int          g_frvpRefreshCounters[];

//--- Per-symbol S/R state
SRState       g_srStates[];



//+------------------------------------------------------------------+

//| GLOBAL VARIABLES                                                   |

//+------------------------------------------------------------------+

double   g_dailyPL = 0;

double   g_dailyStartBalance = 0;

datetime g_dayStart = 0;

int      g_tradesToday = 0;

bool     g_tradingPaused = false;

datetime g_lastTradeCloseTime = 0;

datetime g_eaStartTime = 0;      // Attach time — pre-bot history must not count as TP hits

//--- Per-session TP tracking

int      g_tpHits = 0;           // TPs hit in current session

bool     g_tpPause = false;      // TP pause active for current session

int      g_currentSession = 0;   // 0=none, 1=session1, 2=session2

datetime g_lastTPReset = 0;      // When tpHits was last reset

int      g_logFile = -1;

int      g_heartbeatCount = 0;



//+------------------------------------------------------------------+

//| HELPER: Get filling mode for symbol                               |

//+------------------------------------------------------------------+

ENUM_ORDER_TYPE_FILLING GetFillMode(string symbol)

{

   long filling = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);

   if(filling & SYMBOL_FILLING_FOK)  return ORDER_FILLING_FOK;

   if(filling & SYMBOL_FILLING_IOC)  return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;

}



//+------------------------------------------------------------------+

//| HELPER: Find symbol index by name                                 |

//+------------------------------------------------------------------+

int FindSymbol(string symbol)

{

   for(int i = 0; i < g_symbolCount; i++)

      if(g_states[i].name == symbol) return i;

   return -1;

}



//+------------------------------------------------------------------+

//| HELPER: Create all indicator handles for a symbol                 |

//+------------------------------------------------------------------+

bool CreateHandles(SymbolState &st)

{

   st.maFast   = iMA(st.name, TF_Structure, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);

   st.maSlow   = iMA(st.name, TF_Structure, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);

   st.maTrend  = iMA(st.name, TF_Structure, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);

   st.bb       = iBands(st.name, TF_Entry, BB_Period, 0, BB_StdDev, PRICE_CLOSE);

   st.bbUpper  = iBands(st.name, TF_Entry, BB_Period, 0, BB_StdDev, PRICE_CLOSE);

   st.bbLower  = iBands(st.name, TF_Entry, BB_Period, 0, BB_StdDev, PRICE_CLOSE);

   st.rsi      = iRSI(st.name, TF_Entry, RSI_Period, PRICE_CLOSE);

   st.atrM5    = iATR(st.name, TF_Entry, 14);

   st.atrM15   = iATR(st.name, TF_Structure, 14);



   if(st.maFast == INVALID_HANDLE || st.maSlow == INVALID_HANDLE || st.maTrend == INVALID_HANDLE ||

      st.bb == INVALID_HANDLE || st.rsi == INVALID_HANDLE || st.atrM5 == INVALID_HANDLE)

   {

      Print("ERROR: Failed to create handles for ", st.name);

      return false;

   }

   return true;

}



//+------------------------------------------------------------------+

//| HELPER: Release all indicator handles for a symbol                |

//+------------------------------------------------------------------+

void ReleaseHandles(SymbolState &st)

{

   if(st.maFast  != INVALID_HANDLE) IndicatorRelease(st.maFast);

   if(st.maSlow  != INVALID_HANDLE) IndicatorRelease(st.maSlow);

   if(st.maTrend != INVALID_HANDLE) IndicatorRelease(st.maTrend);

   if(st.bb      != INVALID_HANDLE) IndicatorRelease(st.bb);

   if(st.bbUpper != INVALID_HANDLE) IndicatorRelease(st.bbUpper);

   if(st.bbLower != INVALID_HANDLE) IndicatorRelease(st.bbLower);

   if(st.rsi     != INVALID_HANDLE) IndicatorRelease(st.rsi);

   if(st.atrM5   != INVALID_HANDLE) IndicatorRelease(st.atrM5);

   if(st.atrM15  != INVALID_HANDLE) IndicatorRelease(st.atrM15);

}



//+------------------------------------------------------------------+

//| Expert initialization                                              |

//+------------------------------------------------------------------+

int OnInit()

{

   Comment("FXPair EA v2.0\nMulti-Symbol Confluence Day Trader");

   g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   g_dayStart = GetDayStartUTC();

   g_tradesToday = 0;

   g_dailyPL = 0;

   g_tradingPaused = false;

   g_lastTradeCloseTime = 0;

   g_eaStartTime = TimeCurrent();

   g_lastTPReset = g_eaStartTime;   // don't count pre-bot history as TP hits (anti-lockout)



   //--- Parse symbols

   string parts[];

   g_symbolCount = StringSplit(SymbolList, ',', parts);

   if(g_symbolCount <= 0)

   {

      Print("ERROR: No symbols specified");

      return INIT_FAILED;

   }



   //--- Trim whitespace and validate

   ArrayResize(g_states, g_symbolCount);

   for(int i = 0; i < g_symbolCount; i++)

   {

      string sym = parts[i];

      StringTrimLeft(sym);

      StringTrimRight(sym);

      g_states[i].name = sym;



      if(!SymbolSelect(sym, true))

      {

         Print("WARNING: Cannot select symbol ", sym, " — it may not be available");

      }



      g_states[i].fillMode = GetFillMode(sym);

      g_states[i].lastSwingScan = 0;

      g_states[i].lastBarTime = 0;

      ArrayResize(g_states[i].swingHighs, 0);

      ArrayResize(g_states[i].swingLows, 0);

   }



   //--- Create indicator handles

   for(int i = 0; i < g_symbolCount; i++)

   {

      if(!CreateHandles(g_states[i]))

      {

         // Release already-created handles

         for(int j = 0; j < i; j++)

            ReleaseHandles(g_states[j]);

         ArrayFree(g_states);

         return INIT_FAILED;

      }

   }



   //--- Initialize FRVP state per symbol

   ArrayResize(g_frvpStates, g_symbolCount);

   ArrayResize(g_frvpRefreshCounters, g_symbolCount);

   for(int i = 0; i < g_symbolCount; i++)

   {

      g_frvpStates[i].lastCompute = 0;

      g_frvpStates[i].current.valid = false;

      g_frvpRefreshCounters[i] = FRVP_RefreshBars; // force first compute

   }
   //--- Initialize S/R state per symbol
   ArrayResize(g_srStates, g_symbolCount);
   for(int i = 0; i < g_symbolCount; i++)
   {
      g_srStates[i].lastScan = 0;
      g_srStates[i].current.valid = false;
   }





   //--- Log file

   g_logFile = FileOpen(CommentPrefix + "_log.csv", FILE_WRITE|FILE_CSV|FILE_ANSI, ",", CP_ACP);

   if(g_logFile != INVALID_HANDLE)

   {

      FileWrite(g_logFile, "Time", "Symbol", "Type", "Price", "SL", "TP", "Lot",

                "ConfBuy", "ConfSell", "EntryType", "Balance");

      FileClose(g_logFile);

   }



   string tpMode = (TP_Mode == 0) ? "BB_Band" : (TP_Mode == 1) ? "ATR_x" + DoubleToString(TP_ATR_Mult,1) : "BB_Mid";

   Print("================================================================");

   Print("FXPair EA v2.0 initialized (", g_symbolCount, " symbols)");

   Print("  Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

   Print("  Account: ", AccountInfoInteger(ACCOUNT_LOGIN), " @ ", AccountInfoString(ACCOUNT_SERVER));

   Print("  Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));

   Print("  Symbols: ", SymbolList);

   Print("  TF: M5 entry / M15 structure");

   Print("  Confluence min: ", ConfluenceMinScore);

   Print("  Rejection candle: ", UseRejectionCandle ? "ON" : "OFF (relaxed)");

   Print("  RSI: BUY<=", RSI_Buy_Max, " SELL>=", RSI_Sell_Min, " (relaxed)");

   Print("  SL: ", SL_ATR_Mult, "x ATR | TP: ", tpMode, " | RR>=", Min_RR);

   Print("  Partial TP: ", UsePartialTP ? "ON" : "OFF", " | Trailing: ", UseTrailing ? "ON" : "OFF");

   Print("  Break-Even: ", UseBreakEven ? "ON" : "OFF");

   Print("  Max positions: ", MaxGlobalPositions, " total, ", MaxPositionsPerPair, " per pair");

   Print("  Debug: ", DebugMode ? "ON" : "OFF", " | Magic: ", MagicNumber);

   Print("================================================================");



   return INIT_SUCCEEDED;

}



//+------------------------------------------------------------------+

//| Expert deinitialization                                            |

//+------------------------------------------------------------------+

void OnDeinit(const int reason)

{

   Comment("");

   for(int i = 0; i < g_symbolCount; i++)

      ReleaseHandles(g_states[i]);

   ArrayFree(g_states);

   if(g_logFile != INVALID_HANDLE) FileClose(g_logFile);

}



//+------------------------------------------------------------------+

//| Expert tick — loops through all symbols                           |

//+------------------------------------------------------------------+

void OnTick()

{

   //--- Daily reset + TP detection

   CheckDailyReset();

   DetectTPHits();



   //--- Heartbeat: log status every 12 bars (~1 hour on M5)

   g_heartbeatCount++;

   if(g_heartbeatCount >= 12)

   {

      g_heartbeatCount = 0;

      double bal = AccountInfoDouble(ACCOUNT_BALANCE);

      double eq = AccountInfoDouble(ACCOUNT_EQUITY);

      int posCount = CountAllPositions();

      Print("FXPair HEARTBEAT | Bal=", DoubleToString(bal,2),

            " Eq=", DoubleToString(eq,2),

            " Pos=", posCount,

            " TradesToday=", g_tradesToday,

            " Symbols=", g_symbolCount,

            " Time=", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));

   }



   for(int s = 0; s < g_symbolCount; s++)

   {

      // FIX: MQL5 can't bind a local reference to a dynamic-array element.

      // Use a copy + write-back at the end so lastBarTime/swings persist.

      SymbolState st = g_states[s];



      //--- Only on new bar (guard against the ARRAY element, not the copy)

      datetime curBar = iTime(st.name, TF_Entry, 0);

      if(curBar == g_states[s].lastBarTime) continue;

      g_states[s].lastBarTime = curBar;

      st.lastBarTime = curBar;



      //--- Manage open positions (ALWAYS — even when paused)

      ManageOpenPositions(st);



      //--- Pauses gate ONLY new entries

      if(g_tradingPaused) continue;

      if(g_tpPause) continue;

      if(!CheckDayOfWeek()) continue;



      //--- Cooldown

      if(g_lastTradeCloseTime > 0)

         if((int)(curBar - g_lastTradeCloseTime) < CooldownMin * 60) continue;



      //--- Position/trade limits

      if(CountPositionsForSymbol(st.name) >= MaxPositionsPerPair) continue;

      if(CountAllPositions() >= MaxGlobalPositions) continue;

      if(g_tradesToday >= MaxDailyTrades) continue;



      //--- Session & spread

      if(UseSessionFilter && !IsInSession()) continue;

      double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

      double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

      double point = SymbolInfoDouble(st.name, SYMBOL_POINT);

      double sp = (ask - bid) / point;

      if(sp > MaxSpreadPts) continue;

      //--- MARKET REGIME FILTER: Skip if market is ranging
      if(UseMarketRegime)
      {
         g_marketRegime.SetThresholds(RegimeADXThreshold, RegimeADXStrong, RegimeATRCompRatio, RegimeATRExpRatio);
         g_marketRegime.DetectRegime(TF_Entry);
         
         if(!g_marketRegime.IsTradeable())
         {
            static int lastRegimeWarn = 0;
            if(TimeCurrent() - lastRegimeWarn >= 300)
            {
               lastRegimeWarn = TimeCurrent();
               Print("REGIME BLOCK: ", st.name, " ", g_marketRegime.GetRegimeName(),
                     " | ADX=", DoubleToString(g_marketRegime.GetADX(), 1),
                     " | NOT TRADEABLE");
            }
            continue;
         }
      }

      //--- ATR

      double atrM5 = GetATR(st, TF_Entry);

      double atrM15 = GetATR(st, TF_Structure);

      if(atrM5 <= 0 || atrM15 <= 0) continue;



      //--- Update swings

      UpdateSwingLevels(st, atrM15);



      //--- Refresh FRVP

      g_frvpRefreshCounters[s]++;

      if(g_frvpRefreshCounters[s] >= FRVP_RefreshBars)

      {

         g_frvpRefreshCounters[s] = 0;

         double bucketPips = FRVP_BucketAuto;

         if(bucketPips <= 0) bucketPips = FRVP_BucketPips;

         FRVP_Compute(g_frvpStates[s], st.name, TF_Structure, FRVP_Anchors,

                       bucketPips, FRVP_ValueAreaPct, FRVP_HVNThreshold, FRVP_LVNThreshold);

         if(DebugMode && g_frvpStates[s].current.valid)

            FRVP_PrintProfile(g_frvpStates[s].current, st.name);


      //--- Refresh S/R (every other FRVP refresh cycle)
      if(EnableSR && g_frvpRefreshCounters[s] % 2 == 0)
      {
         SR_Scan(g_srStates[s], st.name, TF_Entry, TF_Structure, atrM5, SR_ZoneATR, SR_SwingLen);
         if(DebugMode && g_srStates[s].current.valid)
            SR_PrintLevels(g_srStates[s].current, st.name);
      }
      }



      //--- Confluence

      int confBuy = CalcConfluenceBuy(st, atrM5, atrM15);

      int confSell = CalcConfluenceSell(st, atrM5, atrM15);



      //--- Debug

      if(DebugMode)

      {

         double rsi = GetRSI(st);

         double bbU = GetBB(st, 1);

         double bbM = GetBB(st, 0);

         double bbL = GetBB(st, 2);

         double maF = GetMA(st, 0);

         double maS = GetMA(st, 1);

         double maT = GetMA(st, 2);

         int digits = (int)SymbolInfoInteger(st.name, SYMBOL_DIGITS);



         Print("FXPair ", st.name,

               " | BID=", DoubleToString(bid, digits),

               " ATR5=", DoubleToString(atrM5,5),

               " ATR15=", DoubleToString(atrM15,5),

               " RSI=", DoubleToString(rsi,1),

               " BB=[", DoubleToString(bbL,digits), " | ", DoubleToString(bbM,digits), " | ", DoubleToString(bbU,digits), "]",

               " | EMA=", DoubleToString(maF,digits), "/", DoubleToString(maS,digits), "/", DoubleToString(maT,digits),

               " | SH=", ArraySize(st.swingHighs), " SL=", ArraySize(st.swingLows),

               " | SP=", DoubleToString(sp,0), "pts",

               " | CONF_BUY=", confBuy, " CONF_SELL=", confSell);

      }



      //--- Entry decision

      int direction = 0; // 0=skip, 1=BUY, -1=SELL

      if(confBuy >= ConfluenceMinScore && confBuy > confSell)

      {

         direction = 1; // BUY wins

      }

      else if(confSell >= ConfluenceMinScore && confSell > confBuy)

      {

         direction = -1; // SELL wins

      }

      else if(confBuy >= ConfluenceMinScore && confSell >= ConfluenceMinScore && confBuy == confSell)

      {

         //--- Tie-break: use trend direction (EMA alignment)

         if(st.maFast > st.maSlow)

            direction = 1;  // Bullish trend → BUY

         else if(st.maFast < st.maSlow)

            direction = -1; // Bearish trend → SELL

         // else direction stays 0 (skip if EMAs are equal)

      }



      if(direction != 0)

      {

         if(direction == 1)

         {

            if(DebugMode) Print("FXPair ", st.name, " ENTRY SIGNAL: BUY conf=", confBuy,

                  " (tie=", confBuy == confSell ? "trend↑" : "dominant", ")");

            if(CheckBuyEntry(st, confBuy, confSell, atrM5))

            {

               g_tradesToday++;

            }

         }

         else

         {

            if(DebugMode) Print("FXPair ", st.name, " ENTRY SIGNAL: SELL conf=", confSell,

                  " (tie=", confSell == confBuy ? "trend↓" : "dominant", ")");

            if(CheckSellEntry(st, confBuy, confSell, atrM5))

            {

               g_tradesToday++;

            }

         }

      }

      else if(DebugMode && (confBuy >= 3 || confSell >= 3))

      {

         Print("FXPair ", st.name, " NEAR-MISS: confBuy=", confBuy, " confSell=", confSell,

               " (min=", ConfluenceMinScore, ")");

      }



      //--- Write back the working copy so swing/lastBarTime state persists

      g_states[s] = st;

   }

}



//+------------------------------------------------------------------+

//| BUY entry                                                         |

//+------------------------------------------------------------------+

bool CheckBuyEntry(SymbolState &st, int confBuy, int confSell, double atr)

{

   double m5_low[], m5_high[], m5_close[], m5_open[];

   ArraySetAsSeries(m5_open, true);  ArraySetAsSeries(m5_high, true);

   ArraySetAsSeries(m5_low, true);   ArraySetAsSeries(m5_close, true);

   // Signals evaluate the LAST CLOSED bar (start=1 skips the forming bar, which

   // has almost no data at the moment a new bar opens).

   if(CopyOpen(st.name, TF_Entry, 1, 5, m5_open) < 5) return false;

   if(CopyHigh(st.name, TF_Entry, 1, 5, m5_high) < 5) return false;

   if(CopyLow(st.name, TF_Entry, 1, 5, m5_low) < 5) return false;

   if(CopyClose(st.name, TF_Entry, 1, 5, m5_close) < 5) return false;



   //--- BB lower touch

   double bbLower = GetBB(st, 2);

   if(bbLower <= 0) return false;

   if(m5_low[0] > bbLower * (1.0 + BB_TouchTolPct / 100.0))

   {

      if(DebugMode) Print("FXPair BUY REJECTED ", st.name, ": no BB lower touch");

      return false;

   }



   //--- RSI

   double rsi = GetRSI(st);

   if(rsi <= 0 || rsi > RSI_Buy_Max)

   {

      if(DebugMode) Print("FXPair BUY REJECTED ", st.name, ": RSI=", DoubleToString(rsi,1));

      return false;

   }



   //--- Rejection candle (optional — was blocking almost all entries)

   if(UseRejectionCandle)

   {

      if(!HasBullishRejection(m5_open, m5_high, m5_low, m5_close, atr))

      {

         if(DebugMode) Print("FXPair BUY REJECTED ", st.name, ": no bullish rejection candle");

         return false;

      }

   }



   //--- SL

   double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

   double swingLow = GetNearestSwingLow(st);

   double slRaw = (swingLow > 0) ? fmin(m5_low[0], swingLow) : m5_low[0];

   double slPrice = slRaw - SL_ATR_Mult * atr;

   if(ask - slPrice > atr * SL_Max_ATR) slPrice = ask - atr * SL_Max_ATR;

   if(ask - slPrice < atr * SL_Min_ATR) slPrice = ask - atr * SL_Min_ATR;

   // Broker minimum stop distance (anti-bleed): the account rewrites stops closer

   // than SYMBOL_TRADE_STOPS_LEVEL, so clamp so the filled SL matches the plan.

   int stopsLevel = (int)SymbolInfoInteger(st.name, SYMBOL_TRADE_STOPS_LEVEL);

   if(stopsLevel > 0)

   {

      double minStop = stopsLevel * SymbolInfoDouble(st.name, SYMBOL_POINT);

      if(ask - slPrice < minStop) slPrice = ask - minStop;

   }

   if(slPrice >= ask) return false;



   //--- TP

   double tpPrice = CalcBuyTP(st, ask, atr);

   if(tpPrice <= ask) return false;



   //--- RR: stretch TP so reward:risk >= Min_RR always holds. This kills the

   //    "RR=0.75 rejected for hours" deadlock WITHOUT weakening Min_RR below 1:1.

   double rr = (tpPrice - ask) / (ask - slPrice);

   if(rr < Min_RR)

   {

      if(DebugMode) Print("FXPair BUY ", st.name, ": RR=", DoubleToString(rr,2), " < Min_RR=", DoubleToString(Min_RR,1), " - stretching TP");

      tpPrice = ask + (ask - slPrice) * Min_RR;

      rr = Min_RR;

   }



   //--- Lot

   double lot = CalcLotSize(st, ask - slPrice);

   if(lot <= 0) return false;



   //--- Send order

   int digits = (int)SymbolInfoInteger(st.name, SYMBOL_DIGITS);

   MqlTradeRequest req = {};

   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;

   req.symbol       = st.name;

   req.volume       = lot;

   req.price        = ask;

   req.sl           = NormalizeDouble(slPrice, digits);

   req.tp           = NormalizeDouble(tpPrice, digits);

   req.deviation    = MaxSlippagePts;

   req.magic        = MagicNumber;

   req.comment      = CommentPrefix + "_BUY";

   req.type_filling = st.fillMode;

   req.type         = ORDER_TYPE_BUY;



   bool ok = OrderSend(req, res);

   if(ok)

   {

      Print("FXPair BUY ", st.name, ": price=", DoubleToString(ask,digits),

            " SL=", DoubleToString(slPrice,digits),

            " TP=", DoubleToString(tpPrice,digits),

            " lot=", DoubleToString(lot,2), " RR=", DoubleToString(rr,2),

            " conf=", confBuy, "/", confSell);

      LogTrade(st.name, "BUY", ask, slPrice, tpPrice, lot, confBuy, confSell, "CONFLUENCE", "OK");

   }

   else

      Print("FXPair BUY FAILED ", st.name, ": ", res.retcode, " ", res.comment);

   return ok;

}



//+------------------------------------------------------------------+

//| SELL entry                                                        |

//+------------------------------------------------------------------+

bool CheckSellEntry(SymbolState &st, int confBuy, int confSell, double atr)

{

   double m5_low[], m5_high[], m5_close[], m5_open[];

   ArraySetAsSeries(m5_open, true);  ArraySetAsSeries(m5_high, true);

   ArraySetAsSeries(m5_low, true);   ArraySetAsSeries(m5_close, true);

   // Signals evaluate the LAST CLOSED bar (start=1 skips the forming bar, which

   // has almost no data at the moment a new bar opens).

   if(CopyOpen(st.name, TF_Entry, 1, 5, m5_open) < 5) return false;

   if(CopyHigh(st.name, TF_Entry, 1, 5, m5_high) < 5) return false;

   if(CopyLow(st.name, TF_Entry, 1, 5, m5_low) < 5) return false;

   if(CopyClose(st.name, TF_Entry, 1, 5, m5_close) < 5) return false;



   //--- BB upper touch

   double bbUpper = GetBB(st, 1);

   if(bbUpper <= 0) return false;

   if(m5_high[0] < bbUpper * (1.0 - BB_TouchTolPct / 100.0))

   {

      if(DebugMode) Print("FXPair SELL REJECTED ", st.name, ": no BB upper touch");

      return false;

   }



   //--- RSI

   double rsi = GetRSI(st);

   if(rsi <= 0 || rsi < RSI_Sell_Min)

   {

      if(DebugMode) Print("FXPair SELL REJECTED ", st.name, ": RSI=", DoubleToString(rsi,1));

      return false;

   }



   //--- Rejection candle (optional — was blocking almost all entries)

   if(UseRejectionCandle)

   {

      if(!HasBearishRejection(m5_open, m5_high, m5_low, m5_close, atr))

      {

         if(DebugMode) Print("FXPair SELL REJECTED ", st.name, ": no bearish rejection candle");

         return false;

      }

   }



   //--- SL

   double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

   double swingHigh = GetNearestSwingHigh(st);

   double slRaw = (swingHigh > 0) ? fmax(m5_high[0], swingHigh) : m5_high[0];

   double slPrice = slRaw + SL_ATR_Mult * atr;

   if(slPrice - bid > atr * SL_Max_ATR) slPrice = bid + atr * SL_Max_ATR;

   if(slPrice - bid < atr * SL_Min_ATR) slPrice = bid + atr * SL_Min_ATR;

   // Broker minimum stop distance (anti-bleed)

   int stopsLevel = (int)SymbolInfoInteger(st.name, SYMBOL_TRADE_STOPS_LEVEL);

   if(stopsLevel > 0)

   {

      double minStop = stopsLevel * SymbolInfoDouble(st.name, SYMBOL_POINT);

      if(slPrice - bid < minStop) slPrice = bid + minStop;

   }

   if(slPrice <= bid) return false;



   //--- TP

   double tpPrice = CalcSellTP(st, bid, atr);

   if(tpPrice >= bid) return false;



   //--- RR: stretch TP so reward:risk >= Min_RR always holds (see BUY entry)

   double rr = (bid - tpPrice) / (slPrice - bid);

   if(rr < Min_RR)

   {

      if(DebugMode) Print("FXPair SELL ", st.name, ": RR=", DoubleToString(rr,2), " < Min_RR=", DoubleToString(Min_RR,1), " - stretching TP");

      tpPrice = bid - (slPrice - bid) * Min_RR;

      rr = Min_RR;

   }



   //--- Lot

   double lot = CalcLotSize(st, slPrice - bid);

   if(lot <= 0) return false;



   //--- Send order

   int digits = (int)SymbolInfoInteger(st.name, SYMBOL_DIGITS);

   MqlTradeRequest req = {};

   MqlTradeResult  res = {};

   req.action       = TRADE_ACTION_DEAL;

   req.symbol       = st.name;

   req.volume       = lot;

   req.price        = bid;

   req.sl           = NormalizeDouble(slPrice, digits);

   req.tp           = NormalizeDouble(tpPrice, digits);

   req.deviation    = MaxSlippagePts;

   req.magic        = MagicNumber;

   req.comment      = CommentPrefix + "_SELL";

   req.type_filling = st.fillMode;

   req.type         = ORDER_TYPE_SELL;



   bool ok = OrderSend(req, res);

   if(ok)

   {

      Print("FXPair SELL ", st.name, ": price=", DoubleToString(bid,digits),

            " SL=", DoubleToString(slPrice,digits),

            " TP=", DoubleToString(tpPrice,digits),

            " lot=", DoubleToString(lot,2), " RR=", DoubleToString(rr,2),

            " conf=", confBuy, "/", confSell);

      LogTrade(st.name, "SELL", bid, slPrice, tpPrice, lot, confBuy, confSell, "CONFLUENCE", "OK");

   }

   else

      Print("FXPair SELL FAILED ", st.name, ": ", res.retcode, " ", res.comment);

   return ok;

}



//+==================================================================+

//| INDICATOR HELPERS (per-symbol)                                    |

//+==================================================================+



double GetATR(SymbolState &st, ENUM_TIMEFRAMES tf)

{

   double buf[];

   ArraySetAsSeries(buf, true);

   int handle = (tf == TF_Structure) ? st.atrM15 : st.atrM5;

   if(handle == INVALID_HANDLE) return 0;

   if(CopyBuffer(handle, 0, 0, 1, buf) < 1) return 0;

   return buf[0];

}



double GetBB(SymbolState &st, int mode)

{

   double buf[];

   ArraySetAsSeries(buf, true);

   int handle;

   if(mode == 0) handle = st.bb;

   else if(mode == 1) handle = st.bbUpper;

   else handle = st.bbLower;

   if(handle == INVALID_HANDLE) return 0;

   if(CopyBuffer(handle, mode, 0, 1, buf) < 1) return 0;

   return buf[0];

}



double GetRSI(SymbolState &st)

{

   double buf[];

   ArraySetAsSeries(buf, true);

   if(st.rsi == INVALID_HANDLE) return 0;

   if(CopyBuffer(st.rsi, 0, 1, 1, buf) < 1) return 0;   // last CLOSED bar RSI

   return buf[0];

}



double GetMA(SymbolState &st, int idx)

{

   double buf[];

   ArraySetAsSeries(buf, true);

   int handle;

   if(idx == 0) handle = st.maFast;

   else if(idx == 1) handle = st.maSlow;

   else handle = st.maTrend;

   if(handle == INVALID_HANDLE) return 0;

   if(CopyBuffer(handle, 0, 0, 1, buf) < 1) return 0;

   return buf[0];

}



//+==================================================================+

//| CONFLUENCE SCORING (0-12, V2.0 relaxed)                          |

//+==================================================================+



int CalcConfluenceBuy(SymbolState &st, double atrM5, double atrM15)

{

   int score = 0;

   string dbg = "";



   //--- 0. FRVP zone confluence (new)

   if(FRVP_UseAsConfluence)

   {

      int si = FindSymbol(st.name);

      if(si >= 0 && g_frvpStates[si].current.valid)

      {

         FRVPResult prof = g_frvpStates[si].current;

         double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

         double zoneTol = atrM5 * FRVP_ZoneTolATR;

         if(FRVP_AtVAL(prof, bid, zoneTol))

         { score += FRVP_ScoreVAHVAL; dbg += "FRVP_VAL(+)" + IntegerToString(FRVP_ScoreVAHVAL) + " "; }

         else if(FRVP_AtPOC(prof, bid, zoneTol))

         { score += FRVP_ScorePOC; dbg += "FRVP_POC(+)" + IntegerToString(FRVP_ScorePOC) + " "; }

         else if(FRVP_NearHVN(prof, bid, zoneTol) >= 0)

         { score += FRVP_ScoreHVN; dbg += "FRVP_HVN(+)" + IntegerToString(FRVP_ScoreHVN) + " "; }

         else

         { dbg += "FRVP_noZone(0) "; }

      }

   }



      //--- S/R confluence
   if(EnableSR)
   {
      int si = FindSymbol(st.name);
      if(si >= 0 && g_srStates[si].current.valid)
      {
         double bid = SymbolInfoDouble(st.name, SYMBOL_BID);
         double zoneTol = atrM5 * SR_ZoneATR;
         if(SR_AtSupport(g_srStates[si].current, bid, zoneTol))
         {
            score += SR_ScoreLevel;
            dbg += "SR_Support(+" + IntegerToString(SR_ScoreLevel) + ") ";
            if(g_srStates[si].current.supports[SR_NearSupport(g_srStates[si].current, bid, zoneTol)].timeframes > 4)
               { score += SR_ScoreMTF; dbg += "SR_MTF(+" + IntegerToString(SR_ScoreMTF) + ") "; }
         }
      }
   }

//--- 1. M15 EMA20 > EMA50 = +2

   double maF = GetMA(st, 0);

   double maS = GetMA(st, 1);

   if(maF > 0 && maS > 0)

   {

      if(maF > maS) { score += 2; dbg += "EMA20>50(+2) "; }

      else dbg += "EMA20<50(0) ";

   }



   //--- 2. M15 EMA50 > EMA200 = +1

   double maT = GetMA(st, 2);

   if(maS > 0 && maT > 0)

   {

      if(maS > maT) { score += 1; dbg += "EMA50>200(+1) "; }

      else dbg += "EMA50<200(0) ";

   }



   //--- 3. Market structure bullish (HH/HL) = +2

   if(IsBullMarketStructure(st)) { score += 2; dbg += "BullStruct(+2) "; }



   //--- 4. Break & retest bullish = +2

   if(CheckBullBreakRetest(st, atrM15)) { score += 2; dbg += "BullRetest(+2) "; }



   //--- 5. At S&R support level = +1

   if(AtSupportLevel(st, atrM15)) { score += 1; dbg += "Support(+1) "; }



   //--- 6. Bullish engulfing = +2

   if(DetectBullishEngulfing(st.name, atrM5)) { score += 2; dbg += "Engulf(+2) "; }



   //--- 7. Morning star reversal (3-bar) = +2 (V2.0: was duplicate of engulfing)

   if(DetectMorningStar(st.name, atrM5)) { score += 2; dbg += "MStar(+2) "; }



   if(DebugMode) Print("FXPair CONF_BUY ", st.name, "=", score, " | ", dbg);

   return score;

}



int CalcConfluenceSell(SymbolState &st, double atrM5, double atrM15)

{

   int score = 0;

   string dbg = "";



   //--- 0. FRVP zone confluence (new)

   if(FRVP_UseAsConfluence)

   {

      int si = FindSymbol(st.name);

      if(si >= 0 && g_frvpStates[si].current.valid)

      {

         FRVPResult prof = g_frvpStates[si].current;

         double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

         double zoneTol = atrM5 * FRVP_ZoneTolATR;

         if(FRVP_AtVAH(prof, ask, zoneTol))

         { score += FRVP_ScoreVAHVAL; dbg += "FRVP_VAH(-)" + IntegerToString(FRVP_ScoreVAHVAL) + " "; }

         else if(FRVP_AtPOC(prof, ask, zoneTol))

         { score += FRVP_ScorePOC; dbg += "FRVP_POC(-)" + IntegerToString(FRVP_ScorePOC) + " "; }

         else if(FRVP_NearHVN(prof, ask, zoneTol) >= 0)

         { score += FRVP_ScoreHVN; dbg += "FRVP_HVN(-)" + IntegerToString(FRVP_ScoreHVN) + " "; }

         else

         { dbg += "FRVP_noZone(0) "; }

      }

   }



      //--- S/R confluence
   if(EnableSR)
   {
      int si = FindSymbol(st.name);
      if(si >= 0 && g_srStates[si].current.valid)
      {
         double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);
         double zoneTol = atrM5 * SR_ZoneATR;
         if(SR_AtResistance(g_srStates[si].current, ask, zoneTol))
         {
            score += SR_ScoreLevel;
            dbg += "SR_Resist(+" + IntegerToString(SR_ScoreLevel) + ") ";
            if(g_srStates[si].current.resistances[SR_NearResistance(g_srStates[si].current, ask, zoneTol)].timeframes > 4)
               { score += SR_ScoreMTF; dbg += "SR_MTF(+" + IntegerToString(SR_ScoreMTF) + ") "; }
         }
      }
   }

//--- 1. M15 EMA20 < EMA50 = +2

   double maF = GetMA(st, 0);

   double maS = GetMA(st, 1);

   if(maF > 0 && maS > 0)

   {

      if(maF < maS) { score += 2; dbg += "EMA20<50(+2) "; }

      else dbg += "EMA20>50(0) ";

   }



   //--- 2. M15 EMA50 < EMA200 = +1

   double maT = GetMA(st, 2);

   if(maS > 0 && maT > 0)

   {

      if(maS < maT) { score += 1; dbg += "EMA50<200(+1) "; }

      else dbg += "EMA50>200(0) ";

   }



   //--- 3. Market structure bearish (LH/LL) = +2

   if(IsBearMarketStructure(st)) { score += 2; dbg += "BearStruct(+2) "; }



   //--- 4. Break & retest bearish = +2

   if(CheckBearBreakRetest(st, atrM15)) { score += 2; dbg += "BearRetest(+2) "; }



   //--- 5. At S&R resistance level = +1

   if(AtResistanceLevel(st, atrM15)) { score += 1; dbg += "Resist(+1) "; }



   //--- 6. Bearish engulfing = +2

   if(DetectBearishEngulfing(st.name, atrM5)) { score += 2; dbg += "Engulf(+2) "; }



   //--- 7. Evening star reversal (3-bar) = +2 (V2.0: was duplicate of engulfing)

   if(DetectEveningStar(st.name, atrM5)) { score += 2; dbg += "EStar(+2) "; }



   if(DebugMode) Print("FXPair CONF_SELL ", st.name, "=", score, " | ", dbg);

   return score;

}



//+==================================================================+

//| CANDLE PATTERN DETECTION                                          |

//+==================================================================+



//--- V2.0 FIX: Morning Star (bullish reversal)

// 3-bar pattern: bearish bar → small-body bar → large bullish bar

bool DetectMorningStar(string symbol, double atr)

{

   double o[], c[], h[], l[];

   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);

   if(CopyOpen(symbol, TF_Entry, 1, 3, o) < 3) return false;

   if(CopyClose(symbol, TF_Entry, 1, 3, c) < 3) return false;

   if(CopyHigh(symbol, TF_Entry, 1, 3, h) < 3) return false;

   if(CopyLow(symbol, TF_Entry, 1, 3, l) < 3) return false;



   // [2]=oldest, [1]=middle, [0]=newest

   double body2 = o[2] - c[2];  // First bar body (bearish if > 0)

   double body1 = MathAbs(c[1] - o[1]);  // Middle bar body (small)

   double body0 = c[0] - o[0];  // Last bar body (bullish if > 0)



   if(body2 < atr * Min_BodyATR) return false;       // First bar too small

   if(body1 > body2 * 0.5) return false;              // Middle body not small enough

   if(body0 < atr * Min_BodyATR) return false;        // Last bar too small

   if(c[2] > o[2]) return false;                      // First not bearish

   if(c[0] <= o[0]) return false;                      // Last not bullish

   if(c[0] < (o[2] + c[2]) / 2.0) return false;       // Last doesn't close above mid of first

   return true;

}



//--- V2.0 FIX: Evening Star (bearish reversal)

// 3-bar pattern: bullish bar → small-body bar → large bearish bar

bool DetectEveningStar(string symbol, double atr)

{

   double o[], c[], h[], l[];

   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   ArraySetAsSeries(h, true); ArraySetAsSeries(l, true);

   if(CopyOpen(symbol, TF_Entry, 1, 3, o) < 3) return false;

   if(CopyClose(symbol, TF_Entry, 1, 3, c) < 3) return false;

   if(CopyHigh(symbol, TF_Entry, 1, 3, h) < 3) return false;

   if(CopyLow(symbol, TF_Entry, 1, 3, l) < 3) return false;



   double body2 = c[2] - o[2];  // First bar body (bullish if > 0)

   double body1 = MathAbs(c[1] - o[1]);  // Middle bar body (small)

   double body0 = o[0] - c[0];  // Last bar body (bearish if > 0)



   if(body2 < atr * Min_BodyATR) return false;       // First bar too small

   if(body1 > body2 * 0.5) return false;              // Middle body not small enough

   if(body0 < atr * Min_BodyATR) return false;        // Last bar too small

   if(c[2] < o[2]) return false;                      // First not bullish

   if(c[0] >= o[0]) return false;                      // Last not bearish

   if(c[0] > (o[2] + c[2]) / 2.0) return false;      // Last doesn't close below mid of first

   return true;

}



//+==================================================================+

//| ENGULFING DETECTION                                               |

//+==================================================================+



bool DetectBullishEngulfing(string symbol, double atr)

{

   double o[], c[];

   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   if(CopyOpen(symbol, TF_Entry, 1, 3, o) < 3) return false;

   if(CopyClose(symbol, TF_Entry, 1, 3, c) < 3) return false;



   if(o[1] <= c[1]) return false;  // prev not bearish

   if(c[0] <= o[0]) return false;  // current not bullish

   double prevBody = o[1] - c[1];

   double currBody = c[0] - o[0];

   if(currBody <= prevBody) return false;

   if(currBody < atr * EngulfBodyATR_Min) return false;

   if(o[0] >= c[1]) return false;

   if(c[0] <= o[1]) return false;

   return true;

}



bool DetectBearishEngulfing(string symbol, double atr)

{

   double o[], c[];

   ArraySetAsSeries(o, true); ArraySetAsSeries(c, true);

   if(CopyOpen(symbol, TF_Entry, 1, 3, o) < 3) return false;

   if(CopyClose(symbol, TF_Entry, 1, 3, c) < 3) return false;



   if(o[1] >= c[1]) return false;  // prev not bullish

   if(c[0] >= o[0]) return false;  // current not bearish

   double prevBody = c[1] - o[1];

   double currBody = o[0] - c[0];

   if(currBody <= prevBody) return false;

   if(currBody < atr * EngulfBodyATR_Min) return false;

   if(o[0] <= c[1]) return false;

   if(c[0] >= o[1]) return false;

   return true;

}



//+==================================================================+

//| MARKET STRUCTURE                                                   |

//+==================================================================+



void DetectSwingPoints(SymbolState &st)

{

   double m15_high[], m15_low[];

   ArraySetAsSeries(m15_high, true);

   ArraySetAsSeries(m15_low, true);



   if(CopyHigh(st.name, TF_Structure, 1, SwingScanBars, m15_high) < SwingScanBars) return;

   if(CopyLow(st.name, TF_Structure, 1, SwingScanBars, m15_low) < SwingScanBars) return;



   ArrayFree(st.swingHighs);

   ArrayFree(st.swingLows);



   for(int i = SwingLookback; i < SwingScanBars - SwingLookback; i++)

   {

      bool isSwingHigh = true;

      for(int j = 1; j <= SwingLookback; j++)

      {

         if(m15_high[i] <= m15_high[i - j] || m15_high[i] <= m15_high[i + j])

         { isSwingHigh = false; break; }

      }

      if(isSwingHigh)

      {

         int sz = ArraySize(st.swingHighs);

         ArrayResize(st.swingHighs, sz + 1, 20);

         st.swingHighs[sz] = m15_high[i];

      }



      bool isSwingLow = true;

      for(int j = 1; j <= SwingLookback; j++)

      {

         if(m15_low[i] >= m15_low[i - j] || m15_low[i] >= m15_low[i + j])

         { isSwingLow = false; break; }

      }

      if(isSwingLow)

      {

         int sz = ArraySize(st.swingLows);

         ArrayResize(st.swingLows, sz + 1, 20);

         st.swingLows[sz] = m15_low[i];

      }

   }



   //--- Keep most recent

   if(ArraySize(st.swingHighs) > MaxSwingLevels)

   {

      int start = ArraySize(st.swingHighs) - MaxSwingLevels;

      double temp[];

      ArrayResize(temp, MaxSwingLevels);

      ArrayCopy(temp, st.swingHighs, 0, start, MaxSwingLevels);

      ArrayResize(st.swingHighs, MaxSwingLevels);

      ArrayCopy(st.swingHighs, temp);

   }

   if(ArraySize(st.swingLows) > MaxSwingLevels)

   {

      int start = ArraySize(st.swingLows) - MaxSwingLevels;

      double temp[];

      ArrayResize(temp, MaxSwingLevels);

      ArrayCopy(temp, st.swingLows, 0, start, MaxSwingLevels);

      ArrayResize(st.swingLows, MaxSwingLevels);

      ArrayCopy(st.swingLows, temp);

   }

}



bool IsBullMarketStructure(SymbolState &st)

{

   if(ArraySize(st.swingHighs) < 2 || ArraySize(st.swingLows) < 2) return false;

   int last = ArraySize(st.swingHighs) - 1;

   bool hh = (st.swingHighs[last] > st.swingHighs[last - 1]);

   last = ArraySize(st.swingLows) - 1;

   bool hl = (st.swingLows[last] > st.swingLows[last - 1]);

   return (hh && hl);

}



bool IsBearMarketStructure(SymbolState &st)

{

   if(ArraySize(st.swingHighs) < 2 || ArraySize(st.swingLows) < 2) return false;

   int last = ArraySize(st.swingHighs) - 1;

   bool lh = (st.swingHighs[last] < st.swingHighs[last - 1]);

   last = ArraySize(st.swingLows) - 1;

   bool ll = (st.swingLows[last] < st.swingLows[last - 1]);

   return (lh && ll);

}



double GetNearestSwingLow(SymbolState &st)

{

   double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

   double nearest = 0;

   double minDist = DBL_MAX;

   for(int i = 0; i < ArraySize(st.swingLows); i++)

   {

      if(st.swingLows[i] < bid && (bid - st.swingLows[i]) < minDist)

      { minDist = bid - st.swingLows[i]; nearest = st.swingLows[i]; }

   }

   return nearest;

}



double GetNearestSwingHigh(SymbolState &st)

{

   double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

   double nearest = 0;

   double minDist = DBL_MAX;

   for(int i = 0; i < ArraySize(st.swingHighs); i++)

   {

      if(st.swingHighs[i] > ask && (st.swingHighs[i] - ask) < minDist)

      { minDist = st.swingHighs[i] - ask; nearest = st.swingHighs[i]; }

   }

   return nearest;

}



//+==================================================================+

//| BREAK & RETEST                                                     |

//+==================================================================+



bool CheckBullBreakRetest(SymbolState &st, double atrM15)

{

   if(ArraySize(st.swingHighs) < 1) return false;

   double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

   double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

   for(int i = 0; i < ArraySize(st.swingHighs); i++)

   {

      double level = st.swingHighs[i];

      double retestZone = level + BreakRetest_ATR * atrM15;

      double breakZone = level + 0.1 * atrM15;

      if(bid > breakZone && ask <= retestZone) return true;

   }

   return false;

}



bool CheckBearBreakRetest(SymbolState &st, double atrM15)

{

   if(ArraySize(st.swingLows) < 1) return false;

   double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

   double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

   for(int i = 0; i < ArraySize(st.swingLows); i++)

   {

      double level = st.swingLows[i];

      double retestZone = level - BreakRetest_ATR * atrM15;

      double breakZone = level - 0.1 * atrM15;

      if(ask < breakZone && bid >= retestZone) return true;

   }

   return false;

}



//+==================================================================+

//| S&R LEVELS                                                         |

//+==================================================================+



bool AtSupportLevel(SymbolState &st, double atrM15)

{

   double bid = SymbolInfoDouble(st.name, SYMBOL_BID);

   double proximity = atrM15 * 0.3;

   for(int i = 0; i < ArraySize(st.swingLows); i++)

   {

      if(MathAbs(bid - st.swingLows[i]) <= proximity) return true;

   }

   return false;

}



bool AtResistanceLevel(SymbolState &st, double atrM15)

{

   double ask = SymbolInfoDouble(st.name, SYMBOL_ASK);

   double proximity = atrM15 * 0.3;

   for(int i = 0; i < ArraySize(st.swingHighs); i++)

   {

      if(MathAbs(ask - st.swingHighs[i]) <= proximity) return true;

   }

   return false;

}



//+==================================================================+

//| REJECTION CANDLES                                                  |

//+==================================================================+



bool HasBullishRejection(double &open[], double &high[], double &low[], double &close[], double atr)

{

   int limit = MathMin(RejectLookback, ArraySize(close) - 1);

   for(int i = 0; i < limit; i++)

   {

      if(close[i] <= open[i]) continue;

      double body = close[i] - open[i];

      double lowerWick = open[i] - low[i];

      if(lowerWick < atr * Min_RejectWickATR) continue;

      if(body > 0 && lowerWick / body < Min_WickBodyRatio) continue;

      if(body < atr * Min_BodyATR) continue;

      return true;

   }

   return false;

}



bool HasBearishRejection(double &open[], double &high[], double &low[], double &close[], double atr)

{

   int limit = MathMin(RejectLookback, ArraySize(close) - 1);

   for(int i = 0; i < limit; i++)

   {

      if(close[i] >= open[i]) continue;

      double body = open[i] - close[i];

      double upperWick = high[i] - open[i];

      if(upperWick < atr * Min_RejectWickATR) continue;

      if(body > 0 && upperWick / body < Min_WickBodyRatio) continue;

      if(body < atr * Min_BodyATR) continue;

      return true;

   }

   return false;

}



//+==================================================================+

//| TP / SL CALCULATIONS                                               |

//+==================================================================+



double CalcBuyTP(SymbolState &st, double ask, double atr)

{

   if(TP_Mode == 0)

   {

      double bbUpper = GetBB(st, 1);

      if(bbUpper > 0) return bbUpper;

   }

   else if(TP_Mode == 2)

   {

      double bbMid = GetBB(st, 0);

      if(bbMid > ask) return bbMid;

   }

   return ask + atr * TP_ATR_Mult;

}



double CalcSellTP(SymbolState &st, double bid, double atr)

{

   if(TP_Mode == 0)

   {

      double bbLower = GetBB(st, 2);

      if(bbLower > 0) return bbLower;

   }

   else if(TP_Mode == 2)

   {

      double bbMid = GetBB(st, 0);

      if(bbMid < bid) return bbMid;

   }

   return bid - atr * TP_ATR_Mult;

}



//+==================================================================+

//| POSITION SIZING                                                    |

//+==================================================================+



double CalcLotSize(SymbolState &st, double slDistPts)

{

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   double riskMoney = balance * RiskPerTradePct / 100.0;

   double tickValue = SymbolInfoDouble(st.name, SYMBOL_TRADE_TICK_VALUE);

   double tickSize = SymbolInfoDouble(st.name, SYMBOL_TRADE_TICK_SIZE);

   double point = SymbolInfoDouble(st.name, SYMBOL_POINT);



   if(tickValue <= 0 || tickSize <= 0 || slDistPts <= 0)

      return FixedLot;



   double slInTicks = slDistPts / tickSize;

   double lotByRisk = riskMoney / (slInTicks * tickValue);



   double lotStep = SymbolInfoDouble(st.name, SYMBOL_VOLUME_STEP);

   double minLot  = SymbolInfoDouble(st.name, SYMBOL_VOLUME_MIN);

   double maxLot  = SymbolInfoDouble(st.name, SYMBOL_VOLUME_MAX);



   //--- Cap notional exposure: ~25k units per $10k balance (prevents tiny-SL lot explosion)

   double notionalCap = (balance / 10000.0) * 25000.0;

   if(notionalCap < minLot) notionalCap = minLot;

   if(maxLot <= 0 || notionalCap < maxLot) maxLot = notionalCap;

   if(lotStep > 0) maxLot = MathFloor(maxLot / lotStep) * lotStep;



   lotByRisk = MathFloor(lotByRisk / lotStep) * lotStep;

   lotByRisk = MathMax(minLot, MathMin(lotByRisk, maxLot));



   return lotByRisk;

}



double NormalizeLot(SymbolState &st, double lot)

{

   double lotStep = SymbolInfoDouble(st.name, SYMBOL_VOLUME_STEP);

   double minLot  = SymbolInfoDouble(st.name, SYMBOL_VOLUME_MIN);

   double maxLot  = SymbolInfoDouble(st.name, SYMBOL_VOLUME_MAX);

   lot = MathFloor(lot / lotStep) * lotStep;

   lot = MathMax(minLot, MathMin(lot, maxLot));

   return lot;

}



//+==================================================================+

//| POSITION COUNTING & MANAGEMENT                                    |

//+==================================================================+



int CountPositionsForSymbol(string symbol)

{

   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)

   {

      if(PositionGetTicket(i) > 0)

      {

         if(PositionGetString(POSITION_SYMBOL) == symbol &&

            PositionGetInteger(POSITION_MAGIC) == MagicNumber)

            count++;

      }

   }

   return count;

}



int CountAllPositions()

{

   int count = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)

   {

      if(PositionGetTicket(i) > 0)

      {

         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)

            count++;

      }

   }

   return count;

}



void ManageOpenPositions(SymbolState &st)

{

   if(!UsePartialTP && !UseTrailing && !UseBreakEven) return;



   int digits = (int)SymbolInfoInteger(st.name, SYMBOL_DIGITS);

   double atr = GetATR(st, TF_Entry);

   if(atr <= 0) return;



   for(int i = PositionsTotal() - 1; i >= 0; i--)

   {

      ulong ticket = PositionGetTicket(i);

      if(ticket == 0) continue;

      if(PositionGetString(POSITION_SYMBOL) != st.name) continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;



      double entry       = PositionGetDouble(POSITION_PRICE_OPEN);

      double sl          = PositionGetDouble(POSITION_SL);

      double tp          = PositionGetDouble(POSITION_TP);

      double volume      = PositionGetDouble(POSITION_VOLUME);

      long   type        = PositionGetInteger(POSITION_TYPE);

      double point       = SymbolInfoDouble(st.name, SYMBOL_POINT);

      double currentPrice = (type == POSITION_TYPE_BUY) ?

                            SymbolInfoDouble(st.name, SYMBOL_BID) :

                            SymbolInfoDouble(st.name, SYMBOL_ASK);



      //--- Break-Even

      if(UseBreakEven)

      {

         double beDist = BreakEven_ATR * atr;

         if(type == POSITION_TYPE_BUY)

         {

            double newSL = entry + point * 5;

            if(currentPrice >= entry + beDist && sl < entry)

            {

               MqlTradeRequest req = {}; MqlTradeResult res = {};

               req.action = TRADE_ACTION_SLTP; req.symbol = st.name;

               req.position = ticket; req.sl = NormalizeDouble(newSL, digits);

               req.tp = tp; req.magic = MagicNumber;

               OrderSend(req, res);

            }

         }

         else

         {

            double newSL = entry - point * 5;

            if(currentPrice <= entry - beDist && (sl > entry || sl == 0))

            {

               MqlTradeRequest req = {}; MqlTradeResult res = {};

               req.action = TRADE_ACTION_SLTP; req.symbol = st.name;

               req.position = ticket; req.sl = NormalizeDouble(newSL, digits);

               req.tp = tp; req.magic = MagicNumber;

               OrderSend(req, res);

            }

         }

      }



      //--- Partial TP

      if(UsePartialTP && volume > SymbolInfoDouble(st.name, SYMBOL_VOLUME_MIN))

      {

         double tpDist = (tp > 0) ? MathAbs(tp - entry) : atr * TP_ATR_Mult;

         double partialPrice;



         if(type == POSITION_TYPE_BUY)

         {

            partialPrice = entry + tpDist * PartialTP_Pct / 100.0;

            if(currentPrice >= partialPrice)

            {

               double closeLot = NormalizeLot(st, volume * PartialClosePct / 100.0);

               if(closeLot >= SymbolInfoDouble(st.name, SYMBOL_VOLUME_MIN))

               {

                  MqlTradeRequest req = {}; MqlTradeResult res = {};

                  req.action = TRADE_ACTION_DEAL; req.symbol = st.name;

                  req.volume = closeLot; req.type = ORDER_TYPE_SELL;

                  req.price = SymbolInfoDouble(st.name, SYMBOL_BID);

                  req.deviation = MaxSlippagePts; req.magic = MagicNumber;

                  req.comment = CommentPrefix + "_PARTIAL";

                  req.type_filling = st.fillMode; req.position = ticket;

                  OrderSend(req, res);

               }

            }

         }

         else

         {

            partialPrice = entry - tpDist * PartialTP_Pct / 100.0;

            if(currentPrice <= partialPrice)

            {

               double closeLot = NormalizeLot(st, volume * PartialClosePct / 100.0);

               if(closeLot >= SymbolInfoDouble(st.name, SYMBOL_VOLUME_MIN))

               {

                  MqlTradeRequest req = {}; MqlTradeResult res = {};

                  req.action = TRADE_ACTION_DEAL; req.symbol = st.name;

                  req.volume = closeLot; req.type = ORDER_TYPE_BUY;

                  req.price = SymbolInfoDouble(st.name, SYMBOL_ASK);

                  req.deviation = MaxSlippagePts; req.magic = MagicNumber;

                  req.comment = CommentPrefix + "_PARTIAL";

                  req.type_filling = st.fillMode; req.position = ticket;

                  OrderSend(req, res);

               }

            }

         }

      }



      //--- Trailing Stop

      if(UseTrailing)

      {

         double trailStart = TrailingStart_ATR * atr;

         double trailStep  = TrailingStep_ATR * atr;



         if(type == POSITION_TYPE_BUY)

         {

            double profitDist = currentPrice - entry;

            if(profitDist >= trailStart)

            {

               double newSL = currentPrice - trailStep;

               if(newSL > sl)

               {

                  MqlTradeRequest req = {}; MqlTradeResult res = {};

                  req.action = TRADE_ACTION_SLTP; req.symbol = st.name;

                  req.position = ticket;

                  req.sl = NormalizeDouble(newSL, digits); req.tp = tp;

                  req.magic = MagicNumber;

                  OrderSend(req, res);

               }

            }

         }

         else

         {

            double profitDist = entry - currentPrice;

            if(profitDist >= trailStart)

            {

               double newSL = currentPrice + trailStep;

               if(newSL < sl || sl == 0)

               {

                  MqlTradeRequest req = {}; MqlTradeResult res = {};

                  req.action = TRADE_ACTION_SLTP; req.symbol = st.name;

                  req.position = ticket;

                  req.sl = NormalizeDouble(newSL, digits); req.tp = tp;

                  req.magic = MagicNumber;

                  OrderSend(req, res);

               }

            }

         }

      }

   }

}



//+==================================================================+

//| SWING CACHE UPDATE                                                 |

//+==================================================================+



void UpdateSwingLevels(SymbolState &st, double atrM15)

{

   datetime m15Time = iTime(st.name, TF_Structure, 0);

   if(m15Time == st.lastSwingScan) return;

   st.lastSwingScan = m15Time;

   DetectSwingPoints(st);

}



//+==================================================================+

//| DAILY / SAFETY CHECKS                                              |

//+==================================================================+



void CheckDailyReset()

{

   datetime dayStart = GetDayStartUTC();

   if(dayStart != g_dayStart)

   {

      g_dayStart = dayStart;

      g_tradesToday = 0;

      g_dailyStartBalance = AccountInfoDouble(ACCOUNT_BALANCE);

      g_dailyPL = 0;

      g_tradingPaused = false;

      g_lastTradeCloseTime = 0;

      g_tpHits = 0;

      g_tpPause = false;

      g_currentSession = 0;

      g_lastTPReset = dayStart;

   }



   //--- Detect session change -> reset TP counter for new session

   int newSession = GetCurrentSession();

   if(newSession != g_currentSession)

   {

      g_currentSession = newSession;

      g_tpHits = 0;

      g_tpPause = false;

      g_lastTPReset = TimeCurrent();

      if(newSession > 0)

         Print("SESSION CHANGE -> ", (newSession == 1 ? "LONDON" : "NY"),

               " | TP counter reset. Fresh ", MaxTPHits, " TPs available.");

   }



   double currBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(g_dailyStartBalance > 0)

   {

      double lossPct = (g_dailyStartBalance - currBalance) / g_dailyStartBalance * 100.0;      if(lossPct >= MaxDailyLossPct)
      {
         g_tradingPaused = true;
         Print("*** HARD STOP: DAILY LOSS LIMIT ", DoubleToString(lossPct, 1), "% — CLOSING ALL ***");
         CloseAllFXPairPositions();
      }

   }

}



//+------------------------------------------------------------------+

//| Detect TPs hit in current session (check deal history)            |

//+------------------------------------------------------------------+

void DetectTPHits()

{

   CheckDailyReset();



   // Only count deals from current session start

   datetime sessionStart = g_lastTPReset;

   if(!HistorySelect(sessionStart, TimeCurrent())) return;



   int deals = HistoryDealsTotal();

   for(int i = 0; i < deals; i++)

   {

      ulong ticket = HistoryDealGetTicket(i);

      if(ticket == 0) continue;

      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicNumber) continue;



      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      if(dealTime < sessionStart) continue;

      if(dealTime < g_eaStartTime) continue;   // ignore pre-bot history (anti-lockout)



      // Track most recent close (any outcome) so the Cooldown filter measures

      // from when a position actually closed, not when it opened.

      if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)

         g_lastTradeCloseTime = dealTime;



      long reason = HistoryDealGetInteger(ticket, DEAL_REASON);

      if(reason == DEAL_REASON_TP)

      {

         static datetime lastTPDealTime = 0;

         static ulong lastTPDealTicket = 0;

         if(dealTime == lastTPDealTime && ticket == lastTPDealTicket) continue;

         lastTPDealTime = dealTime;

         lastTPDealTicket = ticket;



         g_tpHits++;

         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);

         string sym = HistoryDealGetString(ticket, DEAL_SYMBOL);

         string sessName = (g_currentSession == 1) ? "LONDON" : "NY";

         Print("TP HIT #", g_tpHits, "/", MaxTPHits,

               " (", sessName, " session) on ", sym,

               " | Profit: $", DoubleToString(profit, 2));



         if(g_tpHits >= MaxTPHits)

         {

            g_tpPause = true;

            Print("TP PAUSE [", sessName, "]: ", g_tpHits,

                  " TPs hit. No new entries.");

         }

      }

   }



   // Advance cursor so each close is counted exactly once (was: re-counted every tick

   // -> counter exploded -> g_tpPause locked the bot out of new entries

   // AND blocked ManageOpenPositions via the early return).

   g_lastTPReset = TimeCurrent();

}



//+------------------------------------------------------------------+

//| Close all positions for this EA                                    |

//+------------------------------------------------------------------+

void CloseAllFXPairPositions()

{

   for(int i = PositionsTotal() - 1; i >= 0; i--)

   {

      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      string sym = PositionGetString(POSITION_SYMBOL);

      double vol = PositionGetDouble(POSITION_VOLUME);

      long posType = PositionGetInteger(POSITION_TYPE);

      MqlTradeRequest req = {}; MqlTradeResult res = {};

      req.action = TRADE_ACTION_DEAL; req.symbol = sym;

      req.volume = vol; req.deviation = MaxSlippagePts; req.magic = MagicNumber;

      req.comment = CommentPrefix + "_CLOSEALL";

      if(posType == POSITION_TYPE_BUY)

      {

         req.type = ORDER_TYPE_SELL;

         req.price = SymbolInfoDouble(sym, SYMBOL_BID);

      }

      else

      {

         req.type = ORDER_TYPE_BUY;

         req.price = SymbolInfoDouble(sym, SYMBOL_ASK);

      }

      req.type_filling = GetFillMode(sym); req.position = ticket;

      OrderSend(req, res);

   }

}



datetime GetDayStartUTC()

{

   MqlDateTime dt;

   TimeCurrent(dt);

   dt.hour = 0; dt.min = 0; dt.sec = 0;

   return StructToTime(dt);

}



bool CheckDayOfWeek()

{

   switch(PAIR_PHDow())

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

//| Broker GMT offset + PH time helpers (auto-detect broker offset)  |

//+------------------------------------------------------------------+

int PAIR_BrokerOffset()

{

   static int off = -99;

   if(off == -99)

   {

      off = (int)MathRound((TimeTradeServer() - TimeGMT()) / 3600.0);

      if(off < -14) off = -14;

      if(off > 14)  off = 14;

   }

   return off;

}



int PAIR_PHHour()

{

   MqlDateTime dt;

   TimeTradeServer(dt);

   int gmt = dt.hour - PAIR_BrokerOffset();

   if(gmt < 0) gmt += 24;

   int ph = gmt + 8;

   if(ph >= 24) ph -= 24;

   return ph;

}



int PAIR_PHDow()

{

   MqlDateTime dt;

   TimeTradeServer(dt);

   int gmt = dt.hour - PAIR_BrokerOffset();

   int dow = dt.day_of_week;

   if(gmt < 0) { dow--; if(dow < 0) dow = 6; }

   int ph = gmt + 8;

   if(ph >= 24) { dow++; if(dow > 6) dow = 0; }

   return dow;

}



bool IsInSession()

{

   if(!UseSessionFilter) return true;



   int phHour = PAIR_PHHour();



   bool inS1 = (SessionStartHour < SessionEndHour)

       ? (phHour >= SessionStartHour && phHour < SessionEndHour)

       : (phHour >= SessionStartHour || phHour < SessionEndHour);



   bool inS2 = (Session2StartHour < Session2EndHour)

       ? (phHour >= Session2StartHour && phHour < Session2EndHour)

       : (phHour >= Session2StartHour || phHour < Session2EndHour);



   return inS1 || inS2;

}



//+------------------------------------------------------------------+

//| Detect which session we're currently in                           |

//+------------------------------------------------------------------+

int GetCurrentSession()

{

   if(!UseSessionFilter) return 0;



   int phHour = PAIR_PHHour();



   bool inS1 = (SessionStartHour < SessionEndHour)

       ? (phHour >= SessionStartHour && phHour < SessionEndHour)

       : (phHour >= SessionStartHour || phHour < SessionEndHour);



   bool inS2 = (Session2StartHour < Session2EndHour)

       ? (phHour >= Session2StartHour && phHour < Session2EndHour)

       : (phHour >= Session2StartHour || phHour < Session2EndHour);



   // During overlap (20:00-00:00), prefer session 2 (NY)

   if(inS2) return 2;

   if(inS1) return 1;

   return 0;

}



//+==================================================================+

//| LOGGING                                                            |

//+==================================================================+



void LogTrade(string symbol, string type, double price, double sl, double tp, double lot,

              int confBuy, int confSell, string entryType, string comment)

{

   g_logFile = FileOpen(CommentPrefix + "_log.csv", FILE_WRITE|FILE_READ|FILE_CSV|FILE_ANSI, ",", CP_ACP);

   if(g_logFile != INVALID_HANDLE)

   {

      FileSeek(g_logFile, 0, SEEK_END);

      int d = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      FileWrite(g_logFile, TimeToString(TimeCurrent()), symbol, type,

                DoubleToString(price, d), DoubleToString(sl, d), DoubleToString(tp, d),

                DoubleToString(lot, 2), confBuy, confSell, entryType, comment,

                DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));

      FileClose(g_logFile);

   }

}

//+------------------------------------------------------------------+

