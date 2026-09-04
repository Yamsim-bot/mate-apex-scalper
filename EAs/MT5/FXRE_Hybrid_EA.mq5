//+------------------------------------------------------------------+
//|                                            FXRE_Hybrid_EA.mq5     |
//|               FXRE Hybrid v2.0 — AGV Zones + Risk Management     |
//|               XAU/USD | M5+M15 | Swing S&D + SL + %Risk          |
//+------------------------------------------------------------------+
//| v2.0 Fixes:                                                       |
//|  1. Session filter: proper London+NY windows (was 0-0 = blocked)  |
//|  2. SL tightened: 0.4x ATR (was 1.2x — too wide)                 |
//|  3. TP reduced: 1.5x zone width (was 2.0x — too aggressive)       |
//|  4. Zone clustering: ATR-based (was fixed 0.8pts)                 |
//|  5. Added partial TP + trailing stop + break-even                 |
//|  6. Fixed EMA: proper exponential (was SMA)                       |
//|  7. Auto-detect broker fill mode (was hardcoded IOC)              |
//+------------------------------------------------------------------+
#property copyright "FXRE Replication Project"
#property version   "2.10"
#property description "FXRE Hybrid v2.1: Fixed lot cap + improved trailing + breakeven after partial TP"

//--- Scalp Mode (v3.1 — IMPROVED)
input bool     ScalpMode           = true;       // Enable scalp mode (aggressive entries)
input double   Scalp_BreakoutATR   = 0.25;       // Min breakout range (xATR, was 0.20 — too tight)
input int      Scalp_BreakoutBars  = 3;          // Lookback bars for breakout (was 2 — too few)

//--- Swing S&D Parameters (REDUCED for memory efficiency)
input int      Swing_LookbackCandles = 500;   // Scan depth for swings (was 1000 — too much memory)
input int      Swing_LookbackBars    = 2;     // Bars each side for swing detection (was 3)
input double   Swing_ClusterATR      = 0.8;   // Cluster threshold (x ATR, was 0.6 — wider = fewer zones)
input int      Swing_MaxAge          = 120;   // Max zone age in M15 candles (was 240 — old zones waste memory)
input double   Swing_MinStrength     = 1.0;   // Minimum zone strength (was 0.3 — too many weak zones)

//--- Entry Confirmation
input bool     RequireZoneReject     = false;
input double   MinRejectWickATR      = 0.08;  // Min rejection wick (xATR, was 0.10)
input double   ZoneProximityATR      = 2.0;   // Max distance from zone (xATR, was 0.5)

//--- Trend Filter (optional — only trade with M15 trend)
input bool     UseTrendFilter        = false;
input int      TrendFilterMAPeriod   = 50;    // EMA for trend direction (was 200 — uses less memory)

//--- Risk Management (IMPROVED — wider SL for gold volatility)
input double   RiskPerTradePct       = 0.3;   // % risk per trade (was 0.5 — too aggressive)
input double   SL_BufferATR          = 0.5;   // SL behind zone (x ATR, was 0.3 — too tight for gold)
input double   TP_Multiplier         = 2.0;   // TP = zone_width * mult (was 1.5 — improved RR)
input double   TP_MinATR             = 0.8;   // Min TP (x ATR, was 0.6)
input double   Min_RR                = 1.5;   // Minimum reward:risk (was 1.0 — need better RR)

//--- Partial Take-Profit (IMPROVED — tighter trigger, better protection)
input bool     UsePartialTP          = true;   // Enable partial take profit
input double   PartialTP_Pct         = 40.0;   // Partial TP at X% of full TP distance (was 60% — too late)
input double   PartialClosePct       = 50.0;   // Close X% of position at partial TP
input bool     PartialAlreadyDone    = false;  // Track if partial already closed for this position

//--- Trailing Stop (IMPROVED — tighter trail, earlier start)
input bool     UseTrailing           = true;   // Trail after partial TP
input double   TrailingStart_ATR     = 0.35;   // Start trailing after X*ATR profit (was 0.6 — too late)
input double   TrailingStep_ATR      = 0.15;   // Trailing step distance (xATR, was 0.25 — too wide)
input bool     TrailAfterPartial     = true;   // Tighter trail after partial TP hit

//--- Break-Even (IMPROVED — move sooner, protect after partial)
input bool     UseBreakEven          = true;   // Move SL to breakeven
input double   BreakEven_ATR         = 0.4;    // Move SL after X*ATR profit (was 0.8 — too late)
input double   BreakEvenBuffer_Pts   = 10;     // Buffer above/below entry (points)

//--- Lot Sizing (fallback if risk% can't compute)
input double   FixedLotPer2k         = 0.01;   // Fallback lot per $2k
input double   MaxLotSize            = 0.05;   // Hard max lot size (safety cap)

//--- Safety Limits
input int      MaxPositions          = 1;      // Max positions (was 2)
input int      MaxDailyTrades        = 15;     // Max trades per day (10-15 for scalp)
input double   MaxDailyLossPct       = 2.0;    // HARD STOP: close all positions at 2% daily loss
input int      MaxTPHits             = 5;      // Pause after X TPs hit PER SESSION
input bool     ResetOnNewSession    = true;   // Reset TP counter on new session
input int      CooldownSeconds       = 300;    // Minimum seconds between trades (5 min)

//--- Trading Session (PH Time = UTC+8)
input bool     UseSessionFilter      = false;
// Window 1: London session (15:00-00:00 PH = 07:00-16:00 GMT)
input int      SessionStartHour      = 15;     // London open (PH time)
input int      SessionStartMin       = 0;
input int      SessionEndHour        = 0;      // Midnight PH (end of London)
input int      SessionEndMin         = 0;
// Window 2: NY session (20:00-05:00 PH = 12:00-21:00 GMT)
input int      Session2StartHour     = 20;     // NY open (PH time)
input int      Session2StartMin      = 0;
input int      Session2EndHour       = 5;      // NY close (PH time)
input int      Session2EndMin        = 0;
input bool     TradeMonday           = true;
input bool     TradeTuesday          = true;
input bool     TradeWednesday        = true;
input bool     TradeThursday         = true;
input bool     TradeFriday           = true;

//--- General
input ulong    MagicNumber           = 20241201;
input string   CommentPrefix         = "FXRE_HYBRID";
input int      MaxSlippagePts        = 50;
input int      MaxSpreadPts          = 800;
input bool     DebugMode             = true;

//--- Market Regime Filter (NEW — avoid ranging markets)
input bool     UseMarketRegime       = true;   // Enable market regime filter
input double   RegimeADXThreshold    = 25.0;   // ADX above this = trending
input double   RegimeADXStrong       = 40.0;   // ADX above this = strong trend
input double   RegimeATRCompression  = 0.7;    // ATR/MA below this = compression
input double   RegimeATRExpansion    = 1.3;    // ATR/MA above this = expansion
input bool     TradeWithBiasOnly     = false;  // Only trade with market direction (+DI/-DI)

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
double g_atrValue = 0;
double g_atrValueM5 = 0;
int    g_signalBarTime = 0;
datetime g_lastScanTime = 0;
ENUM_ORDER_TYPE_FILLING g_fillMode = ORDER_FILLING_IOC;
int    g_heartbeatCount = 0;
datetime g_lastTradeTime = 0;   // Cooldown timer

//--- Memory optimization: limit history bars loaded
#define MAX_HISTORY_BARS 500   // Max bars to load (reduces memory)
#define MAX_RATES_M5 20       // Max M5 bars to copy

//--- INLINE: FXRE_SwingSD.mqh ---
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

//--- END INLINE: FXRE_SwingSD.mqh ---
//--- INLINE: FXRE_SessionFilter.mqh ---
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

//--- END INLINE: FXRE_SessionFilter.mqh ---
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
//| Check available memory (prevent VirtualAlloc errors)             |
//+------------------------------------------------------------------+
bool IsMemorySafe()
{
   // Check free physical memory
   MEMORYSTATUSEX memInfo;
   memInfo.dwLength = sizeof(MEMORYSTATUSEX);
   if(GlobalMemoryStatusEx(memInfo))
   {
      DWORD freePhysMB = memInfo.ullAvailPhys / (1024 * 1024);
      if(freePhysMB < 100) // Less than 100MB free
      {
         static int lastMemWarn = 0;
         if(TimeCurrent() - lastMemWarn >= 60)
         {
            lastMemWarn = TimeCurrent();
            Print("MEMORY WARNING: Only ", freePhysMB, "MB free! Trading paused.");
         }
         return false;
      }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Auto-detect fill mode                                             |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillMode()
{
   long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if(filling & SYMBOL_FILLING_FOK)  return ORDER_FILLING_FOK;
   if(filling & SYMBOL_FILLING_IOC)  return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Dual-window session check (Window1 + Window2)                    |
//+------------------------------------------------------------------+
bool IsInHybridWindow()
{
   if(!UseSessionFilter) return true;

   int phHour = PHTimeHour();
   int phMin  = PHTimeMin();
   int nowMin = phHour * 60 + phMin;

   int w1Start = SessionStartHour * 60 + SessionStartMin;
   int w1End   = SessionEndHour   * 60 + SessionEndMin;
   int w2Start = Session2StartHour * 60 + Session2StartMin;
   int w2End   = Session2EndHour   * 60 + Session2EndMin;

   bool inW1 = (w1Start < w1End) ? (nowMin >= w1Start && nowMin < w1End)
                                  : (nowMin >= w1Start || nowMin < w1End);
   bool inW2 = (w2Start < w2End) ? (nowMin >= w2Start && nowMin < w2End)
                                  : (nowMin >= w2Start || nowMin < w2End);

   return inW1 || inW2;
}

bool HybridShouldTrade()
{
   if(!UseSessionFilter) return true;
   return IsTradingDay() && IsInHybridWindow();
}

string HybridSessionStatus()
{
   if(!UseSessionFilter) return "No filter";

   int phHour = PHTimeHour();
   int phMin  = PHTimeMin();
   int phDow  = PHTimeDayOfWeek();
   string dayNames[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
   string status = dayNames[phDow] + " " + IntegerToString(phHour) + ":" + StringFormat("%02d", phMin) + " PH | ";

   string w1 = StringFormat("W1:%02d:%02d-%02d:%02d", SessionStartHour, SessionStartMin, SessionEndHour, SessionEndMin);
   string w2 = StringFormat("W2:%02d:%02d-%02d:%02d", Session2StartHour, Session2StartMin, Session2EndHour, Session2EndMin);

   if(IsTradingDay() && IsInHybridWindow())
      status += "ACTIVE " + w1 + " " + w2;
   else if(!IsTradingDay())
      status += "NOT A TRADING DAY";
   else
      status += "OUTSIDE (" + w1 + " " + w2 + ")";

   return status;
}

//+------------------------------------------------------------------+
//| Daily safety tracking                                            |
//+------------------------------------------------------------------+
struct Hybrid_DailyStats
{
   datetime date;
   int      tradeCount;
   int      tpHits;          // Count of TPs hit in CURRENT session
   bool     tpPause;         // True after MaxTPHits reached in current session
   int      currentSession;  // 0=none, 1=session1 (London), 2=session2 (NY)
   datetime lastTPReset;     // When tpHits was last reset (for deal history filtering)
   datetime lastTPDealTime;  // Time of the last TP deal already counted
   ulong    lastTPDealTicket;// Ticket of the last TP deal already counted
   double   startingBalance;
   bool     tradingStopped;
};
Hybrid_DailyStats g_hybridDaily;
datetime g_hybridResetDay = 0;
datetime g_eaStartTime      = 0;   // Attach time — pre-bot history must not count as TP hits

//+------------------------------------------------------------------+
//| Detect which session we're currently in                           |
//+------------------------------------------------------------------+
int GetCurrentSession()
{
   if(!UseSessionFilter) return 0;

   int phHour = PHTimeHour();

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

void ResetHybridDaily()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   datetime today = StructToTime(dt);
   today = today - (today % 86400);
   if(today != g_hybridResetDay)
   {
      ZeroMemory(g_hybridDaily);
      g_hybridDaily.date = today;
      g_hybridDaily.startingBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      g_hybridDaily.tradingStopped = false;
      g_hybridDaily.lastTPReset = today; // Start counting from midnight
      g_hybridResetDay = today;
   }

   //--- Detect session change -> reset TP counter for new session
   int newSession = GetCurrentSession();
   if(newSession != g_hybridDaily.currentSession)
   {
      g_hybridDaily.currentSession = newSession;
      g_hybridDaily.tpHits = 0;
      g_hybridDaily.tpPause = false;
      g_hybridDaily.lastTPReset = TimeCurrent();
      if(newSession > 0)
         Print("SESSION CHANGE -> ", (newSession == 1 ? "LONDON" : "NY"),
               " | TP counter reset. Fresh ", MaxTPHits, " TPs available.");
   }
}

bool CanTradeHybrid()
{
   ResetHybridDaily();
   if(g_hybridDaily.tradingStopped) return false;
   if(g_hybridDaily.tradeCount >= MaxDailyTrades) return false;

   //--- Pause after MaxTPHits TPs reached in current session
   if(g_hybridDaily.tpPause)
   {
      static int lastTpPauseWarn = 0;
      if(TimeCurrent() - lastTpPauseWarn >= 300)
      {
         lastTpPauseWarn = TimeCurrent();
         string sessName = (g_hybridDaily.currentSession == 1) ? "LONDON" : "NY";
         Print("TP PAUSE: ", g_hybridDaily.tpHits, "/", MaxTPHits,
               " TPs hit in ", sessName, " session. Waiting for next session.");
      }
      return false;
   }

   double dd = (g_hybridDaily.startingBalance - AccountInfoDouble(ACCOUNT_EQUITY))
               / MathMax(g_hybridDaily.startingBalance, 1.0) * 100.0;
   if(dd >= MaxDailyLossPct)
   {
      g_hybridDaily.tradingStopped = true;
      Print("STOPPED: Daily loss limit reached. DD=", DoubleToString(dd, 2), "%");
      CloseAllTrades();
      return false;
   }

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPts) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Count open positions                                             |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Detect TPs hit today (check deal history)                        |
//+------------------------------------------------------------------+
void DetectTPHits()
{
   ResetHybridDaily();

   // Already paused for this session — nothing to detect, stop scanning
   if(g_hybridDaily.tpPause) return;

   // INCREMENTAL scan: only consider deals NEWER than the last one we
   // already counted. Without this, every tick re-scans the whole session
   // history and re-counts/re-prints the same old TP deals forever.
   datetime scanFrom = g_hybridDaily.lastTPReset;
   if(g_hybridDaily.lastTPDealTime > 0)
      scanFrom = g_hybridDaily.lastTPDealTime;

   if(!HistorySelect(scanFrom, TimeCurrent())) return;

   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      // Only count deals for our symbol and magic
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != (long)MagicNumber) continue;

      // Skip deals at or before the boundary we already counted
      datetime dealTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(dealTime <= scanFrom) continue;

   // Skip deals before this EA instance started (anti-lockout: an attach
   // must not count today's earlier TP closes and pause instantly)
   if(dealTime < g_eaStartTime) continue;

   // Check if this was a TP close (reason = DEAL_REASON_TP)
   long reason = HistoryDealGetInteger(ticket, DEAL_REASON);
   if(reason != DEAL_REASON_TP) continue;

      g_hybridDaily.tpHits++;
      g_hybridDaily.lastTPDealTime = dealTime;
      g_hybridDaily.lastTPDealTicket = ticket;

      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      string sessName = (g_hybridDaily.currentSession == 1) ? "LONDON" : "NY";
      Print("TP HIT #", g_hybridDaily.tpHits, "/", MaxTPHits,
            " (", sessName, " session)",
            " | Profit: $", DoubleToString(profit, 2),
            " | ", TimeToString(dealTime));

      if(g_hybridDaily.tpHits >= MaxTPHits)
      {
         g_hybridDaily.tpPause = true;
         Print("TP PAUSE [", sessName, "]: ", g_hybridDaily.tpHits,
               " TPs hit. No new entries (open positions still managed).");
      }
   }
}
double CalcATR(int period, ENUM_TIMEFRAMES tf)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, period + 2, rates);
   if(copied < period + 1)
   {
      Print("CalcATR: Not enough bars copied (", copied, "/", period + 2, ")");
      return 0;
   }
   double sum = 0;
   for(int i = 0; i < period; i++)
   {
      double tr = MathMax(rates[i].high - rates[i].low,
         MathMax(MathAbs(rates[i].high - rates[i+1].close),
                 MathAbs(rates[i].low - rates[i+1].close)));
      sum += tr;
   }
   double atr = sum / period;
   //--- Safety floor: minimum 1.0 pt ATR to prevent division by zero
   if(atr < 1.0)
   {
      Print("CalcATR: ATR too low (", DoubleToString(atr, 2), "), using floor 1.0");
      return 1.0;
   }
   return atr;
}

//+------------------------------------------------------------------+
//| Calculate proper EMA (fix #6 — was SMA)                          |
//+------------------------------------------------------------------+
double CalcEMA(ENUM_TIMEFRAMES tf, int period)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 0, period + 5, rates);
   if(copied < period + 2) return 0;

   // Start with SMA of first 'period' bars
   double sma = 0;
   for(int i = 1; i <= period; i++)
      sma += rates[i].close;
   sma /= period;

   // Apply EMA multiplier
   double k = 2.0 / (period + 1.0);
   double ema = sma;
   for(int i = period; i >= 1; i--)
      ema = rates[i].close * k + ema * (1.0 - k);

   return ema;
}

//+------------------------------------------------------------------+
//| Calculate lot size from risk % + SL distance — CONSERVATIVE       |
//+------------------------------------------------------------------+
double CalcRiskLot(double slDistancePts)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   
   if(slDistancePts <= 0)
   {
      //--- Fallback: fixed lot based on balance
      double lot = MathMin(balance / 50000.0, 0.01);  // Very conservative fallback
      lot = MathMax(lot, minVol);
      if(step > 0) lot = MathFloor(lot / step) * step;
      return lot;
   }

   //--- Risk-based calculation
   double riskAmount = balance * (RiskPerTradePct / 100.0);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0 || tickSize <= 0) return minVol;

   double lot = riskAmount / (slDistancePts * tickValue);
   
   //--- Notional cap: $15k exposure per $10k balance (was $30k — too aggressive)
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(price > 0)
   {
      double maxVol = (balance / 10000.0) * 15000.0 / price;
      if(step > 0) maxVol = MathFloor(maxVol / step) * step;
      lot = MathMin(lot, maxVol);
   }

   //--- Balance-based cap: max 0.01 per $10k (extreme safety)
   double balanceCap = balance / 10000.0 * 0.01;
   lot = MathMin(lot, balanceCap);

   //--- Hard cap: MaxLotSize from inputs (SAFETY — never exceed)
   lot = MathMin(lot, MaxLotSize);

   //--- Normalize
   lot = MathMin(lot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   lot = MathMax(lot, minVol);
   if(step > 0) lot = MathFloor(lot / step) * step;
   
   return lot;
}

//+------------------------------------------------------------------+
//| Send market order (auto fill mode) — WITH SAFETY CAP             |
//+------------------------------------------------------------------+
bool OpenOrderHybrid(int type, double volume, double price,
                     double sl, double tp, string comment)
{
   //--- FINAL SAFETY CAP: Never exceed MaxLotSize under any circumstances
   double maxVol = MathMin(MaxLotSize, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   volume = MathMin(volume, maxVol);
   volume = MathMax(volume, minVol);
   if(step > 0) volume = MathFloor(volume / step) * step;
   
   //--- Extra safety: if balance < $5000, cap at 0.02
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance < 5000)
      volume = MathMin(volume, 0.02);
   else if(balance < 10000)
      volume = MathMin(volume, 0.03);
   
   if(volume < minVol)
   {
      Print("ORDER BLOCKED: Volume ", volume, " below minimum ", minVol);
      return false;
   }

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   request.action    = TRADE_ACTION_DEAL;
   request.symbol    = _Symbol;
   request.volume    = volume;
   request.type      = (ENUM_ORDER_TYPE)type;
   request.price     = price;
   request.deviation = MaxSlippagePts;
   request.sl        = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.tp        = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
   request.comment   = comment;
   request.magic     = MagicNumber;
   request.type_filling = g_fillMode;

   if(OrderSend(request, result))
   {
      if(result.retcode == TRADE_RETCODE_DONE)
      {
         Print("ORDER: ", (type == ORDER_TYPE_BUY ? "BUY" : "SELL"),
               " Lot=", volume, " @ ", price,
               " SL=", DoubleToString(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               " TP=", DoubleToString(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
               " MaxLot=", MaxLotSize, " Bal=", DoubleToString(balance, 0));
         return true;
      }
      else
      {
         Print("ORDER FAILED: retcode=", result.retcode, " comment=", result.comment);
      }
   }
   return false;
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
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      int type = (int)PositionGetInteger(POSITION_TYPE);
      req.action = TRADE_ACTION_DEAL;
      req.position = ticket;
      req.symbol = _Symbol;
      req.volume = PositionGetDouble(POSITION_VOLUME);
      req.deviation = MaxSlippagePts;
      req.type_filling = g_fillMode;
      if(type == POSITION_TYPE_BUY)
      { req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); req.type = ORDER_TYPE_SELL; }
      else
      { req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); req.type = ORDER_TYPE_BUY; }
      if(OrderSend(req, res)) closed++;
   }
   return closed;
}

//+------------------------------------------------------------------+
//| Close partial position                                            |
//+------------------------------------------------------------------+
bool ClosePartial(ulong ticket, double closeVol)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int type = (int)PositionGetInteger(POSITION_TYPE);
   req.action = TRADE_ACTION_DEAL;
   req.position = ticket;
   req.symbol = _Symbol;
   req.volume = NormalizeDouble(closeVol, 2);
   req.deviation = MaxSlippagePts;
   req.type_filling = g_fillMode;
   if(type == POSITION_TYPE_BUY)
   { req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID); req.type = ORDER_TYPE_SELL; }
   else
   { req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK); req.type = ORDER_TYPE_BUY; }
   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Modify SL/TP                                                     |
//+------------------------------------------------------------------+
bool ModifySL(ulong ticket, double newSL)
{
   if(!PositionSelectByTicket(ticket)) return false;

   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   req.action = TRADE_ACTION_SLTP;
   req.position = ticket;
   req.symbol = _Symbol;
   req.sl = NormalizeDouble(newSL, digits);
   req.tp = PositionGetDouble(POSITION_TP);
   return OrderSend(req, res);
}

//+------------------------------------------------------------------+
//| Manage open positions — partial TP, trailing, break-even         |
//| IMPROVED: Better profit protection after partial TP              |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!UsePartialTP && !UseTrailing && !UseBreakEven) return;

   double atr = g_atrValue;
   if(atr <= 0) return;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != (long)MagicNumber) continue;

      double entry     = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double tp        = PositionGetDouble(POSITION_TP);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double minVol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      long   type      = PositionGetInteger(POSITION_TYPE);
      double currentPrice = (type == POSITION_TYPE_BUY) ?
                            SymbolInfoDouble(_Symbol, SYMBOL_BID) :
                            SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      //--- Calculate current profit distance in ATR
      double profitDistATR = 0;
      if(type == POSITION_TYPE_BUY)
         profitDistATR = (currentPrice - entry) / atr;
      else
         profitDistATR = (entry - currentPrice) / atr;

      //--- Check if we already did partial close (by comparing current volume to original)
      //    We use a simple heuristic: if SL is already at breakeven or better, partial was likely done
      bool slAtOrAboveEntry = false;
      if(type == POSITION_TYPE_BUY && sl >= entry)
         slAtOrAboveEntry = true;
      else if(type == POSITION_TYPE_SELL && sl <= entry && sl > 0)
         slAtOrAboveEntry = true;

      //--- IMPROVED Break-Even: Move to BE sooner, with buffer
      if(UseBreakEven)
      {
         double beDist = BreakEven_ATR * atr;
         double beBuffer = BreakEvenBuffer_Pts * point;

         if(type == POSITION_TYPE_BUY)
         {
            // Move to breakeven + buffer once profit reaches BreakEven_ATR
            if(currentPrice >= entry + beDist && sl < entry + beBuffer)
            {
               double newSL = NormalizeDouble(entry + beBuffer, digits);
               if(newSL > sl)
               {
                  ModifySL(ticket, newSL);
                  Print("BREAK-EVEN: BUY SL moved to ", newSL, " (entry+", BreakEvenBuffer_Pts, " pts)");
               }
            }
         }
         else  // SELL
         {
            // Move to breakeven - buffer once profit reaches BreakEven_ATR
            if(currentPrice <= entry - beDist && (sl > entry - beBuffer || sl == 0))
            {
               double newSL = NormalizeDouble(entry - beBuffer, digits);
               if(newSL < sl || sl == 0)
               {
                  ModifySL(ticket, newSL);
                  Print("BREAK-EVEN: SELL SL moved to ", newSL, " (entry-", BreakEvenBuffer_Pts, " pts)");
               }
            }
         }
      }

      //--- IMPROVED Partial Take-Profit: Trigger earlier, move SL to BE immediately
      if(UsePartialTP && volume > minVol * 1.5)  // Only if position is large enough
      {
         double tpDist = MathAbs(tp - entry);
         double partialLevel = (type == POSITION_TYPE_BUY) ?
                               entry + tpDist * (PartialTP_Pct / 100.0) :
                               entry - tpDist * (PartialTP_Pct / 100.0);

         bool partialHit = false;
         if(type == POSITION_TYPE_BUY && currentPrice >= partialLevel)
            partialHit = true;
         else if(type == POSITION_TYPE_SELL && currentPrice <= partialLevel)
            partialHit = true;

         if(partialHit && !slAtOrAboveEntry)  // Only if we haven't already moved SL to BE
         {
            double closeVol = NormalizeDouble(volume * (PartialClosePct / 100.0), 2);
            closeVol = MathMax(closeVol, minVol);
            if(closeVol < volume)
            {
               if(ClosePartial(ticket, closeVol))
               {
                  Print("PARTIAL TP: Closed ", closeVol, " lots at ", currentPrice);
                  // IMMEDIATELY move SL to breakeven after partial
                  double beSL = 0;
                  if(type == POSITION_TYPE_BUY)
                     beSL = NormalizeDouble(entry + BreakEvenBuffer_Pts * point, digits);
                  else
                     beSL = NormalizeDouble(entry - BreakEvenBuffer_Pts * point, digits);
                  if(beSL > 0)
                  {
                     ModifySL(ticket, beSL);
                     Print("PARTIAL TP: SL moved to breakeven ", beSL, " after partial close");
                  }
               }
            }
         }
      }

      //--- IMPROVED Trailing Stop: Tighter trail, especially after partial TP
      if(UseTrailing)
      {
         double trailStart, trailStep;

         //--- Use tighter trail after partial TP or SL at BE
         if(slAtOrAboveEntry && TrailAfterPartial)
         {
            // Tighter trail: 0.2 ATR step after partial TP
            trailStart = 0.2 * atr;   // Start trailing immediately after BE
            trailStep  = 0.1 * atr;   // Very tight trail (was 0.15)
         }
         else
         {
            // Normal trail settings
            trailStart = TrailingStart_ATR * atr;
            trailStep  = TrailingStep_ATR * atr;
         }

         if(type == POSITION_TYPE_BUY)
         {
            if(profitDistATR >= trailStart / atr)
            {
               double newSL = NormalizeDouble(currentPrice - trailStep, digits);
               if(newSL > sl + point)
               {
                  ModifySL(ticket, newSL);
                  if(DebugMode && newSL > entry)
                     Print("TRAIL: BUY SL moved to ", newSL, " (profit=", DoubleToString(profitDistATR, 2), "xATR)");
               }
            }
         }
         else  // SELL
         {
            if(profitDistATR >= trailStart / atr)
            {
               double newSL = NormalizeDouble(currentPrice + trailStep, digits);
               if(newSL < sl - point || sl == 0)
               {
                  ModifySL(ticket, newSL);
                  if(DebugMode && newSL < entry)
                     Print("TRAIL: SELL SL moved to ", newSL, " (profit=", DoubleToString(profitDistATR, 2), "xATR)");
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_eaStartTime = TimeCurrent();
   g_fillMode = GetFillMode();
   string fillStr = (g_fillMode == ORDER_FILLING_FOK) ? "FOK" :
                    (g_fillMode == ORDER_FILLING_IOC) ? "IOC" : "RETURN";

   Print("================================================================");
   Print("FXRE Hybrid EA v2.10 (Fixed) initialized");
   Print("  Time: ", TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS));
   Print("  Account: ", AccountInfoInteger(ACCOUNT_LOGIN), " @ ", AccountInfoString(ACCOUNT_SERVER));
   Print("  Balance: $", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2));
   Print("  Symbol=", _Symbol, " TF=", EnumToString(Period()));
   Print("  Fill mode: ", fillStr);
   Print("  SL: ", SL_BufferATR, "x ATR | TP: ", TP_Multiplier, "x zone | RR>=", Min_RR);
   Print("  Risk: ", RiskPerTradePct, "% | Max DD: ", MaxDailyLossPct, "% | MaxLot: ", MaxLotSize);
   Print("  Partial TP: ", UsePartialTP ? "ON" : "OFF", " @ ", PartialTP_Pct, "% | Close: ", PartialClosePct, "%");
   Print("  Trailing: ", UseTrailing ? "ON" : "OFF", " Start=", TrailingStart_ATR, "xATR Step=", TrailingStep_ATR, "xATR");
   Print("  Break-Even: ", UseBreakEven ? "ON" : "OFF", " @ ", BreakEven_ATR, "xATR + ", BreakEvenBuffer_Pts, " pts buffer");
   Print("  Max positions: ", MaxPositions, " | Max daily: ", MaxDailyTrades, " | TP Pause: ", MaxTPHits, " per session");
   Print("  Cluster: ", Swing_ClusterATR, "x ATR | MinStr: ", Swing_MinStrength);
   Print("  Market Regime: ", UseMarketRegime ? "ON" : "OFF", " | ADX Threshold: ", RegimeADXThreshold, " | Bias Only: ", TradeWithBiasOnly ? "YES" : "NO");

   // Check available M15 bars
   int m15bars = Bars(_Symbol, PERIOD_M15);
   int m5bars = Bars(_Symbol, PERIOD_M5);
   Print("  Available: M15=", m15bars, " M5=", m5bars, " bars");

   // Try zone scan
   int zones = DetectSwingZones(PERIOD_M15, Swing_LookbackCandles, Swing_LookbackBars,
                                Swing_ClusterATR * g_atrValue, Swing_MaxAge, Swing_MinStrength);
   Print("  Initial zone scan: ", zones, " zones (", g_swingBullishTotal, "D/", g_swingBearishTotal, "S)");
   if(zones > 0) PrintSwingZones();

   ResetHybridDaily();
   Print("  Session: ", HybridSessionStatus());
   Print("================================================================");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Comment("");
   Print("Hybrid EA v2.1 deinit. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Check entry signals — Swing S&D zones + M5 rejection             |
//+------------------------------------------------------------------+
void CheckHybridEntry()
{
   //--- MARKET REGIME FILTER: Skip if market is ranging
   if(UseMarketRegime)
   {
      g_marketRegime.SetThresholds(RegimeADXThreshold, RegimeADXStrong, RegimeATRCompression, RegimeATRExpansion);
      g_marketRegime.DetectRegime(PERIOD_M15);
      
      if(!g_marketRegime.IsTradeable())
      {
         static int lastRegimeWarn = 0;
         if(TimeCurrent() - lastRegimeWarn >= 300)
         {
            lastRegimeWarn = TimeCurrent();
            Print("REGIME BLOCK: ", g_marketRegime.GetRegimeName(),
                  " | ADX=", DoubleToString(g_marketRegime.GetADX(), 1),
                  " | ATR Ratio=", DoubleToString(g_marketRegime.GetATRRatio(), 2),
                  " | NOT TRADEABLE");
         }
         return;
      }
      
      if(DebugMode)
      {
         static int lastRegimeInfo = 0;
         if(TimeCurrent() - lastRegimeInfo >= 60)
         {
            lastRegimeInfo = TimeCurrent();
            Print("REGIME OK: ", g_marketRegime.GetRegimeName(),
                  " | ADX=", DoubleToString(g_marketRegime.GetADX(), 1),
                  " | +DI=", DoubleToString(g_marketRegime.GetPlusDI(), 1),
                  " | -DI=", DoubleToString(g_marketRegime.GetMinusDI(), 1),
                  " | ATR Ratio=", DoubleToString(g_marketRegime.GetATRRatio(), 2));
         }
      }
   }
   
   MqlRates ratesM5[];
   ArraySetAsSeries(ratesM5, true);
   if(CopyRates(_Symbol, PERIOD_M5, 0, MAX_RATES_M5, ratesM5) < 5) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   // ═══════════════════════════════════════════
   // Scalp Mode: momentum breakout (v3.0)
   // ═══════════════════════════════════════════
   if(ScalpMode)
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double range0 = ratesM5[0].high - ratesM5[0].low;

      //--- Momentum BUY: break above prev bar high with range
      if(range0 >= Scalp_BreakoutATR * g_atrValueM5
         && ratesM5[0].close > ratesM5[0].open
         && ratesM5[0].high > ratesM5[1].high
         && g_signalBarTime != (int)ratesM5[0].time)
      {
         double sl = NormalizeDouble(ratesM5[0].low - SL_BufferATR * g_atrValueM5, digits);
         if(ratesM5[0].low < sl) sl = ratesM5[0].low;
         double slDistPts = (ask - sl) / _Point;
         double minStopPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         if(slDistPts < minStopPts) { sl = NormalizeDouble(ask - minStopPts * _Point, digits); slDistPts = minStopPts; }
         if(slDistPts >= 0.5 * g_atrValueM5 / _Point)
         {
            double tp = NormalizeDouble(ask + slDistPts * 1.5 * _Point, digits);
      double lot = CalcRiskLot(slDistPts);
      lot = MathMin(lot, MaxLotSize);  //--- Safety cap
      if(lot >= 0.01 && OpenOrderHybrid(ORDER_TYPE_BUY, lot, ask, sl, tp,
         CommentPrefix + "_SCALP_BUY"))
      {
         g_signalBarTime = (int)ratesM5[0].time;
         g_lastTradeTime = TimeCurrent();
         g_hybridDaily.tradeCount++;
         Print("SCALP BUY: ", _Symbol, " range=", DoubleToString(range0 / g_atrValueM5, 2), "xATR", " lot=", lot);
         return;
      }
         }
      }

      //--- Momentum SELL: break below prev bar low with range
      if(range0 >= Scalp_BreakoutATR * g_atrValueM5
         && ratesM5[0].close < ratesM5[0].open
         && ratesM5[0].low < ratesM5[1].low
         && g_signalBarTime != (int)ratesM5[0].time)
      {
         double sl = NormalizeDouble(ratesM5[0].high + SL_BufferATR * g_atrValueM5, digits);
         if(ratesM5[0].high > sl) sl = ratesM5[0].high;
         double slDistPts = (sl - bid) / _Point;
         double minStopPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         if(slDistPts < minStopPts) { sl = NormalizeDouble(bid + minStopPts * _Point, digits); slDistPts = minStopPts; }
         if(slDistPts >= 0.5 * g_atrValueM5 / _Point)
         {
            double tp = NormalizeDouble(bid - slDistPts * 1.5 * _Point, digits);
      double lot = CalcRiskLot(slDistPts);
      lot = MathMin(lot, MaxLotSize);  //--- Safety cap
      if(lot >= 0.01 && OpenOrderHybrid(ORDER_TYPE_SELL, lot, bid, sl, tp,
         CommentPrefix + "_SCALP_SELL"))
      {
         g_signalBarTime = (int)ratesM5[0].time;
         g_lastTradeTime = TimeCurrent();
         g_hybridDaily.tradeCount++;
         Print("SCALP SELL: ", _Symbol, " range=", DoubleToString(range0 / g_atrValueM5, 2), "xATR", " lot=", lot);
         return;
      }
         }
      }

      //--- In scalp mode, don't fall through to S&D zone logic
      return;
   }

   //--- Standard mode: S&D zone entry (disabled in scalp mode)
   double clusterPts = Swing_ClusterATR * g_atrValue;
   int zoneCount = DetectSwingZones(PERIOD_M15,
                      Swing_LookbackCandles,
                      Swing_LookbackBars,
                      clusterPts,
                      Swing_MaxAge,
                      Swing_MinStrength);

   if(zoneCount == 0)
   {
      static int lastZoneWarn = 0;
      if(TimeCurrent() - lastZoneWarn >= 300)
      {
         lastZoneWarn = TimeCurrent();
         Print("DEBUG: No swing zones! M15 bars=", Bars(_Symbol, PERIOD_M15),
               " cluster=", DoubleToString(clusterPts, 1), "pts (", Swing_ClusterATR, "x ATR)",
               " maxAge=", Swing_MaxAge, " minStr=", Swing_MinStrength);
      }
      return;
   }

   //--- Check M15 trend (fix #6: proper EMA)
   bool trendBull = true, trendBear = true;
   if(UseTrendFilter)
   {
      double ema200 = CalcEMA(PERIOD_M15, TrendFilterMAPeriod);
      if(ema200 > 0)
      {
         trendBull = (ratesM5[0].close > ema200);
         trendBear = (ratesM5[0].close < ema200);
      }
   }

   //--- Find nearest zones
   SwingSDZone nearDemand, nearSupply;
   bool hasDemand = GetNearestDemandZone(bid, ZoneProximityATR, g_atrValue, nearDemand);
   bool hasSupply = GetNearestSupplyZone(bid, ZoneProximityATR, g_atrValue, nearSupply);

   //--- Log zone proximity status periodically
   if(!hasDemand && !hasSupply)
   {
      static int lastZoneProxWarn = 0;
      if(TimeCurrent() - lastZoneProxWarn >= 300)
      {
         lastZoneProxWarn = TimeCurrent();
         Print("DEBUG: No zones near price. bid=", DoubleToString(bid, 2),
               " zones: D=", g_swingBullishTotal, " S=", g_swingBearishTotal,
               " proximity=", ZoneProximityATR, "x ATR=", DoubleToString(ZoneProximityATR * g_atrValue, 1));
      }
   }

   //--- M5 rejection candle check
   bool rejectionBull = false, rejectionBear = false;

   if(!RequireZoneReject)
   {
      rejectionBull = true;
      rejectionBear = true;
   }
   else
   {
      double minWick = MinRejectWickATR * g_atrValueM5;

      for(int c = 1; c <= 3; c++)
      {
         double lowerWick = MathMin(ratesM5[c].close, ratesM5[c].open) - ratesM5[c].low;
         double upperWick = ratesM5[c].high - MathMax(ratesM5[c].close, ratesM5[c].open);
         double body = MathAbs(ratesM5[c].close - ratesM5[c].open);

         if(lowerWick >= minWick && lowerWick >= body * 0.2 &&
            ratesM5[c].close > ratesM5[c].open)
            rejectionBull = true;

         if(upperWick >= minWick && upperWick >= body * 0.2 &&
            ratesM5[c].close < ratesM5[c].open)
            rejectionBear = true;
      }
   }

   //--- Entry signals
   bool tradeBuy = hasDemand && (rejectionBull || trendBull) &&
                   g_signalBarTime != (int)ratesM5[0].time;
   bool tradeSell = hasSupply && (rejectionBear || trendBear) &&
                    g_signalBarTime != (int)ratesM5[0].time;

   //--- MARKET BIAS FILTER: Only trade with market direction if enabled
   if(TradeWithBiasOnly && UseMarketRegime)
   {
      int bias = GetMarketBias(PERIOD_M15);
      if(bias == 1) tradeSell = false;   // Market trending UP — only BUY
      if(bias == -1) tradeBuy = false;   // Market trending DOWN — only SELL
      
      if(bias != 0 && DebugMode)
      {
         static int lastBiasWarn = 0;
         if(TimeCurrent() - lastBiasWarn >= 300)
         {
            lastBiasWarn = TimeCurrent();
            Print("BIAS FILTER: Market=", (bias==1 ? "UP" : "DOWN"),
                  " | TradeBuy=", tradeBuy, " TradeSell=", tradeSell);
         }
      }
   }
   
   // Conflict resolution
   if(hasDemand && hasSupply)
   {
      if(trendBull) tradeSell = false;
      if(trendBear) tradeBuy = false;
   }

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   //--- BUY SIGNAL
   if(tradeBuy)
   {
      double zoneLow   = nearDemand.priceLow;
      double zoneHigh  = nearDemand.priceHigh;
      double zoneWidth = MathMax(zoneHigh - zoneLow, g_atrValue * 0.15);

      double sl = NormalizeDouble(zoneLow - SL_BufferATR * g_atrValue, digits);
      double tp = NormalizeDouble(bid + MathMax(zoneWidth * TP_Multiplier, g_atrValue * TP_MinATR), digits);

      double slDistPts = (bid - sl) / _Point;
      // Clamp SL to broker minimum stop distance so the filled SL matches the plan
      double minStopPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slDistPts < minStopPts)
      {
         sl = NormalizeDouble(bid - minStopPts * _Point, digits);
         slDistPts = minStopPts;
      }
      double slDistATR = (bid - sl) / g_atrValue;
      double tpDist = tp - bid;
      double rr = (slDistPts > 0) ? tpDist / slDistPts : 0;

      // R:R — stretch TP so reward:risk >= Min_RR always holds (kills the
      // "RR=0.75 rejected for hours" deadlock WITHOUT weakening Min_RR)
      if(rr < Min_RR)
      {
         tp = NormalizeDouble(bid + slDistPts * _Point * Min_RR, digits);
         tpDist = tp - bid;
         rr = Min_RR;
         if(DebugMode) Print("FXRE BUY ", _Symbol, ": RR=", DoubleToString(rr, 2),
               " < Min_RR=", DoubleToString(Min_RR, 1), " - stretching TP");
      }

      double lot = CalcRiskLot(slDistPts);
      lot = MathMin(lot, MaxLotSize);  //--- Safety cap

      if(OpenOrderHybrid(ORDER_TYPE_BUY, lot, ask, sl, tp,
         CommentPrefix + "_BUY_Z" + DoubleToString(nearDemand.strength, 1)))
      {
         g_signalBarTime = (int)ratesM5[0].time;
         g_lastTradeTime = TimeCurrent();
         g_hybridDaily.tradeCount++;
         Print("BUY CONFIRMED: ", _Symbol, " SL=", DoubleToString(slDistATR, 2), "xATR",
               " RR=", DoubleToString(rr, 2), " Lot=", lot, " Zones: D=", g_swingBullishTotal, " S=", g_swingBearishTotal);
      }
   }
   else if(tradeSell)
   {
      double zoneHigh  = nearSupply.priceHigh;
      double zoneWidth = MathMax(nearSupply.priceHigh - nearSupply.priceLow, g_atrValue * 0.15);

      double sl = NormalizeDouble(zoneHigh + SL_BufferATR * g_atrValue, digits);
      double tp = NormalizeDouble(bid - MathMax(zoneWidth * TP_Multiplier, g_atrValue * TP_MinATR), digits);

      double slDistPts = (sl - bid) / _Point;
      // Clamp SL to broker minimum stop distance so the filled SL matches the plan
      double minStopPts = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      if(slDistPts < minStopPts)
      {
         sl = NormalizeDouble(bid + minStopPts * _Point, digits);
         slDistPts = minStopPts;
      }
      double slDistATR = (sl - bid) / g_atrValue;
      double tpDist = bid - tp;
      double rr = (slDistPts > 0) ? tpDist / slDistPts : 0;

      // R:R — stretch TP so reward:risk >= Min_RR always holds
      if(rr < Min_RR)
      {
         tp = NormalizeDouble(bid - slDistPts * _Point * Min_RR, digits);
         tpDist = bid - tp;
         rr = Min_RR;
         if(DebugMode) Print("FXRE SELL ", _Symbol, ": RR=", DoubleToString(rr, 2),
               " < Min_RR=", DoubleToString(Min_RR, 1), " - stretching TP");
      }

      double lot = CalcRiskLot(slDistPts);
      lot = MathMin(lot, MaxLotSize);  //--- Safety cap

      if(OpenOrderHybrid(ORDER_TYPE_SELL, lot, bid, sl, tp,
         CommentPrefix + "_SELL_Z" + DoubleToString(nearSupply.strength, 1)))
      {
         g_signalBarTime = (int)ratesM5[0].time;
         g_lastTradeTime = TimeCurrent();
         g_hybridDaily.tradeCount++;
         Print("SELL CONFIRMED: ", _Symbol, " SL=", DoubleToString(slDistATR, 2), "xATR",
               " RR=", DoubleToString(rr, 2), " Lot=", lot, " Zones: D=", g_swingBullishTotal, " S=", g_swingBearishTotal);
      }
   }
   else if(DebugMode && (hasDemand || hasSupply))
   {
      static int lastSigWarn = 0;
      if(TimeCurrent() - lastSigWarn >= 300)
      {
         lastSigWarn = TimeCurrent();
         Print("DEBUG: Missed signal. D=", hasDemand, " S=", hasSupply,
               " rBull=", rejectionBull, " rBear=", rejectionBear,
               " tBull=", trendBull, " tBear=", trendBear);
      }
   }
}

//+------------------------------------------------------------------+
//| Chart comment                                                    |
//+------------------------------------------------------------------+
string RepeatStr(string s, int n)
{
   string r = "";
   for(int i = 0; i < n; i++) r += s;
   return r;
}

void UpdateComment()
{
   string sep = "\n" + RepeatStr("-", 30) + "\n";
   string info = "=== FXRE Hybrid EA v2.0 ===" + sep;
   info += "Balance: $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2);
   info += " | Equity: $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
   info += " | Spread: " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD)) + "\n";

   if(g_hybridDaily.startingBalance > 0)
   {
      double dd = (g_hybridDaily.startingBalance - AccountInfoDouble(ACCOUNT_EQUITY))
                   / g_hybridDaily.startingBalance * 100.0;
      info += "Today: " + IntegerToString(g_hybridDaily.tradeCount) + "/" + IntegerToString(MaxDailyTrades);
      string sessName = (g_hybridDaily.currentSession == 1) ? "LON" : (g_hybridDaily.currentSession == 2) ? "NY" : "---";
      info += " | TP: " + IntegerToString(g_hybridDaily.tpHits) + "/" + IntegerToString(MaxTPHits) + " [" + sessName + "]";
      info += " | DD: " + DoubleToString(dd, 2) + "% (limit: " + DoubleToString(MaxDailyLossPct, 1) + "%)" + "\n";
   }

   info += "Open: " + IntegerToString(CountOpenPositions()) + "/" + IntegerToString(MaxPositions) + sep;
   info += "ATR(14): M15=" + DoubleToString(g_atrValue, 1) + " M5=" + DoubleToString(g_atrValueM5, 1) + "\n";
   info += "Session: " + HybridSessionStatus() + "\n";
   info += "SL: " + DoubleToString(SL_BufferATR, 1) + "xATR | TP: " + DoubleToString(TP_Multiplier, 1) + "x zone | RR>=" + DoubleToString(Min_RR, 1) + "\n";

   if(g_swingBullishTotal > 0 || g_swingBearishTotal > 0)
      info += "Demand Z: " + IntegerToString(g_swingBullishTotal) +
              " | Supply Z: " + IntegerToString(g_swingBearishTotal) + "\n";

   if(g_hybridDaily.tradingStopped)
      info += "TRADING STOPPED (daily loss limit)\n";
   
   //--- Show regime status
   if(UseMarketRegime)
   {
      info += "Regime: " + g_marketRegime.GetRegimeName();
      info += " (ADX=" + DoubleToString(g_marketRegime.GetADX(), 1) + ")";
      info += " | Tradeable: " + (g_marketRegime.IsTradeable() ? "YES" : "NO") + "\n";
   }

   Comment(info);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Memory safety check (prevent VirtualAlloc errors)
   if(!IsMemorySafe())
   {
      UpdateComment();
      return;
   }
   
   ResetHybridDaily();

   //--- Detect TPs hit today
   DetectTPHits();

   //--- Emergency stop check first
   if(g_hybridDaily.tradingStopped)
   {
      CloseAllTrades();
      UpdateComment();
      return;
   }

   //--- Manage open positions (partial TP, trailing, break-even)
   ManageOpenPositions();

   //--- TP pause: no new entries this session, but open positions stay managed
   //    (trailing/break-even already ran above — do NOT force-close winners)
   if(g_hybridDaily.tpPause)
   { UpdateComment(); return; }

   //--- Position limit check
   int openPos = CountOpenPositions();
   if(openPos >= MaxPositions)
   { UpdateComment(); return; }

   //--- Cooldown: minimum time between trades
   if(g_lastTradeTime > 0 && (TimeCurrent() - g_lastTradeTime) < CooldownSeconds)
   {
      static datetime lastCooldownWarn = 0;
      if(TimeCurrent() - lastCooldownWarn >= 60)
      {
         lastCooldownWarn = TimeCurrent();
         Print("COOLDOWN: Waiting ", CooldownSeconds - (int)(TimeCurrent() - g_lastTradeTime), "s");
      }
      UpdateComment(); return;
   }

   //--- Can we trade?
   bool canTrade = CanTradeHybrid();
   bool inSession = HybridShouldTrade();
   if(!canTrade || !inSession)
   {
      static datetime lastDebugTime = 0;
      if(TimeCurrent() - lastDebugTime >= 60)
      {
         lastDebugTime = TimeCurrent();
         Print("DEBUG: canTrade=", canTrade, " inSession=", inSession,
               " openPos=", openPos, " spread=", (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD),
               " session=", HybridSessionStatus(),
               " dd=", DoubleToString((g_hybridDaily.startingBalance - AccountInfoDouble(ACCOUNT_EQUITY))
                                      / MathMax(g_hybridDaily.startingBalance, 1.0) * 100.0, 1), "%");
      }
      UpdateComment();
      return;
   }

   //--- Update ATR
   g_atrValue = CalcATR(14, PERIOD_M15);
   if(g_atrValue <= 0)
   {
      static bool atr15Warned = false;
      if(!atr15Warned) { Print("DEBUG: ATR M15 = 0"); atr15Warned = true; }
      UpdateComment();
      return;
   }

   g_atrValueM5 = CalcATR(14, PERIOD_M5);
   if(g_atrValueM5 <= 0)
   {
      static bool atr5Warned = false;
      if(!atr5Warned) { Print("DEBUG: ATR M5 = 0"); atr5Warned = true; }
      UpdateComment();
      return;
   }

   //--- Heartbeat every ~5 min
   g_heartbeatCount++;
   if(g_heartbeatCount >= 60)
   {
      g_heartbeatCount = 0;
      Print("HEARTBEAT | Bal=$", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2),
            " Eq=$", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2),
            " Pos=", openPos, " Trades=", g_hybridDaily.tradeCount,
            " Zones: D=", g_swingBullishTotal, " S=", g_swingBearishTotal,
            " ATR: M15=", DoubleToString(g_atrValue,1), " M5=", DoubleToString(g_atrValueM5,1),
            " Cooldown: ", CooldownSeconds, "s | MaxLot: ", MaxLotSize);
   }

   //--- Check entry signals
   CheckHybridEntry();

   UpdateComment();
}
//+------------------------------------------------------------------+
