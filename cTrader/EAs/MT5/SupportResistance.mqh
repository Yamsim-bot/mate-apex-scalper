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
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)MathMax(0, IntegerFindFirstSet(sl.timeframes)) / 6.0 * 0.5);
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
      sl.strength = MathMin(1.0, (double)sl.touches / 8.0 * 0.5 +
                                   (double)MathMax(0, IntegerFindFirstSet(sl.timeframes)) / 6.0 * 0.5);
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
