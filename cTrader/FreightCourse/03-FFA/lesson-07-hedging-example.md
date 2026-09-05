# Lesson 07 — Worked examples: hedge & speculation

**Goal:** see the numbers move in three realistic scenarios.

## Example 1 — Shipowner hedges (short)

A shipowner has a Capesize that will be free in **December**. Today (September), the Dec BCI 5TC FFA is trading at **$20,000/day**. The owner fears rates will fall by then.

- **Action:** *sell* 1 lot Dec BCI 5TC @ $20,000/day.
- **What happens:** December's average BCI 5TC settles at **$14,000/day**.

**FFA result:** (20,000 − 14,000) × 31 days = **+$186,000** received on the FFA.

**Physical reality:** the owner charters the ship in December at $14,000/day — $6,000/day less than September's expectation.

**Net:** the FFA profit exactly offsets the weaker charter. The owner effectively locked in ~$20,000/day. *That's a hedge: certainty, not profit.*

## Example 2 — Charterer hedges (long)

A steel mill will ship ~170,000 t of iron ore (a C5 cargo) from Australia to China in **March**. It wants to cap its freight cost.

- **Action:** *buy* the March C5 voyage FFA at **$11.00/t** (contract size 170,000 t).
- **What happens:** March C5 averages **$14.50/t**.

**FFA result:** (14.50 − 11.00) × 170,000 = **+$595,000** received.

**Physical reality:** the mill pays the market rate $14.50/t to move the ore.

**Net:** the FFA gain compensates for the higher shipping cost. The mill locked in ~$11/t. *Again: insurance, not speculation.*

## Example 3 — Speculator (the pure view)

A fund believes the Q4 iron-ore restock will push Capesize rates up, and that the market's Q4 price is too low.

- **Action:** *buy* 5 lots Dec BCI 5TC @ $18,000/day.
- **What happens:** December averages **$24,000/day**.

**FFA result:** (24,000 − 18,000) × 31 × 5 lots = **+$930,000**.

If December had averaged $15,000 instead, the same position loses **$465,000**. No ship was ever involved — this is pure price risk, sized to taste.

## The rules these examples teach

1. **Know your side first**: are you hedging an existing exposure or speculating?
2. **Size with a loss in mind**: a speculator must survive being wrong (Example 3's downside is real).
3. **Month matters**: settlement uses the *monthly average*, not one day — timing the "best day" is not the game.
4. **Hedging isn't free**: you give up upside to remove downside (Example 1 could have earned $6,000/day more if rates had *risen*).

## Practice prompt

Take a blank sheet: pick a route, a month, and a view (long or short). Write down entry price, settlement price, and the P&L math — for both an up-case and a down-case — before checking the answers in `04-Practice/exercises.md`.

**Next →** Practice: glossary + exercises.