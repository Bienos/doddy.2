import DoddyCore
import SwiftUI

/// Privacy summary and disclosure rows stay together beside the state they describe.
struct SettingsPrivacySection: View {
    let privacy: PrivacyDefaults
    let summary: String
    let isHeyDoddyOn: Bool
    let isListeningOnOpen: Bool

    var body: some View {
        Section("Privacy") {
            // ADR-310: Face ID when Doddy opens, and after a minute away.
            AppLockToggle()
            // The short version that used to sit at the bottom of Home (ADR-326); it follows
            // Memory on calls as it did there.
            Text(summary)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("settings.privacySummary")
            // iPhone search (ADR-330), off until switched on.
            SpotlightToggle()
            NavigationLink {
                DataFlowView()
            } label: {
                Label("What leaves this iPhone", systemImage: "arrow.up.right.circle")
            }
            .accessibilityIdentifier("settings.dataFlow")
            StatusRow(title: "Account required", value: privacy.accountRequired ? "Yes" : "No")
            // From the same rows as What leaves this iPhone, for the settings right now (ADR-447).
            StatusRow(title: "Network", value: privacy.networkRequestsMade ? DataFlow.networkSummary(.current()) : "None")
            StatusRow(
                title: "Microphone",
                value: !privacy.microphoneUsed ? "Not used"
                    : isHeyDoddyOn ? "While talking, and while \u{201C}Hey Doddy\u{201D} listens for its wake word on this iPhone; turn that off under Hey Doddy"
                    : isListeningOnOpen ? "Only while talking. A conversation starts when you open Doddy; turn that off under Voice"
                    : "Only while talking")
            StatusRow(title: "Analytics and telemetry", value: privacy.analyticsEnabled || privacy.contentTelemetryEnabled ? "On" : "Off (not built)")
            StatusRow(title: "Cloud AI", value: privacy.cloudAIEnabled ? DataFlow.cloudAISummary(.current()) : "Off (not built)")
            StatusRow(title: "Sync", value: privacy.syncText)
            // DataFlow (What leaves this iPhone) restates this paragraph row by row; change both together.
            Text("Your notes stay on this iPhone. During a voice conversation, your voice, the conversation, your saved notes (except ones you mark Private), your list names (a list's items only when Doddy reads or changes it), your personality settings, and (if switched on) your last few conversations and your introduction answers are sent to OpenAI, or ElevenLabs if you switch Home's voice to it, which runs the voice agent. Calendar entries, contact names and birthdays (day and month) or message drafts Doddy uses in a conversation go too. When you ask for weather or facts with ElevenLabs as the voice, it looks them up for Doddy: the place name and coordinates go to Open-Meteo, and search words go to Wikipedia; this app makes no such requests itself. ElevenLabs keeps a recording and transcript of each conversation it runs; how long OpenAI keeps the audio and transcript isn't verified in this build. If a token server is set, starting a conversation also sends your access code to it. If you use Connected Apps or switch on an online-account tool, the app sends what you ask (a date, a search word, or the text of a draft, reply or task you confirm) to your Doddy server, which talks to Google, Microsoft (Outlook), Notion or Todoist through Composio, and the results come back to the app and, during a conversation, to OpenAI, or ElevenLabs if you switch Home's voice to it so Doddy can answer; your saved notes are never sent to that server. If you ask Siri \u{201C}Ask Doddy what I saved\u{201D} (it can be turned off below), Doddy searches on this iPhone and hands the matching note to Siri, Apple's assistant, to read aloud; Siri handles what you say and the answer under your Siri settings. If you turn on \u{201C}Hey Doddy\u{201D}, the microphone listens for the wake word on this iPhone and what it hears isn't kept or sent; Picovoice gets your AccessKey to check it, and the conversation the wake word starts goes to OpenAI, or ElevenLabs if you switch Home's voice to it like any other. If you switch on web search, your search words go the same way to your Doddy server, which looks them up through Monid (a paid search service Doddy's server uses; you don't sign in to it). If you turn on Ask Doddy, typed questions (and, if you allow it, saved notes that match them) go to the Ask Doddy gateway, a separate server, which passes them to OpenAI. If a Doddy messaging server is set and you turn on notifications, texts, phone calls or daily news, it gets an anonymous account token, this iPhone's notification token, your phone number once you confirm it with a code, and the news topics you pick; it sends through Apple and Twilio, runs calls on ElevenLabs, and writes the news with an AI (Anthropic or OpenAI, as the server is set up; Daily news names which) and GNews. Your saved notes go there only if you turn on \u{201C}Let Doddy use my memories on calls\u{201D}. If you search for a place for a reminder, the words you type (and roughly where you are, if Doddy already knows) go to Apple Maps; the place you pick stays on this iPhone, and iOS, not Doddy, notices when you get there. In translator mode the other person's voice goes to OpenAI, or ElevenLabs if you switch Home's voice to it too (listen only hears whoever is near you); started from Translate on Home, your notes, conversations and profile aren't sent, and nothing of it is kept on this iPhone unless you tap Copy or Save within 5 minutes. If you share a list, its name and items go to your iCloud (Apple) and to the people you invite, and their changes come back; a list reminder's place goes there too only if you tap Share this place. If you ask Doddy to convert money, the app downloads the European Central Bank's public exchange-rate file; nothing about you is sent with it. If you switch on Read an email or Read a Notion page, the one email (sender, subject and its text) or page (title and text) you ask about, cut short, comes from your Doddy server and goes to OpenAI, or ElevenLabs if you switch Home's voice to it during that conversation. Text you share to Doddy from another app, to-dos found in a voice memo and your Focus settings stay on this iPhone; the parking widget shows when you parked and your note, never where. If you ask Doddy to remind you when to leave, where your iPhone is and the place you're going go to Apple Maps once, to work out the travel time; neither is kept. If you turn on Show notes in iPhone search, your notes and lists (never private ones) are indexed by iOS on this iPhone. Nothing else is sent anywhere.")
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityIdentifier("settings.privacy")
    }
}
