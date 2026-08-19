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



#include "FixedRangeVolumeProfile.mqh"

#include "PriceActionPatterns.mqh"
#include "SupportResistance.mqh"



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

input int      MaxPositionsPerPair = 2;            // Max positions per symbol (was 1)

input int      MaxGlobalPositions  = 6;            // Max total open positions (was 4)

input int      MaxDailyTrades      = 30;           // Max trades per day (all symbols) (was 20)

input double   MaxDailyLossPct     = 5.0;          // Stop trading at this daily loss %

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

         FRVPResult &prof = g_frvpStates[si].current;

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

         FRVPResult &prof = g_frvpStates[si].current;

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

      double lossPct = (g_dailyStartBalance - currBalance) / g_dailyStartBalance * 100.0;

      if(lossPct >= MaxDailyLossPct)

      {

         g_tradingPaused = true;

         Print("Max daily loss (", DoubleToString(lossPct, 1), "%) reached. Paused.");

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

