// Messages by phone (decision docs/decisions/2026-11-27-voice-first-doddy.md, step 4): Doddy calls one person for the
// user and passes on exactly the message the user approved on the card. Every sentence Doddy must say word for word is
// built here, never by the model: the message line, which the result checks Doddy really said, and the card's lines.
import { clean } from "./clean.js";
import { z } from "zod";

/** At most this many characters of message: one breath on the phone. */
export const MESSAGE_MAX = 300;

export const messageSchema = z.string().min(3).max(MESSAGE_MAX * 2).transform(clean).pipe(z.string().min(3).max(MESSAGE_MAX));

/** What a tell call "asks": whether they have a moment for the message. Built here; a model never writes it. */
export const tellQuestion = (principalGenitive: string) => `Mam krótką wiadomość od ${principalGenitive}, mogę przekazać?`;

/** The one sentence that passes the message on, word for word. The result's check looks for it in Doddy's words. */
export const messageLine = (principalGenitive: string, message: string) => {
  const text = message.trim();
  return `Wiadomość od ${principalGenitive}: „${/[.!?…]$/.test(text) ? text : `${text}.`}”`;
};

/** What Doddy says when someone asks not to be called again: only that it is passed on (owner, 9 Nov 2026: notify only). */
export const DO_NOT_CALL_LINE = "Rozumiem, przekażę to. Do widzenia.";
