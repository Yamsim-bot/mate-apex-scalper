//+------------------------------------------------------------------+
//|                              FixedRangeVolumeProfile.cs           |
//|                     FRVP Engine for cTrader C#                   |
//|                     Computes POC / VAH / VAL / HVN / LVN zones   |
//+------------------------------------------------------------------+
using System;
using System.Collections.Generic;
using System.Linq;
using cAlgo.API;

namespace cAlgo.Robots
{
    public enum FRVPZoneType { POC, VAH, VAL, HVN, LVN }

    public class FRVPZone
    {
        public FRVPZoneType Type;
        public double Price;
        public double Upper;
        public double Lower;
        public long Volume;
        public double Strength; // 0..1
    }

    public class FRVPResult
    {
        public double POC;
        public double VAH;
        public double VAL;
        public double RangeHigh;
        public double RangeLow;
        public long TotalVolume;
        public List<FRVPZone> Zones = new List<FRVPZone>();
        public bool Valid;
    }

    public class FixedRangeVolumeProfile
    {
        
        private FRVPResult _current = new FRVPResult();
        private DateTime _lastCompute;
        private int _refreshCounter;

        public FRVPResult Current => _current;

        public FixedRangeVolumeProfile()
        {
            
        }

        /// <summary>
        /// Compute the volume profile over the last N bars.
        /// </summary>
        public bool Compute(Bars bars, int anchors, double bucketPips, double valueAreaPct = 70.0,
                            double hvnThreshold = 0.7, double lvnThreshold = 0.2)
        {
            if (anchors < 10) anchors = 10;
            if (bars == null || bars.Count < 10) return false;

            double rangeHigh = double.MinValue;
            double rangeLow = double.MaxValue;
            long totalVol = 0;

            for (int i = 1; i <= anchors; i++)
            {
                if (i >= bars.Count) break;
                var bar = bars[bars.Count - 1 - i]; // oldest first
                if (bar.High > rangeHigh) rangeHigh = bar.High;
                if (bar.Low < rangeLow) rangeLow = bar.Low;
                totalVol += (long)bar.TickVolume;
            }

            if (rangeHigh <= rangeLow || totalVol <= 0) return false;

            double rangeSize = rangeHigh - rangeLow;
            int numBuckets = (int)Math.Ceiling(rangeSize / bucketPips);
            if (numBuckets < 3) numBuckets = 3;
            if (numBuckets > 100) numBuckets = 100;
            double bucketSize = rangeSize / numBuckets;

            long[] bucketVol = new long[numBuckets];

            for (int i = 1; i <= anchors; i++)
            {
                if (i >= bars.Count) break;
                var bar = bars[bars.Count - 1 - i];
                int loIdx = Math.Max(0, (int)((bar.Low - rangeLow) / bucketSize));
                int hiIdx = Math.Min(numBuckets - 1, (int)((bar.High - rangeLow) / bucketSize));
                int touched = hiIdx - loIdx + 1;
                if (touched <= 0) touched = 1;
                long volPerBucket = (long)(bar.TickVolume / touched);
                if (volPerBucket <= 0) volPerBucket = (long)bar.TickVolume;
                for (int b = loIdx; b <= hiIdx; b++)
                    bucketVol[b] += volPerBucket;
            }

            // Find POC
            int pocIdx = 0;
            long maxVol = 0;
            for (int b = 0; b < numBuckets; b++)
            {
                if (bucketVol[b] > maxVol) { maxVol = bucketVol[b]; pocIdx = b; }
            }
            double pocPrice = rangeLow + (pocIdx + 0.5) * bucketSize;

            // Compute Value Area (expand from POC)
            long vaVolTarget = (long)(totalVol * valueAreaPct / 100.0);
            long vaVolAccum = bucketVol[pocIdx];
            int vaLoIdx = pocIdx, vaHiIdx = pocIdx;

            while (vaVolAccum < vaVolTarget)
            {
                long volBelow = (vaLoIdx > 0) ? bucketVol[vaLoIdx - 1] : 0;
                long volAbove = (vaHiIdx < numBuckets - 1) ? bucketVol[vaHiIdx + 1] : 0;
                if (volBelow == 0 && volAbove == 0) break;
                if (volBelow >= volAbove && vaLoIdx > 0) { vaLoIdx--; vaVolAccum += bucketVol[vaLoIdx]; }
                else if (vaHiIdx < numBuckets - 1) { vaHiIdx++; vaVolAccum += bucketVol[vaHiIdx]; }
                else if (vaLoIdx > 0) { vaLoIdx--; vaVolAccum += bucketVol[vaLoIdx]; }
                else break;
            }

            double vahPrice = rangeLow + (vaHiIdx + 1) * bucketSize;
            double valPrice = rangeLow + vaLoIdx * bucketSize;

            _current = new FRVPResult
            {
                POC = pocPrice,
                VAH = vahPrice,
                VAL = valPrice,
                RangeHigh = rangeHigh,
                RangeLow = rangeLow,
                TotalVolume = totalVol,
                Valid = true
            };

            // Build zones
            _current.Zones.Clear();
            _current.Zones.Add(new FRVPZone { Type = FRVPZoneType.POC, Price = pocPrice,
                Upper = pocPrice + bucketSize * 0.5, Lower = pocPrice - bucketSize * 0.5,
                Volume = maxVol, Strength = 1.0 });
            _current.Zones.Add(new FRVPZone { Type = FRVPZoneType.VAH, Price = vahPrice,
                Upper = vahPrice + bucketSize * 0.5, Lower = vahPrice - bucketSize * 0.5,
                Volume = (vaHiIdx >= 0 && vaHiIdx < numBuckets) ? bucketVol[vaHiIdx] : 0,
                Strength = maxVol > 0 ? (double)bucketVol[Math.Min(vaHiIdx, numBuckets - 1)] / maxVol : 0 });
            _current.Zones.Add(new FRVPZone { Type = FRVPZoneType.VAL, Price = valPrice,
                Upper = valPrice + bucketSize * 0.5, Lower = valPrice - bucketSize * 0.5,
                Volume = (vaLoIdx >= 0 && vaLoIdx < numBuckets) ? bucketVol[vaLoIdx] : 0,
                Strength = maxVol > 0 ? (double)bucketVol[Math.Min(vaLoIdx, numBuckets - 1)] / maxVol : 0 });

            // Scan for HVN/LVN outside value area
            for (int b = 0; b < numBuckets; b++)
            {
                if (b == pocIdx || (b >= vaLoIdx && b <= vaHiIdx)) continue;
                double strength = maxVol > 0 ? (double)bucketVol[b] / maxVol : 0;
                double price = rangeLow + (b + 0.5) * bucketSize;
                if (strength >= hvnThreshold)
                    _current.Zones.Add(new FRVPZone { Type = FRVPZoneType.HVN, Price = price,
                        Upper = rangeLow + (b + 1) * bucketSize, Lower = rangeLow + b * bucketSize,
                        Volume = bucketVol[b], Strength = strength });
                else if (strength <= lvnThreshold && bucketVol[b] > 0)
                    _current.Zones.Add(new FRVPZone { Type = FRVPZoneType.LVN, Price = price,
                        Upper = rangeLow + (b + 1) * bucketSize, Lower = rangeLow + b * bucketSize,
                        Volume = bucketVol[b], Strength = strength });
            }

            _lastCompute = DateTime.UtcNow;
            return true;
        }

        public bool AtPOC(double price, double tolerance) => Math.Abs(price - _current.POC) <= tolerance;
        public bool AtVAH(double price, double tolerance) => Math.Abs(price - _current.VAH) <= tolerance;
        public bool AtVAL(double price, double tolerance) => Math.Abs(price - _current.VAL) <= tolerance;

        public FRVPZone NearestZone(double price)
        {
            FRVPZone best = null;
            double minDist = double.MaxValue;
            foreach (var z in _current.Zones)
            {
                double dist = Math.Abs(price - z.Price);
                if (dist < minDist) { minDist = dist; best = z; }
            }
            return best;
        }

        public FRVPZone NearHVN(double price, double tolerance)
        {
            foreach (var z in _current.Zones)
                if (z.Type == FRVPZoneType.HVN && Math.Abs(price - z.Price) <= tolerance) return z;
            return null;
        }

        public FRVPZone NearLVN(double price, double tolerance)
        {
            foreach (var z in _current.Zones)
                if (z.Type == FRVPZoneType.LVN && Math.Abs(price - z.Price) <= tolerance) return z;
            return null;
        }
    }
}
