# Lesson 06 — FFA basics: trading freight on paper

**Goal:** understand what a Forward Freight Agreement is, how it's priced, and how it settles — with no ships involved.

## What is an FFA?

A **Forward Freight Agreement (FFA)** is a cash-settled contract on a freight index. Two parties agree today on a price for a future month; at settlement, one pays the other the difference. **No cargo, no ship, no delivery** — it's a pure financial trade, like a forward on an index.

## The three things in every FFA

1. **The underlying** — which route or index (e.g. BPI 5TC for December, or the C5 voyage route).
2. **The price** — quoted in **$/day** (TC routes) or **$/tonne** (voyage routes).
3. **The month** — e.g. "Dec 26 BPI 5TC @ $14,000/day".

## Settlement — how the money moves

- During the month, the Baltic publishes the index daily.
- The **settlement price** = the **average of the daily assessments for that month**.
- Payout = (settlement − contract price) × **multiplier**:
  - **TC routes**: × the number of days in the month (one FFA lot = 1 day of TC rate).
  - **Voyage routes**: × the standard cargo size for that route (e.g. ~170k t for C5).

**Example (TC):** you *sell* Dec BPI 5TC at $14,000/day. December averages $11,000/day. Settlement: you receive (14,000 − 11,000) × 31 days = **$93,000**, because rates fell and you were short.

## Long vs short — the first rule of FFA trading

- **Long** (buy the contract): you profit if rates **rise**.
- **Short** (sell the contract): you profit if rates **fall**.

Same as any forward market.

## The curve (calendar strip)

FFA prices exist for the current month, each calendar month, quarters, and calendars out ~2–3 years. Together they form the **forward curve**:

- **Contango** (later months higher): the market expects rates to rise (or seasonal strength ahead).
- **Backwardation** (later months lower): the market expects rates to fall.

The curve is where seasonality shows up: Dec months are usually richer than Jan months. Traders compare spot vs. curve to find "cheap" and "expensive" months.

## Where FFAs trade

- **OTC** (bilaterally, via freight brokers), then **cleared** through clearing houses — mainly **SGX** (which owns the Baltic Exchange) and **ICE**.
- Clearing removes counterparty risk: the clearing house guarantees settlement.
- Contract size: 1 lot = 1 day of TC rate (or the route's cargo size for voyage FFAs).

## Key takeaways

- FFA = cash-settled forward on a freight index; no physical shipping.
- Priced in $/day or $/tonne; settles on the month's average of daily assessments.
- Long profits from rising rates; short from falling.
- The forward curve shows market expectations and seasonality.
- Cleared via SGX/ICE — the clearing house handles counterparty risk.

**Next →** Lesson 07: two worked examples — a real hedge and a real speculation.