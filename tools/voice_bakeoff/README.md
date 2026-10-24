# Polish voice bake-off (ADR-604 follow-up)

Goal: find out whether a cheaper voice pipeline (own speech-to-text + cheap LLM + text-to-speech, about
0.024–0.034 $/min) sounds and listens well enough in Polish to replace ElevenLabs Agents (0.08 $/min
platform fee). Numbers and sources: `docs/research/2026-10-24/research_costs.md`. Nothing here is run yet.

## What to test
- **Speech-to-text:** ElevenLabs Scribe v2 Realtime (current), Soniox, Deepgram Nova-3 (multilingual), optionally
  OpenAI and Gemini transcription.
- **Text-to-speech:** ElevenLabs v4 Turbo / Flash with Doddy's current voice (control), Cartesia Sonic, Soniox TTS.
  Deepgram's voices have no Polish; skip them.
- **Whole-loop challengers (later, if the parts pass):** OpenAI gpt-realtime-2.1-mini, Gemini Live.

## Steps
1. `phrases_pl.tsv` has 35 phrases in categories: `num` numbers, dates, times, money; `name` Polish names and
   places; `en` English words inside Polish; `cmd` short commands; `long` long sentences; `diac` all Polish
   letters; `emo` tone; `fem` Doddy's own verb gender (he is male: "zapisałem"; a voice that says "zapisałam"
   is wrong for him); `short` one-word answers.
2. **Speech-to-text:** record yourself reading the phrases once on the phone (quiet room, then a café or car
   for the noisy set), keep the WAV files. Send each file to each provider (their own tools or dashboards; keys
   stay in your shell, never in the repo). Save each provider's output as `transcripts_<provider>.tsv`
   (`id<TAB>text`) and run `python3 -I wer.py phrases_pl.tsv transcripts_*.tsv`.
3. **Text-to-speech:** generate every phrase with every provider into `out/<provider>/<id>.mp3`, then
   `python3 -I blind_sheet.py out blind`. Listen to the shuffled files, fill `blind/scores.csv`, open
   `blind/key.json` only afterwards. Have a second Polish speaker score too.
4. Latency: for the best pairs measure the time from end of your sentence to first sound (target 1.2 s or
   less) on the phone's mobile connection.

## Decide
- Speech-to-text: word error rate on `num`, `name` and `en` within 3 points of Scribe, and no provider that
  drops digits or names in the `long` set.
- Text-to-speech: average naturalness and pronunciation at least 4.0 and within 0.3 of the ElevenLabs control,
  with "ship: yes" from both listeners on 80% of phrases.
- If nothing passes, stay on ElevenLabs and use the other cost levers (silence cut-off, caps, shorter answers).
- Do not start building the pipeline before the numbers are in. Also check why the measured cost is half the
  list price (ElevenLabs dashboard), since it changes the saving.
