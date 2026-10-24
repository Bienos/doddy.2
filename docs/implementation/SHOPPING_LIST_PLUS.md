# Shopping list+ (ADR-630, ADR-631)

Owner, 24 Oct 2026: "Lista zakupów+" as the first build from the expert-modes research (`docs/strategy/TRYBY_EKSPERCKIE_2026-10.md`, ADR-630): quantities and units on list items, what is already at home, and a product barcode read on the iPhone with Open Food Facts asked from the iPhone. It builds on lists by voice (ADR-216, `LISTS_STATUS.md`), a dish's ingredients to a list (ADR-305) and shopping stage 1 (ADR-607 to 610). Branch `claude/expert-modes-research`. **Status per stage is at the end; nothing here has been seen on a device.**

## Rules that do not change

- An item keeps the user's words, never reworded (ADR-216). Quantities are read from those words; nothing is rewritten.
- Matching and duplicates stay as they are: same words ignoring case, accents, punctuation and a leading article. "milk" never matches "mleko", and "mleka" never matches "mleko" (no Polish stemming).
- Every change is one list's change, read back, with Undo (ADR-216).
- Nothing new leaves the iPhone except the barcode digits sent to Open Food Facts after the user's own tap (stage 3).

## Stage 1: quantities and units

`ListQuantity` (DoddyCore, `ListQuantity.swift`) reads a quantity from an item's words, conservatively:

- **Forms:** a number first ("2 l mleka", "500g mąki", "1,5 kg ziemniaków", "3 jajka", "2x mleko", "2 × mleko"), or a number with a unit or a multiplier last ("mleko 2 l", "jajka 10 szt.", "mleko x2", "mleko ×2"). Polish and English number words one to ten and "pół"/"half" count ("dwa mleka", "pół kilo sera").
- **Units:** g, dag, kg (and "kilo"), ml, l, pieces (szt., pcs), packs (op., opak., opakowanie…, pack), bottles (butelka…, bottle), cans (puszka…, can). Mass is compared in grams and volume in millilitres; packs, bottles and cans are counts of their own and never converted.
- **Not read as a quantity:** a number glued to a word ("7up", "WD-40"), a percentage ("mleko 3,2%"), a bare number at the end ("iPhone 15", "Nivea 50"), zero, more than 9,999 or more than three decimals, and anything that leaves no word with a letter.
- **On screen:** a list row shows the item's words without the quantity, with the quantity as a small label at the end ("mleka · 2 l"); VoiceOver, sharing, the Lock Screen, Doddy's voice and the export still use the full words.
- **Sums:** `ListQuantity.total` adds quantities of the same kind (grams with kilograms, millilitres with litres, pieces with pieces) and keeps different kinds apart; for the meal-plan step later (the research's `unit_normalizer` and `ingredient_aggregator`).

## Stage 2: what is already at home

- **One list is "At home"** (e.g. "W domu", "Spiżarnia"): the list menu has "This is my At home list"; one list at a time, kept on this iPhone (`HomeStock.preferenceKey`). The list shows "At home" under its name.
- **A hint, never a block:** adding to another list (typed, by voice or from a dish's ingredients) still adds; items that are open on the At home list are named: "On your At home list: rice". Doddy's voice reply carries the same line as data. On the ingredients card (ADR-305) those items start unticked and say "at home", like items already on the list.
- **Two explicit moves, each one ordinary add to one list with Undo:**
  - on a shopping list, menu "Add ticked to At home": the ticked items' words go to the At home list (repeats skipped as usual); the ticks stay until "Clear ticked";
  - on the At home list, menu "Add ticked to a list…": ticked items (used up) go to a list the user picks.
- Matching is the same exact-words rule, on the words without the quantity: "ryż 1 kg" at home matches "ryż" added; "ryżu" does not.

## Stage 3: a product's barcode

- **Where:** the list screen's add row gets a barcode button. It opens iOS's own camera screen (`CameraCapture`, ADR-569); the photo stays on the iPhone, is never saved and is dropped after reading.
- **Reading on the iPhone:** Vision's barcode request (in `Features/Photos`, where the guard allows Vision) looks for EAN-13, EAN-8 and UPC codes; `ProductBarcode` in DoddyCore accepts only digits with a valid check digit (GTIN-8, 12, 13, 14).
- **Open Food Facts, from the iPhone:** `OpenFoodFactsClient` (one file, allowed by the guard) asks only `OpenFoodFacts.productURL(for:)`, built in DoddyCore from the checked digits and a fixed field list (`https://world.openfoodfacts.org/api/v2/product/{code}?fields=…`): no cookies, redirects refused, a size cap, a 10 s timeout, a User-Agent naming the app as Open Food Facts asks (`Doddy/{version} (https://doddy.lol)`), and at most 10 look-ups a minute on this iPhone (Open Food Facts allows 15 per IP address). Only the barcode digits are sent; nothing about the user.
- **The answer:** a card with the product's name (Polish name first, then the main name, then English), brand and package size, "Data: Open Food Facts (ODbL)" and **Add to {list}** / **Cancel**. Nothing is added without the tap. Not found, an unreadable photo, no connection or the cap reached each say so and offer to type the item instead; nothing is guessed from the code.
- **Privacy text:** What leaves this iPhone gains an "Open Food Facts (barcodes)" row; the camera permission text already covers taking a photo.

## Not in this build

Pantry counts and expiry dates, scanning receipts, prices for scanned products, a barcode by voice, changing a quantity with a stepper, merging "milk" and "2 milk" into one item, and Polish word forms ("mleko" and "mleka").

## Status

| Stage | Code | Checked |
|---|---|---|
| 1 Quantities | `Packages/DoddyCore/Sources/DoddyCore/ListQuantity.swift`; list rows in `DoddyApp/Features/Lists/ListViews.swift` | DoddyCore `make test-core` (Swift 6.1.2, Linux): **1,751 tests, 0 failures** (12 new in `ListQuantityTests`; the bare-count cap raised on purpose failed 6 of them, then restored). **BLOCKED / NOT RUN:** the list row (SwiftUI; no Xcode here, the hosted Mac job compiles it on a pull request), a device. |
| 2 At home | pending | — |
| 3 Barcode | pending | — |
