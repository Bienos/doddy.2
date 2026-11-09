/** A synthetic Polish text of exactly `n` Unicode scalars (diacritics throughout, no emoji): nobody's real message. */
export function polish(n: number): string {
  const base = "Zażółć gęślą jaźń. Jutro w Warszawie będzie słonecznie i ciepło, weź lekką kurtkę. ";
  let out = "";
  while ([...out].length < n) out += base;
  return [...out].slice(0, n).join("");
}
