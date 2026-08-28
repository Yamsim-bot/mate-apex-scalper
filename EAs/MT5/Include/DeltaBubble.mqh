//+------------------------------------------------------------------+
//|                                               DeltaBubble.mqh     |
//|                          Delta Bubble Order Flow Module v1.0       |
//|                          Absorption + Delta Shift + Bubble Detect  |
//+------------------------------------------------------------------+
#property copyright "YAMSTUNNA Trading Systems"
#property link      ""
#property version   "1.00"

//+------------------------------------------------------------------+
//| DELTA BUBBLE STRUCTURE                                             |
//+------------------------------------------------------------------+
struct DeltaBubbleData
{
   double delta;           // Current delta (buy - sell volume)
   double deltaPrev;       // Previous delta
   double buyVol;          // Total buy volume
   double sellVol;         // Total sell volume
   double bubbleSize;      // Largest bubble size
   double avgBubble;       // Average bubble size
   bool   absorption;      // Absorption detected
   bool   deltaShift;      // Delta changed sign
   bool   strongBuy;       // Strong buying pressure
   bool   strongSell;      // Strong selling pressure
   double deltaRatio;      // Buy ratio (0-1)
   int    bubbleCount;     // Number of significant bubbles
};

//+------------------------------------------------------------------+
//| DELTA BUBBLE ENGINE                                                |
//+------------------------------------------------------------------+
class DeltaBubbleEngine
{
private:
   double m_minBubbleSize;    // Min size for "significant" bubble
   double m_absorbThresh;     // Absorption threshold (volume * multiplier)
   double m_deltaShiftThresh; // Delta shift threshold
   int    m_lookback;         // Lookback bars
   
public:
   DeltaBubbleEngine(double minBubble, double absorbThresh, double shiftThresh, int lookback)
   {
      m_minBubbleSize = minBubble;
      m_absorbThresh = absorbThresh;
      m_deltaShiftThresh = shiftThresh;
      m_lookback = lookback;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate Delta Bubble Data                                       |
   //+------------------------------------------------------------------+
   DeltaBubbleData Calculate(string symbol, ENUM_TIMEFRAMES tf)
   {
      DeltaBubbleData data = {};
      
      // Get tick volumes and directions
      double close[], open[], high[], low[];
      long tickVol[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(tickVol, true);
      
      if(CopyClose(symbol, tf, 0, m_lookback, close) < m_lookback) return data;
      if(CopyOpen(symbol, tf, 0, m_lookback, open) < m_lookback) return data;
      if(CopyHigh(symbol, tf, 0, m_lookback, high) < m_lookback) return data;
      if(CopyLow(symbol, tf, 0, m_lookback, low) < m_lookback) return data;
      if(CopyTickVolume(symbol, tf, 0, m_lookback, tickVol) < m_lookback) return data;
      
      // Calculate delta for each bar
      double totalBuy = 0, totalSell = 0;
      double maxBubble = 0, totalBubble = 0;
      int sigBubbles = 0;
      
      for(int i = 0; i < m_lookback; i++)
      {
         double vol = tickVol[i];
         double range = high[i] - low[i];
         
         if(range <= 0) continue;
         
         // Estimate buy/sell split based on candle direction
         double bodyRatio = 0;
         if(close[i] > open[i]) bodyRatio = 0.7;      // Bullish = 70% buy
         else if(close[i] < open[i]) bodyRatio = 0.3;  // Bearish = 30% buy
         else bodyRatio = 0.5;                           // Doji = 50/50
         
         // Adjust by wick ratio (lower wick = more buying, upper wick = more selling)
         double body = MathAbs(close[i] - open[i]);
         double upperWick = high[i] - MathMax(close[i], open[i]);
         double lowerWick = MathMin(close[i], open[i]) - low[i];
         
         if(body > 0)
         {
            double wickRatio = (lowerWick - upperWick) / body;
            bodyRatio += wickRatio * 0.15;  // Adjust by 15% per wick ratio
            bodyRatio = MathMax(0.1, MathMin(0.9, bodyRatio));
         }
         
         double buyV = vol * bodyRatio;
         double sellV = vol * (1.0 - bodyRatio);
         
         totalBuy += buyV;
         totalSell += sellV;
         
         // Track bubble size
         if(vol > maxBubble) maxBubble = vol;
         totalBubble += vol;
         
         // Count significant bubbles
         if(vol >= m_minBubbleSize) sigBubbles++;
      }
      
      // Calculate current vs previous delta
      double currBuy = 0, currSell = 0;
      double prevBuy = 0, prevSell = 0;
      
      for(int i = 0; i < MathMin(3, m_lookback); i++)
      {
         double vol = tickVol[i];
         double bodyRatio = 0.5;
         if(close[i] > open[i]) bodyRatio = 0.7;
         else if(close[i] < open[i]) bodyRatio = 0.3;
         
         currBuy += vol * bodyRatio;
         currSell += vol * (1.0 - bodyRatio);
      }
      
      for(int i = 3; i < MathMin(6, m_lookback); i++)
      {
         double vol = tickVol[i];
         double bodyRatio = 0.5;
         if(close[i] > open[i]) bodyRatio = 0.7;
         else if(close[i] < open[i]) bodyRatio = 0.3;
         
         prevBuy += vol * bodyRatio;
         prevSell += vol * (1.0 - bodyRatio);
      }
      
      // Fill data structure
      data.buyVol = totalBuy;
      data.sellVol = totalSell;
      data.delta = totalBuy - totalSell;
      data.deltaPrev = prevBuy - prevSell;
      data.bubbleSize = maxBubble;
      data.avgBubble = (m_lookback > 0) ? totalBubble / m_lookback : 0;
      data.bubbleCount = sigBubbles;
      data.deltaRatio = (totalBuy + totalSell > 0) ? totalBuy / (totalBuy + totalSell) : 0.5;
      
      // Detect absorption: high volume but price stalled
      double avgRange = 0;
      for(int i = 0; i < m_lookback; i++)
         avgRange += (high[i] - low[i]);
      avgRange /= m_lookback;
      
      double currRange = (high[0] - low[0]);
      data.absorption = (currRange < avgRange * 0.5 && 
                        maxBubble > avgRange * m_absorbThresh);
      
      // Detect delta shift: sign changed
      data.deltaShift = ((data.delta >= 0 && data.deltaPrev < 0) ||
                         (data.delta <= 0 && data.deltaPrev > 0));
      
      // Strong pressure thresholds
      data.strongBuy = (data.deltaRatio >= 0.65 && sigBubbles >= 3);
      data.strongSell = (data.deltaRatio <= 0.35 && sigBubbles >= 3);
      
      return data;
   }
   
   //+------------------------------------------------------------------+
   //| Check if Delta Confirms BUY                                       |
   //+------------------------------------------------------------------+
   bool ConfirmsBuy(DeltaBubbleData &data)
   {
      // Method 1: Delta shift from negative to positive
      if(data.deltaShift && data.delta > 0) return true;
      
      // Method 2: Absorption at low + strong buying
      if(data.absorption && data.strongBuy) return true;
      
      // Method 3: Delta ratio > 0.60 with significant bubbles
      if(data.deltaRatio >= 0.60 && data.bubbleCount >= 2) return true;
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Check if Delta Confirms SELL                                      |
   //+------------------------------------------------------------------+
   bool ConfirmsSell(DeltaBubbleData &data)
   {
      // Method 1: Delta shift from positive to negative
      if(data.deltaShift && data.delta < 0) return true;
      
      // Method 2: Absorption at high + strong selling
      if(data.absorption && data.strongSell) return true;
      
      // Method 3: Delta ratio < 0.40 with significant bubbles
      if(data.deltaRatio <= 0.40 && data.bubbleCount >= 2) return true;
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Get Bubble Strength (1-10)                                        |
   //+------------------------------------------------------------------+
   int GetBubbleStrength(DeltaBubbleData &data)
   {
      int strength = 5;  // Base
      
      // Boost for delta shift
      if(data.deltaShift) strength += 2;
      
      // Boost for absorption
      if(data.absorption) strength += 2;
      
      // Boost for strong pressure
      if(data.strongBuy || data.strongSell) strength += 1;
      
      // Boost for large bubbles
      if(data.bubbleSize > data.avgBubble * 2) strength += 1;
      
      // Cap at 10
      return MathMin(strength, 10);
   }
   
   //+------------------------------------------------------------------+
   //| Get Bubble Description                                            |
   //+------------------------------------------------------------------+
   string GetDescription(DeltaBubbleData &data)
   {
      string desc = "";
      
      if(data.absorption) desc += "ABSORPTION ";
      if(data.deltaShift) desc += "DELTA_SHIFT ";
      if(data.strongBuy) desc += "STRONG_BUY ";
      if(data.strongSell) desc += "STRONG_SELL ";
      
      desc += StringFormat("delta=%.0f ratio=%.2f bubbles=%d",
                          data.delta, data.deltaRatio, data.bubbleCount);
      
      return desc;
   }
};
//+------------------------------------------------------------------+
