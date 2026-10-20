# Doddy as a personal agent: proposal (21 Oct 2026, not started)

The owner, 21 Oct: "If something is more complicated, you should take some time and be my personal agent. I had this interview, the recording is in Fireflies; you should log in and check what happened, or use the API. Then: can you create a blog post, or a presentation in Google Drive or PowerPoint? You should be able to do that, and do it nicely. Maybe implement 1Password, so you can use their passwords and come through."

This is a proposal for the owner to choose from. Nothing here is built. CLAUDE.md rule 6 makes cloud AI and new actions a milestone of their own.

## What exists today
- **Connected apps through Doddy's server** (`backend/`, ADR-525): Gmail, Google Drive, Google Calendar, Notion, Todoist and Outlook, each signed in once with the provider's own sign-in (OAuth through Composio). Doddy never sees a password. Each tool is a hand-written entry in `backend/src/tools/catalog.ts` with a card for every write (ASK-01).
- **Creating documents:** `create_drive_doc` (a private Google Doc) and `create_notion_page`. No slides, no PowerPoint, no Fireflies.
- **Long tasks:** none. Every tool must answer within one voice turn (60 to 90 s).

## Recommendation: connectors, not passwords
**Don't use 1Password to log in to websites for the user.** Typing a person's saved passwords into sites from a voice agent means Doddy handles every credential the person has, logs in through web pages that change without warning, and trips the sites' bot checks. It also breaks the constitution's rule that model output is a proposal and scoped tools execute. One-time sign-in per app (OAuth, a tap in the conversation) gives the same "Doddy can get in" result, revocably, per app.

1. **More apps, same pattern (small):** add Fireflies (`fireflies` toolkit: list meetings, read a transcript and summary) and Google Slides and Docs writes (create a deck from an outline, a formatted doc). Reads ask by voice; creating a deck or doc shows its card first. Sign-in starts from the card in the conversation, not from Settings (the Settings-detour fix in progress).
2. **Long tasks (medium):** "Doddy, go through yesterday's interview in Fireflies and turn it into a blog post and a 10-slide deck." Doddy says what he'll make and asks once. Doddy's server then runs the job in the background: it reads the transcript, drafts, and builds the doc and deck through the connectors. The Live Activity shows progress, and a notification says "Ready" with links. Nothing is published or shared without a tap. This needs a server-side model call (a Claude model through the API, key only on the server), a job queue (the existing Postgres), and a new ADR on cost limits per user.
3. **Quality ("do it nicely"):** fixed templates for a deck (title, agenda, 3 to 8 content slides, close) and a blog post (headline options, intro, sections, call to action), in Doddy's brand voice (`design/brand-v2.2/`). Doddy offers one revision pass by voice.

## Decisions needed from the owner
- Approve step 1 (Fireflies and Slides connectors) as the next milestone? Yes / no.
- Approve step 2 (background jobs with a server-side model, and a monthly cost cap per user)? Which cap?
- Confirm: no 1Password password-filling (recommended), or keep it as a later, separate review?
