// "Remember it": a memory card game with the small things Doddy keeps for people.
// Flip two cards; matching pairs stay up and Doddy says where the thing is. Nothing stored.

(() => {
  const grid = document.querySelector("#memory-grid");
  if (!grid) return;
  const bubble = document.querySelector("#memory-bubble");
  const pairsEl = document.querySelector("#memory-pairs");
  const movesEl = document.querySelector("#memory-moves");
  const restart = document.querySelector("#memory-restart");
  const pose = document.querySelector(".memory-doddy img");
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  const POSE_THINKING = "/assets/day/poses/kneeling_inspect-320.webp";
  const POSE_DONE = "/assets/day/poses/fistpump-320.webp";

  // Line drawings on a 64 x 64 grid; ".acc" shapes take the orange cue.
  const ITEMS = [
    { id: "keys", label: doddyT("Spare keys"), line: doddyT("Spare keys: blue tin, above the fridge. Got it."),
      icon: '<circle cx="22" cy="24" r="10"/><path d="M29 31 L50 52 M44 46 l6 -6 M48 50 l5 -5"/><rect class="acc" x="8" y="40" width="14" height="10" rx="2" transform="rotate(-15 15 45)"/>' },
    { id: "locker", label: doddyT("Locker 4471"), line: doddyT("Parcel locker code 4471. Saved."),
      icon: '<rect x="10" y="10" width="44" height="44" rx="4"/><path d="M10 26 H54 M10 42 H54 M32 10 V54"/><rect class="acc" x="36" y="30" width="14" height="8" rx="1.5"/>' },
    { id: "book", label: doddyT("Marta's book"), line: doddyT("Marta's book was The Hobbit."),
      icon: '<path d="M32 18 C24 13 14 13 8 15 V50 C14 48 24 48 32 53 C40 48 50 48 56 50 V15 C50 13 40 13 32 18 Z M32 18 V53"/><path class="acc" d="M42 15 V31 L45 28 L48 31 V15 Z"/>' },
    { id: "shoe", label: doddyT("Shoe size 31"), line: doddyT("Size 31. They grow so fast."),
      icon: '<path d="M8 46 C8 36 10 28 14 25 H22 C24 31 30 33 36 33 L46 35 C54 37 58 41 58 46 Z"/><path d="M24 29 l4 -3 M29 32 l4 -3"/><rect class="acc" x="8" y="46" width="50" height="5" rx="2"/>' },
    { id: "wifi", label: doddyT("Wi-Fi password"), line: doddyT("Wi-Fi password is on the router sticker."),
      icon: '<path d="M12 28 C24 16 40 16 52 28 M18 35 C27 27 37 27 46 35 M24 42 C29 38 35 38 40 42"/><circle class="acc" cx="32" cy="49" r="4"/>' },
    { id: "parking", label: doddyT("Parked on B2"), line: doddyT("Level B2, by the lift. You're welcome."),
      icon: '<rect x="12" y="10" width="40" height="44" rx="8"/><path d="M26 44 V22 H34 A7 7 0 0 1 34 36 H26"/><circle class="acc" cx="50" cy="13" r="6"/>' },
  ];
  const MISSES = [doddyT("Not those two. Try again."), doddyT("Close. Flip another pair."), doddyT("Hmm, not a match."), doddyT("Nope. I'd have written that down.")];

  let first = null;
  let locked = false;
  let pairs = 0;
  let moves = 0;

  function say(text) {
    bubble.textContent = text;
    bubble.classList.remove("pop");
    void bubble.offsetWidth;  // restart the pop animation
    bubble.classList.add("pop");
  }
  function score() {
    pairsEl.textContent = pairs;
    movesEl.textContent = moves;
  }
  function shuffle(list) {
    for (let i = list.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [list[i], list[j]] = [list[j], list[i]];
    }
    return list;
  }
  function describe(card, faceUp) {
    const n = card.dataset.n;
    if (card.classList.contains("matched")) card.setAttribute("aria-label", doddyT("Card {n}: {label}, matched", { n: n, label: card.dataset.label }));
    else card.setAttribute("aria-label", faceUp ? doddyT("Card {n}: {label}", { n: n, label: card.dataset.label }) : doddyT("Card {n}, face down", { n: n }));
  }

  function deal() {
    grid.textContent = "";
    first = null;
    locked = false;
    pairs = 0;
    moves = 0;
    score();
    pose.src = POSE_THINKING;
    say(doddyT("Flip two. Find the pair."));
    shuffle([...ITEMS, ...ITEMS]).forEach((item, i) => {
      const card = document.createElement("button");
      card.type = "button";
      card.className = "mem-card";
      card.dataset.id = item.id;
      card.dataset.label = item.label;
      card.dataset.n = String(i + 1);
      card.innerHTML =
        '<span class="mem-inner">' +
          '<span class="mem-back" aria-hidden="true">?</span>' +
          `<span class="mem-front" aria-hidden="true"><svg viewBox="0 0 64 64">${item.icon}</svg><span class="mem-label">${item.label}</span></span>` +
        "</span>";
      describe(card, false);
      card.addEventListener("click", () => flip(card, item));
      grid.append(card);
    });
  }

  function flip(card, item) {
    if (locked || card.classList.contains("up")) return;
    card.classList.add("up");
    describe(card, true);
    if (!first) { first = { card, item }; return; }

    moves += 1;
    const other = first.card;
    first = null;
    if (other.dataset.id === item.id) {
      pairs += 1;
      for (const c of [other, card]) {
        c.classList.add("matched");
        c.setAttribute("aria-disabled", "true");
        describe(c, true);
      }
      score();
      if (pairs === ITEMS.length) {
        pose.src = POSE_DONE;
        say(doddyT("All six in {moves} moves. That's what I'm for.", { moves: moves }));
      } else {
        say(item.line);
      }
      return;
    }
    score();
    say(MISSES[Math.floor(Math.random() * MISSES.length)]);
    locked = true;
    setTimeout(() => {
      for (const c of [other, card]) { c.classList.remove("up"); describe(c, false); }
      locked = false;
    }, reduceMotion.matches ? 700 : 950);
  }

  restart.addEventListener("click", deal);
  deal();
})();
