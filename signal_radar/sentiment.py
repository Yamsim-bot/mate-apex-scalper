"""Sentiment Analysis — ForexFactory-only news feed
with VADER scoring and cross-reference accuracy."""

from datetime import datetime, timezone, timedelta
from dataclasses import dataclass
from typing import Optional
from collections import Counter
import re


@dataclass
class NewsHeadline:
    source: str
    title: str
    url: str
    published: str
    sentiment_score: float      # -1.0 (very negative) to +1.0 (very positive)
    keywords: list[str]
    relevance: float            # 0-1 how relevant to trading


@dataclass
class SourceAccuracy:
    """Tracks how reliable a source's sentiment signals have been."""
    source: str
    articles_scraped: int
    avg_relevance: float
    unique_topics: int
    credibility_score: float    # 0-1 based on specificity & relevance


@dataclass
class CrossReferenceEntry:
    topic: str
    source_sentiments: dict[str, float]   # source_name -> sentiment_score
    consensus: str                       # 'bullish', 'bearish', 'neutral', 'mixed'
    agreement_level: float               # 0.0 (total disagreement) to 1.0 (total agreement)
    discrepancy_flag: bool               # True when sources strongly disagree


class SentimentResult:
    """Result of multi-source sentiment analysis."""
    def __init__(self,
                 overall_score: float = 0.0,
                 headlines: list[NewsHeadline] = None,
                 trending_topics: list[str] = None,
                 dovish_count: int = 0,
                 hawkish_count: int = 0,
                 risk_on_count: int = 0,
                 risk_off_count: int = 0,
                 source_breakdown: dict[str, float] = None,
                 cross_references: list[CrossReferenceEntry] = None,
                 source_accuracy: list[SourceAccuracy] = None,
                 ai_analysis: 'Optional[ConsensusResult]' = None):
        self.overall_score = overall_score
        self.headlines = headlines or []
        self.trending_topics = trending_topics or []
        self.dovish_count = dovish_count
        self.hawkish_count = hawkish_count
        self.risk_on_count = risk_on_count
        self.risk_off_count = risk_off_count
        self.source_breakdown = source_breakdown or {}
        self.cross_references = cross_references or []
        self.source_accuracy = source_accuracy or []
        self.ai_analysis = ai_analysis
        self.source_type = 'sample'  # 'live' or 'sample' — set by analyze()


# ─── RSS / Scraped Sources ──────────────────────────────────────────────
#
# Only sources that currently work (verified 2026-07-19):
#   Investing.com RSS   → 10 entries, forex+general news
#   ForexLive RSS       → 25 entries, forex-specific news
#   MarketWatch RSS     → 10 entries, market/business news
#   CNBC RSS            → 30 entries, general market news
#   Finviz scrape       → HTML page, parsed with BeautifulSoup
#
# Removed (HTTP 403 / broken scraper):
#   DailyFX, FXStreet, CME Group, myFXbook, TradingView, OPEC, ForexFactory

RSS_FEEDS = [
    ('Investing.com', 'https://www.investing.com/rss/news.rss'),
    ('ForexLive', 'https://www.forexlive.com/feed/'),
    ('MarketWatch', 'https://feeds.marketwatch.com/marketwatch/topstories'),
    ('CNBC', 'https://www.cnbc.com/id/100003114/device/rss/rss.html'),
]

# Web-scraped sources
SCRAPED_SOURCES = {
    # Finviz removed - ForexFactory only
}

# ─── Keyword categories ─────────────────────────────────────────────────

DOVISH_KEYWORDS = [
    'dovish', 'rate cut', 'easing', 'stimulus', 'lower rates',
    'accommodative', 'quantitative easing', 'loose policy',
    'soft landing', 'recession fears', 'slowdown', 'inflation peak',
    'bearish', 'selloff', 'risk-off', 'safe haven', 'decline',
]

HAWKISH_KEYWORDS = [
    'hawkish', 'rate hike', 'tightening', 'taper', 'higher rates',
    'restrictive', 'quantitative tightening', 'firm policy',
    'overheating', 'inflation concern', 'supply chain',
    'bullish', 'rally', 'risk-on', 'growth', 'expansion',
]

RISK_ON_KEYWORDS = [
    'risk-on', 'rally', 'bull market', 'all-time high', 'record high',
    'optimism', 'recovery', 'expansion', 'boom', 'upgrade',
    'outperform', 'buyback', 'dividend increase',
]

RISK_OFF_KEYWORDS = [
    'risk-off', 'crash', 'correction', 'bear market', 'recession',
    'pessimism', 'contraction', 'slowdown', 'default', 'downgrade',
    'volatility', 'uncertainty', 'crisis', 'emergency',
]

# Commodity / Oil keywords
COMMODITY_BULLISH_KEYWORDS = [
    'oil rally', 'crude surge', 'supply cut', 'production cut',
    'opec+ cut', 'supply constraint', 'inventory draw', 'bullish crude',
    'gold rally', 'gold surge', 'precious metals', 'safe haven bid',
]

COMMODITY_BEARISH_KEYWORDS = [
    'oil crash', 'crude drop', 'supply glut', 'oversupply',
    'demand concern', 'economic slowdown', 'inventory build',
    'gold decline', 'silver drop', 'precious metals selloff',
]

# ─── Source credibility weights (0-1) ───────────────────────────────────
# Based on: specificity, timeliness, editorial quality
SOURCE_CREDIBILITY = {
    'Investing.com': 0.85,
    'ForexLive': 0.90,
    'MarketWatch': 0.80,
    'CNBC': 0.85,
    # Finviz removed
}


def analyze(quick: bool = False) -> SentimentResult:
    """Multi-source sentiment analysis across all news feeds.

    Args:
        quick: If True, skip live fetching and use sample headlines (instant).
               Use False for the News tab where accuracy matters more than speed.
    """
    if quick:
        # Instant path: use pre-generated sample headlines, no network calls
        headlines = _generate_sample_headlines()
        source_type = 'sample'
    else:
        # Full path: fetch from live sources (RSS + scrapers, ~15-20s)
        headlines = _fetch_headlines()
        if not headlines:
            headlines = _generate_sample_headlines()
            source_type = 'sample'
        else:
            source_type = 'live'

    # Score each headline with VADER + financial lexicon blend
    scores = _blended_sentiment([h.title for h in headlines])
    for i, h in enumerate(headlines):
        h.sentiment_score = scores[i] if i < len(scores) else 0.0
        h.keywords = _extract_keywords(h.title)

    # ── Aggregation ──
    overall = _aggregate_sentiment(headlines)
    trending = _trending_topics(headlines)
    dovish = sum(1 for h in headlines if any(k in h.title.lower() for k in DOVISH_KEYWORDS))
    hawkish = sum(1 for h in headlines if any(k in h.title.lower() for k in HAWKISH_KEYWORDS))
    risk_on = sum(1 for h in headlines if any(k in h.title.lower() for k in RISK_ON_KEYWORDS))
    risk_off = sum(1 for h in headlines if any(k in h.title.lower() for k in RISK_OFF_KEYWORDS))

    # Source breakdown
    src_brk = _build_source_breakdown(headlines)

    # Cross-reference: detect when sources disagree on same topic
    cross_refs = _cross_reference_sources(headlines)

    # Source accuracy / credibility assessment
    src_accuracy = _assess_source_accuracy(headlines)

    result = SentimentResult(
        overall_score=round(overall, 1),
        headlines=headlines[:50],
        trending_topics=trending,
        dovish_count=dovish,
        hawkish_count=hawkish,
        risk_on_count=risk_on,
        risk_off_count=risk_off,
        source_breakdown=src_brk,
        cross_references=cross_refs,
        source_accuracy=src_accuracy,
    )
    result.source_type = source_type
    return result



def _fetch_forexfactory_headlines() -> list[NewsHeadline]:
    """Fetch news headlines from ForexFactory RSS feed."""
    headlines = []
    try:
        import feedparser
        import socket
        old_to = socket.getdefaulttimeout()
        socket.setdefaulttimeout(8)
        try:
            feed = feedparser.parse('https://www.forexfactory.com/rss.php')
        finally:
            socket.setdefaulttimeout(old_to)
        for entry in feed.entries[:20]:
            published = (entry.get('published', '') or entry.get('updated', '') or '')
            title = entry.get('title', '')
            if not title:
                continue
            headlines.append(NewsHeadline(
                source='ForexFactory',
                title=title,
                url=entry.get('link', ''),
                published=published,
                sentiment_score=0.0,
                keywords=[],
                relevance=_calc_relevance(title),
            ))
    except Exception:
        pass
    return headlines

def _fetch_headlines() -> list[NewsHeadline]:
    """Fetch news headlines from ALL sources — RSS + scraped."""
    headlines = []

    # ── RSS feeds (feedparser) with parallel fetching ──
    try:
        import feedparser
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading
        rss_lock = threading.Lock()

        def _parse_rss(source, url):
            """Parse one RSS feed with timeout."""
            try:
                # Set socket timeout so feedparser doesn't hang
                import socket
                old_to = socket.getdefaulttimeout()
                socket.setdefaulttimeout(5)
                try:
                    feed = feedparser.parse(url)
                finally:
                    socket.setdefaulttimeout(old_to)
                local_hl = []
                for entry in feed.entries[:10]:
                    published = (entry.get('published', '')
                                 or entry.get('updated', '') or '')
                    title = entry.get('title', '')
                    if not title:
                        continue
                    local_hl.append(NewsHeadline(
                        source=source,
                        title=title,
                        url=entry.get('link', ''),
                        published=published,
                        sentiment_score=0.0,
                        keywords=[],
                        relevance=_calc_relevance(title),
                    ))
                if local_hl:
                    with rss_lock:
                        headlines.extend(local_hl)
            except Exception:
                pass

        with ThreadPoolExecutor(max_workers=6) as pool:
            futures = [pool.submit(_parse_rss, source, url) for source, url in RSS_FEEDS]
            for f in as_completed(futures, timeout=15):
                try:
                    f.result()
                except Exception:
                    pass
    except Exception:
        pass

    # ── Finviz + Scraped sources (concurrent, short timeouts) ──
    try:
        from concurrent.futures import ThreadPoolExecutor, as_completed
        import threading
        scrape_lock = threading.Lock()

        def _scrape_source(name):
            """Run the appropriate scraper for a source name."""
            try:
                scrapers = {
                    'Finviz': _fetch_finviz,
                }
                scraper = scrapers.get(name)
                if scraper:
                    result = scraper()
                    if result:
                        with scrape_lock:
                            headlines.extend(result)
            except Exception:
                pass

        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(_scrape_source, name)
                       for name in ['Finviz']]
            for f in as_completed(futures, timeout=15):
                try:
                    f.result()
                except Exception:
                    pass
    except Exception:
        pass

    return headlines


# ─── Individual Source Fetchers ─────────────────────────────────────────



def _financial_sentiment(text: str) -> float:
    """Score a headline using the financial-market lexicon."""
    text_lower = text.lower()
    score = 0.0
    count = 0

    # Multi-word phrases (check first)
    for phrase, weight in {**FINANCIAL_BULLISH, **FINANCIAL_BEARISH}.items():
        if ' ' in phrase and phrase in text_lower:
            score += weight
            count += 1

    # Single-word matches (avoid double-counting phrases already matched)
    words = text_lower.split()
    for word in words:
        word = word.strip('.,!?()[]{}"\':;')
        if word in FINANCIAL_BULLISH and word not in [w for w in FINANCIAL_BULLISH if ' ' in w]:
            score += FINANCIAL_BULLISH[word]
            count += 1
        elif word in FINANCIAL_BEARISH and word not in [w for w in FINANCIAL_BEARISH if ' ' in w]:
            score += FINANCIAL_BEARISH[word]
            count += 1

    if count == 0:
        return 0.0
    # Normalise to roughly [-1, 1] and clamp
    avg = score / max(count, 1)
    return max(-1.0, min(1.0, avg * 1.5))  # scale up to saturate


def _blended_sentiment(titles: list[str]) -> list[float]:
    """Score headlines using VADER + financial lexicon blend.

    VADER handles general language. The financial lexicon catches
    domain-specific terms VADER would score as neutral.
    Final score = 0.4 * VADER + 0.6 * financial
    """
    vader_scores = _vader_scores(titles)
    blended = []
    for i, t in enumerate(titles):
        fin = _financial_sentiment(t)
        # Blend: VADER for general, financial for domain
        # Use whichever has stronger signal (further from zero)
        if abs(fin) > abs(vader_scores[i]) * 2:
            blended.append(fin)
        elif abs(vader_scores[i]) > abs(fin) * 2:
            blended.append(vader_scores[i])
        else:
            blended.append(0.4 * vader_scores[i] + 0.6 * fin)
    return blended


def _vader_scores(titles: list[str]) -> list[float]:
    """Score headlines using VADER sentiment. Falls back to simple polarity."""
    try:
        from nltk.sentiment import SentimentIntensityAnalyzer
        try:
            sia = SentimentIntensityAnalyzer()
        except LookupError:
            import nltk
            nltk.download('vader_lexicon', quiet=True)
            sia = SentimentIntensityAnalyzer()

        scores = []
        for t in titles:
            vs = sia.polarity_scores(t)
            scores.append(vs['compound'])
        return scores
    except Exception:
        return [_simple_polarity(t) for t in titles]


def _simple_polarity(text: str) -> float:
    """Simple polarity fallback when VADER unavailable."""
    positive = ['up', 'gain', 'rise', 'rally', 'bullish', 'strong', 'growth',
                'positive', 'surge', 'breakout', 'higher', 'upgrade', 'outperform']
    negative = ['down', 'loss', 'fall', 'decline', 'bearish', 'weak', 'slump',
                'negative', 'drop', 'crash', 'lower', 'downgrade', 'underperform']
    text_lower = text.lower()
    pos_count = sum(1 for w in positive if w in text_lower)
    neg_count = sum(1 for w in negative if w in text_lower)
    total = pos_count + neg_count
    if total == 0:
        return 0.0
    return (pos_count - neg_count) / total


# ─── Keyword / Relevance ────────────────────────────────────────────────


def _extract_keywords(text: str) -> list[str]:
    """Extract trading-relevant keywords from headline."""
    keywords = []
    text_lower = text.lower()
    for word in text_lower.split():
        word = word.strip('.,!?()[]{}"\':;')
        if len(word) > 3 and word not in ('the', 'this', 'that', 'with', 'from',
                                            'have', 'been', 'will', 'were', 'what',
                                            'when', 'where', 'which', 'their'):
            keywords.append(word)
    return keywords[:10]


def _calc_relevance(title: str) -> float:
    """Estimate relevance of a headline to trading (0-1)."""
    trading_keywords = [
        'forex', 'fx', 'eur', 'usd', 'gbp', 'jpy', 'aud', 'nzd',
        'cad', 'chf', 'cpi', 'gdp', 'nfp', 'fed', 'ecb', 'boe',
        'boj', 'rba', 'rbnz', 'stock', 'index', 'commodity',
        'oil', 'gold', 'bond', 'yield', 'rate', 'inflation',
        'market', 'trading', 'bull', 'bear', 'rally', 'crash',
        'opec', 'cme', 'futures', 'fomc', 'treasury', 'spx',
        # FXStreet / TradingView specific
        'technical', 'analysis', 'fibonacci', 'support', 'resistance',
        'breakout', 'retracement', 'divergence', 'candle', 'pattern',
        'entry', 'target', 'stop loss', 'take profit', 'signal',
    ]
    title_lower = title.lower()
    matches = sum(1 for kw in trading_keywords if kw in title_lower)
    return min(1.0, matches / 5)


def _build_source_breakdown(headlines: list[NewsHeadline]) -> dict[str, float]:
    """Compute per-source average sentiment."""
    src_brk = {}
    for h in headlines:
        if h.source not in src_brk:
            src_brk[h.source] = []
        src_brk[h.source].append(h.sentiment_score)
    return {s: round(sum(v) / len(v), 2) for s, v in src_brk.items()}


# ─── Cross-Reference Logic ──────────────────────────────────────────────


def _cross_reference_sources(headlines: list[NewsHeadline]) -> list[CrossReferenceEntry]:
    """Detect same topics across multiple sources and flag discrepancies.

    Groups headlines by topic (common keywords), compares sentiment
    per source, and flags when sources strongly disagree.
    """
    if not headlines:
        return []

    # Build keyword → list of (source, sentiment) mappings
    topic_map: dict[str, list[tuple[str, float]]] = {}
    for h in headlines:
        for kw in h.keywords:
            kw_lower = kw.lower()
            if kw_lower not in topic_map:
                topic_map[kw_lower] = []
            topic_map[kw_lower].append((h.source, h.sentiment_score))

    # Only care about topics mentioned by 2+ different sources
    entries = []
    for topic, pairs in topic_map.items():
        unique_sources = set(s for s, _ in pairs)
        if len(unique_sources) < 2:
            continue

        # Per-source average sentiment for this topic
        src_sent: dict[str, float] = {}
        for s, score in pairs:
            if s not in src_sent:
                src_sent[s] = []
            src_sent[s].append(score)
        src_avg = {s: sum(v) / len(v) for s, v in src_sent.items()}

        # Consensus: bullish, bearish, or mixed
        vals = list(src_avg.values())
        pos = sum(1 for v in vals if v > 0.1)
        neg = sum(1 for v in vals if v < -0.1)
        neu = sum(1 for v in vals if -0.1 <= v <= 0.1)

        if pos > neg and pos >= len(vals) * 0.6:
            consensus = 'bullish'
        elif neg > pos and neg >= len(vals) * 0.6:
            consensus = 'bearish'
        elif neu >= len(vals) * 0.6:
            consensus = 'neutral'
        else:
            consensus = 'mixed'

        # Agreement level: standard deviation of sentiments (lower = more agreement)
        if len(vals) >= 2:
            mean_v = sum(vals) / len(vals)
            variance = sum((v - mean_v) ** 2 for v in vals) / len(vals)
            std_dev = variance ** 0.5
            agreement = max(0.0, min(1.0, 1.0 - std_dev))
        else:
            agreement = 1.0

        # Flag discrepancy: two or more sources disagree in sign
        pos_sources = sum(1 for v in vals if v > 0.1)
        neg_sources = sum(1 for v in vals if v < -0.1)
        discrepancy = (pos_sources >= 1 and neg_sources >= 1)

        if discrepancy or agreement < 0.5:
            entries.append(CrossReferenceEntry(
                topic=topic,
                source_sentiments=src_avg,
                consensus=consensus,
                agreement_level=round(agreement, 2),
                discrepancy_flag=discrepancy,
            ))

    # Return top 15 most interesting discrepancies first
    entries.sort(key=lambda e: (-e.discrepancy_flag, e.agreement_level))
    return entries[:15]


def _assess_source_accuracy(headlines: list[NewsHeadline]) -> list[SourceAccuracy]:
    """Assess source quality metrics based on scraped data."""
    source_data: dict[str, dict] = {}

    for h in headlines:
        if h.source not in source_data:
            source_data[h.source] = {
                'articles': 0,
                'relevance_sum': 0.0,
                'topics': set(),
            }
        source_data[h.source]['articles'] += 1
        source_data[h.source]['relevance_sum'] += h.relevance
        source_data[h.source]['topics'].update(h.keywords)

    results = []
    for source, data in source_data.items():
        n = data['articles']
        avg_rel = data['relevance_sum'] / n if n > 0 else 0.0
        n_unique = len(data['topics'])

        # Credibility = weighted blend of source credibility + observed relevance
        base_cred = SOURCE_CREDIBILITY.get(source, 0.5)
        relevance_bonus = avg_rel * 0.15  # +0.15 if all headlines are relevant
        credibility = min(1.0, base_cred + relevance_bonus)

        results.append(SourceAccuracy(
            source=source,
            articles_scraped=n,
            avg_relevance=round(avg_rel, 2),
            unique_topics=n_unique,
            credibility_score=round(credibility, 2),
        ))

    results.sort(key=lambda r: -r.credibility_score)
    return results


# ─── Aggregation ────────────────────────────────────────────────────────


def _aggregate_sentiment(headlines: list[NewsHeadline]) -> float:
    """Aggregate individual headline scores into an overall -100 to +100 score."""
    if not headlines:
        return 0.0

    total_weight = 0.0
    weighted_sum = 0.0
    for h in headlines:
        # Blend: relevance + source credibility as weight
        base_weight = SOURCE_CREDIBILITY.get(h.source, 0.5)
        w = h.relevance * base_weight
        weighted_sum += h.sentiment_score * w
        total_weight += w

    if total_weight == 0:
        return 0.0

    avg = weighted_sum / total_weight
    return float(avg * 100)


def _trending_topics(headlines: list[NewsHeadline]) -> list[str]:
    """Identify trending topics by keyword frequency."""
    all_words = []
    for h in headlines:
        all_words.extend(h.keywords)
    freq = Counter(all_words)
    return [word for word, _ in freq.most_common(10)]


# ─── Sample Data ────────────────────────────────────────────────────────


def _generate_sample_headlines() -> list[NewsHeadline]:
    """Generate sample news headlines as fallback when live fetching fails."""
    now = datetime.now(timezone.utc).isoformat()
    samples = [
        # Investing.com — trusted economic news
        ('Investing.com', 'Wall Street rallies on tech earnings, S&P 500 holds near highs'),
        ('Investing.com', 'US Dollar Index holds steady ahead of CPI release'),
        ('Investing.com', 'Treasury yields dip as market prices in September rate cut'),
        ('Investing.com', 'Fed officials push back on rapid rate cut expectations'),
        ('Investing.com', 'European equities mixed amid growth concerns'),
        # ForexLive — forex-specific news
        ('ForexLive', 'Fed signals patience on rate cuts as inflation remains sticky'),
        ('ForexLive', 'EURUSD extends decline on stronger US data'),
        ('ForexLive', 'Gold holds near record highs on geopolitical tensions'),
        ('ForexLive', 'AUDUSD rises on RBA hawkish hold, iron ore rebound'),
        ('ForexLive', 'USDJPY tests key resistance as BoJ holds steady'),
        ('ForexLive', 'GBPUSD steady ahead of UK GDP data'),
        ('ForexLive', 'Crude oil extends losses on demand concerns'),
        ('ForexLive', 'EURUSD technical: key support at 1.1050 holds, bounce expected'),
        ('ForexLive', 'GBPUSD finds resistance at 1.2900 ahead of BOE testimony'),
        ('ForexLive', 'Gold technical analysis: bulls eye $2,420 breakout'),
        # MarketWatch — broader markets
        ('MarketWatch', 'S&P 500 extends winning streak on rate cut optimism'),
        ('MarketWatch', 'Nasdaq 100 breaks resistance as tech leads market rally'),
        ('MarketWatch', 'Brent crude consolidates above $85 as OPEC maintains outlook'),
        # Finviz — market data
        ('Finviz', 'NFP expectations signal steady labor market'),
        ('Finviz', 'AAPL upgrades target on AI product cycle optimism'),
        ('Finviz', 'Crude oil supply concerns persist on geopolitical risks'),
        ('Finviz', 'SP500 momentum remains positive on rate cut hopes'),
        # CNBC — broad market coverage
        ('CNBC', 'US Dollar Index holds steady ahead of CPI release'),
        ('CNBC', 'Treasury yields dip as market prices in September rate cut'),
        ('CNBC', 'Fed officials push back on rapid rate cut expectations'),
    ]

    # Day-of-week / time-of-day variation
    dow = datetime.now(timezone.utc).weekday()
    hod = datetime.now(timezone.utc).hour
    day_suffix = 'outlook' if dow < 5 else 'weekend wrap'
    extra = [
        ('ForexLive', f'Forex market {day_suffix}: key levels to watch'),
        ('ForexLive', f'Session highlights: {"Asian" if hod < 8 else "London" if hod < 13 else "New York"} market update'),
        ('Investing.com', f"Today's economic calendar: {'busy with Fed speakers' if dow < 4 else 'light data day'}"),
    ]
    samples.extend(extra)

    return [
        NewsHeadline(source=s, title=t, url='', published=now,
                     sentiment_score=0.0, keywords=[], relevance=_calc_relevance(t))
        for s, t in samples
    ]


# ─── AI Enhancement ───────────────────────────────────────────────────────
#
# Optional: replace VADER keyword scoring with multi-LLM consensus
# (Claude + Gemini + DeepSeek + Grok) for much smarter analysis.
# Falls back gracefully if no API keys are configured.


def enhance_with_ai(sent_result: SentimentResult,
                    live_prices: Optional[dict] = None,
                    calendar_events: Optional[list] = None,
                    cfg: 'Optional[Config]' = None) -> SentimentResult:
    """Enhance a SentimentResult with multi-LLM consensus analysis.

    Calls all available AI models in parallel with the collected headlines,
    prices, and calendar context. The AI consensus score replaces the VADER-
    derived overall_score when successful.

    Args:
        sent_result: Existing SentimentResult from analyze()
        live_prices: Dict of {symbol: price} from fetch_live_prices
        calendar_events: List of CalendarEvent from eco_calendar.analyze
        cfg: Config object (to check use_ai_sentiment flag)

    Returns:
        The same SentimentResult (mutated in-place) with AI enhancements attached.
        If AI is unavailable or disabled, returns unchanged.
    """
    # Check if AI is enabled in config
    if cfg is not None and not getattr(cfg, 'use_ai_sentiment', True):
        return sent_result

    # Lazy import — AI analyst is optional
    try:
        from .ai_analyst import run_ai_consensus, ConsensusResult
    except ImportError:
        return sent_result  # ai_analyst module not available

    if live_prices is None:
        live_prices = {}
    if calendar_events is None:
        calendar_events = []

    # Need at least some headlines to analyse
    if not sent_result.headlines:
        return sent_result

    consensus = run_ai_consensus(
        headlines=sent_result.headlines,
        live_prices=live_prices,
        calendar_events=calendar_events,
    )

    if consensus is not None:
        # Override the VADER score with AI consensus
        sent_result.overall_score = consensus.overall_score
        sent_result.ai_analysis = consensus

        # Also update the risk/dovish/hawkish counts from AI output
        if consensus.risk_appetite == 'risk_on':
            sent_result.risk_on_count = max(sent_result.risk_on_count, 3)
        elif consensus.risk_appetite == 'risk_off':
            sent_result.risk_off_count = max(sent_result.risk_off_count, 3)

    return sent_result

