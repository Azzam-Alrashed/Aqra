# Aqra — Vision

> «يُقَالُ لِصَاحِبِ القُرْآنِ: اقْرَأْ وَارْتَقِ، وَرَتِّلْ كَمَا كُنْتَ تُرَتِّلُ في الدُّنْيَا؛ فإنَّ مَنْزِلَكَ عِنْدَ آخِرِ آيةٍ تَقرَؤُها»

This document records the product decisions agreed so far. It is a living document: update it as open questions are settled.

## Goal

Help Quran memorizers (حفّاظ) revise and consolidate what they have memorized.

As users revise, they ascend **منازل**, a progression inspired by the hadith.

### Guiding principles

- **The Quran text is sacred data.** See [Quran text](#quran-text).
- **The منازل are motivational.** They remind the user of the hadith and never claim to represent a real rank in the Hereafter.
- **Constructive competition.** Competition tools, leaderboards included, are welcome when they create a constructive, motivating environment. Features that encourage showing off for its own sake are avoided, to preserve sincerity (إخلاص).

## Platform

- **First release:** an iOS app, built as an Xcode project with SwiftUI.
- **Minimum deployment target:** iOS 17. It can be raised if a feature requires it.
- **Later:** Android and the web. Data and logic, such as ayah IDs, scheduling and منازل, should be designed to be platform-neutral so the expansion is straightforward.

## Quran text

Accuracy of the Quran text is the project's highest requirement.

### Source and display

- **Source:** the King Fahd Glorious Quran Printing Complex (مجمع الملك فهد لطباعة المصحف الشريف).
- **Riwayah:** Hafs only, for now.
- **Display:** 604 Mushaf pages in the Madinah layout, using the Complex's own fonts, so that huffaz keep the visual memory of where each ayah sits on the page.

### Safeguards

1. **Bundled unmodified.** The text is never typed by hand, edited, generated or "cleaned up".
2. **Checksum.** A checksum of the original files is recorded, and a test fails the build if the text changes.
3. **Cross-verification.** The text is compared once against a second trusted source, such as Tanzil, and any difference is reviewed.
4. **Rendering review.** A qualified hafiz reviews the rendering before release.
5. **License.** The Complex's usage terms are respected, and the Complex is credited in the app.

## Connectivity

- **Online app with accounts.**
- **Offline:** Mushaf reading and basic features work without a connection.
- **Online only:** video calls, booking, the auction, competitions, and other features that require a connection.

## Roles

### Student

- Revises.
- Books tasmee' sessions with teachers.

### Teacher

A separate role. Becoming a teacher requires:
- **An ijazah,** reviewed by the app before acceptance.
- **A personal interview.**
- **Other vetting procedures** (details TBD).

## Tasmee' sessions

- **Booking:** the student chooses a teacher and books a tasmee' time slot.
- **Format:** a live audio and video call in which the student recites and the teacher corrects.
- **Video provider:** LiveKit Cloud. Self-hosting is an option later if costs grow.
- **Access:** room tokens are issued by Cloud Functions only after verifying that the user holds a seat in that session.

### Seat auction

Each session has a limited number of seats.

**Biddable seats:**
1. **Start free:** a seat can initially be reserved at no cost.
2. **Bidding:** other students can outbid, and the price rises.
3. **Close:** bidding closes shortly before the session starts.
4. **Winners:** the highest bidders win the seats.

**Reserved free seats:** each session has free seats that cannot be bid on. They are given first come, first served.

**Integrity:** all bids go through Cloud Functions with Firestore transactions, so a seat can never be won twice.

## Payments

### Students

Students pay through **Apple In-App Purchase**, chosen for simplicity.

Because Apple In-App Purchase only sells fixed-price products, the app uses **credits**:
1. **Buy:** students buy consumable credit packs.
2. **Hold:** credits are held when a student bids.
3. **Release:** held credits are returned if the student is outbid.
4. **Spend:** credits are spent only if the student wins the seat.

### Teachers

- **Revenue split:** the teacher receives most of each winning bid, and the app keeps a commission to cover servers and video calls. Apple's fee also applies on top of this, at 15% under the Small Business Program or 30% otherwise.
- **Earnings:** each teacher's share accrues as earnings visible in their account.
- **Payouts:** teachers are paid traditionally, by bank transfer, since there are few teachers at first.

### Note on Stripe

Stripe does not currently support Saudi-based businesses directly. Revisit Stripe Connect or a regional gateway such as Tap if the company structure changes.

## Competitions

Competitions must be constructive and motivating, consistent with the [guiding principles](#guiding-principles). They may include:
- **Personal challenges,** where the student competes only with themselves.
- **Group goals,** such as a shared khatmah.
- **Private competitions between friends.**
- **Teacher-run competitions** for a teacher's own students.

The exact scope is TBD.

## Backend

- **Firebase:**
  - **Auth:** Sign in with Apple and Google. Phone number sign-in may be added later.
  - **Firestore.**
  - **Cloud Functions.**
- **LiveKit Cloud** for video calls.

## Market and language

- **Market:** global from the start.
- **Interface languages:** Arabic, with full right-to-left layout, and English. The architecture is ready for more languages, such as Urdu, Indonesian, Turkish and French.
- **Mushaf text:** always displayed in Arabic as published.

## Open questions

- **Revision method:** recitation with speech recognition, hide and reveal, quizzes, logging, or a combination.
- **Revision scheduling:** spaced repetition suggested by the app, or chosen by the user.
- **منازل calculation:** by ayat revised, by recitation quality, or by consistency.
- **Free seats:** how many reserved free seats each session has.
- **Commission:** the app's commission percentage.
- **Teacher vetting:** the full acceptance procedure beyond the ijazah and interview.
- **Competitions:** their detailed design.
