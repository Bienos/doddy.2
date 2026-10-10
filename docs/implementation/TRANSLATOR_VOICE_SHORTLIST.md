# Translator: native-voice shortlist (T6, for a listening pass)
Date: 2026-10-10. Status: **reference only. Owner decision (ADR-224): keep Doddy's own voice for both sides, speaking each language natively with correct spelling and accents. None of these voices is used.**

Found with the ElevenLabs voice library search: language, use case "conversational", descriptive "calm". Library voices must be added to the workspace before an agent can use them, and some professional voices are billed differently. Check the price before choosing.

## The constraint to decide around
One ElevenLabs conversation speaks with **one** voice. It is set when the conversation starts (`ttsOverrides.voiceId`, ADR-105) and can't change per line. So "their language in a native voice, mine in Doddy's" is not possible inside one conversation today. The options for the owner:
1. **Keep Doddy's voice for both sides** (what ships). It is multilingual (`eleven_v4_turbo`), with one consistent AI identity (DOD-12).
2. **Home › Translate only:** start with a native voice for *their* language when it is known before the start. The owner then also hears that voice, and Doddy's own voice is gone for that conversation.
3. Wait for per-turn voice switching in the SDK or the agent platform.

## Candidates (listen to the previews in the ElevenLabs library)
| Language | Voice | voice_id | Why on the list |
|---|---|---|---|
| Polish | Paweł – Polski 1 | `T0oFKhodSNDM2GD8c8iA` | Male, "calm and friendly", standard Polish |
| Polish | Adrian | `cwrdX8btCEfA7Nfnw40W` | "Polski spokojny ciepły" |
| Polish | Luiza | `C8ZVSJxcymeT86xT429O` | Female, natural range |
| German | Mira – Conversational Support Agent | `3Ftjjmxq31Rtbgi5smVL` | Female, built for real-time dialogue |
| German | Sebastian – Calm & Authentic | `qVRpsZJDV29g1CIPzssm` | Male, for conversational AI agents |
| German | Piet Convo | `2QhwfRSog8ArO9AfgYMU` | Male, relaxed, unscripted |
| Spanish | Félix Castellanos | `K61wMqaYgfHwUByuyX4U` | Peninsular, calm, made for audio guides |
| Spanish | Valeria | `nfyTTmgO0f6GV9CKrMWL` | Neutral Latin American, female, for voice assistants |
| Spanish | Nestor | `cTZ1Li7htNiwd1cNPgUC` | Latin American, male, conversational |
| French | Cécile M | `DOqLhiOMs8JmafdomNTP` | Female, calm, conversational |
| French | Alexandre | `gP52hjM48hyNoVCbizxO` | Male, Parisian, relaxed |
| French | Arthur | `vhQ8cGSAY3xSxsoFewJ2` | Male, calm and casual |
| Italian | Marco | `2OoHspMHbpIu5oiMaqDy` | Male, conversational, customer care |
| Italian | Aurora | `3LTv5xMEHTJYUIMl1jBR` | Female, clear, supportive |
| Italian | Beatrice | `UnOINkXZ3yK4vVg3Iayj` | Female, warm, assistant use |

Other languages aren't searched yet. Accents differ: Spanish has peninsular and Latin American voices, French has Parisian and African. If option 2 is chosen, pick per country or keep Doddy's voice.

What a listening pass should check: the AI disclosure line spoken in that voice, numbers and prices, a fast exchange, and whether a stranger hears it as an AI ("AI translator" is said first in every voice).
