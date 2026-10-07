# Revision in Aqra

How Aqra plans each day's revision and how it measures the strength of what's memorized. Every number below lives
in one place in the code, `ReviewPolicy` (`apps/ios/Aqra/Revision/RevisionEngine.swift`), so it can be tuned after
trying it with real huffaz and sheikhs, without rewriting anything.

**Status:** first version, adopted provisionally. It is open to review.

## The idea

Huffaz everywhere revise in three lanes:

| Lane | In the hifz tradition | In Aqra |
|---|---|---|
| New memorization | السبق | Today's portion, from the personal plan |
| Near revision | السبقي | Follow-up: pages stumbled on come back soon |
| Far revision | المنزل | The rotation through everything memorized, in Mushaf order |

Aqra adds one thing the tradition can't easily keep track of: **the strength of every ayah**. It fades with time and
grows with revision. It's the brightness of the ayah's topic color in the Mushaf.

## Strength of an ayah

Each memorized ayah has a **half-life**: the number of days until the chance of recalling it falls to half.

- **Declared ayat** (the student says they already know them) start at **14 days**.
- **Newly memorized ayat** (a portion of the plan, «تم الحفظ») start at **2 days**, and their pages come back for
  follow-up the next day.
- **A clean revision** multiplies it by **2.5**.
  - The multiplier is smaller if the revision comes before the memory has had time to slip (the spacing effect).
  - The first revision of a declared ayah counts in full.
- **A stumble** multiplies it by **0.3**, with a minimum of 1 day.
- **A sheikh's tasmee'** counts more: a clean revision heard by a sheikh grows the half-life by **1.5 times** the
  usual growth; a **peer's** by **1.25 times**. A stumble is a stumble, whoever heard it. Provisional, see the
  open questions.
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

**Outside the app** (in prayer, or to a friend): the page is checked off from the plan, as a clean revision — or,
if the student stumbled, the page opens whole and they tap the ayat they stumbled on.

**With a friend** (peer tasmee'): the student shows a short code; the friend hears them on their own phone, marks
the stumbles and the pages heard, and the student's app records it as a peer's revision (it never verifies).

**With a sheikh** (tasmee'): the teacher turns the Mushaf's pages on their own phone as the student recites, taps
the ayat the student stumbles on, and marks each page heard. The record goes into the student's account, and the
student's app applies it: each page heard is a sheikh's revision of its memorized ayat (the stumbled ones weaken,
the rest grow by the sheikh's weight), the clean ayat are marked **verified**, and a stumble takes the mark away
until a teacher hears the ayah clean again. Ayat the student never marked as memorized are left alone: the
student owns the map of what they know.

**Follow-up after a stumble:** the page comes back after **1 day**, then **3**, then **7**, as long as it stays
clean. A new stumble starts it again at 1 day. A newly memorized portion's pages follow the same steps.

## The rotation learns

Pages that keep slipping are suggested for extra follow-up, and the student takes or dismisses the suggestion:
- a page stumbled on in **2** revisions within **30 days**, or
- a page fainter than **0.35** while the memorization as a whole averages at least **0.5**.

At most three pages are suggested at a time; taken, they come back from tomorrow; dismissed, they aren't
suggested again for **14 days**.

## Mastery

An ayah is **mastered** once its half-life reaches **60 days** and no stumble has come since its last clean
revision. It's shown apart from what's memorized and what's verified, for each stage and the whole Quran.

## Open questions for review

1. **Are the numbers right?** The 14-day start, the ×2.5 and ×0.3 multipliers, the 1/3/7 follow-ups, and maturity
   at 90 days.
2. **Revisions outside the app:** they may now record stumbles (provisionally); is that right?
3. **The rotation:** it suggests and the student approves; are the thresholds right?
4. **Evidence weights:** a sheikh's tasmee' counts 1.5 times self-revision, a peer's 1.25, provisionally. And
   should a sheikh hearing an ayah clean that the student never declared mark it memorized? For now it doesn't.
5. **Mastery:** is 60 days with a clean last revision the right bar?
