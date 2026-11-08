/* Doddy · App Store v5. Screens are rebuilt from the app's code and the CI screen atlas (2 Nov 2026);
   every visible word inside the phone is the app's own Polish string (DoddyApp/Resources/Localizable.xcstrings,
   DoddyWidgets/Localizable.xcstrings, DoddyCore/Translator.swift). Lines Doddy says are example conversations.
   Words the app has no Polish for yet are left out, not invented (see the gaps table on the page). */
(function () {
  "use strict";

  const W = "assets/wordmark.svg";
  const reduce = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ───────── icons (simple strokes standing in for SF Symbols) ───────── */
  const P = {
    bubble: '<path d="M5 5.5h14A1.5 1.5 0 0 1 20.5 7v8a1.5 1.5 0 0 1-1.5 1.5h-8.5l-4.5 3.5v-3.5H5A1.5 1.5 0 0 1 3.5 15V7A1.5 1.5 0 0 1 5 5.5z"/>',
    textBubble: '<path d="M5 5.5h14A1.5 1.5 0 0 1 20.5 7v8a1.5 1.5 0 0 1-1.5 1.5h-8.5l-4.5 3.5v-3.5H5A1.5 1.5 0 0 1 3.5 15V7A1.5 1.5 0 0 1 5 5.5z"/><path d="M8 9.5h8M8 12.5h5"/>',
    folder: '<path d="M3.5 7.5v9.5A1.5 1.5 0 0 0 5 18.5h14a1.5 1.5 0 0 0 1.5-1.5V9.5A1.5 1.5 0 0 0 19 8h-7.5l-2-2.5H5A1.5 1.5 0 0 0 3.5 7z"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    ellipsis: '<circle cx="5.5" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.6" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.6" fill="currentColor" stroke="none"/>',
    mic: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5"/>',
    micSlash: '<rect x="9" y="3.5" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v2.5M4 4l16 16"/>',
    phoneDown: '<path d="M3.2 14c4.8-4.4 12.8-4.4 17.6 0l-1.7 2.7-3.6-1.3v-2.3a12 12 0 0 0-7 0v2.3l-3.6 1.3z"/>',
    eyeSlash: '<path d="M2.5 12s3.5-6 9.5-6 9.5 6 9.5 6-3.5 6-9.5 6-9.5-6-9.5-6z"/><circle cx="12" cy="12" r="3"/><path d="M4 4l16 16"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    photo: '<rect x="3.5" y="5" width="17" height="14" rx="2.5"/><circle cx="9" cy="10" r="1.6"/><path d="M4 17l5-4.5 3.5 3 3-2.5 4.5 4"/>',
    camera: '<path d="M4 8.5A1.5 1.5 0 0 1 5.5 7H8l1.5-2h5L16 7h2.5A1.5 1.5 0 0 1 20 8.5V17a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 17z"/><circle cx="12" cy="12.5" r="3.5"/>',
    arrowUp: '<path d="M12 19V6M6.5 11.5L12 6l5.5 5.5"/>',
    xfill: '<circle cx="12" cy="12" r="9" fill="currentColor" stroke="none"/><path d="M9 9l6 6M15 9l-6 6" stroke="#F5EFE2"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5.5M12 7.8v.4"/>',
    note: '<rect x="5" y="3.5" width="14" height="17" rx="2"/><path d="M8.5 8h7M8.5 12h7M8.5 16h4"/>',
    pause: '<path d="M9 6v12M15 6v12"/>',
    replay: '<path d="M5 12a7 7 0 1 0 2.1-5"/><path d="M5 4.5v4h4"/>',
    open: '<rect x="4.5" y="4.5" width="15" height="15" rx="3"/><path d="M10 14l5-5M11 9h4v4"/>',
    stop: '<rect x="6.5" y="6.5" width="11" height="11" rx="2" fill="currentColor" stroke="none"/>',
    stopCircle: '<circle cx="12" cy="12" r="9.5" fill="currentColor" stroke="none"/><rect x="8.6" y="8.6" width="6.8" height="6.8" rx="1.2" fill="#F5EFE2" stroke="none"/>',
    hand: '<path d="M9 11V5.5a1.5 1.5 0 0 1 3 0V11m0-1.5a1.5 1.5 0 0 1 3 0V12m0-1a1.5 1.5 0 0 1 3 0v3.5a6 6 0 0 1-6 6h-1a5 5 0 0 1-4-2l-3-4a1.5 1.5 0 0 1 2.3-1.9L9 14"/>',
    chevUD: '<path d="M8.5 9.5L12 6l3.5 3.5M8.5 14.5L12 18l3.5-3.5"/>',
    chevR: '<path d="M10 6l6 6-6 6"/>',
    translate: '<path d="M4 5h10v8H8l-4 3z"/><path d="M14 9h6v8h-2v3l-3.5-3H11v-2"/>',
    sliders: '<path d="M4 7h10M18 7h2M4 12h3M11 12h9M4 17h12M19.5 17h.5"/><circle cx="16" cy="7" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17.5" cy="17" r="2"/>',
    search: '<circle cx="11" cy="11" r="6"/><path d="M15.5 15.5L20 20"/>',
    list: '<circle cx="5.5" cy="7" r="1.5"/><circle cx="5.5" cy="12" r="1.5"/><circle cx="5.5" cy="17" r="1.5"/><path d="M10 7h10M10 12h10M10 17h10"/>',
    timer: '<circle cx="12" cy="13" r="7.5"/><path d="M12 9.5V13l2.5 2M10 3.5h4"/>',
    calendar: '<rect x="4" y="5.5" width="16" height="14" rx="2"/><path d="M4 9.5h16M8.5 3.5v4M15.5 3.5v4"/>',
    wave: '<path d="M5 10v4M8.5 7v10M12 9v6M15.5 5.5v13M19 10v4"/>',
    cart: '<path d="M3.5 4.5h2l2 10.5h10l2-7.5H7"/><circle cx="9.5" cy="19" r="1.3"/><circle cx="16.5" cy="19" r="1.3"/>',
    sparkle: '<path d="M12 3.5l1.8 5.2 5.2 1.8-5.2 1.8L12 17.5l-1.8-5.2-5.2-1.8 5.2-1.8z"/>',
    clip: '<path d="M16 7.5l-6.5 6.5a2 2 0 0 0 2.8 2.8l7-7a4 4 0 0 0-5.7-5.7l-7.2 7.2a6 6 0 0 0 8.5 8.5L20 14.5"/>',
    pencil: '<path d="M5 19l1-4L15.5 5.5l3 3L9 18z"/><path d="M13.5 7.5l3 3"/>',
    play: '<path d="M8 5.5v13l10-6.5z" fill="currentColor" stroke="none"/>',
    action: '<rect x="8" y="3" width="8" height="18" rx="4"/>'
  };
  function ic(n, s, cls) { return '<svg class="ic ' + (cls || "") + '" width="' + (s || 20) + '" height="' + (s || 20) + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + P[n] + "</svg>"; }

  const SIGNAL = '<svg width="18" height="12" viewBox="0 0 18 12" fill="currentColor" aria-hidden="true"><rect x="0" y="8" width="3" height="4" rx="1"/><rect x="5" y="5.5" width="3" height="6.5" rx="1"/><rect x="10" y="3" width="3" height="9" rx="1"/><rect x="15" y="0" width="3" height="12" rx="1"/></svg>';
  const WIFI = '<svg width="16" height="12" viewBox="0 0 16 12" fill="currentColor" aria-hidden="true"><path d="M8 2.2c2.3 0 4.4.9 6 2.4l1.3-1.4A10.4 10.4 0 0 0 8 .2 10.4 10.4 0 0 0 .7 3.2L2 4.6a8.4 8.4 0 0 1 6-2.4zm0 3.6c1.3 0 2.5.5 3.4 1.4l1.4-1.4A6.8 6.8 0 0 0 8 3.8a6.8 6.8 0 0 0-4.8 2l1.4 1.4c.9-.9 2.1-1.4 3.4-1.4zM8 9.4 10 7.5a2.8 2.8 0 0 0-4 0z"/></svg>';
  const BATT = '<svg width="27" height="13" viewBox="0 0 27 13" aria-hidden="true"><rect x=".5" y=".5" width="23" height="12" rx="3.5" fill="none" stroke="currentColor" opacity=".4"/><rect x="2" y="2" width="20" height="9" rx="2" fill="currentColor"/><path d="M25 4.5v4c.8-.3 1.3-1.1 1.3-2s-.5-1.7-1.3-2z" fill="currentColor" opacity=".45"/></svg>';
  function sb(light) { return '<div class="sb' + (light ? " light" : "") + '"><span>9:41</span><span class="sb-r">' + SIGNAL + WIFI + BATT + "</span></div>"; }

  function img(src, style) { return '<img src="' + src + '" alt="" style="width:100%;height:100%;object-fit:contain;' + (style || "") + '">'; }
  function pose(n) { return img("assets/pose-" + n + ".png"); }
  function sprite(prefix, n, fps, seq) {
    let s = '<div class="sprite" data-fps="' + fps + '"' + (seq ? ' data-seq="' + seq + '"' : "") + ">";
    for (let i = 1; i <= n; i++) s += '<img src="assets/' + prefix + "-" + i + '.png" alt=""' + (i === 1 ? ' class="cur"' : "") + ">";
    return s + "</div>";
  }
  function bars(n) { let s = ""; for (let i = 0; i < n; i++) s += '<i style="animation-delay:-' + (i * 0.13).toFixed(2) + 's"></i>'; return s; }
  function strip(loud) { return '<div class="strip ' + (loud ? "loud" : "soft") + '" data-cls="' + (loud === "late" ? "loud:2-99" : "") + '"><span class="w">' + bars(9) + '</span><span class="w">' + bars(9) + "</span></div>"; }
  // reveal helpers: data-show="a-b,c-d"
  function rv(show, extra) { return ' class="rv ' + (extra || "") + '" data-show="' + show + '"'; }

  /* ───────── screens ───────── */
  function home(o) {
    o = o || {};
    const talking = !!o.talking;
    let h = '<div class="home">' + sb();
    if (talking) h += strip(o.loud);
    h += '<div class="home-head">';
    if (talking) h += '<span class="cap">' + ic("textBubble", 16) + " Zapis rozmowy</span>";
    h += '<img class="wm" src="' + W + '" alt="Doddy"><span class="more">' + ic("ellipsis", 24) + "</span></div>";
    h += '<div class="home-doddy">';
    if (talking && o.speakFrom != null) {
      h += '<div' + rv("0-" + (o.speakFrom - 1), "gone") + ' style="position:absolute;inset:0">' + pose("listening") + "</div>";
      h += '<div' + rv(o.speakFrom + "-99", "gone") + ' style="position:absolute;inset:0">' + sprite("talk", 6, 6) + "</div>";
    } else if (talking) {
      h += pose("listening");
    } else {
      h += sprite("idle", 4, 2);
    }
    h += "</div>";
    h += '<div class="home-status"><span class="dot"></span><h1>Jestem tu.</h1><p>' + (talking ? "Stuknij Doddy’ego, żeby skończyć" : "Stuknij Doddy’ego, żeby porozmawiać") + "</p></div>";
    if (talking) h += '<div class="talkbar"><span class="mute">' + ic("mic", 20) + ' Wycisz</span><span class="end">' + ic("phoneDown", 20) + " Zakończ</span></div>";
    else h += '<div class="home-bar"><div class="home-pill"><span class="msg">' + ic("bubble", 21) + ' Wiadomości</span><i></i><span>' + ic("folder", 21) + ' Pliki</span></div><span class="plusb">' + ic("plus", 24) + "</span></div>";
    if (o.menu === "more") h += moreMenu();
    if (o.menu === "plus") h += plusMenu();
    return h + "</div>";
  }
  function moreMenu() {
    const it = (i, t, hl) => '<div class="it' + (hl ? " hl" : "") + '">' + ic(i, 22) + "<span>" + t + "</span></div>";
    return '<div class="pop" style="top:100px;right:14px;width:292px"><div class="hd">Doddy to AI, nie człowiek.</div>' +
      it("sliders", "Ustawienia") + it("translate", "Tłumacz", true) + it("search", "Znajdź coś") +
      '<div class="it">' + ic("timer", 22) + '<span>Skupienie, minutniki i stoper</span>' + ic("chevR", 14, "sub") + "</div>" +
      it("calendar", "Dzisiaj") + "<hr>" + it("sparkle", "Co potrafię") + "</div>";
  }
  function plusMenu() {
    const it = (i, t, hl) => '<div class="it' + (hl ? " hl" : "") + '">' + ic(i, 22) + "<span>" + t + "</span></div>";
    return '<div class="pop from-bottom" style="bottom:104px;right:16px;width:250px">' + it("camera", "Zrób zdjęcie", true) + it("photo", "Wybierz zdjęcie") + it("clip", "Dołącz plik") + it("pencil", "Nowa notatka") + "</div>";
  }

  function sheetHead() {
    return '<div class="grab"></div><div class="vs-head"><span class="chip">Zamknij</span><b>Porozmawiaj z Doddym</b><span class="roundb">' + ic("eyeSlash", 22) + "</span></div>";
  }
  function voice(o) {
    let h = '<div class="vs"><div class="vs-dim">' + strip(true) + '</div><div class="vs-sheet">' + sheetHead();
    h += '<div class="lpill">' + ic("mic", 16) + "<span>Doddy słucha</span><b>Przestań słuchać</b></div>";
    h += '<div class="vs-status"><div class="sprite-box">' + pose("reaching_high") + "</div><b>Słucham</b></div>";
    h += '<div class="vs-lines">' + o.lines.map(l => '<div' + rv(l.at + "-99", "ln " + l.who) + ">" + l.text + "</div>").join("") + "</div>";
    h += (o.card || "");
    h += '<div class="vs-bottom"><span>' + ic("hand", 20) + ' Słuchaj, aż skończę</span><div class="row2"><span>' + ic("mic", 20) + ' Wycisz</span><span class="end">' + ic("phoneDown", 20) + " Zakończ</span></div></div>";
    return h + "</div></div>";
  }
  function cardReminder(at) {
    return '<div' + rv(at + "-99", "card") + '><div class="t">Dodać to przypomnienie?</div><div class="m">Odebrać paczkę</div><div class="s">niedz., 8 lis 2026, 18:00</div>' +
      '<div class="bp">Dodaj ' + ic("check", 22) + '</div><div class="bs">Nie dodawaj</div></div>';
  }
  function cardMemory(at) {
    return '<div' + rv(at + "-99", "card") + '><div class="t">Zapisać tę notatkę?</div><div class="m">„Auto stoi na poziomie -2, sektor B.”</div>' +
      '<div><span class="pick">Miejsce ' + ic("chevUD", 16) + '</span></div><div class="bp">Zapisz ' + ic("check", 22) + '</div><div class="bs">Nie zapisuj</div></div>';
  }

  function menuCard(hl, cls) {
    const it = (a, b, on) => '<div class="it' + (on ? " hl" : "") + '"><span>' + a + "</span><span>" + b + "</span></div>";
    return '<div class="menu-card ' + (cls || "") + '"><h4>TRATTORIA</h4><div class="sub">ROMA</div><div class="sec-t">PRIMI</div>' +
      it("Spaghetti alla carbonara", "12 €") + it("Tagliatelle ai funghi porcini", "14 €", hl) + it("Penne all’arrabbiata", "11 €") + it("Risotto al limone", "13 €") +
      '<div class="sec-t">SECONDI</div>' + it("Saltimbocca alla romana", "18 €") + it("Pollo alla diavola", "16 €") + "</div>";
  }

  function messages(o) {
    let h = '<div class="ms"><div class="ms-sheet">' + sb();
    h += '<div class="ms-head"><span class="chip">Zamknij</span><img class="wm" src="' + W + '" alt="Doddy"></div>';
    if (o.empty) h += '<div' + rv(o.empty, "ms-empty") + "><h3>Zapytaj mnie o cokolwiek.</h3></div>";
    h += '<div class="ms-thread">';
    (o.items || []).forEach(m => {
      if (m.who === "me") {
        h += '<div' + rv(m.at + "-99", "ms-row me gone") + ">" + (m.photo ? '<span class="ms-meta">' + ic("photo", 14) + " Zdjęcie</span>" : "") +
          '<div class="bub">' + m.text + "</div>" + (m.sending != null ? '<span' + rv(m.sending, "ms-meta gone") + ">Wysyłanie…</span>" : "") + "</div>";
        if (m.sending != null) h += '<div' + rv(m.sending, "ms-row dd gone") + '><div class="bub typing"><i></i><i></i><i></i></div></div>';
      } else {
        h += '<div' + rv(m.at + "-99", "ms-row dd gone") + '><div class="bub">' + m.text + "</div></div>";
        if (m.basis === "notes") {
          h += '<div' + rv(m.at + "-99", "basis gone") + '><span class="lab">' + ic("note", 15) + " Z Twoich zapisanych notatek</span>" +
            m.notes.map(n => '<div class="note"><span class="nt">' + n.text + '</span><span class="nm">' + n.meta + "</span></div>").join("") + "</div>";
        } else if (m.basis === "general") {
          h += '<div' + rv(m.at + "-99", "basis gone") + '><span class="gen">' + ic("info", 14) + " Nie z Twoich notatek. To ogólna odpowiedź.</span></div>";
        }
      }
    });
    h += '</div>';
    h += '<div class="ms-comp"><div class="ms-doddy">' + sprite("idle", 4, 2) + "</div>";
    if (o.chip) h += '<div' + rv(o.chip, "ms-chip gone") + '><span class="th">' + menuCard(false, "thumb") + "</span>Zdjęcie pójdzie z twoją następną wiadomością<span class=\"x\">" + ic("xfill", 22) + "</span></div>";
    const d = o.draft || { show: "-1--1", text: "" };
    h += '<div class="ms-row-in"><span class="ms-plus">' + ic("plus", 18) + '</span><span class="ms-photo">' + ic("photo", 25) + "</span>" +
      '<div class="ms-field"><span' + rv(o.placeholder || "0-99", "ph gone") + ">Zadaj pytanie</span>" +
      '<span' + rv(d.show, "tx gone") + ' data-text="' + d.text + '">' + d.text + '<span class="caret"></span></span>' +
      '<span class="ms-mic" data-cls="' + (o.micLive ? "live:" + o.micLive : "") + '">' + ic("mic", 18, "i-mic") + ic("stopCircle", 22, "i-stop") + "</span>" +
      '<span class="ms-send" data-cls="' + (d.show ? "ready:" + d.show : "") + (o.sending ? ";sending:" + o.sending : "") + '">' + ic("arrowUp", 18, "i-up") + ic("stop", 16, "i-stop") + "</span></div></div>";
    return h + "</div></div></div>";
  }

  function translator(o) {
    let h = '<div class="vs"><div class="vs-dim">' + strip(true) + '</div><div class="vs-sheet">' + sheetHead() + '<div class="tr">';
    h += '<div class="tr-their"><p class="tr-ai">Traducción con IA · puede tener errores</p>' +
      '<p' + rv("0-" + (o.req - 1), "tr-line gone") + ">Hola, soy Doddy, un traductor de IA en este teléfono. Traduciré entre ustedes dos. Hable con normalidad.</p>" +
      '<p' + rv(o.req + "-99", "tr-line gone") + ">¿Nos da una mesa junto a la ventana para dos personas?</p></div>";
    h += '<div class="tr-bar"><i class="g"></i><span>Słucham</span><span class="codes">PL ⇄ ES</span><span class="endb">Zakończ</span></div>';
    h += '<div class="tr-own"><p' + rv(o.ans + "-99", "tr-line gone") + ">Oczywiście. Stolik przy oknie będzie wolny za pięć minut.</p>" +
      '<p' + rv(o.ans + "-99", "tr-disc gone") + ">Pokaż, co powiedzieli " + ic("chevR", 12) + "</p>" +
      '<div class="tr-btns"><span>' + ic("replay", 16) + " Powiedz to jeszcze raz</span><span>" + ic("pause", 16) + " Pauza</span></div>" +
      '<div class="tr-tog">Głośne miejsce: przytrzymaj, aby mówić<i class="sw"></i></div></div>';
    return h + "</div></div></div>";
  }

  function islandBoard() {
    let h = '<div class="spring">' + sb(true) + '<div class="grid">' + "<i></i>".repeat(16) + '</div><div class="dock"><i></i><i></i><i></i><i></i></div></div>';
    h += '<div class="di">';
    h += '<div class="c-row"><span class="face"><img src="assets/pose-listening.png" alt=""></span><span class="cw">' + bars(7) + "</span></div>";
    h += '<div' + rv("1-1", "x-row gone") + '><span class="lab">GŁOS <i>●</i> LIVE</span><span class="time">0:04</span><div class="art">' + pose("listening") + "</div>" +
      '<div class="body"><span class="ttl">Słucham</span><span class="sub">Mów śmiało, jestem tu</span>' +
      '<svg class="wave" viewBox="0 0 240 18" preserveAspectRatio="none"><path d="M0 9 C 20 2, 40 16, 60 9 S 100 2, 120 9 S 160 16, 180 9 S 220 2, 252 9"/><path class="w2" d="M0 10 C 25 15, 45 4, 70 10 S 110 15, 135 10 S 175 4, 200 10 S 235 15, 252 10"/></svg>' +
      '<div class="btns"><span>' + ic("micSlash", 12) + " Wycisz</span><span>" + ic("open", 12) + " Otwórz</span><span>" + ic("stop", 12) + " Stop</span></div></div></div>";
    h += '<div' + rv("2-99", "x-row gone") + '><span class="lab">GŁOS</span><span class="time">0:09</span><div class="art">' + pose("reaching_high") + "</div>" +
      '<div class="body"><span class="ttl">Potwierdź w Doddym</span><span class="sub">Otwórz Doddy’ego, zobacz i zdecyduj</span>' +
      '<div class="btns"><span>' + ic("micSlash", 12) + ' Wycisz</span><span class="cream show">' + ic("hand", 13) + " Pokaż</span><span>" + ic("stop", 12) + " Stop</span></div></div></div>";
    return h + "</div>";
  }

  function camera() {
    return '<div class="cam">' + sb(true) + '<div class="vf">' + menuCard(false) + '</div><div class="shutter"></div><div class="flash"></div></div>';
  }

  /* ───────── the six scenes ───────── */
  const HOME_DODDY = [201, 396];
  const NOTE_META = "Twoja notatka głosowa · 8 lis 2026, 14:05";

  const SCENES = [
    {
      id: "s1", no: "01", name: "Pierwsza rozmowa",
      headline: "Obiad w&nbsp;20 minut? Stuknij i&nbsp;zapytaj.",
      heads: [
        { t: "Obiad w 20 minut? Stuknij i zapytaj.", why: "Sytuacja, którą zna każdy, i gest, od którego się zaczyna.", pick: true },
        { t: "Masz sprawę? Powiedz.", why: "Pasuje do każdego asystenta głosowego (nagłówek z v4)." },
        { t: "Mało czasu na obiad? Powiedz.", why: "Konkretne, ale nie mówi, czego dotknąć." },
        { t: "Twój kumpel w kieszeni.", why: "Hasło marki, a nie scena; nic nie obiecuje ani nie pokazuje." },
        { t: "Pytasz na głos, masz plan.", why: "„Plan” to obietnica, której ekran nie pokazuje." }
      ],
      beats: [
        { k: "Sytuacja", v: "Wracasz do domu. Na obiad zostało dwadzieścia minut, pomysłu brak." },
        { k: "Start", v: "Stuknij Doddy’ego na ekranie głównym. Podskoczy i zacznie słuchać." },
        { k: "Zdanie", v: "<q>Mam 20 minut. Co mogę zrobić na obiad?</q>" },
        { k: "Wynik", v: "Doddy odpowiada głosem. Całą rozmowę widać w „Zapisie rozmowy”." }
      ],
      needs: "<b>Za pierwszym razem:</b> zgoda na przesyłanie głosu do ElevenLabs i dostęp do mikrofonu. Rozmowa wymaga połączenia z internetem.",
      proof: [
        ["ci", "Ekran główny i podskok po stuknięciu: zrzuty z CI (symulator, 2 lis) i <code>HomeView.swift</code>."],
        ["code", "Rozmowa na ekranie głównym i „Zapis rozmowy”: w kodzie (ADR-595). Zrzuty z CI działają offline, więc rozmowy na nich nie ma."],
        ["ex", "Treść odpowiedzi to przykład. Odpowiedź modelu nie była sprawdzana."]
      ],
      situ: { sprite: pose("shrug"), text: "Wracasz do domu. Obiad za 20 minut." },
      ovs: {
        say: '<div class="ov ov-say">„Mam 20 minut. Co mogę zrobić na obiad?”</div>',
        n1: '<div class="ov ov-note"><b>Doddy odpowiada głosem.</b> Słowa są w „Zapisie rozmowy”.</div>'
      },
      frames: {
        rest: () => home({}),
        talk: () => home({ talking: true, speakFrom: 2, loud: "late" }),
        sheet: () => voice({ lines: [
          { who: "me", text: "Mam 20 minut. Co mogę zrobić na obiad?", at: 0 },
          { who: "dd", text: "Makaron z czosnkiem i oliwą zrobisz w kwadrans. Masz makaron i czosnek?", at: 1 }] })
      },
      steps: [
        { b: 0, f: "rest", at: 0, d: 2600, ov: ["situ"] },
        { b: 1, f: "rest", at: 0, d: 1100, ov: ["situ"], tap: HOME_DODDY, set: { ".home-doddy": "+hop" } },
        { b: 2, f: "talk", tr: "fade", at: 0, d: 3000, ov: ["say"] },
        { b: 3, f: "talk", at: 2, d: 2600, ov: ["n1"] },
        { b: 3, f: "talk", at: 2, d: 900, ov: ["n1"], tap: ".cap" },
        { b: 3, f: "sheet", tr: "sheet", at: 0, d: 1200, ov: [] },
        { b: 3, f: "sheet", at: 1, d: 4200, ov: [] }
      ],
      shot: { h: "Obiad w&nbsp;20 minut?<br>Stuknij i&nbsp;zapytaj.", frame: "sheet", at: 1, situ: "Wracasz do domu. Obiad za 20 minut.", say: "„Mam 20 minut. Co mogę zrobić na obiad?”", start: ["hand", "Stuknij Doddy’ego na ekranie głównym"], deco: "pose-listening" }
    },
    {
      id: "s2", no: "02", name: "Coś właśnie się przypomniało",
      headline: "Paczka o&nbsp;18? Naciśnij i&nbsp;powiedz.",
      heads: [
        { t: "Paczka o 18? Naciśnij i powiedz.", why: "Konkretna sprawa, godzina i sposób startu w sześciu słowach.", pick: true },
        { t: "Przypomniało Ci się? Powiedz od razu.", why: "Dobre, ale ogólne; nie pokazuje przycisku (nagłówek z v4)." },
        { t: "Przypomnienie bez otwierania aplikacji.", why: "Nieprawda: zatwierdzenie karty otwiera Doddy’ego." },
        { t: "Zajęte ręce? Wystarczy przycisk.", why: "Obiecuje za dużo: trzeba jeszcze stuknąć „Dodaj”." },
        { t: "Jeden przycisk. Jedno zdanie.", why: "Abstrakcyjne; nie ma sytuacji ani wyniku." }
      ],
      beats: [
        { k: "Sytuacja", v: "Niesiesz zakupy i nagle przypomina Ci się paczka w paczkomacie." },
        { k: "Start", v: "Naciśnij przycisk czynności. Rozmowa toczy się w Dynamic Island, bez otwierania aplikacji." },
        { k: "Zdanie", v: "<q>Przypomnij mi odebrać paczkę o osiemnastej.</q>" },
        { k: "Wynik", v: "Wyspa prosi o potwierdzenie. „Pokaż” otwiera kartę „Dodać to przypomnienie?”. Bez stuknięcia „Dodaj” nic się nie doda." }
      ],
      needs: "<b>Raz:</b> Ustawienia iPhone’a › Przycisk czynności › Sterowanie › Porozmawiaj z Doddym; Aktywności na żywo włączone; dostęp do Przypomnień. <b>Zgodność:</b> przycisk czynności mają tylko niektóre iPhone’y (od iPhone’a 15 Pro); rozmowa w wyspie wymaga iOS 18 lub nowszego i iPhone’a z Dynamic Island (iPhone 16e ma przycisk, ale nie ma wyspy). Bez przycisku: przycisk Doddy’ego w Centrum sterowania albo stuknięcie w tył telefonu.",
      proof: [
        ["ci", "Wyspa „Słucham” i „Potwierdź w Doddym” oraz karta przypomnienia: zrzuty z CI (symulator; wyspa pokazana na danych testowych, bez prawdziwej rozmowy)."],
        ["no", "Przycisk czynności → rozmowa w wyspie: nie sprawdzone na urządzeniu; wszystkie 16 przypadków w <code>ACTION_BUTTON_ISLAND.md</code> ma status NOT VERIFIED."],
        ["ex", "Linia Doddy’ego i data na karcie to przykład."]
      ],
      situ: { sprite: sprite("run", 6, 10), text: "Ręce zajęte. Nagle: paczka!" },
      ovs: {
        ab: '<div class="ov ov-ab"><span>przycisk<br>czynności</span><svg viewBox="0 0 60 30" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M2 8 C 22 2, 40 6, 54 18"/><path d="M44 18 L55 19 L52 8"/></svg></div>',
        setup: '<div class="ov ov-setup">Raz: Ustawienia › Przycisk czynności › Sterowanie › Porozmawiaj z Doddym</div>',
        say: '<div class="ov ov-say">„Przypomnij mi odebrać paczkę o osiemnastej.”</div>',
        n1: '<div class="ov ov-note"><b>Wyspa prosi o decyzję.</b> „Pokaż” otwiera kartę w Doddym.</div>',
        n2: '<div class="ov ov-note">Nic się nie doda, dopóki nie stukniesz <b>Dodaj</b>.</div>'
      },
      frames: {
        board: () => islandBoard(),
        sheet: () => voice({ lines: [
          { who: "me", text: "Przypomnij mi odebrać paczkę o osiemnastej.", at: 0 },
          { who: "dd", text: "Dziś o 18:00. Stuknij Dodaj, jeśli się zgadza.", at: 0 }], card: cardReminder(1) })
      },
      steps: [
        { b: 0, f: "board", at: 0, d: 2600, ov: ["situ", "ab"] },
        { b: 1, f: "board", at: 0, d: 900, ov: ["ab", "setup"], press: true, set: { ".di": "=di compact" } },
        { b: 1, f: "board", at: 1, d: 1600, ov: ["setup"], set: { ".di": "=di x live" } },
        { b: 2, f: "board", at: 1, d: 3200, ov: ["say"], set: { ".di": "=di x live" } },
        { b: 3, f: "board", at: 2, d: 2600, ov: ["n1"], set: { ".di": "=di x confirm" } },
        { b: 3, f: "board", at: 2, d: 900, ov: ["n1"], set: { ".di": "=di x confirm" }, tap: ".di .show" },
        { b: 3, f: "sheet", tr: "sheet", at: 0, d: 1200, ov: [] },
        { b: 3, f: "sheet", at: 1, d: 4400, ov: ["n2"] }
      ],
      shot: { h: "Paczka o&nbsp;18?<br>Naciśnij i&nbsp;powiedz.", frame: "sheet", at: 1, situ: "Ręce zajęte zakupami. Nagle: paczka.", say: "„Przypomnij mi odebrać paczkę o osiemnastej.”", start: ["action", "Naciśnij przycisk czynności"], deco: "run-3", press: true }
    },
    {
      id: "s3", no: "03", name: "Powrót do zapisanej informacji",
      headline: "Gdzie auto? Odpowiedź z&nbsp;Twojej notatki.",
      heads: [
        { t: "Gdzie auto? Odpowiedź z Twojej notatki.", why: "Pytanie z życia i to, co wyróżnia Doddy’ego: widać, skąd jest odpowiedź.", pick: true },
        { t: "Gdzie stoi auto? Doddy ma notatkę.", why: "Dobre, ale brzmi, jakby notatka należała do Doddy’ego (v4)." },
        { t: "Zapisz poziom. Zapytaj przy powrocie.", why: "Jasne kroki, bez korzyści, jaką daje źródło." },
        { t: "Poziom -2, sektor B. Zapamiętane.", why: "Sugeruje zapis bez Twojej zgody; karta wymaga „Zapisz”." },
        { t: "Twoja pamięć zewnętrzna.", why: "Slogan, który pasuje do każdej aplikacji z notatkami." }
      ],
      beats: [
        { k: "Sytuacja", v: "Parking podziemny. Za trzy godziny nie będziesz pamiętać poziomu." },
        { k: "Start", v: "Stuknij Doddy’ego i powiedz. Później otwórz Wiadomości." },
        { k: "Zdanie", v: "<q>Zapamiętaj: auto stoi na poziomie -2, sektor B.</q> Później: <q>Gdzie zostawiłem auto?</q>" },
        { k: "Wynik", v: "Pod odpowiedzią „Z Twoich zapisanych notatek” i sama notatka z datą." }
      ],
      needs: "Notatka zapisuje się dopiero po stuknięciu <b>Zapisz</b>. Pytania w Wiadomościach: włącz „Zapytaj Doddy’ego” w Ustawieniach; pytanie i pasujące notatki trafiają na serwer Doddy’ego i do Anthropic. Przełącznik „Używaj pasujących zapisanych notatek” jest pod <b>+</b>.",
      proof: [
        ["ci", "Karta „Zapisać tę notatkę?”: zrzut z CI (symulator)."],
        ["code", "„Z Twoich zapisanych notatek” z treścią i datą notatki: <code>MessagesView.swift</code>. Brak zrzutu: w CI Wiadomości nie mają serwera."],
        ["ex", "Obie rozmowy to przykład. Trafność wyszukania notatki nie była mierzona."]
      ],
      situ: { sprite: pose("kneeling_inspect"), text: "Parking podziemny. Który to był poziom?" },
      ovs: {
        say1: '<div class="ov ov-say">„Zapamiętaj: auto stoi na poziomie -2, sektor B.”</div>',
        jump: '<div class="ov ov-jump">3 godziny później</div>',
        say2: '<div class="ov ov-say">„Gdzie zostawiłem auto?”</div>',
        n1: '<div class="ov ov-note ov-arrow-left"><b>Źródło odpowiedzi:</b> Twoja notatka, z datą zapisu.</div>'
      },
      frames: {
        rest: () => home({}),
        sheet: () => voice({ lines: [
          { who: "me", text: "Zapamiętaj: auto stoi na poziomie -2, sektor B.", at: 0 },
          { who: "dd", text: "Mam. Stuknij Zapisz, jeśli się zgadza.", at: 1 }], card: cardMemory(1) }),
        rest2: () => home({}),
        msgs: () => messages({ sending: "2-2", empty: "0-1", placeholder: "0-0,2-99", draft: { text: "Gdzie zostawiłem auto?", show: "1-1" },
          items: [
            { who: "me", text: "Gdzie zostawiłem auto?", at: 2, sending: "2-2" },
            { who: "dd", text: "Na poziomie -2, w sektorze B.", at: 3, basis: "notes", notes: [{ text: "Auto stoi na poziomie -2, sektor B.", meta: NOTE_META }] }] })
      },
      steps: [
        { b: 0, f: "rest", at: 0, d: 2600, ov: ["situ"] },
        { b: 1, f: "rest", at: 0, d: 1100, ov: ["situ"], tap: HOME_DODDY, set: { ".home-doddy": "+hop" } },
        { b: 2, f: "sheet", tr: "sheet", at: 0, d: 3000, ov: ["say1"] },
        { b: 2, f: "sheet", at: 1, d: 2600, ov: [] },
        { b: 2, f: "sheet", at: 1, d: 900, ov: [], tap: ".card .bp" },
        { b: 0, f: "rest2", tr: "fade", at: 0, d: 1900, ov: ["jump"] },
        { b: 1, f: "rest2", at: 0, d: 900, ov: [], tap: ".home-pill .msg" },
        { b: 2, f: "msgs", tr: "up", at: 0, d: 900, ov: [] },
        { b: 2, f: "msgs", at: 1, d: 2400, ov: ["say2"], type: ".ms-field .tx" },
        { b: 2, f: "msgs", at: 1, d: 700, ov: ["say2"], tap: ".ms-send" },
        { b: 3, f: "msgs", at: 2, d: 1300, ov: [] },
        { b: 3, f: "msgs", at: 3, d: 4600, ov: ["n1"] }
      ],
      shot: { h: "Gdzie auto?<br>Odpowiedź<br>z&nbsp;Twojej notatki.", frame: "msgs", at: 3, situ: "Parking podziemny. Który to był poziom?", say: "„Gdzie zostawiłem auto?”", start: ["bubble", "Wiadomości › zapytaj o zapisane"], deco: "pose-kneeling_inspect" }
    },
    {
      id: "s4", no: "04", name: "Rozmowa za granicą",
      headline: "Mówisz po polsku. Kelner słyszy hiszpański.",
      heads: [
        { t: "Mówisz po polsku. Kelner słyszy hiszpański.", why: "Dwie osoby, dwa języki i konkretna korzyść.", pick: true },
        { t: "Nie znasz słów? Dogadaj się.", why: "Ogólne; tak mógłby reklamować się każdy tłumacz (v4)." },
        { t: "Stolik przy oknie, po hiszpańsku.", why: "Konkretne, ale nie wiadomo, kto mówi i do kogo." },
        { t: "Tłumacz na stole, między wami.", why: "Opisuje ustawienie telefonu, nie korzyść." },
        { t: "Rozmawiaj bez barier językowych.", why: "Frazes z reklam tłumaczy; obietnica bez dowodu." }
      ],
      beats: [
        { k: "Sytuacja", v: "Restauracja w Walencji. Kelner mówi tylko po hiszpańsku." },
        { k: "Start", v: "••• › Tłumacz › Twarzą w twarz › Polski ⇄ Español › Zacznij tłumaczyć. Połóż telefon między wami." },
        { k: "Zdanie", v: "<q>Poprosimy stolik przy oknie dla dwóch osób.</q>" },
        { k: "Wynik", v: "Kelner czyta po hiszpańsku na swojej połowie ekranu, Ty widzisz odpowiedź po polsku na swojej." }
      ],
      needs: "Najpierw Doddy mówi rozmówcy w jego języku, że jest tłumaczem AI. Oba głosy trafiają do ElevenLabs; notatki, rozmowy i profil nie są wysyłane, a tekst znika po zakończeniu. Nie do nagłych wypadków.",
      proof: [
        ["no", "Tłumacz jest ukryty w wersji beta (decyzja <code>2026-11-07-release-scope</code>): nie ma go w menu •••, a narzędzie <code>start_translator</code> jest odrzucane. Plansza 4 może trafić do sklepu dopiero wtedy, gdy właściciel go odkryje."],
        ["code", "Ekran „Twarzą w twarz” i hiszpańskie zdania Doddy’ego: <code>TranslatorViews.swift</code>, <code>Translator.swift</code>. Tego ekranu nie ma w atlasie zrzutów CI."],
        ["ci", "Wyspa „Tłumaczę” z kodami języków: zrzut z CI (symulator)."],
        ["no", "Pasek tłumacza pokazuje dziś „Listening” po angielsku; na planszy jest „Słucham”, czyli stan po poprawce tłumaczenia."],
        ["ex", "Zdania kelnera i tłumaczenia to przykład."]
      ],
      situ: { sprite: pose("shrug"), text: "Walencja. Kelner mówi tylko po hiszpańsku." },
      ovs: {
        setup: '<div class="ov ov-setup">Twarzą w twarz · Polski ⇄ Español · Zacznij tłumaczyć</div>',
        n0: '<div class="ov ov-note"><b>Najpierw</b> Doddy mówi kelnerowi po hiszpańsku, że jest tłumaczem AI.</div>',
        say: '<div class="ov ov-say">„Poprosimy stolik przy oknie dla dwóch osób.”</div>',
        es: '<div class="ov ov-say es right">„Claro. La mesa junto a la ventana estará libre en cinco minutos.”</div>',
        n1: '<div class="ov ov-note">Kelner czyta swoją połowę ekranu. <b>Ty swoją.</b></div>'
      },
      frames: {
        rest: () => home({}),
        menu: () => home({ menu: "more" }),
        tr: () => translator({ req: 1, ans: 2 })
      },
      steps: [
        { b: 0, f: "rest", at: 0, d: 2600, ov: ["situ"] },
        { b: 1, f: "rest", at: 0, d: 800, ov: [], tap: ".more" },
        { b: 1, f: "menu", tr: "none", at: 0, d: 1300, ov: [] },
        { b: 1, f: "menu", at: 0, d: 800, ov: [], tap: ".pop .it.hl" },
        { b: 1, f: "tr", tr: "sheet", at: 0, d: 1500, ov: ["setup"] },
        { b: 1, f: "tr", at: 0, d: 2800, ov: ["n0"] },
        { b: 2, f: "tr", at: 1, d: 3200, ov: ["say"] },
        { b: 3, f: "tr", at: 2, d: 3000, ov: ["es"] },
        { b: 3, f: "tr", at: 2, d: 3800, ov: ["n1"] }
      ],
      shot: { h: "Mówisz po polsku.<br>Kelner słyszy<br>hiszpański.", frame: "tr", at: 2, situ: "Walencja. Kelner mówi tylko po hiszpańsku.", say: "„Poprosimy stolik przy oknie dla dwóch osób.”", start: ["translate", "••• › Tłumacz › Twarzą w twarz"], deco: "talk-2" }
    },
    {
      id: "s5", no: "05", name: "Pytanie do zdjęcia",
      headline: "Menu po włosku? Zrób zdjęcie i&nbsp;zapytaj.",
      heads: [
        { t: "Menu po włosku? Zrób zdjęcie i zapytaj.", why: "Sytuacja i dwa proste kroki; czytelne w miniaturze.", pick: true },
        { t: "Nie przepisuj. Pokaż zdjęcie.", why: "Dobre, ale nie mówi, w jakiej sytuacji pomaga (v4)." },
        { t: "Zdjęcie karty, odpowiedź po polsku.", why: "Konkretne, ale mniej naturalne w mowie." },
        { t: "Pytaj o to, co widzisz.", why: "Pasuje do każdego asystenta ze zdjęciami." },
        { t: "Rozumie każde menu.", why: "Obietnica bez dowodu; trafności nikt nie mierzył." }
      ],
      beats: [
        { k: "Sytuacja", v: "Trattoria w Rzymie. Karta tylko po włosku." },
        { k: "Start", v: "Stuknij <b>+</b> na ekranie głównym › Zrób zdjęcie. Zdjęcie trafia do Wiadomości, nad pole pytania." },
        { k: "Zdanie", v: "<q>Który to makaron z grzybami?</q>" },
        { k: "Wynik", v: "Odpowiedź wskazuje danie z karty. W rozmowie zostaje tylko słowo „Zdjęcie”, samo zdjęcie nie jest przechowywane." }
      ],
      needs: "Włącz „Zapytaj Doddy’ego” w Ustawieniach. Zdjęcie i pytanie trafiają na serwer Doddy’ego i do Anthropic; zdjęcie nie zostaje ani na iPhonie, ani na serwerze.",
      proof: [
        ["code", "<b>+</b> › Zrób zdjęcie › Wiadomości ze zdjęciem nad polem (od 5 lis), etykieta „Zdjęcie” w wątku: <code>HomeView.swift</code>, <code>MessagePhotoPicker.swift</code>, <code>MessagesView.swift</code>. Brak zrzutu z CI."],
        ["no", "Czy odczyt karty jest trafny: nie mierzono."],
        ["ex", "Karta dań i odpowiedź to przykład."]
      ],
      situ: { sprite: pose("belly_reading"), text: "Rzym. Karta tylko po włosku." },
      ovs: {
        menu: '<div class="ov ov-menu">' + menuCard(false) + "</div>",
        menuhl: '<div class="ov ov-menu">' + menuCard(true) + "</div>",
        n0: '<div class="ov ov-note">Zdjęcie czeka nad polem pytania.</div>',
        say: '<div class="ov ov-say right">„Który to makaron z grzybami?”</div>',
        n1: '<div class="ov ov-note">W rozmowie zostaje słowo <b>„Zdjęcie”</b>. Samo zdjęcie nie jest przechowywane.</div>'
      },
      frames: {
        rest: () => home({}),
        plus: () => home({ menu: "plus" }),
        cam: () => camera(),
        msgs: () => messages({ sending: "2-2", chip: "0-1", placeholder: "0-0,2-99", draft: { text: "Który to makaron z grzybami?", show: "1-1" },
          items: [
            { who: "me", photo: true, text: "Który to makaron z grzybami?", at: 2, sending: "2-2" },
            { who: "dd", text: "To „Tagliatelle ai funghi porcini”, druga pozycja w części Primi. Kosztuje 14 €.", at: 3, basis: "general" }] })
      },
      steps: [
        { b: 0, f: "rest", at: 0, d: 2600, ov: ["situ", "menu"] },
        { b: 1, f: "rest", at: 0, d: 800, ov: [], tap: ".plusb" },
        { b: 1, f: "plus", tr: "none", at: 0, d: 1200, ov: [] },
        { b: 1, f: "plus", at: 0, d: 800, ov: [], tap: ".pop .it.hl" },
        { b: 1, f: "cam", tr: "up", at: 0, d: 1500, ov: [] },
        { b: 1, f: "cam", at: 0, d: 900, ov: [], tap: ".shutter", set: { ".flash": "+on" } },
        { b: 2, f: "msgs", tr: "fade", at: 0, d: 1500, ov: ["n0"] },
        { b: 2, f: "msgs", at: 1, d: 2400, ov: ["say"], type: ".ms-field .tx" },
        { b: 2, f: "msgs", at: 1, d: 700, ov: ["say"], tap: ".ms-send" },
        { b: 3, f: "msgs", at: 2, d: 1300, ov: [] },
        { b: 3, f: "msgs", at: 3, d: 4600, ov: ["menuhl", "n1"] }
      ],
      shot: { h: "Menu po włosku?<br>Zrób zdjęcie<br>i&nbsp;zapytaj.", frame: "msgs", at: 3, situ: "Rzym. Karta tylko po włosku.", say: "„Który to makaron z grzybami?”", start: ["camera", "Stuknij + › Zrób zdjęcie"], deco: "pose-belly_reading", decoStyle: "top:262px;right:4px;width:104px;height:156px" }
    },
    {
      id: "s6", no: "06", name: "Pomysł z dostępnych składników",
      headline: "Jajka, pomidory, feta? Doddy podpowie obiad.",
      heads: [
        { t: "Jajka, pomidory, feta? Doddy podpowie obiad.", why: "Lista z lodówki, którą odbiorca rozpoznaje, i jasny wynik.", pick: true },
        { t: "Z tego, co masz w lodówce.", why: "Dobre, ale bez konkretu (v4)." },
        { t: "Trzy składniki, jeden obiad.", why: "Rytmiczne, ale brzmi jak gwarancja." },
        { t: "Co ugotować? Wymień, co masz.", why: "Naturalne; w miniaturze słabsze, bo bez konkretnych produktów." },
        { t: "Koniec z marnowaniem jedzenia.", why: "Obietnica bez dowodu." }
      ],
      beats: [
        { k: "Sytuacja", v: "Wieczór. W lodówce: jajka, pomidory i feta." },
        { k: "Start", v: "Otwórz Wiadomości i stuknij mikrofon w polu pytania. Albo stuknij Doddy’ego i powiedz." },
        { k: "Zdanie", v: "<q>Mam jajka, pomidory i fetę. Co z tego zrobię?</q>" },
        { k: "Wynik", v: "Propozycja dania w kilku krokach i jedno pytanie, które ją dopasowuje." }
      ],
      needs: "Włącz „Zapytaj Doddy’ego” w Ustawieniach. Pod odpowiedzią widać, czy pochodzi z Twoich notatek; tu: „Nie z Twoich notatek. To ogólna odpowiedź.”",
      proof: [
        ["code", "Dyktowanie w polu pytania i etykieta „Nie z Twoich notatek”: <code>MessagesView.swift</code> (<code>MESSAGES_DICTATION.md</code>). Brak zrzutu z CI."],
        ["ex", "Przepis i pytanie to przykładowa odpowiedź modelu, niesprawdzona."]
      ],
      situ: { sprite: pose("fistpump"), text: "Wieczór. Co jest w lodówce?" },
      ovs: {
        fridge: '<div class="ov ov-fridge">jajka<br>pomidory<br>feta<br><s>pomysł na obiad</s></div>',
        say: '<div class="ov ov-say right">„Mam jajka, pomidory i fetę. Co z tego zrobię?”</div>',
        n1: '<div class="ov ov-note">Propozycja i <b>jedno pytanie</b>, które ją dopasowuje.</div>'
      },
      frames: {
        rest: () => home({}),
        msgs: () => messages({ sending: "2-2", empty: "0-1", placeholder: "0-0,2-99", micLive: "1-1", draft: { text: "Mam jajka, pomidory i fetę. Co z tego zrobię?", show: "1-1" },
          items: [
            { who: "me", text: "Mam jajka, pomidory i fetę. Co z tego zrobię?", at: 2, sending: "2-2" },
            { who: "dd", text: "Szakszukę z fetą. Podsmaż pomidory, wbij jajka, przykryj na 5 minut, na koniec pokrusz fetę. Masz cebulę albo chleb do maczania?", at: 3, basis: "general" },
            { who: "me", text: "Mam tylko chleb.", at: 4 },
            { who: "dd", text: "Wystarczy. Podpiecz kromki na suchej patelni, zanim wbijesz jajka.", at: 5, basis: "general" }] })
      },
      steps: [
        { b: 0, f: "rest", at: 0, d: 2600, ov: ["situ", "fridge"] },
        { b: 1, f: "rest", at: 0, d: 800, ov: ["fridge"], tap: ".home-pill .msg" },
        { b: 1, f: "msgs", tr: "up", at: 0, d: 1000, ov: ["fridge"] },
        { b: 1, f: "msgs", at: 0, d: 800, ov: ["fridge"], tap: ".ms-mic" },
        { b: 2, f: "msgs", at: 1, d: 3200, ov: ["say"], type: ".ms-field .tx" },
        { b: 2, f: "msgs", at: 1, d: 700, ov: ["say"], tap: ".ms-send" },
        { b: 3, f: "msgs", at: 2, d: 1200, ov: [] },
        { b: 3, f: "msgs", at: 3, d: 3800, ov: ["n1"] },
        { b: 3, f: "msgs", at: 4, d: 1500, ov: [] },
        { b: 3, f: "msgs", at: 5, d: 4000, ov: [] }
      ],
      shot: { h: "Jajka, pomidory,<br>feta? Doddy<br>podpowie obiad.", frame: "msgs", at: 3, situ: "Wieczór. W lodówce trzy rzeczy.", say: "„Mam jajka, pomidory i fetę. Co z tego zrobię?”", start: ["mic", "Wiadomości › mikrofon w polu"], deco: "pose-reaching_high" }
    }
  ];

  /* ───────── reveal / state machinery ───────── */
  function inRanges(spec, k) {
    if (!spec) return false;
    return spec.split(",").some(r => {
      const m = r.match(/^(-?\d+)-(-?\d+)$/);
      if (!m) return false;
      return k >= +m[1] && k <= +m[2];
    });
  }
  function applyAt(layer, k) {
    layer.querySelectorAll("[data-show]").forEach(el => el.classList.toggle("on", inRanges(el.getAttribute("data-show"), k)));
    layer.querySelectorAll("[data-cls]").forEach(el => {
      const spec = el.getAttribute("data-cls");
      if (!spec) return;
      spec.split(";").forEach(pair => {
        const i = pair.indexOf(":");
        if (i < 0) return;
        el.classList.toggle(pair.slice(0, i), inRanges(pair.slice(i + 1), k));
      });
    });
  }
  function applySet(layer, set) {
    if (!set) return;
    Object.keys(set).forEach(sel => {
      const v = set[sel];
      layer.querySelectorAll(sel).forEach(el => {
        if (v[0] === "=") el.className = v.slice(1);
        else if (v[0] === "+") { const c = v.slice(1); el.classList.remove(c); void el.offsetWidth; el.classList.add(c); }
      });
    });
  }

  /* sprites: one shared clock */
  const sprites = new Set();
  function registerSprites(root) {
    root.querySelectorAll(".sprite[data-fps]").forEach(s => { s._i = 0; s._t = 0; sprites.add(s); });
  }
  if (!reduce) {
    let last = performance.now();
    const tick = now => {
      const dt = now - last; last = now;
      sprites.forEach(s => {
        if (!s.isConnected) { sprites.delete(s); return; }
        const fps = +s.getAttribute("data-fps");
        s._t += dt;
        if (s._t >= 1000 / fps) {
          s._t = 0;
          const imgs = s.children;
          imgs[s._i].classList.remove("cur");
          s._i = (s._i + 1) % imgs.length;
          imgs[s._i].classList.add("cur");
        }
      });
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  }

  /* ───────── phone ───────── */
  function phoneHTML() {
    return '<div class="phone"><span class="side ab"></span><span class="side v1"></span><span class="side v2"></span><span class="side pw"></span>' +
      '<div class="screen"><div class="hw-island"></div><span class="tap"></span></div></div>';
  }

  class Player {
    constructor(scene, stage) {
      this.s = scene; this.stage = stage;
      this.wrap = stage.querySelector(".phone-wrap");
      this.phone = stage.querySelector(".phone");
      this.screen = stage.querySelector(".screen");
      this.tapEl = stage.querySelector(".tap");
      this.layer = null; this.key = null; this.i = -1; this.timer = null; this.typer = null;
      this.beatEls = Array.from(document.querySelectorAll('[data-scene="' + scene.id + '"] .beat'));
      // per-beat durations for the progress bars
      this.beatTotal = [0, 0, 0, 0];
      scene.steps.forEach(st => { this.beatTotal[st.b] += st.d; });
    }
    mount(key, tr) {
      const html = this.s.frames[key]();
      const el = document.createElement("div");
      el.className = "layer";
      el.innerHTML = html;
      if (tr && tr !== "none" && !reduce) el.classList.add("t-" + tr);
      const old = this.layer;
      this.screen.insertBefore(el, this.tapEl);
      if (old) {
        if (tr && tr !== "none" && !reduce) { old.classList.add("out"); setTimeout(() => old.remove(), 420); }
        else old.remove();
      }
      this.layer = el; this.key = key;
      registerSprites(el);
    }
    show(i, animate) {
      const st = this.s.steps[i];
      if (st.f !== this.key) this.mount(st.f, animate ? (st.tr || "fade") : "none");
      applyAt(this.layer, st.at);
      applySet(this.layer, st.set);
      // overlays
      this.stage.querySelectorAll(".ov[data-ov]").forEach(o => o.classList.toggle("off", !(st.ov || []).includes(o.getAttribute("data-ov"))));
      // hardware button
      this.phone.classList.toggle("press", !!st.press);
      // typing
      if (this.typer) { clearInterval(this.typer); this.typer = null; }
      if (st.type && animate && !reduce) {
        const el = this.layer.querySelector(st.type);
        if (el) {
          const text = el.getAttribute("data-text") || "";
          const caret = '<span class="caret"></span>';
          let n = 0;
          el.innerHTML = caret;
          const per = Math.max(22, Math.min(55, (st.d - 500) / Math.max(1, text.length)));
          this.typer = setInterval(() => {
            n++;
            el.innerHTML = text.slice(0, n) + caret;
            if (n >= text.length) { clearInterval(this.typer); this.typer = null; }
          }, per);
        }
      }
      // tap
      if (st.tap && animate && !reduce) {
        let x, y;
        if (Array.isArray(st.tap)) { x = st.tap[0]; y = st.tap[1]; }
        else {
          const t = this.layer.querySelector(st.tap);
          if (t) {
            const r = t.getBoundingClientRect(), sr = this.screen.getBoundingClientRect();
            const k = sr.width / 402;
            x = (r.left + r.width / 2 - sr.left) / k; y = (r.top + r.height / 2 - sr.top) / k;
          }
        }
        if (x != null) {
          this.tapEl.style.left = x + "px"; this.tapEl.style.top = y + "px";
          this.tapEl.classList.remove("go"); void this.tapEl.offsetWidth; this.tapEl.classList.add("go");
        }
      }
      // beats
      this.beatEls.forEach((b, j) => b.classList.toggle("on", j === st.b));
      if (animate && !reduce) {
        const done = this.s.steps.slice(0, i + 1).filter(x => x.b === st.b).reduce((a, x) => a + x.d, 0);
        const bar = this.beatEls[st.b] && this.beatEls[st.b].querySelector(".bar i");
        if (bar) { bar.style.transition = "width " + st.d + "ms linear"; bar.style.width = (100 * done / this.beatTotal[st.b]).toFixed(1) + "%"; }
      }
      this.i = i;
    }
    rest() {
      this.stop();
      this.show(this.s.steps.length - 1, false);
      this.beatEls.forEach(b => { const bar = b.querySelector(".bar i"); if (bar) { bar.style.transition = "none"; bar.style.width = "0"; } });
      this.playing = false;
    }
    stop() { clearTimeout(this.timer); this.timer = null; if (this.typer) { clearInterval(this.typer); this.typer = null; } }
    play(from) {
      this.stop();
      this.playing = true;
      if (!from) this.beatEls.forEach(b => { const bar = b.querySelector(".bar i"); if (bar) { bar.style.transition = "none"; bar.style.width = "0"; } });
      const run = i => {
        this.show(i, true);
        if (i + 1 < this.s.steps.length) this.timer = setTimeout(() => run(i + 1), this.s.steps[i].d);
        else this.timer = setTimeout(() => { this.playing = false; this.stage.classList.add("ended"); }, this.s.steps[i].d);
      };
      this.stage.classList.remove("ended");
      if (this.key && from === undefined) { this.layer.remove(); this.layer = null; this.key = null; }
      run(from || 0);
    }
  }

  /* ───────── page builders ───────── */
  function esc(t) { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;"); }
  function words(t) { return t.replace(/[„”?.,!]/g, " ").trim().split(/\s+/).filter(Boolean).length; }

  function stageHTML(sc) {
    let ovs = '<div class="ov ov-situ" data-ov="situ"><div class="sprite-box">' + sc.situ.sprite + '</div><div><small>sytuacja</small><p>' + sc.situ.text + "</p></div></div>";
    Object.keys(sc.ovs).forEach(k => { ovs += sc.ovs[k].replace('class="ov ', 'data-ov="' + k + '" class="ov '); });
    return '<div class="stage" aria-label="Animowana rekonstrukcja sceny ' + sc.no + '"><div class="phone-wrap">' + phoneHTML() + ovs + "</div>" +
      '<div class="stage-ctrl"><button class="btn replay" type="button">' + ic("replay", 16) + ' Odtwórz scenę</button></div></div>';
  }

  function sceneHTML(sc) {
    const beats = sc.beats.map((b, j) => '<li><button class="beat" type="button" data-b="' + j + '"><span class="n">' + (j + 1) + '</span><span class="t"><span class="k">' + b.k + '</span><span class="v">' + b.v + '</span></span><span class="bar"><i></i></span></button></li>').join("");
    const heads = sc.heads.map(h => '<li class="' + (h.pick ? "pick" : "") + '"><b>' + esc(h.t) + '</b><span><span class="words">' + words(h.t) + " słów.</span> " + h.why + "</span></li>").join("");
    const proof = sc.proof.map(p => '<li><span class="pill ' + p[0] + '">' + ({ ci: "zrzut z CI", code: "w kodzie", no: "niesprawdzone", ex: "przykład" })[p[0]] + "</span><span>" + p[1] + "</span></li>").join("");
    return '<section class="scene" id="' + sc.id + '" data-scene="' + sc.id + '"><div class="wrap">' +
      '<div class="scene-copy"><div class="scene-no"><b>' + sc.no + "</b><span>" + sc.name + "</span></div><h2>" + sc.headline + "</h2>" +
      '<ol class="beats">' + beats + "</ol>" +
      '<div class="scene-meta"><p class="needs">' + sc.needs + '</p><ul class="proof">' + proof + "</ul>" +
      '<details class="heads"><summary>Pięć nagłówków, jeden wybrany</summary><ol>' + heads + "</ol></details></div></div>" +
      stageHTML(sc) + "</div></section>";
  }

  /* App Store frame (430 × 932; exported at 3× = 1290 × 2796) */
  function shotHTML(sc) {
    const s = sc.shot;
    const decoSrc = s.deco.indexOf("pose-") === 0 ? "assets/" + s.deco + ".png" : "assets/" + s.deco + ".png";
    return '<div class="shot" data-shot="' + sc.id + '">' +
      '<div class="top"><div class="brand"><img class="wmk" src="' + W + '" alt="Doddy"><span class="lbl">Rekonstrukcja · przykładowa rozmowa</span></div><p class="situ">' + s.situ + "</p><h2>" + (s.h || sc.headline) + '</h2><div class="say">' + s.say + '</div><div class="start">' + ic(s.start[0], 18) + " " + s.start[1] + "</div></div>" +
      '<div class="ph"><div class="phone-wrap" style="--s:.78">' + phoneHTML() + "</div></div>" +
      '<img class="deco" src="' + decoSrc + '" alt=""' + (s.decoStyle ? ' style="' + s.decoStyle + '"' : "") + "></div>";
  }
  function fillShot(root, sc) {
    const screen = root.querySelector(".screen");
    const tap = root.querySelector(".tap");
    const layer = document.createElement("div");
    layer.className = "layer";
    layer.innerHTML = sc.frames[sc.shot.frame]();
    screen.insertBefore(layer, tap);
    applyAt(layer, sc.shot.at);
    const last = sc.steps[sc.steps.length - 1];
    if (sc.shot.frame === last.f) applySet(layer, last.set);
    if (sc.shot.press) root.querySelector(".phone").classList.add("press");
    // sprites stand still on the first frame in a picture
  }

  /* ───────── boot ───────── */
  const params = new URLSearchParams(location.search);
  const shotId = params.get("shot");
  const root = document.getElementById("doddy-story");

  if (shotId) {
    // Export mode: one App Store frame, nothing else.
    document.documentElement.classList.add("shot-mode");
    const sc = SCENES.find(x => x.id === shotId);
    document.body.innerHTML = shotHTML(sc);
    fillShot(document.body.querySelector(".shot"), sc);
    return;
  }

  const scenesHost = document.getElementById("scenes");
  if (!scenesHost) { window.DoddyStory = { SCENES, ic, shotHTML, fillShot }; return; }
  scenesHost.innerHTML = SCENES.map(sceneHTML).join("");

  const players = SCENES.map(sc => {
    const stage = document.querySelector("#" + sc.id + " .stage");
    const p = new Player(sc, stage);
    p.rest();
    stage.querySelector(".replay").addEventListener("click", () => p.play());
    document.querySelectorAll("#" + sc.id + " .beat").forEach(b => b.addEventListener("click", () => {
      const j = +b.getAttribute("data-b");
      const first = sc.steps.findIndex(x => x.b === j);
      if (reduce) { p.stop(); p.show(first, false); return; }
      p.play(first);
    }));
    return p;
  });

  registerSprites(document.body);

  if (!reduce && "IntersectionObserver" in window) {
    const io = new IntersectionObserver(entries => {
      entries.forEach(e => {
        const p = players.find(x => x.stage === e.target);
        if (!p) return;
        if (e.isIntersecting && !p.started) { p.started = true; p.play(); }
      });
    }, { threshold: 0.45 });
    players.forEach(p => io.observe(p.stage));
  }

  window.DoddyStory = { SCENES, players };
})();
