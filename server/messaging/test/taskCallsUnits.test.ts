// Unit tests for call-case pieces that need no database: TwiML, signatures, agent drift, the answer
// card, and the exact request Twilio receives.
import assert from "node:assert/strict";
import { describe, test } from "node:test";
import { TwilioCallClient } from "../src/providers/taskCalls.js";
import { checkAgentSafety } from "../src/taskCalls/agentSafety.js";
import { isValidElevenLabsSignature, signElevenLabs } from "../src/taskCalls/elevenLabsSignature.js";
import { audit, buildCallResult, findSpan, type Line, type ResultFacts } from "../src/taskCalls/result.js";
import { agentAnswerTwiml, calleeHandoverTwiml, parseAgentTwiml, sayAndHangUp, takeoverPromptTwiml } from "../src/taskCalls/twiml.js";
import { compliantAgent, EL_TWIML } from "./helpers.js";

describe("ElevenLabs TwiML is accepted in one shape only", () => {
  test("the expected shape is rebuilt with live transcription in front and nothing after but Hangup", () => {
    const s = parseAgentTwiml(EL_TWIML);
    assert.ok(s);
    assert.equal(s.url, "wss://api.elevenlabs.io/v1/convai/conversation/twilio?agent_id=agent_task_test");
    assert.deepEqual(s.parameters, [{ name: "conversation_id", value: "conv_live_1" }]);
    const xml = agentAnswerTwiml(s, { transcription: "https://x.test/t?a=1", connectEnded: "https://x.test/c?a=1" });
    assert.match(xml, /^<\?xml version="1.0" encoding="UTF-8"\?><Response><Start><Transcription name="doddy-live" track="both_tracks" languageCode="pl-PL"/);
    assert.match(xml, /<Connect action="https:\/\/x.test\/c\?a=1" method="POST"><Stream url="wss:\/\/api.elevenlabs.io\/v1\/convai\/conversation\/twilio\?agent_id=agent_task_test"><Parameter name="conversation_id" value="conv_live_1"\/><\/Stream><\/Connect><Hangup\/><\/Response>$/);
  });

  test("anything else is refused", () => {
    const bad = [
      "<Response><Say>hi</Say><Connect><Stream url=\"wss://api.elevenlabs.io/x\"/></Connect></Response>",
      "<Response><Connect><Stream url=\"wss://evil.example/x\"/></Connect></Response>",
      "<Response><Connect><Stream url=\"ws://api.elevenlabs.io/x\"/></Connect></Response>",
      "<Response><Connect><Stream url=\"wss://api.elevenlabs.io.evil.example/x\"/></Connect></Response>",
      "<Response><Connect><Stream url=\"wss://api.elevenlabs.io/x\" statusCallback=\"https://evil\"/></Connect></Response>",
      "<Response><Connect><Stream url=\"wss://api.elevenlabs.io/x\"/><Stream url=\"wss://api.elevenlabs.io/y\"/></Connect></Response>",
      "<Response><Dial>+48600100200</Dial></Response>",
      "<Response><Connect><Stream url=\"wss://api.elevenlabs.io/x\"><Parameter name=\"a\" value=\"b\" extra=\"c\"/></Stream></Connect></Response>",
      "not xml <",
    ];
    for (const xml of bad) assert.equal(parseAgentTwiml(xml), undefined, xml);
  });

  test("text is escaped in every document we build", () => {
    const v = { voice: "Polly.Ewa", language: "pl-PL" as const };
    assert.equal(sayAndHangUp("A & <b>", v),
      '<?xml version="1.0" encoding="UTF-8"?><Response><Say language="pl-PL" voice="Polly.Ewa">A &amp; &lt;b&gt;</Say><Hangup/></Response>');
    const handover = calleeHandoverTwiml("Chwileczkę, przekazuję rozmowę do Anny.", v, "doddy-abc", "https://x.test/conf?t=1");
    assert.match(handover, /^<\?xml[^>]*><Response><Stop><Transcription name="doddy-live"\/><\/Stop><Say/);
    assert.match(handover, /<Conference beep="false" startConferenceOnEnter="true" endConferenceOnExit="true" waitUrl=""/);
    assert.match(takeoverPromptTwiml("Naciśnij 1", v, "https://x.test/d?t=1"), /<Gather numDigits="1" timeout="8" action="https:\/\/x.test\/d\?t=1"/);
  });
});

describe("ElevenLabs webhook signature", () => {
  const secret = "s3cret-s3cret-s3cret";
  const body = '{"type":"post_call_transcription","data":{}}';
  const now = Date.parse("2026-10-19T09:00:00Z");

  test("valid, tampered, stale and future signatures", () => {
    const header = signElevenLabs(secret, body, now);
    assert.equal(isValidElevenLabsSignature(secret, header, Buffer.from(body), now), true);
    assert.equal(isValidElevenLabsSignature(secret, header, Buffer.from(body + " "), now), false);
    assert.equal(isValidElevenLabsSignature("other-secret-123456", header, Buffer.from(body), now), false);
    assert.equal(isValidElevenLabsSignature(secret, header, Buffer.from(body), now + 31 * 60_000), false);
    assert.equal(isValidElevenLabsSignature(secret, signElevenLabs(secret, body, now + 10 * 60_000), Buffer.from(body), now), false);
    assert.equal(isValidElevenLabsSignature(secret, undefined, Buffer.from(body), now), false);
    assert.equal(isValidElevenLabsSignature(secret, "t=abc,v0=zz", Buffer.from(body), now), false);
  });
});

describe("agent drift check", () => {
  const mutate = (fn: (a: any) => void) => { const a = compliantAgent() as any; fn(a); return checkAgentSafety(a); };

  test("the agent as specified has no problems", () => {
    assert.deepEqual(checkAgentSafety(compliantAgent()), []);
  });

  test("every unsafe change is caught", () => {
    const cases: [(a: any) => void, string][] = [
      [(a) => { a.conversation_config.agent.prompt.prompt += " Możesz potwierdzać terminy."; }, "prompt_changed"],
      [(a) => { a.conversation_config.agent.first_message = "Dzień dobry!"; }, "first_message_changed"],
      [(a) => { a.conversation_config.agent.language = "en"; }, "language_changed"],
      [(a) => { a.conversation_config.agent.prompt.tool_ids = ["tool_pay"]; }, "tool_ids_present"],
      [(a) => { a.conversation_config.agent.prompt.built_in_tools.transfer_to_number = { type: "system" }; }, "built_in_tool_not_allowed"],
      [(a) => { a.conversation_config.agent.prompt.built_in_tools.play_keypad_touch_tone = { type: "system" }; }, "built_in_tool_not_allowed"],
      [(a) => { a.conversation_config.agent.prompt.knowledge_base = [{ id: "kb" }]; }, "knowledge_base_present"],
      [(a) => { a.conversation_config.agent.prompt.mcp_server_ids = ["m"]; }, "mcp_present"],
      [(a) => { a.conversation_config.tts.agent_output_audio_format = "pcm_16000"; }, "audio_format_changed"],
      [(a) => { a.platform_settings.privacy.record_voice = true; }, "records_voice"],
      [(a) => { a.platform_settings.overrides.conversation_config_override.agent.prompt.prompt = true; }, "overrides_enabled"],
      [(a) => { a.platform_settings.overrides.custom_llm_extra_body = true; }, "overrides_enabled"],
      [(a) => { a.platform_settings.overrides.enable_conversation_initiation_client_data_from_webhook = true; }, "initiation_webhook_enabled"],
      [(a) => { a.platform_settings.auth.enable_auth = false; }, "auth_off"],
      [(a) => { a.conversation_config.agent.disable_first_message_interruptions = false; }, "first_message_interruptible"],
      [(a) => { a.conversation_config.conversation.max_duration_seconds = 240; }, "max_duration_too_short"],
    ];
    for (const [fn, problem] of cases) assert.ok(mutate(fn).includes(problem as never), problem);
    assert.deepEqual(checkAgentSafety(undefined), ["unreadable"]);
  });
});

describe("answer card", () => {
  const opening = "Dzień dobry, mówi Doddy, asystent AI, dzwonię w imieniu Anny. Chciałbym zapytać: Czy laptop z serwisu jest gotowy?";
  const base = (transcript: Line[], over: Partial<ResultFacts> = {}): ResultFacts => ({
    endReason: "completed", answered: true, voiceConnected: true, takenOverAtSecs: null, durationSecs: 40,
    question: "Czy laptop z serwisu jest gotowy?", callbackLine: "Sprawdzę to u Anny i oddzwonię.",
    allowedTexts: [opening, "Numer zlecenia 12345"], transcript, source: "elevenlabs", voicemailToolUsed: false, ...over,
  });
  const d = (text: string): Line => ({ speaker: "doddy", text, atSecs: null });
  const c = (text: string): Line => ({ speaker: "callee", text, atSecs: null });

  test("the quote is the callee's own reply, word for word", () => {
    const r = buildCallResult(base([c("Halo?"), d(opening), c("Tak, laptop jest gotowy, można go odebrać jutro od dziesiątej."), d("Dziękuję bardzo, do widzenia.")]));
    assert.equal(r.outcome, "answered");
    assert.deepEqual(r.quote, { text: "Tak, laptop jest gotowy, można go odebrać jutro od dziesiątej.", line: 2 });
    assert.equal(r.confidence, "high");
    assert.equal(r.nextStep.kind, "set_reminder");
    assert.deepEqual(r.warnings, []);
  });

  test("a model pointer is used only when its words are really in that callee line", () => {
    const t = [d(opening), c("Laptop jest gotowy do odbioru, zapraszamy jutro."), d("Dziękuję, do widzenia.")];
    const good = buildCallResult(base(t, { writer: { answerLine: 1, answerQuote: "laptop jest GOTOWY do odbioru", summary: "Laptop jest gotowy.", nextStep: "Odbierz laptop jutro.", kind: "answered" } }));
    assert.deepEqual(good.quote, { text: "Laptop jest gotowy do odbioru", line: 1 });
    assert.equal(good.summaryBy, "doddy_model");
    const invented = buildCallResult(base(t, { writer: { answerLine: 1, answerQuote: "laptop będzie gotowy w piątek", summary: "x", nextStep: "y", kind: "answered" } }));
    assert.equal(invented.confidence, "low");
    assert.ok(invented.confidenceReasons.includes("model_quote_rejected"));
    const doddysLine = buildCallResult(base(t, { writer: { answerLine: 0, answerQuote: "Dzień dobry", summary: "x", nextStep: "y", kind: "answered" } }));
    assert.ok(doddysLine.confidenceReasons.includes("model_quote_rejected"));
  });

  test("findSpan returns the transcript's own spelling", () => {
    assert.equal(findSpan("Tak,  laptop JEST gotowy.", "laptop jest gotowy"), "laptop JEST gotowy");
    assert.equal(findSpan("Tak.", "nie"), undefined);
  });

  test("hedged answers, callbacks and live-only transcripts lower confidence", () => {
    assert.equal(buildCallResult(base([d(opening), c("Chyba jest gotowy, nie jestem pewna.")])).confidence, "medium");
    const cb = buildCallResult(base([d(opening), c("A jaki jest numer PESEL?"), d("Sprawdzę to u Anny i oddzwonię."), c("Dobrze.")]));
    assert.equal(cb.callbackPromised, true);
    assert.equal(cb.nextStep.kind, "follow_up");
    assert.equal(buildCallResult(base([d(opening), c("Tak, gotowy.")], { source: "twilio_live" })).confidence, "medium");
  });

  test("phone menus, wrong numbers, voicemail and silence are named honestly", () => {
    assert.equal(buildCallResult(base([d(opening), c("Witamy w infolinii. Aby połączyć się z serwisem, naciśnij 1.")])).outcome, "ivr");
    assert.equal(buildCallResult(base([d(opening), c("To chyba pomyłka, to nie jest serwis.")])).outcome, "wrong_number");
    assert.equal(buildCallResult(base([d(opening)], { voicemailToolUsed: true })).outcome, "voicemail");
    assert.equal(buildCallResult(base([d(opening)])).outcome, "no_conversation");
    assert.equal(buildCallResult(base([], { endReason: "no_answer", answered: false, voiceConnected: false })).outcome, "no_answer");
    assert.equal(buildCallResult(base([], { endReason: "busy", answered: false, voiceConnected: false })).nextStep.kind, "retry");
    assert.equal(buildCallResult(base([], { endReason: "twilio_refused", answered: false, voiceConnected: false })).outcome, "not_placed");
    assert.equal(buildCallResult(base([], { endReason: "voice_unavailable" })).outcome, "voice_unavailable");
  });

  test("Doddy's own lines are checked for promises and numbers it wasn't given", () => {
    const w = audit([d(opening), c("Czy potwierdza Pan odbiór?"), d("Tak, potwierdzam."), d("Numer zlecenia to 12345."), d("Mój numer to 600 100 200."), d("PESEL 44051401359")],
      [opening, "Numer zlecenia 12345"]);
    assert.deepEqual(w.map((x) => x.kind), ["possible_commitment", "unlisted_number", "pesel_said"]);
    const r = buildCallResult(base([d(opening), c("Gotowy."), d("Dobrze, zgadzam się.")]));
    assert.equal(r.confidence, "low");
  });
});

describe("Twilio request", () => {
  test("a task call is created with exactly our limits, never recorded", async () => {
    const seen: { url: string; body: URLSearchParams }[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = (async (url: string, init: { body: URLSearchParams }) => {
      seen.push({ url, body: init.body });
      return new Response(JSON.stringify({ sid: "CA" + "1".repeat(32) }), { status: 201 });
    }) as never;
    try {
      const client = new TwilioCallClient("AC" + "a".repeat(32), "token");
      const r = await client.createCall({ to: "+48221234567", from: "+48221112233", url: "https://x/a", fallbackUrl: "https://x/f", statusCallback: "https://x/s", timeLimitSecs: 260, timeoutSecs: 25 });
      assert.deepEqual(r, { kind: "accepted", sid: "CA" + "1".repeat(32) });
      const b = seen[0]!.body;
      assert.equal(b.get("To"), "+48221234567");
      assert.equal(b.get("TimeLimit"), "260");
      assert.equal(b.get("Timeout"), "25");
      assert.equal(b.get("Record"), "false");
      assert.deepEqual(b.getAll("StatusCallbackEvent"), ["initiated", "ringing", "answered", "completed"]);
      assert.equal(b.has("MachineDetection"), false);
    } finally {
      globalThis.fetch = original;
    }
  });
});
