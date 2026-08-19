"""Configuration for Yams Radar system."""

from pathlib import Path
from dataclasses import dataclass, field

HERE = Path(__file__).parent.resolve()
PROJECT_ROOT = HERE.parent
CACHE_DIR = HERE / "cache"
CACHE_DIR.mkdir(exist_ok=True)

@dataclass
class Config:
    # Data fetching
    mt5_bars: int = 200         # bars per symbol (200 M5 bars = ~17h, covers 2+ trading sessions for ADX/trend)
    cache_expiry_hours: int = 2
    use_cache: bool = True

    # Scoring weights (sum = 1.0)
    weight_technical: float = 0.40
    weight_fundamental: float = 0.25
    weight_sentiment: float = 0.15
    weight_confluence: float = 0.20  # myFXbook, FXStreet, Finviz external data

    # Technical analysis
    adx_period: int = 14
    adx_threshold: int = 20
    ema_fast: int = 20
    ema_slow: int = 50
    rsi_period: int = 14
    bb_period: int = 20
    bb_std: float = 2.0
    macd_fast: int = 12
    macd_slow: int = 26
    macd_signal: int = 9
    swing_lookback: int = 20
    swing_cluster_pips: int = 5

    # Proxy for ForexFactory (WebShare residential proxy to bypass Cloudflare)
    proxy_url: str = ""

    # News feed URLs (RSS)
    rss_feeds: list = field(default_factory=lambda: [
        ("ForexFactory", "https://www.forexfactory.com/rss.php"),
    ])

    # Finviz URL (scraped)
    finviz_url: str = ""  # Disabled - using ForexFactory only

    # Economic calendar sources
    forex_factory_url: str = "https://www.forexfactory.com/calendar"
    investing_calendar_url: str = "https://www.investing.com/economic-calendar/"

    # COT report URL (CFTC)
    cot_url: str = "https://www.cftc.gov/dea/futures/deacmxsf.htm"

    # ─── Multi-LLM AI Consensus ─────────────────────────────────────
    # When enabled, replaces VADER keyword-based sentiment scoring with
    # multi-model LLM consensus (Claude + Gemini + DeepSeek + Grok).
    # Requires API keys in environment variables.
    use_ai_sentiment: bool = True
    ai_cache_ttl: int = 300          # seconds between fresh analyses (default 5 min)
    ai_model_timeout: int = 12       # seconds per-model timeout

