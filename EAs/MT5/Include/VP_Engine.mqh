//+------------------------------------------------------------------+
//|                                                VP_Engine.mqh      |
//|                          Volume Profile Engine for MQL5            |
//|                          Computes POC, VAH, VAL, HVN, LVN         |
//+------------------------------------------------------------------+
#ifndef VP_ENGINE_MQH
#define VP_ENGINE_MQH

// Math/Stat/Normal.mqh not needed

//--- Volume Profile structure
struct VolumeProfileResult
{
   double poc;              // Point of Control (highest volume price)
   double vah;              // Value Area High (70% boundary)
   double val;              // Value Area Low (70% boundary)
   double totalVolume;      // Total volume in profile
   double pocVolume;        // Volume at POC
   double hvnThreshold;     // High Volume Node threshold
   double lvnThreshold;     // Low Volume Node threshold
   bool   valid;            // Is profile valid?
};

//--- VP Engine class
class CVPEngine
{
private:
   int      m_bucketSize;      // Number of buckets
   double   m_bucketPips;      // Price per bucket
   double   m_vaPct;           // Value area percentage (70%)
   double   m_hvnPct;          // HVN threshold (% of POC volume)
   double   m_lvnPct;          // LVN threshold (% of POC volume)
   
public:
   CVPEngine(int buckets = 60, double bucketPips = 0.50, double vaPct = 70.0);
   ~CVPEngine();
   
   //--- Compute volume profile from OHLCV arrays
   VolumeProfileResult Compute(const double &high[], const double &low[], 
                                const double &close[], const double &volume[],
                                int totalBars);
   
   //--- Compute profile for specific symbol and timeframe
   VolumeProfileResult ComputeFromSymbol(string symbol, ENUM_TIMEFRAMES tf,
                                          int startBar, int numBars);
   
   //--- Get nearest VP level to price
   double GetNearestLevel(double price, VolumeProfileResult &vp, double tolerance);
   
   //--- Check if price is at POC
   bool IsAtPOC(double price, double atr, double tolerance = 0.3);
   
   //--- Check if price is at VAH
   bool IsAtVAH(double price, double atr, double tolerance = 0.3);
   
   //--- Check if price is at VAL
   bool IsAtVAL(double price, double atr, double tolerance = 0.3);
};

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CVPEngine::CVPEngine(int buckets, double bucketPips, double vaPct)
{
   m_bucketSize = buckets;
   m_bucketPips = bucketPips;
   m_vaPct = vaPct;
   m_hvnPct = 0.70;  // 70% of POC volume = HVN
   m_lvnPct = 0.20;  // 20% of POC volume = LVN
}

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CVPEngine::~CVPEngine()
{
}

//+------------------------------------------------------------------+
//| Compute Volume Profile from OHLCV arrays                           |
//+------------------------------------------------------------------+
VolumeProfileResult CVPEngine::Compute(const double &high[], const double &low[],
                                        const double &close[], const double &volume[],
                                        int totalBars)
{
   VolumeProfileResult result;
   result.valid = false;
   
   if(totalBars < 10)
      return result;
   
   //--- Find price range
   double minPrice = high[0];
   double maxPrice = low[0];
   
   for(int i = 1; i < totalBars; i++)
   {
      if(high[i] > maxPrice) maxPrice = high[i];
      if(low[i] < minPrice) minPrice = low[i];
   }
   
   double priceRange = maxPrice - minPrice;
   if(priceRange < m_bucketPips)
      return result;
   
   //--- Create buckets
   int numBuckets = (int)(priceRange / m_bucketPips) + 1;
   if(numBuckets > 500) numBuckets = 500;  // Cap at 500
   
   double bucketVol[];
   ArrayResize(bucketVol, numBuckets);
   ArrayInitialize(bucketVol, 0.0);
   
   //--- Distribute volume into buckets
   for(int i = 0; i < totalBars; i++)
   {
      double barHigh = high[i];
      double barLow = low[i];
      double barVol = volume[i];
      
      if(barVol <= 0) continue;
      
      //--- How many buckets does this bar span?
      int startBucket = (int)((barLow - minPrice) / m_bucketPips);
      int endBucket = (int)((barHigh - minPrice) / m_bucketPips);
      
      startBucket = MathMax(0, MathMin(startBucket, numBuckets - 1));
      endBucket = MathMax(0, MathMin(endBucket, numBuckets - 1));
      
      int bucketsSpanned = endBucket - startBucket + 1;
      if(bucketsSpanned < 1) bucketsSpanned = 1;
      
      double volPerBucket = barVol / bucketsSpanned;
      
      for(int b = startBucket; b <= endBucket; b++)
      {
         if(b >= 0 && b < numBuckets)
            bucketVol[b] += volPerBucket;
      }
   }
   
   //--- Find POC (highest volume bucket)
   int pocIndex = 0;
   double maxVol = 0;
   for(int i = 0; i < numBuckets; i++)
   {
      if(bucketVol[i] > maxVol)
      {
         maxVol = bucketVol[i];
         pocIndex = i;
      }
   }
   
   result.poc = minPrice + (pocIndex + 0.5) * m_bucketPips;
   result.pocVolume = maxVol;
   result.totalVolume = 0;
   for(int i = 0; i < numBuckets; i++)
      result.totalVolume += bucketVol[i];
   
   //--- Compute Value Area (70% of total volume)
   double vaTarget = result.totalVolume * (m_vaPct / 100.0);
   double vaVol = bucketVol[pocIndex];
   
   int lowIdx = pocIndex;
   int highIdx = pocIndex;
   
   while(vaVol < vaTarget && (lowIdx > 0 || highIdx < numBuckets - 1))
   {
      double downVol = (lowIdx > 0) ? bucketVol[lowIdx - 1] : 0;
      double upVol = (highIdx < numBuckets - 1) ? bucketVol[highIdx + 1] : 0;
      
      if(downVol >= upVol && lowIdx > 0)
      {
         lowIdx--;
         vaVol += bucketVol[lowIdx];
      }
      else if(highIdx < numBuckets - 1)
      {
         highIdx++;
         vaVol += bucketVol[highIdx];
      }
      else
         break;
   }
   
   result.val = minPrice + (lowIdx + 0.5) * m_bucketPips;
   result.vah = minPrice + (highIdx + 0.5) * m_bucketPips;
   
   //--- Set HVN/LVN thresholds
   result.hvnThreshold = maxVol * m_hvnPct;
   result.lvnThreshold = maxVol * m_lvnPct;
   
   result.valid = true;
   return result;
}

//+------------------------------------------------------------------+
//| Compute Profile from Symbol Data                                  |
//+------------------------------------------------------------------+
VolumeProfileResult CVPEngine::ComputeFromSymbol(string symbol, ENUM_TIMEFRAMES tf,
                                                  int startBar, int numBars)
{
   double high[], low[], close[], volume[];
   
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(volume, true);
   
   if(CopyHigh(symbol, tf, startBar, numBars, high) < numBars)
   {
      VolumeProfileResult empty;
      empty.valid = false;
      return empty;
   }
   
   CopyLow(symbol, tf, startBar, numBars, low);
   CopyClose(symbol, tf, startBar, numBars, close);
   CopyTickVolume(symbol, tf, startBar, numBars, volume);
   
   return Compute(high, low, close, volume, numBars);
}

//+------------------------------------------------------------------+
//| Check if price is at POC                                          |
//+------------------------------------------------------------------+
bool CVPEngine::IsAtPOC(double price, double atr, double tolerance)
{
   //--- This needs a stored POC value, use GetNearestLevel instead
   return false;
}

//+------------------------------------------------------------------+
//| Check if price is at VAH                                          |
//+------------------------------------------------------------------+
bool CVPEngine::IsAtVAH(double price, double atr, double tolerance)
{
   return false;
}

//+------------------------------------------------------------------+
//| Check if price is at VAL                                          |
//+------------------------------------------------------------------+
bool CVPEngine::IsAtVAL(double price, double atr, double tolerance)
{
   return false;
}

//+------------------------------------------------------------------+
//| Get nearest VP level                                               |
//+------------------------------------------------------------------+
double CVPEngine::GetNearestLevel(double price, VolumeProfileResult &vp, double tolerance)
{
   if(!vp.valid) return 0;
   
   double distPOC = MathAbs(price - vp.poc);
   double distVAH = MathAbs(price - vp.vah);
   double distVAL = MathAbs(price - vp.val);
   
   double minDist = MathMin(distPOC, MathMin(distVAH, distVAL));
   
   if(minDist > tolerance) return 0;
   
   if(minDist == distPOC) return vp.poc;
   if(minDist == distVAH) return vp.vah;
   return vp.val;
}

#endif // VP_ENGINE_MQH
