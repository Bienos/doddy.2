// Carrier/Twilio default keywords. Matching is on the whole message, case-insensitive, as Twilio's
// Advanced Opt-Out matches them. POMOC is the Polish help word added in the Messaging Service
// (docs/integrations/PHONE_NUMBER_SETUP.md, step 6); Twilio answers all of these itself.
const OPT_OUT = new Set(["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT", "REVOKE", "OPTOUT"]);
const OPT_IN = new Set(["START", "YES", "UNSTOP"]);
const HELP = new Set(["HELP", "INFO", "POMOC"]);

export type SmsKeyword = "opt_out" | "opt_in" | "help" | "other";

export function classifySms(body: string): SmsKeyword {
  const word = body.trim().toUpperCase();
  if (OPT_OUT.has(word)) return "opt_out";
  if (OPT_IN.has(word)) return "opt_in";
  if (HELP.has(word)) return "help";
  return "other";
}

// How many SMS parts a text takes, as DoddyCore's SMSSegments counts them: the Messaging Service
// has Smart Encoding off, so one character outside GSM-7 sends the whole text as UCS-2.
const GSM_BASIC = new Set(
  "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà");
const GSM_EXTENDED = new Set("^{}\\[~]|€\f");

export function smsSegments(text: string): number {
  const chars = [...text];
  const parts = (units: number, single: number, multi: number) => (units <= single ? 1 : Math.ceil(units / multi));
  if (chars.every((c) => GSM_BASIC.has(c) || GSM_EXTENDED.has(c))) {
    return parts(chars.reduce((n, c) => n + (GSM_EXTENDED.has(c) ? 2 : 1), 0), 160, 153);
  }
  return parts(text.length, 70, 67); // UTF-16 code units, as UCS-2 counts them
}
