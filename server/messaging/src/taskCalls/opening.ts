// Every fixed sentence of a task call, in one place (ADR-502). The opening line and the question are
// spoken word for word as the agent's first message; the model never phrases the AI disclosure.
// Names are used in the genitive only ("w imieniu Anny", "u Anny", "do Anny"), which the user
// confirms on the brief, so no other case has to be guessed.
import type { RecordingNotice } from "../config.js";
import type { FactKind } from "./brief.js";

export const NOTICE_TEXT: Record<RecordingNotice, string> = {
  off: "",
  nagrywana: "Rozmowa jest nagrywana.",
  zapisywana: "Treść rozmowy jest zapisywana.",
};

/**
 * "Dzień dobry, tu Doddy, asystent AI Anny. [notice] Chciałbym zapytać: …?"
 * Owner, 13 Nov 2026: Doddy introduces himself as the person's own assistant calling for them, and the rest
 * of the call sounds like a person's assistant, not a script. The AI disclosure stays, once, in this fixed
 * first sentence (EU AI Act art. 50(1), constitution DOD-03): "asystent AI Anny". The model never phrases it.
 */
export function openingLine(principalGenitive: string, notice: RecordingNotice, question: string): string {
  const q = /[?？]$/.test(question) ? question : `${question}?`;
  const parts = [`Dzień dobry, tu Doddy, asystent AI ${principalGenitive}.`];
  if (NOTICE_TEXT[notice]) parts.push(NOTICE_TEXT[notice]);
  parts.push(`Chciałbym zapytać: ${q}`);
  return parts.join(" ");
}

/** What Doddy says to anything outside the brief. Never a promise of anything but a call back. */
export const callbackLine = (principalGenitive: string) => `Sprawdzę to u ${principalGenitive} i oddzwonię.`;

/** Twilio's voice says these; the agent is already gone when they play. */
export const GOODBYE = "Przepraszam, muszę już kończyć. Dziękuję i do widzenia.";
export const TECHNICAL_APOLOGY = "Dzień dobry, tu asystent AI Doddy. Przepraszamy, mamy problem techniczny. Do widzenia.";
export const handoverLine = (principalGenitive: string) => `Chwileczkę, przekazuję rozmowę do ${principalGenitive}.`;

/** To the user, on their own phone, before they join. */
export const takeoverPrompt = (calleeName: string) =>
  `Doddy jest na linii: ${calleeName}. Naciśnij 1, aby przejąć rozmowę.`;
export const TAKEOVER_NOT_TAKEN = "Nie przejęto rozmowy. Doddy rozmawia dalej.";
export const TAKEOVER_TOO_LATE = "Ta rozmowa już się zakończyła.";

/**
 * What Doddy will never do on this call; shown on the card. A booking call may accept exactly the
 * booking on the card (decision 2026-11-12-book-agent) and nothing else.
 */
export function forbiddenList(principalGenitive: string, factKinds: readonly FactKind[], bookingSummary?: string): string[] {
  const list = bookingSummary
    ? [
      `Rezerwuje tylko dokładnie to: ${bookingSummary}. Na inny dzień, godzinę czy usługę się nie zgadza.`,
      "Nie płaci, nie wpłaca zaliczki i nie podaje danych karty ani konta.",
      "Nie zgadza się na żadne inne warunki i niczego innego nie zamawia.",
    ]
    : [
      "Nie zgadza się na nic i niczego nie potwierdza w Twoim imieniu.",
      "Nie płaci i nie podaje danych do płatności.",
      "Nie umawia, nie rezerwuje i nie zamawia.",
    ];
  if (!factKinds.includes("pesel")) list.push("Nie podaje numeru PESEL.");
  if (!factKinds.includes("address")) list.push("Nie podaje adresu.");
  list.push("Nie mówi o Tobie nic poza zaznaczonymi faktami.");
  list.push(`Na pytania spoza tej karty odpowiada: „${callbackLine(principalGenitive)}”`);
  return list;
}

const FACT_LABEL: Partial<Record<FactKind, string>> = { pesel: "PESEL", address: "Adres", contact: "Kontakt" };

/** The ticked facts as the agent reads them, one per line. */
export function factLines(facts: readonly { kind: FactKind; text: string }[]): string {
  if (facts.length === 0) return "(brak: nie podawaj żadnych informacji o osobie, w imieniu której dzwonisz)";
  return facts.map((f) => `- ${FACT_LABEL[f.kind] ? `${FACT_LABEL[f.kind]}: ` : ""}${f.text}`).join("\n");
}
