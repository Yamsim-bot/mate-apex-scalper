//+------------------------------------------------------------------+
//|                                       WeeklyVolumeProfile.mqh     |
//|             Weekly Volume Profile — CW POC/VAH/VAL computation   |
//|                                                                    |
//|  Scans the last 5 trading days of M15 bars and builds a volume   |
//|  histogram. Returns the Current Week POC, Value Area High and    |
//|  Value Area Low — the key levels used by Syndicate / Shadow Intel|
//|  style VP traders.                                                 |
//+------------------------------------------------------------------+
#ifndef WEEKLY_VOLUME_PROFILE_MQH
#define WEEKLY_VOLUME_PROFILE_MQH

//--- Weekly VP result
struct WeeklyVPResult
{
   double   poc;           // Point of Control (most volume)
   double   vah;           // Value Area High
   double   val;           // Value Area Low
   double   hvn;           // High Volume Node (2nd highest peak)
   double   weekHigh;      // Week's absolute high
   double   weekLow;       // Week's absolute low
   int      totalBars;     // Bars scanned
   bool     valid;
};

//+------------------------------------------------------------------+
//| Compute weekly volume profile from M15 bars                      |
//| bucketSize = minimum price increment per bucket                  |
//| vaPct      = value area percentage (70 = 70% of volume)          |
//| brokerGMT  = broker's GMT offset for Monday detection            |
//+------------------------------------------------------------------+
bool WeeklyVP_Compute(WeeklyVPResult &result,
                      string symbol,
                      double bucketSize,
                      double vaPct,
                      int brokerGMT)
{
   result.valid = false;
   result.poc = 0; result.vah = 0; result.val = 0;
   result.hvn = 0; result.weekHigh = 0; result.weekLow = 0;
   result.totalBars = 0;

   if(bucketSize <= 0) bucketSize = 0.50; // default for gold

   //--- Find this week's Monday 00:00 GMT
   MqlDateTime now;
   TimeTradeServer(now);
   int dayOfWeek = now.day_of_week; // 0=Sun,1=Mon,...

   //--- Go back to Monday 00:00 GMT
   int daysSinceMonday = (dayOfWeek == 0) ? 6 : (dayOfWeek - 1);
   datetime weekStartGMT = TimeTradeServer() - (datetime)(daysSinceMonday * 86400);
   //--- Normalize to 00:00 GMT
   MqlDateTime wsDt;
   TimeToStruct(weekStartGMT, wsDt);
   wsDt.hour = 0; wsDt.min = 0; wsDt.sec = 0;
   weekStartGMT = StructToTime(wsDt);

   //--- Account for broker offset
   datetime weekStartBroker = weekStartGMT + (datetime)(brokerGMT * 3600);

   //--- Load M15 bars from this week
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_M15, weekStartBroker, 500, rates);
   if(copied < 10) return false;

   //--- Find price extent
   double lo = 1e9, hi = 0;
   int n = 0;
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < weekStartBroker) continue;
      if(rates[i].low  < lo) lo = rates[i].low;
      if(rates[i].high > hi) hi = rates[i].high;
      n++;
   }
   if(n < 10 || hi <= lo) return false;

   result.weekHigh = hi;
   result.weekLow  = lo;
   result.totalBars = n;

   //--- Build histogram
   int nb = (int)MathCeil((hi - lo) / bucketSize) + 1;
   if(nb < 2 || nb > 2000) return false;

   double volA[];
   ArrayResize(volA, nb);
   ArrayInitialize(volA, 0.0);

   for(int i = 0; i < copied; i++)
   {
      if(rates[i].time < weekStartBroker) continue;

      double vol = (rates[i].tick_volume > 0) ? (double)rates[i].tick_volume : 1.0;
      int b0 = (int)MathFloor((rates[i].low  - lo) / bucketSize);
      int b1 = (int)MathFloor((rates[i].high - lo) / bucketSize);
      if(b0 < 0) b0 = 0;
      if(b1 >= nb) b1 = nb - 1;
      int span = b1 - b0 + 1;
      double per = vol / span;
      for(int b = b0; b <= b1; b++) volA[b] += per;
   }

   //--- Find POC (highest volume bucket)
   int pocIdx = 0;
   double totalVol = 0;
   for(int b = 0; b < nb; b++)
   {
      totalVol += volA[b];
      if(volA[b] > volA[pocIdx]) pocIdx = b;
   }
   if(totalVol <= 0) return false;

   //--- Find HVN (2nd highest peak — skip POC and its neighbors)
   int hvnIdx = -1;
   double hvnVol = 0;
   for(int b = 0; b < nb; b++)
   {
      if(MathAbs(b - pocIdx) <= 1) continue; // skip POC neighborhood
      if(volA[b] > hvnVol) { hvnVol = volA[b]; hvnIdx = b; }
   }

   //--- Value Area: expand from POC taking the fatter neighbour
   double vaTarget = totalVol * vaPct / 100.0;
   double vaVol = volA[pocIdx];
   int loIdx = pocIdx, hiIdx = pocIdx;
   while(vaVol < vaTarget && (loIdx > 0 || hiIdx < nb - 1))
   {
      double dn = (loIdx > 0)      ? volA[loIdx - 1] : -1;
      double up = (hiIdx < nb - 1) ? volA[hiIdx + 1] : -1;
      if(up >= dn) { hiIdx++; vaVol += volA[hiIdx]; }
      else         { loIdx--; vaVol += volA[loIdx]; }
   }

   result.poc = NormalizeDouble(lo + (pocIdx + 0.5) * bucketSize, _Digits);
   result.vah = NormalizeDouble(lo + (hiIdx + 1.0) * bucketSize, _Digits);
   result.val = NormalizeDouble(lo + loIdx * bucketSize, _Digits);
   if(hvnIdx >= 0)
      result.hvn = NormalizeDouble(lo + (hvnIdx + 0.5) * bucketSize, _Digits);
   result.valid = true;

   return true;
}

#endif
