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
