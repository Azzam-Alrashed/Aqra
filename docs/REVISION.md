# Revision in Aqra

How Aqra plans each day's revision and how it measures the strength of what's memorized. Every number below lives
in one place in the code, `ReviewPolicy` (`apps/ios/Aqra/Revision/RevisionEngine.swift`), so it can be tuned after
trying it with real huffaz and sheikhs, without rewriting anything.

**Status:** first version, adopted provisionally. It is open to review.

## The idea

Huffaz everywhere revise in three lanes:

| Lane | In the hifz tradition | In Aqra |
|---|---|---|
| New memorization | السبق | Comes in a later wave, with the personal plan |
| Near revision | السبقي | Follow-up: pages stumbled on come back soon |
| Far revision | المنزل | The rotation through everything memorized, in Mushaf order |

Aqra adds one thing the tradition can't easily keep track of: **the strength of every ayah**. It fades with time and
grows with revision. It's the brightness of the ayah's topic color in the Mushaf.

## Strength of an ayah

Each memorized ayah has a **half-life**: the number of days until the chance of recalling it falls to half.

- **Declared ayat** (the student says they already know them) start at **14 days**.
- **A clean revision** multiplies it by **2.5**.
  - The multiplier is smaller if the revision comes before the memory has had time to slip (the spacing effect).
  - The first revision of a declared ayah counts in full.
- **A stumble** multiplies it by **0.3**, with a minimum of 1 day.
- **The longest half-life** is **365 days**.

**What the student sees:** the color's strength is how established the ayah is (its half-life, full at **90 days**)
times how fresh it is (the chance of recalling it today).
- A just-declared ayah is faint.
- Three well-spaced clean revisions make it full.
- Weeks without revision fade it.
- The color never disappears entirely while the ayah is memorized.

## Today's plan («وِرد اليوم»)

**The daily amount:** the student chooses it, in pages per day. The suggestion is enough to go through everything
memorized in about a month, between 2 and 20 pages.

**Each day the plan takes, in order:**
1. **Follow-up pages:** pages stumbled on recently, most overdue first.
2. **Rotation pages:** the next pages after where the rotation stopped, among pages with memorized ayat, in Mushaf
   order, wrapping back to the start.

**Rules:**
- **The plan is fixed for the day** once made.
- **Missed days don't pile up.** The rotation only moves past pages that were revised, so tomorrow starts where the
  student stopped, with the same daily amount.

## Recording a revision

**In the app:**
1. The page's memorized ayat are veiled.
2. The student recites, revealing one ayah at a time.
3. They tap an ayah they stumbled on.
4. «تم» records the page.

**Outside the app** (in prayer, or to a friend): the page is checked off from the plan, as a clean revision.

**Follow-up after a stumble:** the page comes back after **1 day**, then **3**, then **7**, as long as it stays
clean. A new stumble starts it again at 1 day.

## Open questions for review

1. **Are the numbers right?** The 14-day start, the ×2.5 and ×0.3 multipliers, the 1/3/7 follow-ups, and maturity
   at 90 days.
2. **Revisions outside the app:** should they be allowed to record stumbles, not only clean revisions?
3. **The rotation:** should it adapt by itself (strong juz' less often, weak ones more often), or only suggest
   changes for the student to approve? The direction so far is to suggest.
4. **Evidence weights** for later waves: how much a peer's or a sheikh's tasmee' should count compared with
   self-revision.
