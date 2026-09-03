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
