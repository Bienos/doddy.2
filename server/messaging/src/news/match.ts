import { fold } from "../memorySearch.js";

// Keyword matching for news (On my radar, 10 Nov 2026; decision 2026-11-10-radar-alerts). The owner's
// "kryptowaluty" follow found nothing because a story says "kryptowalut", "kryptowalucie" or "Bitcoina":
// a plain substring test misses Polish endings. This is a small, predictable rule, not a stemmer: words
// are folded (lower case, no diacritics, ł → l) and compared by their shared beginning, more loosely for
// longer words. The same rule is in DoddyCore (`RadarMatch`), and both are tested against
// `schemas/fixtures/radar_match_v1.json`.

/** The words of a text, folded and split on anything that is not a letter or a digit. */
export function words(text: string): string[] {
  return fold(text).split(/[^\p{L}\p{N}]+/u).filter((w) => w.length > 0);
}

function sharedStart(a: string, b: string): number {
  let i = 0;
  while (i < a.length && i < b.length && a[i] === b[i]) i++;
  return i;
}

const VOWEL = /[aeiouy]$/;

/**
 * How many leading letters a story's word must share with a keyword's word. Polish changes the end of
 * a word, more often after a vowel (Tesla → Tesli, kryptowaluty → kryptowalut) than after a consonant
 * (Orlen → Orlenu keeps "orlen"):
 * - up to 4 letters: the whole word (CPK, AI, Musk → Muska);
 * - ending in a vowel: all but the last letter up to 6 letters (tesla → tesli, polska → polski, not polsat),
 *   all but 2 at 7 (ukraina → ukrainie), all but 3 from 8 (kryptowaluty → kryptowalucie, dywidenda → dywidendzie);
 * - ending in a consonant: the whole word up to 6 letters (sport → sportowy, not sporo), all but the last
 *   letter from 7 (bitcoin → bitcoina, kryptowalut → kryptowaluty).
 */
export function lettersNeeded(keyWord: string): number {
  const n = keyWord.length;
  if (n <= 4) return n;
  if (VOWEL.test(keyWord)) return n <= 6 ? n - 1 : n === 7 ? n - 2 : n - 3;
  return n <= 6 ? n : n - 1;
}

/** One folded word of a story against one folded word of a keyword. Up to 3 letters it must be the same word. */
export function wordMatches(storyWord: string, keyWord: string): boolean {
  if (keyWord.length <= 3) return storyWord === keyWord;
  return sharedStart(storyWord, keyWord) >= lettersNeeded(keyWord);
}

/**
 * True when the keyword's words appear one after another in the text, each allowing for its ending
 * ("Elon Musk" matches "Elona Muska"). A keyword shorter than two letters never matches.
 */
export function matchesKeyword(text: string, keyword: string, textWords: string[] = words(text)): boolean {
  const kw = words(keyword);
  if (kw.length === 0 || kw.join("").length < 2) return false;
  outer: for (let i = 0; i + kw.length <= textWords.length; i++) {
    for (let j = 0; j < kw.length; j++) if (!wordMatches(textWords[i + j]!, kw[j]!)) continue outer;
    return true;
  }
  return false;
}

/** The keywords that appear in the text, in the order given. */
export function matchedKeywords(text: string, keywords: readonly string[]): string[] {
  const textWords = words(text);
  return keywords.filter((k) => matchesKeyword(text, k, textWords));
}
