# Doddy in CarPlay: plan and entitlement request (ADR-317)

Status: **plan only. No CarPlay code is in the repo, and nothing here has been sent to Apple.**
Sending the request is an owner action and needs the paid developer account.

## Which CarPlay category

Apple added a **voice-based conversational apps** category to the CarPlay Developer Guide on
9 February 2026. Apps can request it from iOS 26.4. This is the only category that fits
Doddy: it is a voice conversation, not navigation, audio, messaging, parking payment or a driving
task.

What we know from public reporting (still to check against Apple's own guide before sending):

- The app has to show a voice control screen (`CPVoiceControlTemplate`). It may add action
  buttons, but it must not show text or pictures for the driver to read.
- Apple reviews every request, the same way it does for navigation and audio apps.
- A third-party page gives the entitlement key as `com.apple.developer.carplay-voice-based-conversation`.
  Apple's documentation doesn't confirm this yet. **Check the key in Apple's guide before adding
  it to any entitlements file.**

Sources: [MacRumors, 18 Feb 2026](https://macrumors.com/2026/02/18/ios-26-4-carplay-support),
[AppleInsider](https://appleinsider.com/articles/26/02/18/ai-agents-are-coming-to-carplay-but-theyre-not-getting-the-keys),
[iGeeksBlog](https://www.igeeksblog.com/ios-26-4-carplay-chatgpt-claude-gemini-support/).

## What Doddy would do in the car (proposal)

The same ElevenLabs conversation as on the iPhone, with a **car profile** of tools:

| Allowed in the car | Why |
|---|---|
| Search saved notes ("what's the gate code?") | Read-only. The answer is spoken, never shown. |
| Read calendar, upcoming birthdays, weather, currency, sums | Read-only. |
| "Where did I park?" (ADR-301) | Read-only. Maps is opened by the driver, not by Doddy. |
| Save a note | Local and reversible (Undo on the iPhone). Needs a spoken "yes" to the read-back. |
| Add to a Doddy list | Local and reversible, with the same spoken confirmation. |

| Not in the car | Why |
|---|---|
| Calendar/Reminders changes and deletes, alarms, email drafts, Todoist, plans | Today these need a tap on an exact card (Constitution V1: approval bound to the payload). The driver must not be looking at a screen for it. |
| Private notes (ADR-310) | Already never given to the voice agent. |
| Translator, web search reading long results | Too much to listen to while driving. |

**Owner decision (2026-10-11): yes.** A spoken "yes" after Doddy reads the exact note or list item
back is enough approval for those two local, undoable saves. Nothing that leaves the iPhone, and
nothing else that changes something, is allowed in the car.

## Work, once the entitlement is granted

1. Add the entitlement (with the confirmed key) through an opt-in setting, like the App Group
   (`DODDY_CARPLAY_ENTITLEMENTS`), so a free team can still build.
2. Add a CarPlay scene (`CPTemplateApplicationSceneDelegate`) with one `CPVoiceControlTemplate`.
   It has states for Listening, Thinking, Speaking and Couldn't connect, plus one End action.
3. Add a car tool profile in DoddyCore (`ToolProfile.car`). It is an allow-list that
   `VoiceToolRequest` routing checks, and the agent gets a short car line in its instructions.
   It needs tests like the translator's routing tests (ADR-215).
4. Spoken confirmation for the two local writes: read back exactly what will be saved, then
   accept only "yes"/"tak". Anything else is a no. It is logged in Activity like a tap.
5. Test in the CarPlay Simulator (Xcode, Additional Tools) and then in a real car. Neither can be
   done in this Linux environment.

## Entitlement request text (draft for the owner to send)

> **App:** Doddy (bundle ID set by the owner)
> **Category:** Voice-based conversational app
>
> Doddy is a personal memory assistant you talk to. In CarPlay it is voice only, on the voice
> control screen. You ask what you saved ("what's the gate code at my mum's?"), what's in your
> calendar today, or where you parked, and Doddy answers out loud from what is on your iPhone.
> You can also ask it to save a short note or add an item to a list. Doddy reads the note back
> and saves it only after you say "yes", and you can undo it later on the iPhone.
>
> In the car Doddy shows no text, notes or pictures, and nothing to scroll or read. It can't
> change the calendar, send messages or email, or take any action outside the iPhone while
> driving; those stay on the iPhone, behind a confirmation tap. The conversation uses the same
> voice service as the iPhone app, and the driver can end it at any time with one button or
> by voice.

## Risks

- The entitlement may be refused, or Apple may limit which tools are allowed.
- Speech recognition in a noisy car can mishear "yes". That is why spoken approval covers only
  undoable local saves.
- The voice provider's latency over a phone connection in a moving car hasn't been measured.
