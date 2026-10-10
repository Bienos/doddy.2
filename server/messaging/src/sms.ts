// Carrier/Twilio default keywords. Matching is on the whole message, case-insensitive.
const OPT_OUT = new Set(["STOP", "STOPALL", "UNSUBSCRIBE", "CANCEL", "END", "QUIT", "REVOKE", "OPTOUT"]);
const OPT_IN = new Set(["START", "YES", "UNSTOP"]);
const HELP = new Set(["HELP", "INFO"]);

export type SmsKeyword = "opt_out" | "opt_in" | "help" | "other";

export function classifySms(body: string): SmsKeyword {
  const word = body.trim().toUpperCase();
  if (OPT_OUT.has(word)) return "opt_out";
  if (OPT_IN.has(word)) return "opt_in";
  if (HELP.has(word)) return "help";
  return "other";
}
