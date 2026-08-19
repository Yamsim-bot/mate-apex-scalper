//+------------------------------------------------------------------+
//|                                    SupportResistance.cs           |
//|                     Multi-TF S/R for cTrader C#                  |
//|                     Swing-based with zone clustering              |
//+------------------------------------------------------------------+
using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo.API;

namespace cAlgo.Robots
{
    public enum SRType { Support, Resistance }

    public class SRLevel
    {
        public SRType Type;
        public double Price;
        public double Upper;
        public double Lower;
        public int Touches;
        public int Timeframes;  // bitmask: M15=4, M30=8, H1=16, H4=32, D1=64
        public double Strength; // 0..1
    }

    public class SRResult
    {
        public List<SRLevel> Supports = new List<SRLevel>();
        public List<SRLevel> Resistances = new List<SRLevel>();
        public bool Valid => Supports.Count > 0 || Resistances.Count > 0;
    }

    public class SupportResistance
    {
        private readonly Robot _robot;
        
        private SRResult _current = new SRResult();

        public SRResult Current => _current;

        public SupportResistance(Robot robot)
        {
            _robot = robot;
            
        }

        /// <summary>
        /// Detect swing points from a single timeframe.
        /// </summary>
        private void DetectSwings(string symbol, TimeFrame tf, int lookback, int swingLen,
                                   out List<double> highs, out List<double> lows)
        {
            highs = new List<double>();
            lows = new List<double>();
            var bars = _robot.MarketData.GetBars(tf, symbol);
            if (bars == null || bars.Count < lookback) return;

            for (int i = swingLen; i < bars.Count - swingLen; i++)
            {
                bool isHigh = true;
                for (int j = 1; j <= swingLen; j++)
                {
                    if (bars[i].High <= bars[i - j].High || bars[i].High <= bars[i + j].High)
                    { isHigh = false; break; }
                }
                if (isHigh) highs.Add(bars[i].High);

                bool isLow = true;
                for (int j = 1; j <= swingLen; j++)
                {
                    if (bars[i].Low >= bars[i - j].Low || bars[i].Low >= bars[i + j].Low)
                    { isLow = false; break; }
                }
                if (isLow) lows.Add(bars[i].Low);
            }
        }

        /// <summary>
        /// Count touches for a level.
        /// </summary>
        private int CountTouches(string symbol, TimeFrame tf, int lookback, double level, double tolerance)
        {
            var bars = _robot.MarketData.GetBars(tf, symbol);
            if (bars == null || bars.Count < 5) return 0;
            int touches = 0;
            for (int i = 0; i < bars.Count; i++)
            {
                if (Math.Abs(bars[i].High - level) <= tolerance ||
                    Math.Abs(bars[i].Low - level) <= tolerance)
                    touches++;
                if (Math.Abs(bars[i].Open - level) <= tolerance * 0.5 ||
                    Math.Abs(bars[i].Close - level) <= tolerance * 0.5)
                    touches++;
            }
            return touches;
        }

        /// <summary>
        /// Check if level exists on multiple timeframes.
        /// </summary>
        private int MultiTFScore(string symbol, double level, double tolerance)
        {
            int score = 0;
            var tfs = new[] {
                (TimeFrame.Minute15, 4),
                (TimeFrame.Minute30, 8),
                (TimeFrame.Hour, 16),
                (TimeFrame.Hour4, 32),
                (TimeFrame.Daily, 64)
            };
            foreach (var (tf, bit) in tfs)
            {
                var bars = _robot.MarketData.GetBars(tf, symbol);
                if (bars == null || bars.Count < 20) continue;
                for (int i = 2; i < bars.Count - 2; i++)
                {
                    bool isHigh = true;
                    for (int j = 1; j <= 2; j++)
                    {
                        if (bars[i].High <= bars[i - j].High || bars[i].High <= bars[i + j].High)
                        { isHigh = false; break; }
                    }
                    if (isHigh && Math.Abs(bars[i].High - level) <= tolerance)
                    { score |= bit; break; }

                    bool isLow = true;
                    for (int j = 1; j <= 2; j++)
                    {
                        if (bars[i].Low >= bars[i - j].Low || bars[i].Low >= bars[i + j].Low)
                        { isLow = false; break; }
                    }
                    if (isLow && Math.Abs(bars[i].Low - level) <= tolerance)
                    { score |= bit; break; }
                }
            }
            return score;
        }

        /// <summary>
        /// Scan for S/R levels across multiple timeframes.
        /// </summary>
        public bool Scan(string symbol, TimeFrame entryTF, TimeFrame structTF,
                         double atr, double zoneATR = 0.5, int swingLen = 2)
        {
            double tolerance = Math.Max(atr * zoneATR, atr * 0.5);
            double bid = _robot.Symbol.Bid;

            var allHighs = new List<double>();
            var allLows = new List<double>();

            var scanTFs = new[] {
                (entryTF, 100, swingLen),
                (structTF, 200, swingLen),
                (TimeFrame.Hour4, 300, 3),
                (TimeFrame.Daily, 500, 3)
            };

            foreach (var (tf, lookback, sl) in scanTFs)
            {
                DetectSwings(symbol, tf, lookback, sl, out var h, out var l);
                allHighs.AddRange(h);
                allLows.AddRange(l);
            }

            // Sort and cluster
            allHighs.Sort();
            allLows.Sort();
            var mergedH = ClusterLevels(allHighs, tolerance);
            var mergedL = ClusterLevels(allLows, tolerance);

            _current = new SRResult();

            foreach (var level in mergedH)
            {
                if (level <= bid + atr * 0.2) continue;
                var sr = new SRLevel
                {
                    Type = SRType.Resistance,
                    Price = level,
                    Upper = level + tolerance * 0.5,
                    Lower = level - tolerance * 0.5,
                    Touches = CountTouches(symbol, entryTF, 200, level, tolerance),
                    Timeframes = MultiTFScore(symbol, level, tolerance)
                };
                sr.Strength = Math.Min(1.0, sr.Touches / 8.0 * 0.5 + Math.Max(0, CountSetBits(sr.Timeframes)) / 6.0 * 0.5);
                _current.Resistances.Add(sr);
            }

            foreach (var level in mergedL)
            {
                if (level >= bid - atr * 0.2) continue;
                var sr = new SRLevel
                {
                    Type = SRType.Support,
                    Price = level,
                    Upper = level + tolerance * 0.5,
                    Lower = level - tolerance * 0.5,
                    Touches = CountTouches(symbol, entryTF, 200, level, tolerance),
                    Timeframes = MultiTFScore(symbol, level, tolerance)
                };
                sr.Strength = Math.Min(1.0, sr.Touches / 8.0 * 0.5 + Math.Max(0, CountSetBits(sr.Timeframes)) / 6.0 * 0.5);
                _current.Supports.Add(sr);
            }

            return _current.Valid;
        }

        public bool AtSupport(double price, double tolerance)
        {
            return _current.Supports.Any(s => Math.Abs(price - s.Price) <= tolerance);
        }

        public bool AtResistance(double price, double tolerance)
        {
            return _current.Resistances.Any(r => Math.Abs(price - r.Price) <= tolerance);
        }

        public SRLevel NearestSupportBelow(double price)
        {
            return _current.Supports.Where(s => s.Price < price)
                .OrderByDescending(s => s.Price).FirstOrDefault();
        }

        public SRLevel NearestResistanceAbove(double price)
        {
            return _current.Resistances.Where(r => r.Price > price)
                .OrderBy(r => r.Price).FirstOrDefault();
        }

        public SRLevel NearestSupportAbove(double price)
        {
            return _current.Supports.Where(s => s.Price > price)
                .OrderBy(s => s.Price).FirstOrDefault();
        }

        public SRLevel NearestResistanceBelow(double price)
        {
            return _current.Resistances.Where(r => r.Price < price)
                .OrderByDescending(r => r.Price).FirstOrDefault();
        }

        private List<double> ClusterLevels(List<double> levels, double tolerance)
        {
            if (levels.Count == 0) return new List<double>();
            var result = new List<double>();
            double clusterSum = levels[0];
            int clusterCount = 1;
            result.Add(levels[0]);

            for (int i = 1; i < levels.Count; i++)
            {
                if (levels[i] - result[result.Count - 1] <= tolerance)
                {
                    clusterSum += levels[i];
                    clusterCount++;
                    result[result.Count - 1] = clusterSum / clusterCount;
                }
                else
                {
                    result.Add(levels[i]);
                    clusterSum = levels[i];
                    clusterCount = 1;
                }
            }
            return result;
        }

        private int CountSetBits(int n)
        {
            int count = 0;
            while (n > 0) { count += n & 1; n >>= 1; }
            return count;
        }
    }
}
