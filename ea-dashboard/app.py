"""YAMS Mate EA Dashboard — Client performance tracker."""
import json
import os
import sys
import ssl
import urllib.request
from datetime import datetime, timedelta
from collections import defaultdict

from flask import Flask, render_template, jsonify

app = Flask(__name__)

# Telegram config for sending alerts
TG_TOKEN = os.environ.get('TG_TOKEN', '8813121956:AAHiEmhe7L3ioaNq1AZ6xP4bVWCPmT0ksts')
TG_CHAT = os.environ.get('TG_CHAT', '457995870')

# EA Magic numbers
EA_NAMES = {
    777777: 'ScalpMaster',
    241107: 'ScalpXAU',
    20260723: 'FXPair',
    20241201: 'FXRE_Hybrid',
    20260716: 'FXYAMS_Ultimate1',
}

EA_COLORS = {
    'ScalpMaster': '#3b82f6',
    'ScalpXAU': '#10b981',
    'FXPair': '#f59e0b',
    'FXRE_Hybrid': '#8b5cf6',
    'FXYAMS_Ultimate1': '#ef4444',
}

EA_STRATEGIES = {
    'ScalpMaster': 'RSI + S/R + Pin Bars (M5)',
    'ScalpXAU': 'FRVP + Price Action + Sessions (M15)',
    'FXPair': 'EMA + Break & Retest + FRVP (M5)',
    'FXRE_Hybrid': 'Supply & Demand Zones (M5+M15)',
    'FXYAMS_Ultimate1': 'BB + Swing + TrendMode (M15)',
}

def get_mt5_data():
    """Pull data from MT5 via a helper script on the VPS."""
    try:
        import MetaTrader5 as mt5
        if not mt5.initialize():
            return None

        account = mt5.account_info()
        positions = mt5.positions_get()
        deals = mt5.history_deals_get(
            datetime.now() - timedelta(days=30),
            datetime.now()
        )

        data = {
            'account': {
                'balance': account.balance if account else 0,
                'equity': account.equity if account else 0,
                'profit': account.profit if account else 0,
                'margin': account.margin if account else 0,
                'free_margin': account.margin_free if account else 0,
                'leverage': account.leverage if account else 0,
                'server': account.server if account else '',
            },
            'positions': [],
            'trades': [],
            'ea_stats': {},
        }

        # Open positions
        if positions:
            for p in positions:
                data['positions'].append({
                    'ticket': p.ticket,
                    'symbol': p.symbol,
                    'type': 'BUY' if p.type == 0 else 'SELL',
                    'volume': p.volume,
                    'open_price': p.price_open,
                    'current_price': p.price_current,
                    'sl': p.sl,
                    'tp': p.tp,
                    'profit': p.profit,
                    'swap': p.swap,
                    'magic': p.magic,
                    'time': datetime.fromtimestamp(p.time).strftime('%Y-%m-%d %H:%M'),
                    'ea_name': EA_NAMES.get(p.magic, f'Unknown ({p.magic})'),
                })

        # Trade history (last 30 days)
        ea_stats = defaultdict(lambda: {
            'trades': 0, 'wins': 0, 'losses': 0,
            'total_profit': 0, 'total_loss': 0,
            'best_trade': 0, 'worst_trade': 0,
            'daily_pl': defaultdict(float),
            'symbols': set(),
        })

        if deals:
            for d in deals:
                if d.entry == 0:  # skip entry deals, only count exits
                    continue
                if d.magic not in EA_NAMES:
                    continue

                ea_name = EA_NAMES[d.magic]
                profit = d.profit + d.commission + d.swap
                ea = ea_stats[ea_name]

                ea['trades'] += 1
                if profit >= 0:
                    ea['wins'] += 1
                else:
                    ea['losses'] += 1
                ea['total_profit'] += profit if profit >= 0 else 0
                ea['total_loss'] += abs(profit) if profit < 0 else 0
                ea['best_trade'] = max(ea['best_trade'], profit)
                ea['worst_trade'] = min(ea['worst_trade'], profit)
                ea['symbols'].add(d.symbol)

                trade_date = datetime.fromtimestamp(d.time).strftime('%Y-%m-%d')
                ea['daily_pl'][trade_date] += profit

                data['trades'].append({
                    'ticket': d.ticket,
                    'symbol': d.symbol,
                    'type': 'BUY' if d.type == 0 else 'SELL',
                    'volume': d.volume,
                    'price': d.price,
                    'profit': profit,
                    'magic': d.magic,
                    'ea_name': ea_name,
                    'time': datetime.fromtimestamp(d.time).strftime('%Y-%m-%d %H:%M'),
                })

        # Format EA stats
        for ea_name, stats in ea_stats.items():
            total = stats['wins'] + stats['losses']
            win_rate = (stats['wins'] / total * 100) if total > 0 else 0
            avg_win = stats['total_profit'] / stats['wins'] if stats['wins'] > 0 else 0
            avg_loss = stats['total_loss'] / stats['losses'] if stats['losses'] > 0 else 0
            profit_factor = stats['total_profit'] / stats['total_loss'] if stats['total_loss'] > 0 else 0

            # Equity curve from daily P/L
            sorted_dates = sorted(stats['daily_pl'].keys())
            equity_curve = []
            running = data['account']['balance'] - sum(stats['daily_pl'].values())
            for date in sorted_dates:
                running += stats['daily_pl'][date]
                equity_curve.append({'date': date, 'equity': round(running, 2)})

            data['ea_stats'][ea_name] = {
                'trades': stats['trades'],
                'wins': stats['wins'],
                'losses': stats['losses'],
                'win_rate': round(win_rate, 1),
                'total_profit': round(stats['total_profit'], 2),
                'total_loss': round(stats['total_loss'], 2),
                'net_profit': round(stats['total_profit'] - stats['total_loss'], 2),
                'best_trade': round(stats['best_trade'], 2),
                'worst_trade': round(stats['worst_trade'], 2),
                'avg_win': round(avg_win, 2),
                'avg_loss': round(avg_loss, 2),
                'profit_factor': round(profit_factor, 2),
                'symbols': list(stats['symbols']),
                'strategy': EA_STRATEGIES.get(ea_name, ''),
                'color': EA_COLORS.get(ea_name, '#94a3b8'),
                'equity_curve': equity_curve,
                'daily_pl': {k: round(v, 2) for k, v in stats['daily_pl'].items()},
            }

        mt5.shutdown()
        return data

    except Exception as e:
        return {'error': str(e)}


# Mock data for when MT5 is not available
def get_mock_data():
    """Return mock data for development/testing."""
    return {
        'account': {
            'balance': 10548.52,
            'equity': 10561.91,
            'profit': 13.39,
            'margin': 0,
            'free_margin': 10561.91,
            'leverage': 1000,
            'server': 'VantageMarkets-Demo',
        },
        'positions': [
            {
                'ticket': 12345678,
                'symbol': 'XAUUSD+',
                'type': 'BUY',
                'volume': 0.02,
                'open_price': 4611.29,
                'current_price': 4617.50,
                'sl': 4595.00,
                'tp': 4645.00,
                'profit': 12.42,
                'swap': -0.97,
                'magic': 241107,
                'time': '2026-08-24 08:30',
                'ea_name': 'ScalpXAU',
            }
        ],
        'trades': [],
        'ea_stats': {
            'ScalpMaster': {
                'trades': 45, 'wins': 30, 'losses': 15,
                'win_rate': 66.7, 'net_profit': 312.50,
                'total_profit': 520.00, 'total_loss': 207.50,
                'best_trade': 45.20, 'worst_trade': -28.30,
                'avg_win': 17.33, 'avg_loss': -13.83,
                'profit_factor': 2.51,
                'symbols': ['XAUUSD+'],
                'strategy': 'RSI + S/R + Pin Bars (M5)',
                'color': '#3b82f6',
                'equity_curve': [],
                'daily_pl': {},
            },
            'ScalpXAU': {
                'trades': 32, 'wins': 22, 'losses': 10,
                'win_rate': 68.8, 'net_profit': 185.30,
                'total_profit': 410.00, 'total_loss': 224.70,
                'best_trade': 52.10, 'worst_trade': -35.40,
                'avg_win': 18.64, 'avg_loss': -22.47,
                'profit_factor': 1.82,
                'symbols': ['XAUUSD+'],
                'strategy': 'FRVP + Price Action + Sessions (M15)',
                'color': '#10b981',
                'equity_curve': [],
                'daily_pl': {},
            },
        },
    }


@app.route('/')
def dashboard():
    data = get_mt5_data() or get_mock_data()
    return render_template('dashboard.html', data=data)


@app.route('/api/data')
def api_data():
    data = get_mt5_data() or get_mock_data()
    return jsonify(data)


@app.route('/api/positions')
def api_positions():
    data = get_mt5_data() or get_mock_data()
    return jsonify(data.get('positions', []))


@app.route('/api/trades')
def api_trades():
    data = get_mt5_data() or get_mock_data()
    trades = data.get('trades', [])
    # Return last 50 trades
    return jsonify(trades[-50:])


@app.route('/api/ea-stats')
def api_ea_stats():
    data = get_mt5_data() or get_mock_data()
    return jsonify(data.get('ea_stats', {}))


@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=False)
