//+------------------------------------------------------------------+
//|                                        ScalpMaster_Pro.cBot        |
//|                          Professional Scalping Bot v2.0            |
//|                          Volume Profile + S/D + Order Flow         |
//+------------------------------------------------------------------+
using System;
using System.Linq;
using cAlgo.API;
using cAlgo.API.Internals;
using cAlgo.API.Collections;
using cAlgo.Indicators;

namespace cAlgo.Robots
{
    [Robot(TimeZone = TimeZones.UTC, AccessRights = AccessRights.FullAccess)]
    public class ScalpMaster_Pro : Robot
    {
        #region Parameters
        
        [Parameter("Risk Per Trade %", Group = "General", DefaultValue = 0.5)]
        public double RiskPerTradePct { get; set; }
        
        [Parameter("Max Daily Loss %", Group = "General", DefaultValue = 2.0)]
        public double MaxDailyLossPct { get; set; }
        
        [Parameter("Max Positions", Group = "General", DefaultValue = 1)]
        public int MaxPositions { get; set; }
        
        [Parameter("Max Trades/Day", Group = "General", DefaultValue = 5)]
        public int MaxTradesPerDay { get; set; }
        
        [Parameter("Entry Timeframe", Group = "Timeframes", DefaultValue = TimeFrame.Minute5)]
        public TimeFrame EntryTF { get; set; }
        
        [Parameter("HTF for Zones", Group = "Timeframes", DefaultValue = TimeFrame.Hour1)]
        public TimeFrame HTF { get; set; }
        
        // Volume Profile
        [Parameter("VP Bars", Group = "Volume Profile", DefaultValue = 100)]
        public int VP_Bars { get; set; }
        
        [Parameter("VP Bucket Pips", Group = "Volume Profile", DefaultValue = 0.25)]
        public double VP_BucketPips { get; set; }
        
        [Parameter("VP Value Area %", Group = "Volume Profile", DefaultValue = 70.0)]
        public double VP_VAAPct { get; set; }
        
        [Parameter("VP Tolerance (xATR)", Group = "Volume Profile", DefaultValue = 0.3)]
        public double VP_TolATR { get; set; }
        
        // S/D Zones
        [Parameter("Swing Lookback", Group = "Supply/Demand", DefaultValue = 3)]
        public int SD_SwingLen { get; set; }
        
        [Parameter("Min Zone Strength", Group = "Supply/Demand", DefaultValue = 2.0)]
        public double SD_MinStrength { get; set; }
        
        // Order Flow
        [Parameter("Min Buy Ratio", Group = "Order Flow", DefaultValue = 0.60)]
        public double OF_BuyMin { get; set; }
        
        [Parameter("Flow Lookback Bars", Group = "Order Flow", DefaultValue = 3)]
        public int OF_Bars { get; set; }
        
        // Risk
        [Parameter("SL (xATR)", Group = "Risk", DefaultValue = 1.2)]
        public double SL_ATR { get; set; }
        
        [Parameter("TP (xATR)", Group = "Risk", DefaultValue = 2.0)]
        public double TP_ATR { get; set; }
        
        [Parameter("Min R:R", Group = "Risk", DefaultValue = 1.5)]
        public double MinRR { get; set; }
        
        [Parameter("Use Break-Even", Group = "Risk", DefaultValue = true)]
        public bool UseBE { get; set; }
        
        [Parameter("BE Trigger (xATR)", Group = "Risk", DefaultValue = 0.8)]
        public double BE_TriggerATR { get; set; }
        
        [Parameter("Use Trailing", Group = "Risk", DefaultValue = true)]
        public bool UseTrail { get; set; }
        
        [Parameter("Trail Start (xATR)", Group = "Risk", DefaultValue = 1.0)]
        public double TrailStartATR { get; set; }
        
        [Parameter("Trail Step (xATR)", Group = "Risk", DefaultValue = 0.3)]
        public double TrailStepATR { get; set; }
        
        // Sessions
        [Parameter("London Start (GMT)", Group = "Sessions", DefaultValue = 7)]
        public int LondonStart { get; set; }
        
        [Parameter("London End (GMT)", Group = "Sessions", DefaultValue = 10)]
        public int LondonEnd { get; set; }
        
        [Parameter("NY Start (GMT)", Group = "Sessions", DefaultValue = 13)]
        public int NYStart { get; set; }
        
        [Parameter("NY End (GMT)", Group = "Sessions", DefaultValue = 16)]
        public int NYEnd { get; set; }
        
        #endregion
        
        #region Fields
        
        private double _atr;
        private double _dailyPnL;
        private int _dayTrades;
        private DateTime _lastDay;
        
        // VP levels
        private double _poc, _vah, _val;
        private bool _vpValid;
        
        // S/D zones
        private struct Zone
        {
            public double Top, Bottom, Mid, Strength;
            public bool IsSupply, Active;
        }
        private Zone[] _supply, _demand;
        private int _supplyCnt, _demandCnt;
        
        #endregion
        
        protected override void OnStart()
        {
            _atr = 0;
            _dailyPnL = 0;
            _dayTrades = 0;
            _lastDay = DateTime.MinValue;
            _vpValid = false;
            _supplyCnt = 0;
            _demandCnt = 0;
            _supply = new Zone[20];
            _demand = new Zone[20];
            
            Print($"=== ScalpMaster Pro v2.0 | {Symbol.Name} ===");
        }
        
        protected override void OnStop()
        {
            Print("=== ScalpMaster Pro Stopped ===");
        }
        
        protected override void OnBar()
        {
            UpdateATR();
            ResetDaily();
            ScanSDZones();
            
            if (CanTrade() && IsSession())
                CheckEntry();
        }
        
        protected override void OnTick()
        {
            UpdateATR();
            ManageOpen();
        }
        
        #region ATR
        
        private void UpdateATR()
        {
            var atr = Indicators.AverageTrueRange(EntryTF, 14);
            if (atr.Result.LastValue > 0)
                _atr = atr.Result.LastValue;
        }
        
        #endregion
        
        #region Daily Reset
        
        private void ResetDaily()
        {
            var today = Server.Time.Date;
            if (today != _lastDay)
            {
                _lastDay = today;
                _dailyPnL = 0;
                _dayTrades = 0;
            }
        }
        
        #endregion
        
        #region Can Trade
        
        private bool CanTrade()
        {
            if (Positions.Count(p => p.SymbolName == Symbol.Name) >= MaxPositions)
                return false;
            
            if (_dayTrades >= MaxTradesPerDay)
                return false;
            
            double maxLoss = Account.Balance * MaxDailyLossPct / 100.0;
            if (_dailyPnL <= -maxLoss)
                return false;
            
            return true;
        }
        
        private bool IsSession()
        {
            int h = Server.Time.Hour;
            return (h >= LondonStart && h < LondonEnd) || (h >= NYStart && h < NYEnd);
        }
        
        #endregion
        
        #region S/D Zones
        
        private void ScanSDZones()
        {
            _supplyCnt = 0;
            _demandCnt = 0;
            
            var bars = MarketData.GetBars(HTF, VP_Bars);
            var atr = Indicators.AverageTrueRange(HTF, 14);
            double thick = atr.Result.LastValue * 0.5;
            
            for (int i = SD_SwingLen; i < bars.Count - SD_SwingLen; i++)
            {
                // Swing High = Supply
                bool isHigh = true;
                for (int j = 1; j <= SD_SwingLen; j++)
                {
                    if (bars.HighPrices[i] <= bars.HighPrices[i - j] || 
                        bars.HighPrices[i] <= bars.HighPrices[i + j])
                    {
                        isHigh = false;
                        break;
                    }
                }
                
                if (isHigh && _supplyCnt < 20)
                {
                    var z = new Zone
                    {
                        Top = bars.HighPrices[i] + thick * 0.5,
                        Bottom = bars.HighPrices[i] - thick * 0.5,
                        Mid = bars.HighPrices[i],
                        IsSupply = true,
                        Active = true,
                        Strength = 1.0
                    };
                    
                    int ret = 0;
                    bool broken = false;
                    for (int k = i + 1; k < bars.Count; k++)
                    {
                        if (bars.LowPrices[k] <= z.Top && bars.HighPrices[k] >= z.Bottom) ret++;
                        if (bars.ClosePrices[k] > z.Top) { broken = true; break; }
                    }
                    
                    z.Strength = 1.0 + ret * 0.5;
                    if (z.Strength > 10) z.Strength = 10;
                    
                    if (z.Strength >= SD_MinStrength && !broken)
                    {
                        _supply[_supplyCnt] = z;
                        _supplyCnt++;
                    }
                }
                
                // Swing Low = Demand
                bool isLow = true;
                for (int j = 1; j <= SD_SwingLen; j++)
                {
                    if (bars.LowPrices[i] >= bars.LowPrices[i - j] || 
                        bars.LowPrices[i] >= bars.LowPrices[i + j])
                    {
                        isLow = false;
                        break;
                    }
                }
                
                if (isLow && _demandCnt < 20)
                {
                    var z = new Zone
                    {
                        Top = bars.LowPrices[i] + thick * 0.5,
                        Bottom = bars.LowPrices[i] - thick * 0.5,
                        Mid = bars.LowPrices[i],
                        IsSupply = false,
                        Active = true,
                        Strength = 1.0
                    };
                    
                    int ret = 0;
                    bool broken = false;
                    for (int k = i + 1; k < bars.Count; k++)
                    {
                        if (bars.HighPrices[k] >= z.Bottom && bars.LowPrices[k] <= z.Top) ret++;
                        if (bars.ClosePrices[k] < z.Bottom) { broken = true; break; }
                    }
                    
                    z.Strength = 1.0 + ret * 0.5;
                    if (z.Strength > 10) z.Strength = 10;
                    
                    if (z.Strength >= SD_MinStrength && !broken)
                    {
                        _demand[_demandCnt] = z;
                        _demandCnt++;
                    }
                }
            }
        }
        
        #endregion
        
        #region Volume Profile
        
        private void ComputeVP()
        {
            _vpValid = false;
            
            var bars = MarketData.GetBars(EntryTF, VP_Bars);
            if (bars.Count < VP_Bars) return;
            
            double minP = bars.HighPrices.Take(VP_Bars).Max();
            double maxP = bars.LowPrices.Take(VP_Bars).Min();
            
            // Actually need min of highs and max of lows for range
            minP = bars.LowPrices.Take(VP_Bars).Min();
            maxP = bars.HighPrices.Take(VP_Bars).Max();
            
            double range = maxP - minP;
            if (range < Symbol.PipSize) return;
            
            int nBuckets = Math.Min((int)(range / Symbol.PipSize) + 1, 300);
            double[] bv = new double[nBuckets];
            
            for (int i = 0; i < Math.Min(VP_Bars, bars.Count); i++)
            {
                double vol = bars.TickVolumes[i];
                if (vol <= 0) continue;
                
                int s = Math.Max(0, Math.Min((int)((bars.LowPrices[i] - minP) / Symbol.PipSize), nBuckets - 1));
                int e = Math.Max(0, Math.Min((int)((bars.HighPrices[i] - minP) / Symbol.PipSize), nBuckets - 1));
                int span = e - s + 1;
                if (span < 1) span = 1;
                
                double vpb = vol / span;
                for (int b = s; b <= e; b++)
                    if (b >= 0 && b < nBuckets) bv[b] += vpb;
            }
            
            // POC
            int pocI = 0;
            double maxV = 0;
            for (int i = 0; i < nBuckets; i++)
                if (bv[i] > maxV) { maxV = bv[i]; pocI = i; }
            
            _poc = minP + (pocI + 0.5) * Symbol.PipSize;
            
            // Value Area
            double totalV = bv.Sum();
            double vaTarget = totalV * VP_VAAPct / 100.0;
            double vaV = bv[pocI];
            int li = pocI, hi = pocI;
            
            while (vaV < vaTarget && (li > 0 || hi < nBuckets - 1))
            {
                double dv = (li > 0) ? bv[li - 1] : 0;
                double uv = (hi < nBuckets - 1) ? bv[hi + 1] : 0;
                if (dv >= uv && li > 0) { li--; vaV += bv[li]; }
                else if (hi < nBuckets - 1) { hi++; vaV += bv[hi]; }
                else break;
            }
            
            _val = minP + (li + 0.5) * Symbol.PipSize;
            _vah = minP + (hi + 0.5) * Symbol.PipSize;
            _vpValid = true;
        }
        
        #endregion
        
        #region Order Flow
        
        private void GetFlow(out double buyP, out double sellP)
        {
            buyP = 0;
            sellP = 0;
            
            var bars = MarketData.GetBars(EntryTF, OF_Bars);
            if (bars.Count < OF_Bars) return;
            
            int buys = 0, sells = 0;
            for (int i = 0; i < OF_Bars; i++)
            {
                if (bars.ClosePrices[i] > bars.OpenPrices[i]) buys++;
                else if (bars.ClosePrices[i] < bars.OpenPrices[i]) sells++;
            }
            
            double total = buys + sells;
            if (total > 0)
            {
                buyP = buys / total;
                sellP = sells / total;
            }
        }
        
        #endregion
        
        #region Entry
        
        private void CheckEntry()
        {
            if (_atr <= 0) return;
            
            // Refresh VP periodically
            ComputeVP();
            if (!_vpValid) return;
            
            double price = Symbol.Bid;
            double tol = _atr * VP_TolATR;
            
            GetFlow(out double buyP, out double sellP);
            
            // BUY: at POC/VAL + demand zone + buy flow
            bool atPOC = Math.Abs(price - _poc) < tol;
            bool atVAL = Math.Abs(price - _val) < tol;
            
            if ((atPOC || atVAL) && buyP >= OF_BuyMin)
            {
                for (int i = 0; i < _demandCnt; i++)
                {
                    if (!_demand[i].Active) continue;
                    if (price >= _demand[i].Bottom && price <= _demand[i].Top && 
                        _demand[i].Strength >= SD_MinStrength)
                    {
                        SendBuy(price, atPOC ? "POC" : "VAL", _demand[i].Strength, buyP);
                        return;
                    }
                }
            }
            
            // SELL: at POC/VAH + supply zone + sell flow
            bool atVAH = Math.Abs(price - _vah) < tol;
            
            if ((atPOC || atVAH) && sellP >= (1.0 - OF_BuyMin))
            {
                for (int i = 0; i < _supplyCnt; i++)
                {
                    if (!_supply[i].Active) continue;
                    if (price >= _supply[i].Bottom && price <= _supply[i].Top && 
                        _supply[i].Strength >= SD_MinStrength)
                    {
                        SendSell(price, atVAH ? "VAH" : "POC", _supply[i].Strength, sellP);
                        return;
                    }
                }
            }
        }
        
        #endregion
        
        #region Trade Execution
        
        private void SendBuy(double price, string vpLevel, double str, double flow)
        {
            double sl = price - _atr * SL_ATR;
            double tp = price + _atr * TP_ATR;
            
            double rr = (tp - price) / (price - sl);
            if (rr < MinRR) return;
            
            double lots = CalcLots(price - sl);
            if (lots <= 0) return;
            
            var result = Execute.MarketBuy(Symbol.Name, lots, "SCALP_BUY");
            
            if (result.IsSuccessful)
            {
                // Set SL/TP
                var pos = Positions.Find(result.Position.Id);
                if (pos != null)
                {
                    ModifyPosition(pos, sl, tp);
                }
                
                Print($"BUY: {lots} lots @ {price} | {vpLevel} str={str:F1} flow={flow:P0} | SL={sl:F2} TP={tp:F2}");
                _dayTrades++;
            }
        }
        
        private void SendSell(double price, string vpLevel, double str, double flow)
        {
            double sl = price + _atr * SL_ATR;
            double tp = price - _atr * TP_ATR;
            
            double rr = (price - tp) / (sl - price);
            if (rr < MinRR) return;
            
            double lots = CalcLots(sl - price);
            if (lots <= 0) return;
            
            var result = Execute.MarketSell(Symbol.Name, lots, "SCALP_SELL");
            
            if (result.IsSuccessful)
            {
                var pos = Positions.Find(result.Position.Id);
                if (pos != null)
                {
                    ModifyPosition(pos, sl, tp);
                }
                
                Print($"SELL: {lots} lots @ {price} | {vpLevel} str={str:F1} flow={flow:P0} | SL={sl:F2} TP={tp:F2}");
                _dayTrades++;
            }
        }
        
        private double CalcLots(double slDist)
        {
            double risk = Account.Balance * RiskPerTradePct / 100.0;
            double tv = Symbol.TickValue;
            double ts = Symbol.TickSize;
            
            if (tv <= 0 || ts <= 0 || slDist <= 0) return 0;
            
            double lots = risk / (slDist / ts * tv);
            
            lots = Math.Floor(lots / Symbol.VolumeInstrumentsStep) * Symbol.VolumeInstrumentsStep;
            lots = Math.Max(lots, Symbol.VolumeInstrumentsMin);
            lots = Math.Min(lots, Symbol.VolumeInstrumentsMax);
            
            return lots;
        }
        
        #endregion
        
        #region Manage
        
        private void ManageOpen()
        {
            foreach (var pos in Positions.Where(p => p.SymbolName == Symbol.Name))
            {
                double price = pos.TradeType == TradeType.Buy ? Symbol.Bid : Symbol.Ask;
                
                // Break-even
                if (UseBE)
                {
                    if (pos.TradeType == TradeType.Buy && 
                        price >= pos.EntryPrice + _atr * BE_TriggerATR && 
                        pos.StopLoss < pos.EntryPrice)
                    {
                        ModifyPosition(pos, pos.EntryPrice + _atr * 0.1, pos.TakeProfit);
                    }
                    else if (pos.TradeType == TradeType.Sell && 
                             price <= pos.EntryPrice - _atr * BE_TriggerATR && 
                             (pos.StopLoss > pos.EntryPrice || pos.StopLoss == null))
                    {
                        ModifyPosition(pos, pos.EntryPrice - _atr * 0.1, pos.TakeProfit);
                    }
                }
                
                // Trailing
                if (UseTrail)
                {
                    double start = _atr * TrailStartATR;
                    double step = _atr * TrailStepATR;
                    
                    if (pos.TradeType == TradeType.Buy && price - pos.EntryPrice >= start)
                    {
                        double newSL = price - step;
                        if (newSL > pos.StopLoss)
                            ModifyPosition(pos, newSL, pos.TakeProfit);
                    }
                    else if (pos.TradeType == TradeType.Sell && pos.EntryPrice - price >= start)
                    {
                        double newSL = price + step;
                        if (newSL < pos.StopLoss || pos.StopLoss == null)
                            ModifyPosition(pos, newSL, pos.TakeProfit);
                    }
                }
            }
        }
        
        #endregion
    }
}
