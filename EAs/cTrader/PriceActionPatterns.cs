//+------------------------------------------------------------------+
//|                              PriceActionPatterns.cs               |
//|                     Price Action for cTrader C#                  |
//|                     Pin bar, Engulfing, Combo, BOS, OB flip      |
//+------------------------------------------------------------------+
using System;
using cAlgo.API;

namespace cAlgo.Robots
{
    public class PASignal
    {
        public int Direction;    // +1=bull, -1=bear, 0=none
        public int Strength;     // 0..4
        public string Pattern;
    }

    public static class PriceActionPatterns
    {
        public static PASignal DetectPinBar(Bar r1, Bar r2, double atr,
                                             double minWickATR = 0.5, double wickBodyRatio = 2.0)
        {
            var sig = new PASignal();
            double body = Math.Abs(r1.Close - r1.Open);
            double lowerW = Math.Min(r1.Close, r1.Open) - r1.Low;
            double upperW = r1.High - Math.Max(r1.Close, r1.Open);
            if (atr <= 0 || body == 0) return sig;

            // Bullish pin: long lower wick
            if (lowerW >= atr * minWickATR && lowerW >= body * wickBodyRatio && upperW < body * 0.5)
            {
                sig.Direction = 1; sig.Strength = 3; sig.Pattern = "PinBar_BULL";
                if (r1.Low <= r2.Low) { sig.Strength = 4; sig.Pattern = "PinBar_BULL+Low"; }
            }
            // Bearish pin: long upper wick
            if (upperW >= atr * minWickATR && upperW >= body * wickBodyRatio && lowerW < body * 0.5)
            {
                sig.Direction = -1; sig.Strength = 3; sig.Pattern = "PinBar_BEAR";
                if (r1.High >= r2.High) { sig.Strength = 4; sig.Pattern = "PinBar_BEAR+High"; }
            }
            return sig;
        }

        public static PASignal DetectEngulfing(Bar r1, Bar r2, double atr, double minBodyATR = 0.15)
        {
            var sig = new PASignal();
            double body1 = Math.Abs(r1.Close - r1.Open);
            double body2 = Math.Abs(r2.Close - r2.Open);
            bool r1Bull = r1.Close > r1.Open, r1Bear = r1.Close < r1.Open;
            bool r2Bull = r2.Close > r2.Open, r2Bear = r2.Close < r2.Open;

            if (atr <= 0) return sig;

            if (r2Bear && r1Bull && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
            {
                if (r1.Close > r2.Open && r1.Open < r2.Close)
                {
                    sig.Direction = 1; sig.Strength = 3; sig.Pattern = "Engulf_BULL";
                    if (r1.Close > r2.High) { sig.Strength = 4; sig.Pattern = "Engulf_BULL+CloseAbove"; }
                }
            }
            if (r2Bull && r1Bear && body1 > body2 * 1.1 && body1 > atr * minBodyATR)
            {
                if (r1.Close < r2.Open && r1.Open > r2.Close)
                {
                    sig.Direction = -1; sig.Strength = 3; sig.Pattern = "Engulf_BEAR";
                    if (r1.Close < r2.Low) { sig.Strength = 4; sig.Pattern = "Engulf_BEAR+CloseBelow"; }
                }
            }
            return sig;
        }

        public static PASignal DetectThreeBarReversal(Bars bars, int count, double atr, double minBodyATR = 0.15)
        {
            var sig = new PASignal();
            if (count < 4 || atr <= 0 || bars.Count < 4) return sig;

            int newest = bars.Count - 2, mid = bars.Count - 3, old = bars.Count - 4;
            double body0 = Math.Abs(bars[newest].Close - bars[newest].Open);
            double body1 = Math.Abs(bars[mid].Close - bars[mid].Open);
            double body2 = Math.Abs(bars[old].Close - bars[old].Open);

            // Morning Star
            if (bars[old].Close < bars[old].Open && bars[newest].Close > bars[newest].Open)
            {
                if (body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
                {
                    sig.Direction = 1; sig.Strength = 3; sig.Pattern = "MorningStar";
                    double mid2 = (bars[old].Open + bars[old].Close) / 2.0;
                    if (bars[newest].Close > mid2) { sig.Strength = 4; sig.Pattern = "MorningStar+"; }
                }
            }
            // Evening Star
            if (bars[old].Close > bars[old].Open && bars[newest].Close < bars[newest].Open)
            {
                if (body2 > atr * minBodyATR && body0 > atr * minBodyATR && body1 < body2 * 0.4)
                {
                    sig.Direction = -1; sig.Strength = 3; sig.Pattern = "EveningStar";
                    double mid2 = (bars[old].Open + bars[old].Close) / 2.0;
                    if (bars[newest].Close < mid2) { sig.Strength = 4; sig.Pattern = "EveningStar+"; }
                }
            }
            return sig;
        }

        public static PASignal Aggregate(Bars bars, int count, double atr,
                                          double swingHigh, double swingLow,
                                          double minWickATR = 0.5, double wickBodyRatio = 2.0,
                                          double minBodyATR = 0.15)
        {
            var best = new PASignal();
            if (bars.Count < 3 || atr <= 0) return best;

            // Pin bar
            var pin = DetectPinBar(bars[bars.Count - 2], bars[bars.Count - 3], atr, minWickATR, wickBodyRatio);
            if (pin.Direction != 0 && pin.Strength > best.Strength) best = pin;

            // Engulfing
            var eng = DetectEngulfing(bars[bars.Count - 2], bars[bars.Count - 3], atr, minBodyATR);
            if (eng.Direction != 0 && eng.Strength > best.Strength) best = eng;

            // Three-bar reversal
            var tbr = DetectThreeBarReversal(bars, count, atr, minBodyATR);
            if (tbr.Direction != 0 && tbr.Strength > best.Strength) best = tbr;

            // BOS
            if (bars.Count >= 2)
            {
                double close = bars[bars.Count - 2].Close;
                if (swingHigh > 0 && close > swingHigh + atr * 0.1)
                {
                    var bos = new PASignal { Direction = 1, Strength = 3, Pattern = "BOS_Bull" };
                    if (bos.Strength > best.Strength) best = bos;
                }
                if (swingLow > 0 && close < swingLow - atr * 0.1)
                {
                    var bos = new PASignal { Direction = -1, Strength = 3, Pattern = "BOS_Bear" };
                    if (bos.Strength > best.Strength) best = bos;
                }
            }

            return best;
        }
    }
}
