// Words from someone who is not the user (the other side of a call, the sender of a text) are made safe before they
// go into a text from Doddy's number: no link, web address or number to call or pay survives.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { quotableWords, withoutLinks } from "../src/untrustedWords.js";

const MARK = "…";

describe("withoutLinks", () => {
  test("a link with a scheme goes whole, query and fragment included, whatever the scheme", () => {
    for (const link of [
      "https://a.example/x?y=1&z=2#top", "HTTP://A.EXAMPLE/PATH", "ftp://files.example/a.zip", "hxxps://evil.example/login",
      "myapp://open?x=1", "itms-services://?action=download-manifest&url=x", "http://10.0.0.1:8080/admin",
      "https://l.facebook.com/l.php?u=https%3A%2F%2Fevil.example%2F", "https://www.google.com/url?q=https://evil.example&sa=D",
    ]) {
      assert.equal(withoutLinks(`Wejdź na ${link} teraz`), `Wejdź na ${MARK} teraz`, link);
    }
  });

  test("a link a phone makes tappable without a double slash goes too", () => {
    for (const link of ["mailto:biuro@firma.example", "tel:+48600123456", "sms:+48600123456?body=x", "facetime:ktos@example.com", "javascript:doEvil", "data:text/html;base64,AAAA"]) {
      assert.equal(withoutLinks(`Kliknij ${link} teraz`), `Kliknij ${MARK} teraz`, link);
    }
  });

  test("a bare address a phone turns into a link goes, on any ending and with a path, a port or a query", () => {
    for (const address of [
      "www.osteria.pl", "osteria.pl/rezerwacje", "goo.gl/abc", "bit.ly/3xY", "t.co/Ab1", "evil.de", "evil.ru/p", "pizza.top", "x.click",
      "sklep.com.pl/koszyk", "sub.domain.example.org:8080/a?b=c#d", "evil.COM", "evil.com?x=1", "domena-z-myslnikiem.pl", "zażółć.pl", "evil.рф",
      "192.168.0.1/admin", "10.0.0.1:8080",
    ]) {
      assert.equal(withoutLinks(`Zobacz ${address} proszę`), `Zobacz ${MARK} proszę`, address);
    }
    assert.equal(withoutLinks("Zobacz (www.osteria.pl), proszę."), `Zobacz (${MARK}), proszę.`, "the sentence's own punctuation stays");
  });

  test("an e-mail address goes", () => {
    assert.equal(withoutLinks("Napisz na jan.kowalski+rez@firma.pl albo nie"), `Napisz na ${MARK} albo nie`);
  });

  test("tricks that keep a link tappable or readable do not hide it: other dots, invisible characters, wide letters", () => {
    for (const trick of ["evil。com", "evil．com", "ｅｖｉｌ．ｃｏｍ", "evil​.com", "ev­il.com", "evil.c⁠om", "ｈｔｔｐｓ：／／evil.example／x"]) {
      assert.equal(withoutLinks(`Zobacz ${trick} proszę`), `Zobacz ${MARK} proszę`, JSON.stringify(trick));
    }
  });

  test("a link wrapper goes with the link: a markdown label keeps its words, an angle bracket or anchor tag keeps nothing", () => {
    assert.equal(withoutLinks("[Kliknij tutaj](https://evil.example/x) po zniżkę"), "Kliknij tutaj po zniżkę");
    assert.equal(withoutLinks("[evil.example](https://evil.example/x)"), MARK, "a label that is itself an address goes too");
    assert.equal(withoutLinks("Zobacz <https://evil.example/x> teraz"), `Zobacz ${MARK} teraz`);
    assert.equal(withoutLinks('Zobacz <a href="https://evil.example/x">tutaj</a> teraz'), "Zobacz tutaj teraz");
  });

  test("the mark is the caller's", () => {
    assert.equal(withoutLinks("Wejdź na www.a.pl i https://b.example", "[link pominięty]"), "Wejdź na [link pominięty] i [link pominięty]");
  });

  test("ordinary Polish and English text is left exactly as it is", () => {
    for (const plain of [
      "Tak, o 19 jest stolik. Proszę przyjść o 18.30, cena 12.5 zł, data 12.11.2026, godz. 9, ul. Długa 5, np. jutro, tj. w piątek, itd.",
      "Yes, we have a table for two at 7 p.m. tonight. Price: 45.50 PLN, e.g. a set menu. Thanks!",
      "Dzwoń 22 123 45, wersja 2.1, pokój 3.14.", "Co? Tak... Nie wiem... Może.", "",
    ]) {
      assert.equal(withoutLinks(plain), plain, plain);
    }
  });

  test("only the link changes: other characters a link finder reads as something else stay as written", () => {
    assert.equal(withoutLinks("Pokój 50 m², cena 3 000 zł… ﬁrma „Pod Różą” – ｅｖｉｌ．ｃｏｍ – tak jest."), "Pokój 50 m², cena 3 000 zł… ﬁrma „Pod Różą” – … – tak jest.");
  });

  test("hostile input takes time in proportion to its length, never more", () => {
    for (const shape of ["a".repeat(200_000), "a.".repeat(100_000), "a@".repeat(100_000), "a-".repeat(100_000), "1.1.1.".repeat(40_000), "http://" + "a/".repeat(100_000)]) {
      const started = performance.now();
      withoutLinks(shape);
      quotableWords(shape);
      assert.ok(performance.now() - started < 3000, `${shape.slice(0, 12)}… took ${Math.round(performance.now() - started)} ms`);
    }
  });
});

describe("quotableWords", () => {
  test("links, addresses and long numbers become …, and the spaces left are closed", () => {
    assert.equal(
      quotableWords("Tak, o 19 jest stolik, proszę potwierdzić na https://osteria-due.example/rez?id=7 albo www.osteria.pl, mail rezerwacje@osteria.pl, tel. 600 123 456, kod 4821937."),
      "Tak, o 19 jest stolik, proszę potwierdzić na … albo …, mail …, tel. …, kod ….");
    assert.equal(quotableWords("  Zadzwoń   +48 600-123-456   "), "Zadzwoń …");
  });

  test("a place's words are not changed when there is nothing to remove", () => {
    assert.equal(quotableWords("Tak, mamy wolny stolik o 19."), "Tak, mamy wolny stolik o 19.");
    assert.equal(quotableWords("Zamknięte od 12.11.2026, otwarte o 18:00."), "Zamknięte od 12.11.2026, otwarte o 18:00.");
  });

  test("a number written with other digits or wide characters is a number too", () => {
    assert.equal(quotableWords("tel. ６００ １２３ ４５６"), "tel. …");
  });
});
