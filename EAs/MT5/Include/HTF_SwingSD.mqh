//+------------------------------------------------------------------+
//|                                             HTF_SwingSD.mqh       |
//|                    High TF Supply & Demand Zone Detection          |
//|                    Uses H4/Daily swing points for structure         |
//+------------------------------------------------------------------+
#ifndef HTF_SWINGSD_MQH
#define HTF_SWINGSD_MQH

//--- Supply/Demand Zone structure
struct SDZone
{
   double   top;           // Zone top (supply) or bottom (demand)
   double   bottom;        // Zone bottom (supply) or top (demand)
   double   midpoint;      // Zone midpoint
   double   strength;      // Zone strength (1-10)
   int      retests;       // Number of retests
   datetime firstTouch;    // When zone was created
   datetime lastTouch;     // Last retest time
   bool     isSupply;      // true = supply, false = demand
   bool     valid;         // Is zone still valid?
   bool     mitigated;     // Has zone been mitigated (broken)?
};

//--- HTF Swing SD Detector
class CHTF_SwingSD
{
private:
   int      m_swingLen;        // Swing lookback bars
   double   m_zoneATR;         // Zone thickness in ATR
   int      m_maxZones;        // Max zones to track
   double   m_minStrength;     // Minimum zone strength to trade
   
   SDZone   m_supplyZones[];   // Array of supply zones
   SDZone   m_demandZones[];   // Array of demand zones
   int      m_supplyCount;
   int      m_demandCount;
   
public:
   CHTF_SwingSD(int swingLen = 5, double zoneATR = 0.5, int maxZones = 10, double minStrength = 3.0);
   ~CHTF_SwingSD();
   
   //--- Detect zones from H4/Daily bars
   void DetectZones(string symbol, ENUM_TIMEFRAMES htf);
   
   //--- Get nearest supply zone to price
   SDZone* GetNearestSupply(double price, double atr);
   
   //--- Get nearest demand zone to price
   SDZone* GetNearestDemand(double price, double atr);
   
   //--- Check if price is inside a zone
   bool IsInSupplyZone(double price, double atr);
   bool IsInDemandZone(double price, double atr);
   
   //--- Get zone strength
   double GetZoneStrength(SDZone &zone);
   
   //--- Print all zones
   void PrintZones();
   
   //--- Get zone count
   int GetSupplyCount() { return m_supplyCount; }
   int GetDemandCount() { return m_demandCount; }
};

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
CHTF_SwingSD::CHTF_SwingSD(int swingLen, double zoneATR, int maxZones, double minStrength)
{
   m_swingLen = swingLen;
   m_zoneATR = zoneATR;
   m_maxZones = maxZones;
   m_minStrength = minStrength;
   m_supplyCount = 0;
   m_demandCount = 0;
   
   ArrayResize(m_supplyZones, maxZones);
   ArrayResize(m_demandZones, maxZones);
}

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
CHTF_SwingSD::~CHTF_SwingSD()
{
}

//+------------------------------------------------------------------+
//| Detect Supply/Demand Zones from HTF                                |
//+------------------------------------------------------------------+
void CHTF_SwingSD::DetectZones(string symbol, ENUM_TIMEFRAMES htf)
{
   m_supplyCount = 0;
   m_demandCount = 0;
   
   //--- Get HTF data
   double high[], low[], close[];
   datetime time[];
   int bars = 500;
   
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time, true);
   
   if(CopyHigh(symbol, htf, 0, bars, high) < bars) return;
   CopyLow(symbol, htf, 0, bars, low);
   CopyClose(symbol, htf, 0, bars, close);
   CopyTime(symbol, htf, 0, bars, time);
   
   //--- Get ATR for zone thickness
   double atr[];
   ArraySetAsSeries(atr, true);
   int atrHandle = iATR(symbol, htf, 14);
   if(atrHandle == INVALID_HANDLE) return;
   CopyBuffer(atrHandle, 0, 0, 1, atr);
   IndicatorRelease(atrHandle);
   
   double zoneThickness = atr[0] * m_zoneATR;
   
   //--- Find swing highs (supply) and swing lows (demand)
   for(int i = m_swingLen; i < bars - m_swingLen; i++)
   {
      //--- Check for swing high (potential supply zone)
      bool isSwingHigh = true;
      for(int j = 1; j <= m_swingLen; j++)
      {
         if(high[i] <= high[i-j] || high[i] <= high[i+j])
         {
            isSwingHigh = false;
            break;
         }
      }
      
      if(isSwingHigh && m_supplyCount < m_maxZones)
      {
         SDZone zone;
         zone.top = high[i] + zoneThickness * 0.5;
         zone.bottom = high[i] - zoneThickness * 0.5;
         zone.midpoint = high[i];
         zone.firstTouch = time[i];
         zone.lastTouch = time[i];
         zone.retests = 0;
         zone.isSupply = true;
         zone.valid = true;
         zone.mitigated = false;
         
         //--- Count retests
         for(int k = i + 1; k < bars; k++)
         {
            if(low[k] <= zone.top && high[k] >= zone.bottom)
            {
               zone.retests++;
               zone.lastTouch = time[k];
            }
            //--- Zone broken = mitigated
            if(close[k] > zone.top)
            {
               zone.mitigated = true;
               break;
            }
         }
         
         zone.strength = GetZoneStrength(zone);
         if(zone.strength >= m_minStrength && !zone.mitigated)
         {
            m_supplyZones[m_supplyCount] = zone;
            m_supplyCount++;
         }
      }
      
      //--- Check for swing low (potential demand zone)
      bool isSwingLow = true;
      for(int j = 1; j <= m_swingLen; j++)
      {
         if(low[i] >= low[i-j] || low[i] >= low[i+j])
         {
            isSwingLow = false;
            break;
         }
      }
      
      if(isSwingLow && m_demandCount < m_maxZones)
      {
         SDZone zone;
         zone.top = low[i] + zoneThickness * 0.5;
         zone.bottom = low[i] - zoneThickness * 0.5;
         zone.midpoint = low[i];
         zone.firstTouch = time[i];
         zone.lastTouch = time[i];
         zone.retests = 0;
         zone.isSupply = false;
         zone.valid = true;
         zone.mitigated = false;
         
         //--- Count retests
         for(int k = i + 1; k < bars; k++)
         {
            if(high[k] >= zone.bottom && low[k] <= zone.top)
            {
               zone.retests++;
               zone.lastTouch = time[k];
            }
            //--- Zone broken = mitigated
            if(close[k] < zone.bottom)
            {
               zone.mitigated = true;
               break;
            }
         }
         
         zone.strength = GetZoneStrength(zone);
         if(zone.strength >= m_minStrength && !zone.mitigated)
         {
            m_demandZones[m_demandCount] = zone;
            m_demandCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get Zone Strength (1-10 scale)                                    |
//+------------------------------------------------------------------+
double CHTF_SwingSD::GetZoneStrength(SDZone &zone)
{
   double strength = 1.0;
   
   //--- Retest bonus (each retest adds 0.5)
   strength += zone.retests * 0.5;
   
   //--- Freshness bonus (untouched zones are stronger)
   int barsSinceTouch = iBars(_Symbol, PERIOD_M15) - iBarShift(_Symbol, PERIOD_M15, zone.lastTouch);
   if(barsSinceTouch > 100) strength += 1.0;   // Very fresh
   else if(barsSinceTouch > 50) strength += 0.5; // Somewhat fresh
   
   //--- Cap at 10
   if(strength > 10.0) strength = 10.0;
   
   return strength;
}

//+------------------------------------------------------------------+
//| Get Nearest Supply Zone                                            |
//+------------------------------------------------------------------+
SDZone* CHTF_SwingSD::GetNearestSupply(double price, double atr)
{
   SDZone* nearest = NULL;
   double minDist = DBL_MAX;
   
   for(int i = 0; i < m_supplyCount; i++)
   {
      if(!m_supplyZones[i].valid || m_supplyZones[i].mitigated) continue;
      
      double dist = MathAbs(price - m_supplyZones[i].midpoint);
      if(dist < minDist && dist < atr * 3)  // Within 3 ATR
      {
         minDist = dist;
         nearest = &m_supplyZones[i];
      }
   }
   
   return nearest;
}

//+------------------------------------------------------------------+
//| Get Nearest Demand Zone                                            |
//+------------------------------------------------------------------+
SDZone* CHTF_SwingSD::GetNearestDemand(double price, double atr)
{
   SDZone* nearest = NULL;
   double minDist = DBL_MAX;
   
   for(int i = 0; i < m_demandCount; i++)
   {
      if(!m_demandZones[i].valid || m_demandZones[i].mitigated) continue;
      
      double dist = MathAbs(price - m_demandZones[i].midpoint);
      if(dist < minDist && dist < atr * 3)
      {
         minDist = dist;
         nearest = &m_demandZones[i];
      }
   }
   
   return nearest;
}

//+------------------------------------------------------------------+
//| Check if Price is in Supply Zone                                   |
//+------------------------------------------------------------------+
bool CHTF_SwingSD::IsInSupplyZone(double price, double atr)
{
   for(int i = 0; i < m_supplyCount; i++)
   {
      if(!m_supplyZones[i].valid || m_supplyZones[i].mitigated) continue;
      
      if(price <= m_supplyZones[i].top && price >= m_supplyZones[i].bottom)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if Price is in Demand Zone                                   |
//+------------------------------------------------------------------+
bool CHTF_SwingSD::IsInDemandZone(double price, double atr)
{
   for(int i = 0; i < m_demandCount; i++)
   {
      if(!m_demandZones[i].valid || m_demandZones[i].mitigated) continue;
      
      if(price >= m_demandZones[i].bottom && price <= m_demandZones[i].top)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Print All Zones                                                    |
//+------------------------------------------------------------------+
void CHTF_SwingSD::PrintZones()
{
   Print("=== SUPPLY ZONES ===");
   for(int i = 0; i < m_supplyCount; i++)
   {
      PrintFormat("  Zone %d: %.2f-%.2f | Strength: %.1f | Retests: %d | Mitigated: %s",
                  i, m_supplyZones[i].bottom, m_supplyZones[i].top,
                  m_supplyZones[i].strength, m_supplyZones[i].retests,
                  m_supplyZones[i].mitigated ? "YES" : "NO");
   }
   
   Print("=== DEMAND ZONES ===");
   for(int i = 0; i < m_demandCount; i++)
   {
      PrintFormat("  Zone %d: %.2f-%.2f | Strength: %.1f | Retests: %d | Mitigated: %s",
                  i, m_demandZones[i].bottom, m_demandZones[i].top,
                  m_demandZones[i].strength, m_demandZones[i].retests,
                  m_demandZones[i].mitigated ? "YES" : "NO");
   }
}

#endif // HTF_SWINGSD_MQH
