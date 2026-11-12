# Travel is one trip that Doddy carries from the first idea to the way home; the person books and pays at the seller

- **Date:** 2026-11-11
- **Decided by:** owner, 11 Nov 2026, in Polish. The request: "będziemy teraz tworzyli funkcję podróż … podłączył do różnych portali podróżniczych … tryb czuwania … planer … pytania, jeżeli czegoś mu brakowało … raport … zadzwonienia za ciebie … bukowania … last minute, sam z siebie szukać", then "zrób to … ciekawiej … jak ludzie teraz wyszukują … 100 razy lepiej". Answers to four questions the same day:
  - who it is for: "Wszyscy po równo";
  - initiative: "Sam podsuwa pomysły";
  - booking: "Przygotowuje, płacisz sam";
  - email: "Tak ma dostęp do maila normalnie".

  Then, for stage 1:
  - when Gmail is read: "Tylko na żądanie" (only on request);
  - how an email is read: "AI ze sprawdzaniem" (a model, with every value checked against the email);
  - sample emails: "Tak, tylko do wzorów" (the owner's mail read for layouts only, no real email in the repository);
  - where trips show: "Karta na Home, gdy jest wyjazd".

  So in point 8 below, the mailbox is read only when the person asks.
  The design and the order of stages are this pull request's proposal; **owner approval of the plan as a whole is pending**.
- **Status:** proposed (the four answers above are the owner's)
- **Replaces:** version 1 of this decision (same day, a source-by-source plan). Builds on ADR-570 (errands), ADR-607 (shopping runner), `2026-11-10-radar-alerts`, `2026-11-09-restaurant-calls-one-tap`.

## Why

Research on how people plan trips and use AI for it (`docs/implementation/TRAVEL.md` sections 1 and 9) found:
- a long, scattered search;
- price-first hunting from several airports;
- two Polish markets (packages and DIY);
- domestic stays booked by phone;
- hidden fees and low-cost airline rules as the top pains;
- confirmations scattered across email and screenshots;
- AI planners that fail on invented places, wrong hours and prices.

People use AI to plan but not to book: 12% would let it book in Europe. No product covers the Polish traveller end to end in Polish.

The portals the owner named give a company of Doddy's size no search API, and scraping is ruled out (version 1's research, kept in section 7).

## Decision

1. **One trip (Wyjazd)** holds everything from the first idea to the way home, through four moments: dreaming, choosing, going, there and after.
2. **Doddy recognises the kind of trip:** deal hunt, package, city break, domestic, or a fixed trip. It changes its questions, sources and card to match, and says what it assumed.
3. **Doddy asks only what it can't know.** It fills dates from the calendar and companions and likes from saved notes, with at most three questions, one at a time. New likes are saved only with a yes.
4. **The answer in seconds by voice, details on screen:** three options with one recommendation, the real door-to-door total, and what is not included or not checked. A package is compared with the same trip done on your own.
5. **Every price, place and hour comes from a source in this run,** with the source and time. This is enforced in code, as in the shopping runner. Visa and entry rules come only with an official link.
6. **Standby:** flexible watches, a live re-check before every push, and factual wording. Doddy also sends three ideas a week, on by default for people who use travel and off in one tap.
7. **Guesthouse calls** use Calls for you for Polish numbers. A deposit is prepared as a transfer draft; Doddy never pays.
8. **After booking**, Doddy reads travel confirmations in the connected Gmail as data. It fills the trip and proposes, on cards:
   - calendar entries;
   - the free-cancellation reminder;
   - online check-in;
   - when to leave;
   - document checks;
   - a packing list.

   It watches the price of a cancellable stay and doesn't rebook.
9. **At the destination and afterwards:**
   - a today view that also works offline;
   - for a delayed or cancelled flight, Doddy explains the EU261 rights and drafts the claim email for the person to send;
   - a cost split for the trip's people.
10. **No booking or payment inside Doddy.**
11. **Order of work:**
    1. the trip and filling it from email;
    2. the planner;
    3. standby and ideas;
    4. guesthouse calls;
    5. there and after;
    6. planning together.

    Each part ships behind its own switch, default off.

## Consequences

- **Stage 1 needs no travel partner,** so it can start first. It needs real confirmation emails as test fixtures, with personal data removed, which only the owner can provide.
- **Reading email for confirmations** is a new use of the Gmail connection. Before it is switched on, the in-app text, "What leaves this iPhone" and the privacy policy must say:
  - what is read;
  - where it is read;
  - what is kept.
- **Weekly ideas are an unprompted push.** Watch opt-out rates; the owner may want them off by default.
- **Partner accounts and Kiwi's answer** gate stage 2 (owner queue 43).
- **Standby needs** an always-on worker and working APNs (owner queue 8).
- **Automatic flight-delay detection** needs a flight-status source that hasn't been researched yet.
- **Planning together** needs a decision on whether companions need a Doddy account.

## Evidence

- **Web research** by four research agents on 11 Nov 2026: two on sources and law, two on how people plan and use AI. Reddit could not be read; several statistics are from UK, US or German surveys or from vendors, as marked in the plan.
- **Read in the repository:** errands, watches, radar, task calls, the voice tool list.
- **Not run:** no travel API was called, no code was written, nothing compiled or tested. The legal points are not legal advice.
