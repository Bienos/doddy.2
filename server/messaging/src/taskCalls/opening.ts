// Every fixed sentence of a task call, in one place (ADR-502). The opening line and the question are
// spoken word for word as the agent's first message; the model never phrases the disclosure.
// Since 13 Nov 2026 (owner: the agent should sound like the person's own assistant, not keep saying "AI";
// decision docs/decisions/2026-11-13-call-agent-sounds-like-an-assistant.md) the disclosure is "wirtualny asystent":
// still said once, first, and never denied when asked; no longer the words "asystent AI".
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
 * "Dzień dobry, tu Doddy, wirtualny asystent Anny. [notice] Dzwonię z krótkim pytaniem, czy mogę zająć chwilkę?"
 * Since 15 Nov 2026 the question itself is not in the opening: the agent asks it word for word once they say yes
 * (owner: "niech kończy «czy mogę zająć chwilkę» – bardziej kulturalne"; decisions
 * docs/decisions/2026-11-15-calls-sound-natural.md and 2026-11-15-call-opening-asks-for-a-moment.md).
 * The disclosure is still the first thing said, and the model never phrases it.
 */
export function openingLine(principalGenitive: string, notice: RecordingNotice): string {
  const parts = [`Dzień dobry, tu Doddy, wirtualny asystent ${principalGenitive}.`];
  if (NOTICE_TEXT[notice]) parts.push(NOTICE_TEXT[notice]);
  parts.push("Dzwonię z krótkim pytaniem, czy mogę zająć chwilkę?");
  return parts.join(" ");
}

/** What Doddy says to anything outside the brief. Never a promise of anything but a call back. */
export const callbackLine = (principalGenitive: string) => `Sprawdzę to u ${principalGenitive} i oddzwonię.`;

/** Twilio's voice says these; the agent is already gone when they play. */
export const GOODBYE = "Przepraszam, muszę już kończyć. Dziękuję i do widzenia.";
export const TECHNICAL_APOLOGY = "Dzień dobry, tu Doddy, wirtualny asystent. Przepraszamy, mamy problem techniczny. Do widzenia.";
export const handoverLine = (principalGenitive: string) => `Chwileczkę, przekazuję rozmowę do ${principalGenitive}.`;

/** To the user, on their own phone, before they join. */
export const takeoverPrompt = (calleeName: string) =>
  `Doddy jest na linii: ${calleeName}. Naciśnij 1, aby przejąć rozmowę.`;
export const TAKEOVER_NOT_TAKEN = "Nie przejęto rozmowy. Doddy rozmawia dalej.";
export const TAKEOVER_TOO_LATE = "Ta rozmowa już się zakończyła.";

/**
 * What Doddy will never do on this call; shown on the card. A booking call may accept exactly the
 * booking on the card (decision 2026-11-12-book-agent), an order call exactly the order on the card
 * (decision 2026-11-12-food-by-phone), and nothing else.
 */
export function forbiddenList(principalGenitive: string, factKinds: readonly FactKind[], bookingSummary?: string, orderSummary?: string): string[] {
  const list = orderSummary
    ? [
      `Zamawia tylko dokładnie to: ${orderSummary}. Innych dań, innego adresu ani wyższej kwoty nie przyjmuje.`,
      "Płatność tylko przy odbiorze. Nie płaci z góry, nie podaje danych karty, kodu BLIK ani konta i nie klika w linki do płatności.",
      "Nie zgadza się na żadne inne warunki i nie zamawia nic więcej.",
    ]
    : bookingSummary
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
  if (!factKinds.includes("address") && !orderSummary) list.push("Nie podaje adresu.");
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
