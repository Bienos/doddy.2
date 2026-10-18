// What a caller hears when Doddy's server answers without connecting the phone agent (ADR-490).
// Each line says Doddy is an AI (DOD-03), in Polish and then English, and the call ends.
// Nothing here records the call: recording stays off.

const LINES = {
  unknown_caller: {
    pl: "Tu Doddy, asystent AI. Ten numer działa tylko dla właściciela. Do usłyszenia.",
    en: "This is Doddy, an AI assistant. This number only works for its owner. Goodbye.",
  },
  calls_off: {
    pl: "Tu Doddy, asystent AI. Rozmowy telefoniczne są wyłączone w aplikacji Doddy. Do usłyszenia.",
    en: "This is Doddy, an AI assistant. Phone calls are turned off in the Doddy app. Goodbye.",
  },
  not_set_up: {
    pl: "Tu Doddy, asystent AI. Rozmowy telefoniczne nie są jeszcze włączone. Do usłyszenia.",
    en: "This is Doddy, an AI assistant. Phone calls aren't connected yet. Goodbye.",
  },
  cant_talk: {
    pl: "Tu Doddy, asystent AI. Nie mogę teraz rozmawiać. Spróbuj za chwilę. Do usłyszenia.",
    en: "This is Doddy, an AI assistant. I can't talk right now. Please try again in a minute. Goodbye.",
  },
  unavailable: {
    pl: "Tu Doddy, asystent AI. Doddy jest teraz niedostępny. Spróbuj później. Do usłyszenia.",
    en: "This is Doddy, an AI assistant. Doddy isn't available right now. Please try again later. Goodbye.",
  },
} as const;

export type FixedLine = keyof typeof LINES;

export function sayAndHangUp(line: FixedLine): string {
  const { pl, en } = LINES[line];
  return '<?xml version="1.0" encoding="UTF-8"?><Response>'
    + `<Say language="pl-PL" voice="Polly.Ola-Neural">${pl}</Say>`
    + `<Say language="en-US" voice="Polly.Joanna">${en}</Say>`
    + "<Hangup/></Response>";
}

/**
 * The TwiML that connects a call to the phone agent, from ElevenLabs register-call. Its docs don't
 * say whether the body is raw XML or a JSON string, so both are accepted. Anything that isn't a
 * TwiML document, or that would record the call, is refused.
 */
export function connectTwiml(body: string, contentType: string | null): string | undefined {
  let text = body.trim();
  if (contentType?.includes("json")) {
    try {
      const parsed: unknown = JSON.parse(text);
      if (typeof parsed !== "string") return undefined;
      text = parsed.trim();
    } catch {
      return undefined;
    }
  }
  const isTwiml = /^(<\?xml[^>]*\?>\s*)?<Response[\s>/]/.test(text) && /(<\/Response>|<Response\s*\/>)$/.test(text);
  if (!isTwiml || /<Record[\s>/]/i.test(text)) return undefined;
  return text;
}
