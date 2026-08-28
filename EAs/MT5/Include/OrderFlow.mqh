//+------------------------------------------------------------------+
//|                                              OrderFlow.mqh        |
//|                    Order Flow Confirmation Module                  |
//|                    Uses tick data as buy/sell pressure proxy       |
//+------------------------------------------------------------------+
#ifndef ORDERFLOW_MQH
#define ORDERFLOW_MQH

//--- Order Flow Result structure
struct OrderFlowResult
{
   double   buyPressure;     // Buy pressure ratio (0.0 - 1.0)
   double   sellPressure;    // Sell pressure ratio (0.0 - 1.0)
   double   delta;           // Net delta (buy - sell)
   double   totalTicks;      // Total ticks analyzed
   bool     valid;           // Is result valid?
};

//--- Order Flow Analyzer
class COrderFlow
{
private:
   int      m_lookbackBars;    // Bars to look back for flow
   int      m_lookbackMinutes; // Minutes to look back
   double   m_buyThreshold;    // Min buy ratio for long confirmation
   double   m_sellThreshold;   // Min sell ratio for short confirmation
   
public:
   COrderFlow(int lookbackBars = 5, int lookbackMinutes = 20, 
              double buyThresh = 0.55, double sellThresh = 0.45);
   ~COrderFlow();
   
   //--- Analyze order flow for symbol
   OrderFlowResult Analyze(string symbol, ENUM_TIMEFRAMES tf);
   
   //--- Analyze with tick data (more accurate)
   OrderFlowResult AnalyzeTicks(string symbol, int lookbackMinutes = 20);
   
   //--- Check if flow confirms BUY
   bool ConfirmsBuy(OrderFlowResult &flow);
   
   //--- Check if flow confirms SELL
   bool ConfirmsSell(OrderFlowResult &flow);
   
   //--- Print flow analysis
   void PrintFlow(OrderFlowResult &flow);
};

//+------------------------------------------------------------------+
//| Constructor                                                        |
//+------------------------------------------------------------------+
COrderFlow::COrderFlow(int lookbackBars, int lookbackMinutes, 
                        double buyThresh, double sellThresh)
{
   m_lookbackBars = lookbackBars;
   m_lookbackMinutes = lookbackMinutes;
   m_buyThreshold = buyThresh;
   m_sellThreshold = sellThresh;
}

//+------------------------------------------------------------------+
//| Destructor                                                         |
//+------------------------------------------------------------------+
COrderFlow::~COrderFlow()
{
}

//+------------------------------------------------------------------+
//| Analyze Order Flow from Bar Data                                  |
//+------------------------------------------------------------------+
OrderFlowResult COrderFlow::Analyze(string symbol, ENUM_TIMEFRAMES tf)
{
   OrderFlowResult result;
   result.valid = false;
   
   double open[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(symbol, tf, 0, m_lookbackBars, open) < m_lookbackBars)
      return result;
   
   if(CopyClose(symbol, tf, 0, m_lookbackBars, close) < m_lookbackBars)
      return result;
   
   int buys = 0;
   int sells = 0;
   
   for(int i = 0; i < m_lookbackBars; i++)
   {
      if(close[i] > open[i])
         buys++;
      else if(close[i] < open[i])
         sells++;
   }
   
   result.totalTicks = buys + sells;
   if(result.totalTicks == 0) return result;
   
   result.buyPressure = buys / result.totalTicks;
   result.sellPressure = sells / result.totalTicks;
   result.delta = buys - sells;
   result.valid = true;
   
   return result;
}

//+------------------------------------------------------------------+
//| Analyze Order Flow from Tick Data (More Accurate)                 |
//+------------------------------------------------------------------+
OrderFlowResult COrderFlow::AnalyzeTicks(string symbol, int lookbackMinutes)
{
   OrderFlowResult result;
   result.valid = false;
   
   //--- Get recent ticks
   MqlTick ticks[];
   datetime from = TimeCurrent() - lookbackMinutes * 60;
   datetime to = TimeCurrent();
   
   int copied = CopyTicks(symbol, ticks, COPY_TICKS_ALL, from, to);
   if(copied < 10) return result;
   
   int buys = 0;
   int sells = 0;
   
   for(int i = 0; i < copied; i++)
   {
      //--- Classify tick as buy or sell
      //--- If tick price > last tick = buy pressure
      //--- If tick price < last tick = sell pressure
      if(i > 0)
      {
         if(ticks[i].ask > ticks[i-1].ask)
            buys++;
         else if(ticks[i].bid < ticks[i-1].bid)
            sells++;
         else
         {
            //--- Use volume flag if available
            if((ticks[i].flags & TICK_FLAG_BUY) != 0)
               buys++;
            else if((ticks[i].flags & TICK_FLAG_SELL) != 0)
               sells++;
         }
      }
   }
   
   result.totalTicks = buys + sells;
   if(result.totalTicks == 0) return result;
   
   result.buyPressure = buys / result.totalTicks;
   result.sellPressure = sells / result.totalTicks;
   result.delta = buys - sells;
   result.valid = true;
   
   return result;
}

//+------------------------------------------------------------------+
//| Check if Flow Confirms BUY                                        |
//+------------------------------------------------------------------+
bool COrderFlow::ConfirmsBuy(OrderFlowResult &flow)
{
   if(!flow.valid) return false;
   return flow.buyPressure >= m_buyThreshold;
}

//+------------------------------------------------------------------+
//| Check if Flow Confirms SELL                                       |
//+------------------------------------------------------------------+
bool COrderFlow::ConfirmsSell(OrderFlowResult &flow)
{
   if(!flow.valid) return false;
   return flow.sellPressure >= m_sellThreshold;
}

//+------------------------------------------------------------------+
//| Print Flow Analysis                                               |
//+------------------------------------------------------------------+
void COrderFlow::PrintFlow(OrderFlowResult &flow)
{
   if(!flow.valid)
   {
      Print("Order Flow: INVALID");
      return;
   }
   
   PrintFormat("Order Flow: Buy=%.1f%% Sell=%.1f%% Delta=%.0f Ticks=%.0f",
               flow.buyPressure * 100, flow.sellPressure * 100,
               flow.delta, flow.totalTicks);
}

#endif // ORDERFLOW_MQH
